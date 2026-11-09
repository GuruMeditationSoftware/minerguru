#!/usr/bin/env python3
"""Simulated Bitaxe / NerdOS miners for testing MinerGuru without hardware.

Every variant from MockMiners/variants runs on its own port. Add one in MinerGuru with
"Add Miner by IP…" → `127.0.0.1:<port>`.

    python3 MockMiners/mock_miner.py                      # all variants from port 48001
    python3 MockMiners/mock_miner.py gamma-hex nerdqx     # only variants whose file name contains one of the words
    python3 MockMiners/mock_miner.py --list               # show variants and ports
    python3 MockMiners/mock_miner.py --host 0.0.0.0       # reachable from a VM, e.g. the Windows port

Behaves like the firmware where it matters for the app (read from the firmware sources):
- GET  /api/system/info      live telemetry with some jitter
- PATCH /api/system          AxeOS stores settings and applies them on restart, NerdOS applies them at once.
                             AxeOS 2.15+ ignores the legacy stratum fields and rejects pool slots without
                             id / URL / user ("Wrong API input", HTTP 400), exactly like ESP-Miner.
- POST /api/system/restart   miner is unreachable for a few seconds, uptime starts again
- DELETE /api/system/pools/N AxeOS 2.15+; refused for the primary / fallback slot
- POST /api/system/pause     AxeOS 2.15+: hashrate and power drop until /api/system/resume; 404 elsewhere
- WS   /api/ws               live log with asic_result lines (feeds the share difficulty chart)
- GET  /mock/set?key=value   changes a running miner for tests, see Miner.control
Every request the app sends is printed with its body.

Miners without block data of their own (NerdOS, AxeOS < 2.13) point at local Stratum pools that replay
the recorded pool replies from MockMiners/stratum-captures, so the app's Stratum probe (MG-04) has
something to read. Their pool user becomes the recorded early address. `--real-pools` keeps the
variants' pools as they are.
"""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
import random
import re
import secrets
import socket
import struct
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

VARIANTS = Path(__file__).resolve().parent / "variants"
CAPTURES = Path(__file__).resolve().parent / "stratum-captures"
# Local Stratum pools: one port per recorded capture, in file name order.
STRATUM_BASE_PORT = 43301
# Captures handed to probe-only miners in turn: solo pools that pay the address, Ocean's shared
# coinbase (address missing), a refused authorize, other coins.
PROBE_CAPTURES = [
    "ckpool-eu-btc", "solopooleu-bch", "publicpool-btc", "ocean-btc", "nerdminers-btc",
    "solopoolorg-dgb", "2miners-bch", "solopoolorg-xec", "atlaspool-btc", "braiins-btc",
]
RESTART_SECONDS = 4
# High port range: ports around 8000 are often taken by other services on a Mac.
BASE_PORT = 48001
MAX_POOLS = 8
# Block template: a new block every ten minutes from this height on.
BASE_HEIGHT = 974_212
STARTED = time.time()


class Miner:
    def __init__(self, name: str, info: dict):
        self.name = name
        self.info = info
        self.flatline = False  # --flatline: shares and hashrate stand still, like ESP-Miner #1053
        self.fallback_stuck = False  # --fallback-stuck: stays on the fallback pool, like ESP-Miner #1618
        self.restart_every = 0  # --restart-every: reboots on its own every so many seconds
        self.overheat = False  # --overheat: at the limit, AxeOS throttled
        self.otp_code: str | None = None  # NerdOS: set by --otp, protects PATCH /api/system
        self.otp_sessions: set[str] = set()
        self.otp_failures: list[float] = []
        self.otp_blocked_until = 0.0
        self.pending: dict = {}           # AxeOS: saved settings, active after restart
        self.booted_at = time.time()
        self.offline_until = 0.0
        self.paused = False
        self.fault = ""                   # /mock/set: http500, badjson, truncated, wrongtypes, extreme, nulls
        self.delay = 0.0                  # /mock/set: seconds before every answer
        self.lock = threading.Lock()

    def control(self, query: dict[str, str]) -> dict:
        """Test hook: fault=..., delay=..., offline=seconds, flatline/overheat/fallback=0|1,
        set.<field>=<JSON or text> to change a telemetry field, slot.<id>.user=... to edit a pool slot."""
        with self.lock:
            for key, value in query.items():
                if key == "fault":
                    self.fault = value
                elif key == "delay":
                    self.delay = float(value)
                elif key == "offline":
                    self.offline_until = time.time() + float(value)
                elif key == "flatline":
                    self.flatline = value == "1"
                elif key == "overheat":
                    self.overheat = value == "1"
                elif key == "fallback":
                    self.fallback_stuck = value == "1"
                elif key == "uptime":
                    self.booted_at = time.time() - float(value)
                elif key.startswith("set."):
                    try:
                        self.info[key[4:]] = json.loads(value)
                    except json.JSONDecodeError:
                        self.info[key[4:]] = value
                elif key.startswith("slot."):
                    _, index, field = key.split(".", 2)
                    for pool in self.info.get("pools", []):
                        if pool["id"] == int(index):
                            pool[{"user": "stratumUser", "url": "stratumURL"}.get(field, field)] = value
            print(f"[{self.name}] MOCK {query}", flush=True)
            return {"ok": True}

    @property
    def is_nerdos(self) -> bool:
        return "boardVersion" not in self.info

    @property
    def has_pool_slots(self) -> bool:
        return "pools" in self.info

    def use_local_pools(self, pools: dict[str, tuple[int, str]], index: int, address: str = "127.0.0.1"):
        """Primary (and fallback) pool become local replay pools with the capture's address."""
        if "blockHeight" in self.info or "stratumURL" not in self.info:
            return
        for offset, prefix in enumerate(("stratum", "fallbackStratum")):
            name = PROBE_CAPTURES[(index * 2 + offset) % len(PROBE_CAPTURES)]
            if name not in pools:
                continue
            port, user = pools[name]
            worker = self.info.get(f"{prefix}User", "").rpartition(".")[2] or "mock"
            self.info[f"{prefix}URL"] = address
            self.info[f"{prefix}Port"] = port
            self.info[f"{prefix}User"] = f"{user.rpartition('.')[0]}.{worker}"
            self.info[f"{prefix}TLS"] = False if self.is_nerdos else 0

    def snapshot(self) -> dict:
        with self.lock:
            info = copy.deepcopy(self.info)
        jitter = random.uniform(0.97, 1.03)
        for key in ("hashRate", "hashRate_1m"):
            if key in info and not self.flatline:
                info[key] = round(info[key] * jitter, 1)
        info["temp"] = round(info.get("temp", 55) + random.uniform(-0.6, 0.6), 1)
        if self.overheat:
            info["temp"] = info.get("overheat_temp", 80) - 1
            if "overheat_mode" in info:
                info["overheat_mode"] = 1
        if self.fallback_stuck:
            info["isUsingFallbackStratum"] = 1
            if isinstance(info.get("stratum"), dict):
                info["stratum"]["usingFallback"] = True
        if self.restart_every and time.time() - self.booted_at > self.restart_every:
            self.booted_at = time.time()
        if self.restart_every:
            info["resetReason"] = "Brownout"
        info["uptimeSeconds"] = int(time.time() - self.booted_at)
        if self.paused:
            for key in ("hashRate", "hashRate_1m", "hashRate_10m", "hashRate_1h"):
                if key in info:
                    info[key] = 0
            info["power"] = round(info.get("power", 15) * 0.25, 1)
        if "blockHeight" in info:
            self._fill_block(info)
        return info

    def _fill_block(self, info: dict):
        """Block template like AxeOS 2.13+: height, tag and sum always, outputs only while
        the active slot decodes the coinbase (system.c / coinbase_decoder.c)."""
        fallback = bool(info.get("isUsingFallbackStratum"))
        prefix = "fallbackStratum" if fallback else "stratum"
        slot = {}
        if self.has_pool_slots:
            index = info.get("secondaryPoolIndex" if fallback else "primaryPoolIndex", 0)
            slot = next((p for p in info["pools"] if p["id"] == index), {})
        url = slot.get("stratumURL", info.get(f"{prefix}URL", ""))
        user = slot.get("stratumUser", info.get(f"{prefix}User", ""))
        decode = slot.get("stratumDecodeCoinbase", info.get(f"{prefix}DecodeCoinbase", True))
        is_bch = "bch" in url

        elapsed = time.time() - STARTED
        height = BASE_HEIGHT + int(elapsed // 600)
        # fees grow while the template fills up
        fees = int((1_800 if is_bch else 1_400_000) * (1 + (elapsed % 600) / 60))
        total = 312_500_000 + fees
        host = url.split("://")[-1].split(":")[0]
        info["blockHeight"] = height
        info["scriptsig"] = f"/{host}/" if host else ""
        info["blockSignals"] = [] if is_bch else ["BIP-54"]
        info["coinbaseValueTotalSatoshis"] = total
        info["coinbaseOthersCount"] = 0
        info["coinbaseOthersValueSatoshis"] = 0
        if not decode:
            info["coinbaseOutputs"] = []
            info["coinbaseValueUserSatoshis"] = 0
            return
        wallet = user.split(".", 1)[0]
        pool_fee = total * 2 // 100
        outputs = [
            {"value": total - pool_fee, "address": wallet, "isUserOutput": 1},
            {"value": pool_fee, "address": "bc1qpoolfeeexampleaddressxxxxxxxxxxxxxxxxx", "isUserOutput": 0},
        ]
        if not is_bch:
            rng = random.Random(height)
            commitment = "".join(rng.choice(".....abcdefXYZ0123") for _ in range(32))
            outputs.append({"value": 0, "address": f"OP_RETURN: .!..{commitment}", "isUserOutput": 0})
        info["coinbaseOutputs"] = outputs
        info["coinbaseValueUserSatoshis"] = total - pool_fee

    # MARK: settings

    def patch(self, body: dict) -> tuple[int, str]:
        with self.lock:
            if self.is_nerdos:
                self._apply_nerdos(body)
                return 200, ""
            error = self._validate_axeos(body)
            if error:
                return 400, error
            self.pending.update(body)
            return 200, ""

    def _validate_axeos(self, body: dict) -> str | None:
        pools = body.get("pools")
        if pools is not None:
            if not isinstance(pools, list):
                return "Wrong API input"
            for pool in pools:
                index = pool.get("id")
                if not isinstance(index, int) or not 0 <= index < MAX_POOLS:
                    return "Wrong API input"
                if not pool.get("stratumURL") or not pool.get("stratumUser"):
                    return "Wrong API input"
                if not isinstance(pool.get("stratumPort"), int) or not 1 <= pool["stratumPort"] <= 65535:
                    return "Wrong API input"
        for key in ("primaryPoolIndex", "secondaryPoolIndex"):
            if key in body and not (isinstance(body[key], int) and 0 <= body[key] < MAX_POOLS):
                return "Wrong API input"
        return None

    def _apply_nerdos(self, body: dict):
        stratum = self.info.get("stratum")
        for key, value in body.items():
            if key in ("poolMode", "poolBalance"):
                if stratum is not None:
                    stratum[key] = value
                    if key == "poolMode":
                        stratum["activePoolMode"] = value
            elif not key.endswith("Password"):
                self.info[key] = value

    def _apply_pending_axeos(self):
        body, self.pending = self.pending, {}
        info = self.info
        if self.has_pool_slots:
            slots = {pool["id"]: pool for pool in info["pools"]}
            for pool in body.get("pools", []):
                stored = dict(pool)
                stored["stratumPassword"] = "*****"
                slots[pool["id"]] = stored
            info["pools"] = [slots[i] for i in sorted(slots)]
            for key in ("primaryPoolIndex", "secondaryPoolIndex", "useFallbackStratum"):
                if key in body:
                    info[key] = body[key]
            # The legacy fields mirror the selected slots, like system_api_json.c does …
            for prefix, index_key in (("stratum", "primaryPoolIndex"), ("fallbackStratum", "secondaryPoolIndex")):
                slot = slots.get(info.get(index_key, 0), {})
                info[f"{prefix}URL"] = slot.get("stratumURL", "")
                info[f"{prefix}Port"] = slot.get("stratumPort", 3333)
                info[f"{prefix}User"] = slot.get("stratumUser", "")
                info[f"{prefix}DecodeCoinbase"] = slot.get("stratumDecodeCoinbase", True)
            # … and writing them is ignored since 2.15.
            body = {k: v for k, v in body.items() if not k.lower().startswith(("stratum", "fallbackstratum"))}
        for key, value in body.items():
            if key in ("pools", "primaryPoolIndex", "secondaryPoolIndex") or key.endswith("Password"):
                continue
            info[key] = value

    def delete_pool(self, index: int) -> tuple[int, str]:
        with self.lock:
            if not self.has_pool_slots or not 0 <= index < MAX_POOLS:
                return 400, "Invalid pool index"
            if index in (self.info.get("primaryPoolIndex"), self.info.get("secondaryPoolIndex")):
                return 400, "Cannot delete a pool that is currently selected as primary or fallback"
            self.info["pools"] = [p for p in self.info["pools"] if p["id"] != index]
            return 200, json.dumps({"message": "Pool cleared successfully"})

    def restart(self):
        with self.lock:
            if not self.is_nerdos:
                self._apply_pending_axeos()
            self.offline_until = time.time() + RESTART_SECONDS
            self.booted_at = self.offline_until
            self.paused = False

    @property
    def offline(self) -> bool:
        return time.time() < self.offline_until

    # MARK: live log

    def log_line(self) -> str:
        ms = int((time.time() - self.booted_at) * 1000)
        pool_diff = int(self.info.get("poolDifficulty") or 1000)
        diff = round(pool_diff * random.lognormvariate(-0.7, 1.2), 1)
        if self.is_nerdos:
            tag = random.choice(["Pri", "Sec"]) if self.info.get("stratum", {}).get("poolMode") == 1 else "Pri"
            return f"I ({ms}) asic_result: ({tag}) Job ID: {random.randint(1, 99)} AsicNr: {random.randint(0, 3)} diff {diff}/{pool_diff}/791M\n"
        return f"I ({ms}) asic_result: ID: {random.randint(1, 255)}, ASIC nr: 0, ver: 00000000 Nonce {random.getrandbits(32):08X} diff {diff} of {pool_diff}.\n"


def make_handler(miner: Miner):
    class Handler(BaseHTTPRequestHandler):
        server_version = "MockMiner"
        # URLSession rejects a WebSocket upgrade answered as HTTP/1.0.
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):
            pass

        def _log(self, body: str = ""):
            print(f"[{miner.name}] {self.command} {self.path} {body}".rstrip(), flush=True)

        def _send(self, status: int, text: str = "", content_type: str = "application/json"):
            data = text.encode()
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _offline(self) -> bool:
            if miner.offline:
                self.close_connection = True
                self.connection.shutdown(socket.SHUT_RDWR)
                return True
            return False

        def _body(self) -> str:
            length = int(self.headers.get("Content-Length") or 0)
            return self.rfile.read(length).decode() if length else ""

        def do_GET(self):
            if self._offline():
                return
            if self.path.startswith("/mock/set"):
                query = {k: v[0] for k, v in parse_qs(urlsplit(self.path).query, keep_blank_values=True).items()}
                self._send(200, json.dumps(miner.control(query)))
            elif self.path == "/api/system/info":
                if miner.delay:
                    time.sleep(miner.delay)
                self._send_info()
            elif self.path == "/api/otp/status":
                self._send(200, json.dumps({"enabled": miner.otp_code is not None}))
            elif self.path == "/api/ws" and self.headers.get("Upgrade", "").lower() == "websocket":
                self._log()
                self._websocket()
            else:
                self._send(404, "Not found", "text/plain")

        def _send_info(self):
            info = miner.snapshot()
            if miner.fault == "http500":
                self._send(500, "Internal Server Error", "text/plain")
            elif miner.fault == "badjson":
                self._send(200, "<html>not json</html>", "text/html")
            elif miner.fault == "truncated":
                self._send(200, json.dumps(info)[:200])
            elif miner.fault == "wrongtypes":
                self._send(200, json.dumps({**info, "hashRate": "fast", "temp": [1], "power": {"a": 1}, "ASICModel": 7}))
            elif miner.fault == "extreme":
                self._send(200, json.dumps({**info, "hashRate": 1e15, "power": -5, "temp": 9999, "uptimeSeconds": -1, "bestDiff": 1e30}))
            elif miner.fault == "nulls":
                self._send(200, json.dumps({key: None for key in info}))
            else:
                self._send(200, json.dumps(info))

        def _otp_refused(self) -> bool:
            """Like NerdOS: a request without a valid code or session counts as a failed attempt."""
            if miner.otp_code is None:
                return False
            now = time.time()
            if now < miner.otp_blocked_until:
                self._send(401, "blocked for 5 minutes", "text/plain")
                return True
            if self.headers.get("X-OTP-Session") in miner.otp_sessions or self.headers.get("X-TOTP") == miner.otp_code:
                return False
            miner.otp_failures = [t for t in miner.otp_failures if now - t < 60] + [now]
            if len(miner.otp_failures) >= 5:
                miner.otp_failures = []
                miner.otp_blocked_until = now + 300
                print(f"[{miner.name}]   → too many OTP failures, blocked for 5 minutes", flush=True)
            self._send(401, "OTP/Session required", "text/plain")
            return True

        def _otp_session(self):
            if miner.otp_code is None:
                return self._send(405, "OTP disabled", "text/plain")
            code = self.headers.get("X-TOTP")
            if code is None:
                return self._send(400, "Missing X-TOTP header", "text/plain")
            if code != miner.otp_code:
                return self._send(401, "Invalid TOTP", "text/plain")
            token = secrets.token_hex(36)
            miner.otp_sessions.add(token)
            ttl_ms = 24 * 3600 * 1000
            self._send(200, json.dumps({"token": token, "ttlMs": ttl_ms, "expiresAt": int(time.time() * 1000) + ttl_ms}))

        def do_PATCH(self):
            if self._offline():
                return
            body = self._body()
            self._log(body)
            if self.path != "/api/system":
                return self._send(404, "Not found", "text/plain")
            if self._otp_refused():
                return
            try:
                payload = json.loads(body or "{}")
            except json.JSONDecodeError:
                return self._send(400, "Invalid JSON", "text/plain")
            status, text = miner.patch(payload)
            if status != 200:
                print(f"[{miner.name}]   → {status} {text}", flush=True)
            self._send(status, text, "text/plain")

        def do_POST(self):
            if self._offline():
                return
            self._log(self._body())
            if self.path == "/api/otp/session":
                self._otp_session()
            elif self.path == "/api/system/restart":
                self._send(200, "System will restart shortly.", "text/plain")
                miner.restart()
                print(f"[{miner.name}]   → restarting, offline for {RESTART_SECONDS}s", flush=True)
            elif self.path in ("/api/system/pause", "/api/system/resume") and miner.has_pool_slots:
                miner.paused = self.path.endswith("pause")
                self._send(200, json.dumps({"message": "Paused" if miner.paused else "Resumed"}))
                print(f"[{miner.name}]   → {'paused' if miner.paused else 'resumed'}", flush=True)
            else:
                self._send(404, "Not found", "text/plain")

        def do_DELETE(self):
            if self._offline():
                return
            self._log()
            match = re.fullmatch(r"/api/system/pools/(\d+)", self.path)
            if not match:
                return self._send(404, "Not found", "text/plain")
            status, text = miner.delete_pool(int(match.group(1)))
            if status != 200:
                print(f"[{miner.name}]   → {status} {text}", flush=True)
            self._send(status, text)

        def _websocket(self):
            key = self.headers.get("Sec-WebSocket-Key", "")
            accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
            self.send_response(101, "Switching Protocols")
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", accept)
            self.end_headers()
            self.close_connection = True
            try:
                while not miner.offline:
                    data = miner.log_line().encode()
                    header = bytes([0x81]) + (bytes([len(data)]) if len(data) < 126 else bytes([126]) + struct.pack(">H", len(data)))
                    self.wfile.write(header + data)
                    self.wfile.flush()
                    time.sleep(random.uniform(0.3, 1.2))
            except (BrokenPipeError, ConnectionResetError, OSError):
                pass

    return Handler


def start_stratum_pools(host: str = "127.0.0.1") -> dict[str, tuple[int, str]]:
    """Replays every capture on its own port: after the first line from a client, all recorded
    pool lines follow; the connection stays open until the client hangs up. Returns name → (port, user)."""
    expected = {entry["file"]: entry for entry in json.loads((CAPTURES / "expected.json").read_text())}
    pools = {}
    for offset, path in enumerate(sorted(CAPTURES.glob("*.jsonl"))):
        port = STRATUM_BASE_PORT + offset
        lines = path.read_bytes().splitlines(keepends=True)
        try:
            listener = socket.create_server((host, port))
        except OSError as error:
            print(f"  ⚠️  Stratum port {port} not available ({error.strerror}), skipping {path.stem}")
            continue

        def serve(listener=listener, lines=lines, name=path.stem):
            while True:
                client, _ = listener.accept()
                threading.Thread(target=replay, args=(client, lines, name), daemon=True).start()

        threading.Thread(target=serve, daemon=True).start()
        pools[path.stem] = (port, expected[path.name]["user"])
    return pools


def replay(client: socket.socket, lines: list[bytes], name: str):
    with client:
        client.settimeout(15)
        try:
            request = client.recv(4096).decode(errors="replace")
            if not request:
                return  # the app's latency check only connects
            users = re.findall(r'"mining\.authorize","params":\["([^"]*)"', request)
            print(f"[stratum {name}] probe as {users[0] if users else '?'}", flush=True)
            if "mining.submit" in request:
                print(f"[stratum {name}] ⚠️  share submitted", flush=True)
            for line in lines:
                client.sendall(line if line.endswith(b"\n") else line + b"\n")
                time.sleep(0.02)
            while client.recv(4096):
                pass
        except OSError:
            pass


def main():
    parser = argparse.ArgumentParser(description="Simulated Bitaxe / NerdOS miners for MinerGuru")
    parser.add_argument("filters", nargs="*", help="only variants whose file name contains one of these words")
    parser.add_argument("--base-port", type=int, default=BASE_PORT)
    parser.add_argument("--host", default="127.0.0.1", help="address the miners listen on, e.g. 0.0.0.0 for a VM")
    parser.add_argument("--advertise", default="127.0.0.1", help="address the miners name for their Stratum replays, e.g. this Mac's address from a VM")
    parser.add_argument("--list", action="store_true", help="list variants and ports, then exit")
    parser.add_argument("--otp", metavar="CODE", help="NerdOS miners protect their settings with this one-time code")
    parser.add_argument("--flatline", action="store_true", help="hashrate freezes and shares stand still (ESP-Miner #1053)")
    parser.add_argument("--fallback-stuck", action="store_true", help="the miner stays on its fallback pool (ESP-Miner #1618)")
    parser.add_argument("--restart-every", type=int, default=0, metavar="SECONDS", help="the miner reboots on its own, naming a reset reason")
    parser.add_argument("--overheat", action="store_true", help="miners run at their overheat limit, AxeOS throttles")
    parser.add_argument("--real-pools", action="store_true", help="keep the variants' pools instead of local Stratum replays")
    args = parser.parse_args()

    # Ports follow the full, sorted variant list, so a miner keeps its port when filtering.
    files = list(enumerate(sorted(VARIANTS.glob("*.json"))))
    if args.filters:
        files = [(i, f) for i, f in files if any(word.lower() in f.stem.lower() for word in args.filters)]
    if not files:
        sys.exit("No matching variants. Run MockMiners/make_variants.py first or check the filter.")

    pools = {} if args.list or args.real_pools else start_stratum_pools(args.host)
    if pools:
        print(f"  Stratum replays on {args.advertise}:{STRATUM_BASE_PORT}–{STRATUM_BASE_PORT + len(pools) - 1}")
    servers = []
    probe_index = 0
    for offset, path in files:
        port = args.base_port + offset
        print(f"  {args.host}:{port}  {path.stem}")
        if args.list:
            continue
        miner = Miner(path.stem, json.loads(path.read_text()))
        miner.flatline = args.flatline
        if args.flatline:
            miner.booted_at -= 3600  # past the restart grace period of the apps
        miner.fallback_stuck = args.fallback_stuck
        if args.fallback_stuck:
            miner.booted_at -= 3600
        miner.restart_every = args.restart_every
        miner.overheat = args.overheat
        if args.otp and "otp" in miner.info:
            miner.otp_code = args.otp
            miner.info["otp"] = True
        if pools and "blockHeight" not in miner.info:
            # Dual pool miners get BTC + BCH, so both cards differ.
            dual = (miner.info.get("stratum") or {}).get("poolMode") == 1
            miner.use_local_pools(pools, 0 if dual else probe_index, args.advertise)
            probe_index += 1
        try:
            server = ThreadingHTTPServer((args.host, port), make_handler(miner))
        except OSError as error:
            print(f"  ⚠️  port {port} not available ({error.strerror}), skipping {path.stem}")
            continue
        server.daemon_threads = True
        threading.Thread(target=server.serve_forever, daemon=True).start()
        servers.append(server)
    if args.list:
        return
    print(f"{len(servers)} mock miners running. Add them in MinerGuru by IP, e.g. 127.0.0.1:{args.base_port}. Ctrl+C stops.", flush=True)
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
