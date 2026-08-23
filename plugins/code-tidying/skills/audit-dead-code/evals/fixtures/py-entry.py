"""Entry point that keeps dispatch() statically reachable.

Without a caller, every symbol in dead-and-dynamic.py reads as unused and the
capture carries no used-symbol control to discriminate against.
"""

from importlib import import_module


def main(kind):
    module = import_module("dead_and_dynamic")
    return module.dispatch(kind, {"id": 1})
