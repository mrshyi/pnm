# Real Core evidence on Debian WSL

Goal: supplement stand-in tests with fixed official Core binaries, actual generated
configuration validation, startup/TLS and local protocol traffic. This does not
replace disposable VM/reboot, actual service-account provisioning or an external
client on a separate host.

Design: root orchestrates private fixtures and randomly named transient systemd
units. Existing nobody runs each Core without capabilities, with NoNewPrivileges,
ProtectSystem/ProtectHome and PrivateNetwork. Clients and a fixture-only HTTP
origin enter that unit's network namespace and run as nobody. Before starting the
origin, root verifies that the pinned namespace differs from the host and contains
only lo, then adds a fixture address to that private lo device. The pinned Xray
blocks private/documentation destinations by default; the fixture uses a nonprivate
address that exists solely in this isolated namespace, with no external interface.
No managed Core unit, installation path, account, firewall, host interface or route
is changed. Units have a runtime deadline and cleanup targets only owned names and
child processes. A host-loopback-only design offers weaker isolation; a disposable
VM is not currently available. The selected namespace design uses existing WSL.

Assets: [Xray v26.10.21](https://github.com/XTLS/Xray-core/releases/tag/v26.10.21)
and [Hysteria v2.13.0](https://github.com/HyNetworks/hysteria/releases/tag/app/v2.13.0).
`tests/integration/real_core_versions.json` pins the official release API SHA-256
digests and sizes fetched on 2026-10-23. Check exact archive/binary bytes before
extracting or executing; binaries run as nobody. These test pins do not change
PNM VERSION, managed versions.conf or production approval. Logs/configuration
containing generated credentials stay in protected temporary files and are never
printed in ordinary output.

Stages:

- [x] Verify namespace prerequisites, validate the manifest and commit the reviewed
  test-only official metadata pins/plan.
- [x] Download and verify the exact pinned assets privately before any execution.
- [x] Implement an explicit opt-in real-Core test entry. Reuse production renderers,
  validate Xray config, then observe both real startup and HY2 TLS loading.
- [x] Verify positive local client traffic through both Cores.
- [x] Follow with authentication/TLS rejection cases that verify valid candidates
  and the expected refusal cause, not arbitrary startup/connect failures.
  Preserve the external-client boundary.
- [x] Run static checks and independent safety review before service execution;
  verify owned-unit/child cleanup, document evidence and commit each complete stage.

The default make check target never downloads assets or starts these units.
Any unsupported namespace or missing verified asset fails before service setup.

Prerequisite evidence: Debian WSL PID 1 systemd, manager running, and
`unshare --net true` exit 0. Official release API metadata and manifest JSON parsed
successfully. Official asset API transfers completed after bounded retries/resume;
both exact sizes/SHA-256 match the pins. No downloaded executable or new Core unit
has run at this preparation checkpoint. Runtime fixtures use random `/run` paths
because PrivateTmp would hide `/var/tmp` within the units.

Positive-stage evidence (2026-10-23): frozen source
`/var/tmp/pnm-realcore-positive-v6`, `make syntax security-scan shellcheck`, explicit
fixture ShellCheck and Python compilation all exited 0. With the verified asset
cache, `make test-real-cores` passed **5/5** and removed all seven owned units and
its runtime fixture. The `.run.log` and `.lint.log` beside that copy retain the
sanitized results. Both real Cores validated/loaded production-rendered configs;
each real local client transferred the fixture marker through its Core. HY2 used
CA verification against the fixture certificate, not the PNM share-link pin.
Earlier diagnostic runs established that Xray's default private-IP block caused
the original loopback probe to time out; the final pass leaves production
configuration unchanged. Failed-run credentials/logs are kept behind a root-owned
0700 parent in `/var/tmp`, without following symlinks or copying public binaries.

Next: exercise PNM's HY2 wire pin with the official client. Source inspection shows
PNM stores an SPKI/base64 hash while this official client expects a leaf-certificate
DER/hex fingerprint. Reproduce this mismatch before choosing a compatible repair.

Share-pin repair design: retain `HY2_TLS_PIN_SHA256` as the existing internal
SPKI/base64 field and preserve CLI/schema/URI query names. For selfsigned-pin
share links only, derive the official client's SHA-256 leaf-certificate DER
fingerprint as lowercase hex from the configured certificate. Extraction failure
must omit only HY2 and retain a ready Xray link. Test the current generated URI
with the official client after the CA-positive control and reproduce the specific
pin mismatch. Add focused DER/hex/error and independent-Core link regressions
before the smallest production repair. Run default checks and the real client,
then independently review before committing. Wrong-pin/auth refusal cases must
show their expected causes and preserve a valid positive control.

Repair evidence: the original URI pin failed after all five protocol/CA controls
passed (`pnm-realcore-pin-red`). Focused TLS/link regressions failed before the
production change, then passed 5/5 and 30/30. `pnm-pin-green-v2.real.log` passes
6/6 using the full PNM-generated URI as the official client's server field, with
no hand-mapped authentication/TLS fields. All eight test units were cleaned.
Readiness is mapped solely in the URI fixture and independently tested startup
is not full PNM managed-service readiness. The repair retains the internal schema.

Rejection-stage design: mutate only VLESS UUID or REALITY short ID in a copy of
the validated real client config; validate each with the real Xray before probing.
Require the corresponding private server/client log cause, then repeat the correct
client's transfer. For HY2, mutate only the URI pin or password, require respectively
the exact fingerprint mismatch or authentication HTTP 502 plus server masquerade
evidence, observe that the owned
candidate has stopped, then repeat the working URI transfer. No arbitrary failed
connection or invalid config counts as a refusal. All candidates remain in the
same owned private namespace and use the existing guarded cleanup.
The REALITY short-ID candidate trusts the fixture fallback certificate only via
its own `SSL_CERT_FILE` environment. Host trust is untouched; this prevents an
unknown-CA error from masking the explicit REALITY unverified-connection cause.
After recording an Xray refusal, stop the owned negative client through the same
ownership/stop guard as final cleanup before repeating the valid transfer. Invalid
REALITY's fallback spider otherwise holds the single-connection openssl fixture
endpoint; the first run showed queued valid requests released only on candidate
cleanup. This tests refusal and subsequent recovery, not concurrent DoS resistance.
The production HY2 proxy masquerade targets the fixture's `.invalid` TLS name.
Official server source routes rejected authentication to that proxy; in the private
namespace it produces 502, not a default 404. Require both the client's typed auth
error and the server's reverse-proxy error for that target, then repeat the valid
URI. The earlier strict 404 expectation failed and was not counted as acceptance.

Final rejection-stage evidence: `/var/tmp/pnm-rejection-final.real.log` passes
**10/10**, including all four refusals and subsequent valid transfers. The offline
guard covers four safety failures and passes before the real run; syntax/security/
ShellCheck/Python compilation pass. All twelve owned units and the success fixture
were cleaned. The available WSL plan is complete; actual managed-account/lifecycle,
disposable-VM reboot/fault injection, deployed-source identity and external-client
acceptance remain open in TASKS. Phase 3 and release readiness are not complete.
