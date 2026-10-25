# T-15: actual marker rename refusal after durable uncertainty

Continue the authorized Phase3 transaction acceptance after T-16. Reuse the
existing publisher-only private namespace, readonly bind and complete deployment
compensation assertions. No product file API or service function is replaced.

- [x] Record host refusal RED and cover observer timing while extending the
      existing commit fault helper. Default mapped-container behavior stays intact.
- [x] Allow only the explicit rename variant to use the approved VM guard.
      The readonly bind helper receives that guard explicitly; its default
      account/startup/publication users keep their existing guard.
- [x] Observe the unchanged stdin publisher after its marker candidate is
      written/fsynced/closed and before os.replace. Bind its transaction directory
      read-only only inside that publisher's private mount namespace. Observe
      the real os.replace EROFS with matching source/destination; retain uncertainty
      and no marker, then retire the owned mount before returning to the CLI.
- [x] Require original publisher/CLI73 and complete resource, identity, directory,
      unit and applied compensation. Inspect the retained uncertainty without
      deleting or repairing it. Actual fresh commands/retry determine whether
      the completed rollback is recognized, rather than assuming it from flags.
- [x] Run the normal14-case lifecycle and7 same-disk reboot checks on a new
      private VM; verify full encrypted image readback, host database equality
      and exact process/mount cleanup. Review, document and locally commit.

This is kernel EROFS on actual rename, not physical EIO or arbitrary fault timing.
Keep other matrix positions, deployed identity, external clients and other
platforms explicitly separate.

Executed `pnm-vm-boot-volume.36t5df2a`: actual rename EROFS, publisher/CLI73,
complete compensation and retained uncertainty/no marker, then clean14-case
retry/lifecycle and7 reboot checks pass. Full2GiB encrypted readback matches;
loop detached, QEMU quiescent, host databases unchanged and cleanup empty.
Preboot guards23/23,23 integration compilations and static checks pass. The
independent reviewer is still usage-limited; no independent approval is claimed.
