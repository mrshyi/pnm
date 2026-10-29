# Release checklist

Phase7 preparation does not authorize publishing, deployment, version changes or
Git mutations. The steps below apply when that specific release is authorized.
Current source/test evidence and blockers live in [TASKS](TASKS.md).

## Source release

1. Confirm the intended files are committed and the working tree is clean.
2. For the authorized release, select its version and update `VERSION` and
   `CHANGELOG.md` together. Unreleased development changes do not require a bump.
3. Run `make check`, `make shellcheck`, and `make release-check`; retain exact
   source identity, exits and skips. Verify Ubuntu22.04/24.04 CI on the actual
   candidate commit, including the selected root/systemd/Core steps and both native
   architectures. A workflow definition or a different source commit's success is not a passing candidate.
4. Review the staged diff for credentials, private keys, backups, logs, and generated artifacts.
5. Confirm repository security settings and private vulnerability reporting with
   the repository owner; account-setting changes require their authorization.
6. After approval of the concrete candidate and checks, create an annotated
   version tag and publish the source from that tag. Do not attach an old workspace archive.

## Production readiness

A source release or passing local tests alone does not make a node production-ready.
Use an explicitly authorized disposable supported amd64/arm64/systemd target; do not
provision the ARM64 development host or reboot a CI controller to satisfy this list.

1. Verify target identity, copied source, approved asset hashes and the allowed
   install/account/failure/reboot scope. Follow the existing finite
   [Ubuntu U-01–U-08 contract](ACCEPTANCE_PLAN.md#ubuntu-closeout); Debian and other
   unexecuted platform/client evidence remain explicitly unverified.
2. Follow [README setup](../README.md#configure-one-node): initialize and validate
   desired state, preview installation, then install the two approved Cores.
   `./bin/pnm install` runs Core installation from source; it does not install the
   PNM CLI wrapper. CLI installation uses the separately reviewed `install.sh`.
   External-CA installation also requires the documented certificate/key inputs.
3. On the installed node, verify the normal `dual`→`reality`→`hy2`→`dual` Profile
   flow and existing selected compensation behavior, retaining credentials/files
   and unchanged-peer invocation evidence. Do not add speculative fault campaigns.
   Check the configured TCP/UDP ports and desired service policy; default443/8443
   and both-active state are not universal requirements after customization.
4. Collect `pnm status`, `pnm check`, optional `check --resources` and sanitized
   `recovery list|inspect` results with their exact exits. Recovery diagnostics
   preserve evidence and never certify successful automatic replay. Validate
   same-disk reboot persistence through U-08 and reconnect only through the
   operator's approved management path. PNM does not modify SSH or firewall rules.
5. Test VLESS REALITY and Hysteria2 separately from authorized external clients.
   Local services, listeners, resource observations and fixtures do not prove
   public protocol connectivity.
6. Record sanitized evidence and exact PNM/Core versions, source SHA and any
   worktree delta. Never publish secrets, full share links or backup archives.

Stop at documented missing prerequisites or reproduced failures. Missing targets,
assets or authorization remain BLOCKED; implementation and local gate completion
must not be relabeled as full platform or production acceptance.
