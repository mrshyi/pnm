# Transaction filesystem safety implementation plan

Approved scope: A-02/A-05 safety prerequisites for deployment recovery. G-02's
deployment owner and commit marker remain a separate implementation slice.

Goal: restore file content/mode/numeric UID/GID, restore existing managed
directory metadata and remove only newly created empty directories, and reject
symlink ancestors before managed-path mutation. Reuse the Bash transaction API.

- [x] Add regression cases in `test_transaction.sh`, `test_host_apply.sh`, and
  `test_sandbox_install.sh`; reproduce failures in a temporary Debian copy.
- [x] Add a shared pre-mutation path check in `common.sh`; use it for host and
  sandbox paths and transaction snapshot/write/restore operations.
- [x] Extend `transaction.sh` with schema 2 file metadata and directory receipts;
  keep schema 1 inspection, reject legacy/unknown formats for new recovery writes.
  Validate records as data. Restore ownership before final mode and verify results.
- [x] Register directory compensation in `sandbox-install.sh` before directory
  creation; restore files before removing dependent identities/directories.
- [x] Run focused red/green tests, then `make check` and `make shellcheck` in
  Debian. Review the diff and update `docs/TASKS.md` with exact evidence.

Tests use temporary paths and mocked service/account operations. No production
apply, account/firewall changes, version change, Git commit or release is included.

Executed evidence and remaining baseline failures are recorded in `docs/TASKS.md`.
The completed checkbox records execution, not a claim that `make check` passed.
