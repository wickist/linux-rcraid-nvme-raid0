#!/bin/bash
# run-benchmarks.sh
# Runs the validated fio benchmark suite against a mountpoint.
# Reproduces the numbers in results/fio-summary.md.
#
# USAGE:
#   sudo bash scripts/run-benchmarks.sh /mnt/raid0
#
# Optimal profile (validated — see docs/06-benchmarks.md):
#   numjobs=4, iodepth=64, ioengine=libaio, bs=1M
# Higher job counts HURT throughput on mdadm (stripe lock contention).

set -e

MOUNT="${1:-/mnt/raid0}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root (fio --direct=1 needs it, plus drop_caches): sudo bash $0"
    exit 1
fi

if [ ! -d "$MOUNT" ]; then
    echo "ERROR: mountpoint not found: $MOUNT"
    exit 1
fi

command -v fio >/dev/null 2>&1 || {
    echo "fio not installed — install it:"
    echo "  Ubuntu/Debian: sudo apt install fio"
    echo "  Fedora/RHEL:   sudo dnf install fio"
    exit 1
}

echo "==> Mountpoint: $MOUNT"
echo "==> Profile: numjobs=4 iodepth=64 ioengine=libaio"
echo "==> Time:    $(date -Iseconds)"
echo ""

# Helper
run() {
    local name="$1" rw="$2" bs="$3"
    echo "[$name] rw=$rw bs=$bs"
    fio --name="$name" --filename="${MOUNT}/fio-${name}" \
        --rw="$rw" --bs="$bs" --size=4G --numjobs=4 --iodepth=64 \
        --runtime=30 --time_based --group_reporting \
        --ioengine=libaio --direct=1 \
        2>&1 | awk '/READ:|WRITE:/{print "   "$0}'
    rm -f "${MOUNT}/fio-${name}"*
    sync
    echo ""
}

# Clean any leftovers
rm -f "${MOUNT}"/fio-* 2>/dev/null || true
sync; echo 3 > /proc/sys/vm/drop_caches
sleep 2

run "seq-read-1M"  read       1M
run "seq-write-1M" write      1M
run "seq-read-4M"  read       4M
run "seq-write-4M" write      4M
run "rand-read-4K" randread   4K
run "rand-write-4K" randwrite 4K

echo "writeback errors in dmesg: $(dmesg | grep -c 'writeback error')"
echo "(0 = clean)"
