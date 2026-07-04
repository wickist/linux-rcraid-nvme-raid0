# 02 — rcraid kernel 6.14 port

This document describes what we changed in AMD's `raid_linux_driver_930_00276`
source to make it compile and run on Linux 6.14.

For the per-symbol change list, see [../patches/kernel-6.14/CHANGELOG.md](../patches/kernel-6.14/CHANGELOG.md).
This document focuses on the **why** and the **non-obvious traps**.

## Source layout

AMD ships the SDK like this:

```
raid_linux_driver_930_00276/
└── Ubuntu20.04.02/
    ├── driver_sdk/
    │   ├── install                ← distro installer
    │   ├── mk_certs               ← signing helper (NOT shipped, breaks DKMS)
    │   ├── README.sdk
    │   └── src/
    │       ├── Makefile
    │       ├── rc_init.c          ← main module entry, SCSI host template
    │       ├── rc_msg.c           ← mailbox / DMA messaging layer
    │       ├── rc_mem_ops.c       ← XOR/SG list ops (RAID5/6 — unused for RAID0)
    │       ├── rc_config.c        ← /dev/rccfg miscdevice (userspace API)
    │       ├── rc_event.c         ← async event queue
    │       ├── rcblob.x86_64      ← 10.5 MB prebuilt closed-source object
    │       └── ... headers
    ├── rcraid.ko                  ← prebuilt for 5.x — useless on 6.14
    └── ...
```

Two important facts that shape everything else:

1. **The driver is NOT fully open.** The actual RAID logic lives inside the
   prebuilt ELF object `rcblob.x86_64` (~10.5 MB). The C source is just
   glue: PCI probe, SCSI host template, sysctl/procfs entries, ioctl glue.
2. **The blob must link.** Kernel 6.14's stricter `modpost` and `objtool`
   could in principle reject a 2021-era prebuilt object. In our testing
   they did NOT — the blob passed through unmodified. If your toolchain
   rejects it, try `CONFIG_STACK_VALIDATION=n` or older `pahole`.

## Patch strategy

Every change is **version-guarded** with `LINUX_VERSION_CODE` so the tree
still builds on older kernels. We never delete legacy code paths — we
`#if` them out.

```c
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 18, 0)
    /* new API */
#else
    /* legacy AMD code */
#endif
```

This keeps a single source tree buildable from 5.x through 6.14+.

## Categories of changes

### 1. SCSI host template (`rc_init.c`)

Modern kernels restructured the SCSI host template significantly:

* `DEF_SCSI_QCMD` macro is gone — replaced by direct 2-arg `queuecommand`.
* The completion callback moved from `scp->scsi_done` (a pointer field
  on `struct scsi_cmnd`) to the function `scsi_done(scp)`.
* The per-command scratch space `scp->SCp` was removed in 5.18; the
  replacement is `scp->host_scribble`.
* `slave_configure` was renamed to `sdev_configure` and now receives a
  `struct queue_limits *` argument (6.14).
* `.present` field was removed (6.5).
* `blk_queue_max_hw_sectors()` was removed (6.14) — use the host
  template's `.max_sectors` field instead.

### 2. DMA API (`rc_init.c`, `rc_msg.c`)

The `pci_*_consistent` and `pci_set_dma_mask` family was removed across
5.18 in favor of the generic DMA API:

```c
/* old */ pci_alloc_consistent(pdev, size, &dma_handle)
/* new */ dma_alloc_coherent(&pdev->dev, size, &dma_handle, GFP_KERNEL)
```

Likewise `pci_set_dma_mask` → `dma_set_mask`, and the `PCI_DMA_*`
direction enum became `DMA_*`.

### 3. sysctl tables (`rc_init.c`)

The legacy `register_sysctl_table(parent_table)` with `.child` chains was
removed in 6.6; modern kernels take a path + flat table:

```c
rcraid_sysctl_hdr = register_sysctl("dev/scsi/rcraid", rcraid_table);
```

**Important:** we deliberately made sysctl registration **non-fatal** on
modern kernels. AMD uses these knobs (`dipm`, `hipm`, `ncq`, `zpodd`) for
SATA power management — they are irrelevant for NVMe RAID. Letting module
init fail because the table is rejected would leak the PCI driver name
and prevent retrying `insmod`. See [07-troubleshooting.md](07-troubleshooting.md#already-registered).

### 4. Headers and bookkeeping

* `<linux/genhd.h>` was removed in 6.9 — drop the include from `rc_config.c`.
* `init_timer()` was removed long ago; we drop it and keep only `timer_setup()`.
* `sysrq_key_op` handler signature changed from `void (*)(int)` to
  `void (*)(u8)` in 6.14.

### 5. Makefile fixes for DKMS

The original `Makefile` has a `clean` target that creates the
`rcblob.x86_64.o` symlink. DKMS does **not** run `clean` before `all`, so
the link step fails with `ld: cannot find ./rcblob.x86_64.o`. We added
an `rcblob_pre` prerequisite to `all` that creates the symlink.

The `mk_certs` module-signing step is also gated behind a helper script
that isn't shipped with the SDK. We disabled it in the Makefile — sign
manually with `kmodsign` if you need Secure Boot.

## Runtime workarounds (NOT in the source)

Three problems cannot be solved in the source — they need system-level
configuration. The `install-rcraid-dkms.sh` script handles the first two;
the third is documented for completeness.

### a. `IO_PAGE_FAULT` storm from AMD-Vi IOMMU

The AMD-Vi IOMMU rejects DMA writes from rcraid's firmware mailbox with
`IO_PAGE_FAULT` on address `0xfffffffffffff000`. Disabling the IOMMU
sidesteps it entirely:

```
GRUB_CMDLINE_LINUX_DEFAULT="... amd_iommu=off"
```

### b. `nvme` driver grabs the RAID-Bottom-Devices first

The 4 Samsung SSDs surface as PCI devices with class `0x010802` — the
same class the in-tree `nvme` driver claims. Whichever driver loads
first wins. On a normal boot `nvme` wins, and rcraid probes nothing.

We handle this with a systemd oneshot service that runs after boot:

1. Unbind the 4 RAID-member SSDs from `nvme` (skip any non-RAID NVMe
   such as the boot disk — detected by model string).
2. `rmmod rcraid` and re-`modprobe` with `rc_adapter_count=N`.

The matching script and unit file are kept outside this repo (host-specific)
but the recipe is reproduced in [07-troubleshooting.md](07-troubleshooting.md).

### c. `rc_adapter_count` defaults to a sentinel

AMD's stock module parameter `rc_adapter_count=999` is supposed to mean
"auto-detect". It does — by counting all AMD RAID-Bottom-Devices on the
PCI bus. If you have any non-RAID NVMe on the same chipset (e.g. your
boot disk), it gets counted too, and the `rcraid_probe_one` "all adapters
accounted for" check never matches. The fix is to pass the **real** member
count via modprobe:

```
options rcraid rc_adapter_count=4
```

## Verifying the port

The quickest sanity check after build is `modinfo`:

```
$ modinfo rcraid.ko | grep -E 'vermagic|alias'
vermagic: 6.14.0-37-generic SMP preempt mod_unload modversions
alias:    pci:v00001022d0000B000sv*sd*bc01sc08i02*
```

The `pci:v00001022d0000B000...` alias is the AMD NVMe RAID-Bottom-Device.
If `vermagic` matches your running kernel, the port compiled cleanly.

Continue with [03-proprietary-blob.md](03-proprietary-blob.md) for the
binary blob handling.
