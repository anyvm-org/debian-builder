#!/bin/bash
# host-side prepareImage hook (runs in main process env after _prep_vhd_disk
# materialized "${VM_OS_NAME}.qcow2" but BEFORE the VM is started).
#
# Debian cloud images ship with NO console password and NO ssh key, so there
# is no way to log in on first boot. Bake root SSH access straight into the
# qcow2 with virt-customize, so once the VM boots we can just ssh in via the
# slirp hostfwd port (see host_enablessh.sh). Avoids a cloud-init seed disk.

set -e

# build.py writes the working image under build/ (VM_WORK_QCOW); fall back to
# the repo-root name for a standalone hook run.
_qcow="${VM_WORK_QCOW:-${VM_OS_NAME}.qcow2}"

echo "Preparing ${_qcow} with virt-customize"

# Generate the build's SSH keypair now so we can inject its public key into
# the image. build.py would otherwise create the same key later; reuse it.
if [ ! -e "$HOME/.ssh/id_rsa" ]; then
  ssh-keygen -f "$HOME/.ssh/id_rsa" -q -N ""
fi
_pub="$HOME/.ssh/id_rsa.pub"

# --- generate the guest's SSH HOST keys here ---------------------------------
# Debian's cloud images ship with NO host keys in /etc/ssh -- they are stripped
# at image build time and regenerated on first boot by cloud-init's ssh module.
# We pin datasource_list to [NoCloud, None] below and supply no seed, so on
# release 12 cloud-init never runs and the keys are never created. sshd then
# refuses to start at all:
#
#     sshd: no hostkeys available -- exiting.
#     ssh.service: Start request repeated too quickly.
#
# Nothing listens on 22, the slirp forward has no target, and the build waits
# out its entire ssh-probe budget against a guest that booted perfectly. That
# is how release 12's first CI run burned 2 h 40 m. (Release 13 escaped it
# because its cloud-init did run.)
#
# Host keys are ordinary files with no architecture in them, so generating
# them on the host and uploading works for the aarch64 / ppc64le / riscv64
# images too -- unlike `ssh-keygen -A`, which would have to run inside the
# guest and cannot cross-arch.
#
# The keys are baked into the published image, so every VM booted from one
# release shares them. That is the same bargain every other builder here makes
# (the image is public and build.py connects with StrictHostKeyChecking=no),
# and these are disposable CI guests on localhost -- but it is a deliberate
# choice, not an oversight. A fresh set is generated per build.
_hkdir="$(mktemp -d)"
for _t in rsa ecdsa ed25519; do
  ssh-keygen -q -t "$_t" -N "" -C "anyvm-${VM_OS_NAME}-${VM_RELEASE}" \
             -f "$_hkdir/ssh_host_${_t}_key"
done
echo "Generated host keys: $(ls "$_hkdir" | tr '\n' ' ')"

# libguestfs on a GitHub-hosted runner needs the direct backend.
export LIBGUESTFS_BACKEND=direct
if ! command -v virt-customize >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y libguestfs-tools
fi
# Make the host kernel readable for the libguestfs appliance (harmless if it
# is already readable / not present).
sudo chmod 0644 /boot/vmlinuz-* 2>/dev/null || true

_pw="${VM_ROOT_PASSWORD:-anyvm.org}"

# Everything below is FILESYSTEM-level so the SAME command also works when
# we customize an aarch64 image on this x86 runner. We deliberately avoid
# --run-command, which has to execute a binary INSIDE the guest and fails
# cross-arch with "host cpu (x86_64) and guest arch (aarch64) are not
# compatible". --no-network disables the libguestfs appliance network (newer
# libguestfs defaults it on and tries to start "passt", which fails on the
# GitHub-hosted runner: "libguestfs error: passt exited with status 1").
#
# Access is granted by the injected root key. We append PermitRootLogin etc.
# to the main sshd_config: sshd takes the FIRST value it obtains for a
# keyword, so an appended line only wins if nothing earlier sets it. Nothing
# does here -- Debian's stock sshd_config leaves PermitRootLogin commented
# out, and the cloud-init drop-in the image ships under sshd_config.d sets
# PasswordAuthentication but not PermitRootLogin. Even if that ever changed,
# the build would still get in: the injected key works under the
# prohibit-password default too. sshd is already enabled on cloud images, so
# no "systemctl enable" is needed here.

# --- bake in networking; do NOT rely on cloud-init for it -------------------
# Debian 12 and 13 get their network configuration from different places, and
# only 13 survives without cloud-init:
#
#   13 (trixie)   systemd-networkd, configured in the image itself
#   12 (bookworm) cloud-init writes /etc/network/interfaces.d/50-cloud-init
#
# We pin datasource_list to [NoCloud, None] above and supply no seed, so
# cloud-init lands on the None datasource. On 13 that is harmless -- networkd
# brings the link up anyway. On 12 it means NO network configuration at all:
# the guest boots perfectly to a login prompt with no DHCP lease, slirp's
# hostfwd has nothing to forward to, and the build sits in the ssh probe until
# its ceiling. That is exactly how the first CI run of release 12 burned 2 h
# 40 m while its serial log showed a healthy multi-user.target the whole time.
#
# So configure networking here, the same way the ssh key is configured here:
# a lowest-priority networkd unit plus the enable symlink. The 99- prefix
# means any config the image already ships matches first, so this only fills a
# gap and cannot override 13's own setup. Match both naming schemes -- cloud
# images often boot with net.ifnames=0, giving eth0 rather than enp0s3.
#
# The symlink is created directly rather than with `systemctl enable`:
# --run-command executes inside the guest and fails cross-arch, and this hook
# also prepares aarch64/ppc64le/riscv64 images on an x86 runner.
_netcfg='[Match]
Name=en*

[Network]
DHCP=yes

[DHCPv4]
UseDomains=yes
'

sudo -E virt-customize --no-network -a "${_qcow}" \
  --root-password "password:$_pw" \
  --ssh-inject "root:file:$_pub" \
  --append-line '/etc/ssh/sshd_config:PermitRootLogin yes' \
  --append-line '/etc/ssh/sshd_config:PubkeyAuthentication yes' \
  --append-line '/etc/ssh/sshd_config:AcceptEnv *' \
  --write '/etc/cloud/cloud.cfg.d/99-anyvm-ds.cfg:datasource_list: [ NoCloud, None ]' \
  --mkdir /etc/systemd/network \
  --write "/etc/systemd/network/99-anyvm-dhcp.network:$_netcfg" \
  --mkdir /etc/systemd/system/multi-user.target.wants \
  --link '/lib/systemd/system/systemd-networkd.service:/etc/systemd/system/multi-user.target.wants/systemd-networkd.service' \
  --upload "$_hkdir/ssh_host_rsa_key:/etc/ssh/ssh_host_rsa_key" \
  --upload "$_hkdir/ssh_host_rsa_key.pub:/etc/ssh/ssh_host_rsa_key.pub" \
  --upload "$_hkdir/ssh_host_ecdsa_key:/etc/ssh/ssh_host_ecdsa_key" \
  --upload "$_hkdir/ssh_host_ecdsa_key.pub:/etc/ssh/ssh_host_ecdsa_key.pub" \
  --upload "$_hkdir/ssh_host_ed25519_key:/etc/ssh/ssh_host_ed25519_key" \
  --upload "$_hkdir/ssh_host_ed25519_key.pub:/etc/ssh/ssh_host_ed25519_key.pub" \
  --chmod '0600:/etc/ssh/ssh_host_rsa_key' \
  --chmod '0600:/etc/ssh/ssh_host_ecdsa_key' \
  --chmod '0600:/etc/ssh/ssh_host_ed25519_key' \
  --chmod '0644:/etc/ssh/ssh_host_rsa_key.pub' \
  --chmod '0644:/etc/ssh/ssh_host_ecdsa_key.pub' \
  --chmod '0644:/etc/ssh/ssh_host_ed25519_key.pub'

# Make sure qemu can read+write the image on the following steps.
sudo chmod 0666 "${_qcow}" 2>/dev/null || true

echo "Image prepared:"
ls -lh "${_qcow}"
