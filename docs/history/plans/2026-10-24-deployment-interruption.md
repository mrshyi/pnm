# Native whole-deployment process interruption

Continue T-19 after post-health acceptance commit3336d92. Reuse the existing
owned CLI Popen/session watcher and delayed start probe. Extract the watcher
without changing its target ownership checks; both standalone and deployment
tests must use the same bounded helper. Signal only the exact new CLI process
group after an actual service start attempt inside the mapped private guest.

TERM for each Core's initial startup must preserve143, compensate all original
resources/NSS/directories/services, retain APPLY_FAILED rc143 and no promotion,
then complete the normal14-case lifecycle. A separate fresh SIGKILL scenario
must retain the unfinished deployment, candidate resources and absent applied/
commit marker. After startup stabilizes and the fault is removed, apply/links/
show/check must refuse70 with empty stdout and no persisted/runtime mutation.
The SIGKILL scenario deliberately ends uncommitted and must explicitly state
that the full normal lifecycle was not run there.

- [x] Add watcher host-refusal regression and observe RED.
- [x] Reuse the watcher, extend guarded deployment cases and terminal scenario.
- [x] Compile/static/guard checks; fresh TERM and SIGKILL native evidence.
- [x] Review outcomes, retain private archives, update status and commit.

This proves catchable compensation and subsequent-process pending-state guards,
not kernel reboot/power-loss durability, automatic replay or external clients.

Offline RED lacks the extracted context entry; GREEN9/9 includes all host-entry
refusals. Thirteen Python sources compile and syntax/security/ShellCheck pass.
Independent source review accepts PID ownership, exception/thread cleanup, driver
imports and explicit terminal-result boundaries. Product source remains the
31-suite/389-test baseline; no redundant full rerun for this test-only increment.

Actual TERM `r7jlz938` passes16/16: both startup windows preserve143 and an outer
APPLY_FAILED rc143, complete rollback, then run the normal main flow. Initial
SIGKILL `kaiki853` passes5/5 and deliberately leaves the deployment unfinished.
Both retained images are under protected control/key
`/var/tmp/pnm-deploy-signal-volume.cz3yjtzb` plus the ignored D encrypted archive;
cipher/raw readback passes, loop detached, cleanup errors empty.

Add the explicit unresolved-deployment stderr assertion to exclude unrelated70.
An automatic approval review quota failure prevented the first final rerun; no
command ran and no review was bypassed. After user continuation, the retry was
approved and fresh `wetg5fc0` passes5/5 with the final assertion. Control/key
`/var/tmp/pnm-deploy-sigkill-final-volume.ppf6ot75` and its ignored D full-image
archive pass cipher/raw readback, loop detached and no cleanup errors. Each
native/Make exit0 records unchanged host databases, not-found scope and no mounts.
SIGKILL reports mainflow_completed=false/expected_recovery_required=true; false
recovered-baseline booleans are expected candidate state, not successful recovery.
