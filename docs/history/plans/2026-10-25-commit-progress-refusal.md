# T-16: derived progress refusal after durable deployment commit

Continue the authorized Phase3 acceptance work using the existing transaction
engine and private Debian VM. Production code and public CLI remain unchanged.

The L1 test already replaces journal append with a refusal. This stage instead
keeps the actual publisher and Bash append: launch only the install CLI in its
own private mount namespace, observe the return from its final directory fsync
after uncertainty removal, and bind its regular journal read-only there. The
caller Bash then encounters an actual kernel EROFS appending derived progress.
Neither the guest manager's namespace nor the host receives the bind mount.
The namespace and its mount disappear when that owned CLI exits. A block-device
fault framework is unnecessary for this narrow append-error assertion.

- [x] Add host refusal regression before implementing the observer/helper.
- [x] Reuse the guarded publisher arguments/identity and real stdin execution;
      never replace product fsync, rename, unlink, append or service functions.
- [x] Validate owner/mode/inode, private mount propagation, distinct CLI mount
      namespace and exact new mount identity. Probe real EROFS; retain only safe
      structured diagnostics in protected evidence.
- [x] Require install0 with the committed-journal warning, valid authoritative
      marker, no uncertainty or rollback promotion, journal ending COMMIT_INTENT,
      unchanged parent mounts, both real applied-bound Core generations and fresh
      protected commands that can proceed. Run the existing14-case lifecycle.
- [x] Reboot the same private VM disk, run the existing stale-link/reconfirm
      checks, verify full encrypted image readback and exact process/mount cleanup.
- [x] Run focused guards, Python compilation and relevant static checks; review
      and update TASKS, then locally commit before the next remaining slice.

This proves real post-commit journal append EROFS in an isolated Linux namespace,
not real-device EIO, physical power loss or every cleanup/logging failure. Keep
G-01, external clients and the remaining acceptance matrix explicitly separate.

Executed `pnm-vm-boot-volume.q9afkgcu`: actual journal append EROFS keeps install0
and valid marker/no uncertainty, normal14-case lifecycle and7 reboot checks pass.
Full2GiB encrypted readback matches; loop detached, QEMU quiescent, host databases
unchanged and cleanup empty. Guards21/21 and23 integration compilations pass;
static checks pass. Host refusal and trace-return regressions have recorded RED
runs before GREEN. The independent reviewer remains usage-limited; self-review
and actual validation are recorded without claiming independent approval.
