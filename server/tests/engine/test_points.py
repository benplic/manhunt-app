import pytest

from app.errors import ErrorCode, GameRuleError
from tests.engine.helpers import meters, reading, two_player_hunt


def test_close_taunt_scores_more_than_a_distant_one() -> None:
    close_session, close_clock, close_hider, close_seeker = two_player_hunt()
    close_session.record_location(close_hider, reading(meters(100, 100), close_clock))
    close_session.record_location(close_seeker, reading(meters(110, 100), close_clock))
    close_session.taunt(close_hider)
    close_points = close_session.state.players[close_hider].points

    far_session, far_clock, far_hider, far_seeker = two_player_hunt()
    far_session.record_location(far_hider, reading(meters(20, 20), far_clock))
    far_session.record_location(far_seeker, reading(meters(180, 180), far_clock))
    far_session.taunt(far_hider)
    far_points = far_session.state.players[far_hider].points

    assert close_points > far_points


def test_taunt_disabled_rejects_and_awards_nothing() -> None:
    session, clock, hider, seeker = two_player_hunt({"points": {"taunt_enabled": False}})
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(110, 100), clock))
    with pytest.raises(GameRuleError) as exc:
        session.taunt(hider)
    assert exc.value.code == ErrorCode.WRONG_PHASE
    assert session.state.players[hider].points == 0
    assert session.state.players[hider].points_earned == 0


def test_second_taunt_inside_the_cooldown_is_refused() -> None:
    session, clock, hider, seeker = two_player_hunt({"points": {"taunt_cooldown": 45}})
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(110, 100), clock))
    session.taunt(hider)
    try:
        session.taunt(hider)
    except GameRuleError as exc:
        assert exc.code == ErrorCode.COOLING_DOWN
    else:
        raise AssertionError("A second taunt inside the cooldown should be refused")
    from tests.engine.helpers import run_for

    run_for(session, clock, 45)
    session.taunt(hider)


def test_seeker_gains_twenty_five_for_a_tag() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, 101), clock))
    from datetime import timedelta

    from app.engine.modules.base import TagClaim
    from app.engine.qr import make_qr_token

    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    before = session.state.players[seeker].points
    session.claim_tag(TagClaim(seeker, hider, qr_token=token))
    assert session.state.players[seeker].points == before + 25


def test_new_players_start_at_zero_and_spending_does_not_change_earned() -> None:
    from app.engine.modules.power_ups import CATALOG

    session, clock, hider, seeker = two_player_hunt()
    assert session.state.players[hider].points == 0
    assert session.state.players[hider].points_earned == 0
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, 100), clock))
    session.taunt(hider)
    earned = session.state.players[hider].points_earned
    balance = session.state.players[hider].points
    assert earned == balance
    assert earned >= 5
    cost = int(CATALOG["ghost"]["cost"])
    session.state.players[hider].points = cost
    session.purchase(hider, "ghost")
    assert session.state.players[hider].points == 0
    assert session.state.players[hider].points_earned == earned
