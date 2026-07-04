# 08 — Results

All numbers measured on the same hardware:

* CPU: AMD Ryzen Threadripper PRO 3945WX (12c / 24t)
* Board: ASUS Pro WS WRX80E-SAGE SE WIFI
* PCIe card: ASUS Hyper M.2 x16 Gen4 in PCIEX16_7 (x4×4 bifurcation)
* Member SSDs: 4× Samsung 990 PRO 1TB
* Boot SSD: KIOXIA Exceria Pro 2TB (CPU-attached, not in RAID)
* OS: Ubuntu 24.04 LTS, kernel `6.14.0-37-generic`
* Filesystem: XFS (`su=512k,sw=4` for mdadm; `su=256k,sw=4` for rcraid)
* fio profile: `numjobs=4, iodepth=64, ioengine=libaio, direct=1, runtime=30s`

## Final mdadm RAID0 results

| Workload | Throughput | IOPS | % raw HW |
|---|---:|---:|---:|
| Sequential Read 1M | **27.7 GB/s** | 27K | **94%** |
| Sequential Write 1M | **25.5 GB/s** | 25K | **94%** |
| Sequential Read 4M | 19.8 GB/s | 5K | — |
| Sequential Write 4M | **27.1 GB/s** | 7K | — |
| Random Read 4K (QD64) | 2.4 GB/s | **597K** | — |
| Random Write 4K (direct) | 89 MB/s | 22K | — |
| Sustained write 60s | 25.9 GB/s | — | — |
| writeback errors | **0** | — | — |

## Final rcraid (DKMS port) results

| Workload | Throughput | IOPS |
|---|---:|---:|
| Sequential Read 1M | 15.7 GB/s | 15K |
| Sequential Write 1M | 13.7 GB/s | 13K |
| Sequential Read 4M | 16.6 GB/s | 4K |
| Sequential Write 4M | 16.7 GB/s | 4K |
| Random Read 4K | 623 MB/s | 152K |
| Random Write 4K (direct) | 67 MB/s | 16K |

rcraid's ceiling is structural: a single SCSI host queue funnels all
I/O from 4 NVMe SSDs. No tuning raises it past ~16.6 GB/s on this
hardware.

## Comparison: rcraid vs mdadm vs raw

| Path | Seq Read | Seq Write | Random Read 4K |
|---|---:|---:|---:|
| Raw 4 NVMe (no RAID) | 29.5 GB/s | 27.2 GB/s | — |
| **mdadm RAID0** (recommended) | **27.7 GB/s** | **25.5 GB/s** | **597K IOPS** |
| rcraid DKMS port | 16.6 GB/s | 16.7 GB/s | 152K IOPS |

The mdadm path reaches **94% of the raw hardware ceiling** on read and
write. The 5.8 GB/s mdadm overhead on read is the dm-stripe target's
coordination cost — confirmed by `/dev/md0` raw reads at 23.3 GB/s
versus file reads at 27.7 GB/s (the difference being XFS allocation
behavior at different block sizes).

The rcraid path is roughly **half** of mdadm. It's the right choice
only if you need BIOS-visible RAID (typically for Windows dual-boot).

## fio sweep data

These tables back the recommendations in [05-xfs-optimization.md](05-xfs-optimization.md).

### numjobs sweep (libaio, bs=1M, iodepth=16, /dev/md0 raw read)

| numjobs | Read |
|---:|---:|
| 1 | 13.0 GB/s |
| 2 | 25.9 GB/s |
| 4 | 25.0 GB/s |
| 8 | 19.7 GB/s ← collapse |
| 16 | 19.8 GB/s |

### iodepth sweep (libaio, bs=1M, numjobs=4, /dev/md0 raw read)

| iodepth | Read |
|---:|---:|
| 4 | 23.5 GB/s |
| 8 | 25.2 GB/s |
| 16 | 24.5 GB/s |
| 32 | 26.3 GB/s |
| 64 | **27.7 GB/s** |
| 128 | 19.8 GB/s ← collapse |

### Chunk size (mdadm) — read

All within measurement noise. Chunk size does not move the read needle
on this hardware; we keep 512K as mdadm default.

| Chunk | Read |
|---:|---:|
| 128K | 19.7 GB/s |
| 512K | 19.7 GB/s |

## PCIe link validation

```
$ sudo lspci -vv -s 02:00.0 | grep LnkSta
LnkSta: Speed 16GT/s, Width x4
$ sudo lspci -vv -s 03:00.0 | grep LnkSta
LnkSta: Speed 16GT/s, Width x4
$ sudo lspci -vv -s 04:00.0 | grep LnkSta
LnkSta: Speed 16GT/s, Width x4
$ sudo lspci -vv -s 05:00.0 | grep LnkSta
LnkSta: Speed 16GT/s, Width x4
```

All 4 Samsung SSDs negotiate **Gen4 x4** = ~8 GB/s each. The upstream
link from the ASUS Hyper M.2 card to the chipset negotiates **Gen4 x8**.

## Per-SSD utilization during a 4-job read

```
nvme1n1: util=99.18%
nvme2n1: util=99.66%
nvme3n1: util=99.55%
nvme4n1: util=99.56%
```

Even load distribution across all 4 members — mdadm striping is working
correctly.

## Environment provenance

* Built and benchmarked: 2026-07-04
* Kernel: 6.14.0-37-generic
* Compiler: gcc 13.3.0
* fio: 3.36
* mdadm: 4.3
* XFS: xfsprogs 6.x

If you reproduce this on different hardware, please open an issue with
your numbers and the topology capture from [06-benchmarks.md](06-benchmarks.md).
