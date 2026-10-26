# T-15: actual candidate creation and write refusals

Continue after the actual rename refusal stage. Reuse its publisher subprocess,
guard, transaction identity, complete compensation and VM reboot facilities.
Keep the existing pending-create and rename variants compatible.

- [x] Record host refusal RED for the explicit create/write candidates and a
      real, isolated Python write-limit test before implementing those variants.
- [x] Creation: enter the existing private read-only bind at the actual mkstemp
      call for the publisher's .commit- candidate; observe real EROFS, not an API
      replacement. Preserve and verify the owned mount's retirement.
- [x] Write: after candidate creation, validate its exact FD/inode and limit
      only the publisher subprocess's soft RLIMIT_FSIZE to0, keeping its hard
      limit unchanged. Require Python's existing ignored SIGXFSZ policy; observe
      actual EFBIG from its marker write/flush. Restore and verify original limits
      before writing observer evidence; parent process limits must stay unchanged.
- [x] Keep uncertainty/no marker and original publisher/CLI73, complete actual
      resource/NSS/directory/service/applied compensation, no fixture repair.
      Repeat the established rename variant, then run normal14-case lifecycle
      and7 same-disk independent reboot checks.
- [x] Run guards/compilation/static checks, self-review and attempted independent
      review with exact availability, full encrypted image readback and host
      cleanup/database checks. Update TASKS and locally commit the stage.

EFBIG is a process-scoped kernel file-size refusal, not ENOSPC/EIO or damaged
physical storage. No producer file API, transaction callback or service command
is replaced. No host or manager limit/mount changes are authorized by this test.

Evidence: RED `pnm-marker-candidate-red.ar0ulmg6`; final26-guard/static/compile
checks `pnm-marker-candidate-final.sco0sk7e`; successful complete VM image
`pnm-vm-boot-volume.smlq1v57`. Earlier `pnm-vm-boot-volume.op1m0hdn` passed the
guest checks but its D-backed encrypted export failed EIO, so is not a verified
retained image. Its failed artifacts remain. The successful run uses the exact
protected Linux control/image path after Windows C capacity verification and
output-guard checks. Independent review remains unavailable by usage capacity;
self-review and executed checks are the validation boundary.
