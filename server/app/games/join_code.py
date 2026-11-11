import random

ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
# Reserved for the solo sample lobby. A normal create must not take it.
SAMPLE_CODE = "PARK42"


def normalize(raw: str) -> str:
    return raw.strip().upper()


def is_valid(raw: str) -> bool:
    code = normalize(raw)
    return len(code) == 6 and all(ch in ALPHABET for ch in code)


def generate(rng: random.Random | None = None) -> str:
    rng = rng or random.SystemRandom()
    for _ in range(20):
        code = "".join(rng.choice(ALPHABET) for _ in range(6))
        if code != SAMPLE_CODE:
            return code
    return "HUNT42"
