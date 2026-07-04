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

# Prepare a file once, then run all read tests against it. Read tests
# against an empty/nonexistent file produce meaningless or unstable
# results — fio ends up creating the file lazily and the first read
# pass is contaminated by allocation cost.
PREPARE_FILE="${MOUNT}/fio-prepare"
PREPARE_SIZE=${PREPARE_SIZE:-16G}

prepare_file() {
    echo "[prepare] writing ${PREPARE_SIZE} to ${PREPARE_FILE}"
    fio --name=prepare --filename="${PREPARE_FILE}" \
        --rw=write --bs=4M --size="${PREPARE_SIZE}" \
        --numjobs=4 --iodepth=32 \
        --ioengine=libaio --direct=1 \
        --group_reporting --end_fsync=1 \
        2>&1 | awk '/WRITE:/{print "   "$0}'
    sync
    echo 3 > /proc/sys/vm/drop_caches
}

# Helper for a single benchmark run
run() {
    local name="$1" rw="$2" bs="$3" filename="$4"
    echo "[$name] rw=$rw bs=$bs"
    fio --name="$name" --filename="$filename" \
        --rw="$rw" --bs="$bs" --size=4G --numjobs=4 --iodepth=64 \
        --runtime=30 --time_based --group_reporting \
        --ioengine=libaio --direct=1 \
        2>&1 | awk '/READ:|WRITE:/{print "   "$0}'
    sync
    echo ""
}

echo "==> Mountpoint: $MOUNT"
echo "==> Profile:   numjobs=4 iodepth=64 ioengine=libaio"
echo "==> Time:      $(date -Iseconds)"
echo ""

# Clean leftovers, then prepare the shared read target.
rm -f "${MOUNT}"/fio-* 2>/dev/null || true
sync; echo 3 > /proc/sys/vm/drop_caches
sleep 2
prepare_file
sleep 1

# Reads use the prepared file; writes use fresh per-test files.
run "seq-read-1M"   read       1M "${PREPARE_FILE}"
run "seq-read-4M"   read       4M "${PREPARE_FILE}"
run "rand-read-4K"  randread   4K "${PREPARE_FILE}"

# Writes create their own files.
run "seq-write-1M"  write      1M "${MOUNT}/fio-write-1M"
run "seq-write-4M"  write      4M "${MOUNT}/fio-write-4M"
run "rand-write-4K" randwrite  4K "${MOUNT}/fio-write-rand4K"

# Cleanup
rm -f "${MOUNT}"/fio-* 2>/dev/null || true

echo "writeback errors in dmesg: $(dmesg | grep -c 'writeback error')"
echo "(0 = clean)"
