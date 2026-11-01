#!/usr/bin/env bash
# The test-node steps whose suites print `::error` lines on purpose (fixtures
# that exercise a script's own failure messages) run them inside a
# `::stop-commands::<token>` block, so a green run raises no failure
# annotations. Each step's own `::error` lines stay outside the block. It also pins the
# test-bash and test-python Playwright browser cache steps.
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

# The Playwright browser cache in test-bash and test-python: test-bash restores it only on a
# leg that installs Chromium, both jobs restore under select-tests' one key, the install step
# records a download, and the save runs only on main after one.
if out=$("$reader" - "$WORKFLOW" <<'PY' 2>&1
import sys

import yaml

jobs = yaml.safe_load(open(sys.argv[1]))["jobs"]
errors = []
shared = "${{ env.BROWSER_CACHE_KEY }}"
entry = "${{ needs.select-tests.outputs.playwright_cache_key }}"
if "playwright_cache_key" not in jobs["select-tests"].get("outputs", {}):
    errors.append("select-tests has no playwright_cache_key output")


def step(job, name):
    found = [s for s in jobs[job]["steps"] if s.get("name") == name]
    if len(found) != 1:
        errors.append(f"{len(found)} {job} steps named {name!r}")
        return {}
    return found[0]


for job in ("test-bash", "test-python"):
    if jobs[job].get("env", {}).get("BROWSER_CACHE_KEY") != entry:
        errors.append(f"{job}'s env does not set BROWSER_CACHE_KEY to {entry}")
    restore = step(job, "Restore the Playwright browser")
    install = step(job, "Install locked plugin test toolchains")
    save = step(job, "Save the Playwright browser")
    if restore.get("with", {}).get("key") != shared:
        errors.append(f"{job} restores under {restore.get('with', {}).get('key')!r}, not {shared}")
    if install.get("id") != "toolchains" or 'echo "browser_downloaded=true" >> "$GITHUB_OUTPUT"' not in install.get("run", ""):
        errors.append(f"{job}'s install step is not id toolchains writing browser_downloaded")
    cond = save.get("if", "")
    if "github.ref == 'refs/heads/main'" not in cond or "steps.toolchains.outputs.browser_downloaded == 'true'" not in cond:
        errors.append(f"{job}'s save does not run only on main after a download: {cond!r}")
    if save.get("with", {}).get("key") != "${{ steps.playwright_cache.outputs.cache-primary-key }}":
        errors.append(f"{job}'s save does not reuse the restore's key")

cond = step("test-bash", "Restore the Playwright browser").get("if", "")
for need in ("browser", "animation"):
    if f"contains(fromJSON(env.LEG_PLAN)[env.LEG], '{need}')" not in cond:
        errors.append(f"test-bash's restore does not run on a leg needing {need}: {cond!r}")
sys.exit("\n".join(errors) or None)
PY
); then
  ok "test-bash and test-python cache Chromium under one key, saved only on main after a download"
else
  bad "test-bash and test-python cache Chromium under one key, saved only on main after a download" "$out"
fi

test_harness::report
