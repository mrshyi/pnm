# Native managed-account TLS access acceptance

Scope: existing T-12/G-06 behavior in the private Debian guest. No product or
CLI changes. Reuse the installed managed hysteria identity, actual certificate
and key, diagnostic command and startup health gate. This continues the user's
authorized sequential main-flow acceptance work.

Use the existing lifecycle fixture rather than mock permissions or start another
VM framework. Test (1) wrong key owner with root-only read access and (2) correct
leaf metadata under a non-traversable TLS directory. For each, prove the actual
service account cannot read, diagnostics report FAIL, the deployment health gate
rejects, and inspection changes neither Core state nor persisted receipts/NSS.
Restore only owned fixture metadata in finally. Then run the real standalone
HY2 restart, verify applied binding and both links, and preserve the peer Core.
Do not infer current runtime TLS material from link/configuration evidence alone.

- [x] Add guarded scenario and offline host-refusal regression; show RED first.
- [x] Implement isolated permission cases and compile/static/guard checks.
- [x] Run fresh native case using reviewed private D storage and retain evidence.
- [x] Review outcomes, update status, and commit exact files.

Independent kernel reboot, external clients and deployed-source identity remain
outside this local test. Never print diagnostics containing credentials or URIs.

Offline RED: nine checks ran, with one missing-module failure. GREEN: nine pass;
nine Python sources compile, and syntax/security/ShellCheck pass. Independent
read-only review found no blocking issue. The first native fixture `f3lk33j8`
completed the original14 cases then stopped at the new test's incorrect failure
code1; existing common.sh and check tests specify FAIL=2. Only the assertion was
corrected. Its failed evidence is retained in the encrypted private volume under
`/var/tmp/pnm-tls-volume.wtzitxoi` (verified readback, loop detached, no cleanup
errors); it is not a passing TLS acceptance run. A fresh guest is required.

Final fresh `qktokjdj` passes17/17, including both negative permission cases and
the real post-repair HY2 restart. Native/Make exit0, host databases unchanged,
scope not-found, no fixture mounts. Protected control/key/results are under
`/var/tmp/pnm-tls-green-volume.d1xlzf9b`; its full image is retained as
`pnm-tls-green-volume.d1xlzf9b.ext4.gz.enc` in the private-storage plan's ignored
D pool. Trusted cipher and complete raw-image readback hashes verify, the loop
is detached and cleanup errors are empty. Final independent review accepts the
failure-code correction. Product source retains the31-suite/380-test baseline;
this test-only increment does not claim external traffic or VM reboot acceptance.
