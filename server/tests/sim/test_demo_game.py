"""Full-match simulation tests for the PARK42 demo lobby."""

from uuid import UUID

from fastapi.testclient import TestClient


def test_full_demo_game_plays_through_head_start_reveal_and_bot_tags(
    client: TestClient,
) -> None:
    auth = client.post("/v1/auth/dev", json={"display_name": "Casey"}).json()
    headers = {"Authorization": f"Bearer {auth['access_token']}"}

    joined = client.post("/v1/games/join", headers=headers, json={"join_code": "PARK42"})
    assert joined.status_code == 200
    gid = joined.json()["id"]

    # Put host on seeker team so bot seekers + host play against bot hiders.
    host_id = auth["user"]["id"]
    view = client.get(f"/v1/games/{gid}", headers=headers).json()
    assert view["phase"] == "lobby"
    client.post(
        f"/v1/games/{gid}/demo",
        headers=headers,
        json={"action": "switch_team", "role": "seeker"},
    )
    view = client.get(f"/v1/games/{gid}", headers=headers).json()
    if not any(p["role"] == "hider" for p in view["players"]):
        bot_id = next(p["player_id"] for p in view["players"] if p["player_id"] != host_id)
        client.post(
            f"/v1/games/{gid}/roles",
            headers=headers,
            json={"mode": "manual", "assignments": {bot_id: "hider"}},
        )

    client.post(f"/v1/games/{gid}/demo", headers=headers, json={"action": "end_phase"})
    client.post(f"/v1/games/{gid}/demo", headers=headers, json={"action": "set_speed", "speed": 5})

    manager = client.app.state.manager
    session = manager.get(UUID(gid))
    assert session is not None
    assert session.state.phase == "head_start"

    saw_reveal = False
    for _ in range(120):
        manager.tick_all()
        if session.state.reveals:
            saw_reveal = True
        if session.state.phase == "ended":
            break

    assert saw_reveal is True
    assert session.state.phase == "ended"
    assert session.state.result is not None
    assert session.state.result.winner == "seekers"
    assert any(e.type == "tag" for e in session.state.event_log)
    assert not any(item["kind"] == "location" for item in session.state.inputs)


def test_demo_game_exercises_zone_shrink_and_safe_zone_with_human_hider(
    client: TestClient,
) -> None:
    auth = client.post("/v1/auth/dev", json={"display_name": "Casey"}).json()
    headers = {"Authorization": f"Bearer {auth['access_token']}"}
    joined = client.post("/v1/games/join", headers=headers, json={"join_code": "PARK42"})
    gid = joined.json()["id"]

    # Host plays as hider. PARK42 draws one seeker, so the host may be that
    # seeker. Keep a bot on seeker or start() refuses the lobby.
    client.post(
        f"/v1/games/{gid}/demo",
        headers=headers,
        json={"action": "switch_team", "role": "hider"},
    )
    host_id = auth["user"]["id"]
    view = client.get(f"/v1/games/{gid}", headers=headers).json()
    if not any(p["role"] == "seeker" for p in view["players"]):
        bot_id = next(p["player_id"] for p in view["players"] if p["player_id"] != host_id)
        assigned = client.post(
            f"/v1/games/{gid}/roles",
            headers=headers,
            json={"mode": "manual", "assignments": {bot_id: "seeker", host_id: "hider"}},
        )
        assert assigned.status_code == 200

    started = client.post(f"/v1/games/{gid}/demo", headers=headers, json={"action": "end_phase"})
    assert started.status_code == 200
    assert started.json()["phase"] == "head_start"
    active_response = client.post(
        f"/v1/games/{gid}/demo",
        headers=headers,
        json={"action": "end_phase"},
    )
    assert active_response.status_code == 200
    active = active_response.json()
    assert active["phase"] == "active"

    # Walk host toward North Pavilion safe zone and skip 70s so zone_shrink fires.
    client.post(
        f"/v1/games/{gid}/demo",
        headers=headers,
        json={"action": "move_me", "lat": 40.66228, "lon": -73.96930},
    )
    before_r = active["timers"]["zone"]["radius_m"]
    skipped = client.post(
        f"/v1/games/{gid}/demo",
        headers=headers,
        json={"action": "skip", "seconds": 70},
    )
    assert skipped.status_code == 200
    body = skipped.json()
    assert body["timers"]["zone"]["radius_m"] < before_r
