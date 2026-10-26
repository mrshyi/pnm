# Renderer local-array scope repair

Trigger: actual offline-cache PNM installation in the isolated booted Debian guest
passes init/validate/preview, creates managed resources, then fails during real
post-health. `pnm_check_deploy_core_health` passes local reality/hysteria arrays
through comparison/validation into renderer namerefs with the same names. Bash
dynamic scope forms circular references and nounset aborts on SCHEMA_VERSION.

Minimal design: give the two Core config and two Secret renderers private
function-specific nameref names. Preserve caller interfaces, rendered bytes,
validation, health gates and the existing transaction/compensation model. Do not
rename health callers to conceal the shared defect or disable nounset/checks.

- [x] Reproduce all four local-array render paths and actual health -> compare ->
  render in focused tests before changing production code. Keep credentials out of
  assertion output, and compare local/global rendering byte-for-byte.
- [x] Repair only renderer reference names; inspect all callers for alias clashes.
- [x] Run focused tests, syntax/security/ShellCheck and the default suite.
- [x] Repeat real installation in a fresh guest clone with actual NSS/systemd,
  verified asset-cache reuse and protected logs. Require account/process identity,
  bounded capabilities, applied/config/invocation and actual link readiness.
- [x] Independently review and record exact evidence for the local commit; then continue the
  next main-flow slice. Preserve the failed guest's recovery evidence.

The failed guest has no remaining managed users/binaries/configs/units, keeps
PNM_CONFIGURED=no, and records ROLLBACK_COMPLETE/ROLLED_BACK. Those are persisted
resource/journal observations after shutdown, not a retroactive live-process
recovery test. Host databases were unchanged and the outer scope/mounts cleaned.

Red: `/var/tmp/pnm-render-scope-red.log`, eight existing tests pass and all five
new cases fail. Green frozen source `/var/tmp/pnm-render-scope-green` passes
13/13 focused tests, syntax/security/ShellCheck and `make check` (exit 0,
31 suites / 359 tests). Independent source review confirms the four renderer
entrypoints resolve the actual call chain without changing validation or output.

Fresh guest `/var/tmp/pnm-install-guest.zh1menk9` passes actual CLI installation
and all eight account/process/applied/link/health checks with normal root PATH.
Its `boot-result.json` records host boundary approval, guest success, nspawn
exit 0, unchanged host databases, not-found scope and no remaining fixture mounts.
Protected raw logs and copied-source hashes remain in the private fixture.
The earlier fixed-source guest `gswqfozh` used a PATH without `/usr/local/bin`:
Xray starts, but the bare `xray` config-test command fails the health gate. Adding
the standard PATH alone makes the new guest pass. This separately identified
health-command resolution issue is the next scoped repair; the failing attempt
does not count as successful installation evidence. No clock diagnostic was
collected, and no network download, traffic, reboot or external acceptance is
inferred from these installation checks.
