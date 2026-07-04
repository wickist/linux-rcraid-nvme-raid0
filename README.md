# linux-rcraid-nvme-raid0

> AMD `rcraid` Linux kernel port (6.14+), DKMS build, NVMe RAID0 setup, mdadm/XFS optimization, and fio benchmarks for high-speed workstation storage.

[![Kernel](https://img.shields.io/badge/kernel-6.14%2B-blue.svg)](https://www.kernel.org/)
[![License](https://img.shields.io/badge/license-MIT--Patches-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-WRX80%20%7C%20TRX40%20%7C%20X570-lightgrey.svg)](https://www.amd.com/)
[![RAID](https://img.shields.io/badge/RAID-NVMe%20RAID0-orange.svg)](docs/04-mdadm-raid0-setup.md)

---

## 🎯 What this project solves

AMD ships the **RAIDXpert2 Linux driver (`rcraid`)** as a binary-blob + glue-source package that targets **old kernels (5.x)**. On modern kernels (6.14+) it does not compile, breaking **hardware NVMe RAID** for anyone on Threadripper Pro / WRX80 / TRX40 / X570 platforms.

This repository:

1. **Patches the AMD 9.3.0 `rcraid` source** so it compiles on **Linux 6.14+**.
2. Packages it as **DKMS** so it auto-rebuilds on every kernel update.
3. Provides **mdadm RAID0** as a higher-throughput alternative with **fio benchmark profiles** and tuning scripts.
4. Documents the **entire journey**: kernel port → DKMS → NVMe bind/unbind → IOMMU workaround → systemd service → mdadm fallback → read/write tuning.

> ⚠️ **TL;DR for the impatient:** if you just want maximum throughput from 4× NVMe SSDs and don't specifically need AMD's hardware RAID, jump straight to **[mdadm setup](docs/04-mdadm-raid0-setup.md)**. The rcraid port is provided for users who need BIOS-visible RAID (e.g. dual-boot with Windows).

---

## ⚡ Final performance (4× Samsung 990 PRO, mdadm RAID0, XFS)

| Workload | Throughput | IOPS | % of raw HW |
|---|---:|---:|---:|
| **Sequential Read 1M** (4 jobs, depth 64) | **27.7 GB/s** | 27K | **94%** |
| **Sequential Write 1M** | **25.5 GB/s** | 25K | **94%** |
| **Sequential Write 4M** | **27.1 GB/s** | 7K | — |
| Random Read 4K | 2.4 GB/s | **597K** | — |
| Random Write 4K (direct) | 89 MB/s | 22K | — |

**Raw 4× NVMe ceiling measured at 29.5 GB/s** — we reach **94% of theoretical maximum** through the software stack.

### rcraid vs mdadm (same 4 SSDs)

| Path | Seq Read | Seq Write | Random Read 4K |
|---|---:|---:|---:|
| Raw 4 NVMe (no RAID) | 29.5 GB/s | 27.2 GB/s | — |
| **mdadm RAID0** (recommended) | **27.7 GB/s** | **27.1 GB/s** | **597K IOPS** |
| rcraid (single SCSI queue) | 16.6 GB/s | 16.7 GB/s | 152K IOPS |

rcraid uses a single SCSI host queue, which caps aggregate throughput at ~16.6 GB/s regardless of tuning. mdadm preserves native NVMe blk-mq multi-queue and scales near-linearly.

---

## 🤖 Why this matters for AI / LLM workloads

This project is especially useful for **local AI workstations** that move
large model files, datasets and checkpoints.

A 4× NVMe RAID0 array does **not** make GPU inference faster by itself —
token generation is usually limited by GPU compute, VRAM bandwidth and
model architecture. What it **does** improve is the storage side of the
workflow:

| ✅ Improved by fast NVMe RAID0 | ❌ Not directly affected |
|---|---|
| Loading large GGUF / safetensors / checkpoint files | GPU token/s during inference |
| Moving models between cache, workspace and runtimes | Model architecture / quantization |
| Hugging Face / Transformers cache performance | VRAM capacity |
| DuckDB / Parquet scans over large local datasets | CUDA / ROCm compute throughput |
| Vector database indexing and rebuilds | |
| ML dataset staging and preprocessing | |

On the validated system, the mdadm RAID0 + XFS path reaches up to
**27.7 GB/s sequential read** and **25.5–27.1 GB/s sequential write**,
close to the raw 4× NVMe hardware ceiling. For comparison, a single
Samsung 990 PRO tops out around 7 GB/s — so the RAID0 array loads
multi-hundred-GB model files roughly **4× faster** than a single SSD.

## ⚡ Quick AI Win: put your model cache on the RAID0 array

After creating and mounting the RAID0 array at `/mnt/raid0`, move your
AI model cache there so large model downloads, cache reads and
checkpoint movement happen on the high-throughput volume.

### Hugging Face / Transformers

```bash
mkdir -p /mnt/raid0/ai-cache/huggingface

export HF_HOME=/mnt/raid0/ai-cache/huggingface
export HF_HUB_CACHE=/mnt/raid0/ai-cache/huggingface/hub
```

To persist across sessions, append to your shell profile:

```bash
cat <<'EOF' >> ~/.bashrc
export HF_HOME=/mnt/raid0/ai-cache/huggingface
export HF_HUB_CACHE=/mnt/raid0/ai-cache/huggingface/hub
EOF
```

Now every `from_pretrained(...)` call, `huggingface-cli download` and
`transformers` cache lookup lands on the RAID0 array.

---

## 🧰 Hardware reference (validated)

| Component | Model |
|---|---|
| CPU | AMD Ryzen Threadripper PRO 3945WX (12c/24t) |
| Motherboard | ASUS Pro WS WRX80E-SAGE SE WIFI |
| PCIe card | ASUS Hyper M.2 x16 Gen4 (PCIEX16_7, x4×4 bifurcation) |
| RAID member SSDs | 4× Samsung 990 PRO 1TB (Hyper M.2 card) |
| Boot SSD | 1× KIOXIA Exceria Pro 2TB (CPU-attached NVMe) |
| OS | Ubuntu 24.04 LTS, kernel `6.14.0-37-generic` |

---

## 📦 Repository layout

```
linux-rcraid-nvme-raid0/
├── README.md                       ← you are here
├── LICENSE                         ← MIT (covers patches/scripts only)
├── .gitignore
├── dkms/rcraid/                    ← DKMS package (NO AMD source committed)
│   ├── dkms.conf
│   ├── src/                        ← empty by default — populated by
│   │                                 prepare-rcraid-source.sh from AMD's zip
│   └── post_install / post_remove
├── patches/kernel-6.14/            ← our compatibility patch + change log
│   ├── rcraid-6.14-combined.patch  ← unified diff against AMD 9.3.0
│   └── CHANGELOG.md
├── scripts/                        ← setup, source preparation, tuning
│   ├── prepare-rcraid-source.sh    ← extracts AMD src + applies our patch
│   ├── verify-blob.sh
│   ├── install-rcraid-dkms.sh
│   ├── setup-mdadm-raid0.sh
│   ├── tune-storage-runtime.sh
│   └── run-benchmarks.sh
├── fio/                            ← reproducible benchmark profiles
│   ├── read-optimal.fio
│   ├── write-optimal.fio
│   ├── raw-4nvme-read.fio
│   └── regression.fio
├── docs/                           ← deep technical documentation
│   ├── 01-problem.md
│   ├── 02-rcraid-kernel-port.md
│   ├── 03-proprietary-blob.md
│   ├── 04-mdadm-raid0-setup.md
│   ├── 05-xfs-optimization.md
│   ├── 06-benchmarks.md
│   ├── 07-troubleshooting.md
│   └── 08-results.md
├── checksums/
│   └── amd-raid-9.3.0.sha256       ← SHA-256 manifest for the AMD blob
└── results/
    ├── fio-summary.md
    └── hardware-topology.md
```

---

## 🚀 Quick start

### Option A — mdadm RAID0 (recommended, max throughput)

```bash
git clone https://github.com/wickist/linux-rcraid-nvme-raid0.git
cd linux-rcraid-nvme-raid0

# 1. Create the array on 4 NVMe SSDs (EDIT devices first!)
sudo bash scripts/setup-mdadm-raid0.sh /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/nvme4n1

# 2. Apply runtime tuning (scheduler, read-ahead, sysctl, udev)
sudo bash scripts/tune-storage-runtime.sh /dev/md0

# 3. Benchmark
sudo bash scripts/run-benchmarks.sh /mnt/raid0
```

See **[docs/04-mdadm-raid0-setup.md](docs/04-mdadm-raid0-setup.md)** for full details.

### Option B — rcraid DKMS port (BIOS-visible hardware RAID)

```bash
git clone https://github.com/wickist/linux-rcraid-nvme-raid0.git
cd linux-rcraid-nvme-raid0

# 1. Download AMD RAID driver from AMD.com, place the archive in vendor/
#    https://www.amd.com/en/support/downloads/drivers.html/chipsets/swrx8/wrx80.html
mkdir -p vendor
cp ~/Downloads/raid_linux_driver_930_00276.zip vendor/

# 2. Extract AMD source into dkms/rcraid/src/ AND apply the kernel-6.14 patch
bash scripts/prepare-rcraid-source.sh vendor/raid_linux_driver_930_00276.zip

# 3. Verify blob integrity
bash scripts/verify-blob.sh

# 4. Install as DKMS (auto-rebuilds on kernel updates)
sudo bash scripts/install-rcraid-dkms.sh
```

See **[docs/02-rcraid-kernel-port.md](docs/02-rcraid-kernel-port.md)** for the full kernel-port writeup.

---

## 🔐 Proprietary AMD source and binary blob

**This repository does NOT redistribute AMD proprietary source files or binary blobs.**

Both the AMD-owned driver source (`dkms/rcraid/src/*.c`, `*.h`, `Makefile`, `common_shell`) and the `rcblob.x86_64` binary (a 10.5 MB prebuilt closed-source object inside the AMD RAID driver) are **owned by AMD** and are subject to AMD's End User License Agreement. We cannot host them here.

Users must obtain the AMD RAID driver package themselves from AMD's official download page and run the provided `prepare-rcraid-source.sh` script. That script:
1. Extracts AMD's source files + binary blob into `dkms/rcraid/src/`
2. Applies our kernel-6.14 compatibility patch on top

See **[docs/03-proprietary-blob.md](docs/03-proprietary-blob.md)** for details and SHA-256 verification.

---

## 📚 Documentation

| Doc | What it covers |
|---|---|
| [01-problem.md](docs/01-problem.md) | Why AMD's stock driver fails on modern kernels |
| [02-rcraid-kernel-port.md](docs/02-rcraid-kernel-port.md) | The 18 kernel API changes we patched |
| [03-proprietary-blob.md](docs/03-proprietary-blob.md) | `rcblob.x86_64` handling, license, verification |
| [04-mdadm-raid0-setup.md](docs/04-mdadm-raid0-setup.md) | Higher-throughput software RAID alternative |
| [05-xfs-optimization.md](docs/05-xfs-optimization.md) | XFS stripe geometry, mount options, queue tuning |
| [06-benchmarks.md](docs/06-benchmarks.md) | fio profiles, methodology, how to reproduce |
| [07-troubleshooting.md](docs/07-troubleshooting.md) | `already registered`, XFS shutdown, IO_PAGE_FAULT, ... |
| [08-results.md](docs/08-results.md) | Full benchmark tables, rcraid vs mdadm |

---

## ⚠️ Disclaimer

* This project is **not affiliated with AMD**. AMD®, RAIDXpert2™, Threadripper™ are trademarks of Advanced Micro Devices, Inc.
* The `rcraid` driver source originates from AMD's `raid_linux_driver_930_00276` package. Only our **kernel-compatibility patches and glue scripts** are MIT-licensed — the driver itself remains under AMD's proprietary license.
* **No warranty.** You can brick your boot process if you follow the rcraid path incorrectly. Always keep a separate boot disk (we used a KIOXIA SSD on the CPU-attached NVMe slot, never touched by RAID).
* The mdadm path is non-destructive to BIOS RAID metadata if you don't zero the superblocks — but if you do, your BIOS array is gone. Back up first.

---

## ⭐ Support / contribute

If this helped you bring AMD RAIDXpert2 / rcraid back to life on a modern
Linux kernel, please consider:

- ⭐ **Starring** the repo so others can find it
- 🍴 **Forking** it for your own platform or kernel version
- 🐛 **Opening an issue** with your motherboard, kernel version and error log
- 📊 **Sharing benchmark results** from your own NVMe / RAID setup

PRs welcome, especially:
* Patches for kernels beyond 6.14 (6.15, 6.16, 6.17+)
* Additional chipset/platform validation (WRX90, TRX50, X670E, ...)
* fio profiles for real-world workloads (DuckDB, Parquet, vector DBs, ML model loading)

Open an issue first if you want to discuss scope.

Useful details to include when filing an issue:

```bash
uname -a
lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINTS
lspci -vv | grep -E 'Non-Volatile|LnkSta|LnkCap'
dkms status
dmesg | grep -iE 'rcraid|nvme|iommu|xfs|md0'
```

---

## 📝 License

* **Patches, scripts, docs, fio profiles, DKMS config**: [MIT License](LICENSE)
* **`rcraid` driver source (`src/*.c`, `src/*.h`, `rcblob.x86_64`)**: AMD proprietary — see `LICENSE_SDK` inside the original AMD package. Not covered by this repo's MIT license.
