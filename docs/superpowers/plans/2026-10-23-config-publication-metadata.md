# Protect configuration publication metadata

Scope: config apply currently publishes the runtime config without required
metadata receipts and normalizes ownership separately. Reproduce whether external
permission changes are overwritten or accepted before failure compensation.

- [x] Reproduce post-publication and pre-ownership-normalization permission drift.
- [x] Reuse existing verified Core file publication/ownership helper; preserve
  the original snapshot and reject unexpected metadata before/after normalization.
- [x] Cover both cores with real file receipts and mapped test service identities;
  run focused/default checks, nobody compatibility and existing systemd fixtures.
- [x] Review, record exact evidence and commit.

No new transaction framework, public CLI/config change, real account provisioning,
Core/TLS loading, network, reboot or production operations.

Final copy `/var/tmp/pnm-config-metadata-final`: default check exit 0 (31 suites /
351 passed), actual nobody evidence 38/38, restore focus 9/9, systemd stand-ins 8/8,
and complete static checks exit 0. Independent review's ownership-error regression
was reproduced before preserving the first error without adopting rejected
metadata. Exact fixture units are not-found/inactive without files/enable links.
Detailed evidence and the unverified real Core/reboot/client boundary are in Tasks.
