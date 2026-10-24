"""Fixture app for the map eval: route table only, never run."""

ROUTES = {
    "/": "catalog",
    "/cart": "cart",
    "/checkout": "checkout",
    "/account/reset-password": "reset_password",
    "/healthz": "health",
}
PORT = 8080
