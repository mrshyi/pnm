# Native first-deployment Core startup failure acceptance

Continue T-09/T-10 after dependency-matrix commite726f17. Reuse the clean private
guest, existing one-shot real service start probe and actual install CLI. A
separate VM or fake Core would add setup or miss systemd's failed-state behavior.
Before the normal14-case lifecycle, reject Xray's first start, then HY2's first
start after Xray activation. Each actual deployment must retain its initiating
failure, compensate all changed managed resources and account/directory/service
baselines, leave node unconfigured with no applied/commit promotion, and end in
ROLLED_BACK rather than recovery uncertainty. Remove only the owned fault and
prove the next operation/retry works without resetting any PNM evidence.

Capture safe event/status/recovery booleans before assertions so a failure can
be diagnosed from retained private evidence without exposing secrets. The test
fixture must not clear failed units or otherwise repair PNM's recovery itself.

- [x] Add guarded guest entry and observe offline RED.
- [x] Implement source-independent startup-failure assertions and run native RED/GREEN.
- [x] If a defect is reproduced, add focused regression, fix the shared cause and run applicable full/static checks.
- [x] Review final native evidence, update status, retain archives and commit.

Existing update/restore failures and late-deadline deployment compensation are
separate evidence. Other publication/interruption positions, VM reboot and
external clients remain open. Never use production nodes for these fault cases.

Offline guard RED misses the new helper; GREEN9/9 and thirteen Python sources
compile. Real RED `7ivqzpmd` rejects Xray once, restores authority/NSS/directories,
removes applied/commit promotion, but leaves not-found Xray in failed/PID0 while
the transaction says ROLLED_BACK. Safe observations and full encrypted evidence
are retained under `/var/tmp/pnm-deploy-start-volume.kscv56k1`; cipher/raw readback
passes, loop detached and cleanup errors empty. This is a real recovery defect.

Focused initial RED `pnm-deploy-stop-red.tx0w8vr0` fails the reset assertion0/1.
Expanded RED `pnm-deploy-stop-audit-red.lahpau75` fails all3 deployment absence/
compensation cases and the verified-stop adapter case0/1. Extract restore's
existing failed-state normalization into the systemd adapter and reuse it from
deployment and restore. Missing-unit predicates explicitly capture query exit
status before checking inactive/PID0; use them before writes and in recovery.
Do not reset an unowned preexisting missing/failed unit.

Focused GREEN `pnm-deploy-stop-green.y1jaz9wj` passes deployment22/22,
lifecycle9/9, restore-recovery12/12, restore-flow17/17 and deploy8/8. The first
restore-flow run exposed its missing adapter import (12 pass/5 fail); add the
real module, retaining real stop/reset semantics. Final review accepts that fix
and ineffective reset/failing-query tests. Full frozen source
`/var/tmp/pnm-deploy-start-full.j0rp4aah` and fresh native control
`/var/tmp/pnm-deploy-start-green-volume.xowihu1c` are running at this checkpoint.

Fresh GREEN `4n7nub1u` passes16/16: both actual first-start failures now restore
not-found/inactive/PID0 and all authority/NSS/directory baselines, record completed
rollback and no commit/applied promotion, then the complete main flow passes.
Native/Make exit0, unchanged host databases, scope not-found and no mounts. The
full image under control/key `/var/tmp/pnm-deploy-start-green-volume.xowihu1c`
and the ignored D pool passes cipher/raw readback verification, loop detached,
cleanup errors empty. Both safe observations are also retained in the control dir.

First full source `j0rp4aah` passes388/fails1 across31 suites: the sandbox shared
deployment fixture also lacked the real adapter import and returned InvocationID
for MainPID. Add the actual module and correct the per-property fixture response;
its12/12 tests and static-final pass. Independent review accepts the import fixes
without stubbing the new stop/absence helpers. Final full rerun passes:
**31 suites/389 tests, exit0**, with static-final and nine guards passing. This
completes the startup-failure slice; actual post-health listener absence, other
publication/interruption positions and independent VM/external acceptance remain.
