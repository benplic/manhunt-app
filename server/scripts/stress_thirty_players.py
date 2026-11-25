#!/usr/bin/env python3
"""Live 30-player WebSocket stress run against a real uvicorn process.

Simulates tonight's mix: 3 iOS seekers + 27 web hiders. Exercises join,
1 Hz tick broadcasts, location traffic, and disconnect/reconnect with
last_seq replay. Prints concrete latency and resource numbers.

Usage (from server/ with the venv active):

    python scripts/stress_thirty_players.py
    python scripts/stress_thirty_players.py --players 40 --seconds 20
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import resource
import socket
import subprocess
import sys
import tempfile
import time
import traceback
from dataclasses import dataclass, field
from pathlib import Path
from uuid import UUID, uuid4

import httpx
import uvicorn
import websockets
from websockets.exceptions import ConnectionClosed

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.config import Settings  # noqa: E402
from app.limits import MAX_GAME_PLAYERS  # noqa: E402
from app.main import create_app  # noqa: E402

_M = 1 / 111_320
ARENA = {
    "name": "Stress Square",
    "boundary": [
        {"lat": 0.0, "lon": 0.0},
        {"lat": 200 * _M, "lon": 0.0},
        {"lat": 200 * _M, "lon": 200 * _M},
        {"lat": 0.0, "lon": 200 * _M},
    ],
    "zones": [],
}


@dataclass
class PlayerClient:
    index: int
    name: str
    role: str
    token: str = ""
    user_id: str = ""
    views: int = 0
    events: int = 0
    welcome: int = 0
    errors: list[str] = field(default_factory=list)
    view_latencies_ms: list[float] = field(default_factory=list)
    last_seq: int | None = None
    connected: bool = False


@dataclass
class StressReport:
    players: int
    seekers: int
    hiders: int
    join_ok: bool
    start_ok: bool
    sockets_open: int
    gameplay_seconds: float
    views_received: int
    events_received: int
    location_sends: int
    reconnect_ok: int
    reconnect_fail: int
    view_p50_ms: float | None
    view_p95_ms: float | None
    view_max_ms: float | None
    broadcast_p50_ms: float | None
    broadcast_p95_ms: float | None
    broadcast_max_ms: float | None
    rss_peak_mb: float
    cpu_user_s: float
    cpu_system_s: float
    errors: list[str]
    passed: bool
    fail_reasons: list[str]


def _square_point(index: int, total: int) -> tuple[float, float]:
    side = max(1, int(total**0.5))
    row = index // side
    col = index % side
    return (40 + row * 12) * _M, (40 + col * 12) * _M


def _percentile(values: list[float], pct: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * (pct / 100.0)
    low = int(rank)
    high = min(low + 1, len(ordered) - 1)
    weight = rank - low
    return ordered[low] * (1 - weight) + ordered[high] * weight


def _sample_rss_mb(pid: int) -> float:
    try:
        out = subprocess.check_output(
            ["ps", "-o", "rss=", "-p", str(pid)],
            text=True,
        ).strip()
        return float(out) / 1024.0
    except (subprocess.CalledProcessError, ValueError):
        return 0.0


async def _wait_healthy(base: str, timeout_s: float = 20.0) -> None:
    deadline = time.monotonic() + timeout_s
    async with httpx.AsyncClient() as client:
        while time.monotonic() < deadline:
            try:
                response = await client.get(f"{base}/v1/healthz", timeout=1.0)
                if response.status_code == 200:
                    return
            except httpx.HTTPError:
                pass
            await asyncio.sleep(0.1)
    raise RuntimeError(f"server did not become healthy at {base}")


async def _auth(client: httpx.AsyncClient, base: str, name: str) -> dict:
    response = await client.post(
        f"{base}/v1/auth/dev",
        json={"display_name": name, "installation_id": str(uuid4()), "age": 18},
    )
    response.raise_for_status()
    return response.json()


async def _run_player(
    player: PlayerClient,
    ws_url: str,
    *,
    stop: asyncio.Event,
    last_broadcast_mono: list[float],
    location_interval_s: float,
) -> int:
    locations_sent = 0
    lat, lon = _square_point(player.index, MAX_GAME_PLAYERS)
    if player.role == "seeker":
        lat += 5 * _M
    else:
        lat -= 5 * _M

    async def handle_message(raw: str | bytes) -> None:
        try:
            message = json.loads(raw)
        except json.JSONDecodeError:
            player.errors.append("bad_json")
            return
        kind = message.get("type")
        data = message.get("data") or {}
        if kind == "welcome":
            player.welcome += 1
            player.connected = True
        elif kind == "view":
            player.views += 1
            mark = last_broadcast_mono[0]
            if mark > 0:
                player.view_latencies_ms.append((time.monotonic() - mark) * 1000.0)
        elif kind == "event":
            player.events += 1
            seq = data.get("seq")
            if isinstance(seq, int):
                if player.last_seq is None or seq > player.last_seq:
                    player.last_seq = seq
        elif kind == "error":
            player.errors.append(f"{data.get('code')}:{data.get('message')}")

    try:
        async with websockets.connect(
            ws_url,
            open_timeout=10,
            close_timeout=5,
            max_queue=64,
        ) as ws:
            await ws.send(
                json.dumps(
                    {
                        "type": "hello",
                        "data": {"token": player.token, "last_seq": player.last_seq},
                    }
                )
            )
            for _ in range(6):
                raw = await asyncio.wait_for(ws.recv(), timeout=5)
                await handle_message(raw)
                if player.views >= 1 and player.welcome >= 1:
                    break

            last_loc = 0.0
            while not stop.is_set():
                try:
                    raw = await asyncio.wait_for(ws.recv(), timeout=location_interval_s)
                    await handle_message(raw)
                except TimeoutError:
                    pass
                now = time.monotonic()
                if now - last_loc >= location_interval_s:
                    wobble = (locations_sent % 5) * 0.5 * _M
                    await ws.send(
                        json.dumps(
                            {
                                "type": "location",
                                "data": {
                                    "lat": lat + wobble,
                                    "lon": lon + wobble,
                                    "accuracy_m": 5.0,
                                    "flag": "normal",
                                },
                            }
                        )
                    )
                    locations_sent += 1
                    last_loc = now
                    if locations_sent % 15 == 0:
                        await ws.send(json.dumps({"type": "ping", "data": {}}))
    except ConnectionClosed as exc:
        player.errors.append(f"closed:{exc.code}")
        player.connected = False
    except Exception as exc:  # noqa: BLE001
        player.errors.append(f"{type(exc).__name__}:{exc}")
        player.connected = False
    return locations_sent


async def _reconnect_player(player: PlayerClient, ws_url: str) -> bool:
    try:
        async with websockets.connect(ws_url, open_timeout=10, close_timeout=5) as ws:
            await ws.send(
                json.dumps(
                    {
                        "type": "hello",
                        "data": {"token": player.token, "last_seq": player.last_seq},
                    }
                )
            )
            got_welcome = False
            got_view = False
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and not (got_welcome and got_view):
                raw = await asyncio.wait_for(ws.recv(), timeout=5)
                message = json.loads(raw)
                kind = message.get("type")
                if kind == "welcome":
                    got_welcome = True
                elif kind == "view":
                    got_view = True
                    player.views += 1
                elif kind == "event":
                    player.events += 1
                    seq = (message.get("data") or {}).get("seq")
                    if isinstance(seq, int):
                        player.last_seq = max(player.last_seq or 0, seq)
            player.connected = got_welcome and got_view
            return player.connected
    except Exception as exc:  # noqa: BLE001
        player.errors.append(f"reconnect:{type(exc).__name__}:{exc}")
        return False


async def run_stress(
    *,
    players: int = MAX_GAME_PLAYERS,
    seekers: int = 3,
    gameplay_s: float = 20.0,
    location_hz: float = 1.0,
    host: str = "127.0.0.1",
    port: int = 0,
) -> StressReport:
    if players > MAX_GAME_PLAYERS:
        raise ValueError(f"players={players} exceeds MAX_GAME_PLAYERS={MAX_GAME_PLAYERS}")
    if seekers < 1 or seekers >= players:
        raise ValueError("need at least one seeker and one hider")

    tmp = tempfile.TemporaryDirectory(prefix="manhunt-stress-")
    db_path = Path(tmp.name) / "stress.db"
    log_dir = Path(tmp.name) / "playtest-logs"

    sock_port = port
    if sock_port == 0:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.bind((host, 0))
            sock_port = sock.getsockname()[1]

    settings = Settings(
        manhunt_env="test",
        manhunt_dev_auth=True,
        manhunt_tick_loop=True,
        manhunt_session_signing_key="s" * 32,
        manhunt_qr_signing_key="q" * 32,
        manhunt_database_url=f"sqlite+aiosqlite:///{db_path}",
        manhunt_self_ping_url=f"http://{host}:{sock_port}/v1/healthz",
        manhunt_playtest_log_dir=str(log_dir),
    )
    app = create_app(settings)

    config = uvicorn.Config(
        app,
        host=host,
        port=sock_port,
        log_level="warning",
        access_log=False,
        lifespan="on",
    )
    server = uvicorn.Server(config)
    server_task = asyncio.create_task(server.serve())
    base = f"http://{host}:{sock_port}"
    ws_base = f"ws://{host}:{sock_port}"

    errors: list[str] = []
    rss_samples: list[float] = []
    broadcast_ms: list[float] = []
    location_sends = 0
    reconnect_ok = 0
    reconnect_fail = 0
    sockets_open = 0
    join_ok = False
    start_ok = False
    clients: list[PlayerClient] = []
    last_broadcast_mono = [0.0]

    ru_before = resource.getrusage(resource.RUSAGE_SELF)

    try:
        await _wait_healthy(base)
        rss_samples.append(_sample_rss_mb(os.getpid()))

        async with httpx.AsyncClient(timeout=30.0) as http:
            for index in range(players):
                role = "seeker" if index < seekers else "hider"
                label = "iOS" if role == "seeker" else "web"
                name = f"{label}-{role}-{index}"
                body = await _auth(http, base, name)
                clients.append(
                    PlayerClient(
                        index=index,
                        name=name,
                        role=role,
                        token=body["access_token"],
                        user_id=body["user"]["id"],
                    )
                )

            host_player = clients[0]
            arena = await http.post(
                f"{base}/v1/arenas",
                json=ARENA,
                headers={"Authorization": f"Bearer {host_player.token}"},
            )
            arena.raise_for_status()
            game = await http.post(
                f"{base}/v1/games",
                json={
                    "arena_id": arena.json()["id"],
                    "preset_id": "classic",
                    "overrides": {
                        "head_start": {"enabled": False},
                        "signal_loss": {"silence": 120},
                        "reveal_fuzzy": {"interval": 60},
                    },
                },
                headers={"Authorization": f"Bearer {host_player.token}"},
            )
            game.raise_for_status()
            game_id = game.json()["id"]
            join_code = game.json()["join_code"]
            game_uuid = UUID(game_id)

            for guest in clients[1:]:
                joined = await http.post(
                    f"{base}/v1/games/join",
                    json={"join_code": join_code},
                    headers={"Authorization": f"Bearer {guest.token}"},
                )
                if joined.status_code != 200:
                    errors.append(
                        f"join_failed:{guest.name}:{joined.status_code}:{joined.text}"
                    )
            join_ok = not any(err.startswith("join_failed:") for err in errors)

            roles = await http.post(
                f"{base}/v1/games/{game_id}/roles",
                json={
                    "mode": "manual",
                    "assignments": {p.user_id: p.role for p in clients},
                },
                headers={"Authorization": f"Bearer {host_player.token}"},
            )
            if roles.status_code != 200:
                errors.append(f"roles_failed:{roles.status_code}:{roles.text}")
            started = await http.post(
                f"{base}/v1/games/{game_id}/start",
                headers={"Authorization": f"Bearer {host_player.token}"},
            )
            if started.status_code != 200:
                errors.append(f"start_failed:{started.status_code}:{started.text}")
            else:
                start_ok = True

            ws_url = f"{ws_base}/v1/games/{game_id}/ws"
            stop = asyncio.Event()

            async def sample_broadcast_cost() -> None:
                manager = app.state.manager
                while not stop.is_set():
                    t0 = time.monotonic()
                    await manager.broadcast(game_uuid)
                    # broadcast only queues now; settle waits for delivery so the number
                    # still measures how long a tick's frames take to reach every socket.
                    # TODO: not run on this change (needs POSIX `resource`); verify on the host.
                    await manager.settle(game_uuid)
                    last_broadcast_mono[0] = time.monotonic()
                    broadcast_ms.append((last_broadcast_mono[0] - t0) * 1000.0)
                    rss_samples.append(_sample_rss_mb(os.getpid()))
                    await asyncio.sleep(1.0)

            marker = asyncio.create_task(sample_broadcast_cost())
            player_tasks = [
                asyncio.create_task(
                    _run_player(
                        player,
                        ws_url,
                        stop=stop,
                        last_broadcast_mono=last_broadcast_mono,
                        location_interval_s=1.0 / location_hz,
                    )
                )
                for player in clients
            ]

            await asyncio.sleep(2.0)
            sockets_open = sum(1 for player in clients if player.connected)
            await asyncio.sleep(max(0.0, gameplay_s - 2.0))
            stop.set()
            marker.cancel()
            try:
                await marker
            except asyncio.CancelledError:
                pass
            results = await asyncio.gather(*player_tasks, return_exceptions=True)
            for result in results:
                if isinstance(result, int):
                    location_sends += result
                elif isinstance(result, Exception):
                    errors.append(f"player_task:{result}")

            for player in clients[::2]:
                if await _reconnect_player(player, ws_url):
                    reconnect_ok += 1
                else:
                    reconnect_fail += 1

    except Exception as exc:  # noqa: BLE001
        errors.append(f"harness:{type(exc).__name__}:{exc}")
        traceback.print_exc()
    finally:
        server.should_exit = True
        try:
            await asyncio.wait_for(server_task, timeout=10)
        except (TimeoutError, asyncio.CancelledError):
            server_task.cancel()
        tmp.cleanup()

    ru_after = resource.getrusage(resource.RUSAGE_SELF)
    all_view_lat = [ms for player in clients for ms in player.view_latencies_ms]
    views_received = sum(player.views for player in clients)
    events_received = sum(player.events for player in clients)
    for player in clients:
        errors.extend(f"{player.name}:{err}" for err in player.errors)

    fail_reasons: list[str] = []
    if not join_ok:
        fail_reasons.append("join_not_clean")
    if not start_ok:
        fail_reasons.append("start_failed")
    if sockets_open < players:
        fail_reasons.append(f"sockets_open={sockets_open}<{players}")
    if views_received < players:
        fail_reasons.append(f"views_received={views_received}<{players}")
    if reconnect_fail:
        fail_reasons.append(f"reconnect_fail={reconnect_fail}")
    p95 = _percentile(all_view_lat, 95)
    if p95 is not None and p95 > 2000:
        fail_reasons.append(f"view_p95_ms={p95:.0f}>2000")
    b95 = _percentile(broadcast_ms, 95)
    if b95 is not None and b95 > 1000:
        fail_reasons.append(f"broadcast_p95_ms={b95:.0f}>1000")

    return StressReport(
        players=players,
        seekers=seekers,
        hiders=players - seekers,
        join_ok=join_ok,
        start_ok=start_ok,
        sockets_open=sockets_open,
        gameplay_seconds=gameplay_s,
        views_received=views_received,
        events_received=events_received,
        location_sends=location_sends,
        reconnect_ok=reconnect_ok,
        reconnect_fail=reconnect_fail,
        view_p50_ms=_percentile(all_view_lat, 50),
        view_p95_ms=p95,
        view_max_ms=max(all_view_lat) if all_view_lat else None,
        broadcast_p50_ms=_percentile(broadcast_ms, 50),
        broadcast_p95_ms=b95,
        broadcast_max_ms=max(broadcast_ms) if broadcast_ms else None,
        rss_peak_mb=max(rss_samples) if rss_samples else 0.0,
        cpu_user_s=max(0.0, ru_after.ru_utime - ru_before.ru_utime),
        cpu_system_s=max(0.0, ru_after.ru_stime - ru_before.ru_stime),
        errors=errors[:40],
        passed=not fail_reasons,
        fail_reasons=fail_reasons,
    )


def print_report(report: StressReport) -> None:
    def fmt(value: float | None) -> str:
        return "n/a" if value is None else f"{value:.1f}"

    print("=== Manhunt full-lobby stress ===")
    print(
        f"players={report.players} seekers(iOS)={report.seekers} "
        f"hiders(web)={report.hiders}"
    )
    print(
        f"join_ok={report.join_ok} start_ok={report.start_ok} "
        f"sockets_open={report.sockets_open}"
    )
    print(
        f"gameplay_s={report.gameplay_seconds:.1f} views={report.views_received} "
        f"events={report.events_received} locations_sent={report.location_sends}"
    )
    print(f"reconnect_ok={report.reconnect_ok} reconnect_fail={report.reconnect_fail}")
    print(
        f"view_latency_ms p50={fmt(report.view_p50_ms)} "
        f"p95={fmt(report.view_p95_ms)} max={fmt(report.view_max_ms)}"
    )
    print(
        f"broadcast_ms p50={fmt(report.broadcast_p50_ms)} "
        f"p95={fmt(report.broadcast_p95_ms)} max={fmt(report.broadcast_max_ms)}"
    )
    print(
        f"rss_peak_mb={report.rss_peak_mb:.1f} "
        f"cpu_user_s={report.cpu_user_s:.2f} cpu_system_s={report.cpu_system_s:.2f}"
    )
    if report.errors:
        print(f"errors({len(report.errors)}):")
        for err in report.errors[:20]:
            print(f"  - {err}")
    if report.passed:
        print("RESULT: PASS at", report.players)
    else:
        print("RESULT: FAIL at", report.players, "reasons=", report.fail_reasons)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--players", type=int, default=MAX_GAME_PLAYERS)
    parser.add_argument("--seekers", type=int, default=3)
    parser.add_argument("--seconds", type=float, default=20.0)
    parser.add_argument("--location-hz", type=float, default=1.0)
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()
    report = asyncio.run(
        run_stress(
            players=args.players,
            seekers=args.seekers,
            gameplay_s=args.seconds,
            location_hz=args.location_hz,
            port=args.port,
        )
    )
    print_report(report)
    return 0 if report.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
