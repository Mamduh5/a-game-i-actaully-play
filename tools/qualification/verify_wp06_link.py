"""Run WP06's isolated loopback link probe in separate Windows release processes."""

import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time


PAIRED = "fixture.local"
ADDRESS = "127.0.0.1"
MUTEX_DIAGNOSTIC = "godot_mbedtls_mutex_free"
HANDSHAKE_DIAGNOSTIC = "_do_handshake (modules/mbedtls/packet_peer_mbed_dtls.cpp:100)"


def peer_env(directory):
    roaming, local = directory / "roaming", directory / "local"
    roaming.mkdir(parents=True)
    local.mkdir()
    return dict(os.environ, APPDATA=str(roaming), LOCALAPPDATA=str(local), GODOT_MCP_RUNTIME="off")


def ephemeral_port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as listener:
        listener.bind((ADDRESS, 0))
        return listener.getsockname()[1]


def launch(command, log, environment, *args):
    return subprocess.Popen(
        [*command, "--headless", "--verbose", "--max-fps", "120", "--log-file", log, "--", *map(str, args)],
        env=environment, creationflags=subprocess.CREATE_NO_WINDOW,
    )


def wait_for_host(process, path):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and process.poll() is None:
        if path.is_file() and path.read_bytes() == b"\x01":
            return
        time.sleep(0.025)
    raise RuntimeError("Fixture host did not become ready")


def receipt(log):
    visible = log.read_text(encoding="utf-8", errors="replace")
    marker = "WP06_LINK_RESULT "
    index = visible.find(marker)
    if index < 0:
        raise ValueError(f"Missing link receipt in {log.name}")
    result = json.loads(visible[index + len(marker):].splitlines()[0])
    diagnostics = []
    phase = "startup"
    lines = visible.splitlines()
    for at, line in enumerate(lines):
        if line.startswith("WP06_LINK_READY "):
            phase = "connecting"
        if line.startswith("WP06_LINK_PHASE "):
            phase = line.split()[1]
        if "ERROR:" in line:
            subsequent = "\n".join(lines[at:at + 3])
            diagnostics.append({"line": line, "phase": phase, "teardown_site": MUTEX_DIAGNOSTIC in subsequent,
                                "handshake_site": HANDSHAKE_DIAGNOSTIC in subsequent})
    result["diagnostics"] = diagnostics
    return result


def exchange(exe, root, credentials, name):
    output, secrets = root / name, credentials / name
    output.mkdir()
    host_env = peer_env(secrets / "host")
    guest_env = peer_env(secrets / "guest")
    guest_pin = secrets / "guest" / "paired.crt"
    identity = credentials / "original"
    anchor = credentials / "replacement" if name == "changed-anchor" else identity
    shutil.copyfile(anchor / "host.crt", guest_pin)
    name_on_certificate = "changed.fixture.local" if name == "wrong-name" else PAIRED
    expectation = "paired" if name.startswith("paired") else "reject"
    port = ephemeral_port()
    host_log, guest_log = output / "host.log", output / "guest.log"
    ready = secrets / "host-ready"
    children = []
    try:
        host = launch(exe, host_log, host_env, "host", port, identity / "host.crt", identity / "host.key",
                      PAIRED, expectation, ready)
        children.append(host)
        wait_for_host(host, ready)
        guest = launch(exe, guest_log, guest_env, "guest", port, guest_pin, "-", name_on_certificate, expectation, "-")
        children.append(guest)
        codes = [guest.wait(timeout=8), host.wait(timeout=8)]
        results = [receipt(guest_log), receipt(host_log)]
        diagnostics_ok = True
        for side in results:
            for diagnostic in side["diagnostics"]:
                teardown = diagnostic["teardown_site"] and (
                    diagnostic["phase"] == "disconnected" or expectation == "reject"
                )
                refusal = expectation == "reject" and diagnostic["handshake_site"] and diagnostic["phase"] == "connecting"
                diagnostics_ok = diagnostics_ok and (teardown or refusal)
        if expectation == "reject":
            diagnostics_ok = diagnostics_ok and any(item["handshake_site"] for item in results[0]["diagnostics"])
        return {"exits": codes, "peers": results, "passed": not any(codes) and diagnostics_ok
                and all(side["passed"] for side in results)}
    finally:
        for child in children:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=5)


def grant_fixture_identity(exe, temporary, root, label):
    identity = temporary / label
    identity.mkdir()
    environment = peer_env(identity / "profile")
    process = launch(exe, root / f"keygen-{label}.log", environment, "keygen", identity)
    try:
        if process.wait(timeout=10) != 0 or not (identity / "host.crt").is_file():
            raise RuntimeError(f"Fixture key generation failed for {label}")
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--control-project", type=Path, help="Use the editor executable against the disposable fixture project")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    exe, output = args.release.resolve(strict=True), args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    command = [exe]
    if args.control_project:
        command += ["--path", args.control_project.resolve(strict=True)]
    report = {}
    with tempfile.TemporaryDirectory(prefix="agip-wp06-credentials-") as scratch:
        credentials = Path(scratch)
        for label in ("original", "replacement"):
            grant_fixture_identity(command, credentials, output, label)
        for name in ("paired-a", "wrong-name", "changed-anchor", "paired-b"):
            report[name] = exchange(command, output, credentials, name)
    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({case: result["passed"] for case, result in report.items()}))
    if not all(result["passed"] for result in report.values()):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
