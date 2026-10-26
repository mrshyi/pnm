# Native account deletion refusal retains incomplete recovery

Continue T-08/G-06 from `1b49c04`, separately from creation compensation.

- [x] Add guarded generic account-tool/deletion-case entries and observe RED.
- [x] Reuse the reviewed private-child read-only `/etc` context for exact
      `userdel -- hysteria` or `groupdel -- hysteria`. Require original actual
      identities, expected partial removal point and both services already
      absent/inactive/PID0. Delegate other/recovery tool calls unchanged.
- [x] In each fresh guest, combine the existing real publisher EROFS73 with one
      actual deletion refusal. Require CLI70, original73/recovery70, retained
      RECOVERY_REQUIRED and unfinished owned-account receipts, no marker or
      commit, restored original ordinary resources/services and precisely the
      remaining owned identities. Do not claim full NSS/directory recovery.
- [x] Restore both PATH scopes and run four fresh protected commands: require
      exact deployment refusal70, empty stdout and unchanged primary NSS,
      PNM receipts, remaining resources/directories and service state. Retain
      the unresolved guest without manual cleanup or fabricated recovery.
- [x] Run guards, Python compilation/static checks and independent review;
      execute separate userdel/groupdel native guests, verify encrypted-image
      readback and host/mount/loop cleanup, update TASKS/guide, review and commit.

No product code hook, shell-function replacement, host account modification or
cross-process automatic recovery is introduced. Kernel probe and actual shadow
tool error remain separate observations. Other NSS backends/media/VM gates stay
open; primary NSS excludes ancillary shadow-tool backup files.

Initial userdel `03i3l3z_` passes5/5 with verified encrypted evidence. Groupdel
`plytlxc6` failsCLI73: verified read-only image extraction proves default
USERGROUPS_ENAB=yes removed the private group during userdel; the group RESTORED
receipt exists and no groupdel wrapper attempt occurred. Retain that failed image
and do not count it as groupdel refusal. The installed shadow manual documents
the same policy. Only the fresh groupdel fixture changes the protected unique
setting to no before baseline, preserves ownership/mode/inode, and compares
login.defs as a resource. Userdel still tests Debian's default yes. Independent
review accepts this fixture repair; final three native regressions follow.

Final groupdel `kxu3cfbs` passes5/5 under
`/var/tmp/pnm-account-delete-group-final-volume.qluan8iw`, default-policy userdel
`g7re80jp` passes5/5 under
`/var/tmp/pnm-account-delete-user-final-volume.ehcq2731`, and shared creation
regression `pqxtqvyd` passes16/16 under
`/var/tmp/pnm-account-creation-final-regression-volume.zpaqug3_`. All three retain
verified full encrypted-image readback, detached loops, no cleanup errors,
unchanged host DBs/not-found scopes/no mounts and Native/Make0. Eleven guards,
19 Python compilations and static gates pass; final review finds no blocker.
Product Bash remains the verified31/391 baseline. Continue the separate
independent Debian kernel VM plan after committing this increment.
