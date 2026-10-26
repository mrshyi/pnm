# Actual restart evidence and consistency lock

Extend only the existing verified guest harness with a runtime-evidence scenario.
Production logic, CLI, schemas and host services remain unchanged.

- [x] Run the original14 actual installation/lifecycle/restore cases.
- [x] For each Core, restart via guest systemctl outside PNM. Require a new
  actual invocation, unchanged configuration/applied bytes and unchanged peer.
  Show/links must report unconfirmed state and withhold only the affected URI.
- [x] PNM restart may restart this service but must not promote stale evidence;
  only a subsequent fully validated PNM apply can rebuild its applied binding.
  Require both ready links and unchanged peer after explicit apply.
- [x] Hold the real global flock from the test process, then run a writer and
  protected link reader. Require cause-qualified lock refusal, no URI output,
  no resource/applied/process/transaction change. Release and prove normal
  operation resumes without a leaked lock.
- [x] Finish static/review and record evidence for the commit; compilation/offline
  and real cases pass. Container restart does not prove kernel/VM reboot behavior.

Fresh `/var/tmp/pnm-install-guest.j61dn9c1` passes19/19, Make exit0. Node links
must return0 with only the peer URI; node show returns78 and reports unconfirmed
target/ready peer. Stale PNM restart preserves all target resource/applied bytes;
explicit validated apply restores confirmed binding. The lock case also uses a
second independent FD to prove kernel contention, checks both rc73/empty stdout
and no new transaction/Core changes, then succeeds with the same commands after
release. This is a real held-lock collision, not all concurrent phase interleavings.
Host databases remain unchanged, nspawn exits0, scope not-found and no fixture
mounts remain. Two Python files compile and seven offline guards pass. No
production code changed; the existing default31/370 result is not rerun.
Syntax/security/ShellCheck exit0 and independent review finds no blocking issue.
