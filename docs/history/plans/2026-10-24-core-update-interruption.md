# Native update and rollback process interruption

Continue T-19/T-22 after deployment interruption commit2d26132. Reuse the
existing actual old/current pinned versions, loopback HTTPS transport, CLI session
watcher and delayed real start. No production hooks or fake Core binaries.

TERM each Core's update and rollback after binary publication/start attempt:
preserve143, restore original binary/config/previous resources and metadata,
reactivate the original version with confirmed applied binding, preserve peer,
complete rollback and finish the normal distinct-version matrix. Count the extra
real update download. Independent SIGKILL fixtures cover each operation/Core:
candidate binary/version is active, prior applied/previous evidence unchanged,
unfinished journal/no commit, then asset server retires before fresh writer and
protected reads refuse70 with the exact unresolved operation cause and no writes.

- [x] Add mapped-guest interruption-entry regression and observe RED.
- [x] Extend the existing update fixture with bounded TERM/SIGKILL modes.
- [x] Compile/static/guard checks and fresh real Core acceptance with retained evidence.
- [x] Review, update status and commit.

Each SIGKILL case completes the initial14-case main flow but intentionally does
not complete the update matrix; report both boundaries. These startup windows
do not close late previous/metadata/commit publication, restore interruption,
independent kernel reboot, deployed-source identity or external clients.

Entry regression first failed with the absent interruption keyword, then passed
all9 offline guards after the guarded entry was implemented. Fifteen Python
sources compile; syntax/security/ShellCheck pass. TERM `7j76s5tp` passes26/26,
including both operations on both Cores and the full successful version matrix;
control `/var/tmp/pnm-update-term-volume.t4khgkre` verifies full encrypted-image
readback, detached loop and empty cleanup errors. SIGKILL Xray update `3dpcxgms`
passes17/17 with the expected incomplete update matrix; control
`/var/tmp/pnm-core-update-sigkill-xray-volume.qd0i2b31` also verifies readback and
clean retirement. Update HY2 `_cqcdl7y` passes21/21, rollback Xray `2r8p2l7r`
passes18/18 and rollback HY2 `ht89ott5` passes22/22. Respective controls
`/var/tmp/pnm-core-update-sigkill-hysteria2-volume.qqg8cyxp`,
`/var/tmp/pnm-core-rollback-sigkill-xray-volume.h2akq7k8` and
`/var/tmp/pnm-core-rollback-sigkill-hysteria2-volume.vhsoaqxh` each verify full
encrypted-image readback, detached loop and no cleanup errors. All native/Make
exits0 retain unchanged host databases, not-found scopes and no fixture mounts.
Two independent static reviews found no blocker. Product Bash is unchanged;
the31-suite/389-test baseline was not repeated for this test-only increment.
The task runner now reports usageLimited; close this increment without starting
restore interruption, late-publication faults or any new stage.
