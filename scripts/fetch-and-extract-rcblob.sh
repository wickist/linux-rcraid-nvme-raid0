#!/bin/bash
# fetch-and-extract-rcblob.sh
#
# Extracts the proprietary rcblob.x86_64 binary blob from an AMD RAID
# driver archive the user has already downloaded from AMD's website.
#
# WHY THIS EXISTS:
#   This repository does NOT redistribute AMD's proprietary binary. Users
#   must obtain the original AMD RAID driver package directly from AMD and
#   place it under vendor/ themselves. This script simply extracts the
#   blob and drops it where the DKMS source tree expects it.
#
# WHERE TO GET THE AMD DRIVER:
#   https://www.amd.com/en/support/downloads/drivers.html/chipsets/swrx8/wrx80.html
#   Look for: "Linux x86 64-bit Driver" (raid_linux_driver_930_00276.zip)
#
# USAGE:
#   bash scripts/fetch-and-extract-rcblob.sh vendor/raid_linux_driver_930_00276.zip
#   bash scripts/fetch-and-extract-rcblob.sh vendor/            # auto-detect zip in vendor/

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${REPO_ROOT}/dkms/rcraid/src/rcblob.x86_64"

# Locate the AMD archive.
ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ] || [ -d "$ARCHIVE" ]; then
    # Auto-detect inside a vendor/ directory.
    AUTO="$(ls "${ARCHIVE:-vendor/}"raid_linux_driver_*.zip 2>/dev/null | head -1)"
    if [ -z "$AUTO" ]; then
        echo "ERROR: no AMD RAID driver archive found."
        echo "       Download it from AMD.com and place it under vendor/"
        echo "       Then: bash $0 vendor/<archive>.zip"
        exit 1
    fi
    ARCHIVE="$AUTO"
fi

if [ ! -f "$ARCHIVE" ]; then
    echo "ERROR: archive not found: $ARCHIVE"
    exit 1
fi

echo "==> AMD driver archive: $ARCHIVE"

# Extract to a temp dir, search for the blob.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -o -q "$ARCHIVE" -d "$WORK"

# Search for rcblob.x86_64 — AMD's package layout varies by version.
BLOB="$(find "$WORK" -type f -name rcblob.x86_64 -size +1M | head -1)"
if [ -z "$BLOB" ]; then
    echo "ERROR: rcblob.x86_64 not found inside $ARCHIVE"
    echo "       Available files:"
    find "$WORK" -type f | head -20
    exit 1
fi

echo "==> Found: $(echo "$BLOB" | sed "s|$WORK/||")"
echo "==> Size: $(stat -c%s "$BLOB") bytes"

# Install into the DKMS src tree.
mkdir -p "$(dirname "$DEST")"
cp -f "$BLOB" "$DEST"
echo "==> Installed: $DEST"
echo ""
echo "Next: verify the blob"
echo "  bash scripts/verify-blob.sh $DEST"
