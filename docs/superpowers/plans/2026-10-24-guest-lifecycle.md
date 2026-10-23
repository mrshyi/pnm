# Actual CLI lifecycle acceptance

Continue from a fresh isolated guest using the verified native boot/scope gate,
official pinned offline assets and the corrected CLI source. Keep raw output
private. Do not mutate the WSL host or reuse a failed/uncertain installation.

- [x] Re-run the eight baseline installation/account checks with minimal PATH.
- [x] Repeat install must refuse before changing either Core's bytes, metadata,
  invocation, process, accounts, desired state or applied evidence.
- [x] Restart each Core through PNM; require its new invocation and applied
  binding, active/enabled state and unchanged runtime configuration. The peer's
  invocation, PID, binary/config/secret/unit bytes and applied record must remain.
- [x] Change only desired REALITY target to another reserved fixture value,
  confirm drift suppresses only its link, and apply Xray. Then deliberately
  replace only the fixture's HY2 desired password and apply HY2. Require actual
  config/applied binding and unchanged peer. Keep both existing listener ports.
- [x] Create a protected backup, retain its checksum separately, make a further
  configuration change, verify provenance and restore the original complete set.
  Check resource bytes/metadata, both actual processes and refreshed bindings.
- [x] Review implementation and record evidence for the stage commit.

No download, external traffic, automatic recovery across processes, uncatchable
crash or VM/kernel reboot is covered. Do not count same-version cache publication
as a real version upgrade; update/rollback and fault recovery need separate cases.
Persist a reusable explicit opt-in entry after the exercised cases are stable.

Review notes: HY2 masquerade also uses XRAY_SERVER_NAME, so independent Xray
acceptance changes only XRAY_TARGET. Host-side preparation must reject existing
guest leaf symlinks as well as symlink ancestors before writing into the clone.

The inherited baseline test unit actually has RuntimeMaxSec=80. Earlier full
attempts were terminated by this boot-only watchdog, including one interrupted
restore and one run that already reached check-restored. These do not establish
a production restore hang or a passing restore. The new clone alone now receives
a dedicated 390-second test unit, with guest cases capped at 300 and host at 420.
CLI timeout owns/retires its process group so inherited PIPE fds cannot extend
the wait indefinitely. Offline guards pass 5/5.

Final repository entry `make test-guest-mainflow` exits 0 in fresh
`/var/tmp/pnm-install-guest._slfzj2u`: all **14/14** cases pass, including restored
resource bytes/ownership/modes, both new real invocations and applied bindings,
link readiness and final diagnostics. Parent `boot-result.json` records both
boundary approvals, normal nspawn exit 0, no interruption, unchanged host
databases, not-found scope and no fixture mounts. The copied-source hashes and
protected raw evidence remain in that parent. Independent review found no
blocking issue in the final code. Python compilation and diff checks pass.
No production restore change was needed for the former 80-second interruption.
