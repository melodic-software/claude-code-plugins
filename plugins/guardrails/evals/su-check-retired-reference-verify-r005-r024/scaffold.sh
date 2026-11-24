#!/usr/bin/env bash
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
printf '# Demo\n' >README.md
git add .
git commit -q -m "chore: init"
for d in .git/hooks .githooks; do
  mkdir -p "$d/pre-push.d" "$d/guardrails"
  printf 'guardrails/reference-verify.sh\n' >"$d/pre-push.d/guardrails.reference-verify"
  printf '#!/bin/sh\n# guardrails reference-verify sha256:%064d\nexit 0\n' 0 >"$d/guardrails/reference-verify.sh"
  printf '#!/usr/bin/env bash\n# Dispatcher: run several guardrails guards for ONE hook event\n' >"$d/guardrails/run-guards.sh"
  printf '# Abort boundary for the guardrails hooks\n' >"$d/guardrails/abort-boundary.sh"
  printf '# Shared hook utility library for this marketplace\n' >"$d/guardrails/hook-utils.sh"
  printf '#!/usr/bin/env bash\n# PostToolUse hook: verify CLI flags in newly-written files\n' >"$d/guardrails/cli-flag-verify.sh"
  printf '#!/usr/bin/env bash\n# verify skill references written to markdown\n' >"$d/guardrails/skill-reference-verify.sh"
  printf '#!/usr/bin/env bash\n# verify that a repo-relative path cited in newly-written markdown\n' >"$d/guardrails/stale-path-verify.sh"
  printf '#!/usr/bin/env bash\n# Verify whether a CLI flag exists\n' >"$d/guardrails/verify-cli-flag.sh"
  printf '# Shared by lib/verification/verify-cli-flag.sh and hooks/cli-flag-verify.sh\n' >"$d/guardrails/cli-flag-cache.sh"
  chmod +x "$d/guardrails/reference-verify.sh"
done
