from datetime import timedelta

from app.engine.modules.base import TagClaim
from app.engine.qr import make_qr_token
from app.engine.recovery import rebuild_session
from tests.engine.helpers import meters, reading, two_player_hunt


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
