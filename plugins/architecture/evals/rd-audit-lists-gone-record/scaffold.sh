#!/usr/bin/env bash
# Two decision records. 0001 chose Redis for session storage; a later commit removed the Redis
# store and its dependency. 0002 (PostgreSQL for orders) still matches the code.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/adr src/session src/orders

cat >docs/adr/0001-keep-sessions-in-redis.md <<'MD'
# 1. Keep sessions in Redis

Status: accepted

Sessions must survive a web node restart, so they live in Redis.

## Considered options

- Signed cookies: the session payload outgrew the cookie size budget.
MD

cat >docs/adr/0002-store-orders-in-postgresql.md <<'MD'
# 2. Store orders in PostgreSQL

Status: accepted

Orders need multi-row transactions, so we store them in PostgreSQL.

## Considered options

- MongoDB: cross-document transactions added latency.
MD

cat >src/session/redis_store.py <<'PY'
import redis

client = redis.Redis(host="sessions")
PY

cat >src/orders/store.py <<'PY'
import psycopg

def connect():
    return psycopg.connect("dbname=orders")
PY

printf 'redis==5.0.4\npsycopg==3.2.1\n' >requirements.txt

git add -A
git commit -q -m "Sessions in Redis, orders in PostgreSQL"

git rm -q src/session/redis_store.py
mkdir -p src/session
cat >src/session/cookie_store.py <<'PY'
"""Sessions live in signed cookies."""


def load(cookie):
    return cookie
PY
printf 'psycopg==3.2.1\n' >requirements.txt
git add -A
git commit -q -m "Move sessions to signed cookies and drop Redis"
