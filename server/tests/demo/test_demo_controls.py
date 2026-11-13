"""Tests for POST /v1/games/{id}/demo, build_view demo block, and config gates."""

from uuid import UUID

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def _auth(client: TestClient, name: str) -> dict:
    res = client.post("/v1/auth/dev", json={"display_name": name})
    assert res.status_code == 200
    return res.json()


def _hdr(auth: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth['access_token']}"}


def _join_park(client: TestClient, auth: dict) -> str:
    res = client.post("/v1/games/join", headers=_hdr(auth), json={"join_code": "PARK42"})
    assert res.status_code == 200
    return res.json()["id"]


def test_demo_view_and_all_host_actions(client: TestClient) -> None:
    host = _auth(client, "Casey")
    gid = _join_park(client, host)

    view = client.get(f"/v1/games/{gid}", headers=_hdr(host)).json()
    assert view["demo"]["controls_enabled"] is True
    assert view["demo"]["speed"] == 1
    assert view["demo"]["lobby_hold"] is False
    assert view["demo"]["seeker_lock"] == "spawn_zone"
    assert len(view["demo"]["bots"]) == 5

    # Lobby hold & seeker_lock toggle
    held = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "lobby_hold", "hold": True},
    )
    assert held.status_code == 200
    assert held.json()["demo"]["lobby_hold"] is True

    locked = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "set_seeker_lock", "mode": "locked_map"},
    )
    assert locked.status_code == 200
    assert locked.json()["demo"]["seeker_lock"] == "locked_map"

    # End phase: lobby -> head_start -> active
    hs = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "end_phase"},
    )
    assert hs.status_code == 200
    assert hs.json()["phase"] == "head_start"

    active = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "end_phase"},
    )
    assert active.status_code == 200
    assert active.json()["phase"] == "active"

    # Add points
    pts_before = active.json()["you"]["points"]
    added = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "add_points", "amount": 100},
    )
    assert added.status_code == 200
    assert added.json()["you"]["points"] == pts_before + 100

    # Switch team
    role_before = added.json()["you"]["role"]
    switched = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "switch_team"},
    )
    assert switched.status_code == 200
    assert switched.json()["you"]["role"] != role_before

    # Ensure host is seeker so build_view returns all hider reveal pins
    if switched.json()["you"]["role"] != "seeker":
        switched = client.post(
            f"/v1/games/{gid}/demo",
            headers=_hdr(host),
            json={"action": "switch_team", "role": "seeker"},
        )
        assert switched.status_code == 200

    # Force reveal (two active hider bots exist right after head start)
    revealed = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "force_reveal"},
    )
    assert revealed.status_code == 200
    assert len(revealed.json()["reveals"]) >= 1

    # Bot go dark & restore
    dark = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "bot_go_dark", "dark": True},
    )
    assert dark.status_code == 200
    assert any(p["status"] == "signal_lost" for p in dark.json()["players"])
    dark_bot_id = next(
        b["player_id"] for b in dark.json()["demo"]["bots"] if b["mode"] == "go_dark"
    )
    restored = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "bot_go_dark", "bot_id": dark_bot_id, "dark": False},
    )
    assert restored.status_code == 200
    assert all(b["mode"] != "go_dark" for b in restored.json()["demo"]["bots"])

    # Bot OOB & return
    oob = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "bot_oob", "oob": True},
    )
    assert oob.status_code == 200
    assert any(b["mode"] == "oob" for b in oob.json()["demo"]["bots"])
    oob_bot_id = next(b["player_id"] for b in oob.json()["demo"]["bots"] if b["mode"] == "oob")
    returned = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "bot_oob", "bot_id": oob_bot_id, "oob": False},
    )
    assert returned.status_code == 200
    assert all(b["mode"] != "oob" for b in returned.json()["demo"]["bots"])

    # Move me
    moved = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "move_me", "lat": 40.6619, "lon": -73.9691},
    )
    assert moved.status_code == 200
    assert moved.json()["demo"]["virtual_location"] is not None

    # Switch to hider so at least 2 active hiders exist, then force_tag leaves >= 1 active.
    if switched.json()["you"]["role"] != "hider":
        as_hider = client.post(
            f"/v1/games/{gid}/demo",
            headers=_hdr(host),
            json={"action": "switch_team", "role": "hider"},
        )
        assert as_hider.status_code == 200

    tagged = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "force_tag"},
    )
    assert tagged.status_code == 200
    assert tagged.json()["phase"] == "active"
    session = client.app.state.manager.get(UUID(gid))
    assert session is not None
    assert any(e.type == "tag" for e in session.state.event_log)

    # Speed & skip 1 min (triggers zone shrink)
    spd = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "set_speed", "speed": 5},
    )
    assert spd.status_code == 200
    assert spd.json()["demo"]["speed"] == 5

    before_r = spd.json()["timers"]["zone"]["radius_m"]
    skipped = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(host),
        json={"action": "skip", "seconds": 60},
    )
    assert skipped.status_code == 200
    if skipped.json()["phase"] != "ended":
        assert skipped.json()["timers"]["zone"]["radius_m"] < before_r
    else:
        assert skipped.json()["result"] is not None

    # End phase in active -> ended
    if skipped.json()["phase"] != "ended":
        ended = client.post(
            f"/v1/games/{gid}/demo",
            headers=_hdr(host),
            json={"action": "end_phase"},
        )
        assert ended.status_code == 200
        assert ended.json()["phase"] == "ended"


def test_demo_gate_permissions_normal_game_and_prod_env(client: TestClient, tmp_path) -> None:
    host = _auth(client, "Casey")
    joiner = _auth(client, "Morgan")
    gid = _join_park(client, host)
    client.post("/v1/games/join", headers=_hdr(joiner), json={"join_code": "PARK42"})

    # Non-host gets 403 on host demo actions, but can move_me
    forbidden = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(joiner),
        json={"action": "skip", "seconds": 60},
    )
    assert forbidden.status_code == 403
    assert forbidden.json()["error"]["code"] == "NOT_HOST"

    joiner_view = client.get(f"/v1/games/{gid}", headers=_hdr(joiner)).json()
    assert joiner_view["demo"]["controls_enabled"] is False

    move_ok = client.post(
        f"/v1/games/{gid}/demo",
        headers=_hdr(joiner),
        json={"action": "move_me", "lat": 40.6618, "lon": -73.9690},
    )
    assert move_ok.status_code == 200

    # Normal non-sample game returns 404
    arena = client.post(
        "/v1/arenas",
        headers=_hdr(host),
        json={
            "name": "Normal",
            "boundary": [
                {"lat": 40.663, "lon": -73.970},
                {"lat": 40.663, "lon": -73.968},
                {"lat": 40.661, "lon": -73.969},
            ],
            "zones": [],
        },
    ).json()
    normal_gid = client.post(
        "/v1/games",
        headers=_hdr(host),
        json={"arena_id": arena["id"], "preset_id": "classic", "overrides": {}},
    ).json()["id"]
    normal_view = client.get(f"/v1/games/{normal_gid}", headers=_hdr(host)).json()
    assert "demo" not in normal_view or normal_view["demo"] is None
    not_demo = client.post(
        f"/v1/games/{normal_gid}/demo",
        headers=_hdr(host),
        json={"action": "skip", "seconds": 60},
    )
    assert not_demo.status_code == 404

    # Prod / Azure env disables demo controls by default
    prod_settings = Settings(
        manhunt_env="prod",
        manhunt_database_url=f"sqlite+aiosqlite:///{tmp_path / 'prod.db'}",
        manhunt_dev_auth=False,
        manhunt_tick_loop=False,
    )
    assert prod_settings.demo_controls_enabled is False
    assert Settings(manhunt_env="azure").demo_controls_enabled is False

    disabled_app = create_app(
        Settings(
            manhunt_env="test",
            manhunt_database_url=f"sqlite+aiosqlite:///{tmp_path / 'disabled.db'}",
            manhunt_dev_auth=True,
            manhunt_tick_loop=False,
            manhunt_demo_controls=False,
        )
    )
    with TestClient(disabled_app) as disabled_client:
        h2 = _auth(disabled_client, "Casey")
        gid2 = _join_park(disabled_client, h2)
        view2 = disabled_client.get(f"/v1/games/{gid2}", headers=_hdr(h2)).json()
        assert view2["demo"]["controls_enabled"] is False
        res = disabled_client.post(
            f"/v1/games/{gid2}/demo",
            headers=_hdr(h2),
            json={"action": "skip"},
        )
        assert res.status_code == 404
