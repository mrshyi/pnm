# Fail closed on unobservable deployment marker

Continue T-17 from `236b566`. Current abort uses a shell existence test, whose
false result cannot distinguish a missing marker from an unavailable transaction
directory. Rollback callbacks can still run after the initial journal append
fails. Reproduce the behavioral consequence before modifying production code.

- [x] Add a real-filesystem/mocked-service regression: prepare a live deployment,
      publish and verify its real marker without the in-memory committed flag,
      rename only its private fixture transaction directory out of the tracked
      path, call abort and require no service controls or rollback callbacks.
      Require recovery70 and retained candidate/marker evidence. Observe RED.
- [x] Reuse the existing deployment marker helper for a checked probe: open the
      protected directory with O_DIRECTORY/O_NOFOLLOW, check its fd identity
      policy, and query the marker relative to the fd without following it.
      Exists/ENOENT/observation error are distinct; only known absence permits
      compensation. Unknown state retains recovery and original error reporting.
- [x] Run focused transaction/deployment tests, syntax/security/ShellCheck and
      the full existing check suite. Verify normal absence and present/uncertain
      marker behavior remain compatible. Repair only relevant fixture assumptions.
- [x] Independent review; rerun real publisher EROFS recovery to exercise the
      known-absent branch and retain verified native image/host/loop cleanup.
- [x] Update Architecture/TASKS with implemented behavior and exact evidence,
      inspect staged/unstaged changes, commit, then continue late commit acceptance.

The unavailable-directory test is private Linux filesystem evidence with service
mocks, not actual hardware EIO or VM reboot. No production services, unrelated
resources, protocols, firewall or release/version state may be changed.

RED confirms unavailable-directory service controls (22/1) and observer generic
failure authorizing rollback (23/1). Dedicated absence3 rejects generic Python1;
the observer-failure test saves its path before real transaction close resets it.
Final focused24/24 and full31 suites/391 tests pass, with syntax/security/
ShellCheck0 under `/var/tmp/pnm-marker-checked-records.s6pfj9_l`. Earlier private
source ancestor and test-assertion failures remain recorded in TASKS. Independent
final review finds no blocker. Final native `_w5ter13` passes15/15 under
`/var/tmp/pnm-marker-probe-final-native-volume.povfwhp2`, verifies complete encrypted
readback, detached loop, no cleanup errors, unchanged host DBs/not-found scope/no
mounts. Continue the separate late publisher SIGKILL plan after committing.
