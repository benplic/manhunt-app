from uuid import uuid4

from tests.engine.helpers import make_session


def test_random_roles_honor_hider_count_and_empty_input() -> None:
    session, _ = make_session(seed=99)
    ids = [uuid4() for _ in range(4)]
    for i, player_id in enumerate(ids):
        session.add_player(player_id, f"P{i}", is_host=i == 0)
    session.assign_roles_random(1)
    roles = [p.role for p in session.state.players.values()]
    assert roles.count("hider") == 1
    assert roles.count("seeker") == 3

    session.assign_roles_random(0)
    assert all(p.role == "seeker" for p in session.state.players.values())

    session.assign_roles_random(90)
    assert all(p.role == "hider" for p in session.state.players.values())

    empty, _ = make_session(seed=1)
    empty.assign_roles_random(2)
    assert empty.state.players == {}
