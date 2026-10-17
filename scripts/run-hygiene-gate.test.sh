#!/usr/bin/env bash
# Self-test for scripts/run-hygiene-gate.sh, and for its wiring in the hygiene
# jobs of pr-require-checks.yml: every `run:` gate a job's CHECK_RESULTS feed
# reads names the wrapper as its shell under its own feed name, and every
# `uses:` gate is listed in that job's STEP_LOG_CHECKS. A gate added without
# either still gates, but its failure annotation would say only that it
# failed, which is the gap this wiring closes.
# test-scope: .github/workflows/pr-require-checks.yml scripts/aggregate-hygiene-results.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/run-hygiene-gate.sh"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$ROOT/scripts/lib/fixture-tree.sh"

scratch=""
fixture_tree::build scratch --label run-hygiene-gate

out_dir="$scratch/out"

# run_gate <check> <body>: runs <body> through the wrapper; sets RC and OUT.
run_gate() {
  printf '%s\n' "$2" >"$scratch/body.sh"
  OUT=$(HYGIENE_OUTPUT_DIR="$out_dir" bash "$SCRIPT" "$1" "$scratch/body.sh" 2>&1) && RC=0 || RC=$?
}

# A failing gate keeps its exit code, still prints to the step log, and its
# stdout and stderr both land in the capture file.
run_gate spoke-plugin-root $'echo "to stdout"\necho "to stderr" >&2\nexit 3'
if [[ "$RC" -eq 3 ]]; then ok 'a failing gate keeps its exit code'; else bad 'a failing gate keeps its exit code' "rc=$RC"; fi
if [[ "$OUT" == *'to stdout'* && "$OUT" == *'to stderr'* ]]; then
  ok 'the gate output still reaches the step log'
else
  bad 'the gate output still reaches the step log' "$OUT"
fi
if grep -qxF 'to stdout' "$out_dir/spoke-plugin-root.log" && grep -qxF 'to stderr' "$out_dir/spoke-plugin-root.log"; then
  ok 'stdout and stderr are captured under the check name'
else
  bad 'stdout and stderr are captured under the check name' "$(cat "$out_dir/spoke-plugin-root.log" 2>&1)"
fi

# The body runs under `bash -e`, as a step with no `shell:` does.
run_gate errexit $'false\necho "after false"'
if [[ "$RC" -ne 0 && "$OUT" != *'after false'* ]]; then
  ok 'the body runs with errexit, like the default step shell'
else
  bad 'the body runs with errexit, like the default step shell' "rc=$RC out=$OUT"
fi

run_gate passing 'echo fine'
if [[ "$RC" -eq 0 ]] && grep -qxF fine "$out_dir/passing.log"; then
  ok 'a passing gate exits 0 and is captured'
else
  bad 'a passing gate exits 0 and is captured' "rc=$RC"
fi

# A check name cannot reach outside the output directory.
run_gate '../escape' 'echo x'
if [[ "$RC" -eq 2 && ! -e "$scratch/escape.log" ]]; then
  ok 'a check name with a path separator is refused'
else
  bad 'a check name with a path separator is refused' "rc=$RC"
fi

# An unwritable output directory still runs the gate, uncaptured, with a warning.
: >"$scratch/not-a-dir"
printf 'echo ran; exit 4\n' >"$scratch/body.sh"
OUT=$(HYGIENE_OUTPUT_DIR="$scratch/not-a-dir/sub" bash "$SCRIPT" uncaptured "$scratch/body.sh" 2>&1) && RC=0 || RC=$?
if [[ "$RC" -eq 4 && "$OUT" == *ran* && "$OUT" == *'::warning title=uncaptured output not captured::'* ]]; then
  ok 'an unwritable output directory runs the gate uncaptured, with a warning'
else
  bad 'an unwritable output directory runs the gate uncaptured, with a warning' "rc=$RC out=$OUT"
fi

# With neither HYGIENE_OUTPUT_DIR nor RUNNER_TEMP set there is no shared-temp
# fallback: the gate runs uncaptured.
printf 'echo ran\n' >"$scratch/body.sh"
OUT=$(HYGIENE_OUTPUT_DIR='' RUNNER_TEMP='' TMPDIR="$scratch/tmp" bash "$SCRIPT" nodir "$scratch/body.sh" 2>&1) && RC=0 || RC=$?
if [[ "$RC" -eq 0 && "$OUT" == *ran* && "$OUT" == *'output not captured'* && ! -e "$scratch/tmp" ]]; then
  ok 'no configured output directory runs the gate uncaptured, with no temp fallback'
else
  bad 'no configured output directory runs the gate uncaptured, with no temp fallback' "rc=$RC out=$OUT"
fi

# The wiring in the live workflow.
reader=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import yaml' >/dev/null 2>&1; then
    reader=$candidate
    break
  fi
done
if [[ -z "$reader" ]]; then
  bad 'the workflow wiring check needs python3 with PyYAML (.github/requirements-ci.txt)'
else
  wiring=$("$reader" - "$WORKFLOW" <<'PY' 2>&1
import re
import sys

import yaml

doc = yaml.safe_load(open(sys.argv[1]))
row = re.compile(r"^\s*([A-Za-z0-9._-]+)=\$\{\{.*\bsteps\.([A-Za-z0-9_-]+)\.outcome\s*\}\}\s*$")  # portability-ok: Python re in a heredoc, not grep or sed
problems = []
jobs = 0
for job_id, job in doc["jobs"].items():
    steps = job.get("steps") or []
    aggregators = [s for s in steps if str(s.get("run", "")).strip() == "scripts/aggregate-hygiene-results.sh"]
    if not aggregators:
        continue
    jobs += 1
    env = aggregators[0].get("env") or {}
    feed = {}
    for line in str(env.get("CHECK_RESULTS", "")).splitlines():
        m = row.match(line)
        if m:
            feed[m.group(2)] = m.group(1)
    listed = set(str(env.get("STEP_LOG_CHECKS", "")).split())
    composites = set()
    for s in steps:
        check = feed.get(s.get("id"))
        if check is None:
            continue
        if "uses" in s:
            composites.add(check)
            if check not in listed:
                problems.append(f"{job_id}: uses-gate {check} is not in STEP_LOG_CHECKS")
        else:
            want = f"bash scripts/run-hygiene-gate.sh {check} {{0}}"
            if s.get("shell") != want:
                problems.append(f"{job_id}: run-gate {s.get('id')} has shell {s.get('shell')!r}, want {want!r}")
    for extra in sorted(listed - composites):
        problems.append(f"{job_id}: STEP_LOG_CHECKS names {extra}, which is not a uses-gate in its feed")
    # A composite gate's failure quotes the job's own check-run annotations.
    if listed:
        if str(env.get("CHECK_RUN_ID", "")).replace(" ", "") != "${{job.check_run_id}}":
            problems.append(f"{job_id}: the aggregator's CHECK_RUN_ID is not ${{{{ job.check_run_id }}}}")
        if str(env.get("GH_TOKEN", "")).replace(" ", "") != "${{github.token}}":
            problems.append(f"{job_id}: the aggregator's GH_TOKEN is not ${{{{ github.token }}}}")
        if (job.get("permissions") or {}).get("checks") != "read":
            problems.append(f"{job_id}: a job with composite gates needs permissions checks: read")
if jobs == 0:
    problems.append("no job runs scripts/aggregate-hygiene-results.sh")
print("\n".join(problems) if problems else f"wired: {jobs} job(s)")
sys.exit(1 if problems else 0)
PY
  ) && RC=0 || RC=$?
  if [[ "$RC" -eq 0 ]]; then
    ok "every hygiene gate is wired for its failure reason ($wiring)"
  else
    bad 'every hygiene gate is wired for its failure reason' "$wiring"
  fi
fi

# The aggregator's own contract runs here too, so a change to it is caught by
# this suite as well as by the CI self-test steps.
if OUT=$(bash "$ROOT/scripts/aggregate-hygiene-results.sh" --self-test 2>&1); then
  ok 'the aggregator self-test passes'
else
  bad 'the aggregator self-test passes' "$OUT"
fi

test_harness::report
