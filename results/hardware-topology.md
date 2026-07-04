# Hardware topology reference

The complete hardware/software stack the results in this repo were
measured against. If you're reporting a benchmark discrepancy in an
issue, please copy this template and fill it in for your system.

## CPU & platform

```
$ lscpu | grep -E 'Model name|^CPU\(s\):|Architecture'
Architecture:           x86_64
CPU(s):                 24
Model name:             AMD Ryzen Threadripper PRO 3945WX 12-Cores

$ uname -r
6.14.0-37-generic

$ grep -E 'GRUB_CMDLINE_LINUX_DEFAULT' /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash pci=noaer pcie_aspm=off amd_iommu=off"
```

`amd_iommu=off` is **required for the rcraid path** — the AMD-Vi IOMMU
rejects the firmware mailbox DMA writes. The mdadm path works with or
without it.

## Motherboard

```
$ cat /sys/class/dmi/id/board_vendor
ASUSTeK COMPUTER INC.
$ cat /sys/class/dmi/id/board_name
Pro WS WRX80E-SAGE SE WIFI
```

BIOS RAID mode was enabled in the chipset (the array `Array 02` was
visible in the BIOS RAIDXpert2 utility) for the rcraid-path measurements,
and **disabled** (chipset in AHCI mode) for the mdadm-path measurements.

## PCIe topology (4 Samsung 990 PRO + KIOXIA)

```
$ lspci -nn | grep -i 'non-volatile'
02:00.0 ... [AMD] RAID Bottom Device [1022:b000]   ← Samsung 990 PRO #1
03:00.0 ... [AMD] RAID Bottom Device [1022:b000]   ← Samsung 990 PRO #2
04:00.0 ... [AMD] RAID Bottom Device [1022:b000]   ← Samsung 990 PRO #3
05:00.0 ... [AMD] RAID Bottom Device [1022:b000]   ← Samsung 990 PRO #4
2c:00.0 ... [AMD] RAID Bottom Device [1022:b000]   ← KIOXIA (boot)
```

The 4 Samsungs sit on the ASUS Hyper M.2 x16 Gen4 carrier in slot
`PCIEX16_7`. BIOS is set to `x4x4x4x4` bifurcation.

```
$ sudo lspci -vv -s 02:00.0 | grep -E 'LnkCap:|LnkSta:'
LnkCap: Port #0, Speed 16GT/s, Width x4
LnkSta: Speed 16GT/s, Width x4
$ sudo lspci -vv -s 21:00.0 | grep -E 'LnkCap:|LnkSta:'   # Hyper M.2 upstream
LnkCap: Port #0, Speed 16GT/s, Width x8
LnkSta: Speed 16GT/s, Width x8
```

Each Samsung negotiates Gen4 x4 (~8 GB/s). The Hyper M.2 card's upstream
link to the chipset is Gen4 x8.

## NVMe namespace layout

```
$ nvme list
Node       Generic    SN            Model                       Namespace
/dev/nvme0n1 /dev/ng0n1  15HB3182KR1P  KIOXIA-EXCERIA PRO SSD     0x1   ← boot
/dev/nvme1n1 /dev/ng1n1  S6Z1NJ0W...  Samsung SSD 990 PRO 1TB    0x1   ← RAID member
/dev/nvme2n1 /dev/ng2n1  S6Z1NJ0W...  Samsung SSD 990 PRO 1TB    0x1   ← RAID member
/dev/nvme3n1 /dev/ng3n1  S6Z1NU0X...  Samsung SSD 990 PRO 1TB    0x1   ← RAID member
/dev/nvme4n1 /dev/ng4n1  S6Z1NU0X...  Samsung SSD 990 PRO 1TB    0x1   ← RAID member
```

## Memory

```
$ free -h
                total        used        free      shared  buff/cache   available
Mem:            125Gi        41Gi       118Gi       1.2Gi       2.1Gi        125Gi
```

Single NUMA node (Threadripper Pro 3945WX is monolithic-die):
```
$ numactl --hardware
available: 1 nodes (0)
node 0 cpus: 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23
```

## Kernel module state (mdadm path)

```
$ lsmod | grep -E 'nvme|raid'
nvme               61440  5
nvme_core         225280  7 nvme
md_mod             ...

$ cat /proc/mdstat
md0 : active raid0 nvme4n1[3] nvme3n1[2] nvme2n1[1] nvme1n1[0]
      3906521088 blocks super 1.2 512k chunks
```

## Block layer state (after tune-storage-runtime.sh)

```
$ cat /sys/block/md0/queue/scheduler
[none] mq-deadline

$ cat /sys/block/md0/queue/read_ahead_kb
4096

$ cat /sys/block/md0/queue/wbt_lat_usec
0

$ sysctl vm.dirty_ratio vm.dirty_background_ratio
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
```

## Filesystem

```
$ xfs_info /mnt/raid0
meta-data=/dev/md0   isize=512    agcount=32, agsize=30519680 blks
data     =           bsize=4096   blocks=976629760
         =           sunit=128    swidth=512 blks     ← 512K stripe unit
```

## How to reproduce

1. Clone this repo.
2. (Optional, rcraid path only) Drop `raid_linux_driver_930_00276.zip`
   under `vendor/` and run `scripts/fetch-and-extract-rcblob.sh`.
3. Pick your path:
   * **mdadm:** `sudo bash scripts/setup-mdadm-raid0.sh /dev/nvme{1..4}n1`
     then `sudo bash scripts/tune-storage-runtime.sh /dev/md0`.
   * **rcraid:** `sudo bash scripts/install-rcraid-dkms.sh`, then the
     systemd unbind helper described in
     [../docs/07-troubleshooting.md](../docs/07-troubleshooting.md).
4. `sudo bash scripts/run-benchmarks.sh /mnt/raid0`.

If your numbers diverge from [fio-summary.md](fio-summary.md), capture
this same topology and open an issue.
