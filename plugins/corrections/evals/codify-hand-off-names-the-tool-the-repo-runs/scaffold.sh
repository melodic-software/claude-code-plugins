#!/usr/bin/env bash
# A Python repository that already runs import-linter for its layer contracts, and a findings file
# whose one row breaks a layer boundary that no contract covers yet.
set -euo pipefail
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config commit.gpgsign false
mkdir -p src/app/web src/app/domain src/app/persistence
cat >pyproject.toml <<'EOF'
[project]
name = "app"
version = "0.1.0"

[tool.importlinter]
root_package = "app"

[[tool.importlinter.contracts]]
name = "Domain does not import web"
type = "forbidden"
source_modules = ["app.domain"]
forbidden_modules = ["app.web"]
EOF
printf 'lint:\n\tlint-imports\n' >Makefile
cat >src/app/persistence/orders.py <<'EOF'
def load(order_id):
    return {"id": order_id}
EOF
cat >src/app/web/orders.py <<'EOF'
from app.persistence.orders import load


def show(order_id):
    return load(order_id)
EOF
touch src/app/__init__.py src/app/web/__init__.py src/app/domain/__init__.py src/app/persistence/__init__.py
git add .
git commit -q -m "feat: order page"
cat >findings.md <<'EOF'
---
type: review-findings
date: 2026-01-01T00:00:00Z
branch: fixture
tier: medium
---

## Findings

| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |
|------|------|------------|----------|------------|---------|--------|
| 1 | IMPORTANT | high | src/app/web/orders.py:1 | architecture-guardian | The web layer imports the persistence package directly, skipping the domain layer. | Assert the layer boundary and route through the domain layer. |

## By dimension

### architecture

| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |
|------|------|------------|----------|------------|---------|--------|
| 1 | IMPORTANT | high | src/app/web/orders.py:1 | architecture-guardian | The web layer imports the persistence package directly, skipping the domain layer. | Assert the layer boundary and route through the domain layer. |

## Unparsed

None.

## Surfaces

Ran: architecture-guardian.
EOF
