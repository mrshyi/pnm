# PNM — Project Instructions

## Project identity

Proxy Node Manager (PNM) is a lightweight Linux VPS management tool. Its CLI is `pnm`. The repository source at the current HEAD is the implementation source of truth; plans and historical reports do not prove a feature is implemented or verified.

## Documentation index and reading rules

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) describes behavior implemented in source. Read it before architecture or cross-module changes; confirm relevant details in code.
- [docs/ROADMAP.md](docs/ROADMAP.md) contains proposed work and milestones. Read it when planning work. Roadmap items are not authorization to implement them.
- [docs/TASKS.md](docs/TASKS.md) records the latest known phase, open issues, blockers, and next actions. Read it when taking over project work; refresh evidence before changing status.
- [docs/DECISIONS.md](docs/DECISIONS.md) records durable technical decisions and their evidence. Read it when a change touches an existing decision.
- [docs/PHASE2_GAP_ANALYSIS.md](docs/PHASE2_GAP_ANALYSIS.md) is a dated historical audit. Use its issue IDs and rationale as context, then verify current source and tests.
- [docs/RELEASING.md](docs/RELEASING.md) applies to release work only.

Read only documents relevant to the task. Keep enduring rules here; keep implementation detail in Architecture, future intent in Roadmap, current status in Tasks, and rationale in Decisions. When evidence changes, update the relevant status document rather than copying the same details into every file.

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
- Do not change `VERSION` merely because code or documentation changed.
- Do not automatically switch branches, reset the worktree, or overwrite uncommitted files.
- Production deployment and destructive operations require explicit authorization.
