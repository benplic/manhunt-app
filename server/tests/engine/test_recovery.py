import copy
import logging
from datetime import timedelta
from uuid import uuid4

import pytest

from app.engine.modules.base import TagClaim
from app.engine.qr import make_qr_token
from app.engine.recovery import _already_applied, rebuild_session
from app.errors import ErrorCode, GameRuleError
from tests.engine.helpers import make_session, meters, reading, two_player_hunt


def test_rebuild_replays_a_tag_to_the_same_result() -> None:
    session, clock, hider, seeker = two_player_hunt()
    session.record_location(hider, reading(meters(100, 100), clock))
    session.record_location(seeker, reading(meters(100, 101), clock))
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    session.claim_tag(TagClaim(seeker, hider, qr_token=token))
    rebuilt = rebuild_session(
        game_id=session.state.game_id,
        arena=session.state.arena,
        preset=session.state.preset,
        seed=session.state.seed,
        join_code=session.state.join_code,
        inputs=session.state.inputs,
        qr_key=session.qr_signing_key,
    )
    assert rebuilt.state.players[hider].status == "eliminated"
    assert rebuilt.state.players[seeker].points == session.state.players[seeker].points
    assert rebuilt.state.phase == "ended"


def _two_hider_hunt():
    """Seeker plus two hiders, no head start, so one tag does not end the game."""
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": False},
            "signal_loss": {"enabled": False},
            "reveal_fuzzy": {"interval": 6000},
        }
    )
    seeker, hider_a, hider_b = uuid4(), uuid4(), uuid4()
    session.add_player(seeker, "Jordan", is_host=True)
    session.add_player(hider_a, "Riley", is_host=False)
    session.add_player(hider_b, "Casey", is_host=False)
    session.set_role(seeker, "seeker")
    session.set_role(hider_a, "hider")
    session.set_role(hider_b, "hider")
    session.start()
    clock.advance(1)
    session.tick()
    return session, clock, seeker, hider_a, hider_b


def _rebuild(session, inputs):
    return rebuild_session(
        game_id=session.state.game_id,
        arena=session.state.arena,
        preset=session.state.preset,
        seed=session.state.seed,
        join_code=session.state.join_code,
        inputs=inputs,
        qr_key=session.qr_signing_key,
    )


def _tag(session, clock, seeker, hider) -> None:
    token = make_qr_token(
        game_id=session.state.game_id,
        hider_id=hider,
        expires_at=clock.now() + timedelta(seconds=30),
        key=session.qr_signing_key,
    )
    session.claim_tag(TagClaim(seeker, hider, qr_token=token))


def test_replay_treats_a_repeated_tag_as_a_noop(caplog: pytest.LogCaptureFixture) -> None:
    """PS95VZ shape: the log holds a tag whose target is already eliminated."""
    session, clock, seeker, hider_a, hider_b = _two_hider_hunt()
    _tag(session, clock, seeker, hider_a)
    inputs = copy.deepcopy(session.state.inputs)
    tag_input = next(item for item in inputs if item["kind"] == "tag")
    inputs.append(copy.deepcopy(tag_input))

    with caplog.at_level(logging.WARNING, logger="manhunt.recovery"):
        rebuilt = _rebuild(session, inputs)

    assert rebuilt.state.players[hider_a].status == "eliminated"
    assert rebuilt.state.players[hider_b].status == "active"
    assert rebuilt.state.phase == "active"
    assert "replay_input_skipped" in caplog.text
    assert "TARGET_NOT_ACTIVE" in caplog.text


def test_replay_skips_a_tag_when_replay_ticks_eliminated_the_target_first() -> None:
    """The likely PS95VZ mechanism: replay ticks run under a later clock than live did.

    Live, the tag happened one second in. In the log its timestamp is two minutes later,
    so replay's signal-loss penalty eliminates the hiders before the tag is applied.
    """
    session, clock = make_session(
        overrides={
            "head_start": {"enabled": False},
            "signal_loss": {
                "enabled": True,
                "silence": 10,
                "penalty": "eliminate",
                "penalty_after": 20,
            },
            "reveal_fuzzy": {"interval": 6000},
        }
    )
    seeker, hider_a, hider_b = uuid4(), uuid4(), uuid4()
    session.add_player(seeker, "Jordan", is_host=True)
    session.add_player(hider_a, "Riley", is_host=False)
    session.add_player(hider_b, "Casey", is_host=False)
    session.set_role(seeker, "seeker")
    session.set_role(hider_a, "hider")
    session.set_role(hider_b, "hider")
    session.start()
    for player in (seeker, hider_a, hider_b):
        session.record_location(player, reading(meters(100, 100), clock))
    clock.advance(1)
    session.tick()
    _tag(session, clock, seeker, hider_a)
    inputs = copy.deepcopy(session.state.inputs)
    tag_input = inputs[-1]
    assert tag_input["kind"] == "tag"
    tag_input["at"] = (clock.now() + timedelta(seconds=120)).isoformat()
    tag_input["game_elapsed_s"] = 60

    rebuilt = _rebuild(session, inputs)

    assert rebuilt.state.players[hider_a].status == "eliminated"
    assert rebuilt.state.players[hider_b].status == "eliminated"


def test_rebuilt_session_keeps_the_input_log_so_the_next_persist_cannot_wipe_it() -> None:
    session, clock, seeker, hider_a, _hider_b = _two_hider_hunt()
    _tag(session, clock, seeker, hider_a)
    inputs = copy.deepcopy(session.state.inputs)

    rebuilt = _rebuild(session, inputs)

    assert rebuilt.state.inputs == inputs
    # And a rebuild of the rebuilt log reaches the same state (stable across restarts).
    again = _rebuild(rebuilt, rebuilt.state.inputs)
    assert again.state.players[hider_a].status == "eliminated"


def test_replay_tolerance_requires_the_state_to_prove_it_was_already_applied() -> None:
    session, _clock, seeker, hider_a, _hider_b = _two_hider_hunt()
    tag = {"kind": "tag", "payload": {"hider_id": str(hider_a), "seeker_id": str(seeker)}}

    # Hider is still active and the game is live: a tag error here is a real divergence.
    assert not _already_applied(session, tag, ErrorCode.TARGET_NOT_ACTIVE)
    assert not _already_applied(session, tag, ErrorCode.WRONG_PHASE)
    # Unknown players and unlisted codes are never tolerated.
    missing = {"kind": "tag", "payload": {"hider_id": str(uuid4())}}
    assert not _already_applied(session, missing, ErrorCode.TARGET_NOT_ACTIVE)
    assert not _already_applied(session, tag, ErrorCode.TOKEN_INVALID)
    # A start while the game is running is already applied; pause/resume need their state.
    assert _already_applied(session, {"kind": "start"}, ErrorCode.WRONG_PHASE)
    assert not _already_applied(session, {"kind": "pause"}, ErrorCode.WRONG_PHASE)
    assert _already_applied(session, {"kind": "resume"}, ErrorCode.WRONG_PHASE)

    session.state.players[hider_a].status = "eliminated"
    assert _already_applied(session, tag, ErrorCode.TARGET_NOT_ACTIVE)


def test_replay_treats_a_repeated_state_transition_as_a_noop() -> None:
    session, clock, _seeker, _hider_a, _hider_b = _two_hider_hunt()
    session.pause()
    inputs = copy.deepcopy(session.state.inputs)
    inputs.append(copy.deepcopy(next(i for i in inputs if i["kind"] == "pause")))
    inputs.append(copy.deepcopy(next(i for i in inputs if i["kind"] == "start")))

    rebuilt = _rebuild(session, inputs)

    assert rebuilt.state.phase == "paused"


def test_replay_still_fails_on_errors_that_are_not_already_applied() -> None:
    session, _clock, _seeker, hider_a, _hider_b = _two_hider_hunt()
    inputs = copy.deepcopy(session.state.inputs)
    inputs.append(
        {
            "kind": "role_set",
            "at": inputs[-1]["at"],
            "game_elapsed_s": session.state.game_elapsed_s,
            "payload": {"player_id": str(hider_a), "role": "spectator"},
        }
    )

    with pytest.raises(GameRuleError) as caught:
        _rebuild(session, inputs)

    assert caught.value.code == ErrorCode.VALIDATION_FAILED


def test_live_path_still_rejects_a_tag_on_an_eliminated_hider() -> None:
    session, clock, seeker, hider_a, _hider_b = _two_hider_hunt()
    _tag(session, clock, seeker, hider_a)

    with pytest.raises(GameRuleError) as caught:
        _tag(session, clock, seeker, hider_a)

    assert caught.value.code == ErrorCode.TARGET_NOT_ACTIVE
