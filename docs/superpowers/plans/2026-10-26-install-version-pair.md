# First-install approved binary/version consistency

Source review finds that update compares staged binary versions to approved
versions, whereas actual host first-install staging publishes verified bytes
without comparing the binaries' reported versions to the manifest. Prove the
specific trigger before changing product behavior.

- [x] RED: isolated staging tests with safe fixture programs and forbidden real
      writes show that wrong/unparseable/failing versions reach publication.
- [x] At real-host sandbox staging, reuse the existing version-number adapter and
      manifest parser to reject either mismatch before publishing either binary.
      Preserve isolated synthetic sandbox behavior and all public interfaces.
- [x] Positive matching-pair staging and both-Core negative tests pass; execute
      syntax/security/ShellCheck and a fresh complete default regression.
- [x] Reuse separately verified official prior assets in the actual VM first-
      install acquisition fixture: approve their hashes with current version
      labels, require original78 and full rollback for each Core, then normal
      installation/reboot and encrypted image/host/cleanup verification.
- [x] Update implementation/status documentation, review and locally commit.

No version rotation, new asset source, protocol, lifecycle coupling or release.
The checksum remains mandatory; a checksum match alone does not prove the user-
requested version pair. Never execute unverified acquisition bytes.

Evidence: four negative RED cases `pnm-install-version-red.9lj1i3u6`,5-case GREEN
`pnm-install-version-green.1up2p8u0`;30 guards/28 compilations/static gates
`pnm-install-version-preboot.43v0k2lp`; fresh32 suites/399 tests
`pnm-install-version-full.gpn5pjlr`. VM `pnm-vm-boot-volume.q_ry4hhc` passes9
refusals +14 lifecycle +7 reboot checks, complete2GiB encrypted readback and
host/QEMU/loop cleanup checks. Independent review remains usage-limited; review
is self-review and executed validation. No production deployment/version/release.
