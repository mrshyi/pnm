# PNM Current Tasks

**Updated:** 2026-10-26. **Phase 3 remains incomplete; Phase 4 and release work have not started.**

**Published baseline:** branch `dev`, commit `39312aa`, VERSION
`0.16.0-rc.1`, including TLS/test repairs, cloud-development cleanup and
Ubuntu22.04/24.04 CI/regressions. Local preparation checks below used parent
`65c8109` plus that increment; the remote CI checks used exactly `39312aa`.

## Continuation checkpoint

- Local stage commits:166e828 (CI evidence),6ec55cc (asset publication),5eb8be9
  (ZIP observation/mode errors),ae838f5 (version-query refusal tests),9dda49f
  (filename-independent asset checksums),fd3710c (TLS pin pipeline failures),
  e4999df (transaction hash/inspect refusals). They have not been pushed.
- Stage8 repairs the remaining runtime-config checksum parsing in applied
  publication/status. Validation parent:e4999df; resolve the final stage commit
  with Git. Logs: `/tmp/pnm-stage8-binding.qk3v4VNg/`.
- Actual Ubuntu amd64 CI evidence remains at39312aa; unpublished increments
  have local ARM64 L1 evidence only.
- Next integration work needs an explicitly authorized disposable Debian13
  x86_64/root/systemd environment; the environment question is pending.
  Do not provision, run faults on the development host, push or start Phase4.

## Current environment

- `dev-sanjose`: Ubuntu 22.04.5 LTS ARM64, UID/GID1001, OpenSSL3.0.2.
- The execution namespace has PID1 `codex`; root, `/dev/kvm`, QEMU and nspawn
  are not available in the checked session. Do not infer the whole host's service
  state from this namespace. Recheck capabilities before choosing integration work.
- This is a Linux L1 development workspace. Supported deployments remain Debian
  12/13 and Ubuntu22.04/24.04 amd64 with systemd.
- ShellCheck0.8.0 was approved, downloaded from the configured Ubuntu repository
  and extracted to `/tmp/pnm-cloud-fix.v5LWBeoD/shellcheck-tool`. It was not
  installed system-wide. This temporary path must be rechecked before reuse.
- No deployment target or external clients have been supplied for G-01/L3.
  Historical WSL storage limits, host paths and private VM assets are not cloud
  prerequisites or transferred fixtures.

For development setup and gate commands, use [CONTRIBUTING](../CONTRIBUTING.md).
For test IDs and closure rules, use [ACCEPTANCE_PLAN](ACCEPTANCE_PLAN.md).
The latest user instruction authorizes continuing unfinished development,
committing each validated local stage, recording a compact continuation summary
and proceeding to the next stage. The earlier push of `39312aa` is complete;
there is no standing authorization to push subsequent stages. Package installation,
provisioning, production access and deployment remain outside scope.

## Current implementation and remaining acceptance

| Item | Source / historical evidence | Still open |
|---|---|---|
| G-01 runtime/config/link state | Both Core runtime rows and applied/InvocationID gates exist | Read-only source identity comparison on an authorized deployed target; none supplied |
| G-02 deployment recovery | Shared deployment transaction, metadata/directory/account receipts, uncertainty guards; selected native/VM fault and reboot records | Remaining commit/storage/corruption windows and concurrent schedules; physical media behavior is not established |
| G-03 Core update/rollback | Paired current/previous binaries and version metadata; selected distinct-version, fault and reboot records | Remaining commit/storage and abrupt-VM update/rollback positions |
| G-04 backup/restore | Trusted archive validation, bounded parsing, metadata compensation; selected real restore/fault/reboot records | Remaining storage and abrupt-VM restore positions; arbitrary untrusted executables remain outside the trusted-input contract |
| G-05 dependency preflight | Declared prerequisite checks and historical Debian guest19-tool refusal records | Remaining acquisition/DNS/PKI/timeout/archive cases and other distributions |
| G-06 HY2 TLS/account access | Ownership/mode/effective-read checks, historical managed-account and TLS fault records | Root/platform/NSS variations, changed TLS paths on supported amd64, external handshake/traffic |
| T-04/T-20/T-26 | Historical configured-port conflict, real lock contention, stale-binding refusal and same-disk reboot slices | Other topology/scheduling combinations and external-client routing |
| Platform/L3 | Debian13 amd64 is the first L2 baseline; Ubuntu22.04/24.04 amd64 L1 CI passed at39312aa | Root/service/reboot acceptance on the remaining supported platforms and controlled external Xray/HY2 clients |

These are source observations and explicitly historical results, not fresh cloud
L2 passes. The [dated T-01–T-27 reconciliation](history/PHASE3_EXECUTION_2026-10-22_26.md#matrix-reconciliation--2026-10-25)
retains exact prior coverage and limits. Earlier A-01–A-05 reports are pre-repair
findings; do not reopen them solely because the archived text describes old code.

## Latest completed code increment: shared TLS and non-root tests

- Shared TLS validation rejects OpenSSL3.0's exit0 hostname mismatches and uses
  locale-stable default certificate dates instead of unsupported date options.
  Added regression coverage retains SAN/CN precedence and wildcard boundaries.
- Transaction inspect's umask failure was a hardcoded0644 fixture expectation;
  the test records the actual mode. Production transaction logic was unchanged.
- Non-root fixtures expect diagnostic UNKNOWN/WARN or permission refusal without
  weakening production guards. Root assertions/skips remain distinct.

Results below were executed **after the TLS fix and before the current cleanup**:

| Check | Actual result |
|---|---|
| `make check`, umask077 | exit0;32 suite summaries,392 passed,0 failed |
| `make shellcheck`, temporary tool on PATH | exit0; ShellCheck0.8.0 |
| `make release-check`, umask077 | exit0; repeats32 suites/392 passes, not independent coverage |
| Supplemental ShellCheck of five changed test/fixture scripts | exit0 |
| Transaction suite, umask077 and022 | exit0 each;25/25 each |
| Offline guest guards | exit0;33 total,25 passed/8 root-only skipped |
| Core refusal guard | exit0;1 passed |
| Integration Python in-memory compilation |26 files passed, no bytecode generated |

Root-only bodies/suites were skipped: real update CLI, root/runuser/nobody access,
real TLS access, low-mode recovery and numeric ownership. Non-root392 passes are
not the historical root399 baseline or proof of root branches. The pre-fix cloud
baseline had374 passes/17 failures; its separate log remains
`/tmp/pnm-cloud-l1.zOeyAANW/check.log`. Post-fix logs are private under
`/tmp/pnm-cloud-fix.v5LWBeoD/`; these are volatile local evidence, not durable
handoff artifacts. Detailed repair evidence is
[archived](history/PHASE3_EXECUTION_2026-10-22_26.md#cloud-tls-compatibility-and-regression-repair--2026-10-26).

## Cloud development cleanup

- Current instructions are in AGENTS/CONTRIBUTING; the completed one-time cloud
  transfer handoff is removed, including its obsolete source-transfer/commit text.
- Old rolling execution notes, three baseline audit/design reports and56 dated
  plans are in [history](history/README.md). Their results and limitations are
  retained, but their old next steps are not the current task list.
- Acceptance guidance now distinguishes Linux ARM64/non-root L1 from amd64 L2.
  Repeated historical result blocks have been removed from the active plan.
- Removed Windows-only certificate-path handling and the Windows metadata stub.
  Preflight now exercises actual Linux ownership/modes and rejects unsafe modes.
- Python test entry points suppress bytecode, and caches are ignored.

Fresh cleanup checks (Ubuntu ARM64/non-root, private logs under
`/tmp/pnm-cloud-cleanup.o0x8j6_s/`):

| Check | Actual result |
|---|---|
| `make release-check`, umask077 | exit0; release scan plus embedded `make check`:32 suites,392 passed,0 failed |
| `make shellcheck`, approved temporary ShellCheck0.8.0 on PATH | exit0 |
| Supplemental ShellCheck of the two changed test scripts | exit0 |
| Preflight suite, umask077 and022 | exit0 each;14/14 each, real Linux metadata |
| HY2 SNI suite | exit0;9/9 |
| Markdown local paths/anchors |73 files,138 links checked; no failures; external URLs not fetched |
| Archive preservation |59 reports/plans and the prior uncommitted rolling task record preserved, apart from banners/links/title |

The release target supplies this cleanup's full check run; a second standalone
`make check` was not repeated. Root-only bodies/suites retain the skips listed
above. No new root/systemd, actual Core, VM/reboot or external traffic evidence
is claimed. The opt-in real-Core target was only dry-run inspected for `-B`;
no assets were downloaded or executed. No commit, push or deployment was performed.

## Ubuntu22.04/24.04 compatibility

The platform adapter already accepts Ubuntu22.04/24.04 amd64; no whitelist,
architecture, Core asset, account or service-policy relaxation was needed.
The shared TLS repairs above are included in published commit39312aa.

- CI now selects `ubuntu-22.04` and `ubuntu-24.04` explicitly instead of a moving
  `ubuntu-latest`, keeps failures independent, records OS/tool versions and checks
  the native host through the actual platform adapter before mock tests. All
  three existing gates remain configured. The setup step declares its test tools.
- Platform regressions cover both Ubuntu fixtures and the Debian compatibility
  baseline, reject unsupported architectures, other Ubuntu versions, derivatives
  and missing VERSION_ID. The distro name alone cannot bypass the architecture gate.
- Service regressions run the actual `systemd-analyze verify` against both
  rendered unit policies using isolated targets and temporary Core paths, and
  require refusal when the fixture executable loses its executable mode. No Core
  program or service is started, and host unit search paths are excluded.

This session has Ubuntu22.04 ARM64, Bash5.1.16, Python3.10.12, OpenSSL3.0.2 and
systemd249.11. It has no approved Ubuntu24.04 or amd64/root guest. The CI matrix
was initially checked only as configuration; the subsequent executed amd64 results
are recorded below. Neither layer proves deployed Ubuntu lifecycle acceptance.
Fresh local results (private logs under `/tmp/pnm-ubuntu-compat.oNt1gGQy/`):

| Check | Actual result |
|---|---|
| `make release-check`, umask077 | exit0; release scan and embedded `make check`:32 suites,395 passed,0 failed |
| `make shellcheck`, approved temporary ShellCheck0.8.0 on PATH | exit0 |
| Supplemental ShellCheck of check/service suites | exit0 |
| Focused check/platform suite | exit0;27/27 |
| Focused service suite, actual systemd249 verifier | exit0;4/4 |
| CI YAML/matrix and all five run scripts | parsed/asserted and `bash -n` passed; no CI execution |

This is fresh Ubuntu22.04 ARM64/non-root L1 evidence, including static systemd
parsing. Explicit root-only skips remain: real update CLI, root/runuser/nobody
access, real TLS access, low-mode recovery and numeric ownership. No second
standalone full check was counted. Ubuntu22.04/24.04 amd64 root/service lifecycle,
reboot and external traffic remain unverified.

## Stage 1: executed Ubuntu CI reconciliation

On2026-10-26 the connected GitHub app supplied the completed job metadata and
full job logs for [CI run40310959008](https://github.com/mrshyi/pnm/actions/runs/40310959008),
attempt1, exact source39312aaf6de9e97cccfcaf09e257e923d6246cad, event `push`.
Both jobs and each of `make check`, `make shellcheck`, `make release-check`
concluded success. Each log contains64 suite summaries:32/395 passes for the
first full check, then the same32/395 for the release target's repeated check,
with0 failures. Repetition is not additional independent coverage.

| Job | Observed native environment | Actual scope |
|---|---|---|
|121531726496, Ubuntu22.04 |22.04.5 LTS, x86_64, Bash5.1.16, Python3.10.12, OpenSSL3.0.2, systemd249.11 | Non-root L1 plus real certificate tools and isolated static unit verification; all three gates passed |
|121531726942, Ubuntu24.04 |24.04.5 LTS, x86_64, Bash5.2.21, Python3.12.3, OpenSSL3.0.13, systemd255.4 | Same L1/static scope; all three gates passed |

Both logs retain explicit skips for the real update CLI, root/runuser/nobody
access, real TLS access, low-mode recovery and numeric ownership. These are
now actual Ubuntu amd64 CI results, not os-release fixture inference, but do
not close root/Core/systemd lifecycle, reboot, G-01 or L3. Only status evidence
changed in this stage; no business tests were rerun for the documentation edit.

## Stage 2: fail-closed asset candidate publication

Validation parent166e828. Source/caller inspection found that the shared download
adapter ignored chmod failure and accepted GNU `mv -n` exit0 when a destination
appeared during transport. A directory could also receive the temporary candidate
as a child. Host cache preparation would then set its selected path without a
new hash check. Core update uses the same adapter before its binary transaction.

The shared function now rejects pre-existing dangling links, checks candidate
chmod, uses no-target-directory/no-clobber publication and requires the original
candidate path to disappear before success. Occupied destinations return73;
candidate mode failure returns77. Only the owned candidate is removed on refusal;
foreign destinations and unrelated sentinels are retained. No CLI, manifest,
URI, service policy or managed transaction schema changed.

Five new regression wrappers exercise both Cores with a controlled curl script:
dangling destination before transport, raced file/directory/link and chmod error.
Before the fix the asset suite had6 passes/5 failures; afterward11/11 pass. Actual
GNU move/file/link operations and hashes execute in private temporary paths;
chmod error is injected and no network, account or service operation occurs.
The14 host-apply and5 approved-version tests also pass (exit0 each). Full
`make release-check` exits0:32 suites,400 passed,0 failed, including syntax and
security scanning. Standard ShellCheck and supplemental asset-test ShellCheck
both exit0. Root-only skips remain unchanged; no L2 or external result is added.
Private logs:
`/tmp/pnm-stage2-assets.OWQojhdj/`. Earlier39312aa CI results do not cover this patch.

## Stage 3: ZIP observation and executable-mode refusal

Validation parent6ec55cc. A private reproduction showed `unzip -Z1` returning23
with a valid-looking name, followed by successful extraction and staging0. The
process-substitution producer's status did not reach the existing while-loop guard.
The helper now checks list-query success and nonempty output before the existing
member-name checks and real extraction. It returns78 on list/format refusal,
and77 when candidate chmod fails, with no successful candidate path on stdout.

Four new wrappers first failed (11 existing passed/4 failed), then the staging
suite passed15/15. They cover failed listing with and without output, empty
success, and final chmod failure. Extractor invocation and actual candidate files
are checked, source ZIP hashes remain unchanged, and the real safe/traversal ZIP
cases remain. Safe ZIP construction/extraction and metadata use real tools;
observer/permission errors are injected. No real Core, account or service runs.
The12 sandbox install cases also pass. `make release-check` exits0:32 suites,
404 passed,0 failed; standard ShellCheck and supplemental staging-test ShellCheck
both exit0. Existing root-only skips remain; neither storage failure on a real
device nor L2/Core runtime is newly validated. Private logs:
`/tmp/pnm-stage3-zip.2QudjIGe/`.

## Stage 4: first-install version-query refusal symmetry

Validation parent5eb8be9. Added unparseable HY2 and failed Xray query cases;
both failed-query fixtures now emit a matching-looking banner before exit23.
Per-process receipt files prove the correct version command ran and preserve
fail-fast Xray-before-HY2 behavior. Each refusal returns78 without publishing
either managed binary; the matching pair still permits both publications.
Only fixed safe fixture programs execute and their publication function is
substituted. Runtime code and manifests did not change in this stage.

The focused approved-version suite passes7/7. Standard and supplemental
test-script ShellCheck pass. `make release-check` exits0:32 suites,406 passed,
0 failed, including syntax/security scanning. Root-only skip labels remain the
same. No additional independent full run is counted. Private logs:
`/tmp/pnm-stage4-versions.S7jmiGqQ/`. These remain L1 boundary checks, not official
Core execution, a failed real filesystem, root identity or L2 acceptance.

## Stage 5: filename-independent checksum verification

Validation parentae838f5. A real GNU sha256sum probe rejected a correct approved
digest when the source filename contained a literal backslash: filename escaping
prepended a backslash to the parsed digest. The shared verifier now reads the
content through standard input, checks the tool's exit status directly and
extracts the digest without an awk pipeline. Download, cached and supplied-asset
callers retain their interfaces and mismatch refusal behavior.

Two regressions first failed (11 passed/2 failed), then the focused asset suite
passed13/13. One uses an actual backslash-containing Linux path and real hashing;
the other injects matching checksum output followed by exit23 with caller
pipefail disabled. No network, Core or host service is involved. Private logs:
`/tmp/pnm-stage5-hash.sKgyFC7V/`.

`make release-check` exits0:32 suites,408 passed,0 failed. Standard ShellCheck
and supplemental asset-test ShellCheck exit0. The same root-only skips remain;
this is L1 evidence, not a fresh supported-platform integration result.

## Stage 6: TLS pin pipeline failure propagation

Validation parent9dda49f. Shared SPKI pin generation previously masked pipeline
failure with a successful final newline. The private-key pipeline also depended
on caller pipefail. Both now enable pipefail within command
substitutions, check status before using output and return78 on tool failure.
The SPKI helper buffers output until the pipeline succeeds. No persisted pin,
certificate, CLI or client-link format changed; caller shell options are retained.

Four regressions first failed (6 passed/4 failed). The focused TLS suite then
passed10/10. Actual temporary EC certificates, public-key DER conversion, hashing
and encoding run; controlled wrappers emit their normal valid output before
exit23 at DER/digest/base64 or private-key export. Tests cover caller pipefail
both on/off, empty failure output and unchanged caller options. Standard and
supplemental TLS-test ShellCheck pass. Private logs:
`/tmp/pnm-stage6-tls.L98Uhzxk/`. These are L1 tool-failure boundary checks,
not actual Core TLS handshakes or root/service permission acceptance.

`make release-check` exits0:32 suites,412 passed,0 failed, including syntax and
security/release scans. Existing root-only skips remain unchanged. No second
independent full test run or new Ubuntu amd64 CI execution is claimed.

## Stage 7: transaction checksum and inspect observation failures

Validation parentfd3710c. Transaction hashing had the same GNU filename-escape
issue as asset verification, causing write intent refusal for a legal parent
path containing a backslash. It now hashes content through stdin and propagates
tool failure without relying on caller pipefail. Missing/unsafe sentinels remain.
Inspect previously accepted an empty failed hash query because it only compared
output against UNSAFE; it now checks status and a canonical digest before using
the transaction's terminal state. Existing write guards retain the refusal.

Three regressions first failed (25 passed/3 failed), then the focused suite
passed28/28. Actual private files, snapshots, writes, rollback, numeric metadata
and receipt parsing execute. Backslash-path recovery preserves original content
and metadata and remains inspectable. A controlled hash wrapper emits valid
output before exit23, or no output; failed observations refuse inspect78 and the
pending-transaction guard70 while preserving candidate bytes. The direct hash
failure case runs with caller pipefail disabled. Standard and supplemental
transaction-test ShellCheck pass. Private logs:
`/tmp/pnm-stage7-transaction.FEq7vMyo/`. This does not prove physical EIO or
authenticate snapshot bytes against a separately retained original digest.

`make release-check` exits0:32 suites,415 passed,0 failed. The existing root-only
skips remain. The final focused28/28 run additionally verifies downstream write
guard refusal; the full run also includes those assertions. No L2 result is added.

## Stage 8: applied binding hash observation consistency

Validation parente4999df. Applied publication and status retained filename-based
checksum pipelines: a literal backslash could prevent publication or label
unchanged runtime content as changed. With caller pipefail disabled, a hash tool
printing a valid digest before exit23 could still publish/confirm a binding.
Publication now reuses the transaction hash helper; standalone status retains
its module boundary and hashes through stdin with direct status checking.
Publication refuses70 and observation returns unknown on hash failure. Existing
digest/InvocationID matching, CLI and record formats are unchanged.

Four regressions first failed (41 passed/4 failed), then the focused suite
passed45/45. Each exercises both Cores:
backslash-path observation, real transaction-backed evidence publication and
receipt inspection, failed observation and failed publication. Actual private
files/hashes/transactions execute; systemd InvocationIDs are controlled fixtures.
Peer receipts and restart counters remain unchanged, and a failed hash leaves
original applied bytes with no written resource or staged binding. The error
cases disable caller pipefail and inject valid hash output followed by exit23.
Standard and supplemental Core-evidence-test ShellCheck pass. Private logs:
`/tmp/pnm-stage8-binding.qk3v4VNg/`. This is L1 evidence, not a real running
configuration identity or new supported-platform/L2/client acceptance result.

`make release-check` exits0:32 suites,419 passed,0 failed, including syntax and
security/release scans. Root-only skips remain the same; the focused45/45 run
and its full-gate repeat are not counted as independent acceptance coverage.

## Next priorities

1. Integration prerequisite: provide/authorize a disposable Debian13 x86_64 root/systemd
   fixture for changed TLS, acquisition and permission paths. The environment
   question is pending; no approved fixture/asset cache has been supplied here.
   Replay changed paths only after those prerequisites are established.
2. Replay changed TLS and permission paths as root in an approved disposable
   Debian13 x86_64 fixture; prepare assets/identity/cleanup prerequisites first.
3. Continue the remaining L2 commit/storage/interruption positions from the
   reconciliation. Do not reuse old private paths or run fault injection on the
   development host.
4. Obtain an authorized deployed target for G-01 and controlled external clients
   for T-27; record source identity and each protocol's handshake/traffic separately.
5. Execute other supported amd64 platform acceptance, then reassess Phase3 closure.
   Do not start Profiles, production changes or release work automatically.
