# T-15 uncertainty record ENOSPC checks

After the candidate ENOSPC stage is verified and committed, reuse its exact
bounded child tmpfs and unchanged publisher. Complete the earlier uncertainty
record positions without a fresh VM or changing any product API.

- [x] New pending-create and pending-write cases first fail on unknown phase.
- [x] At the original pending-file open, exhaust only the tmpfs inodes; require
      actual ENOSPC73, absent pending/marker/candidate and original records intact.
- [x] At its empty regular root0600 FD, exhaust only data blocks; require actual
      ENOSPC73, an empty incomplete pending record, absent marker/candidate and
      original records intact. Do not call this empty record durable uncertainty.
- [x] Re-run both established candidate cases, guards, compilation, static and
      cleanup/parent/host checks. Preserve the earlier fresh full Bash baseline.
- [x] Update evidence boundaries and locally commit the completed stage.
- [x] Reject an incorrect supplied parent namespace before mutation by checking
      the actual live parent namespace; retain RED and final four-case GREEN.

The observer records real kernel failures, not replaced os.open/write results.
This is synthetic-record publisher evidence, not complete deployment rollback,
independent-kernel storage acceptance or physical-device failure.

Evidence: unsupported-phase RED `pnm-pending-storage-red.t92zj6b_`, four-case
GREEN `pnm-pending-storage-green.4c05vhie`; caller-supplied parent-number RED
`pnm-storage-parent-red.ygcq6jxd`; final four actual cases/28 guards/nobody guard/
24 compilations/static gates `pnm-storage-parent-green.39wbf1nm`.20 document
paths pass. The initial parent-number RED still stops at the separate propagation
gate with mutation functions forbidden; it is not evidence that a host mount
occurred. The final worker checks the actual live parent's namespace before any
mutation. The preceding31/394 full Bash result is unchanged, not re-executed for
this test-only extension. Independent reviewer remains usage-limited.
