"""The results timeline is the ordered non-sensitive event log."""

from datetime import timedelta
from uuid import UUID

from fastapi.testclient import TestClient

from app.engine.arena import arena_to_dict
from app.engine.clock import FakeClock
from app.engine.qr import make_qr_token
from app.engine.state import LocationReading
from tests.engine.helpers import meters, square

PLAYTEST = ("reveal", "tag", "out_of_bounds", "signal_lost")


def _auth(client: TestClient, name: str) -> dict:
    response = client.post("/v1/auth/dev", json={"display_name": name})
    assert response.status_code == 200, response.text
    return response.json()


def _hdr(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _put(session, player_id: str, point) -> None:
    session.record_location(
        UUID(player_id),
        LocationReading(
            lat=point.lat,
            lon=point.lon,
            accuracy_m=5,
            recorded_at=session.clock.now(),
        ),
    )


def test_results_timeline_includes_playtest_events_in_order(client: TestClient) -> None:
    host = _auth(client, "Seeker")
    hider_a = _auth(client, "Hider")
    hider_b = _auth(client, "Runner")
    headers = _hdr(host["access_token"])
    arena = client.post("/v1/arenas", json=arena_to_dict(square()), headers=headers)
    assert arena.status_code == 200, arena.text
    game = client.post(
        "/v1/games",
        json={
            "arena_id": arena.json()["id"],
            "preset_id": "classic",
            "overrides": {
                "head_start": {"enabled": False},
                "reveal_fuzzy": {"interval": 20, "enabled": True},
                "zone_policy": {"oob_countdown": 5},
                "signal_loss": {"silence": 15},
                # Eliminations must not end the hunt before signal loss is recorded.
                "win": {"condition": "time_limit", "time_limit": 30},
            },
        },
        headers=headers,
    )
    assert game.status_code == 200, game.text
    gid = game.json()["id"]
    code = game.json()["join_code"]
    client.post("/v1/games/join", json={"join_code": code}, headers=_hdr(hider_a["access_token"]))
    client.post("/v1/games/join", json={"join_code": code}, headers=_hdr(hider_b["access_token"]))
    view = client.get(f"/v1/games/{gid}", headers=headers).json()
    ids = {p["display_name"]: p["player_id"] for p in view["players"]}
    roles = client.post(
        f"/v1/games/{gid}/roles",
        json={
            "mode": "manual",
            "assignments": {
                ids["Seeker"]: "seeker",
                ids["Hider"]: "hider",
                ids["Runner"]: "hider",
            },
        },
        headers=headers,
    )
    assert roles.status_code == 200, roles.text
    started = client.post(f"/v1/games/{gid}/start", headers=headers)
    assert started.status_code == 200, started.text

    manager = client.app.state.manager
    session = manager.get(UUID(gid))
    assert session is not None
    _put(session, ids["Hider"], meters(100, 100))
    _put(session, ids["Runner"], meters(100, 100))
    _put(session, ids["Seeker"], meters(100, 101))
    # Reveal interval is 20 game seconds. One tick is not enough; walk the clock.
    for _ in range(20):
        manager.tick_all()

    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=UUID(ids["Hider"]),
        expires_at=session.clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    tagged = client.post(
        f"/v1/games/{gid}/tags/qr",
        json={"token": token},
        headers=headers,
    )
    assert tagged.status_code == 200, tagged.text

    _put(session, ids["Runner"], meters(100, -80))
    for _ in range(8):
        manager.tick_all()

    clock = session.clock
    assert isinstance(clock, FakeClock)
    clock.advance(20)
    manager.tick_all()

    timeline = client.get(f"/v1/games/{gid}/events", headers=headers)
    assert timeline.status_code == 200, timeline.text
    events = timeline.json()["events"]
    types = [event["type"] for event in events]
    seqs = [event["seq"] for event in events]
    assert seqs == sorted(seqs)
    assert "location" not in types
    for required in PLAYTEST:
        assert required in types, types
    assert types.index("reveal") < types.index("tag")
    assert types.index("tag") < types.index("out_of_bounds")
    assert types.index("out_of_bounds") < types.index("signal_lost")
    for event in events:
        if event["type"] in PLAYTEST:
            assert event["payload"]["text"]
