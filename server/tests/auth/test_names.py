import pytest

from app.auth.names import assert_display_name_allowed, normalize_display_name
from app.errors import ApiError, ErrorCode


def test_normalize_strips_and_collapses_spaces():
    assert normalize_display_name("  Casey   Lee ") == "Casey Lee"


def test_blocked_token_rejected():
    with pytest.raises(ApiError) as exc:
        assert_display_name_allowed("hello retard")
    assert exc.value.code == ErrorCode.NAME_BLOCKED