#!/bin/bash
# install-rcraid-dkms.sh
# Installs the patched rcraid driver as a DKMS module on the running kernel.
#
# PREREQUISITES:
#   1. rcblob.x86_64 must be present under dkms/rcraid/src/
#      (run scripts/fetch-and-extract-rcblob.sh first)
#   2. linux-headers-$(uname -r), build-essential, dkms installed
#
# USAGE:
#   sudo bash scripts/install-rcraid-dkms.sh

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo bash $0"
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DKMS_SRC="${REPO_ROOT}/dkms/rcraid"
INSTALL_SRC="/usr/src/rcraid-9.3.0-6.14"

# Sanity checks
if [ ! -f "${DKMS_SRC}/src/rcblob.x86_64" ]; then
    echo "ERROR: dkms/rcraid/src/rcblob.x86_64 missing."
    echo "       Run: bash scripts/fetch-and-extract-rcblob.sh vendor/<archive>.zip"
    exit 1
fi

command -v dkms >/dev/null 2>&1 || {
    echo "ERROR: dkms not installed. Install it first:"
    echo "  Ubuntu/Debian: sudo apt install dkms"
    echo "  Fedora/RHEL:   sudo dnf install dkms"
    exit 1
}

KVER="$(uname -r)"
if [ ! -d "/lib/modules/${KVER}/build" ]; then
    echo "ERROR: kernel headers for ${KVER} not installed."
    echo "  Ubuntu: sudo apt install linux-headers-${KVER}"
    exit 1
fi

echo "==> Kernel: $KVER"
echo "==> Staging DKMS source at ${INSTALL_SRC}"

# Clean any previous install
dkms remove rcraid/9.3.0-6.14 --all >/dev/null 2>&1 || true
rm -rf "$INSTALL_SRC"

# Stage the source tree (excludes build artifacts via .gitignore-style cleanup)
mkdir -p "$INSTALL_SRC/src"
cp "$DKMS_SRC"/src/*.c "$DKMS_SRC"/src/*.h "$INSTALL_SRC/src/" 2>/dev/null || true
cp "$DKMS_SRC"/src/Makefile "$INSTALL_SRC/src/"
cp "$DKMS_SRC"/src/common_shell "$INSTALL_SRC/src/" 2>/dev/null || true
cp "$DKMS_SRC"/src/rcblob.x86_64 "$INSTALL_SRC/src/"
cp "$DKMS_SRC"/dkms.conf "$INSTALL_SRC/"
cp "$DKMS_SRC"/post_install.sh "$DKMS_SRC"/post_remove.sh "$INSTALL_SRC/"
chmod +x "$INSTALL_SRC"/post_*.sh
chown -R root:root "$INSTALL_SRC"

# Add / build / install
echo "==> dkms add"
dkms add rcraid/9.3.0-6.14

echo "==> dkms build"
dkms build rcraid/9.3.0-6.14 -k "$KVER"

echo "==> dkms install"
dkms install rcraid/9.3.0-6.14 -k "$KVER"

# Default module parameters
if [ ! -f /etc/modprobe.d/rcraid.conf ]; then
    echo "==> Writing /etc/modprobe.d/rcraid.conf"
    mkdir -p /etc/modprobe.d
    cat > /etc/modprobe.d/rcraid.conf <<'EOF'
# rc_adapter_count = number of RAID-member NVMe SSDs (excludes the boot NVMe).
# tag_q_depth      = per-LUN queue depth (default 16 is too low for NVMe).
options rcraid rc_adapter_count=4 tag_q_depth=64
EOF
else
    echo "==> /etc/modprobe.d/rcraid.conf already exists — leaving it alone"
fi

echo ""
echo "✅ rcraid installed via DKMS for kernel $KVER"
echo ""
echo "dkms status:"
dkms status rcraid/9.3.0-6.14
echo ""
echo "Next: load the module"
echo "  sudo modprobe rcraid"
echo "Or reboot. If you have non-RAID NVMe (e.g. a boot disk), you'll also"
echo "need the systemd bind/unbind helper — see docs/02-rcraid-kernel-port.md"
