# 05 — XFS / storage tuning

The single most important lesson from this project's tuning work:

> **Throughput is not limited by the SSDs. It is limited by software
> knobs you have to find.**

We measured raw 4-NVMe reads at **29.5 GB/s** but the initial mdadm
stack capped at 19.7 GB/s. Closing that gap to 27.7 GB/s required
fixing several independent knobs. This doc lists them, what each does,
and why we landed on the values we did.

## Filesystem layer

### XFS stripe geometry

Format with `su=` and `sw=` matching the mdadm chunk:

```bash
mkfs.xfs -f -d su=512k,sw=4 /dev/md0
```

* `su=` is the striping unit (the mdadm chunk size).
* `sw=` is the striping width (number of data disks).

Without this, XFS picks `sunit=0 swidth=0` and block allocations land on
arbitrary stripe offsets, hurting random write throughput.

If you forget to set it at format time, you can also pass it as a mount
option: `mount -o sunit=128,swidth=512 /dev/md0 /mnt/raid0`
(4 KiB blocks: 512K / 4K = 128, 128 × 4 = 512).

### Mount options

Use `noatime,nodiratime` to suppress atime updates on reads:

```
UUID=<...> /mnt/raid0 xfs defaults,noatime,nodiratime 0 2
```

## Block layer

### I/O scheduler — `none`

For NVMe behind mdadm, the in-kernel `mq-deadline` scheduler adds
reordering work that NVMe doesn't benefit from. `none` (pure blk-mq)
is the right answer:

```bash
echo none > /sys/block/md0/queue/scheduler
```

Persisted via the udev rule installed by `tune-storage-runtime.sh`.

### Read-ahead — 4 MB

The default 128 KB read-ahead limits how far ahead of sequential reads
the kernel prefetches. 4 MB is the sweet spot on this hardware — higher
values (16 MB) didn't help further:

```bash
echo 4096 > /sys/block/md0/queue/read_ahead_kb
```

### Writeback throttling — off

`wbt_lat_usec` defaults to ~2 ms on this kernel and caps sequential
write bursts. Setting it to 0 disables the throttle:

```bash
echo 0 > /sys/block/md0/queue/wbt_lat_usec
```

## VM layer

### `vm.dirty_ratio` / `vm.dirty_background_ratio`

Aggressive write workloads benefit from a large dirty-page buffer. We
kept the kernel defaults:

```
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
```

Setting `dirty_ratio` very low (5 or below) made sequential write drop
by 30–40% — the kernel started flushing too early.

## fio / application layer — THE big one

This is the knob most people miss. **Linux md/raid0 serializes across
stripes.** Adding more fio jobs past a certain point does NOT raise
throughput — it makes latency explode and aggregate bandwidth drops.

On this 4-NVMe hardware we measured:

| `numjobs` (iodepth=16, libaio) | seq read |
|---:|---:|
| 1 | 13.0 GB/s |
| **2** | **25.9 GB/s** |
| 4 | 25.0 GB/s |
| 8 | 19.7 GB/s ← collapse |
| 16 | 19.8 GB/s |

And the iodepth sweep (4 jobs, libaio):

| `iodepth` | seq read |
|---:|---:|
| 4 | 23.5 GB/s |
| 8 | 25.2 GB/s |
| 16 | 24.5 GB/s |
| 32 | 26.3 GB/s |
| **64** | **27.7 GB/s** |
| 128 | 19.8 GB/s ← collapse |

**Optimal profile:**

```
--numjobs=4 --iodepth=64 --ioengine=libaio --bs=1M --direct=1
```

`libaio` edged out `io_uring` slightly for reads in our runs (~+1 GB/s),
but the difference is small and either works. The big lever is keeping
job count low.

### Implication for application tuning

If your application drives the I/O itself (DuckDB, Postgres, a vector DB,
an ML training loop loading checkpoints), make sure to cap its thread
count to roughly the number of physical NVMe SSDs in the array. Telling
DuckDB to use 16 threads on a 4-SSD RAID0 will run **slower** than 4
threads.

```sql
-- DuckDB
SET threads TO 4;
```

## rcraid-specific tuning (Path B)

If you went with the rcraid port instead of mdadm, the same VM and
block-layer knobs apply, plus module parameters:

```
# /etc/modprobe.d/rcraid.conf
options rcraid rc_adapter_count=4 tag_q_depth=64
```

* `rc_adapter_count=N` — number of RAID-member SSDs (not counting any
  non-RAID NVMe like the boot disk). Critical for `rcraid_probe_one` to
  finish init.
* `tag_q_depth=N` — per-LUN queue depth (default 16 is way too low for
  NVMe). 64 was the validated sweet spot. 256 didn't help further.

Note that even with all of this, rcraid caps around 16.6 GB/s because
of the single SCSI host queue. There is no tuning that fixes that — it's
architectural. See [08-results.md](08-results.md).

## Summary

| Layer | Knob | Value | Why |
|---|---|---|---|
| XFS | `mkfs.xfs -d su=512k,sw=4` | matches chunk | block alloc aligned |
| XFS | `noatime,nodiratime` mount | on | drop atime writes |
| Block | `queue/scheduler` | `none` | no reordering needed for NVMe |
| Block | `queue/read_ahead_kb` | 4096 | large seq workload |
| Block | `queue/wbt_lat_usec` | 0 | don't throttle writeback |
| VM | `vm.dirty_ratio` | 20 | large write buffer |
| App | `numjobs` | = # of SSDs | mdadm stripe contention |
| App | `iodepth` | 64 | sweet spot (128 collapses) |
| App | `ioengine` | libaio | slight edge over io_uring for read |
