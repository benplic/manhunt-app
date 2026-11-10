"""Who may start a Nearby Interaction session with whom."""

from datetime import UTC, datetime
from uuid import uuid4

from app.engine.state import LocationReading, PlayerState
from app.engine.uwb import UWB_MAX_PEERS, select_uwb_peers
from tests.engine.helpers import meters


def _player(role: str, name: str, token: str | None, x: float, y: float, accuracy: float = 5):
    player = PlayerState(player_id=uuid4(), display_name=name, is_host=False, role=role)
    player.uwb_token = token
    player.location = LocationReading(
        lat=meters(x, y).lat,
        lon=meters(x, y).lon,
        accuracy_m=accuracy,
        recorded_at=datetime(2023, 11, 14, tzinfo=UTC),
    )
    return player


def test_uwb_peer_cap_is_five_until_measured_on_device() -> None:
    assert UWB_MAX_PEERS == 5


def test_forty_meters_apart_yields_no_peers() -> None:
    seeker = _player("seeker", "Jordan", "s" * 16, 0, 0)
    hider = _player("hider", "Riley", "h" * 16, 0, 40)
    assert select_uwb_peers([seeker, hider]) == {}


def test_ten_meters_opposite_roles_exchange_tokens() -> None:
    seeker = _player("seeker", "Jordan", "s" * 16, 0, 0)
    hider = _player("hider", "Riley", "h" * 16, 0, 10)
    selected = select_uwb_peers([seeker, hider])
    assert selected[seeker.player_id] == [
        {"player_id": str(hider.player_id), "display_name": "Riley", "token": "h" * 16}
    ]
    assert selected[hider.player_id][0]["token"] == "s" * 16
    assert "lat" not in selected[seeker.player_id][0]


def test_same_role_is_not_paired() -> None:
    one = _player("seeker", "Jordan", "s" * 16, 0, 0)
    two = _player("seeker", "Alex", "a" * 16, 0, 10)
    assert select_uwb_peers([one, two]) == {}


def test_accuracy_over_thirty_meters_is_ignored() -> None:
    seeker = _player("seeker", "Jordan", "s" * 16, 0, 0, accuracy=31)
    hider = _player("hider", "Riley", "h" * 16, 0, 10)
    assert select_uwb_peers([seeker, hider]) == {}


def test_cap_keeps_the_closest_opponents() -> None:
    seeker = _player("seeker", "Jordan", "s" * 16, 0, 0)
    near = _player("hider", "Near", "n" * 16, 5, 0)
    mid = _player("hider", "Mid", "m" * 16, 12, 0)
    far = _player("hider", "Far", "f" * 16, 20, 0)
    selected = select_uwb_peers([seeker, near, mid, far], cap=2)
    names = [peer["display_name"] for peer in selected[seeker.player_id]]
    assert names == ["Near", "Mid"]


def test_player_without_a_token_is_omitted() -> None:
    seeker = _player("seeker", "Jordan", None, 0, 0)
    hider = _player("hider", "Riley", "h" * 16, 0, 10)
    assert select_uwb_peers([seeker, hider]) == {}
