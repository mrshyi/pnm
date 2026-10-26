# Native restore interruption implementation plan

Continue T-19/T-24 from `a2f8654` under the user's consecutive-stage authorization.
Reuse the existing mapped native guest, official Cores, trusted backup, start
delay and exact owned CLI/session signal watcher. No production hooks or host
service changes. Implement inline with review checkpoints.

Restore owns both Cores: TERM at either startup must retain143, restore every
original resource and directory tuple, preserve NSS and previous state, refresh
both bindings against recovered invocations, and close ROLLED_BACK without a
commit. Then retry the trusted archive successfully. Separate SIGKILL Xray/HY2
fixtures must show published archive resources, old applied records, an unfinished
core-restore journal, and expected actual active/inactive service generations.
After removing the fault, apply/links/show/check must refuse70 with the exact
unresolved operation and no output or state change. Initial mainflow completion
and interrupted restore matrix completion are reported separately.

- [x] Add host-refusal entry to `test_guest_mainflow_guard.py`; run9 guards and
      observe the missing restore entry fail before implementing it.
- [x] Add `run_restore_interruptions` to `guest_signal_cases.py`; wire three
      scenarios into the existing driver and case dispatcher. Reuse fingerprint,
      start-fault, signal watcher and protected-command assertions.
- [x] Run nine guards, compile integration Python, syntax/security/ShellCheck;
      run fresh TERM and two SIGKILL native guests. Retain full encrypted images
      with verified readback, detached loops, no mounts and unchanged host DBs.
- [x] Independent review, refresh TASKS and the integration guide, inspect staged
      and unstaged diffs separately, commit only this stage, then continue.

Storage/commit IO faults, earlier partial-file publication, independent VM kernel
reboot, deployed-source identity and external clients remain separate boundaries.

Initial TERM `78z29jw3` passes17/17 with verified retained image under
`/var/tmp/pnm-restore-term-volume.hcfa56al`. Initial SIGKILL Xray `2ngevftq`
fails the HY2-inactive assertion: Type=simple returns before the delayed ExecStart
probe, allowing the next restart before watcher delivery. Failed control
`/var/tmp/pnm-restore-sigkill-xray-volume.8_hd28ny` verifies full encrypted-image
readback, detached loop and no cleanup errors. It is not acceptance evidence.

Add a guarded `delay-pre` mode to the existing start fixture, preserving real
ExecStart/Type while holding systemctl in ExecStartPre. Invalid delay/type checks
first fail on the absent mode, then all9 guards pass. Fresh final TERM and both
SIGKILL cases rerun with this bounded blocking window and post-signal service
assertions; a missed window must fail, not be accepted. Old results stay separate.

Final TERM `_o0lwh5i` passes17/17; SIGKILL Xray `npkl6xla` and HY2 `k844uu2j`
each pass16/16. Respective controls `/var/tmp/pnm-restore-term-final-volume.u3wg8v9z`,
`/var/tmp/pnm-restore-sigkill-xray-final-volume.u6y5tp_5` and
`/var/tmp/pnm-restore-sigkill-hysteria2-final-volume.1b9imypr` all verify full
encrypted-image readback, detached loops and empty cleanup errors. Every final
native/Make exit0 retains unchanged host databases, not-found scopes and no
fixture mounts. Final fifteen Python sources compile;9 guards pass. Independent
reviews accept the window repair and report boundaries. Product Bash is unchanged;
the31-suite/389-test baseline was not rerun for this test-only stage.
