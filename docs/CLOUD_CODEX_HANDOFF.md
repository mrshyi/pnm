# Cloud Codex CLI Handoff

This note prepares repository work to continue in a cloud Linux workspace using
Codex CLI. It does not authorize deployment, production access, or changes to
cloud networking or services.

## Current source baseline

- Branch: `dev`
- Handoff preparation baseline: `0.16.0-rc.1`
- The configured-port VM verification stage is recorded in `docs/TASKS.md` and
  committed as `87f2b85` (`test: verify configured ports through VM reboot`).
- The branch was 81 commits ahead of `origin/dev` after that commit. The cloud
  workspace must receive the intended commits through an approved repository
  synchronization or transfer before it can continue from this baseline. A
  normal clone of the current remote may omit this work. No push was performed.
- The source worktree had a pre-existing untracked
  `tests/integration/__pycache__/` directory. It was deliberately left out of
  commits; do not treat it as source or copy it as a deliverable.

Recent committed work includes VM coverage for inode exhaustion, recovery after
ENOSPC, runtime evidence and lock contention, and configured ports across a
same-disk reboot. Read each commit and the dated evidence in `docs/TASKS.md`
before extending its status. These commits do not close the broader Phase 3,
platform, deployed-source-identity, or external-client acceptance gaps.

## Bring up a repository workspace

Use the organization-approved cloud account, repository transfer route, and
Codex CLI installation procedure. Do not place SSH keys, access tokens, private
repository URLs containing credentials, or server credentials in this file or
in prompts.

After the authorized source transfer, enter the repository root and verify the
checkout before starting work:

```bash
cd /path/to/pnm
git status --short --branch
git log -1 --oneline
git rev-parse --verify 87f2b85^{commit}
codex
```

If `87f2b85` is absent, stop before editing and complete the approved source
synchronization. Do not reset, clean, or overwrite a worktree with local changes.
Keep any unrelated staged, unstaged, and untracked files intact.

## First Codex CLI session

At the start of the session, ask Codex to:

1. Read `AGENTS.md`, `docs/TASKS.md`, `docs/ARCHITECTURE.md`,
   `docs/ROADMAP.md`, and `docs/ACCEPTANCE_PLAN.md`.
2. Inspect the actual source and tests for the next open task; plans and reports
   are not proof of current implementation.
3. Refresh the environment and repository evidence before changing task status.
4. Make the smallest root-cause change, preserve the two independent managed
   cores and existing CLI/configuration/URI contracts, and update the relevant
   task record with exact validation boundaries.
5. Run applicable repository checks and report their exact commands/results.

The user's working instruction is to complete and commit each local stage, then
continue with the next stage. This does not authorize pushing, publishing a
release, deploying to a server, or changing production services. Do not change
`VERSION` just because code or documentation changed.

## Validation boundaries

In a prepared Linux development workspace, the repository acceptance plan lists
these checks:

```bash
make check
make shellcheck
make release-check
```

Record separate exit codes and results. `make release-check` includes
`make check`; do not count the repeated run as additional independent test
coverage.
The latest configured-port slice also recorded 26 integration Python
compilations, 33 guards, static/security checks and ShellCheck, plus an approved
Debian VM conflict/lifecycle/same-disk-reboot run. Those results describe the
prior environment and do not establish that the cloud host has equivalent
capabilities.

Do not assume a cloud VM offers `/dev/kvm`, nested virtualization, systemd boot,
or an approved disposable root filesystem. Run the existing independent-VM
acceptance only after verifying those prerequisites and its guarded cleanup
path. Otherwise continue with the applicable source/mock checks and record the
VM acceptance as unavailable; do not relabel it as passed.

## Safety and open acceptance

- Do not copy private `/var/tmp/pnm-*` VM images, encrypted archive fixtures,
  credentials, real node configuration, client share links, or test secrets to
  cloud storage. Use only approved public/fixed fixtures or explicitly approved
  test assets.
- Do not modify production systemd services, SSH, Tailscale, users or authorized
  keys, UFW, cloud firewall rules, or running proxy nodes. This handoff is for
  repository development only.
- Never log private keys, passwords, credentials, or complete client URIs.
- Keep L1 mock/source checks, L2 disposable Debian systemd VM results, real VPS
  source-identity checks, and L3 external-client connectivity as separate
  evidence. The known environment is Debian WSL; it is not production VPS or
  external-client acceptance.
- Consult `docs/TASKS.md` and `docs/ACCEPTANCE_PLAN.md` for open items. In
  particular, broader storage/interleaving coverage, supported-platform
  coverage, authorized deployed-source identity, and external Xray/Hysteria2
  client traffic remain distinct acceptance work.

## References

- [Current task status](TASKS.md)
- [Architecture](ARCHITECTURE.md)
- [Roadmap](ROADMAP.md)
- [Acceptance plan](ACCEPTANCE_PLAN.md)
- [Configured-port VM verification plan](superpowers/plans/2026-10-26-vm-configured-ports.md)
