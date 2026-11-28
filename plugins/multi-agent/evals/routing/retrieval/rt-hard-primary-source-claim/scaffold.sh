#!/usr/bin/env bash
set -euo pipefail

mkdir -p docs/guides src/authz

cat >README.md <<'EOF'
# gatepass

`gatepass` enforces API key scope checks on audit and reporting endpoints.

## Scopes overview

Every `read:*` scope grants read-only access to its resource family. In particular, `read:audit` grants access to both `GET /v2/audit` and asynchronous export creation via `POST /v2/exports`.

See `docs/guides/scopes-cheatsheet.md` and `docs/faq.md` for quick reference, and `docs/architecture.md` for module layout.
EOF

cat >docs/guides/scopes-cheatsheet.md <<'EOF'
# Scopes Cheat Sheet

| Scope | Endpoints permitted | Notes |
| --- | --- | --- |
| `read:audit` | `GET /v2/audit`, `POST /v2/exports` | No additional scope is required for export jobs. |
| `export:create` | `POST /v2/exports` | Optional convenience scope for export-only workers. |
| `admin:audit` | All `/v2/audit` and `/v2/exports` routes | Full audit administration. |
EOF

cat >docs/faq.md <<'EOF'
# Frequently Asked Questions

## Can a `read:audit` key call `POST /v2/exports`?

Yes. `POST /v2/exports` accepts `read:audit` just like `GET /v2/audit`. Keys missing `read:audit` receive `ERR_SCOPE_MISSING`.
EOF

cat >docs/architecture.md <<'EOF'
# Architecture

Route-level authorization checks are enforced at runtime by the modules under `src/authz/`:

- `src/authz/scopes.py`: scope catalog.
- `src/authz/audit_reader.py`: `GET /v2/audit` route gate.
- `src/authz/export_gate.py`: `POST /v2/exports` route gate.
EOF

cat >src/authz/scopes.py <<'EOF'
SCOPES = {
    "read:audit": "Read audit event streams",
    "export:create": "Create asynchronous export jobs",
    "admin:audit": "Full audit administration",
}
EOF

cat >src/authz/audit_reader.py <<'EOF'
from dataclasses import dataclass


@dataclass(frozen=True)
class Decision:
    allowed: bool
    status: int
    error_code: str


def authorize_audit_read(scopes: set[str]) -> Decision:
    if "admin:audit" in scopes or "read:audit" in scopes:
        return Decision(allowed=True, status=200, error_code="none")
    return Decision(allowed=False, status=403, error_code="ERR_SCOPE_MISSING")
EOF

cat >src/authz/export_gate.py <<'EOF'
from dataclasses import dataclass


@dataclass(frozen=True)
class Decision:
    allowed: bool
    status: int
    error_code: str


def authorize_export_request(method: str, path: str, scopes: set[str]) -> Decision:
    if method != "POST" or path != "/v2/exports":
        return Decision(allowed=False, status=404, error_code="ERR_ROUTE_UNKNOWN")
    if "admin:audit" in scopes:
        return Decision(allowed=True, status=200, error_code="none")
    if "read:audit" not in scopes:
        return Decision(allowed=False, status=403, error_code="ERR_SCOPE_MISSING")
    if "export:create" not in scopes:
        return Decision(
            allowed=False,
            status=403,
            error_code="ERR_EXPORT_SCOPE_REQUIRED",
        )
    return Decision(allowed=True, status=200, error_code="none")
EOF
