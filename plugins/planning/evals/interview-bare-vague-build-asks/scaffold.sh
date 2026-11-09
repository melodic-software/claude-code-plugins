#!/usr/bin/env bash
# Seeds a small order-tracking web app with users and orders and no notification code.
set -euo pipefail

mkdir -p src/app tests
cat >src/app/__init__.py <<'PY'
from flask import Flask

from .orders import bp as orders_bp


def create_app():
    app = Flask(__name__)
    app.register_blueprint(orders_bp)
    return app
PY
cat >src/app/models.py <<'PY'
from dataclasses import dataclass, field


@dataclass
class User:
    id: int
    email: str


@dataclass
class Order:
    id: int
    user_id: int
    status: str = "placed"
    items: list = field(default_factory=list)
PY
cat >src/app/orders.py <<'PY'
from flask import Blueprint, jsonify, request

from .models import Order

bp = Blueprint("orders", __name__)
ORDERS = {}


@bp.post("/orders")
def place_order():
    body = request.get_json()
    order = Order(id=len(ORDERS) + 1, user_id=body["user_id"], items=body.get("items", []))
    ORDERS[order.id] = order
    return jsonify(id=order.id, status=order.status), 201


@bp.post("/orders/<int:order_id>/ship")
def ship_order(order_id):
    ORDERS[order_id].status = "shipped"
    return jsonify(id=order_id, status="shipped")
PY
cat >tests/test_orders.py <<'PY'
from app import create_app


def test_place_order():
    client = create_app().test_client()
    response = client.post("/orders", json={"user_id": 1, "items": ["book"]})
    assert response.status_code == 201
PY
cat >README.md <<'MD'
# Order tracker

A small Flask service: users place orders and staff mark them shipped.
MD
