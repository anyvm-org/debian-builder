# Image-slimming finalize. Runs as the LAST in-guest hook, after postBuild
# and the VM_PRE_INSTALL_PKGS apt installs.
#
# NOTE: do NOT remove /var/lib/apt/lists here. hooks/vm_installpkgs.sh has
# just refreshed them, and shipping usable indexes lets users (and the
# vmactions VM_PREPARE step) `apt-get install` without an `apt-get update`,
# which is painfully slow on the TCG-emulated arches. Only the package
# archive cache is dropped.
#
# There is deliberately no dracut block here (ubuntu-builder carries one for
# 26.04+). Debian 12 and 13 both build their initrd with initramfs-tools,
# so there is no dracut in the guest to configure.

echo "=== finalize: image cleanup ==="

# Drop cached .deb archives fetched by the build's installs.
apt-get clean || true

# TRIM every mounted filesystem: the build disk runs with discard=unmap,
# so freed ext4 blocks (package churn, kernel leftovers) become holes in
# the qcow2 and the export-time sparsify reclaims them.
fstrim -av || true

df -h || true
echo "=== finalize: image cleanup done ==="
