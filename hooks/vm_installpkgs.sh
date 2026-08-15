# In-guest install script for debian (piped into the guest sh by build.py
# with ANYVM_PKGS prepended; runs under set -e).
#
# Every package this builder installs (tree, rsync, sshfs, nfs-common) lives
# in Debian "main", so unlike ubuntu-builder there is no universe component
# to enable. The apt indexes are still refreshed first: the cloud image's
# pre-baked /var/lib/apt/lists is a point-in-time snapshot of the release it
# was built from, and once a point release rolls the pinned Packages hashes
# no longer resolve, which surfaces as a 404 mid-install rather than as a
# clear error.
#
# APT::Update::Post-Invoke-Success="" skips the post-update apt hooks
# (the command-not-found database rebuild in particular): they burn tens
# of minutes of CPU on TCG-emulated guests and the build does not need them.
export DEBIAN_FRONTEND=noninteractive
apt-get update -o APT::Update::Post-Invoke-Success=""
apt-get install -y $ANYVM_PKGS
