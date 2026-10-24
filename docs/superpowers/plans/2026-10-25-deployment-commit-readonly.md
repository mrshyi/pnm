# Native deployment commit publisher EROFS plan

Continue T-15 from `4206f2e`. Reuse the protected real native guest and the tested
private-child read-only bind. No product code hooks or synthetic IO return values.

The python3 launcher delegates normally except the exact deployment publisher
invocation. Validate its canonical protected tx-ID path, schema2 deployment
metadata and COMMIT_INTENT before entering a new private child mount namespace.
Run the unchanged real publisher stdin under a read-only transaction directory.
A scoped sitecustomize trace observes the real OSError errno/path because product
diagnostics deliberately retain only a fixed message. The observer must not
replace file APIs or alter exceptions/results. Record only safe errno/boolean data.
Remove only the creating child's bind, return the real73, verify whole first-
deployment compensation and permit a complete normal install/lifecycle retry.

- [x] Add new context/child/bind host-refusal entries to the guards and observe
      RED before implementation; add a focused observer forwarding/filter check.
- [x] Extract the existing read-only bind into one guarded shared context without
      changing move semantics; add a separate commit launcher and strict matcher.
- [x] Reuse deployment baseline/NSS/directory/unit recovery checks in a single
      commit-failure variant. Require real73, COMMIT_INTENT, both applied writes,
      post-health completion, actual pending-file EROFS, no marker/uncertainty,
      terminal rollback and a full healthy retry; preserve startup variants.
- [x] Run guards, compile/static gates, fresh commit publisher case and a fresh
      restore-publication regression for the refactored move/bind path; retain
      verified full encrypted images and exact host/namespace/loop cleanup.
- [x] Independent review, refresh TASKS/guide, exact stage/unstage inspection and
      commit; continue the remaining commit/post-publication safety matrix.

This pre-publication refusal is separate from marker rename/fsync uncertainty,
persistent media errors, independent VM reboot, G-01 and external clients.

Reference: [Python3.13 trace events](https://docs.python.org/3.13/library/sys.html#sys.settrace).
The observer's focused test uses synthetic exceptions only to check filtering and
unchanged control flow; it is not kernel IO acceptance. Missing entries first fail
the suite, then10 offline guards pass,17 Python sources compile and static gates
pass. Independent pre-execution review accepts stdin, observer scope and mount
ownership. Native results are recorded below.

Final publisher `fkorwxid` passes15/15 under
`/var/tmp/pnm-deployment-commit-readonly-volume.3yn9k7x9`: real pending-file
EROFS30/publisher73, full rollback with no marker/uncertainty/applied residue,
and healthy complete normal-flow retry. Shared-bind restore regression `mtixk7f7`
passes16/16 with4 of12 ordinary resources published first, under
`/var/tmp/pnm-restore-publication-volume.50mysyr7`. Both native/Make0 retain
unchanged host DBs, not-found scopes and no mounts; both full encrypted images
verify readback, detached loops and no cleanup errors. Ten guards,17 compilations
and static gates pass. Product Bash is unchanged, so the31/389 baseline was not
repeated. Later marker/rename/fsync and persistent-media boundaries remain open.
