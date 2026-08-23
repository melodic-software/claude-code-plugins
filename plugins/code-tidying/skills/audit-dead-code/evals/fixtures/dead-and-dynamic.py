"""Paired discrimination fixture for the vulture (Python) lane.

Holds one genuinely-dead symbol alongside two dynamic-reference traps. A static
detector reports all three identically, so adjudication -- not the detector --
is what separates them.
"""

import sys

ROUTES = {"beta": "handle_beta"}


def format_legacy_row(record):
    """Genuinely dead: no reference anywhere, static or dynamic."""
    return "|".join(str(value) for value in record)


def handle_alpha(payload):
    """Alive: reached only through the getattr dispatch below."""
    return {"kind": "alpha", "payload": payload}


def handle_beta(payload):
    """Alive: reached only through the string-keyed ROUTES table below."""
    return {"kind": "beta", "payload": payload}


def dispatch(kind, payload):
    """Resolve a handler by name at run time and call it."""
    name = ROUTES.get(kind, "handle_" + kind)
    handler = getattr(sys.modules[__name__], name, None)
    if handler is None:
        raise KeyError(kind)
    return handler(payload)
