# PNM Current Tasks

**Updated:** 2026-10-26. **Phase 3 remains incomplete; Phase 4 and release work have not started.**

**Validation baseline:** branch `dev`, parent commit `65c8109`, VERSION
`0.16.0-rc.1`, including TLS/test repairs, cloud-development cleanup and
Ubuntu22.04/24.04 CI/regressions. The checks below preceded publication of this
increment; use Git for its final commit identity, not the old baseline reports.

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
The latest user instruction authorizes committing this reviewed increment and
pushing it to `origin/dev`. Package installation, provisioning, production access
and deployment remain outside scope. This is not standing authorization for
future commits or pushes.

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
| Platform/L3 | Debian13 amd64 is the first L2 baseline; earlier local client evidence has its own boundary | Debian12/Ubuntu22.04/24.04 amd64 acceptance and controlled external Xray/HY2 clients |

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
The shared TLS repairs above remain part of the uncommitted source.

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
has been parsed and checked locally but has not been pushed, triggered or observed
running. Do not infer Ubuntu24.04 or deployed Ubuntu amd64 acceptance from it.
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
reboot, external traffic and the newly configured GitHub runs remain unverified.

## Next priorities

1. Replay changed TLS and permission paths as root in an approved disposable
   Debian13 x86_64 fixture; prepare assets/identity/cleanup prerequisites first.
2. Continue the remaining L2 commit/storage/interruption positions from the
   reconciliation. Do not reuse old private paths or run fault injection on the
   development host.
3. Obtain an authorized deployed target for G-01 and controlled external clients
   for T-27; record source identity and each protocol's handshake/traffic separately.
4. Execute other supported amd64 platform acceptance, then reassess Phase3 closure.
   Do not start Profiles, production changes or release work automatically.
