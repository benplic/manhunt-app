"""Display name normalization and a small blocklist for beta."""

from __future__ import annotations

import re
import unicodedata

from app.errors import ApiError, ErrorCode

# Keep short. Lowercase tokens matched as whole words after normalize.
_BLOCKED = frozenset(
    {
        # Maintainers: add tokens people should not broadcast on the map.
        "nigger",
        "faggot",
        "retard",
    }
)

_SPACE = re.compile(r"\s+")


def normalize_display_name(name: str) -> str:
    # NFC so "e" + combining accent and the single "é" code point are the same name for
    # duplicate checks. Nothing is stripped: apostrophes, accents, and emoji stay intact.
    return _SPACE.sub(" ", unicodedata.normalize("NFC", name).strip())


def assert_display_name_allowed(name: str) -> None:
    cleaned = normalize_display_name(name)
    if not cleaned or len(cleaned) > 40:
        raise ApiError(ErrorCode.VALIDATION_FAILED, "Display name is invalid.", status_code=422)
    tokens = {t.lower() for t in re.split(r"[^a-zA-Z0-9]+", cleaned) if t}
    if tokens & _BLOCKED:
        raise ApiError(
            ErrorCode.NAME_BLOCKED,
            "That display name is not allowed.",
            status_code=422,
        )