# Preserve uncertainty after failed service recovery

Continue the existing Phase 3 update/restore acceptance. Reuse the current
transaction implementation and private Debian guest; do not add recovery replay,
change the public CLI, or perform host/production service operations.

- [ ] Reproduce whether update/rollback records the initiating failure separately
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
