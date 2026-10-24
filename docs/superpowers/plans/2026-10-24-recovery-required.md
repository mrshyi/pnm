# Preserve uncertainty after failed service recovery

Continue the existing Phase 3 update/restore acceptance. Reuse the current
transaction implementation and private Debian guest; do not add recovery replay,
change the public CLI, or perform host/production service operations.

- [x] Reproduce whether update/rollback records the initiating failure separately
  from a recovery failure. Extend the existing real-journal focused regression
  before changing the abort helper, then preserve the original return code and
  existing recovery-required gate. Run focused, static and full checks; commit.
- [ ] Extend the owned start-fault probe to reject both the operation start and
  compensation start. Keep the namespace, ownership and bounded cleanup gates.
- [ ] In fresh guests, exercise failed rollback recovery for each Core after
  the distinct-version update trajectory. Check restored binary/previous bytes
  and numeric metadata, failed target service, unchanged peer and applied record,
  exact original/recovery error codes, and retained uncertain transaction.
- [ ] Exercise a restore failure whose compensation also cannot restart HY2.
  Check recovered resources without claiming fully recovered service state.
- [ ] After removing the owned probe, real subsequent writes and protected reads
  must still refuse with empty stdout, without changing files, receipts, service
  state or peer. Removing a fault must never erase recovery evidence.
- [ ] Validate fresh guest results, independently review and commit each slice.

No automatic transaction deletion, manual service recovery, cross-process replay,
kernel reboot or external-client acceptance is implied. Preserve private raw
logs; ordinary output contains only static assertion labels and safe state.

Execution detail for the next native slice: `core-recovery-failure-xray` and
`core-recovery-failure-hysteria2` reuse the distinct-version22-check trajectory,
then fail both starts of a real rollback. Require original1/recovery70, restored
binary/previous bytes and numeric metadata, retained applied bytes, failed target
with MainPID0, unchanged peer and one RECOVERY_REQUIRED transaction. After removing
the owned fault, repeat real writer/protected-reader refusals with empty stdout
and unchanged state/receipts. Expected24 checks per fresh guest; no receipt is
deleted or reclassified to prepare a subsequent case.

The restore counterpart must distinguish the recovered Xray generation from HY2's
failed compensation: both ordinary resource baselines recover, Xray may receive
a newly confirmed invocation, HY2 must not be certified, and the unresolved
transaction continues to block commands. Do not assert complete service/directory
recovery when the callback has stopped early.

Disk checkpoint: two stopped successful rootfs copies have separately verified
private retained-evidence bundles and cleanup-review.json manifests. Their rootfs
paths are `pnm-install-guest.mkmrfpdx/rootfs` and `pnm-install-guest.jkja5d_v/rootfs`
under `/var/tmp`; logical sizes513225820 and1043038092 bytes. Deletion requires the
pending explicit user decision because the guide retains fixtures for review.
Do not treat elapsed time or a generic continuation as that cleanup approval.

First slice verification: RED37/1 with original_rc0; GREEN38/38 with original78/
recovery70, then syntax/security/ShellCheck and default31 suites/380 tests pass.
Independent source review approves the one-line shared abort-entry repair. The
remaining native slices wait for the explicit disk-retention decision.
