"""Host edits the rules from the lobby. Host-only, lobby-only, and visible to everyone live."""

from __future__ import annotations

import json
from uuid import UUID, uuid4

import anyio
from fastapi.testclient import TestClient

from app.db.models import GameRow
from app.engine.arena import arena_to_dict
from tests.engine.helpers import square


def _auth(client: TestClient, name: str) -> dict:
    response = client.post(
        "/v1/auth/dev",
        json={"display_name": name, "installation_id": str(uuid4()), "age": 18},
    )
    assert response.status_code == 200, response.text
    return response.json()


def _hdr(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _lobby(client: TestClient) -> tuple[dict, dict, str, str]:
    """Host + one guest in a lobby. Returns (host, guest, game_id, join_code)."""
    host = _auth(client, "Casey")
    guest = _auth(client, "Riley")
    arena = client.post(
        "/v1/arenas", json=arena_to_dict(square()), headers=_hdr(host["access_token"])
    )
    assert arena.status_code == 200, arena.text
    game = client.post(
        "/v1/games",
        json={"arena_id": arena.json()["id"], "preset_id": "classic", "overrides": {}},
        headers=_hdr(host["access_token"]),
    )
    assert game.status_code == 200, game.text
    joined = client.post(
        "/v1/games/join",
        json={"join_code": game.json()["join_code"]},
        headers=_hdr(guest["access_token"]),
    )
    assert joined.status_code == 200, joined.text
    return host, guest, game.json()["id"], game.json()["join_code"]


def _rules(client: TestClient, token: str, game_id: str, overrides: dict):
    return client.post(
        f"/v1/games/{game_id}/rules",
        json={"overrides": overrides},
        headers=_hdr(token),
    )


def _next_view(ws, timeout: float = 2) -> dict:
    async def receive():
        with anyio.fail_after(timeout):
            message = await ws._send_rx.receive()
        if message["type"] == "websocket.close":
            raise AssertionError(f"socket closed: {message.get('code')}")
        return json.loads(message["text"])

    while True:
        try:
            frame = ws.portal.call(receive)
        except TimeoutError:
            raise AssertionError("expected a websocket frame") from None
        if frame["type"] == "view":
            return frame


def test_host_updates_rules_and_view_reflects_them(client: TestClient) -> None:
    host, _guest, game_id, _code = _lobby(client)
    response = _rules(
        client,
        host["access_token"],
        game_id,
        {"head_start": {"duration": 90}, "win": {"time_limit": 45}},
    )
    assert response.status_code == 200, response.text
    timers = response.json()["timers"]
    assert timers["head_start_s"] == 90
    assert timers["time_limit_s"] == 45 * 60

    # A fresh read (the path a rejoining phone uses) must agree.
    again = client.get(f"/v1/games/{game_id}", headers=_hdr(host["access_token"]))
    assert again.json()["timers"]["head_start_s"] == 90


def test_non_host_gets_not_host(client: TestClient) -> None:
    host, guest, game_id, _code = _lobby(client)
    denied = _rules(client, guest["access_token"], game_id, {"head_start": {"duration": 90}})
    assert denied.status_code == 403
    assert denied.json()["error"]["code"] == "NOT_HOST"
    still = client.get(f"/v1/games/{game_id}", headers=_hdr(host["access_token"]))
    assert still.json()["timers"]["head_start_s"] == 60


def test_edit_after_start_gets_wrong_phase(client: TestClient) -> None:
    host, guest, game_id, _code = _lobby(client)
    roles = client.post(
        f"/v1/games/{game_id}/roles",
        json={
            "mode": "manual",
            "assignments": {
                host["user"]["id"]: "seeker",
                guest["user"]["id"]: "hider",
            },
        },
        headers=_hdr(host["access_token"]),
    )
    assert roles.status_code == 200, roles.text
    started = client.post(f"/v1/games/{game_id}/start", headers=_hdr(host["access_token"]))
    assert started.status_code == 200, started.text
    late = _rules(client, host["access_token"], game_id, {"head_start": {"duration": 90}})
    assert late.status_code == 409
    assert late.json()["error"]["code"] == "WRONG_PHASE"


def test_invalid_rules_are_rejected_without_partial_apply(client: TestClient) -> None:
    host, _guest, game_id, _code = _lobby(client)
    out_of_range = _rules(
        client,
        host["access_token"],
        game_id,
        {"win": {"time_limit": 45}, "head_start": {"duration": 5}},
    )
    assert out_of_range.status_code == 422
    unknown_module = _rules(client, host["access_token"], game_id, {"nope": {"x": 1}})
    assert unknown_module.status_code == 422
    unknown_field = _rules(client, host["access_token"], game_id, {"win": {"bogus": 1}})
    assert unknown_field.status_code == 422
    wrong_type = _rules(client, host["access_token"], game_id, {"head_start": {"enabled": "yes"}})
    assert wrong_type.status_code == 422
    view = client.get(f"/v1/games/{game_id}", headers=_hdr(host["access_token"])).json()
    assert view["timers"]["time_limit_s"] == 30 * 60
    assert view["timers"]["head_start_s"] == 60


def test_rules_edit_keeps_roles_and_players(client: TestClient) -> None:
    host, guest, game_id, _code = _lobby(client)
    client.post(
        f"/v1/games/{game_id}/roles",
        json={
            "mode": "manual",
            "assignments": {
                host["user"]["id"]: "seeker",
                guest["user"]["id"]: "hider",
            },
        },
        headers=_hdr(host["access_token"]),
    )
    response = _rules(client, host["access_token"], game_id, {"win": {"time_limit": 20}})
    assert response.status_code == 200, response.text
    roles = {p["display_name"]: p["role"] for p in response.json()["players"]}
    assert roles == {"Casey": "seeker", "Riley": "hider"}


def test_zone_shrink_requires_circle_play_area(client: TestClient) -> None:
    host, _guest, game_id, _code = _lobby(client)
    # The square arena has no play circle, so shrinking cannot be enabled on it.
    response = _rules(client, host["access_token"], game_id, {"zone_shrink": {"enabled": True}})
    assert response.status_code == 422


def test_rules_edit_reaches_every_lobby_member_live(client: TestClient) -> None:
    host, guest, game_id, _code = _lobby(client)
    with client.websocket_connect(f"/v1/games/{game_id}/ws") as guest_ws:
        guest_ws.send_json({"type": "hello", "data": {"token": guest["access_token"]}})
        assert _next_view(guest_ws)["data"]["timers"]["head_start_s"] == 60
        response = _rules(client, host["access_token"], game_id, {"head_start": {"duration": 120}})
        assert response.status_code == 200, response.text
        pushed = _next_view(guest_ws)
        assert pushed["data"]["timers"]["head_start_s"] == 120


def _circle_lobby(client: TestClient, radius_m: float = 400) -> tuple[dict, str]:
    host = _auth(client, "Casey")
    arena = client.post(
        "/v1/arenas",
        json={
            "name": "Park",
            "boundary": [],
            "boundary_circle": {"center": {"lat": 40.6616, "lon": -73.9688}, "radius_m": radius_m},
            "zones": [],
        },
        headers=_hdr(host["access_token"]),
    )
    assert arena.status_code == 200, arena.text
    game = client.post(
        "/v1/games",
        json={"arena_id": arena.json()["id"], "preset_id": "classic", "overrides": {}},
        headers=_hdr(host["access_token"]),
    )
    assert game.status_code == 200, game.text
    return host, game.json()["id"]


def test_non_finite_and_absurd_numbers_are_rejected_and_the_game_stays_readable(
    client: TestClient,
) -> None:
    host, _guest, game_id, _code = _lobby(client)
    token = host["access_token"]
    for raw in (
        '{"overrides":{"win":{"time_limit":NaN}}}',
        '{"overrides":{"win":{"time_limit":Infinity}}}',
        '{"overrides":{"win":{"time_limit":-Infinity}}}',
        '{"overrides":{"win":{"time_limit":' + "9" * 400 + "}}}",
        '{"overrides":{"power_ups":{"ghost_cost":NaN}}}',
    ):
        response = client.post(
            f"/v1/games/{game_id}/rules",
            content=raw,
            headers={**_hdr(token), "Content-Type": "application/json"},
        )
        assert response.status_code == 422, (raw[:60], response.text)
    view = client.get(f"/v1/games/{game_id}", headers=_hdr(token))
    assert view.status_code == 200
    assert view.json()["timers"]["time_limit_s"] == 30 * 60


def test_values_are_checked_against_the_module_schema(client: TestClient) -> None:
    host, _guest, game_id, _code = _lobby(client)
    token = host["access_token"]
    bad_edits = [
        {"power_ups": {"ghost_cost": -500}},
        {"power_ups": {"ghost_cost": 201}},
        {"power_ups": {"ghost_cost": 1e308}},
        {"roles": {"seeker_count": 1.5}},
        {"head_start": {"seeker_lock": "xx"}},
        {"reveal_fuzzy": {"location_mode": "xx"}},
        {"head_start": {"duration": True}},
    ]
    for overrides in bad_edits:
        response = _rules(client, token, game_id, overrides)
        assert response.status_code == 422, (overrides, response.text)
    good = _rules(
        client,
        token,
        game_id,
        {
            "head_start": {"seeker_lock": "spawn_zone", "duration": 90.0},
            "power_ups": {"ghost_cost": 30},
        },
    )
    assert good.status_code == 200, good.text
    assert good.json()["timers"]["head_start_s"] == 90


def test_edit_is_saved_even_when_the_live_session_shares_the_rows_dict(
    client: TestClient,
) -> None:
    host, _guest, game_id, _code = _lobby(client)
    # Dropping the live session makes the next call rebuild it from the row. The rebuilt
    # session may hold the row's own preset dict, which used to hide the change from the ORM.
    client.app.state.manager.sessions.pop(UUID(game_id))
    response = _rules(client, host["access_token"], game_id, {"head_start": {"duration": 90}})
    assert response.status_code == 200, response.text

    async def saved() -> int:
        async with client.app.state.session_factory() as db:
            row = await db.get(GameRow, UUID(game_id))
            return row.preset_snapshot["modules"]["head_start"]["duration"]

    assert client.portal.call(saved) == 90


def test_a_rematch_inherits_the_edited_rules(client: TestClient) -> None:
    host, guest, game_id, _code = _lobby(client)
    headers = _hdr(host["access_token"])
    assert (
        _rules(client, host["access_token"], game_id, {"head_start": {"duration": 90}}).status_code
        == 200
    )
    client.post(
        f"/v1/games/{game_id}/roles",
        json={
            "mode": "manual",
            "assignments": {
                host["user"]["id"]: "seeker",
                guest["user"]["id"]: "hider",
            },
        },
        headers=headers,
    )
    assert client.post(f"/v1/games/{game_id}/start", headers=headers).status_code == 200
    assert client.post(f"/v1/games/{game_id}/end", headers=headers).status_code == 200
    rematch = client.post(f"/v1/games/{game_id}/rematch", headers=headers)
    assert rematch.status_code == 200, rematch.text
    assert rematch.json()["timers"]["head_start_s"] == 90


def test_zone_shrink_can_be_enabled_on_a_circle_but_not_below_the_radius(
    client: TestClient,
) -> None:
    host, game_id = _circle_lobby(client, radius_m=400)
    token = host["access_token"]
    enabled = _rules(client, token, game_id, {"zone_shrink": {"enabled": True}})
    assert enabled.status_code == 200, enabled.text
    # With shrink on, the play circle may not be resized to the shrink floor or smaller.
    too_small = client.post(
        f"/v1/games/{game_id}/arena", headers=_hdr(token), json={"radius_m": 50}
    )
    assert too_small.status_code == 422
    fine = client.post(f"/v1/games/{game_id}/arena", headers=_hdr(token), json={"radius_m": 200})
    assert fine.status_code == 200, fine.text
    # And the floor cannot be raised past the current radius either.
    raised = _rules(client, token, game_id, {"zone_shrink": {"min_radius_m": 300}})
    assert raised.status_code == 422


def test_resizing_a_polygon_arena_needs_an_explicit_center(client: TestClient) -> None:
    host, _guest, game_id, _code = _lobby(client)
    token = host["access_token"]
    refused = client.post(f"/v1/games/{game_id}/arena", headers=_hdr(token), json={"radius_m": 300})
    assert refused.status_code == 422
    view = client.get(f"/v1/games/{game_id}", headers=_hdr(token)).json()
    assert view["arena"].get("boundary_circle") is None
    chosen = client.post(
        f"/v1/games/{game_id}/arena",
        headers=_hdr(token),
        json={"radius_m": 300, "center": {"lat": 40.66, "lon": -73.96}},
    )
    assert chosen.status_code == 200, chosen.text
