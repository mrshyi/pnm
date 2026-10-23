#!/usr/bin/env python3
"""Opt-in, pinned real-Core evidence; no production installation or host sockets."""
from __future__ import annotations

import hashlib
import io
import json
import os
from pathlib import Path
import pwd
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid
from urllib.parse import parse_qs, quote, unquote, urlencode, urlsplit
import zipfile


class CheckFailed(RuntimeError):
    """A safe diagnostic label, never raw Core output or configuration."""


class UnitExited(CheckFailed):
    """The candidate exec succeeded but its observed unit has already exited."""


# The pinned Xray blocks private/documentation destinations by default. This
# address exists only on lo inside the owned, interface-less test namespace.
ORIGIN_ADDRESS = "93.184.216.34"


def run(args: list[str], *, timeout: int = 20, pass_fds: tuple[int, ...] = ()) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=timeout, check=False, pass_fds=pass_fds)


def require(condition: bool, label: str) -> None:
    if not condition:
        raise CheckFailed(label)


def verified_assets(cache: Path, *, manifest_path: Path | None = None) -> dict[str, bytes]:
    require(cache.is_absolute() and cache == cache.resolve(), "asset cache must be canonical")
    info = cache.stat()
    require(stat.S_ISDIR(info.st_mode) and info.st_uid == 0 and stat.S_IMODE(info.st_mode) == 0o700,
            "asset cache must be root-owned mode 0700")
    manifest = json.loads((manifest_path or Path(__file__).with_name("real_core_versions.json")).read_text())
    result: dict[str, bytes] = {}
    for core in ("xray", "hysteria2"):
        asset = manifest[core]
        require(0 < asset["size"] <= 64 * 1024 * 1024, "asset size limit")
        path = cache / asset["filename"]
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as stream:
            item = os.fstat(stream.fileno())
            require(stat.S_ISREG(item.st_mode) and item.st_uid == 0 and not item.st_mode & 0o022,
                    "unsafe asset file")
            require(item.st_size == asset["size"], "asset size mismatch")
            data = stream.read(asset["size"] + 1)
        require(len(data) == asset["size"] and hashlib.sha256(data).hexdigest() == asset["sha256"],
                "asset digest mismatch")
        # Use the checked bytes, not a second path open, for extraction/execution.
        result[core] = data
    return result


class Harness:
    def __init__(self) -> None:
        account = pwd.getpwnam("nobody")
        require(account.pw_uid > 0 and account.pw_gid > 0, "nobody must be unprivileged")
        self.uid, self.gid = account.pw_uid, account.pw_gid
        # PrivateTmp hides /tmp and /var/tmp inside the units; /run stays visible.
        self.root = Path("/run") / ("pnm-realcore." + uuid.uuid4().hex)
        self.identity: tuple[int, int] | None = None
        self.prefix = "pnm-realcore-" + str(uuid.uuid4())
        self.units: dict[str, str] = {}
        self.namespaces: list[int] = []
        self.passed = 0
        self.stage = "fixture setup"
        self.drop = ["setpriv", f"--reuid={self.uid}", f"--regid={self.gid}",
                     "--clear-groups", "--no-new-privs", "--"]
        self.offline = ["unshare", "--net", "--"] + self.drop
        self.xray = self.root / "bin/xray"
        self.hy2 = self.root / "bin/hysteria"

    def prepare(self, assets: dict[str, bytes]) -> None:
        # The caller already owns this object, so every partial setup is covered
        # by finally/cleanup, including extraction or permission failures.
        self.root.mkdir(mode=0o700)
        info = self.root.stat()
        self.identity = (info.st_dev, info.st_ino)
        os.chown(self.root, 0, self.gid)
        self.root.chmod(0o750)
        for name in ("bin", "config", "config/secrets", "payload"):
            directory = self.root / name
            directory.mkdir(mode=0o750)
            os.chown(directory, 0, self.gid)
            directory.chmod(0o750)  # Restore required traversal after private umask.
        (self.root / "logs").mkdir(mode=0o700)
        with zipfile.ZipFile(io.BytesIO(assets["xray"])) as archive:
            member = archive.getinfo("xray")
            require(not member.is_dir() and not stat.S_ISLNK(member.external_attr >> 16)
                    and 0 < member.file_size <= 96 * 1024 * 1024, "unsafe Xray archive member")
            binary = archive.read(member)
        for destination, data in ((self.xray, binary), (self.hy2, assets["hysteria2"])):
            destination.write_bytes(data)
            destination.chmod(0o755)

    def write(self, name: str, content: str) -> Path:
        path = self.root / name
        path.write_text(content)
        os.chown(path, self.uid, self.gid)
        path.chmod(0o600)
        return path

    def check(self, label: str) -> None:
        self.passed += 1
        print(f"ok - {label}", flush=True)

    def value(self, unit: str, field: str) -> str:
        result = run(["systemctl", "show", unit, f"--property={field}", "--value"])
        require(result.returncode == 0, "systemd observation failed")
        return result.stdout.decode().strip()

    def start(self, label: str, args: list[str], *, join: str | None = None,
              environment: dict[str, str] | None = None) -> str:
        name = f"{self.prefix}-{len(self.units)}-{label}.service"
        require(self.value(name, "LoadState") == "not-found", "test unit collision")
        self.units[name] = args[0]  # Register intent before the manager can start it.
        properties = [f"Description={name}", f"User={self.uid}", f"Group={self.gid}",
                      "PrivateNetwork=yes", "NoNewPrivileges=yes", "PrivateTmp=yes",
                      "ProtectSystem=strict", "ProtectHome=yes", "CapabilityBoundingSet=",
                      "AmbientCapabilities=", "RuntimeMaxSec=180", "TimeoutStopSec=5",
                      f"StandardOutput=append:{self.root}/logs/{label}.log", "StandardError=inherit"]
        if join:
            require(join in self.units and self.value(join, "ActiveState") == "active", "join target inactive")
            properties.append(f"JoinsNamespaceOf={join}")
        if environment:
            properties.extend(f"Environment={key}={value}" for key, value in environment.items())
        command = ["systemd-run", "--quiet", "--collect", "--no-ask-password",
                   "--service-type=exec", f"--unit={name}"]
        command.extend(f"--property={item}" for item in properties)
        require(run(command + ["--"] + args).returncode == 0, "test unit exec failed")
        time.sleep(0.2)
        state = self.value(name, "ActiveState")
        if state in ("inactive", "failed"):
            raise UnitExited("test unit exited after exec")
        require(state == "active", "test unit did not stay active")
        pid = int(self.value(name, "MainPID"))
        status = Path(f"/proc/{pid}/status").read_text()
        require(f"Uid:\t{self.uid}\t{self.uid}\t{self.uid}\t{self.uid}" in status,
                "actual process identity mismatch")
        require("NoNewPrivs:\t1" in status and "CapEff:\t0000000000000000" in status,
                "actual process privilege mismatch")
        if join:
            target_pid = int(self.value(join, "MainPID"))
            require(os.stat(f"/proc/{pid}/ns/net").st_ino == os.stat(f"/proc/{target_pid}/ns/net").st_ino,
                    "helper did not join the Core network namespace")
        return name

    def namespace(self, unit: str) -> int:
        pid = int(self.value(unit, "MainPID"))
        fd = os.open(f"/proc/{pid}/ns/net", os.O_RDONLY)
        self.namespaces.append(fd)
        require(os.fstat(fd).st_ino != os.stat("/proc/self/ns/net").st_ino, "host network namespace refused")
        return fd

    def inside(self, fd: int, args: list[str], *, timeout: int = 15) -> subprocess.CompletedProcess[bytes]:
        # Pin the owned namespace by descriptor so a reused PID cannot select a host namespace.
        return run(["nsenter", f"--net=/proc/self/fd/{fd}", "--"] + self.drop + args,
                   timeout=timeout, pass_fds=(fd,))

    def prepare_origin_network(self, fd: int) -> None:
        require(os.fstat(fd).st_ino != os.stat("/proc/self/ns/net").st_ino,
                "host network namespace refused")
        command = ["nsenter", f"--net=/proc/self/fd/{fd}", "--", "ip"]
        links = run(command + ["-j", "link", "show"], pass_fds=(fd,))
        require(links.returncode == 0 and [link["ifname"] for link in json.loads(links.stdout)] == ["lo"],
                "test namespace has an unexpected interface")
        require(run(command + ["address", "add", f"{ORIGIN_ADDRESS}/32", "dev", "lo"],
                    pass_fds=(fd,)).returncode == 0, "private origin address setup failed")

    def probe(self, fd: int, port: int, marker: str) -> bool:
        response = self.inside(fd, ["curl", "--silent", "--show-error", "--fail", "--max-time", "4",
                                    "--noproxy", "", "--socks5-hostname", f"127.0.0.1:{port}",
                                    f"http://{ORIGIN_ADDRESS}:31802/probe.txt"])
        (self.root / "logs/probe.stderr").write_bytes(response.stderr)
        return response.returncode == 0 and response.stdout.decode().strip() == marker

    def wait_probe(self, fd: int, port: int, marker: str) -> None:
        for _ in range(4):
            if self.probe(fd, port, marker):
                return
            time.sleep(0.25)
        raise CheckFailed("local protocol transfer failed")

    def require_cause(self, log: Path, cause: str) -> None:
        for _ in range(30):
            if log.exists() and cause in log.read_text():
                return
            time.sleep(0.1)
        raise CheckFailed("expected refusal cause was not observed")

    def reject_xray(self, fd: int, unit: str, config: dict, label: str,
                    cause: str, log_name: str, marker: str, *, trust: Path | None = None) -> None:
        config["inbounds"][0]["port"] = 31812 + int(label == "bad-reality")
        port = config["inbounds"][0]["port"]
        path = self.write(f"{label}.json", json.dumps(config))
        require(run(self.offline + [str(self.xray), "run", "-test", "-config", str(path)]).returncode == 0,
                "negative Xray candidate failed configuration validation")
        # Trust only in this candidate's process: otherwise an untrusted fixture
        # fallback certificate would hide the more precise REALITY refusal.
        name = self.start(label, [str(self.xray), "run", "-config", str(path)], join=unit,
                          environment={"SSL_CERT_FILE": str(trust)} if trust else None)
        require(not self.probe(fd, port, marker), "invalid Xray credentials transferred data")
        self.require_cause(self.root / "logs" / log_name, cause)
        # Invalid REALITY clients retain a fallback spider connection. Retire the
        # candidate before rechecking our single-connection fixture TLS endpoint.
        self.stop_owned(name, self.units[name])
        self.wait_probe(fd, 31810, marker)
        self.check(f"{label} refused with its expected cause; valid Xray transfers after candidate cleanup")

    def reject_hy2(self, fd: int, unit: str, uri: str, label: str, cause: str, marker: str) -> None:
        path = self.write(f"{label}.yaml", f"server: {json.dumps(uri)}\n"
                          "socks5:\n  listen: 127.0.0.1:31812\n")
        name = f"{self.prefix}-{len(self.units)}-{label}.service"
        try:
            self.start(label, [str(self.hy2), "client", "-c", str(path)], join=unit)
        except UnitExited:
            # Early exit alone is insufficient: require the exact protocol/TLS
            # cause below, a stopped owned candidate and a live positive control.
            pass
        self.require_cause(self.root / "logs" / f"{label}.log", cause)
        require(name in self.units and self.value(name, "ActiveState") in ("failed", "inactive"),
                "rejected HY2 candidate remains active")
        if label == "bad-auth":
            # PNM's production masquerade is an HTTPS reverse proxy. In this
            # interface-less namespace its .invalid target returns 502 on auth
            # refusal; corroborate that path, rather than accepting any failure.
            self.require_cause(self.root / "logs/hy2.log", "HTTP reverse proxy error")
            self.require_cause(self.root / "logs/hy2.log", "pnm-accept.invalid")
        self.wait_probe(fd, 31811, marker)
        self.check(f"{label} refused with its expected cause; valid HY2 URI still transfers")

    def exercise(self) -> None:
        self.stage = "actual versions"
        manifest = json.loads(Path(__file__).with_name("real_core_versions.json").read_text())
        for core, binary, argument in (("xray", self.xray, "version"), ("hysteria2", self.hy2, "version")):
            version = run(self.offline + [str(binary), argument])
            require(version.returncode == 0 and manifest[core]["version"].lstrip("v").encode() in version.stdout,
                    "actual binary version mismatch")
        self.check("verified official binary versions run as nobody")
        self.stage = "rendered configuration"
        key_output = run(self.offline + [str(self.xray), "x25519"])
        require(key_output.returncode == 0, "REALITY key generation failed")
        fields = {label.split("(", 1)[0].strip(): value.strip()
                  for label, value in (line.split(":", 1) for line in key_output.stdout.decode().splitlines() if ":" in line)}
        private = fields.get("PrivateKey", "").strip()
        public = (fields.get("Password") or fields.get("PublicKey") or "").strip()
        require(len(private) == 43 and len(public) == 43, "REALITY key output format")
        user_id, short_id, password = str(uuid.uuid4()), secrets.token_hex(8), secrets.token_urlsafe(24)
        cert, key = self.root / "server.crt", self.root / "server.key"
        generation = run(["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
                          "-nodes", "-days", "1", "-subj", "/CN=pnm-accept.invalid",
                          "-addext", "subjectAltName=DNS:pnm-accept.invalid", "-keyout", str(key), "-out", str(cert)])
        require(generation.returncode == 0, "fixture certificate generation failed")
        for path in (cert, key):
            os.chown(path, self.uid, self.gid)
            path.chmod(0o600)
        self.write("config/node.conf", "SCHEMA_VERSION=1\nNODE_REGION=test\nTIMEZONE=UTC\nPNM_CONFIGURED=yes\n"
                   "XRAY_PORT=31443\nXRAY_SERVER_NAME=pnm-accept.invalid\nXRAY_TARGET=127.0.0.1:31444\n"
                   "HY2_PORT=32443\nHY2_TLS_MODE=selfsigned-pin\nHY2_TLS_SERVER_NAME=pnm-accept.invalid\n")
        self.write("config/secrets/reality.env", f"SCHEMA_VERSION=1\nXRAY_UUID={user_id}\n"
                   f"XRAY_REALITY_PRIVATE_KEY={private}\nXRAY_REALITY_SHORT_ID={short_id}\n")
        self.write("config/secrets/hysteria.env", f"SCHEMA_VERSION=1\nHY2_AUTH_PASSWORD={password}\n"
                   f"HY2_TLS_CERT_PATH={cert}\nHY2_TLS_KEY_PATH={key}\nHY2_TLS_PIN_SHA256=\n")
        renderer = Path(__file__).with_name("render_real_core_fixtures.sh")
        require(run(["bash", str(renderer), str(self.root)]).returncode == 0, "production fixture rendering failed")
        for file in ("xray-server.json", "hy2-server.yaml"):
            path = self.root / file
            os.chown(path, self.uid, self.gid)
            path.chmod(0o600)
        validation = run(self.offline + [str(self.xray), "run", "-test", "-config", str(self.root / "xray-server.json")])
        require(validation.returncode == 0, "real Xray rejected rendered configuration")
        self.check("production-rendered config and certificate pair validate")
        marker = "PNM_RUNTIME_OK_" + uuid.uuid4().hex
        self.write("payload/probe.txt", marker)
        self.stage = "real Core startup"
        xray_unit = self.start("xray", [str(self.xray), "run", "-config", str(self.root / "xray-server.json")])
        hy2_unit = self.start("hy2", [str(self.hy2), "server", "-c", str(self.root / "hy2-server.yaml")])
        self.check("both real Core processes start unprivileged")
        for core, unit in (("xray", xray_unit), ("hysteria2", hy2_unit)):
            self.stage = f"{core} local protocol"
            fd = self.namespace(unit)
            self.prepare_origin_network(fd)
            self.start(f"{core}-origin", [sys.executable, "-m", "http.server", "31802", "--bind", ORIGIN_ADDRESS,
                                         "--directory", str(self.root / "payload")], join=unit)
            origin = self.inside(fd, ["curl", "--silent", "--show-error", "--fail", "--max-time", "4",
                                      "--noproxy", "*", f"http://{ORIGIN_ADDRESS}:31802/probe.txt"])
            require(origin.returncode == 0 and origin.stdout.decode().strip() == marker,
                    "local HTTP origin control failed")
            if core == "xray":
                self.start("reality-target", ["/usr/bin/openssl", "s_server", "-accept", "127.0.0.1:31444", "-cert", str(cert),
                                              "-key", str(key), "-tls1_3", "-groups", "X25519", "-alpn", "h2,http/1.1", "-www"], join=unit)
            port = 31810
            if core == "xray":
                # Detailed client diagnostics remain inside the private fixture.
                config = {"log": {"loglevel": "debug"}, "inbounds": [{"listen": "127.0.0.1", "port": port,
                          "protocol": "socks", "settings": {"auth": "noauth"}}], "outbounds": [{"protocol": "vless",
                          "settings": {"vnext": [{"address": "127.0.0.1", "port": 31443, "users": [{
                              "id": user_id, "encryption": "none", "flow": "xtls-rprx-vision"}]}]},
                          "streamSettings": {"network": "tcp", "security": "reality",
                          "realitySettings": {"serverName": "pnm-accept.invalid", "fingerprint": "chrome",
                                              "password": public, "shortId": short_id}}}]}
                path = self.write("xray-client.json", json.dumps(config))
                args = [str(self.xray), "run", "-config", str(path)]
            else:
                path = self.write("hy2-client.yaml", f"server: 127.0.0.1:32443\nauth: {password}\n"
                                  f"tls:\n  sni: pnm-accept.invalid\n  insecure: false\n  ca: {cert}\n"
                                  f"socks5:\n  listen: 127.0.0.1:{port}\n")
                args = [str(self.hy2), "client", "-c", str(path)]
            self.start(f"{core}-client", args, join=unit)
            self.wait_probe(fd, port, marker)
            self.check(f"{core} transfers through its real local client")
            if core == "xray":
                self.stage = "VLESS UUID refusal"
                denied = json.loads(json.dumps(config))
                denied_id = str(uuid.uuid4())
                denied["outbounds"][0]["settings"]["vnext"][0]["users"][0]["id"] = denied_id
                self.reject_xray(fd, unit, denied, "bad-vless", f"invalid request user id: {denied_id}",
                                 "xray.log", marker)
                self.stage = "REALITY short ID refusal"
                denied = json.loads(json.dumps(config))
                wrong_short_id = ("0" if short_id[0] != "0" else "1") + short_id[1:]
                denied["outbounds"][0]["streamSettings"]["realitySettings"]["shortId"] = wrong_short_id
                self.reject_xray(fd, unit, denied, "bad-reality",
                                 "REALITY: received real certificate (potential MITM or redirection)",
                                 "bad-reality.log", marker, trust=cert)
            if core == "hysteria2":
                self.stage = "PNM share-link pin"
                uri = json.loads((self.root / "hy2-link.json").read_text())["hysteria2"]
                link = urlsplit(uri)
                query = parse_qs(link.query, strict_parsing=True)
                require(link.scheme == "hysteria2" and link.hostname == "127.0.0.1" and link.port == 32443
                        and unquote(link.username or "") == password and query["sni"] == ["pnm-accept.invalid"]
                        and query["insecure"] == ["1"], "production share-link fields differ from fixture")
                # Let the official client import the entire production URI;
                # JSON quoting is valid YAML and protects '#' and credentials.
                pin_config = self.write("hy2-pin-client.yaml", f"server: {json.dumps(uri)}\n"
                                        "socks5:\n  listen: 127.0.0.1:31811\n")
                try:
                    self.start("hy2-pin-client", [str(self.hy2), "client", "-c", str(pin_config)], join=unit)
                    self.wait_probe(fd, 31811, marker)
                except CheckFailed as error:
                    log = self.root / "logs/hy2-pin-client.log"
                    if log.exists() and "no certificate matches the pinned hash" in log.read_text():
                        raise CheckFailed("PNM share pin rejected: certificate fingerprint mismatch") from error
                    raise
                self.check("PNM share-link pin transfers through the official HY2 client")
                self.stage = "HY2 certificate pin refusal"
                wrong_query = {name: values[0] for name, values in query.items()}
                wrong_query["pinSHA256"] = ("0" if query["pinSHA256"][0][0] != "0" else "1") + query["pinSHA256"][0][1:]
                self.reject_hy2(fd, unit, link._replace(query=urlencode(wrong_query)).geturl(), "bad-pin",
                                "no certificate matches the pinned hash", marker)
                self.stage = "HY2 authentication refusal"
                wrong_auth = link._replace(netloc=f"{quote(password + '_invalid', safe='')}@{link.hostname}:{link.port}")
                self.reject_hy2(fd, unit, wrong_auth.geturl(), "bad-auth",
                                "authentication error, HTTP status code: 502", marker)

    def stop_owned(self, name: str, binary: str) -> None:
        require(self.units.get(name) == binary, "unregistered test unit refused")
        if self.value(name, "LoadState") != "not-found":
            require(self.value(name, "Description") == name and self.value(name, "User") == str(self.uid)
                    and self.value(name, "Transient") == "yes" and self.value(name, "PrivateNetwork") == "yes"
                    and binary in self.value(name, "ExecStart"), "changed test unit retained")
            require(run(["systemctl", "stop", name]).returncode == 0, "test unit stop failed")
            for _ in range(20):
                if self.value(name, "LoadState") == "not-found":
                    break
                time.sleep(0.1)
            require(self.value(name, "LoadState") == "not-found", "test unit still loaded")

    def cleanup(self, success: bool) -> bool:
        okay = True
        for name, binary in reversed(self.units.items()):
            try:
                self.stop_owned(name, binary)
                print(f"# cleaned unit={name}", flush=True)
            except (CheckFailed, OSError, subprocess.SubprocessError):
                okay = False
                print(f"# cleanup requires inspection unit={name}", file=sys.stderr)
        for fd in self.namespaces:
            os.close(fd)
        if self.identity is None:
            if not self.root.exists() and not self.root.is_symlink():
                return okay
            print(f"# setup identity requires inspection={self.root}", file=sys.stderr)
            return False
        info = self.root.lstat()
        require(self.root.parent == Path("/run") and self.root.name.startswith("pnm-realcore.")
                and stat.S_ISDIR(info.st_mode) and info.st_uid == 0
                and (info.st_dev, info.st_ino) == self.identity, "fixture identity changed")
        if success and okay:
            shutil.rmtree(self.root)
        else:
            self.root.chmod(0o700)
            # /run is volatile on WSL shutdown. Retain logs/config privately on
            # disk as well; verified public binaries already live in the cache.
            evidence = Path(tempfile.mkdtemp(prefix="pnm-realcore-failed.", dir="/var/tmp"))
            shutil.copytree(self.root, evidence, dirs_exist_ok=True, symlinks=True,
                            ignore=shutil.ignore_patterns("bin"))
            evidence.chmod(0o700)
            print(f"# private evidence retained={evidence}", file=sys.stderr)
        return okay


def main() -> int:
    if os.environ.get("PNM_RUN_REAL_CORE_TESTS") != "1":
        print("Opt in with sudo make test-real-cores and PNM_REAL_CORE_ASSETS.", file=sys.stderr)
        return 64
    if os.geteuid() != 0:
        return 77
    # Files must be private from creation, before final ownership adjustments.
    os.umask(0o077)
    harness: Harness | None = None
    result = 1
    try:
        for tool in ("systemctl", "systemd-run", "nsenter", "setpriv", "openssl", "curl", "unshare", "bash", "ip"):
            require(shutil.which(tool) is not None, "required tool unavailable")
        require(run(["systemctl", "is-system-running"]).stdout.strip() in (b"running", b"degraded"), "systemd unavailable")
        require(run(["unshare", "--net", "true"]).returncode == 0, "private network unavailable")
        assets = verified_assets(Path(os.environ.get("PNM_REAL_CORE_ASSETS", "/nonexistent")))
        harness = Harness()
        def interrupted(signum: int, _frame: object) -> None:
            raise CheckFailed(f"interrupted by signal {signum}")
        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(signum, interrupted)
        harness.prepare(assets)
        harness.exercise()
        result = 0
    except (CheckFailed, OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        # Core stderr may contain credentials. Raw output stays in the protected fixture.
        label = str(error) if isinstance(error, CheckFailed) else type(error).__name__
        print(f"not ok - {harness.stage if harness else 'preflight'}: {label}", file=sys.stderr)
    finally:
        if harness:
            for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
                signal.signal(signum, signal.SIG_IGN)
            try:
                clean = harness.cleanup(result == 0)
            except (CheckFailed, OSError, subprocess.SubprocessError):
                clean = False
                print("# cleanup requires manual inspection", file=sys.stderr)
            if not clean:
                result = 1
            print(f"# passed={harness.passed} failed={int(result != 0)}", flush=True)
    return result


if __name__ == "__main__":
    sys.exit(main())
