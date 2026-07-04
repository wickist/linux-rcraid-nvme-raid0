# 03 — Proprietary AMD binary blob

## Why this repository does not redistribute the blob

The AMD RAID driver consists of two layers:

1. **Open glue source** (`rc_init.c`, `rc_msg.c`, headers, Makefile) —
   provided by AMD inside the `raid_linux_driver_930_00276` SDK.
2. **Closed binary object** `rcblob.x86_64` (~10.5 MB) — also provided
   by AMD inside the same SDK, linked as a prebuilt object.

Both are governed by AMD's End User License Agreement ([AMD EULA]).
Redistributing AMD's binary components from a third-party GitHub repo
would violate that EULA and risk a takedown.

This repository therefore ships:

* ✅ Our own **patches** (MIT-licensed).
* ✅ Our **DKMS configuration** and build glue.
* ✅ Our **setup / extract / verify** scripts.
* ✅ Our **fio profiles and tuning scripts**.
* ❌ **NOT** `rcblob.x86_64`.
* ❌ **NOT** any repackaged AMD installer / zip / deb / rpm.

## How to obtain the blob

End users download the AMD RAID driver directly from AMD's official page:

> https://www.amd.com/en/support/downloads/drivers.html/chipsets/swrx8/wrx80.html

Look for the **Linux x86 64-bit Driver** section and grab
`raid_linux_driver_930_00276.zip`. Save it under `vendor/` in your clone.

## Extraction workflow

```bash
# 1. Clone and enter the repo
git clone https://github.com/<owner>/linux-rcraid-nvme-raid0.git
cd linux-rcraid-nvme-raid0

# 2. Drop the AMD archive into vendor/
mkdir -p vendor
cp ~/Downloads/raid_linux_driver_930_00276.zip vendor/

# 3. Extract the blob
bash scripts/fetch-and-extract-rcblob.sh vendor/raid_linux_driver_930_00276.zip
#    → installs dkms/rcraid/src/rcblob.x86_64

# 4. Verify integrity
bash scripts/verify-blob.sh
#    → compares SHA-256 against checksums/amd-raid-9.3.0.sha256
```

The `fetch-and-extract-rcblob.sh` script:

* Accepts either an explicit zip path or auto-detects a
  `raid_linux_driver_*.zip` inside `vendor/`.
* Extracts just `rcblob.x86_64` (no other files), so we don't drag in
  any more AMD content than strictly necessary.
* Refuses to continue if the blob is not found inside the archive.

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

```
dkms/rcraid/src/rcblob.x86_64
vendor/
*.zip
*.iso
*.rpm
*.deb
```

Even if you accidentally drop the AMD archive into a tracked location,
`git add` will refuse to stage it. Double-check with `git status` before
committing if you're unsure.

## License reminder

The MIT [LICENSE](../LICENSE) file explicitly states that it covers only
the original patches, scripts, docs and DKMS config authored by this
project's contributors. The AMD-owned source files (`src/*.c`, `src/*.h`,
`src/Makefile`, `src/common_shell`) and the blob (`src/rcblob.x86_64`)
remain under AMD's proprietary license.

Continue with [04-mdadm-raid0-setup.md](04-mdadm-raid0-setup.md) if you
want the higher-throughput software-RAID alternative.

[AMD EULA]: https://www.amd.com/en/legal/eula.html
