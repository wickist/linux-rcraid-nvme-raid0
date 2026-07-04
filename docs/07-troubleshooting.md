# 07 — Troubleshooting

Every problem we hit during this project, the symptom, the cause, and
the fix. Indexed by error message so you can grep this file.

---

## `Error: Driver 'rcraid' is already registered, aborting...`

### Symptom

```
$ sudo insmod rcraid.ko
insmod: ERROR: could not insert module rcraid.ko: Device or resource busy
$ sudo dmesg | tail
Error: Driver 'rcraid' is already registered, aborting...
```

But `lsmod | grep rcraid` shows nothing.

### Cause

A previous `insmod` got far enough to call `pci_register_driver()` but
failed later in `module_init` (typically at `register_sysctl_table`).
The driver name leaked into the kernel's PCI driver registry and stays
there until reboot.

### Fix

1. Reboot. There is no clean way to unregister a leaked driver at runtime.
2. Apply the sysctl-as-best-effort patch from this repo's `dkms/rcraid/src/`
   — it makes sysctl registration non-fatal, so a sysctl failure no longer
   aborts module init.

---

## `sysctl table check failed: dev/scsi/rcraid/(null) procname is null`

### Symptom

```
sysctl table check failed: dev/scsi/rcraid/(null) procname is null
sysctl table check failed: dev/scsi/rcraid/(null) No proc_handler
```

### Cause

On kernel 6.6+, `register_sysctl(path, table)` is stricter about the
sentinel entry. The legacy `.child`-based wrapper tables (`rcraid_dir_table`,
`rcraid_root_table`) reference a struct member that no longer exists.

### Fix

Our patched source:

1. Switches to `register_sysctl("dev/scsi/rcraid", rcraid_table)` on
   `LINUX_VERSION_CODE >= KERNEL_VERSION(6, 5, 0)`.
2. Excludes the `.child` wrapper tables from compilation on `>= 6.6`.
3. Makes sysctl registration **best-effort** — failure logs a warning
   but does not abort module init. The sysctl knobs are for SATA power
   management and are irrelevant to NVMe RAID.

---

## `AMD-Vi: Event logged [IO_PAGE_FAULT ... address=0xfffffffffffff000]`

### Symptom

A flood of these in `dmesg` immediately after `insmod rcraid`. The RAID
array does not appear; `/proc/scsi/scsi` shows the AMD-RAID
Configuration device but no Array device.

### Cause

The AMD-Vi IOMMU rejects the DMA writes that rcraid's firmware mailbox
issues. The address `0xfffffffffffff000` is clearly garbage.

### Fix

Disable the IOMMU via the kernel command line:

```
GRUB_CMDLINE_LINUX_DEFAULT="... amd_iommu=off"
```

Then `sudo update-grub` and reboot.

This costs you IOMMU protection for the whole system, but it's the only
way we found to make rcraid's DMA work. The mdadm path does not have
this problem — it uses the in-tree `nvme` driver with full IOMMU support.

---

## rcraid loads, 4 SSDs probe, but no `/dev/sda` appears

### Symptom

```
$ lsmod | grep rcraid
rcraid  5169152  0
$ dmesg | grep rcraid
rcraid_probe_one: Total adapters matched 5     ← 5, not 4!
rcraid: card 0..3: AMD NVMe
(sysctl warning, then nothing)
$ lsblk
(no sda, just the 4 nvmes still owned by nvme driver)
```

### Cause

Two things conspiring:

1. The in-tree `nvme` driver loaded first and claimed the RAID-Bottom-Device
   PCI IDs. rcraid probed nothing.
2. `rc_adapter_count` defaults to the sentinel 999, expecting to count
   adapters itself. But it counts ALL RAID-Bottom-Devices including any
   non-RAID NVMe (your boot disk), so the "all adapters accounted for"
   check in `rcraid_probe_one` never matches and `rc_init_host` is never
   called.

### Fix

Two-step fix:

1. Unbind the 4 RAID-member SSDs from `nvme` and reload rcraid with the
   real adapter count. We packaged this as a systemd oneshot service so
   it runs automatically after every boot. The unit (host-specific but
   easy to adapt):

   ```bash
   #!/bin/bash
   # rcraid-nvme-fixup.sh
   set +e
   # Identify the non-RAID NVMe (boot disk) by model string and skip it.
   KIOXIA=$(for d in /sys/bus/pci/drivers/nvme/0000:*; do
       n=$(ls "$d/nvme/" 2>/dev/null | head -1)
       m=$(cat "/sys/class/nvme/$n/model" 2>/dev/null | tr -d ' ')
       case "$m" in *KIOXIA*|*Exceria*) echo "$(basename $d)";; esac
   done)

   rmmod rcraid
   for d in /sys/bus/pci/drivers/nvme/0000:*; do
       a=$(basename "$d")
       [ "$a" = "$KIOXIA" ] && continue
       echo "$a" > /sys/bus/pci/drivers/nvme/unbind
   done
   modprobe rcraid rc_adapter_count=4
   ```

   Wire it into a `[Unit] After=local-fs.target Before=multi-user.target`
   systemd oneshot.

2. Set the module parameter persistently:

   ```
   # /etc/modprobe.d/rcraid.conf
   options rcraid rc_adapter_count=4 tag_q_depth=64
   ```

   Replace `4` with the number of RAID-member SSDs in your system.

---

## `XFS (sda): writeback error on inode ...`

### Symptom

```
$ sudo touch /mnt/raid0/test
touch: cannot touch '/mnt/raid0/test': Input/output error
$ sudo dmesg | tail
XFS (sda): writeback error on inode 131, offset ...
XFS (sda): Corruption of in-memory data detected. Shutting down filesystem.
```

### Cause

We saw this when running aggressive fio write tests with `tag_q_depth`
or `numjobs` raised too high. Some writes returned an I/O error, which
XFS interpreted as corruption and self-shutdown.

### Fix

* `sudo umount /mnt/raid0`
* `sudo xfs_repair -L /dev/sda` (or `/dev/md0` for the mdadm path)
* `sudo mount /mnt/raid0`

If `xfs_repair` refuses with "log needs to be replayed", mount then
unmount first, then re-run.

This is a symptom, not a root cause — if it recurs, the underlying
write path is still unstable. Lower `numjobs` / `iodepth` in your fio
profile and re-test.

---

## `mdadm: /dev/nvmeXn1 appears to be part of a raid array: ... Continue creating array?`

### Symptom

```
$ sudo mdadm --create /dev/md0 --level=0 --raid-devices=4 /dev/nvme*n1
mdadm: /dev/nvme4n1 appears to be part of a raid array:
       level=raid0 devices=4 ctime=...
Continue creating array? mdadm: create aborted.
```

### Cause

A previous mdadm array or AMD BIOS RAID left metadata on the member
devices. mdadm sees it and refuses to proceed interactively (and our
non-interactive context answers "no").

### Fix

Zero the superblocks first:

```bash
for d in /dev/nvme1n1 /dev/nvme2n1 /dev/nvme3n1 /dev/nvme4n1; do
    sudo mdadm --zero-superblock --force "$d"
    sudo wipefs -a "$d"
done
```

Then re-run `mdadm --create`. The `setup-mdadm-raid0.sh` script does
this automatically.

---

## `modprobe: ERROR: could not insert rcraid: Invalid module format`

### Cause

The module's `vermagic` doesn't match the running kernel — you built
against one kernel and are loading against another, or Secure Boot
rejected an unsigned module.

### Fix

* Check: `modinfo rcraid.ko | grep vermagic` and compare to `uname -r`.
* If mismatched, rebuild: `sudo dkms remove rcraid/9.3.0-6.14 --all &&
  sudo dkms install rcraid/9.3.0-6.14 -k $(uname -r)`.
* If Secure Boot: sign the module with `kmodsign` and your MOK, or
  disable Secure Boot.

---

## `ld: cannot find ./rcblob.x86_64.o: No such file or directory`

### Cause

The Makefile created the `rcblob.x86_64.o` symlink in its `clean`
target, but DKMS skips `clean`. The link step fails.

### Fix

Already handled in this repo's Makefile: we added an `rcblob_pre`
prerequisite to `all` that creates the symlink. If you're building
manually, run `make clean` once before `make`.

---

## Read throughput stuck at ~19.7 GB/s with high parallelism

### Symptom

fio reports exactly 19.7 GB/s no matter what you raise. Lowering jobs
doesn't help.

### Cause

You're past the mdadm stripe-contention knee. With too many jobs or too
deep a queue, latency rises faster than throughput.

### Fix

Drop to the validated optimal profile:

```
--numjobs=4 --iodepth=64 --ioengine=libaio --bs=1M --direct=1
```

See [05-xfs-optimization.md](05-xfs-optimization.md) for the sweep tables.

Continue with [08-results.md](08-results.md).
