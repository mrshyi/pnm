# Deployment transaction owner

Continue the approved production main flow using proposal A in
`docs/history/DEPLOYMENT_TRANSACTION_DESIGN.md`. Preserve standalone Core/sandbox wrappers,
CLI, credentials and all unrelated working-tree changes. No production operation.

- [x] Reproduce resource retention after an outer gate failure with temporary
  filesystem resources and mocked service state.
- [x] Extract explicit sandbox/lifecycle/state participants; one deployment
  transaction stays open until the apply gate's final health/deadline checks.
- [x] Persist independent service baselines, compensate resources in dependency
  order, verify recovery, and retain evidence on drift or recovery failure.
- [x] Publish a durable authoritative deployment commit marker; treat derived
  audit/cleanup failures after commit as warnings. Reject unresolved deployments
  before subsequent writes or credential-bearing reads.
- [x] Exercise late health/deadline/commit/receipt/rollback failures, run all
  existing checks, obtain independent review, and reconcile status documents.

Mock/filesystem acceptance does not establish real systemd/reboot/client behavior.
