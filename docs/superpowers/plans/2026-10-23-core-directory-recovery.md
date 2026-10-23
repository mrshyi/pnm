# Include standalone Core state directories in recovery

Scope: applied publication normalizes state directories outside directory receipts;
update also creates/normalizes its previous-state directory before transaction
begin. Failed standalone operations must recover these resources as well as files.

- [x] Reproduce existing-directory mode drift and new-directory leaks on failure.
- [x] Reuse directory preparation receipts for applied publication and update
  staging destinations, with reverse directory recovery in standalone callbacks.
  Include the legacy install-state caller found during shared-publisher review.
- [x] Preserve foreign content/metadata with recovery-required; cover both cores,
  apply/restart/update/rollback, missing directories and partial preparation.
- [x] Run focused/default checks, real nobody and existing isolated systemd tests,
  review evidence and commit.

No new transaction model, CLI/config change, real Core/account/network/reboot or
production operations. Files/services/applied recovery precede directory cleanup.

Final copy `/var/tmp/pnm-core-directories-final-v2`: default check exit 0,
31 suites/348 passed; actual nobody evidence 35/35, systemd fixtures 8/8 and all
static checks exit 0. Exact generated units were confirmed absent/inactive and
without files/enable links. Core and legacy red regressions preceded the repairs;
independent static review accepted both paths. Earlier Hangup logs are historical,
not passing evidence. Full real Core/TLS/reboot/client acceptance remains open.
