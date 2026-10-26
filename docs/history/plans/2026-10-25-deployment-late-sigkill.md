# Native late deployment publisher SIGKILL acceptance

After the marker-observation fix is committed, continue T-17/T-19 in the existing
private Debian guest. This is process interruption, not power loss, media failure
or independent-kernel reboot acceptance.

- [x] Add guarded entries and a focused observer-filter test; observe RED before
      implementation. Reuse the strict deployment publisher argument/identity
      matcher and exact owned CLI process-group signal helper.
- [x] Run the unchanged publisher stdin with a narrowly scoped interpreter trace.
      At the real post-rename `sync_directory` call, require both marker and
      uncertainty record, persist a safe receipt and pause for at most30 seconds.
      Do not replace filesystem APIs or simulate rename/fsync return values.
- [x] Deliver SIGKILL only to the recorded live CLI SID/PGID. Require real -9,
      unique COMMIT_INTENT, both applied records, both live enabled generations,
      retained valid marker plus uncertainty record, and no COMMIT/rollback.
- [x] Remove the observer PATH scope, then run four fresh real protected commands.
      Require70, no protected stdout and no persisted/runtime/resource mutation.
      Retain the intentionally unresolved guest rather than retrying or repairing it.
- [x] Run offline guards, Python compilation and relevant static gates; obtain
      independent read-only review. Run a fresh isolated native guest, verify full
      encrypted-image readback and exact host/namespace/loop cleanup, update TASKS
      and acceptance guidance, inspect/stage only this increment and commit.

The pause must match a real call after successful rename and before that call's
directory fsync. Its focused offline test proves filtering only. Native evidence
must separately establish the actual publication window and runtime state.

RED guards fail for the missing module. Final11 guards and18 Python compilations
pass (`pnm-late-final-guards.c29x7w2a`), static gates0 (`pnm-late-static.h7903px8`).
Independent pre-execution review finds no blocker. A complete root0600 bounded
JSON receipt authorizes the signal, preventing partial-write/existence races.
Native `kx7wcwuz` passes6/6 under
`/var/tmp/pnm-late-commit-sigkill-volume.tsq9luc1`; realCLI-9, valid product-verified
marker plus pending, no finalization, both live bound listeners and four fresh
refusals without mutation. Native/Make0 retains unchanged host DBs, not-found
scope/no mounts, verified full encrypted-image readback, detached loop and no
cleanup errors. Product Bash is unchanged;31/391 remains the full baseline.
