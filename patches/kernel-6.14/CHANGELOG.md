# rcraid 9.3.0 → kernel 6.14 port — change log

Source base: AMD `raid_linux_driver_930_00276` (Ubuntu 20.04.02 / `driver_sdk/src`).
Target kernel: Linux 6.14.0-37-generic (Ubuntu 24.04 HWE).

All changes are inside `dkms/rcraid/src/` and are version-guarded so the
source tree still builds on older kernels wherever the legacy API still exists.

## API replacements

| # | Old API / symbol | New API / symbol | File(s) | Kernel cut |
|---|---|---|---|---|
| 1 | `DEF_SCSI_QCMD` + 2-arg `queuecommand` w/ `CompletionRoutine` | modern 2-arg `queuecommand(cmd, done)` + `scsi_done(scp)` call | rc_init.c, rc_msg.c | 5.16 |
| 2 | `scp->scsi_done(scp)` (callback pointer) | `scsi_done(scp)` (function) | rc_msg.c (4 sites) | 5.16 |
| 3 | `scp->SCp.ptr` | `scp->host_scribble` | rc_init.c, rc_msg.c | 5.18 |
| 4 | `register_sysctl_table(rcraid_root_table)` + `.child` hierarchy | `register_sysctl("dev/scsi/rcraid", rcraid_table)` | rc_init.c | 6.5 |
| 5 | `.child` wrapper ctl_tables (`rcraid_dir_table`, `rcraid_root_table`) | compile-time excluded when `>= 6.6` (struct member gone) | rc_init.c | 6.6 |
| 6 | sysctl registration failure aborts module init | sysctl made best-effort (NVMe RAID does not depend on the SATA-only knobs) | rc_init.c | 6.6 |
| 7 | `pci_set_dma_mask` / `pci_set_consistent_dma_mask` | `dma_set_mask` / `dma_set_coherent_mask` | rc_init.c | 5.18 |
| 8 | `pci_alloc_consistent` | `dma_alloc_coherent(..., GFP_KERNEL)` | rc_init.c, rc_msg.c | 5.18 |
| 9 | `pci_free_consistent` | `dma_free_coherent` | rc_init.c, rc_msg.c | 5.18 |
| 10 | `init_timer` (with manual `.data`/`.function`) | `timer_setup()` only (drop `init_timer` calls) | rc_init.c, rc_msg.c | 4.15 |
| 11 | `blk_queue_max_hw_sectors()` | dropped; rely on host template `.max_sectors` | rc_init.c | 6.14 |
| 12 | `.slave_configure` host-template field | `.sdev_configure` + `queue_limits *` arg | rc_init.c | 6.14 |
| 13 | `Scsi_Host_Template.present` | excluded for `>= 6.5` (member removed) | rc_init.c | 6.5 |
| 14 | `sysrq_key_op` handler `void (*)(int)` | `void (*)(u8)` | rc_msg.c | 6.14 |
| 15 | `<linux/genhd.h>` include | removed (header deleted upstream) | rc_config.c | 6.9 |
| 16 | `dma_map_page/single` w/ `PCI_DMA_BIDIRECTIONAL` | `DMA_BIDIRECTIONAL` | rc_msg.c | 5.18 |
| 17 | `scp->request->timeout` | `scsi_cmd_to_rq(scp)->timeout` | rc_msg.c | 5.16 |
| 18 | `COMMAND_COMPLETE` / `GOOD` / `CHECK_CONDITION` macros | `SAM_STAT_GOOD` / `SAM_STAT_CHECK_CONDITION` (0 << 8) | rc_msg.c | 6.14 |

## Other fixes applied during the port

* `mk_certs` module-signing step in `Makefile` is commented out — the
  original code tried to run a local signing helper that is not shipped
  with the SDK and not needed when Secure Boot is off. (If you run Secure
  Boot, sign the module yourself with `kmodsign` / MOK.)
* New `rcblob_pre` make target ensures the `rcblob.x86_64.o` symlink exists
  before the kernel build system links. The original `clean` target created
  this symlink, but DKMS does not invoke `clean` first, causing
  `ld: cannot find ./rcblob.x86_64.o` failures. `all: bbanner rcblob_pre`.
* On `>= 6.5` the sysctl registration is **non-fatal**: AMD uses these
  knobs for SATA power management (DIPM, HIPM, NCQ, ZPODD) which are
  irrelevant for NVMe RAID. Aborting module load because sysctl rejected
  the table caused `pci_register_driver` to leak the "rcraid" name and
  broke subsequent `insmod` retries.

## Workarounds (NOT in the source — applied at runtime)

| Issue | Fix | Where |
|---|---|---|
| `IO_PAGE_FAULT` storm from AMD-Vi IOMMU when rcraid DMAs the firmware mailbox | `amd_iommu=off` on the kernel command line | GRUB |
| `nvme` driver claims the RAID-Bottom-Device PCI IDs before rcraid probes | systemd service that unbinds the Samsung SSDs from `nvme` and reloads rcraid (`rc_adapter_count=N`) | systemd unit |
| `rc_adapter_count` defaults to a sentinel (999) that never matches when a non-RAID NVMe (boot disk) is present | `options rcraid rc_adapter_count=<N of RAID-member SSDs>` | /etc/modprobe.d/rcraid.conf |
| mdadm read ceiling at ~19.7 GB/s with high parallelism | drop `numjobs` to 4 and `iodepth` to 64; use `libaio` instead of `io_uring` for read | fio profile / docs |

## Validated environment

* Kernel: 6.14.0-37-generic
* Compiler: gcc 13.3.0
* linux-headers: present
* Secure Boot: disabled (no module signing required)
* CPU: Threadripper PRO 3945WX
* Motherboard: ASUS Pro WS WRX80E-SAGE SE WIFI
* Member SSDs: 4× Samsung 990 PRO 1TB on ASUS Hyper M.2 x16 Gen4
* Boot SSD (kept on `nvme` driver, NOT touched by RAID): KIOXIA Exceria Pro 2TB
