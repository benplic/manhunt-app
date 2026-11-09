"""Typed error codes shared with the iOS client. Do not invent extra strings."""

from enum import StrEnum


class ErrorCode(StrEnum):
    UNAUTHORIZED = "UNAUTHORIZED"
    FORBIDDEN = "FORBIDDEN"
    NOT_HOST = "NOT_HOST"
    NOT_A_MEMBER = "NOT_A_MEMBER"
    VALIDATION_FAILED = "VALIDATION_FAILED"
    ARENA_INVALID = "ARENA_INVALID"
    ARENA_NOT_FOUND = "ARENA_NOT_FOUND"
    PRESET_NOT_FOUND = "PRESET_NOT_FOUND"
    GAME_NOT_FOUND = "GAME_NOT_FOUND"
    INVALID_JOIN_CODE = "INVALID_JOIN_CODE"
    GAME_FULL = "GAME_FULL"
    WRONG_PHASE = "WRONG_PHASE"
    NEED_BOTH_ROLES = "NEED_BOTH_ROLES"
    TOKEN_INVALID = "TOKEN_INVALID"
    TOKEN_EXPIRED = "TOKEN_EXPIRED"
    NOT_IN_PAIRING_RANGE = "NOT_IN_PAIRING_RANGE"
    NOT_IN_RANGE = "NOT_IN_RANGE"
    TARGET_NOT_ACTIVE = "TARGET_NOT_ACTIVE"
    TARGET_SHIELDED = "TARGET_SHIELDED"
    TARGET_IN_SAFE_ZONE = "TARGET_IN_SAFE_ZONE"
    WRONG_ROLE = "WRONG_ROLE"
    ELIMINATED = "ELIMINATED"
    INSUFFICIENT_POINTS = "INSUFFICIENT_POINTS"
    COOLING_DOWN = "COOLING_DOWN"
    NEEDS_TARGET = "NEEDS_TARGET"
    TARGET_OUTSIDE = "TARGET_OUTSIDE"
    RATE_LIMITED = "RATE_LIMITED"
    INTERNAL = "INTERNAL"


class ApiError(Exception):
    """Raised by HTTP handlers. Rendered as {"error":{code,message,details}}."""

    def __init__(
        self,
        code: ErrorCode,
        message: str,
        *,
        status_code: int = 400,
        details: dict | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.details = details or {}


class GameRuleError(Exception):
    """Raised by the engine when a player action violates a rule."""

    def __init__(self, code: ErrorCode, message: str | None = None) -> None:
        super().__init__(message or code.value)
        self.code = code
        self.message = message or code.value
