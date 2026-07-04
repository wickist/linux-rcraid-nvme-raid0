#!/bin/bash
# verify-blob.sh
# Verifies that the rcblob.x86_64 file under dkms/rcraid/src/ matches the
# expected SHA-256 from AMD's raid_linux_driver_930_00276 package.
#
# USAGE:
#   bash scripts/verify-blob.sh [path/to/rcblob.x86_64]

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BLOB="${1:-${REPO_ROOT}/dkms/rcraid/src/rcblob.x86_64}"
MANIFEST="${REPO_ROOT}/checksums/amd-raid-9.3.0.sha256"

if [ ! -f "$BLOB" ]; then
    echo "ERROR: blob not found: $BLOB"
    echo "       Run scripts/fetch-and-extract-rcblob.sh first."
    exit 1
fi

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: manifest not found: $MANIFEST"
    exit 1
fi

echo "==> Verifying: $BLOB"
echo "    Size: $(stat -c%s "$BLOB") bytes"

ACTUAL="$(sha256sum "$BLOB" | awk '{print $1}')"
EXPECTED="$(grep rcblob "$MANIFEST" | awk '{print $1}')"

if [ "$ACTUAL" = "$EXPECTED" ]; then
    echo "✅ SHA-256 matches"
    echo "   $ACTUAL"
    exit 0
else
    echo "❌ SHA-256 MISMATCH"
    echo "   Expected: $EXPECTED"
    echo "   Actual:   $ACTUAL"
    echo ""
    echo "   This usually means you extracted from a different AMD driver version"
    echo "   than 9.3.0 (raid_linux_driver_930_00276). The patches in this repo"
    echo "   were validated against 9.3.0 — building with a different blob may fail."
    exit 1
fi
