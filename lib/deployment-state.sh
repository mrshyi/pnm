#!/usr/bin/env bash

# Persistence helpers for transaction.sh's deployment operation, not a second
# transaction engine. Standalone Core operations keep their existing receipts.
pnm_tx_validate_deployment_record() {
    local path="$1" core
    local -A baseline=()
    [[ -f "$path" && ! -L "$path" && "$(stat -c '%a|%u' -- "$path")" == "600|$EUID" ]] || return "$PNM_EXIT_CONFIG"
    pnm_config_load "$path" baseline SCHEMA_VERSION APPLY_ID XRAY_LOAD XRAY_ACTIVE XRAY_ENABLED HY2_LOAD HY2_ACTIVE HY2_ENABLED \
        XRAY_APPLIED HY2_APPLIED XRAY_CONFIG_HASH HY2_CONFIG_HASH XRAY_APPLIED_HASH HY2_APPLIED_HASH \
        XRAY_APPLIED_ATTRIBUTES HY2_APPLIED_ATTRIBUTES || return "$PNM_EXIT_CONFIG"
    [[ "${baseline[SCHEMA_VERSION]-}" == 1 && ( "${baseline[APPLY_ID]-}" == none || "${baseline[APPLY_ID]-}" =~ ^[A-Za-z0-9._-]{8,80}$ ) ]] || return "$PNM_EXIT_CONFIG"
    for core in XRAY HY2; do
        [[ "${baseline[${core}_LOAD]-}" =~ ^(loaded|not-found)$ &&
            "${baseline[${core}_ACTIVE]-}" =~ ^(active|inactive)$ &&
            "${baseline[${core}_ENABLED]-}" =~ ^(enabled|disabled)$ &&
            "${baseline[${core}_APPLIED]-}" =~ ^[01]$ ]] || return "$PNM_EXIT_CONFIG"
        if [[ "${baseline[${core}_APPLIED]}" == 1 ]]; then
            [[ "${baseline[${core}_CONFIG_HASH]-}" =~ ^[a-f0-9]{64}$ ]] || return "$PNM_EXIT_CONFIG"
            [[ "${baseline[${core}_APPLIED_HASH]-}" =~ ^[a-f0-9]{64}$ &&
                "${baseline[${core}_APPLIED_ATTRIBUTES]-}" =~ ^600:[0-9]+:[0-9]+$ ]] || return "$PNM_EXIT_CONFIG"
        else
            [[ "${baseline[${core}_CONFIG_HASH]-}" == MISSING ]] || return "$PNM_EXIT_CONFIG"
            [[ "${baseline[${core}_APPLIED_HASH]-}" == MISSING && "${baseline[${core}_APPLIED_ATTRIBUTES]-}" == MISSING ]] || return "$PNM_EXIT_CONFIG"
        fi
        if [[ "${baseline[${core}_LOAD]}" == not-found ]]; then
            [[ "${baseline[${core}_ACTIVE]}" == inactive && "${baseline[${core}_ENABLED]}" == disabled ]] || return "$PNM_EXIT_CONFIG"
        fi
    done
}

pnm_tx_deployment_marker() {
    local action="$1" directory="$2" transaction_id="$3" deployment_id="$4"
    shift 4
    python3 - "$action" "$directory" "$transaction_id" "$deployment_id" "$@" <<'PY'
import base64
import hashlib
import os
import re
import stat
import sys
import tempfile
import time

action, directory, tx_id, deploy_id = sys.argv[1:5]
temporary = None

def protected_file(path, hash_only=False):
    info = os.lstat(path)
    if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != os.geteuid():
        raise ValueError("unsafe transaction record")
    with open(path, "rb") as stream:
        if hash_only:
            content_hash = hashlib.sha256()
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                content_hash.update(chunk)
            value = content_hash.digest()
        else:
            value = stream.read(128 * 1024 + 1)
            if len(value) > 128 * 1024:
                raise ValueError("oversized transaction record")
        if action == "publish":
            os.fsync(stream.fileno())
    return value

def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)

try:
    names = ["metadata.env", "changes.tsv", "directories.tsv", "deployment.env"]
    for name in ("accounts.tsv", "file-attributes.tsv"):
        if os.path.lexists(os.path.join(directory, name)):
            names.append(name)
    snapshots = os.path.join(directory, "snapshots")
    if os.path.lexists(snapshots):
        info = os.lstat(snapshots)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
            raise ValueError("unsafe snapshot directory")
        for name in os.listdir(snapshots):
            if not re.fullmatch(r"[A-Za-z0-9._-]+", name):
                raise ValueError("invalid snapshot name")
            names.append("snapshots/" + name)
    digest = hashlib.sha256()
    for name in sorted(names):
        content_hash = protected_file(os.path.join(directory, name), hash_only=True)
        digest.update(name.encode() + b"\0" + content_hash)
    baseline = dict(line.split("=", 1) for line in protected_file(os.path.join(directory, "deployment.env")).decode("ascii").splitlines())
    expected = {
        "SCHEMA_VERSION": "1", "TRANSACTION_ID": tx_id,
        "DEPLOYMENT_ID": deploy_id, "APPLY_ID": baseline["APPLY_ID"],
        "RECORDS_SHA256": digest.hexdigest(),
    }
    marker = os.path.join(directory, "commit.env")
    if action == "verify":
        lines = protected_file(marker).decode("ascii").splitlines()
        actual = dict(line.split("=", 1) for line in lines)
        if len(lines) != len(expected) or actual != expected:
            raise ValueError("invalid commit marker")
    elif action == "publish":
        if os.path.lexists(marker):
            raise ValueError("commit marker already exists")
        # Persist uncertainty BEFORE publication. A crash or storage failure
        # after rename must remain blocked without needing a later error write.
        pending = os.path.join(directory, "commit-uncertain.env")
        descriptor = os.open(pending, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(b"SCHEMA_VERSION=1\nORIGINAL_RC=70\n")
            stream.flush()
            os.fsync(stream.fileno())
        sync_directory(directory)
        deadline = int(sys.argv[5])
        attributes = {}
        if "file-attributes.tsv" in names:
            for line in protected_file(os.path.join(directory, "file-attributes.tsv")).decode().splitlines():
                label, encoded, metadata, expected_hash = line.split("\t")
                path = os.fsdecode(base64.b64decode(encoded, validate=True))
                attributes[path] = (metadata, expected_hash)
        for path in sys.argv[6:]:
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
            try:
                info = os.fstat(descriptor)
                if not stat.S_ISREG(info.st_mode):
                    raise ValueError("invalid managed file")
                expected_metadata, expected_hash = attributes[path]
                actual_metadata = f"{stat.S_IMODE(info.st_mode):o}|{info.st_uid}|{info.st_gid}"
                content_hash = hashlib.sha256()
                with os.fdopen(os.dup(descriptor), "rb") as stream:
                    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                        content_hash.update(chunk)
                actual_hash = content_hash.hexdigest()
                if actual_metadata != expected_metadata or actual_hash != expected_hash:
                    raise ValueError("managed resource changed")
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
            sync_directory(os.path.dirname(path))
        for line in protected_file(os.path.join(directory, "directories.tsv")).decode().splitlines():
            event, encoded, original, expected_metadata, identity = line.split("\t")
            if event == "APPLIED":
                path = os.fsdecode(base64.b64decode(encoded, validate=True))
                sync_directory(path)
                sync_directory(os.path.dirname(path))
        if os.path.isdir(snapshots):
            sync_directory(snapshots)
        sync_directory(directory)
        sync_directory(os.path.dirname(directory))
        sync_directory(os.path.dirname(os.path.dirname(directory)))
        descriptor, temporary = tempfile.mkstemp(prefix=".commit-", dir=directory)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write("".join(f"{key}={value}\n" for key, value in expected.items()).encode("ascii"))
            stream.flush()
            os.fsync(stream.fileno())
        if deadline and time.time() > deadline:
            raise TimeoutError("commit window expired")
        os.replace(temporary, marker)
        temporary = None
        # Failure here is uncertain: the caller retains resources and recovery
        # evidence rather than pretending a published marker never existed.
        sync_directory(directory)
        os.unlink(pending)
        try:
            sync_directory(directory)
        except OSError:
            # The marker was already durable. If the removed uncertainty file
            # reappears after a crash, inspection will conservatively block.
            print("Deployment committed; uncertainty-record cleanup sync failed.", file=sys.stderr)
    else:
        raise ValueError("invalid marker action")
except (OSError, ValueError, UnicodeError, KeyError) as error:
    if temporary is not None:
        try:
            os.unlink(temporary)
        except OSError:
            pass
    print("Deployment commit record could not be persisted or verified.", file=sys.stderr)
    sys.exit(73)
PY
}

pnm_tx_publish_deployment_commit() {
    pnm_tx_validate_deployment_record "$PNM_TX_PATH/deployment.env" || return $?
    pnm_tx_verify_written_resources || return $?
    pnm_tx_deployment_marker publish "$PNM_TX_PATH" "$PNM_TX_ID" "$PNM_TX_DEPLOYMENT_ID" \
        "${PNM_APPLY_GATE_COMMIT_DEADLINE:-0}" "${PNM_TX_WRITTEN_PATHS[@]}"
}

# Recovery changes only InvocationID after restoring a previously confirmed
# runtime. Keep the original metadata and refuse an intervening external edit.
pnm_tx_refresh_recovered_applied() {
    python3 - "$@" <<'PY'
import hashlib
import os
import stat
import sys
import tempfile

path, core, config_hash, invocation, old_hash, attributes = sys.argv[1:]
mode, uid, gid = (int(value, 8 if index == 0 else 10) for index, value in enumerate(attributes.split(":")))
temporary = None
try:
    info = os.lstat(path)
    if not stat.S_ISREG(info.st_mode) or (stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid) != (mode, uid, gid):
        raise ValueError("applied metadata changed")
    with open(path, "rb") as stream:
        if hashlib.sha256(stream.read(128 * 1024 + 1)).hexdigest() != old_hash:
            raise ValueError("applied record changed")
    payload = f"SCHEMA_VERSION=1\nCORE={core}\nCONFIG_SHA256={config_hash}\nSERVICE_INVOCATION_ID={invocation}\n".encode("ascii")
    parent = os.path.dirname(path)
    descriptor, temporary = tempfile.mkstemp(prefix=".pnm-recovered-", dir=parent)
    with os.fdopen(descriptor, "wb") as stream:
        os.fchown(stream.fileno(), uid, gid)
        os.fchmod(stream.fileno(), mode)
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    temporary = None
    descriptor = os.open(parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    info = os.lstat(path)
    if not stat.S_ISREG(info.st_mode) or (stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid) != (mode, uid, gid):
        raise ValueError("applied metadata changed after recovery")
    with open(path, "rb") as stream:
        if stream.read(len(payload) + 1) != payload:
            raise ValueError("applied record changed after recovery")
except (OSError, ValueError, UnicodeError):
    if temporary is not None:
        try:
            os.unlink(temporary)
        except OSError:
            pass
    print("Recovered applied record could not be persisted or verified.", file=sys.stderr)
    sys.exit(70)
PY
}

pnm_tx_assert_no_pending_deployment() {
    local directory id
    local -A metadata=()
    [[ -e "$PNM_STATE_DIR/transactions" || -L "$PNM_STATE_DIR/transactions" ]] || return 0
    pnm_validate_managed_path "$PNM_STATE_DIR/transactions" || return $?
    for directory in "$PNM_STATE_DIR"/transactions/*; do
        [[ -d "$directory" && ! -L "$directory" ]] || continue
        if ! pnm_config_load "$directory/metadata.env" metadata SCHEMA_VERSION TRANSACTION_ID OPERATION DEPLOYMENT_ID 2>/dev/null; then
            [[ ! -e "$directory/deployment.env" ]] || return "$PNM_EXIT_SOFTWARE"
            continue
        fi
        [[ "${metadata[OPERATION]-}" == deployment ]] || continue
        id="${directory##*/}"
        if ! pnm_tx_load_for_inspect "$id" || [[ "$PNM_TX_INSPECT_STATE" != COMMITTED && "$PNM_TX_INSPECT_STATE" != ROLLED_BACK ]]; then
            pnm_error "Unresolved deployment transaction $id; inspect recovery evidence before continuing."
            return "$PNM_EXIT_SOFTWARE"
        fi
    done
}
