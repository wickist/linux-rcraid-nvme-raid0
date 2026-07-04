# 03 — Proprietary AMD source and binary blob

## Why this repository does not redistribute AMD's files

The AMD RAID driver consists of two layers, **both owned by AMD** and
governed by AMD's End User License Agreement ([AMD EULA]):

1. **Driver glue source** (`rc_init.c`, `rc_msg.c`, headers, `Makefile`,
   `common_shell`) — provided by AMD inside the
   `raid_linux_driver_930_00276` SDK.
2. **Closed binary object** `rcblob.x86_64` (~10.5 MB) — also provided
   by AMD inside the same SDK, linked as a prebuilt object.

Redistributing **either** of those from a third-party GitHub repo would
violate AMD's EULA and risk a takedown notice.

This repository therefore ships:

* ✅ Our own **unified diff patch** against AMD 9.3.0 (`patches/kernel-6.14/`).
* ✅ Our **DKMS configuration** and post-install hooks.
* ✅ Our **source preparation, verification, tuning, benchmark scripts**.
* ✅ Our **fio profiles**.
* ✅ A SHA-256 manifest for verifying the extracted blob.
* ❌ **NOT** any of AMD's `*.c` / `*.h` source files.
* ❌ **NOT** `rcblob.x86_64`.
* ❌ **NOT** any repackaged AMD installer / zip / deb / rpm.

## How to obtain AMD's driver package

End users download the AMD RAID driver directly from AMD's official page:

> https://www.amd.com/en/support/downloads/drivers.html/chipsets/swrx8/wrx80.html

Look for the **Linux x86 64-bit Driver** section and grab
`raid_linux_driver_930_00276.zip`. Save it under `vendor/` in your clone.

## Source preparation workflow

`scripts/prepare-rcraid-source.sh` does everything in one shot:

1. Extracts **all** AMD source files (`.c`, `.h`, `Makefile`,
   `common_shell`) plus the `rcblob.x86_64` blob into `dkms/rcraid/src/`.
2. Applies our `patches/kernel-6.14/rcraid-6.14-combined.patch` on top.

```bash
# 1. Clone and enter the repo
git clone https://github.com/wickist/linux-rcraid-nvme-raid0.git
cd linux-rcraid-nvme-raid0

# 2. Drop the AMD archive into vendor/
mkdir -p vendor
cp ~/Downloads/raid_linux_driver_930_00276.zip vendor/

# 3. Extract AMD source + apply the kernel-6.14 patch
bash scripts/prepare-rcraid-source.sh vendor/raid_linux_driver_930_00276.zip
#    → fills dkms/rcraid/src/ with patched AMD source + blob

# 4. Verify blob integrity
bash scripts/verify-blob.sh
#    → compares SHA-256 against checksums/amd-raid-9.3.0.sha256
```

The script:

* Accepts either an explicit zip path or auto-detects a
  `raid_linux_driver_*.zip` inside `vendor/`.
* Refuses to continue if the AMD source tree or the blob is missing.
* Applies the patch with `patch -p1` (falls back to `-p0` if needed).

## Integrity check

The `verify-blob.sh` script computes SHA-256 of the extracted blob and
compares against the manifest at `checksums/amd-raid-9.3.0.sha256`:

```
0a536dd9368b1d2e299e4b0a562024634c8467bed3e926058bb2f7112eee658a  rcblob.x86_64
```

If the hash doesn't match, you probably extracted from a different AMD
driver version (not 9.3.0). Our patches were validated against 9.3.0 — a
different blob may compile and link, but the firmware mailbox protocol
is not guaranteed to match the glue source.

## What `.gitignore` protects

```text
dkms/rcraid/src/*
!dkms/rcraid/src/.gitkeep
vendor/
*.zip
*.iso
*.rpm
*.deb
```

This prevents both AMD source files and AMD binary blobs from being
committed. Even if you accidentally drop the AMD archive into a tracked
location, `git add` will refuse to stage it. Double-check with
`git status` before committing if you're unsure.

## License reminder

The MIT [LICENSE](../LICENSE) file explicitly states that it covers only
the original patches, scripts, docs and DKMS config authored by this
project's contributors. The AMD-owned source files (`src/*.c`, `src/*.h`,
`src/Makefile`, `src/common_shell`) and the blob (`src/rcblob.x86_64`)
remain under AMD's proprietary license.

Continue with [04-mdadm-raid0-setup.md](04-mdadm-raid0-setup.md) if you
want the higher-throughput software-RAID alternative.

[AMD EULA]: https://www.amd.com/en/legal/eula.html
