# Native account creation refusal and compensation

Continue T-08/G-06 from `6a7e970`. Reuse the existing mapped Debian guest and
private-child read-only bind. No host account or NSS changes are authorized.

- [x] Add guarded account-refusal entry points and observe missing implementation
      RED before adding a narrowly scoped useradd/groupadd launcher.
- [x] Target only the exact normal `hysteria` account/group creation command,
      after the actual Xray identity exists. Run the real shadow tool under a
      private child read-only `/etc` bind, require actual nonzero failure and
      kernel EROFS probe, then retire only that child's exact owned mount.
- [x] In one fresh guest, fail groupadd and useradd separately. Require real
      CLI70, actual prior account creation receipts, complete primary NSS bytes
      and metadata, absent managed identities/resources and original service/
      directory baseline, no commit/applied promotion and completed rollback.
      Delegate all unrelated/recovery tool calls; restore PATH between cases.
- [x] Follow with the complete normal lifecycle/backup-restore flow. Run guards,
      Python compilation and static checks, obtain independent review, retain
      verified encrypted native evidence and host/loop cleanup, update status/
      guide, inspect the exact stage and commit.

This is a transient kernel read-only refusal of actual creation tools, not a
claim about all PAM/NSS backends, account deletion failures, physical media or VM
reboot. Primary NSS state means passwd/group/shadow/gshadow; ancillary shadow-tool
backup files are outside that assertion.

Missing-module guards first fail. Final11 guards and19 Python compilations plus
static gates pass under `/var/tmp/pnm-account-final-gates.bhnu66xg`. Native
`uvjp4dv2` passes16/16 under `/var/tmp/pnm-account-creation-volume.dye5wq46`,
including both failure positions,2/3 actual created identities completely
compensated and the full healthy normal retry. Native/Make0 leaves unchanged
host DBs, not-found scope and no mounts; full encrypted-image readback verifies,
loop detaches and cleanup errors are empty. Independent final review finds no
blocker. Product Bash is unchanged;31/391 remains the full baseline. Continue
account deletion failure as a separate retained-recovery increment.
