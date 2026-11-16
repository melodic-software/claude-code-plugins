---
type: llm
focus: last_message
---

The repository is a Go module. Its recorded rule says no package outside billing imports billing/ledger, tests included. The user asked for the plan before any change.

PASS only if the plan's chosen mechanism for that rule is one the Go build itself enforces: making the ledger an internal package of billing (for example billing/internal/ledger), so the compiler refuses an import of it from outside billing. The plan may mention a separately run check (a lint rule, a script, an architecture-test or import-linting tool) only as a rejected or secondary option.

FAIL if the primary mechanism is a separately run check, a new linter or tool, or a script, or if the plan lists several mechanisms without choosing the build-time one.
