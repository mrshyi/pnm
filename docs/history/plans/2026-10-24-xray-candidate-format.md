# Xray apply candidate format repair

Real managed CLI apply fails before runtime mutation. In guest pos73g_w the same
candidate bytes return 23 without a suffix (Failed to get format), and 0 with
`.json`. Xray v26.10.21's default auto loader selects format from the filename.
The apply path names its temporary candidate `config` and does not specify format.

Give only the Xray candidate a `.json` suffix; leave HY2 staging, CLI arguments,
validation and transaction/publication/recovery behavior intact.

- [x] Add a focused auto-format contract regression and reproduce failure.
- [x] Make the minimal candidate filename change.
- [x] Run focused/full/static checks and actual changed-config guest lifecycle.
- [x] Independently review and record evidence for the repair commit before the
  separate reusable guest acceptance harness increment.

Red `/var/tmp/pnm-candidate-red.ls_hk0ge`: 14 pass / new case fails. Green frozen
`/var/tmp/pnm-candidate-green.9ryuw8sq`: 15/15 focused, syntax/security/ShellCheck
and `make check` exit 0 (31 suites / 362 tests). Independent review found no
blocking issue. Real guest `fewv_gnd` passes all 13 checks through per-Core
changed-config apply with peer preservation, confirming the repaired route.
The subsequent restore times out and records RECOVERY_REQUIRED/original rc143;
the harness reports failure/NoGuestReport, never a full pass. Its container exits
0 with host databases unchanged, scope not-found and no fixture mounts. Restore
diagnosis and bounded descendant cleanup remain the next separate test increment.
