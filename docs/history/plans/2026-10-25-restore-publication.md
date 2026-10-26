# Native partial restore publication failure plan

Continue T-24 from `d475c80` under consecutive-stage authorization. Reuse the
verified private-child-namespace EROFS move fixture and the existing restore
startup-failure case's resource/NSS/directory/binding/retry checks. No production
function changes or host mounts. The trusted archive must differ from current
desired/applied Xray state before restore starts.

- [x] Extend the existing unsafe-work-directory guard to the new
      restore-publication scenario and observe RED before adding its dispatcher.
- [x] Allow only the additional fixed /etc/hysteria/config.yaml destination in
      the existing IO fixture, copy it for this case and reuse restore failure
      validation with real73, actual EROFS receipt and no leftover child bind.
- [x] Require journal WRITE count greater than0 and less than the ordinary
      archive resource count, complete ROLLED_BACK without commit/uncertainty,
      both original resources/metadata/NSS/directories and fresh applied bindings,
      then successful trusted archive retry. Preserve the existing startup case.
- [x] Run9 offline guards,16 Python compilations, static gates and one fresh
      native guest; verify full encrypted-image readback and host/loop cleanup.
- [x] Independent review, refresh TASKS/guide, inspect staged/unstaged diffs and
      commit this stage before moving to commit/marker fault acceptance.

This transient VFS refusal does not prove persistent media, journal durability,
VM/kernel reboot, deployed-source identity or external client connectivity.

The new scenario first fails with an invalid argparse choice, then9 guards pass
after routing is implemented, preserving unsafe-directory refusal before fixture
access. Sixteen Python sources compile and syntax/security/ShellCheck pass.
Independent pre-execution review finds no blocker. Native control
`/var/tmp/pnm-restore-publication-volume.5yo2uajz` runs `sbvfde8t`, now16/16:
4 of12 ordinary resources publish before the real EROFS failure, the distinct
archive node has APPLIED evidence and the failed target does not. Both original
resources and generations recover; trusted retry succeeds. Native/Make0 leaves
unchanged host DBs, scope not-found and no mounts. Full encrypted-image readback,
detached loop and empty cleanup errors are confirmed. Final review has no blocker.
Product Bash is unchanged; the31-suite/389-test baseline was not repeated.
