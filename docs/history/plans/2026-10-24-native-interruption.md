# Native standalone Core interruption acceptance

Continue existing T-19/T-25 using the private guest and14-case lifecycle, then
interrupt only the new CLI child/session owned by this test. Use the existing
guest-only delayed real ExecStart probe to observe that restart has changed the
service invocation before signalling. A bounded watcher receives the exact Popen
object from the existing call helper and verifies PID/session/group ownership;
it must never discover a target by name or signal a host process.

TERM should preserve143, complete rollback, restore resource bytes/metadata,
refresh the old confirmed configuration binding and keep the peer unchanged.
After healthy link/read checks, SIGKILL should preserve the interrupted disk
journal and prior applied bytes without claiming rollback/commit. Once the real
Core listener stabilizes and the test drop-in is removed, a new writer and all
protected readers must refuse70 with empty stdout and unchanged persisted state.
Use the existing unresolved-journal guard; no automatic recovery or product hooks.

- [x] Add offline host-refusal regression and observe RED.
- [x] Implement the minimal guest scenario; compile/static/guard checks.
- [x] Run fresh native TERM/SIGKILL cases and retain private verified evidence.
- [x] Review actual outcomes, update status and commit.

This is process interruption with real systemd/Core behavior; independent kernel
reboot, other interruption windows and external traffic remain separate.

First native `12ve6uhl` stops at a test assumption: TERM preserves143 and records
complete rollback, but lifecycle recovery legitimately retains an already-active
process rather than starting it twice. Its encrypted evidence under private
`/var/tmp/pnm-signal-volume.gg2si3i8` is verified, loop detached and cleanup empty;
it is not a passed interruption case. The revised assertion checks real TCP
readiness at call return, correct binding and peer state, allowing either valid
service-start count.

Source review exposes a separate recovery defect: standalone shared recovery
rebinds an active Type=simple invocation before its listener is ready. Focused
RED `/var/tmp/pnm-recovery-listener-red.zoeoahfk` rejects neither missing/unknown
listener nor a configuration edit during waiting. Both new cases fail. Renderer
RED `pnm-runtime-port-red.cwe0i6h4` passes13/fails1 before the shared helper exists.
Extract deployment's existing runtime-port wait into render.sh; reuse it from
standalone recovery and deployment, then recheck active/config/applied baseline
after waiting. Restore already shares standalone recovery. Preserve disabled
baselines, original runtime ports and unavailable-tool failure propagation.

Focused GREEN `pnm-recovery-listener-green.xz5yrtts` passes renderer14/14 and
Core evidence40/40 (RED38/2). Final native `gljriftj` passes17/17: TERM returns143
with a real listener ready at return and a correct recovered binding; SIGKILL
retains prior applied bytes/unfinished disk journal, and all four protected
commands refuse70 without mutation after fault removal. Native/Make exit0,
unchanged host databases, scope not-found, no mounts. Protected control/key/results
are under `/var/tmp/pnm-signal-green-volume.37po60eo`; its full encrypted image
in the existing ignored D pool passes cipher/raw readback verification, loop is
detached and cleanup errors are empty. Independent review accepts the repair.

First full frozen `pnm-recovery-full.m_tn0a5p` records31 suites/378 pass/5 fail.
One old direct-helper fixture had an inactive HY2 baseline despite testing active
recovery; four restore-flow failures used label-only configs with simulated
services. Correct those fixture boundaries, keeping real helper parser and
observer behavior in render/core-evidence tests. At that checkpoint a full rerun
was pending; static-final and nine guards passed. Initial failure log is retained.

The second full run records382 pass/1 fail: the intended HY2 fixture-state change
had matched the adjacent preparation block. Move it into the named runtime-port
fixture; that complete deployment suite passes19/19. Both failed full logs
are retained and a final full rerun then began. The native signal helper is
also parameterized for a fresh HY2 UDP case, with the same PID ownership and
peer-preservation checks; Xray's retained GREEN is unchanged evidence.

Final `make check` succeeds:31 suites/383 pass/0 fail, exit0. The accurately fixed
deployment suite passes19/19; static-final, current nine guards and compilation
also pass. HY2 `8itir9ca` passes17/17 with unchanged host databases, nspawn0,
not-found scope and no mounts; protected storage control is
`/var/tmp/pnm-signal-hy2-volume.o83q9afv`. Its full image in the existing ignored
D pool passes cipher/raw readback verification, loop detached and no cleanup
errors. Retain both protected control directories with their encrypted archives.

The ordinary restart forward health gate also checks only systemd state; track
that adjacent path separately rather than claiming this recovery repair fixes it.
