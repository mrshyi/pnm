#!/usr/bin/env python3
"""Offline guard: expected refusal logs must never mask safety failures."""
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock

sys.dont_write_bytecode = True
from test_real_cores import CheckFailed, Harness


class RefusalGuardTest(unittest.TestCase):
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
