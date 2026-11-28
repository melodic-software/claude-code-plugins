from importlib import import_module


def main(kind):
    module = import_module("dead_and_dynamic")
    return module.dispatch(kind, {"id": 1})
