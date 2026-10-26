# Native deployment post-health listener refusal

Continue T-11 after startup recovery commit08b4a6c. Reuse the existing delayed
real ExecStart probe with a validated12-second delay, exceeding the existing
5-second readiness window. Keep the3-second default unchanged. Do not replace
Core binaries, validators or systemd observations. Both lifecycle phases must
finish before the actual post-health phase refuses78 for the selected Core.

Reuse the first-deployment recovery assertions for both TCP/Xray and UDP/HY2:
authority/NSS/directory/service baseline restored, no applied/commit promotion,
completed rollback, then normal14-case lifecycle. The fixture must not repair
PNM state. Bound delay inputs before command/file operations; never interpolate
unvalidated input into generated program text.

- [x] Add invalid-delay refusal regression and observe RED.
- [x] Extend only the guest probe/cases/driver and validate offline checks.
- [x] Run fresh dual-Core native post-health failures and retain evidence.
- [x] Review, update status and commit; keep VM/external boundaries open.

Offline RED misses the new delay argument; GREEN9/9 rejects zero/out-of-range,
string, bool, float and None before command/file actions. Thirteen Python files
compile, syntax/security/ShellCheck pass. First `1wxctimg`16/16 proves phase/Core
failure and compensation; its verified encrypted image under control
`/var/tmp/pnm-deploy-listener-volume.c66y0ilu` is retained as earlier evidence.

Review required direct causal observations. Add specific Core check failure,
bounded active/port observer and a monotonic first-accept timestamp. Require
the CLI to return before first-accept+11.75 seconds, while the managed wrapper
cannot exec before ack+12 seconds. Observer errors fail; finally retires its thread.
Fresh `yex496qc` passes16/16 with active/absent-listener observations and preserved
delay window true for both Cores, original78, complete rollback and clean retry.
Native/Make exit0, unchanged host databases, not-found scope and no mounts.
Protected control/key/results `/var/tmp/pnm-deploy-listener-final-volume.eilh3c60`
and the ignored D pool's full image pass cipher/raw readback verification, loop
detached and cleanup errors empty. Final independent review has no blocking issue.
Product Bash is unchanged from the31-suite/389-test baseline; no redundant full
rerun. This is controlled startup delay in the private WSL guest, not VM reboot
or external-client acceptance.
