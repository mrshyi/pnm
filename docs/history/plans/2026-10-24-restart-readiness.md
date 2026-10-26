# Ordinary restart runtime-readiness repair

Continue the adjacent confirmed source gap after recovery commit54d5d67.
Ordinary restart currently uses only systemd active/enabled health before binding
and success. Type=simple may be active before its real Core listener exists.
Reuse the new runtime-port readiness helper in a restart health callback before
the existing service policy check. Keep failure78 and the shared compensation
path; no additional restart, CLI change or new transaction mechanism.

- [x] Add focused RED for absent/error forward listener with successful recovery.
- [x] Implement the small callback and add guarded real CLI delayed-start cases.
- [x] Run focused/default/static/guard checks and fresh dual-Core native scenario.
- [x] Review, retain private evidence, update status and commit.

Actual native assertions use TCP443/UDP8443 at CLI return, changed invocation,
correct applied binding, identical target resources, one startup attempt and peer
preservation. This covers ordinary restart; deployment and recovery retain their
independent gates. External clients and independent VM/kernel reboot remain open.

Focused RED `/var/tmp/pnm-restart-ready-red.iafk106w` runs the new case only:
0 pass/1 fail because the old forward gate reports success. GREEN frozen source
`/var/tmp/pnm-restart-full.21i4fnot` passes that case, including both Core protocols
and absent/error observations with completed recovery. Nine offline guards fail
before the new guest entry exists, then pass after its mapped-root guard is
implemented; eleven Python sources compile. Full/default/static and native
`/var/tmp/pnm-restart-volume.1yzaosbh` remain in progress at this checkpoint.

Review identified that forward restart may have unknown prior applied evidence,
so the helper also needs its own regular/readable/non-symlink leaf guard before
parsing HY2. Safe RED `/var/tmp/pnm-restart-path-red.jsuudf6f` returns timeout124
for the old FIFO path rather than70 (0/1). Add the existing-style file type guard;
renderer GREEN passes15/15, including both Core FIFO/symlink refusal without
observer calls. Review accepts the correction. Initial regular-file native
`ypttmsha` passes16/16 before that final guard; final exact behavior is rerun in
`/var/tmp/pnm-restart-final-volume.d52dqp7n`, alongside final full source
`/var/tmp/pnm-restart-final.mkb7hk8r`. Final results below supersede that checkpoint.

Final source passes static checks, nine guards, renderer15/15 and default
`make check`:31 suites/385 tests, exit0. Earlier pre-type-guard full baseline
also passes31/384 but is not the final result. Final native `7xhrrhf0` passes16/16,
including actual ordinary delayed restarts for both Cores. Native/Make exit0,
unchanged host databases, not-found scope, no mounts. Protected control/key/results
under `/var/tmp/pnm-restart-final-volume.d52dqp7n` and the existing ignored D pool's
encrypted full image pass trusted cipher/raw readback verification; loop detached,
cleanup errors empty. Initial regular-file success evidence is retained separately.
Independent review's file-type blocker is resolved and re-reviewed; the helper
comment now distinguishes ordinary runtime inspection from hash-verified recovery.
