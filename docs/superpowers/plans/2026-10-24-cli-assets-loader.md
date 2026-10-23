# CLI asset dependency repair

Actual `pnm update` in guest ut1_l8m2 returns78 before the HTTPS fixture receives
any request: stderr reports pnm_assets_load command not found. The existing
function is in lib/assets.sh, while bin/pnm loads only adapters/assets.sh.
Directly sourced unit tests conceal this CLI wiring defect.

- [x] Reproduce through the actual CLI for both Core names with an unapproved
  requested version. Require the proper approval refusal, not only exit78.
  Use only private state/lock paths and skip the writer case for non-root.
- [x] Source the existing assets library after its adapter, without adding the
  deliberately removed broad assets command or changing public CLI behavior.
- [x] Finish default checks; focused/static and actual distinct-version cases pass.
- [x] Independently review the entry repair and its regression.
- [x] Record final default evidence for the separate repair commit.

Red `/var/tmp/pnm-cli-assets-red.4k1esxdy`: 10 pass / new case fails. Green frozen
`/var/tmp/pnm-cli-assets-green.fqpxumap`: focused11/11 and syntax/security/ShellCheck
exit0; default `make check` exits0,31 suites/363 tests pass. Real fresh
guest2t13z9ae passes22/22, including
actual checksum refusal and both distinct-version updates/rollback swaps. Its
private HTTPS fixture substitutes only asset transport; real CLI, curl/TLS,
checksum/version/staging/publication/health/applied logic run. Host databases are
unchanged, scope not-found, no fixture mounts and nspawn exit0. Do not infer
upstream DNS/PKI/download, reboot or external-client acceptance.
