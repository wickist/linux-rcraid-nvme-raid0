# 06 — Benchmarks

## Methodology

All numbers in this repo come from [fio] with these defaults unless
otherwise noted:

* `--direct=1` — bypass page cache (measure disk, not RAM).
* `--ioengine=libaio` — slightly faster than `io_uring` for read on this
  kernel, identical for write.
* `--runtime=30 --time_based=1` — sustained measurement, not just a
  burst that benefits from SLC cache.
* `--group_reporting=1` — single aggregate number per test.
* Test files dropped from page cache (`echo 3 > /proc/sys/vm/drop_caches`)
  before each run.
* Each test runs on a freshly prepared file (write+fsync before any read).

The full sequence is automated by `scripts/run-benchmarks.sh`:

```bash
sudo bash scripts/run-benchmarks.sh /mnt/raid0
```

Reproducible `.fio` profiles are under [../fio/](../fio/).

## Profiles

### Optimal sequential read — `fio/read-optimal.fio`

```
ioengine=libaio, direct=1, rw=read, bs=1M
numjobs=4, iodepth=64, runtime=30, time_based
```

This is the **maximum throughput profile**. Do not raise `numjobs` or
`iodepth` beyond these values — Linux md/raid0 serializes across
stripes, and beyond ~4×64 the latency grows faster than throughput.

### Optimal sequential write — `fio/write-optimal.fio`

```
ioengine=libaio, direct=1, rw=write, bs=1M
numjobs=4, iodepth=64, runtime=30, time_based
```

### Raw 4-NVMe bypass — `fio/raw-4nvme-read.fio`

```
ioengine=io_uring, direct=1, rw=read, bs=1M
4 sections, each targeting one /dev/nvmeXn1 directly (no mdadm/XFS)
```

Use this to measure the **hardware ceiling** without the software stack
in the way. Useful for diagnosing whether a slow number is the SSDs'
fault or the kernel's.

### Regression — `fio/regression.fio`

A short multi-test profile for quick sanity checks after kernel or
config changes. Runs each test for 10 s.

## Reading fio output

A typical line:

```
READ: bw=25.8GiB/s (27.7GB/s), ..., io=775GiB (832GB), run=30019-30019msec
```

* `bw=25.8GiB/s` — bandwidth in binary units.
* `(27.7GB/s)` — bandwidth in SI units (the number we report).
* `io=775GiB` — total bytes transferred during the runtime window.
* `run=30019msec` — actual wall-clock runtime.

Multiply `bw` × `run` to double-check against `io`.

## Disk stats

fio also prints per-device stats at the end:

```
nvme1n1: ios=667667/0, sectors=683691008/0, ..., util=99.18%
```

A healthy sequential workload should show **roughly equal `ios`** across
all members. A wildly skewed distribution means mdadm isn't striping
evenly — usually a sign of misaligned XFS geometry or wrong chunk size.

## Hardware topology you should record

Before reporting numbers, capture:

```bash
uname -r
lscpu | grep -E 'Model name|CPU\(s\):'
lspci -nn | grep -i 'non-volatile'
for d in 0000:02:00.0 0000:03:00.0 0000:04:00.0 0000:05:00.0; do
    lspci -vv -s $d | grep -E 'LnkCap:|LnkSta:'
done
mdadm --detail /dev/md0 | head
xfs_info /mnt/raid0 | head
cat /sys/block/md0/queue/scheduler
cat /sys/block/md0/queue/read_ahead_kb
sysctl vm.dirty_ratio vm.dirty_background_ratio
```

These are the variables that explain a benchmark result. Without them,
"my RAID0 only does X GB/s" is impossible to interpret.

## Common pitfalls

### "Read is slower than write"

Counter-intuitive but real. Possible causes:

* Linux md/raid0 read coordination overhead (~30% in our measurements).
* SLC cache absorbing writes faster than TLC reads can stream.
* PCIe ASPM throttling under sustained read.

The fix isn't to chase the write number — it's to verify against the
raw 4-NVMe profile. If raw is also low, it's hardware. If raw is fine
but mdadm is low, it's the md/raid0 layer.

### "Bigger block size always wins"

Not always. On our system, 4M blocks read was actually **slower** (19.8
GB/s) than 1M (27.7 GB/s) through XFS, because XFS' allocation decisions
at 4M granularity were suboptimal. Test a sweep:

```
for bs in 64k 128k 256k 512k 1m 2m 4m; do
    fio --name=t --bs=$bs ...
done
```

### "More threads = more throughput"

Decisively false on mdadm. Past `numjobs = # of physical SSDs`, latency
explodes and bandwidth drops. See the table in [05-xfs-optimization.md](05-xfs-optimization.md).

Continue with [07-troubleshooting.md](07-troubleshooting.md).

[fio]: https://fio.readthedocs.io/en/latest/fio_doc.html
