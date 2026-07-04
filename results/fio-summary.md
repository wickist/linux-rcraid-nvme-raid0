# fio summary — final benchmark results

Captured on 2026-07-04 with the validated optimal profile. See
[../docs/06-benchmarks.md](../docs/06-benchmarks.md) for methodology and
[../docs/08-results.md](../docs/08-results.md) for the full comparison
table.

## Hardware

| Role | Model |
|---|---|
| CPU | AMD Ryzen Threadrunner PRO 3945WX (12c/24t) |
| Motherboard | ASUS Pro WS WRX80E-SAGE SE WIFI |
| PCIe carrier | ASUS Hyper M.2 x16 Gen4 (PCIEX16_7, x4×4) |
| RAID members | 4× Samsung 990 PRO 1TB |
| Boot SSD | KIOXIA Exceria Pro 2TB |

## Software

| Layer | Version |
|---|---|
| Kernel | 6.14.0-37-generic (Ubuntu 24.04 HWE) |
| Compiler | gcc 13.3.0 |
| mdadm | 4.3 |
| XFS | xfsprogs 6.x |
| fio | 3.36 |

## Optimal fio profile

```
--numjobs=4 --iodepth=64 --ioengine=libaio --bs=1M --direct=1 --runtime=30 --time_based
```

## mdadm RAID0 (recommended)

| Workload | Throughput | IOPS | % raw HW |
|---|---:|---:|---:|
| Seq Read 1M | **27.7 GB/s** | 27K | 94% |
| Seq Write 1M | **25.5 GB/s** | 25K | 94% |
| Seq Write 4M | **27.1 GB/s** | 7K | — |
| Random Read 4K | 2.4 GB/s | 597K | — |
| Random Write 4K (direct) | 89 MB/s | 22K | — |
| writeback errors | 0 | — | — |

## rcraid DKMS port (BIOS RAID path)

| Workload | Throughput | IOPS |
|---|---:|---:|
| Seq Read 1M | 16.6 GB/s | 16K |
| Seq Write 1M | 13.7 GB/s | 13K |
| Random Read 4K | 623 MB/s | 152K |

## Raw 4-NVMe bypass (no RAID)

| Workload | Throughput |
|---|---:|
| Seq Read 1M (io_uring, depth 128) | 28.3 GB/s |
| Seq Read 4M (io_uring, depth 64) | 27.2 GB/s |
| Seq Write 1M (io_uring, depth 128) | 27.2 GB/s |

## Per-SSD PCIe link during test

```
nvme1n1: Speed 16GT/s, Width x4, util 99.18%
nvme2n1: Speed 16GT/s, Width x4, util 99.66%
nvme3n1: Speed 16GT/s, Width x4, util 99.55%
nvme4n1: Speed 16GT/s, Width x4, util 99.56%
```

## Conclusion

The mdadm path reaches **94% of the raw hardware ceiling** (27.7 of
29.5 GB/s). The remaining ~6% is the dm-stripe target's coordination
overhead — irreducible without switching to a kernel-bypass stack like
SPDK, which is out of scope for this project.

The rcraid path is roughly half of mdadm because of the single SCSI
host queue architecture. Use it only when you specifically need
BIOS-visible RAID.
