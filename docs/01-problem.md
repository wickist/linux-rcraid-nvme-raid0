# 01 — The problem

## Background

AMD's high-end desktop (HEDT) and workstation platforms —
**Threadripper / Threadripper Pro** on **TRX40 / WRX80 / WRX90**, plus
consumer **AM4/AM5** chipsets (**X399 / X470 / X570 / X670E**) — ship with
an on-chipset **fake-RAID** controller marketed as **RAIDXpert2**.

On Windows this is fully supported: AMD ships a signed driver and the
**BIOS RAID configuration utility** lets you build NVMe or SATA RAID0/1/10
arrays that are then presented to the OS as ordinary block devices.

On Linux, AMD ships a **single binary driver** (`rcraid.ko`) plus a partial
glue-source SDK. It works on the kernel version AMD last updated it for —
and **nothing newer**. There has been no upstream maintenance for years.

## Symptoms on modern kernels

If you take AMD's `raid_linux_driver_930_00276` package and try to build
its `driver_sdk` against anything past Linux 5.x, you hit a wall of errors:

```
rc_init.c:1504:12: error: 'struct scsi_cmnd' has no member named 'scsi_done'
rc_init.c:1540:30: error: 'struct scsi_cmnd' has no member named 'SCp'
rc_init.c:2200:9:  error: implicit declaration of function 'blk_queue_max_hw_sectors'
rc_init.c:2521:12: error: 'struct ctl_table' has no member named 'child'
rc_init.c:2580:29: error: implicit declaration of function 'register_sysctl_table'
rc_init.c:624:14:   error: implicit declaration of function 'pci_set_dma_mask'
rc_config.c:12:10:  fatal error: linux/genhd.h: No such file or directory
... (20+ more)
```

That's because the SCSI host template, the DMA API, the sysctl API, the
procfs helpers, the block-layer queue API, the timer API and several
headers have all changed substantially since AMD last touched this code.

## What people usually do

The most common advice on forums is:

> "Forget BIOS RAID. Switch the chipset back to AHCI mode and use `mdadm`."

That works, but it has costs:

1. **You lose BIOS-visible RAID.** Windows can no longer see the array.
   Dual-boot scenarios break.
2. **You lose the array's metadata.** Any data on the BIOS RAID is gone
   unless you back it up first.
3. **The AMD RAID-Bottom-Device PCI IDs (`1022:b000`, class `010802`) end
   up claimed by the `nvme` driver**, which sees 4 raw disks instead of
   one stripe.

## What this project provides

Instead of telling users to abandon BIOS RAID, we **port the AMD driver**
forward to modern kernels. We also document — with measured benchmarks —
when `mdadm` is the better choice (it usually is, for pure throughput).

The repo gives you **both paths**:

* **Path A (rcraid port):** patch + DKMS package for the AMD 9.3.0 driver
  so it compiles and runs on Linux 6.14+. Keeps BIOS RAID intact.
* **Path B (mdadm fallback):** scripts and tuning for a higher-throughput
  software RAID0 stack on the same hardware. Recommended when you don't
  need BIOS-level visibility.

Both paths are validated on the same 4× Samsung 990 PRO + WRX80 testbed.
The numbers in [08-results.md](08-results.md) show mdadm winning on every
metric except "BIOS visibility".

Continue with [02-rcraid-kernel-port.md](02-rcraid-kernel-port.md) for
the full kernel-port writeup.
