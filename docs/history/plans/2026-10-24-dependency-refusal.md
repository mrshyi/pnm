# Native installation dependency refusal matrix

Continue G-05/T-03 after ordinary-restart commit22e088b. Exercise the real CLI
and its JSON installation preflight, rather than replacing command discovery or
service/account functions. Within the guarded clean native guest, create a
private flat PATH of links to trusted installed programs. Temporarily remove
only this fixture's link for each of the19 declared prerequisites: base tools,
systemctl, Xray ZIP, TLS, unit validation, account creation/removal and runuser.
Restore the original environment and private link in finally for every case.

Each actual install --apply must refuse2 with the matching FAIL check, preserve
the node/version/NSS file fingerprints and transaction set, leave managed Core
resources/accounts absent, and leave the original units/processes absent. Do
not claim zero audit/cache writes. Then complete the original14-case lifecycle
without changing host packages, binaries, accounts, services or network.

- [x] Add guarded helper refusal regression and observe RED.
- [x] Implement19 real-tool negative cases and extend the opt-in driver only.
- [x] Compile/static/guard checks and fresh native scenario with retained evidence.
- [x] Review outcomes, update G-05 status, and commit exact files.

This is missing-tool preflight on the prepared Debian guest, not acquisition
from upstream, other supported distributions, VM reboot or external clients.

Offline RED ran9 checks with the intended missing-module failure, then GREEN
passes9/9. Twelve Python sources compile and syntax/security/ShellCheck pass.
Independent source review found no blocking issue. Fresh `fitvjgzu` passes33/33:
all19 exact dependency classes refuse2 with preserved state and no new transaction,
then all14 normal main-flow checks pass. Native/Make exit0, unchanged host databases,
not-found scope and no mounts. Protected control is
`/var/tmp/pnm-dependency-volume.7got3ah5`. The full encrypted image in the existing
ignored D pool passes trusted cipher/raw readback verification; loop detached,
cleanup errors empty. Retain the protected control/key with that archive.
Product source remains the final31-suite/385-test baseline; this increment changes
only opt-in acceptance tests and documentation, without repeating the full suite.
