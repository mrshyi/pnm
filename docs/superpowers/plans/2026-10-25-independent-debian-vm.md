# Independent Debian kernel acceptance from the available WSL host

Continue the existing Phase3 VM/reboot gate after account deletion acceptance is
committed. WSL/nspawn results remain distinct from independent-kernel VM evidence.
Do not start Profiles, change VERSION, publish or use a production host.

Read-only preflight finds `/dev/kvm` with API12, approximately3.2GiB available
WSL memory and APT candidate metadata for QEMU, linux-image-amd64
and busybox-static. No QEMU executable, boot kernel or initrd is installed. This
does not yet prove a VM can be created or booted.

## Stage1: private trusted tooling and boot feasibility

- [x] Check an ephemeral empty KVM VM descriptor and release it; do not change
      host virtualization settings. Use one bounded VM at a time.
- [x] Use an isolated APT state/cache and explicit Debian13/trixie official
      sources with the installed Debian archive signing keyring. Verify signed
      metadata and package SHA256; retain exact package/version/hash manifests.
      Isolate APT_CONFIG, main/parts/preferences and Pre/Post-Invoke hooks before
      loading any system configuration; inspect the effective configuration.
      Download/extract tools and needed dependencies privately, without installing
      host packages or running package maintainer scripts. Verify host NSS/dpkg
      database hashes before/after preparation. Keep logs/state private.
- [x] Check the entire clean baseline's numeric UID/GID ranges and key file
      attributes before copying. Do not assume private-users ownership is
      unshifted and never replace all ownership with recursive chown0.
- [x] Build a minimal public-artifact initramfs using the trusted static busybox,
      cpio and required APT-authenticated kernel module dependencies. Boot the existing
      trusted clean Debian baseline on a newly owned anonymous D-backed ext4
      volume. Unmount host preparation before QEMU. Prefer an inherited anonymous
      file FD via QEMU fdset when supported; otherwise hold only the exact owned
      loop descriptor, with no concurrent host mount. Specify format=raw.
- [x] QEMU has no NIC, host directory shares, device passthrough or monitor;
      allow only the owned block device, bounded RAM/vCPUs and private serial IO.
      Explicitly set nodefaults/no-user-config, no NIC/monitor/QMP, disable guest
      memory core dumps and set the worker's core limit to0. Bind nonce, disk FD,
      QEMU PID/start identity and serial to the same boot.
      Validate the live process/drive identity and a one-use nonce handshake
      before any PNM mutation. A clean boot/poweroff is the first acceptance slice.
- [x] Preserve the established encrypted full-image readback, private evidence,
      exact mount/device/process cleanup and unchanged host databases. Review,
      update TASKS with exact results, commit the bounded boot/tooling slice.

## Stage2: real PNM lifecycle and independent reboot

- [ ] Extend only test guards for an authenticated QEMU boot marker; default host
      refusal and existing mapped nspawn guards must remain intact. Do not compare
      namespace inode numbers across kernels as proof of isolation.
- [ ] Reuse the existing actual CLI/Core assets and main-flow assertions inside
      the VM, then reboot that same guest. Require changed kernel boot_id and
      Core InvocationIDs, unchanged persisted applied records and withheld stale
      links before explicit verified apply. Confirm both recovered bindings.
- [ ] Run focused guards/compilation/static checks and independent review; retain
      full VM evidence and clean host boundaries, update status and commit.

## Stage3: bounded abrupt-VM interruption

- [ ] If boot and lifecycle are verified, terminate only the exact owned QEMU
      process at an observed pending-commit window, reboot its retained owned
      disk and verify on-disk uncertainty and fresh protected-command refusals.
      This is abrupt VM termination, not physical media/power-loss acceptance.
- [ ] Review remaining matrix positions against executed source/unit/native/VM
      evidence. Deployed identity G-01 and independent external clients still
      require authorized targets; do not infer them from local tests.

Preparation must stop and retain evidence on identity, signature, resource or
cleanup uncertainty. Missing software is a preparation task, not evidence that
WSL cannot support an independent guest kernel.

Initial `/var/tmp/pnm-vm-tools.s1a8keac` confirms API12 and successful empty VM
creation/close, with unchanged host NSS/dpkg hashes. The full numeric ownership
scan covers10,184 unshifted entries; key account/init bytes, modes and ownership
are also compared in the owned ext4 clone. Authenticated tooling preparation
passes38 archive verifications/extractions and runtime probes. Private initramfs
contains8 resolved modules; its host execution refuses77 before mount operations.
Independent plan review accepts the route with the APT/FD/default-device/ownership
constraints above. APT package authentication is not Secure Boot verification.

First attempt `pnm-vm-boot-volume.twmcogmx` fails before kernel entry because
legacy -drive auto-read-only needs an O_RDONLY fdset entry. The same failure is
reproduced on a small fresh anonymous file. Explicit file/raw -blockdev with
read-only=off,auto-read-only=off passes the paused-VM probe without changing file
locking. Its failed full image is encrypted/readback-verified and retained.
Fresh attempt `pnm-vm-boot-volume.n79xtpbb` boots kernel6.12.113+deb13-amd64,
reaches systemd running, passes the live owned-PID/disk/nonce handshake and
cleanly powers off with QEMU0. Full2GiB encrypted image readback matches the
original digest; loop detached, QEMU quiescent, host databases unchanged and
cleanup empty. Preboot guards12/12,20 Python compilations and static checks pass.
Later operator/extraction/initramfs code has self-review and executed checks;
independent review is unavailable after the review agent's usage limit.
Primary references: [KVM API](https://docs.kernel.org/virt/kvm/api.html),
[APT configuration order](https://manpages.debian.org/trixie/apt/apt.conf.5.en.html),
[QEMU options](https://www.qemu.org/docs/master/system/qemu-manpage.html).
