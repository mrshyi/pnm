# Actual guest deployment failure and retry

Extend only the existing explicit opt-in native guest harness with one named
failure scenario. Preserve the successful 14-case lifecycle scenario and all
isolation/host boundary guards. No production hooks or functions are replaced.

- [x] Add a `deployment-failure` test scenario, stored as protected clone data.
- [x] After actual init/preview, hide only openssl from a guest-private filtered
  PATH. Require preflight refusal with unchanged node/config/accounts/resources.
- [x] Add a guest-only Xray ExecStartPre sleep35 drop-in and set the supported
  commit window to30 seconds for the single attempted install. Require actual
  dual-Core deployment to reach post-health before the deadline refusal.
- [x] Verify live rollback: no managed users/binaries/configs/units/applied state,
  inactive/absent services with no process/listeners, PNM_CONFIGURED=no, completed
  rollback receipt and no durable deployment commit. Preserve preexisting
  directories/metadata and the unchanged owned drop-in; no unresolved promotion.
- [x] Remove only the exact owned delay drop-in and reload guest systemd, then
  retry actual install and run the original 14-case lifecycle to completion.
- [x] Run offline guards/compile/static checks, independently review and record
  exact local evidence and commit. Do not claim VM/reboot or external acceptance.

The native guest and all delay/filter resources are private disposable fixtures.
Timeout failure is not expected success: require the actual CLI deadline exit77
and its completed compensation evidence, then a verified successful retry.

`make test-guest-mainflow PNM_GUEST_SCENARIO=deployment-failure` exits 0 in fresh
`/var/tmp/pnm-install-guest.vh5luh5b`: **16/16** checks pass, including the original
14 after retry. Exit77 alone is insufficient attribution: the test also requires
the 30-second metadata window, APPLY_DONE/HEALTH_CHECK before APPLY_FAILED rc77,
failure timestamp beyond the recorded deadline, completed real post-health and
no commit marker/pointer. Live compensation verifies absent services/processes/
listeners/accounts/groups, restored baseline files/directories, no applied state,
and completed rollback without RECOVERY_REQUIRED. Host databases remain unchanged,
nspawn exits 0, scope is not-found and no fixture mounts remain. Raw protected
evidence and source hashes are retained. No production function was replaced.
Offline guards pass 5/5, both changed Python scripts compile, and
syntax/security/ShellCheck exit 0. Independent review found no blocking issue.
