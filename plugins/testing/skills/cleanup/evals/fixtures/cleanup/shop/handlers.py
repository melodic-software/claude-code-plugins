REGISTRY = {}


def register(name):
    def wrap(cls):
        REGISTRY[name] = cls
        return cls

    return wrap


@register("shipping")
class ShippingHandler:
    def fee(self, weight_kg):
        if weight_kg > 20:
            return 15
        return 5


def handle(kind, *args):
    return REGISTRY[kind]().fee(*args)
