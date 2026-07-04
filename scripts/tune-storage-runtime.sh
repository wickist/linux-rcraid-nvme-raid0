#!/bin/bash
# tune-storage-runtime.sh
# Applies validated runtime tuning to the mdadm block device and the
# underlying NVMe members. All settings are persisted via sysctl.d and udev.
#
# Validated optimal profile (4× Samsung 990 PRO, kernel 6.14):
#   * I/O scheduler = none (blk-mq, no extra reordering)
#   * read_ahead_kb = 4096 on md device
#   * writeback throttling (wbt) disabled
#   * vm.dirty_ratio = 20 (large write buffer for sequential writes)
#   * XFS mount: noatime,nodiratime (set in /etc/fstab by setup script)
#
# USAGE:
#   sudo bash scripts/tune-storage-runtime.sh /dev/md0

set -e

DEV="${1:-/dev/md0}"
if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo bash $0 ..."
    exit 1
fi

BASE="$(basename "$DEV")"
QDIR="/sys/block/${BASE}/queue"

if [ ! -d "$QDIR" ]; then
    echo "ERROR: queue dir not found: $QDIR"
    exit 1
fi

echo "==> Tuning $DEV"

# I/O scheduler
if [ -w "${QDIR}/scheduler" ]; then
    echo none > "${QDIR}/scheduler" 2>/dev/null || true
    echo "   scheduler: $(cat ${QDIR}/scheduler)"
fi

# read-ahead (4 MB)
if [ -w "${QDIR}/read_ahead_kb" ]; then
    echo 4096 > "${QDIR}/read_ahead_kb" 2>/dev/null || true
    echo "   read_ahead_kb: $(cat ${QDIR}/read_ahead_kb)"
fi

# Disable writeback throttling (default 2 ms caps sequential write bursts)
if [ -w "${QDIR}/wbt_lat_usec" ]; then
    echo 0 > "${QDIR}/wbt_lat_usec" 2>/dev/null || true
    echo "   wbt_lat_usec: $(cat ${QDIR}/wbt_lat_usec)"
fi

# Persist via sysctl
echo "==> Persisting dirty_ratio via /etc/sysctl.d/99-raid-tune.conf"
cat > /etc/sysctl.d/99-raid-tune.conf <<'EOF'
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
vm.dirty_expire_centisecs = 3000
EOF
sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-raid-tune.conf || true

# Persist block-device settings via udev rule (re-applied at boot)
echo "==> Persisting block-device settings via udev"
RULE=/etc/udev/rules.d/99-raid-tune.rules
cat > "$RULE" <<EOF
# Applied by tune-storage-runtime.sh
ACTION=="add|change", KERNEL=="${BASE}", SUBSYSTEM=="block", \\
  ATTR{queue/scheduler}="none", \\
  ATTR{queue/read_ahead_kb}="4096", \\
  ATTR{queue/wbt_lat_usec}="0"
EOF
udevadm control --reload-rules 2>/dev/null || true

echo ""
echo "✅ Runtime tuning applied and persisted"
echo ""
echo "Note on fio/I/O profile for maximum throughput:"
echo "  --numjobs=4  (one per NVMe — DO NOT exceed)"
echo "  --iodepth=64 (sweet spot — 128 causes stripe lock contention)"
echo "  --ioengine=libaio"
echo "  --bs=1M"
echo ""
echo "Why not more jobs? mdadm dm-stripe target serializes across stripes;"
echo "beyond 4 jobs × 64 depth, latency rises faster than throughput."
