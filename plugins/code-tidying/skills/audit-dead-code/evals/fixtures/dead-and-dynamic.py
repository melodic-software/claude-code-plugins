import sys

ROUTES = {"beta": "handle_beta"}


def format_legacy_row(record):
    return "|".join(str(value) for value in record)


def handle_alpha(payload):
    return {"kind": "alpha", "payload": payload}


def handle_beta(payload):
    return {"kind": "beta", "payload": payload}


def dispatch(kind, payload):
    name = ROUTES.get(kind, "handle_" + kind)
    handler = getattr(sys.modules[__name__], name, None)
    if handler is None:
        raise KeyError(kind)
    return handler(payload)
