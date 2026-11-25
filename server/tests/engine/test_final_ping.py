"""A player's own "sent a last fix" alert goes to everyone else, never back to them."""

from __future__ import annotations

from uuid import UUID, uuid4

from fastapi.testclient import TestClient

from app.engine.events import visible_to
from app.engine.state import LocationReading
from app.realtime.manager import SessionManager
from tests.engine.helpers import make_session, meters
from tests.sim.test_full_games import _hdr, _open_game


class _RecordingSocket:
    def __init__(self) -> None:
        self.messages: list[dict] = []

    async def send_json(self, data: dict) -> None:
        self.messages.append(data)

    async def close(self, code: int = 1000) -> None:
        return None


def _final_fix(session, player_id: UUID) -> None:
    point = meters(100, 100)
    session.record_location(
        player_id,
        LocationReading(
            lat=point.lat,
            lon=point.lon,
            accuracy_m=5,
            recorded_at=session.clock.now(),
            flag="final",
        ),
    )


def _hunt():
    session, _clock = make_session(overrides={"head_start": {"enabled": False}})
    sender, other = uuid4(), uuid4()
    session.add_player(sender, "Riley", is_host=True)
    session.add_player(other, "Jordan", is_host=False)
    session.set_role(sender, "hider")
    session.set_role(other, "seeker")
    session.start()
    return session, sender, other


def test_final_ping_is_marked_hidden_from_its_sender() -> None:
    session, sender, other = _hunt()
    _final_fix(session, sender)

    event = next(e for e in session.state.event_log if e.type == "final_ping")

    assert event.player_id == sender
    assert event.hide_from_actor is True
    assert visible_to(event, sender) is False
    assert visible_to(event, other) is True


def test_other_events_stay_visible_to_the_player_they_are_about() -> None:
    session, sender, _other = _hunt()
    event = next(e for e in session.state.event_log if e.type == "player_joined")
    assert event.player_id == sender
    assert visible_to(event, sender) is True


def test_sensitive_events_are_never_visible() -> None:
    session, sender, other = _hunt()
    _final_fix(session, sender)
    location = next(e for e in session.state.event_log if e.type == "location")
    assert visible_to(location, sender) is False
    assert visible_to(location, other) is False


async def test_broadcast_skips_the_sender_but_not_everyone_else() -> None:
    session, sender, other = _hunt()
    manager = SessionManager()
    manager.sessions[session.state.game_id] = session
    mine, theirs = _RecordingSocket(), _RecordingSocket()
    manager.attach(session.state.game_id, sender, mine)  # type: ignore[arg-type]
    manager.attach(session.state.game_id, other, theirs)  # type: ignore[arg-type]
    session.drain_events()

    _final_fix(session, sender)
    await manager.broadcast(session.state.game_id)
    await manager.settle(session.state.game_id)

    def types(sock: _RecordingSocket) -> list[str]:
        return [m["data"]["type"] for m in sock.messages if m["type"] == "event"]

    assert "final_ping" not in types(mine)
    assert "final_ping" in types(theirs)


def _replayed_event_types(client: TestClient, gid: str, token: str) -> list[str]:
    """Reconnect with last_seq=0 and collect every replayed event type."""
    seen: list[str] = []
    with client.websocket_connect(f"/v1/games/{gid}/ws") as ws:
        ws.send_json({"type": "hello", "data": {"token": token, "last_seq": 0}})
        assert ws.receive_json()["type"] == "welcome"
        assert ws.receive_json()["type"] == "view"
        # The pong marks the end of the replay burst.
        ws.send_json({"type": "ping", "data": {}})
        while True:
            message = ws.receive_json()
            if message["type"] == "pong":
                break
            if message["type"] == "event":
                seen.append(message["data"]["type"])
    return seen


def test_reconnect_replay_and_timeline_also_hide_it_from_the_sender(client: TestClient) -> None:
    gid, _host, hider, seeker, hider_id, _seeker_id = _open_game(client)
    session = client.app.state.manager.get(UUID(gid))
    assert session is not None
    _final_fix(session, UUID(hider_id))

    assert "final_ping" in _replayed_event_types(client, gid, seeker["access_token"])
    assert "final_ping" not in _replayed_event_types(client, gid, hider["access_token"])

    sender_timeline = client.get(f"/v1/games/{gid}/events", headers=_hdr(hider["access_token"]))
    other_timeline = client.get(f"/v1/games/{gid}/events", headers=_hdr(seeker["access_token"]))
    assert "final_ping" not in [e["type"] for e in sender_timeline.json()["events"]]
    assert "final_ping" in [e["type"] for e in other_timeline.json()["events"]]
