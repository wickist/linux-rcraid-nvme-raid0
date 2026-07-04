#!/bin/bash
# DKMS post-remove hook for rcraid.
# Refresh initramfs after the module disappears from /lib/modules.
set -e

KVER="${kernelver:-$(uname -r)}"

if command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u -k "$KVER" || true
elif command -v dracut >/dev/null 2>&1; then
    dracut --force --kver "$KVER" || true
fi

exit 0
