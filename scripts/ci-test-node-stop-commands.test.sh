#!/usr/bin/env bash
# The test-node steps whose suites print `::error` lines on purpose (fixtures
# that exercise a script's own failure messages) run them inside a
# `::stop-commands::<token>` block, so a green run raises no failure
# annotations. Each step's own `::error` lines stay outside the block.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

reader=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import yaml' >/dev/null 2>&1; then
    reader=$candidate
    break
  fi
done
if [[ -z "$reader" ]]; then
  bad 'this check needs python3 with PyYAML (.github/requirements-ci.txt)'
  test_harness::report
  exit
fi

# check_step <name> <command>: the named test-node step's run body stops workflow
# commands with a random token before <command>, resumes after it, and has
# no `::error` line inside the block.
check_step() {
  local out
  if out=$("$reader" - "$WORKFLOW" "$1" "$2" <<'PY' 2>&1
import sys

import yaml

wf, name, command = sys.argv[1:]
steps = yaml.safe_load(open(wf))["jobs"]["test-node"]["steps"]
runs = [s.get("run", "") for s in steps if s.get("name") == name]
if len(runs) != 1:
    sys.exit(f"{len(runs)} test-node steps named {name!r}")
body = runs[0]
token = body.find("token=$(openssl rand -hex 16)")
stop = body.find('echo "::stop-commands::$token"')
call = body.find(command)
resume = body.find('echo "::$token::"')
if not (0 <= token < stop < call < resume):
    sys.exit(f"want a random token, then stop-commands, then {command!r}, then resume; got {token} {stop} {call} {resume}")
if "::error" in body[stop:resume]:
    sys.exit("an ::error line sits inside the stop-commands block")
PY
  ); then
    ok "$1 runs its suite with workflow commands stopped"
  else
    bad "$1 runs its suite with workflow commands stopped" "$out"
  fi
}

check_step 'Test resolve-config' 'npm test --prefix .github/actions/resolve-config'
check_step 'Test the other Node packages' 'scripts/run-outside-node-suites.sh --paths'

test_harness::report
