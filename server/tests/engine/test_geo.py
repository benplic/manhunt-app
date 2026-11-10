from app.engine.arena import Arena, ArenaZone, CircleShape, PolygonShape, ZoneKind, validate_arena
from app.engine.geo import contains, distance_m, is_confidently_outside
from tests.engine.helpers import meters, square


def test_equator_thousandth_degree() -> None:
    distance = distance_m(
        __import__("app.engine.geo", fromlist=["GeoPoint"]).GeoPoint(0, 0),
        __import__("app.engine.geo", fromlist=["GeoPoint"]).GeoPoint(0.001, 0),
    )
    assert abs(distance - 111.32) < 0.05


def test_square_contains_center_and_boundary_but_not_the_bay() -> None:
    square_poly = [
        meters(0, 0),
        meters(200, 0),
        meters(200, 200),
        meters(0, 200),
    ]
    assert contains(meters(100, 100), square_poly)
    assert contains(meters(0, 0), square_poly)
    assert contains(meters(100, 0), square_poly)
    assert not contains(meters(100, -40), square_poly)

    concave = [
        meters(0, 0),
        meters(100, 0),
        meters(100, 20),
        meters(20, 20),
        meters(20, 80),
        meters(100, 80),
        meters(100, 100),
        meters(0, 100),
    ]
    assert contains(meters(10, 50), concave)
    assert not contains(meters(50, 50), concave)


def test_validator_rejects_bowtie_and_zones_that_leave() -> None:
    bowtie = square()
    bowtie.boundary = [meters(0, 0), meters(100, 100), meters(0, 100), meters(100, 0)]
    codes = {i.code for i in validate_arena(bowtie)}
    assert "self_intersection" in codes

    empty = square()
    empty.boundary = [meters(0, 0), meters(1, 0)]
    assert any(i.code == "play_area_too_small" for i in validate_arena(empty))

    stray = square()
    stray.zones = [
        ArenaZone(
            id=__import__("uuid").uuid4(),
            name="Shed",
            kind=ZoneKind.OUT_OF_BOUNDS,
            shape=PolygonShape(vertices=[meters(400, 400), meters(420, 400), meters(410, 420)]),
        )
    ]
    assert any(i.code == "outside_play_area" and i.name == "Shed" for i in validate_arena(stray))

    overhang = square()
    overhang.zones = [
        ArenaZone(
            id=__import__("uuid").uuid4(),
            name="Fountain",
            kind=ZoneKind.SAFE,
            shape=CircleShape(center=meters(100, 100), radius_m=500),
        )
    ]
    issues = validate_arena(overhang)
    assert any(i.code == "outside_play_area" and i.name == "Fountain" for i in issues)

    tiny = square()
    tiny.zones = [
        ArenaZone(
            id=__import__("uuid").uuid4(),
            name="Bench",
            kind=ZoneKind.SAFE,
            shape=CircleShape(center=meters(20, 20), radius_m=3),
        )
    ]
    assert validate_arena(tiny) == []


def test_out_of_bounds_waits_for_accuracy() -> None:
    boundary = square().boundary
    inside = meters(100, 100)
    barely_out = meters(100, -10)
    clearly_out = meters(100, -50)
    assert not is_confidently_outside(inside, 5, boundary, 5)
    assert not is_confidently_outside(barely_out, 10, boundary, 5)
    assert is_confidently_outside(clearly_out, 8, boundary, 5)
    assert not is_confidently_outside(clearly_out, 31, boundary, 5)


def test_overhanging_triangle_is_clipped_into_the_square() -> None:
    play = square().boundary
    subject = [meters(-20, 20), meters(40, 20), meters(10, 80)]
    from app.engine.geo import clip_polygon, contains

    clipped = clip_polygon(subject, play)
    assert clipped is not None
    assert all(contains(p, play) for p in clipped)


def test_zone_completely_outside_clips_to_nothing() -> None:
    from app.engine.geo import clip_polygon

    assert (
        clip_polygon([meters(400, 400), meters(420, 400), meters(410, 420)], square().boundary)
        is None
    )


def test_contained_circle_stays_a_circle_and_overhang_becomes_a_polygon() -> None:
    from uuid import uuid4

    from app.engine.arena import ArenaZone, CircleShape, PolygonShape, ZoneKind, clip_zone

    play = square().boundary
    inside = ArenaZone(
        id=uuid4(),
        name="Bench",
        kind=ZoneKind.SAFE,
        shape=CircleShape(center=meters(20, 20), radius_m=3),
    )
    clipped_in = clip_zone(inside, play)
    assert isinstance(clipped_in.shape, CircleShape)

    overhang = ArenaZone(
        id=uuid4(),
        name="Fountain",
        kind=ZoneKind.SAFE,
        shape=CircleShape(center=meters(100, 100), radius_m=500),
    )
    clipped_over = clip_zone(overhang, play)
    assert isinstance(clipped_over.shape, PolygonShape)
    from app.engine.geo import contains

    assert all(contains(p, play) for p in clipped_over.shape.vertices)


def test_arena_dataclass_roundtrip_name() -> None:
    arena = square()
    assert arena.name == "Square"
    assert isinstance(arena, Arena)
