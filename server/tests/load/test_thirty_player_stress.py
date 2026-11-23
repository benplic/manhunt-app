"""30-player live WebSocket stress against a real uvicorn + tick loop."""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

from stress_thirty_players import print_report, run_stress  # noqa: E402

from app.limits import MAX_GAME_PLAYERS  # noqa: E402


def test_thirty_player_ws_stress_passes() -> None:
    """Cap is already 30; this proves join + tick + reconnect hold at that size."""
    assert MAX_GAME_PLAYERS == 30
    report = asyncio.run(
        run_stress(players=30, seekers=3, gameplay_s=15.0, location_hz=1.0)
    )
    print_report(report)
    assert report.passed, report.fail_reasons
    assert report.sockets_open == 30
    assert report.reconnect_fail == 0
    assert report.broadcast_p95_ms is not None
    assert report.broadcast_p95_ms < 1000
