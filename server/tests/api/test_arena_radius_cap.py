"""The play circle radius cap is 3,000 m on every server entry point."""

from __future__ import annotations

import time
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.engine.arena import (
    PLAY_CIRCLE_MAX_M,
    PLAY_CIRCLE_MIN_M,
    arena_from_dict,
    clip_arena,
    validate_arena,
)
from app.engine.geo import circle_sample_ring, local_xy
from app.engine.modules.zone_shrink import zone_shrink_schedule
from tests.engine.helpers import make_session

CENTER = {"lat": 40.6616, "lon": -73.9688}


def _auth(client: TestClient, name: str = "Host") -> dict:
    response = client.post(
        "/v1/auth/dev",
        json={"display_name": name, "installation_id": str(uuid4()), "age": 18},
    )
    assert response.status_code == 200, response.text
    return response.json()


def _headers(auth: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {auth['access_token']}"}


def _arena_body(radius) -> dict:
    return {
        "name": "Park",
        "boundary": [],
        "boundary_circle": {"center": CENTER, "radius_m": radius},
        "zones": [],
    }


def test_cap_constants_are_three_kilometers() -> None:
    assert PLAY_CIRCLE_MIN_M == 30.0
    assert PLAY_CIRCLE_MAX_M == 3000.0


@pytest.mark.parametrize(
    ("radius", "valid"),
    [
        (29.99, False),
        (30, True),
        (2000, True),
        (2001, True),
        (3000, True),
        (3000.01, False),
        (3001, False),
        (float("inf"), False),
        (float("nan"), False),
    ],
)
def test_validate_arena_radius_boundaries(radius: float, valid: bool) -> None:
    arena = arena_from_dict(_arena_body(radius))
    codes = [issue.code for issue in validate_arena(arena)]
    assert ("play_area_radius_invalid" not in codes) is valid


@pytest.mark.parametrize(
    ("radius", "status"),
    [(2000, 200), (2001, 200), (3000, 200), (3001, 422)],
)
def test_create_arena_enforces_the_cap(client: TestClient, radius: float, status: int) -> None:
    host = _auth(client)
    response = client.post("/v1/arenas", headers=_headers(host), json=_arena_body(radius))
    assert response.status_code == status, response.text


def _lobby(client: TestClient, host: dict) -> str:
    arena = client.post("/v1/arenas", headers=_headers(host), json=_arena_body(400))
    assert arena.status_code == 200, arena.text
    game = client.post(
        "/v1/games",
        headers=_headers(host),
        json={"arena_id": arena.json()["id"], "preset_id": "classic", "overrides": {}},
    )
    assert game.status_code == 200, game.text
    return game.json()["id"]


@pytest.mark.parametrize(
    ("radius", "status"),
    [
        (29, 422),
        (30, 200),
        (2000, 200),
        (2001, 200),
        (3000, 200),
        (3001, 422),
        ("abc", 422),
        (None, 422),
    ],
)
def test_lobby_circle_resize_enforces_the_cap(
    client: TestClient, radius: object, status: int
) -> None:
    host = _auth(client)
    gid = _lobby(client, host)
    response = client.post(
        f"/v1/games/{gid}/arena", headers=_headers(host), json={"radius_m": radius}
    )
    assert response.status_code == status, response.text
    if status == 200:
        assert response.json()["arena"]["boundary_circle"]["radius_m"] == float(radius)


def test_three_km_arena_can_start_a_hunt_with_zone_shrink(client: TestClient) -> None:
    host = _auth(client)
    arena = client.post("/v1/arenas", headers=_headers(host), json=_arena_body(3000))
    assert arena.status_code == 200, arena.text
    game = client.post(
        "/v1/games",
        headers=_headers(host),
        json={
            "arena_id": arena.json()["id"],
            "preset_id": "classic",
            "overrides": {"zone_shrink": {"enabled": True, "min_radius_m": 500}},
        },
    )
    assert game.status_code == 200, game.text


def test_three_km_arena_zone_shrink_schedule_reaches_the_minimum() -> None:
    shrink = {"enabled": True, "every": 1, "shrink_to": 75, "min_radius_m": 500}
    session, _clock = make_session(overrides={"zone_shrink": shrink})
    arena = arena_from_dict(_arena_body(3000.0))
    session.state.arena = arena
    session.state.initial_radius_m = 3000.0

    radii = []
    for elapsed in range(0, 40 * 60, 60):
        session.state.game_elapsed_s = elapsed
        schedule = zone_shrink_schedule(session)
        if schedule is not None:
            radii.append(schedule["target_radius_m"])

    assert radii, "schedule never produced a target"
    assert radii[0] <= 3000.0
    assert min(radii) >= 500.0
    assert radii[-1] == 500.0


def test_three_km_containment_and_clip_stay_fast() -> None:
    """Containment at 3 km is a polygon test against a 64-point ring. Keep it cheap."""
    arena = arena_from_dict(_arena_body(3000.0))
    assert validate_arena(arena) == []

    started = time.perf_counter()
    clipped = clip_arena(arena)
    ring = circle_sample_ring(arena.boundary_circle.center, 3000.0, steps=64)
    for point in ring:
        local_xy(point, arena.boundary_circle.center)
    elapsed = time.perf_counter() - started

    assert len(clipped.boundary) == 64
    # Generous bound. This only guards against an accidental quadratic blowup.
    assert elapsed < 0.5
