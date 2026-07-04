#!/bin/bash
# prepare-rcraid-source.sh
#
# Extracts AMD's rcraid driver source from the official AMD RAID driver
# archive, drops it into dkms/rcraid/src/, then applies this repo's
# kernel-6.14 compatibility patch on top.
#
# WHY THIS EXISTS:
#   This repository does NOT redistribute AMD's source files or binary
#   blob — both are governed by AMD's EULA. Users must obtain the AMD
#   RAID driver package themselves. This script extracts the AMD-owned
#   files locally and layers our patches on top.
#
# PREREQUISITES:
#   1. Download raid_linux_driver_930_00276.zip from AMD:
#      https://www.amd.com/en/support/downloads/drivers.html/chipsets/swrx8/wrx80.html
#   2. Place it under vendor/ in your clone of this repo.
#
# USAGE:
#   bash scripts/prepare-rcraid-source.sh [path/to/raid_linux_driver_*.zip]
#   bash scripts/prepare-rcraid-source.sh vendor/               # auto-detect

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_SRC="${REPO_ROOT}/dkms/rcraid/src"
PATCH="${REPO_ROOT}/patches/kernel-6.14/rcraid-6.14-combined.patch"

# --- Locate the AMD archive ---------------------------------------------
ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ] || [ -d "$ARCHIVE" ]; then
    AUTO="$(ls "${ARCHIVE:-${REPO_ROOT}/vendor/}"raid_linux_driver_*.zip 2>/dev/null | head -1)"
    if [ -z "$AUTO" ]; then
        echo "ERROR: no AMD RAID driver archive found."
        echo "       Download raid_linux_driver_930_00276.zip from AMD.com,"
        echo "       place it under vendor/, then re-run:"
        echo "         bash $0 vendor/raid_linux_driver_930_00276.zip"
        exit 1
    fi
    ARCHIVE="$AUTO"
fi

if [ ! -f "$ARCHIVE" ]; then
    echo "ERROR: archive not found: $ARCHIVE"
    exit 1
fi

if [ ! -f "$PATCH" ]; then
    echo "ERROR: patch file missing: $PATCH"
    exit 1
fi

echo "==> AMD driver archive: $ARCHIVE"
echo "==> Target src dir:     $DEST_SRC"

# --- Extract AMD source files -------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -o -q "$ARCHIVE" -d "$WORK"

# AMD's package layout has a space in the path: "Ubuntu 20.04.02/..."
AMD_SRC="$(find "$WORK" -type d -name src -path '*driver_sdk*' | head -1)"
if [ -z "$AMD_SRC" ] || [ ! -f "${AMD_SRC}/rc_init.c" ]; then
    echo "ERROR: could not find driver_sdk/src/ inside $ARCHIVE"
    echo "       Expected path: */driver_sdk/src/rc_init.c"
    echo "       Available top-level dirs:"
    find "$WORK" -maxdepth 3 -type d | head -10
    exit 1
fi

echo "==> Found AMD source at: $(echo "$AMD_SRC" | sed "s|$WORK/||")"

# Wipe destination and copy AMD files in (blob included — local only,
# .gitignore prevents it from being committed).
rm -rf "$DEST_SRC"
mkdir -p "$DEST_SRC"
cp -a "${AMD_SRC}/." "$DEST_SRC/"
rm -f "$DEST_SRC"/*.o "$DEST_SRC"/.*.cmd 2>/dev/null || true

echo "==> Extracted files:"
ls "$DEST_SRC" | sed 's/^/    /'

# --- Apply the kernel-6.14 patch ----------------------------------------
echo "==> Applying patch: $PATCH"
cd "$DEST_SRC"
if patch -p1 --dry-run < "$PATCH" >/dev/null 2>&1; then
    patch -p1 < "$PATCH"
    echo ">>> Patch applied cleanly."
elif patch -p0 --dry-run < "$PATCH" >/dev/null 2>&1; then
    patch -p0 < "$PATCH"
    echo ">>> Patch applied cleanly (p0)."
else
    echo "WARNING: dry-run did not match p1 or p0 cleanly."
    echo "         Attempting p1 anyway."
    patch -p1 < "$PATCH" || {
        echo "ERROR: patch did not apply. You may need to apply it manually."
        exit 1
    }
fi

# --- Verify blob is present ---------------------------------------------
if [ ! -f "$DEST_SRC/rcblob.x86_64" ]; then
    echo ""
    echo "WARNING: rcblob.x86_64 not found in extracted source."
    echo "         The build will fail at link time without it."
fi

echo ""
echo "✅ Source prepared at: $DEST_SRC"
echo ""
echo "Next steps:"
echo "  bash scripts/verify-blob.sh                     # verify blob SHA-256"
echo "  sudo bash scripts/install-rcraid-dkms.sh        # DKMS install"
