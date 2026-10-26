# Native read-only publication failure plan

Continue T-22 from `f6f60ee`. Reuse official distinct versions, the guarded native
guest, real CLI transaction/compensation, and existing protected image retention.
No production functions are replaced. Follow the user-approved sequential stages.

Use a guest-only mv launcher: on exactly one matching .pnm-write publication,
enter a new private child mount namespace without changing the guest's mounts,
bind its protected Core-state parent onto itself, remount only that bind read-only,
verify a kernel EROFS probe, and invoke the real /usr/bin/mv. Verify its actual
read-only failure, remove only the recorded owned mount before returning the real
exit status, and allow PNM compensation to execute normally. All other moves
delegate unchanged. Validate mapped root, private network/namespace, path allowlist,
protected parents, mount identity and bounded commands; retain receipts. Never
mount/remount a host filesystem or unmount an unowned mount. This tests VFS
publication refusal, not physical media failure or power-loss durability.

Mount behavior source: [util-linux mount(8)](https://man7.org/linux/man-pages/man8/mount.8.html),
bind/remount section. A read-only bind changes the selected VFS view, leaving the
underlying filesystem writable after the owned bind is removed.

- [x] Add new guest-only context entry to the existing9 guards and observe RED.
- [x] Implement `guest_io_fault.py`, copy it only for the three new native cases,
      and add previous/metadata/applied scenarios to the existing update fixture.
- [x] For each Core and publication point, fail rollback from current to prior,
      verify resources/previous/binding/peer and terminal rollback, then swap to
      prior, fail update to current, verify the same, and swap forward again.
      Require real73 and stage-specific error, no commit, EROFS receipt, no mount.
- [x] Run guards, Python compilation, static gates, and three separate fresh
      native guests, one publication point per guest, with full encrypted images.
- [x] Review, refresh guide/TASKS, inspect staged/unstaged changes and commit.

Commit-journal/marker faults and earlier partial restore writes remain next local
stages. Independent VM/reboot, deployed identity and external clients stay open.

The missing fixture first fails the host guard; after implementation9 guards pass,
including direct launcher host refusal and unsafe-target refusal before actions.
Sixteen Python sources compile; syntax/security/ShellCheck pass. Independent
pre-execution review finds no blocker. Native execution is still pending; no
actual EROFS, mount or recovery pass is claimed from static review.

Initial native previous `2of0eycu` fails after18 successful preceding checks.
Control `/var/tmp/pnm-core-publication-previous-volume._fuk4tfd` verifies full
encrypted-image readback, detached loop, empty cleanup errors and unchanged host
DBs. Read-only extraction of its verified image confirms the launcher rejected
the existing guest mount propagation before mounting; the absent receipt then
raised FileNotFoundError. It does not count as EROFS acceptance. Run the matched
move in a separate private child mount namespace, record its distinct namespace,
retain propagation/identity checks, and diagnose missing receipts explicitly.

The namespace change's pre-execution review identified a parent cleanup fallback
using child mount IDs. Remove it: the parent only compares its namespace and
target mount rows with baseline; the creating child alone unmounts its bind.
Direct unmount entry now also refuses the host before actions. Review accepts
the corrected ownership boundary;9 guards pass and all16 Python sources compile.
The three final native cases run sequentially and stop on a failed case.

Final previous `x4aht50p`, metadata `kow46z9k` and applied `bfopszs1` each pass26/26,
including four real EROFS failure/recovery paths per guest. Controls
`/var/tmp/pnm-core-publication-previous-final-volume.w3fymwp8`,
`/var/tmp/pnm-core-publication-metadata-final-volume.1ztys_du` and
`/var/tmp/pnm-core-publication-applied-final-volume.tktrfinz` all verify full
encrypted-image readback, detached loops and no cleanup errors. Native/Make0,
unchanged host DBs, not-found scopes and no mounts hold for every final run.
Nine guards,16 compilations, syntax/security/ShellCheck pass; source review accepts
the corrected namespace ownership boundary. Product Bash is unchanged and the
31-suite/389-test baseline was not repeated. This does not close persistent media,
commit/marker, partial restore-write, VM reboot, deployed-host or external-client
acceptance.
