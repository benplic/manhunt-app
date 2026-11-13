from uuid import uuid4

from tests.engine.helpers import make_session


def test_random_roles_honor_seeker_count_and_empty_input() -> None:
    session, _ = make_session(seed=99)
    ids = [uuid4() for _ in range(4)]
    for i, player_id in enumerate(ids):
        session.add_player(player_id, f"P{i}", is_host=i == 0)
    session.assign_roles_random(1)
    roles = [p.role for p in session.state.players.values()]
    assert roles.count("seeker") == 1
    assert roles.count("hider") == 3
    assert session.state.inputs[-1]["payload"] == {"seeker_count": 1}

    session.assign_roles_random(0)
    assert all(p.role == "hider" for p in session.state.players.values())

    session.assign_roles_random(90)
    assert all(p.role == "seeker" for p in session.state.players.values())

    empty, _ = make_session(seed=1)
    empty.assign_roles_random(2)
    assert empty.state.players == {}


def test_legacy_hider_count_input_still_deals_hiders() -> None:
    session, _ = make_session(seed=99)
    ids = [uuid4() for _ in range(4)]
    for i, player_id in enumerate(ids):
        session.add_player(player_id, f"P{i}", is_host=i == 0)
    session.assign_hiders_random(1)
    roles = [p.role for p in session.state.players.values()]
    assert roles.count("hider") == 1
    assert roles.count("seeker") == 3
    assert session.state.inputs[-1]["payload"] == {"hider_count": 1}
