#!/bin/bash
# DKMS post-install hook for rcraid.
# Runs after the module is built and copied into /lib/modules/$kernel.
#
# Responsibilities:
#   - Refresh initramfs so rcraid is available early at boot if the
#     admin chooses to boot from the BIOS RAID array.
#   - Install a default modprobe.d snippet with the module parameters
#     we validated (rc_adapter_count + tag_q_depth).
set -e

KVER="${kernelver:-$(uname -r)}"

# Refresh initramfs (best-effort — initramfs-tools may not be present on RHEL/Fedora).
if command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u -k "$KVER" || true
elif command -v dracut >/dev/null 2>&1; then
    dracut --force --kver "$KVER" || true
fi

# Install a default modprobe.d snippet if one is not already present.
# The user can edit rc_adapter_count to match their disk count.
if [ ! -f /etc/modprobe.d/rcraid.conf ]; then
    cat > /etc/modprobe.d/rcraid.conf <<'EOF'
# Managed by rcraid DKMS post_install. Edit rc_adapter_count to match
# the number of NVMe SSDs in the BIOS RAID array (excludes any non-RAID
# NVMe such as the boot disk).
options rcraid rc_adapter_count=4 tag_q_depth=64
EOF
fi

exit 0
