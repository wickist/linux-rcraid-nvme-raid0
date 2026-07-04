#!/bin/bash
# setup-mdadm-raid0.sh
# Creates an mdadm RAID0 array from N NVMe SSDs, formats XFS with proper
# stripe geometry, and mounts it persistently.
#
# This is the RECOMMENDED path for maximum throughput. mdadm preserves
# native NVMe blk-mq multi-queue, which the AMD rcraid driver (single SCSI
# host queue) cannot do.
#
# USAGE:
#   sudo bash scripts/setup-mdadm-raid0.sh /dev/nvme1n1 /dev/nvme2n1 ...
#
# IMPORTANT: This is DESTRUCTIVE on the listed devices. Verify the device
# names carefully — the script will refuse to operate on /dev/nvme0n1
# (common boot-disk name) unless you pass --i-know-nvme0n1-is-not-boot.

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo bash $0 ..."
    exit 1
fi

if [ "$#" -lt 2 ]; then
    echo "Usage: sudo bash $0 <dev1> <dev2> [dev3] [dev4] ..."
    echo "  e.g. sudo bash $0 /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/nvme4n1"
    exit 1
fi

DEVS=("$@")
MOUNT=/mnt/raid0
CHUNK=${CHUNK:-512}     # KB — mdadm default, validated optimal for NVMe
FORCE_NVME0=0
if [ "${1:-}" = "--i-know-nvme0n1-is-not-boot" ]; then
    FORCE_NVME0=1
    shift
    DEVS=("$@")
fi

# Safety: refuse /dev/nvme0n1 (typical boot disk) unless overridden
for d in "${DEVS[@]}"; do
    if [ "$d" = "/dev/nvme0n1" ] && [ $FORCE_NVME0 -eq 0 ]; then
        echo "REFUSING: /dev/nvme0n1 is typically the boot disk."
        echo "  If you really mean it, pass --i-know-nvme0n1-is-not-boot first."
        exit 1
    fi
done

# Sanity: devices must exist and be NVMe block devices
for d in "${DEVS[@]}"; do
    if [ ! -b "$d" ]; then
        echo "ERROR: not a block device: $d"
        exit 1
    fi
done

ND=${#DEVS[@]}
echo "==> About to create mdadm RAID0 across $ND devices:"
echo ""
echo "Device details:"
lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINTS "${DEVS[@]}" 2>/dev/null || \
    lsblk -o NAME,SIZE,MODEL "${DEVS[@]}" 2>/dev/null
echo ""

# Destructive confirmation: typing YES is required.
# Bypass with CONFIRM_DESTROY=YES for non-interactive runs.
if [ "${CONFIRM_DESTROY:-}" != "YES" ]; then
    read -r -p "WARNING: This will DESTROY all data on: ${DEVS[*]}. Type YES to continue: " ans
    if [ "$ans" != "YES" ]; then
        echo "Aborted."
        exit 1
    fi
fi

echo "==> Proceeding."
echo "==> Chunk size: ${CHUNK}K"

# Zero out any existing md/BIOS RAID metadata on member devices
echo "==> Wiping existing RAID superblocks / signatures on members..."
for d in "${DEVS[@]}"; do
    mdadm --zero-superblock --force "$d" 2>/dev/null || true
    wipefs -a "$d" 2>/dev/null || true
done

# Create the array
echo "==> mdadm --create /dev/md0"
mdadm --create /dev/md0 --verbose --level=0 --raid-devices=$ND \
    --chunk=$CHUNK "${DEVS[@]}"
sleep 2

# Persist the array configuration so it reassembles at boot
echo "==> Updating /etc/mdadm/mdadm.conf"
mkdir -p /etc/mdadm
{
    echo ""
    echo "# Added by setup-mdadm-raid0.sh ($(date -Iseconds))"
    echo "DEVICE ${DEVS[*]}"
    mdadm --detail --brief /dev/md0
} >> /etc/mdadm/mdadm.conf

# Update initramfs so the array auto-assembles before rootfs is mounted
echo "==> Refreshing initramfs"
if command -v update-initramfs >/dev/null 2>&1; then
    update-initramfs -u
elif command -v dracut >/dev/null 2>&1; then
    dracut --force
fi

# Compute XFS stripe geometry from chunk size and disk count
# su = chunk, sw = ND  (in XFS "blocks" of 4K, so su = chunk/4)
SU_BYTES=$((CHUNK * 1024))
SW=$ND

echo "==> Formatting XFS (su=${CHUNK}k sw=${SW})"
mkfs.xfs -f -L raid0 -d su=${CHUNK}k,sw=${SW} /dev/md0

echo "==> Mounting at $MOUNT"
mkdir -p "$MOUNT"
mount /dev/md0 "$MOUNT"

# Persist in fstab by UUID
UUID=$(blkid -s UUID -o value /dev/md0)
FSTAB_LINE="UUID=${UUID} ${MOUNT} xfs defaults,noatime,nodiratime 0 2"
if ! grep -q "$UUID" /etc/fstab; then
    echo "==> Adding to /etc/fstab"
    echo "$FSTAB_LINE" >> /etc/fstab
fi

echo ""
echo "✅ mdadm RAID0 ready"
echo ""
echo "Array detail:"
mdadm --detail /dev/md0 | awk '/Raid Level|Array Size|Total Devices|State|Chunk/{print "   "$0}'
echo ""
echo "Filesystem:"
df -h "$MOUNT"
echo ""
echo "fstab entry:"
grep "$UUID" /etc/fstab
echo ""
echo "Next steps:"
echo "  sudo bash scripts/tune-storage-runtime.sh /dev/md0"
echo "  sudo bash scripts/run-benchmarks.sh $MOUNT"
