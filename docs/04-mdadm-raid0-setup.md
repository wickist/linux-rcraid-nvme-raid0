# 04 — mdadm RAID0 setup (recommended for max throughput)

If you don't specifically need BIOS-visible RAID (e.g. you're not
dual-booting Windows), `mdadm` is the better choice. It preserves the
native NVMe `blk-mq` multi-queue path, which the AMD `rcraid` driver
funnels through a single SCSI host queue.

On the same 4× Samsung 990 PRO hardware, **mdadm RAID0 reaches 27.7 GB/s
sequential read vs rcraid's 16.6 GB/s** — see [08-results.md](08-results.md).

This document walks through the setup. The whole flow is automated by
`scripts/setup-mdadm-raid0.sh`.

## Prerequisites

* Member NVMe SSDs visible to the in-tree `nvme` driver (i.e. **not**
  captured by rcraid). If you previously had rcraid loaded, `sudo rmmod
  rcraid` first — the SSDs will fall back to `nvme`.
* `mdadm` installed: `sudo apt install mdadm` (Ubuntu/Debian).
* A separate boot disk that is **NOT** a member of the array. We used a
  KIOXIA Exceria Pro 2TB on a CPU-attached NVMe slot.

## Identify member devices

```bash
$ lsblk -o NAME,SIZE,MODEL,TRAN | grep -v loop
NAME    SIZE MODEL                  TRAN
nvme1n1 931G Samsung SSD 990 PRO   nvme
nvme2n1 931G Samsung SSD 990 PRO   nvme
nvme3n1 931G Samsung SSD 990 PRO   nvme
nvme4n1 931G Samsung SSD 990 PRO   nvme
nvme0n1 1.8T KIOXIA-EXCERIA PRO SSD nvme   ← boot, NOT a member
```

Always double-check against `nvme list` and `lsblk` before going further.
The setup script refuses `/dev/nvme0n1` by default as a safety net.

## Create the array

The helper script does everything in one shot:

```bash
sudo bash scripts/setup-mdadm-raid0.sh /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/nvme4n1
```

Under the hood it runs:

```bash
# Wipe any stale md / BIOS RAID metadata on the members
for d in "$@"; do
    mdadm --zero-superblock --force "$d"
    wipefs -a "$d"
done

# Create the array — chunk=512K is the validated optimum
mdadm --create /dev/md0 --level=0 --raid-devices=4 --chunk=512 \
    /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/nvme4n1

# Persist for boot-time auto-assembly
mdadm --detail --brief /dev/md0 >> /etc/mdadm/mdadm.conf
update-initramfs -u
```

## Format XFS with stripe geometry

XFS should be told about the mdadm stripe so its block allocations line
up with chunk boundaries:

```bash
mkfs.xfs -f -L raid0 -d su=512k,sw=4 /dev/md0
```

* `su=512k` — striping unit, equal to the mdadm chunk size.
* `sw=4` — striping width, equal to the number of data disks.

`xfs_info /dev/md0` should then report `sunit=128 swidth=512 blks`
(4 KiB blocks: 512K / 4K = 128).

## Mount persistently

```bash
mkdir -p /mnt/raid0
mount /dev/md0 /mnt/raid0

UUID=$(blkid -s UUID -o value /dev/md0)
echo "UUID=$UUID /mnt/raid0 xfs defaults,noatime,nodiratime 0 2" >> /etc/fstab
```

## Runtime tuning

Apply the validated runtime tuning (scheduler, read-ahead, dirty_ratio,
writeback throttling off) — automated by `tune-storage-runtime.sh`:

```bash
sudo bash scripts/tune-storage-runtime.sh /dev/md0
```

See [05-xfs-optimization.md](05-xfs-optimization.md) for what each knob
does and why.

## Verification

```bash
# Array healthy
cat /proc/mdstat
mdadm --detail /dev/md0 | head

# Filesystem mounted
df -h /mnt/raid0

# Benchmark
sudo bash scripts/run-benchmarks.sh /mnt/raid0
```

## Removing the array (if you ever want to)

```bash
umount /mnt/raid0
mdadm --stop /dev/md0
mdadm --remove /dev/md0

# Wipe md superblocks from members
for d in /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/nvme4n1; do
    mdadm --zero-superblock "$d"
    wipefs -a "$d"
done

# Remove from /etc/mdadm/mdadm.conf and /etc/fstab manually
```

## What about BIOS RAID metadata?

`mdadm --zero-superblock` targets Linux md metadata. `wipefs -a` removes
filesystem and other well-known signatures. **AMD BIOS RAID metadata
behavior may vary** — on some firmware versions `wipefs` will spot and
erase the AMD signature, on others it won't. If you need to preserve
BIOS RAID for dual-boot, **do not run the destructive mdadm setup script
without a full backup**, and verify in your motherboard's RAID utility
afterward.

To definitively remove BIOS RAID metadata, use `dmraid -r -E` or delete
the array from the motherboard's RAID BIOS.

Continue with [05-xfs-optimization.md](05-xfs-optimization.md).
