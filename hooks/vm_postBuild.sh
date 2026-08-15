# in-guest postBuild hook (piped to the guest's sh over SSH by build.py).
#
# Keep everything tolerant: build.py runs this over the remote shell with the
# remote shell exiting non-zero on any unhandled error, and one apt hiccup
# should not abort the whole build.
#
# IMPORTANT: do NOT run `apt-get update` here. On a TCG aarch64 / riscv64 /
# ppc64le guest the post-fetch dpkg trigger phase (man-db rebuild, icon
# caches, etc.) silently chews tens of minutes of CPU on a 2-core GHA
# runner, which blocks the SSH session and looks like the build has hung.
# The refresh happens once, later, in hooks/vm_installpkgs.sh.

export DEBIAN_FRONTEND=noninteractive

echo "=================== debian postBuild ===="

# Make sure sshd survives the reboot that build.py does right after this
# hook. Debian has shipped the unit as ssh.service throughout, but newer
# releases socket-activate it via ssh.socket; enable whichever exists.
echo "--- enabling ssh ---"
systemctl enable ssh.service 2>/dev/null || systemctl enable ssh 2>/dev/null || true

# --- kill the background apt auto-update machinery ----------------------
# Debian cloud images ship apt-daily.timer / apt-daily-upgrade.timer, which
# fire within a couple of minutes of every boot and take the dpkg frontend
# lock. A short-lived VM is handed to the user the moment sshd answers, so
# the user's very first command races them:
#
#   E: Could not get lock /var/lib/dpkg/lock-frontend.
#      It is held by process 989 (apt-get)
#
# apt then exits 100 and the job fails. Nothing in a disposable CI VM
# benefits from background upgrades -- they only mutate the system
# underneath the job -- so switch them off permanently.
#
# Order matters: stop anything already running (a mask does not stop a live
# unit), then disable, then mask so a later package upgrade cannot quietly
# re-enable the units. This block must stay AHEAD of every apt-get in this
# hook, and it protects the VM_PRE_INSTALL_PKGS install build.py runs after
# the reboot as well. unattended-upgrades is not installed on a stock Debian
# cloud image; naming it here is harmless and covers a customized base.
echo "--- disabling apt auto-update timers/services ---"
_apt_auto_units="apt-daily.timer apt-daily-upgrade.timer apt-daily.service
apt-daily-upgrade.service unattended-upgrades.service"
systemctl stop $_apt_auto_units 2>/dev/null || true
systemctl disable apt-daily.timer apt-daily-upgrade.timer \
    unattended-upgrades.service 2>/dev/null || true
systemctl mask $_apt_auto_units 2>/dev/null || true

# Belt and braces, and the part that survives a systemd-unit reshuffle: with
# every APT::Periodic interval at 0 the periodic work is a no-op even if a
# unit comes back.
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'APTAUTOEOF'
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::Unattended-Upgrade "0";
APT::Periodic::AutocleanInterval "0";
APTAUTOEOF

# Make apt-get WAIT for the dpkg lock instead of dying on it. apt ships a
# 120s default for its own `apt` frontend but leaves `apt-get` -- the one
# every script and CI job actually calls -- at 0, i.e. fail immediately:
#
#   $ apt-config dump | grep -i lock::timeout
#   binary::apt::DPkg::Lock::Timeout "120";
#
# That asymmetry is the whole reason `apt-get install` reports the lock as a
# hard error. Setting it globally makes apt-get behave like apt. This is the
# safety net for anything that grabs the lock that we did NOT disable above
# (a user's own background job, a cloud-init module still finishing), so
# keep it even though the auto-update units are masked. Supported since apt
# 2.0; the oldest release built here is bookworm with apt 2.6.
cat > /etc/apt/apt.conf.d/99anyvm-lock-timeout <<'APTLOCKEOF'
DPkg::Lock::Timeout "120";
APTLOCKEOF

# Wait out an upgrade that was already mid-flight when we stopped it, so the
# apt-get calls below (and build.py's install step) find the lock free.
_n=0
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 && [ $_n -lt 60 ]; do
    [ $_n -eq 0 ] && echo "--- waiting for the dpkg lock to be released ---"
    _n=$((_n + 1))
    sleep 5
done

# NOTE: do NOT run "cloud-init clean" here. build.py reboots right after
# this hook, and a clean makes cloud-init treat the next boot as a new
# instance, which (via ssh_deletekeys) regenerates the SSH host keys. The
# host key for the VM's IP then changes mid-build and the next "ssh"
# fails with "REMOTE HOST IDENTIFICATION HAS CHANGED".

passwd -d root

echo "debian postBuild done."

exit 0
