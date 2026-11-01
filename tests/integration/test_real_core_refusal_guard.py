#!/usr/bin/env python3
"""Offline guard: expected refusal logs must never mask safety failures."""
from pathlib import Path
import sys
import stat
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

sys.dont_write_bytecode = True
from test_real_cores import CheckFailed, Harness, core_manifest_path, load_core_manifest


class RefusalGuardTest(unittest.TestCase):
    def test_manifests_select_native_architecture_and_reject_foreign_pins(self) -> None:
        for machine, architecture in (("x86_64", "amd64"), ("aarch64", "arm64")):
            with self.subTest(machine=machine), patch("test_real_cores.platform.machine", return_value=machine):
                for previous in (False, True):
                    manifest = load_core_manifest(core_manifest_path(previous=previous))
                    self.assertEqual(manifest["architecture"], architecture)
                    self.assertIn("arm64" if architecture == "arm64" else "linux-64", manifest["xray"]["url"])
                    self.assertTrue(manifest["hysteria2"]["url"].endswith("linux-" + architecture))
                foreign = core_manifest_path()
            other = "aarch64" if machine == "x86_64" else "x86_64"
            with patch("test_real_cores.platform.machine", return_value=other):
                with self.assertRaisesRegex(CheckFailed, "architecture differs"):
                    load_core_manifest(foreign)
        with patch("test_real_cores.platform.machine", return_value="armv7l"):
            with self.assertRaisesRegex(CheckFailed, "unsupported"):
                core_manifest_path()

    def test_cleanup_matches_fixture_parent_and_refuses_identity_drift(self) -> None:
        harness=Harness()
        root=Mock(spec=Path)
        root.parent=harness.root.parent
        root.name=harness.root.name
        root.lstat.return_value=SimpleNamespace(st_mode=stat.S_IFDIR|0o750,st_uid=0,st_dev=1,st_ino=2)
        harness.root=root
        harness.identity=(1,2)
        with patch("test_real_cores.shutil.rmtree") as remove:
            self.assertTrue(harness.cleanup(True))
            remove.assert_called_once_with(root)
            remove.reset_mock()
            root.parent=Path('/unexpected')
            with self.assertRaisesRegex(CheckFailed,'fixture identity changed'):
                harness.cleanup(True)
            remove.assert_not_called()
            root.parent=Path('/opt')
            root.lstat.return_value.st_ino=3
            with self.assertRaisesRegex(CheckFailed,'fixture identity changed'):
                harness.cleanup(True)
            remove.assert_not_called()

    def test_start_safety_failures_propagate_before_refusal_evidence(self) -> None:
        for label in ("actual process identity mismatch", "actual process privilege mismatch",
                      "helper did not join the Core network namespace", "systemd observation failed"):
            with self.subTest(label=label):
                fake = Mock()
                fake.prefix, fake.units, fake.hy2 = "offline", {}, Path("/not-executed")
                fake.root = Path("/not-executed")
                fake.value.return_value = "inactive"

                def unsafe_start(*_args: object, **_kwargs: object) -> None:
                    fake.units["offline-0-bad-auth.service"] = "fixture"
                    raise CheckFailed(label)

                fake.start.side_effect = unsafe_start
                with self.assertRaisesRegex(CheckFailed, label):
                    Harness.reject_hy2(fake, 0, "fixture", "fixture", "bad-auth", "expected cause", "marker")
                fake.require_cause.assert_not_called()
                fake.wait_probe.assert_not_called()
                fake.check.assert_not_called()


if __name__ == "__main__":
    unittest.main()
