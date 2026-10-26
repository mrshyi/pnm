# Native preexisting service-account acceptance

Continue T-08/G-06 within the user's authorized sequential local acceptance.
Reuse the private native guest and existing deployment-failure/lifecycle cases.
Mock NSS would miss real identity deletion; a new VM framework adds no value.
Create valid nonzero UID/GID system identities only after the mapped native guest
guard and clean baseline pass. Preserve complete passwd/group/shadow/gshadow
fingerprints across preview, dependency refusal, late-deadline compensation and
normal install/restart/apply/restore. Require empty account ownership receipts:
PNM must not claim or delete the preexisting identities. Verify actual processes
still run under those exact UIDs/GIDs. No host identity or product code changes.

- [x] Add guarded helper's offline refusal check and observe RED.
- [x] Extend the existing driver/cases minimally; compile and run offline guards.
- [x] Run fresh account-reuse scenario; retain native evidence and cleanup checks.
- [x] Review, reconcile status/plans and commit exact files.

This covers valid reuse and late rollback, not arbitrary NSS corruption or
account-tool failures. Independent VM reboot and external clients remain open.

Offline RED ran nine checks with the intended missing-helper failure. GREEN
passes9/9; ten Python sources compile and syntax/security/ShellCheck pass.
Independent review found no blocking issue. Fresh `ecwu2gy_` completes18/18,
including real late-deadline compensation/retry and the full lifecycle with
unchanged preexisting NSS files and empty created-account ledgers. Native/Make
exit0, host databases unchanged, scope not-found, no fixture mounts. Private
control/key/results are under `/var/tmp/pnm-account-volume.k93z09hb`. The full
image `pnm-account-volume.k93z09hb.ext4.gz.enc` in the existing ignored D pool
passes trusted cipher and complete raw-image readback hash verification. The
loop is detached and cleanup errors are empty. Retain the protected control
directory with that archive. Product source remains the31-suite/380-test baseline.
