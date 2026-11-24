#!/usr/bin/env bash
# The cases of scripts/affected-tests.test.sh that must run against the LIVE
# repository: the derived shared-lib copy sets, real fan-outs, and the probes
# discovered in the tree. Each runs the selector over the whole tree, so no test
# selection can say when it must run; the lint-repo job of
# .github/workflows/pr-require-checks.yml runs this on every pull request.
#
# Usage: scripts/affected-tests-live.sh   (from anywhere; exit 0 all pass, 1 a failure)
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
cd "$REPO_ROOT" || exit 1

# Captured output is matched in-shell, never piped into an early-exit reader.
has_line() { [[ $'\n'$1$'\n' == *$'\n'"$2"$'\n'* ]]; }

select_for() {
  out="$(bash scripts/affected-tests.sh "$@" 2>/dev/null)"
  RC=$?
}

standards_src=docs/contracts/standards/README.md
[[ -f "$standards_src" ]] || standards_src=docs/conventions/standards/README.md
manifest=scripts/sync-shared-copies.sh
manifest_out="$(bash "$manifest" --print-manifest)"
for src in lib/hook-utils.sh lib/parse-concern-value.sh "$standards_src"; do
  derived="$(bash scripts/affected-tests.sh --print-fanout "$src" 2>/dev/null | sort)"
  expected="$(printf '%s\n' "$manifest_out" | awk -F '\t' -v s="$src" '$1=="src"{on=($2==s)} on && $1=="copy" && $2!=""{print $2}' | while IFS= read -r pat; do
    if [[ -e "$pat" ]]; then
      printf '%s\n' "$pat"
    else
      # shellcheck disable=SC2086 # a published entry may still be a glob.
      for m in $pat; do [[ -e "$m" ]] && printf '%s\n' "$m"; done
    fi
  done | sort)"
  if [[ -n "$derived" && "$derived" == "$expected" ]]; then
    ok "live derivation for $src matches $manifest ($(printf '%s\n' "$derived" | wc -l | tr -d ' ') copies)"
  else
    fail "live derivation drifted for $src: derived=[$derived] expected=[$expected]"
  fi
done

# Every live sync-*.sh (except the test helper) must implement the surface.
# The publisher's stdout is captured, then matched in-shell with no pipe: an
# early-exit reader on a pipe can kill a still-writing producer with SIGPIPE,
# which this script's pipefail then reports as a failed assertion.
live_missing=0
for manifest in "$REPO_ROOT"/scripts/sync-*.sh; do
  [[ "$manifest" == *.test.sh ]] && continue
  live_out="$(bash "$manifest" --print-manifest)" || {
    fail "live $manifest --print-manifest exited non-zero"
    live_missing=1
    continue
  }
  if [[ $'\n'$live_out != *$'\n'src$'\t'* ]]; then
    fail "live $manifest --print-manifest did not emit a src line"
    live_missing=1
  fi
done
if [[ "$live_missing" -eq 0 ]]; then
  ok "every live scripts/sync-*.sh implements --print-manifest"
fi

select_for lib/hook-utils.sh
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" lib/hook-utils.test.sh &&
  has_line "$out" plugins/guardrails/hooks/block-no-verify.test.sh &&
  has_line "$out" plugins/eol-normalizer/hooks/eol-normalizer.test.sh; then
  ok "live shared-lib change reaches suites in more than one carrying plugin"
else
  fail "live hook-utils fan-out (rc=$RC): $out"
fi

select_for "$standards_src"
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" plugins/planning/tests/standards-binding.test.sh &&
  has_line "$out" plugins/review/tests/standards-binding.test.sh; then
  ok "a structural basename that is also a sync src still fans out"
else
  fail "standards-contract fan-out (rc=$RC): $out"
fi

wf_yaml=""
while IFS= read -r c; do
  [[ "$c" == .github/workflows/* ]] && continue
  if ! git grep -q -F -- "${c##*/}" \
    -- '*.sh' '*.bash' '*.js' '*.mjs' '*.cjs' '*.py' '*.ps1' '*.psm1' 2>/dev/null; then
    wf_yaml="$c"
    break
  fi
done < <(git ls-files '.github/*.yaml' '.github/*.yml')
if [[ -z "$wf_yaml" ]]; then
  wf_yaml=.github/unreferenced-$$-$RANDOM.yaml
  : >"$wf_yaml"
  trap 'rm -f -- "$wf_yaml"' EXIT
fi
select_for "$wf_yaml"
if [[ "$RC" -eq 0 && -z "$out" ]]; then
  ok ".github YAML stays a recorded no-suite class via .github/*: $wf_yaml"
else
  fail ".github YAML should exit 0 with no suites (rc=$RC): $out"
fi

select_for plugins/source-control/skills/babysit-prs/scripts/babysit_lease.py
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" plugins/source-control/skills/babysit-prs/scripts/tests/test_babysit_lease.py; then
  ok "live: a .py whose only suite sits in tests/ maps to that suite"
else
  fail "live tests/ subdirectory suite (rc=$RC): $out"
fi

select_for plugins/eol-normalizer/hooks/eol-normalizer.sh
count="$(printf '%s\n' "$out" | grep -c '.')"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/eol-normalizer/hooks/eol-normalizer.test.sh && [[ "$count" -lt 10 ]]; then
  ok "live co-located change selects a narrow set ($count suites)"
else
  fail "live co-located selection too wide or wrong (rc=$RC, count=$count): $out"
fi

select_for plugins/disk-hygiene/lib/hook_telemetry.py
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/disk-hygiene/lib/test_hook_telemetry.py; then
  ok "live: a .py beside its test_<stem>.py is no longer UNMAPPED"
else
  fail "live python co-located selection (rc=$RC): $out"
fi

# --- LIVE repo: a real autonomy reference doc selects the contract suite -----
# The probe doc is discovered, never spelled: a basename written here would make
# this script name that file, and R3 would then cover it without R7. The suite
# path below IS spelled on purpose: renaming the suite fails this case instead
# of R7 silently selecting nothing.
# The assertion is on the R7 reason, not on bare selection: a live doc can also
# reach the suite through R4 fan-out (a hook naming it), which would pass without
# R7. The seed is walked first, so R7's reason is the one recorded.
# The exit status of this head pipe is never read, so its early exit is harmless.
live_ref="$(git ls-files 'plugins/autonomy/reference/*.md' | head -n 1)"
if [[ -z "$live_ref" ]]; then
  fail "LIVE R7: no tracked plugins/autonomy/reference/*.md to probe"
else
  out="$(bash scripts/affected-tests.sh --explain "$live_ref" 2>&1)"
  RC=$?
  if [[ "$RC" -eq 0 && "$out" == *"select: scripts/validate-plugin-contracts.test.sh  (path class:"* ]]; then
    ok "LIVE R7: $live_ref selects the plugin-contract suite through R7"
  else
    fail "LIVE R7: $live_ref did not select the plugin-contract suite through R7 (rc=$RC): $out"
  fi
fi

for probe in 'plugins/github/skills/advise/S*.md|plugins/github/github.test.sh' \
  'plugins/planning/skills/interview/S*.md|plugins/planning/tests/interview-defenses.test.sh'; do
  body="$(git ls-files "${probe%%|*}")"
  select_for "$body"
  if [[ -n "$body" && "$RC" -eq 0 ]] && has_line "$out" "${probe#*|}"; then
    ok "LIVE: $body selects ${probe#*|}"
  else
    fail "LIVE: '$body' did not select ${probe#*|} (rc=$RC): $out"
  fi
done

# --- LIVE repo: files a suite reads select that suite (#8410) ------------------
# The selection audit traced each suite reading these files while a one-file
# diff to the file did not select it: each suite reaches them through a path
# built from parts, a directory glob, or a launcher hooks.json names, so its
# `# test-scope:` header declares them (R8).
s_session=plugins/planning/shared/tests/test_session.py
s_dims=plugins/work-items/tests/set-dimensions.test.sh
gh_adapter=plugins/work-items/tools/work-item-tracker/adapters/github
tracker_lib=plugins/work-items/tools/work-item-tracker/lib
pl_fix=plugins/planning/shared/tests/fixtures
read_pairs=(
  "$s_session|plugins/planning/shared/schema/event.schema.json"
  "$s_session|plugins/planning/shared/schema/question-shape.schema.json"
  "$s_session|plugins/planning/surface/schema/event.schema.json"
  "$s_session|plugins/planning/surface/schema/ops.schema.json"
  "$s_session|plugins/planning/surface/schema/responses.schema.json"
  "$s_session|plugins/planning/surface/schema/visual.schema.json"
  "$s_dims|$gh_adapter/capabilities.json"
  "$s_dims|$gh_adapter/common.sh"
  "$s_dims|$gh_adapter/set-fields.sh"
  "$s_dims|$tracker_lib/id.sh"
  "$s_dims|$tracker_lib/lease.sh"
  "plugins/python-format/hooks/python-format.test.sh|plugins/python-format/lib/git-hooks/install.mjs"
  "plugins/python-format/hooks/python-format.test.sh|plugins/python-format/lib/prerequisites.mjs"
  "plugins/javascript-format/hooks/javascript-format-end-of-turn.test.sh|plugins/javascript-format/hooks/exec-bash.mjs"
  "plugins/code-metrics/skills/audit/scripts/audit-complexity.test.sh|plugins/code-metrics/scripts/yaml_subset.py"
  "plugins/instruction-placement/git-hooks/index-check.test.sh|plugins/instruction-placement/.claude-plugin/plugin.json"
  "lib/view-settings.test.sh|plugins/architecture/.claude-plugin/plugin.json"
  "scripts/check-data-root.test.sh|plugins/architecture/.claude-plugin/plugin.json"
)
for fixture in events-v1 invalid-device-scope-on-prototype invalid-reaction-agree \
  invalid-recommendation-on-choice state-full state-v7-live wire-heartbeat wire-presence; do
  read_pairs+=("$s_session|$pl_fix/$fixture.json")
done
for pair in "${read_pairs[@]}"; do
  suite="${pair%%|*}" file="${pair#*|}"
  select_for "$file"
  if [[ -e "$file" && "$RC" -eq 0 ]] && has_line "$out" "$suite"; then
    ok "LIVE: $file selects $suite"
  else
    fail "LIVE: $file did not select $suite (rc=$RC): $out"
  fi
done

test_harness::report
