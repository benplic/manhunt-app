"""Field-level AES-256-GCM for sensitive event payloads. Key lives in Key Vault."""

from __future__ import annotations

import json
import os
from base64 import b64decode, b64encode

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


class TrailKeyError(RuntimeError):
    """Raised when the trail key is missing or the wrong length."""


def load_trail_key(raw: str) -> bytes:
    """Accept 64 hex chars or 32 raw bytes encoded as latin-1 in tests."""
    text = raw.strip()
    if len(text) == 64:
        try:
            return bytes.fromhex(text)
        except ValueError as exc:
            raise TrailKeyError("MANHUNT_TRAIL_KEY must be 32-byte hex.") from exc
    data = text.encode("utf-8")
    if len(data) == 32:
        return data
    raise TrailKeyError("MANHUNT_TRAIL_KEY must be 32 bytes (64 hex chars).")


def encrypt_payload(key: bytes, payload: dict, key_id: str = "v1") -> dict:
    aes = AESGCM(key)
    nonce = os.urandom(12)
    plaintext = json.dumps(payload, separators=(",", ":")).encode()
    ciphertext = aes.encrypt(nonce, plaintext, None)
    return {
        "kid": key_id,
        "nonce": b64encode(nonce).decode(),
        "ct": b64encode(ciphertext).decode(),
    }


def decrypt_payload(key: bytes, blob: dict) -> dict:
    aes = AESGCM(key)
    nonce = b64decode(str(blob["nonce"]))
    ciphertext = b64decode(str(blob["ct"]))
    plaintext = aes.decrypt(nonce, ciphertext, None)
    return json.loads(plaintext.decode())
