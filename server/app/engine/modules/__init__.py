from app.engine.modules.base import BaseModule
from app.engine.modules.head_start import HeadStartModule
from app.engine.modules.reveal_fuzzy import RevealFuzzyModule
from app.engine.modules.roles import RolesModule
from app.engine.modules.signal_loss import SignalLossModule
from app.engine.modules.tag_policy import TagPolicyModule
from app.engine.modules.win import WinModule
from app.engine.modules.zone_policy import ZonePolicyModule

MODULE_TYPES: dict[str, type[BaseModule]] = {
    "roles": RolesModule,
    "head_start": HeadStartModule,
    "reveal_fuzzy": RevealFuzzyModule,
    "tag_policy": TagPolicyModule,
    "zone_policy": ZonePolicyModule,
    "signal_loss": SignalLossModule,
    "win": WinModule,
}

__all__ = ["MODULE_TYPES", "BaseModule"]
