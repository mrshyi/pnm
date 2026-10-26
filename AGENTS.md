# PNM — Project Instructions

## Project identity

Proxy Node Manager (PNM) is a lightweight Linux VPS management tool. Its CLI is `pnm`. The repository source at the current HEAD is the implementation source of truth; plans and historical reports do not prove a feature is implemented or verified.

## Documentation index and reading rules

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) describes behavior implemented in source. Read it before architecture or cross-module changes; confirm relevant details in code.
- [docs/ROADMAP.md](docs/ROADMAP.md) contains proposed work and milestones. Read it when planning work. Roadmap items are not authorization to implement them.
- [docs/TASKS.md](docs/TASKS.md) records the latest known phase, open issues, blockers, and next actions. Read it when taking over project work; refresh evidence before changing status.
- [docs/DECISIONS.md](docs/DECISIONS.md) records durable technical decisions and their evidence. Read it when a change touches an existing decision.
- [CONTRIBUTING.md](CONTRIBUTING.md) describes Linux development prerequisites, repository gates, and cloud test boundaries.
- [docs/history/README.md](docs/history/README.md) indexes historical audits, plans, and execution records. Read these only when the current task needs their issue IDs or rationale; old instructions and results are not current authorization or validation.
- [docs/RELEASING.md](docs/RELEASING.md) applies to release work only.

Read only documents relevant to the task. Keep enduring rules here; keep implementation detail in Architecture, future intent in Roadmap, current status in Tasks, and rationale in Decisions. When evidence changes, update the relevant status document rather than copying the same details into every file.

## Linux and cloud development

- Develop and run L1 tests on Linux. Ubuntu ARM64 is a development environment; the managed deployment platform remains the amd64 Debian/Ubuntu matrix in README. Do not bypass platform guards or select amd64 assets for native ARM64 execution.
- Recheck the execution namespace's UID, architecture, PID 1, tools, privileges and virtualization before integration tests. A cloud host name or an installed `systemctl` does not establish systemd, root, mount or KVM access.
- Run L1 as the normal workspace user with private temporary fixtures. Keep non-root WARN/UNKNOWN/refusal behavior and explicit root-only skips; never weaken production permission checks to make tests pass.
- Real service/account, mount, disk-exhaustion and reboot tests require an explicitly authorized disposable environment and the existing harness guards. Do not run them on the development host merely because a test target exists.
- Record HEAD and worktree changes, tool versions, exact exits and skips. Treat `/tmp` tools/logs as temporary; do not copy old private images, keys or test secrets into the workspace. Keep current host facts in `docs/TASKS.md`, not in permanent rules.

## Architecture and compatibility

- Preserve the two independent managed cores: Xray VLESS + REALITY and official Hysteria2 over QUIC. PNM manages them and does not forward proxy traffic.
- Preserve each core's configuration, service, lifecycle, update/rollback, and health boundaries. A core operation must not unnecessarily restart or modify the other core.
- Preserve existing `pnm` CLI commands, arguments, configuration formats, and client URI formats. Do not add `pn` aliases.
- Reuse existing modules and transaction facilities. Do not add Profile management, protocols, firewall automation, or unrelated features without explicit authorization.

## Engineering and safety

Priority: security, correctness, recoverability, stability, compatibility, maintainability.

- Make the smallest root-cause change. Preserve unrelated staged, unstaged, and untracked work.
- Distinguish desired, persisted, applied, and actual runtime state, as well as PNM ownership. A running service or open port alone does not prove which configuration is active.
- Do not expose private keys, passwords, client credentials, or complete share links in ordinary logs, diagnostics, tests, or reports.
- Do not modify production services, SSH, Tailscale, user accounts/authorized keys, UFW, or cloud firewall rules without explicit authorization.
- Never run destructive cleanup or reset operations such as `git reset --hard`, `git clean -fd`, `ufw reset`, `iptables -F`, or `tailscale down` as routine work.
- Do not evaluate configuration data as shell code. Quote paths and values, protect temporary files, use atomic writes where appropriate, and preserve error propagation.

## Transactions and validation

For state-changing work, follow the existing transaction model: PRECHECK → SNAPSHOT → STAGE → VALIDATE → APPLY → VERIFY → COMMIT; on failure, ROLLBACK → VERIFY RECOVERY. Rollback must cover resources changed by the operation, or clearly report what cannot be restored. Do not create a parallel transaction framework without a demonstrated need.

For code changes, inspect relevant source and tests, implement the minimal fix, run applicable existing checks (including ShellCheck where available), and report exact results. Clearly distinguish source review, automated tests, Linux/systemd integration, real VPS checks, and external client connectivity. Do not claim a check passed unless it was run successfully.

## Git and release boundaries

- Do not automatically commit, push, tag, or publish releases.
- Do not automatically install dependencies or deploy PNM to satisfy a development check; report missing prerequisites or use already approved isolated tools.
- Do not change `VERSION` merely because code or documentation changed.
- Do not automatically switch branches, reset the worktree, or overwrite uncommitted files.
- Production deployment and destructive operations require explicit authorization.
