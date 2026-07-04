---
name: Bug report
about: Driver build failure, RAID setup problem, performance regression, or crash
title: "[bug] "
labels: ["bug", "needs-triage"]
assignees: []
---

## Summary

<!-- One or two sentences: what went wrong and what you expected instead. -->

-

## Path affected

<!-- Check one. -->

- [ ] **rcraid DKMS** — driver does not build / load / see the BIOS array
- [ ] **mdadm RAID0** — array assembly, XFS, or mount problem
- [ ] **Performance** — throughput / IOPS far below expected
- [ ] **Documentation** — incorrect or unclear instructions
- [ ] **Other**

## Environment

<!-- These are mandatory for build/RAID/performance issues. Paste real output. -->

**Kernel and distro:**

```text
$(uname -a)
$(lsb_release -d 2>/dev/null || cat /etc/os-release | grep -E '^(NAME|VERSION)=')
```

```bash
# Run this block and paste the output verbatim.
uname -a
lsblk -o NAME,SIZE,MODEL,SERIAL,MOUNTPOINTS
lspci -vv | grep -E 'Non-Volatile|LnkSta|LnkCap'
```

**CPU / chipset / platform:**

```text
CPU:
Chipset (X570 / TRX40 / WRX80 / WRX90 / ...):
PCIe card (if any, e.g. ASUS Hyper M.2 x16):
Number and model of NVMe drives:
```

**rcraid setup (if applicable):**

```bash
dkms status
dmesg | grep -iE 'rcraid|nvme|iommu|xfs|md0' | tail -n 50
```

**mdadm setup (if applicable):**

```bash
cat /proc/mdstat
mdadm --detail --scan
```

## Steps to reproduce

1.
2.
3.

## Expected behavior

<!-- What you thought would happen. -->

## Actual behavior

<!-- What actually happened. -->

## Logs / error output

```text
# Paste the full error (compiler output, dmesg, fio stderr, ...).
# For build failures, include the full `make` / `dkms build` log.
```

## Benchmark output (for performance issues only)

```bash
# Which fio profile did you run? (fio/*.fio)
# Paste the fio summary line(s), not the whole run.
```

## Checklist

- [ ] I have read [docs/07-troubleshooting.md](../../docs/07-troubleshooting.md) and it did not solve my issue.
- [ ] I have searched the existing issues for duplicates.
- [ ] My boot disk is **not** part of the RAID array (separate CPU-attached NVMe / SATA).
- [ ] I have a full backup of any data on the drives I am reporting about.
