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

# Captured output is matched in-shell, never piped into an early-exit reader.
has_line() { [[ $'\n'$1$'\n' == *$'\n'"$2"$'\n'* ]]; }
contains() { [[ $1 == *"$2"* ]]; }

contract_suite=scripts/validate-plugin-contracts.test.sh

# --- LIVE repo: the derived copy set equals the published manifest today ---
# The synthetic cases above prove the mechanism; this one proves it is still
# wired to THIS repository, which is what rots. The oracle is each script's
# --print-manifest surface (not a transcription of src=/copies=( scraping), so
# renaming those variables cannot make this assertion go green for the wrong
# reason.
for src in lib/hook-utils.sh lib/parse-concern-value.sh docs/conventions/standards/README.md; do
  derived="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh --print-fanout "$src" 2>/dev/null | sort)"
  manifest="scripts/sync-shared-copies.sh"
  expected="$(cd "$REPO_ROOT" && bash "$manifest" --print-manifest | awk -F '\t' -v s="$src" '$1=="src"{on=($2==s)} on && $1=="copy" && $2!=""{print $2}' | while IFS= read -r pat; do
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
  case "$manifest" in
  *.test.sh) continue ;;
  *) ;;
  esac
  live_out=""
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

# --- LIVE repo: a real shared-lib change reaches a real carrying plugin ----
out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh lib/hook-utils.sh 2>/dev/null)"
RC=$?
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" lib/hook-utils.test.sh &&
  has_line "$out" plugins/guardrails/hooks/block-no-verify.test.sh &&
  has_line "$out" plugins/eol-normalizer/hooks/eol-normalizer.test.sh; then
  ok "live shared-lib change reaches suites in more than one carrying plugin"
else
  fail "live hook-utils fan-out (rc=$RC): $out"
fi

# --- LIVE repo: a STRUCTURAL basename that is also a sync src -------------
# docs/conventions/standards/README.md is both. R3/R4 must ignore the basename
# (every plugin has a README.md, so the match carries no signal) while R5 must
# still fan the change out to the differently-named copies the manifest
# declares — plugins/*/reference/standards-contract.md — and on to the suites
# that bind against them. Neither the synthetic fixture nor the copy-set
# assertions above isolate that interaction.
out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh docs/conventions/standards/README.md 2>/dev/null)"
RC=$?
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" plugins/planning/tests/standards-binding.test.sh &&
  has_line "$out" plugins/review/tests/standards-binding.test.sh; then
  ok "a structural basename that is also a sync src still fans out"
else
  fail "standards-contract fan-out (rc=$RC): $out"
fi

# ... while YAML under .github/, which actionlint/zizmor/check-jsonschema DO
# read, stays covered by the .github/* entry. Without this, the cases above
# would pass just as well if someone deleted .github/* too — and since the
# probe here is itself a *.yaml, it is the direct evidence that dropping the
# bare *.yaml entry did not orphan the one YAML that had a real lane.
#
# Asserted as a SILENT no-suite exit (rc 0 AND an empty selection), not merely
# rc 0: a path that some suite happens to name is selected by R3 long before the
# no-suite list is consulted, which would pass a bare rc-0 check while proving
# nothing about .github/*. That is not hypothetical — .github/workflows/pr-require-checks.yml
# is named by two suites and reaches exit 0 through R3, so it cannot serve as
# this probe. Discovered by glob, never spelled: a path spelled here would make
# this script name it, and R3 would select through it the same way.
#
# The candidate is additionally FILTERED to one that no grepped-language file
# names at all, rather than assuming the sole `.github/*.yaml` qualifies: a
# file some suite reaches through R3 reaches exit 0 the way
# pr-require-checks.yml does, so it cannot serve as this probe either.
#
# The filter is an INDEPENDENT oracle (a direct git grep for the basename), not
# a call to affected-tests.sh: picking the probe with the tool under test would
# make the assertion below tautological. One incoming reference anywhere is
# enough to disqualify a candidate, because R3's first level would then have
# somewhere to go.
mapfile -t wf_candidates < <(cd "$REPO_ROOT" && git ls-files '.github/*.yaml' '.github/*.yml')
wf_yaml=()
for c in ${wf_candidates[@]+"${wf_candidates[@]}"}; do
  # scripts/workflow-self-paths.test.sh declares `.github/workflows/*` (R8), so
  # a workflow file selects that suite and cannot be the probe.
  [[ "$c" == .github/workflows/* ]] && continue
  if ! (cd "$REPO_ROOT" && git grep -q -F -- "${c##*/}" \
    -- '*.sh' '*.bash' '*.js' '*.mjs' '*.cjs' '*.py' '*.ps1' '*.psm1') 2>/dev/null; then
    wf_yaml=("$c")
    break
  fi
done
if [[ ${#wf_yaml[@]} -eq 0 ]]; then
  fail "no unreferenced .github YAML found to probe — the case below would be vacuous"
fi
for y in ${wf_yaml[@]+"${wf_yaml[@]}"}; do
  out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh "$y" 2>/dev/null)"
  RC=$?
  if [[ "$RC" -eq 0 && -z "$out" ]]; then
    ok ".github YAML stays a recorded no-suite class via .github/*: $y"
  else
    fail ".github YAML should exit 0 with no suites (rc=$RC): $out"
  fi
done

# --- LIVE repo: the false coverage that masked a real suite ----------------
# babysit_lease.py's suite is scripts/tests/test_babysit_lease.py, and nothing
# in the corpus spells that filename: every consumer says `import
# babysit_lease`. Under the old substring lookup the file still came back
# MAPPED, at exit 0, with five suites — none of them its own — purely because
# `babysit_lease.py` is a substring of `manage_babysit_lease.py`. That is the
# masked-zero-coverage shape the boundary rule exists to expose, and exposing it
# is only half the fix: the co-located rule then has to find the real suite by
# path, or a covered file reports UNMAPPED.
out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh plugins/source-control/skills/babysit-prs/scripts/babysit_lease.py 2>/dev/null)"
RC=$?
if [[ "$RC" -eq 0 ]] &&
  has_line "$out" plugins/source-control/skills/babysit-prs/scripts/tests/test_babysit_lease.py; then
  ok "live: a .py whose only suite sits in tests/ maps to that suite"
else
  fail "live tests/ subdirectory suite (rc=$RC): $out"
fi

# --- LIVE repo: a co-located change stays narrow ---------------------------
out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh plugins/eol-normalizer/hooks/eol-normalizer.sh 2>/dev/null)"
RC=$?
count="$(printf '%s\n' "$out" | grep -c '.')"
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/eol-normalizer/hooks/eol-normalizer.test.sh && [[ "$count" -lt 10 ]]; then
  ok "live co-located change selects a narrow set ($count suites)"
else
  fail "live co-located selection too wide or wrong (rc=$RC, count=$count): $out"
fi

# --- LIVE repo: the false-UNMAPPED regression this all exists to fix -------
# hook_telemetry.py sits directly beside test_hook_telemetry.py and was still
# reported UNMAPPED. Asserted against the LIVE repo, not a fixture: the point is
# that the tool tracks THIS corpus's real conventions.
out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh plugins/disk-hygiene/lib/hook_telemetry.py 2>/dev/null)"
RC=$?
if [[ "$RC" -eq 0 ]] && has_line "$out" plugins/disk-hygiene/lib/test_hook_telemetry.py; then
  ok "live: a .py beside its test_<stem>.py is no longer UNMAPPED"
else
  fail "live python co-located selection (rc=$RC): $out"
fi

# --- LIVE repo: a real autonomy reference doc selects the contract suite -----
# The probe doc is discovered, never spelled: a basename written here would make
# this script name that file, and R3 would then cover it without R7. The suite
# path above IS spelled on purpose: renaming the suite fails this case instead
# of R7 silently selecting nothing.
# The assertion is on the R7 reason, not on bare selection: a live doc can also
# reach the suite through R4 fan-out (a hook naming it), which would pass without
# R7. The seed is walked first, so R7's reason is the one recorded.
# The exit status of this head pipe is never read, so its early exit is harmless.
live_ref="$(cd "$REPO_ROOT" && git ls-files 'plugins/autonomy/reference/*.md' | head -n 1)"
if [[ -z "$live_ref" ]]; then
  fail "LIVE R7: no tracked plugins/autonomy/reference/*.md to probe"
else
  out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh --explain "$live_ref" 2>&1)"
  RC=$?
  if [[ "$RC" -eq 0 ]] && contains "$out" "select: $contract_suite  (path class:"; then
    ok "LIVE R7: $live_ref selects the plugin-contract suite through R7"
  else
    fail "LIVE R7: $live_ref did not select the plugin-contract suite through R7 (rc=$RC): $out"
  fi
fi

# --- LIVE repo: the two suite breaks only a full main run caught --------------
# Both were a skill body edit breaking a suite that never spells the body's
# path the plain way: one scans its plugin's markdown (R8 declares it), the
# other spells the body relative to its plugin (AMBIGUOUS NAMES resolves it).
# The probe bodies are discovered by glob, so renaming or deleting either fails
# this case.
for probe in 'plugins/github/skills/advise/S*.md|plugins/github/github.test.sh' \
  'plugins/planning/skills/interview/S*.md|plugins/planning/tests/interview-defenses.test.sh'; do
  body="$(cd "$REPO_ROOT" && git ls-files "${probe%%|*}")"
  out="$(cd "$REPO_ROOT" && bash scripts/affected-tests.sh "$body" 2>/dev/null)"
  RC=$?
  if [[ -n "$body" && "$RC" -eq 0 ]] && has_line "$out" "${probe#*|}"; then
    ok "LIVE: $body selects ${probe#*|}"
  else
    fail "LIVE: '$body' did not select ${probe#*|} (rc=$RC): $out"
  fi
done

test_harness::report
