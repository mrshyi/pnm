# Actual distinct-version Core update and rollback

Use the existing opt-in guest and real CLI/transaction model. The official release
APIs supply a second frozen pair: Xray v26.9.30 and HY2 v2.12.3. Existing current
test pins remain v26.10.21 / v2.13.0; production VERSION/pins do not change.

- [x] Record previous release URL, size and SHA-256; acquire exact official bytes
  into a private cache and verify before use. Reuse the existing asset verifier.
- [x] Add one opt-in core-update scenario: initially install the previous pair,
  then deliberately approve only the frozen current pair inside the guest.
- [x] Serve only checked current asset bytes through a private lo HTTPS CONNECT
  fixture. Actual curl, TLS, checksum/staging/version checks and PNM publication
  remain enabled. Trust only the fixture CA via CLI process env, never host trust.
- [x] For each Core, reject a wrong approved checksum before write transaction,
  then run real different-version update, rollback to previous and rollback-swap
  forward. Require binary/version/invocation/applied evidence and unchanged peer
  resource bytes/metadata/PID/invocation; finish with both links/health ready.
- [x] Bound fixture requests/headers/timeouts and cleanup, keep logs private, add
  meaningful offline guards, run real cases/static/compile, review and commit.

The HTTPS fixture is a transport boundary substitution, not upstream PKI/DNS or
public download acceptance. No production function is replaced. This proves
actual distinct binary/transaction behavior with separately verified official
assets, not network acquisition, public clients or reboot/fault acceptance.

Official release APIs supplied both frozen previous asset digests/sizes. WSL
download/continuation timed out; Windows curl then downloaded both exact files.
Windows size/SHA checks and the Linux private-cache verifier pass2/2. Failed
partial files remain unpublished and unexecuted. Cache is
`/var/tmp/pnm-update-core-assets`, root0700 with root0600 assets.

Fresh `/var/tmp/pnm-install-guest.2t13z9ae` passes22/22 and the Make entry exits0.
The initial14 lifecycle cases run on the older pair, followed by four checks per
Core: fetched checksum refusal before transaction, real new version publication,
rollback to the previous version and swap forward. Peer comparisons include
previous binary/metadata. Final links/health and applied bindings pass; parent
checks report no interruption, normal exit0, unchanged host databases, scope
not-found and no fixture mounts. Source hashes and protected reports are retained.
Seven offline guards pass, including header limits and real CA-verified transport
plus wrong target/path and incomplete CONNECT/TLS cleanup in a new network NS.
Five implementation Python files compile; existing refusal guard and static
checks pass. CLI dependency repair is committed separately after default checks.
