from app.crypto import decrypt_payload, encrypt_payload, load_trail_key, open_inputs, seal_inputs


def test_round_trip_and_key_id() -> None:
    key = load_trail_key("ab" * 32)
    blob = encrypt_payload(key, {"lat": 40.66, "lon": -73.97}, key_id="v1")
    assert blob["kid"] == "v1"
    assert "lat" not in blob
    assert decrypt_payload(key, blob) == {"lat": 40.66, "lon": -73.97}


def test_replay_log_seals_coordinates() -> None:
    key = load_trail_key("cd" * 32)
    inputs = [{"kind": "location", "payload": {"lat": 40.66, "lon": -73.97}}]
    sealed = seal_inputs(key, inputs, "v1")
    assert isinstance(sealed, dict)
    assert "lat" not in sealed
    assert open_inputs(key, sealed) == inputs
    # Rows written before sealing are still a plain list.
    assert open_inputs(key, inputs) == inputs
