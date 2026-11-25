"""Display names with apostrophes, accents, and emoji survive create, join, view, and log."""

from __future__ import annotations

import json
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.auth.names import normalize_display_name
from app.engine.arena import arena_to_dict
from app.playtest_log import configure_playtest_log
from tests.engine.helpers import square

HOST_NAME = "Ryan O\u2019Donnell"  # typographic apostrophe, what iOS smart punctuation sends
GUEST_NAME = "Jos\u00e9 O'Neil \U0001f98a"  # accent, straight apostrophe, emoji


def _auth(client: TestClient, name: str) -> dict:
    response = client.post(
        "/v1/auth/dev",
        json={"display_name": name, "installation_id": str(uuid4()), "age": 18},
    )
    assert response.status_code == 200, response.text
    return response.json()


def _hdr(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def log_dir(tmp_path: Path):
    root = tmp_path / "playtest"
    configure_playtest_log(root)
    yield root
    configure_playtest_log(None)


def test_names_round_trip_through_create_join_view_and_log(
    client: TestClient, log_dir: Path
) -> None:
    host = _auth(client, HOST_NAME)
    guest = _auth(client, GUEST_NAME)
    assert host["user"]["display_name"] == HOST_NAME
    assert guest["user"]["display_name"] == GUEST_NAME

    arena = client.post(
        "/v1/arenas", json=arena_to_dict(square()), headers=_hdr(host["access_token"])
    )
    game = client.post(
        "/v1/games",
        json={"arena_id": arena.json()["id"], "preset_id": "classic", "overrides": {}},
        headers=_hdr(host["access_token"]),
    )
    assert game.status_code == 200, game.text
    game_id = game.json()["id"]
    joined = client.post(
        "/v1/games/join",
        json={"join_code": game.json()["join_code"]},
        headers=_hdr(guest["access_token"]),
    )
    assert joined.status_code == 200, joined.text

    view = client.get(f"/v1/games/{game_id}", headers=_hdr(guest["access_token"]))
    names = [p["display_name"] for p in view.json()["players"]]
    assert names == [HOST_NAME, GUEST_NAME]

    # Read bytes and decode explicitly: the platform default (cp1252 on Windows) is how a
    # correct UTF-8 file ends up looking corrupted in a viewer.
    raw = (log_dir / "games" / f"{game_id}.jsonl").read_bytes().decode("utf-8")
    logged = [json.loads(line) for line in raw.splitlines()]
    assert any(r.get("host_name") == HOST_NAME for r in logged if r["event"] == "game_created")
    # The file itself must show the real characters, not \uXXXX escapes, so a human
    # reading a playtest log sees the same name the players typed.
    assert HOST_NAME in raw
    assert "\\u2019" not in raw


def test_normalize_keeps_unicode_and_unifies_composed_forms() -> None:
    composed = "Jos\u00e9"
    decomposed = "Jose\u0301"
    assert normalize_display_name(f"  {composed}  ") == composed
    assert normalize_display_name(decomposed) == composed
    assert normalize_display_name(HOST_NAME) == HOST_NAME
    assert normalize_display_name("Zo\u00eb \U0001f98a") == "Zo\u00eb \U0001f98a"


def test_composed_and_decomposed_names_count_as_duplicates(client: TestClient) -> None:
    host = _auth(client, "Jos\u00e9")
    other = _auth(client, "Jose\u0301")
    arena = client.post(
        "/v1/arenas", json=arena_to_dict(square()), headers=_hdr(host["access_token"])
    )
    game = client.post(
        "/v1/games",
        json={"arena_id": arena.json()["id"], "preset_id": "classic", "overrides": {}},
        headers=_hdr(host["access_token"]),
    )
    joined = client.post(
        "/v1/games/join",
        json={"join_code": game.json()["join_code"]},
        headers=_hdr(other["access_token"]),
    )
    assert joined.status_code == 409
    assert joined.json()["error"]["code"] == "DISPLAY_NAME_TAKEN"
