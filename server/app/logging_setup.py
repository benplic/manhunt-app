"""JSON logs in azure/prod; otherwise a readable formatter. Never log coordinates or tokens."""

import logging
import sys


def configure_logging(env: str) -> None:
    handler = logging.StreamHandler(sys.stdout)
    if env in {"azure", "prod"}:
        fmt = '{"level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}'
    else:
        fmt = "%(levelname)s %(name)s %(message)s"
    handler.setFormatter(logging.Formatter(fmt))
    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(logging.INFO)
