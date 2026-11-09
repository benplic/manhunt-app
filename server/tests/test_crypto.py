from app.crypto import decrypt_payload, encrypt_payload, load_trail_key


def test_round_trip_and_key_id() -> None:
    key = load_trail_key("ab" * 32)
    blob = encrypt_payload(key, {"lat": 40.66, "lon": -73.97}, key_id="v1")
    assert blob["kid"] == "v1"
    assert "lat" not in blob
    assert decrypt_payload(key, blob) == {"lat": 40.66, "lon": -73.97}
