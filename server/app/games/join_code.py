import random

ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


def normalize(raw: str) -> str:
    return raw.strip().upper()


def is_valid(raw: str) -> bool:
    code = normalize(raw)
    return len(code) == 6 and all(ch in ALPHABET for ch in code)


def generate(rng: random.Random | None = None) -> str:
    rng = rng or random.SystemRandom()
    return "".join(rng.choice(ALPHABET) for _ in range(6))
