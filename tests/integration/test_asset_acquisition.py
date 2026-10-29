#!/usr/bin/env python3
"""Real loopback curl/TLS checks; synthetic assets, no Core or host installation."""
from __future__ import annotations

import hashlib
import os
import platform
from pathlib import Path
import shutil
import ssl
import subprocess
import tempfile
import threading
import unittest

from guest_update_cases import AssetServer


PROJECT = Path(__file__).resolve().parents[2]
BODY = b"PNM private acquisition fixture\n"
XRAY_ASSET = "Xray-linux-arm64-v8a.zip" if platform.machine() == "aarch64" else "Xray-linux-64.zip"
HY2_ASSET = "hysteria-linux-arm64" if platform.machine() == "aarch64" else "hysteria-linux-amd64"
PINS = {
    "xray": ("v1.2.3", f"/XTLS/Xray-core/releases/download/v1.2.3/{XRAY_ASSET}"),
    "hysteria2": ("v2.3.4", f"/apernet/hysteria/releases/download/app/v2.3.4/{HY2_ASSET}"),
}
DOWNLOAD = r'''
set -Eeuo pipefail
umask 077
project=$1 core=$2 version=$3 digest=$4 destination=$5 receipt=$6 deadline=$7 retry_mode=$8
source "$project/lib/common.sh"
source "$project/lib/config.sh"
source "$project/adapters/assets.sh"
# Fault cases disable retries; retry cases preserve the production retry flags.
curl() {
    local rc=0
    local -a bounds=(--max-time "$deadline")
    [[ "$retry_mode" == default ]] || bounds+=(--retry 0)
    command curl --disable "$@" "${bounds[@]}" || rc=$?
    printf '%s\n' "$rc" >"$receipt"
    return "$rc"
}
pnm_asset_download_verified "$core" "$version" "$digest" "$destination"
'''


class AcquisitionTest(unittest.TestCase):
    def setUp(self) -> None:
        for tool in ("bash", "curl", "openssl", "sha256sum"):
            self.assertIsNotNone(shutil.which(tool), f"required tool unavailable: {tool}")
        self.private = tempfile.TemporaryDirectory(prefix="pnm-acquisition.")
        self.addCleanup(self.private.cleanup)
        self.root = Path(self.private.name)
        (self.root / "sentinel").write_bytes(b"unrelated fixture data")
        self.expected_errors: list[str] = []
        for name in ("trusted", "untrusted"):
            hostname = "github.com" if name == "trusted" else "pnm-untrusted.invalid"
            result = subprocess.run([
                "openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt",
                "ec_paramgen_curve:prime256v1", "-nodes", "-days", "1", "-subj",
                f"/CN={hostname}", "-addext", f"subjectAltName=DNS:{hostname}",
                "-keyout", str(self.root / f"{name}.key"),
                "-out", str(self.root / f"{name}.crt"),
            ], capture_output=True, timeout=10)
            self.assertEqual(0, result.returncode, "fixture certificate generation failed")
        self.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.context.minimum_version = ssl.TLSVersion.TLSv1_2
        self.context.load_cert_chain(self.root / "trusted.crt", self.root / "trusted.key")
        self.server = AssetServer({path: BODY for _, path in PINS.values()}, self.context)
        self.worker = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.worker.start()
        self.addCleanup(self.close_server)

    def close_server(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.worker.join(timeout=2)
        self.assertFalse(self.worker.is_alive(), "fixture server did not stop")
        self.assertEqual(self.expected_errors, self.server.errors)

    def finish_requests(self) -> None:
        for worker in self.server.request_threads:
            worker.join(timeout=2)
            self.assertFalse(worker.is_alive(), "fixture request did not retire")

    def download(self, core: str, *, checksum: bool = True, trusted: bool = True,
                 deadline: str = "5", default_retries: bool = False
                 ) -> tuple[subprocess.CompletedProcess, Path, int]:
        version, _ = PINS[core]
        destination = self.root / core
        receipt = self.root / f"{core}.curl-status"
        digest = hashlib.sha256(BODY).hexdigest() if checksum else "0" * 64
        environment = os.environ.copy()
        for name in ("http_proxy", "HTTP_PROXY", "https_proxy", "HTTPS_PROXY",
                     "all_proxy", "ALL_PROXY", "no_proxy", "NO_PROXY"):
            environment.pop(name, None)
        environment["https_proxy"] = f"http://127.0.0.1:{self.server.server_address[1]}"
        environment["NO_PROXY"] = ""
        environment["CURL_CA_BUNDLE"] = str(self.root / ("trusted.crt" if trusted else "untrusted.crt"))
        result = subprocess.run([
            "bash", "-c", DOWNLOAD, "pnm-acquisition", str(PROJECT), core, version,
            digest, str(destination), str(receipt), deadline,
            "default" if default_retries else "single",
        ], env=environment, capture_output=True, timeout=25)
        self.assertEqual(b"", result.stdout, "downloader must not publish an output path")
        self.assertTrue(receipt.is_file(), "real curl did not return a status")
        self.assertEqual([], list(self.root.glob(".pnm-asset.*")), "private candidate leaked")
        self.assertEqual(b"unrelated fixture data", (self.root / "sentinel").read_bytes())
        return result, destination, int(receipt.read_text())

    def assert_refused(self, result, destination: Path, curl_status: int,
                       expected_status: int, expected_curl: int) -> None:
        self.assertEqual(expected_curl, curl_status)
        self.assertEqual(expected_status, result.returncode)
        self.assertFalse(destination.exists() or destination.is_symlink())

    def test_verified_transport_publishes_private_content(self) -> None:
        for core in PINS:
            with self.subTest(core=core):
                result, destination, curl_status = self.download(core)
                self.assertEqual(0, curl_status)
                self.assertEqual(0, result.returncode)
                self.assertEqual(BODY, destination.read_bytes())
                self.assertEqual(0o600, destination.stat().st_mode & 0o777)
                self.assertEqual(os.geteuid(), destination.stat().st_uid)
        self.finish_requests()
        self.assertCountEqual([path for _, path in PINS.values()], self.server.requests)
        self.assertEqual([], self.server.errors)

    def test_checksum_mismatch_never_publishes(self) -> None:
        for core in PINS:
            self.assert_refused(*self.download(core, checksum=False), 78, 0)
        self.finish_requests()
        self.assertEqual([], self.server.errors)

    def test_transient_http_recovers_with_production_retries(self) -> None:
        self.server.retry_budget.update({path: 2 for _, path in PINS.values()})
        for core, (_, path) in PINS.items():
            result, destination, curl_status = self.download(core, default_retries=True)
            self.assertEqual(0, curl_status)
            self.assertEqual(0, result.returncode)
            self.assertEqual(BODY, destination.read_bytes())
            self.assertEqual(0o600, destination.stat().st_mode & 0o777)
            self.finish_requests()
            self.assertEqual(2, self.server.retry_requests.count(path))
            self.assertEqual(0, self.server.retry_budget[path])
        self.assertCountEqual([path for _, path in PINS.values()], self.server.requests)

    def test_transient_http_exhausts_production_retries(self) -> None:
        self.server.retry_budget.update({path: 3 for _, path in PINS.values()})
        for core, (_, path) in PINS.items():
            self.assert_refused(*self.download(core, default_retries=True), 69, 22)
            self.finish_requests()
            self.assertEqual(3, self.server.retry_requests.count(path))
            self.assertEqual(0, self.server.retry_budget[path])
        self.assertEqual([], self.server.requests)

    def test_partial_http_body_never_publishes(self) -> None:
        self.server.partial_paths.update(path for _, path in PINS.values())
        for core in PINS:
            self.assert_refused(*self.download(core), 69, 18)
        self.finish_requests()
        self.assertCountEqual([path for _, path in PINS.values()], self.server.partial_requests)
        self.assertEqual([], self.server.errors)

    def test_untrusted_tls_never_publishes(self) -> None:
        self.server.tls_refusal_budget = 2
        for core in PINS:
            self.assert_refused(*self.download(core, trusted=False), 69, 60)
        self.finish_requests()
        self.assertEqual(2, self.server.tls_refusals)
        self.assertEqual([], self.server.requests)
        self.assertEqual([], self.server.errors)

    def test_tls_handshake_timeout_never_publishes(self) -> None:
        self.expected_errors = ["asset request failed"] * 2
        for core in PINS:
            entered, release = threading.Event(), threading.Event()

            def stall(_connection, _name, _context):
                entered.set()
                release.wait(timeout=5)

            self.context.set_servername_callback(stall)
            try:
                self.assert_refused(*self.download(core, deadline="0.25"), 69, 28)
                self.assertTrue(entered.is_set(), "timeout did not reach the TLS fixture")
            finally:
                release.set()
                self.finish_requests()
        self.assertEqual([], self.server.requests)


if __name__ == "__main__":
    os.umask(0o077)
    unittest.main()
