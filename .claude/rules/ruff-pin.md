---
description: "Python linting runs through the pinned ruff wrapper, never a bare ruff on PATH"
paths:
  - "**/*.py"
---

# Ruff pin

Lint Python in this repo through `scripts/run-ruff.sh check <paths>` (the wrapper passes any
ruff arguments through and resolves the CI-pinned ruff version); a bare `ruff` on PATH can
disagree with CI in both directions, so never use it for verification here. Do not adopt a newer ruff's new rules in an
unrelated change; bumping the pin is a deliberate Dependabot change. Full rationale:
[`docs/CI-RUNNER-ROUTING.md`, "Local / workstation ruff"](../../docs/CI-RUNNER-ROUTING.md#local--workstation-ruff).
