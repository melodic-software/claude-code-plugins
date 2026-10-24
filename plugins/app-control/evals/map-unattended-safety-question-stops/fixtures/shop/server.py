"""Fixture app for the map eval: route table only, never run."""

ROUTES = {
    "/": "catalog",
    "/cart": "cart",
    "/checkout": "checkout",
    "/signin": "redirect_to_identity_server",
    "/healthz": "health",
}
PORT = 8080
