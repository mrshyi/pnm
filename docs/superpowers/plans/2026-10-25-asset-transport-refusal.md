# T-03: actual update transport refusals

Continue the existing acquisition matrix after candidate commit refusal acceptance.
Reuse the private loopback-only HTTPS release fixture and real curl/update path;
no new transport or production configuration is introduced. A fake curl would
repeat existing L1 evidence. Changing host DNS/trust is unnecessary: serve a
deliberately truncated permitted asset and use the guest's unchanged public CA
bundle to reject the fixture's fresh private self-signed certificate.

- [x] RED: real curl in an isolated network namespace must receive18 for a
      Content-Length/body mismatch and60 for the untrusted certificate, with
      bounded connection/thread cleanup and no unexpected server errors.
- [x] Extend only the existing asset fixture: explicitly selected allowed paths
      may be truncated; accept only one specifically budgeted unknown-CA TLS
      alert per expected trust failure. Default handling remains unchanged.
- [x] For each Core, actual update must refuse69 with actual curl18/60 evidence,
      unchanged complete Core/peer resources, previous pairs, applied evidence
      and service invocation, and no new publication transaction. Restore only
      fixture transport settings before normal checksum/update/rollback/swap.
- [x] Run host guards, compile/static checks, real independent VM update/lifecycle
      plus same-disk reboot, encrypted image full readback and host/cleanup checks.
- [x] Reconcile matrix and self-review with exact independent-review availability;
      commit only the completed stage locally.

This is controlled HTTPS acquisition failure evidence through update. It does
not establish upstream DNS/PKI outages, first-install acquisition/ZIP failures,
external client traffic or production service acceptance.

Evidence: meaningful RED `pnm-asset-transport-red.y27zefj_`; final27 guards
`pnm-asset-transport-green.ofm5k3uc`;25 compilations/static gates
`pnm-asset-transport-preboot.11_2dbrr`; actual VM
`pnm-vm-boot-volume.c09hq622` passes14 lifecycle+12 update/refusal assertions
and7 reboot checks. Complete2GiB encrypted readback, QEMU0/quiescence, detached
loop, empty cleanup and fresh host NSS/dpkg hash equality pass.18 document paths
pass. Independent reviewer remains usage-limited; this is self-review plus
execution evidence. The final Windows C/D capacity is below a fresh2GiB raw disk
on either volume, so further heavy fault runs need adequate storage first; no
retained evidence is deleted to manufacture capacity.
