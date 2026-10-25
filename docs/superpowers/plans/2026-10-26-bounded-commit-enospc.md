# T-15 bounded tmpfs ENOSPC publisher checks

The existing independent-VM operator requires a2GiB disk plus ciphertext and
operating margin; neither Windows backing volume currently has that capacity.
Keep all retained evidence. Continue a smaller, explicit publisher-only slice.

Use the unchanged deployment marker shell/Python helper with synthetic protected
transaction records. A new child mount namespace owns only a unique root0700
temporary directory and a64KiB tmpfs with64 inodes, nodev/nosuid/noexec. Observe
the actual publisher without replacing its stdin or file APIs. At candidate
creation exhaust only that tmpfs's inodes; at candidate write exhaust only its
data blocks. Each must return73 with actual ENOSPC, no marker/candidate and
retained pending evidence. Retire the exact owned mount and prove parent mount
table/namespace and host databases remain unchanged. No services or accounts run.

- [x] Host refusal regression fails before the fixture exists, then passes.
- [x] Actual bounded inode/data exhaustion tests and safety/cleanup checks pass.
- [x] Compile, existing guards, syntax/security/ShellCheck and docs checks pass.
- [x] Review, record exact L1 publisher boundary and locally commit.

This is a Linux tmpfs publisher slice with synthetic records, not whole-deployment
compensation, independent-kernel ENOSPC, physical-media EIO or full T-15 closure.

RED: `pnm-bounded-storage-red.d4plgzfj`. Final actual2 cases/28 guards/24 Python
compilations/static gates: `pnm-bounded-storage-final.138tyvnl`. Entry/nonroot
checks: `pnm-bounded-storage-refusals.vkf1dz2s` and
`pnm-bounded-entry-refusals.ymgvrs39`. Fresh31-suite/394-test default regression
and final28 guards: `pnm-bounded-full-corrected.omxdc7dv`;19 document paths pass.
The first full copy `pnm-bounded-full.99nobvbg` failed its real nobody case because
its enclosing log directory was0700. Keep the failure; corrected public trusted
source and private logs are separate. Independent reviewer remains usage-limited,
so the review boundary is self-review plus executed checks.
