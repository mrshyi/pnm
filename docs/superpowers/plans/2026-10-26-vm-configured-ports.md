# T-04 independent VM configured-port refusal and reboot

Continue from `ce55287`. Replay the existing `configured-ports` cases on the
approved VM: custom TCP10443/UDP18443 conflicts refuse before publication, while
unrelated TCP443/UDP8443 fixture listeners survive the full normal lifecycle.

- [x] Reuse the existing conflict/resource/NSS/transaction and normal lifecycle
      assertions; admit the exact14+2 check count in the VM validator.
- [x] Bind a private reboot listener-port baseline to the selected scenario and
      actual persisted node ports. Reboot must query those ports; older private
      baseline records without the optional field retain their default ports.
- [x] Run26 Python compilations,33 guards and syntax/security-scan/ShellCheck.
- [x] Execute the actual conflict refusal, custom-port normal lifecycle and
      peer isolation, then7 same-disk reboot checks with actual custom listeners.
- [x] Verify encrypted2GiB readback, unchanged host databases, quiescent QEMU,
      detached loop and empty cleanup; review, update status and commit locally.

The product/unit source and full32-suite/399-test baseline remain unchanged.
Default fixture listeners are process-owned before reboot; no claim is made that
those fixture processes survive a new kernel. Physical media, every scheduling
interleaving, other platforms, deployed identity and external traffic remain open.

Focused source copy `/var/tmp/pnm-inode-check.h6mxn4ah` passes26 integration
Python compilations,33 guards and all static checks (exit0). Independent read-only
review finds no blocking baseline/count/listener or compatibility issue.
