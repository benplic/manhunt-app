from __future__ import annotations

from typing import TYPE_CHECKING, ClassVar

from app.engine.modules.base import BaseModule

if TYPE_CHECKING:
    pass


class RolesModule(BaseModule):
    module_id: ClassVar[str] = "roles"
