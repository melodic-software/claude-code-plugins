#!/usr/bin/env bash
# Unit tests for check-silent-revert.sh.
#
# Every case builds a throwaway git repository and drives the real script, so
# the suite is hermetic: it needs no network, no GitHub API, and nothing about
# this repository's own history. That split is deliberate. These tests pin the
# MECHANICS -- attribution, per-culprit aggregation, the recency window, every
# disposition path, and the fail-closed exits. The claim that the shipped
# thresholds still catch the real #2691 merges is a different claim about
# different data, and it is pinned separately by
# `check-silent-revert.sh --verify-known-incidents` against
# scripts/silent-revert-incidents.txt, which the canary workflow runs with full
# history. Neither is allowed to substitute for the other, and neither is
# allowed to skip.
#
# Most cases override SILENT_REVERT_THRESHOLD so fixtures stay small and
# readable. `default_threshold_is_wired` deliberately does not, so a typo in the
# shipped default cannot hide behind an override in every single test.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-silent-revert.sh"
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

TMPDIRS=()
cleanup() {
  local d
  for d in ${TMPDIRS+"${TMPDIRS[@]}"}; do
    [[ -n "$d" ]] && rm -rf "$d"
  done
}
trap cleanup EXIT

# A repo laid out the way the incident was: a base file, then a "culprit" commit
# that adds a block of content, then optional filler commits, then whatever the
# test wants to do to that block.
#
# It must NEVER return an empty path. Callers invoke it as `repo="$(mk_repo)"`,
# so a `return 1` from inside the command substitution cannot abort the suite --
# the caller just gets "" and carries on. And "" is not inert: `git -C ""`
# operates on the CALLER's repository, so the very next `add -A` + `commit`
# stages and commits whatever the developer happened to be working on, authored
# as `test <t@t.test>`. That is not hypothetical -- it happened during #2837's
# development when mktemp transiently failed under load, and the resulting
# commit cannot be pushed here because it fails required_signatures.
#
# So a failure yields a path that does not exist. Every git call against it then
# fails loudly and the assertions go red, which is the correct fail-closed
# outcome for a harness that cannot build its fixture. The path is derived from
# SELF_DIR rather than written as a drive-root absolute like /nonexistent/...,
# which MSYS rewrites into the Git installation prefix on Windows.
MK_REPO_FAILED="$SELF_DIR/.mk-repo-failed-this-path-does-not-exist"
mk_repo() {
  local dir
  dir="$(mktemp -d)" || {
    printf '%s' "$MK_REPO_FAILED"
    return 0
  }
  TMPDIRS+=("$dir")
  git_init_test_repo "$dir" >/dev/null || {
    printf '%s' "$MK_REPO_FAILED"
    return 0
  }
  mkdir -p "$dir/scripts"
  cp "$SCRIPT" "$dir/scripts/check-silent-revert.sh"
  printf 'base line %s\n' $(seq 1 5) >"$dir/feature.txt"
  git_test_config "$dir" add -A >/dev/null
  git_test_config "$dir" commit -qm "base"
  printf '%s' "$dir"
}

# add_block <repo> <file> <count> <tag> -- the content a later commit will drop.
add_block() {
  local repo="$1" file="$2" count="$3" tag="$4" i
  for i in $(seq 1 "$count"); do
    printf 'the %s guard rejects a relocation outside the session root, case %s\n' \
      "$tag" "$i" >>"$repo/$file"
  done
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: add the $tag guard"
}

# drop_block <repo> <file> <tag> <commit-message> -- a squash carrying a tree
# from before the block existed, exactly as the incident's merges did.
drop_block() {
  local repo="$1" file="$2" tag="$3" msg="$4"
  grep -v "the $tag guard rejects" "$repo/$file" >"$repo/$file.tmp" || true
  mv "$repo/$file.tmp" "$repo/$file"
  printf 'unrelated work from the stale branch\n' >>"$repo/$file"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "$msg"
}

filler() {
  local repo="$1" n="$2" i
  for i in $(seq 1 "$n"); do
    printf 'filler %s\n' "$i" >>"$repo/other.txt"
    git_test_config "$repo" add -A >/dev/null
    git_test_config "$repo" commit -qm "chore: unrelated change $i"
  done
}

# run_canary <repo> <args...>
#
# Sets RC and OUT. Deliberately NOT a function whose output the caller captures
# with $(...): a command substitution runs in a subshell, so an exit status
# assigned to a global inside one is silently discarded and every assertion
# degrades to "rc=0". Callers therefore invoke it as a statement and read the
# globals afterwards. Env overrides go on the call as a prefix
# (`SILENT_REVERT_THRESHOLD=20 run_canary ...`), which bash applies to the
# child process the function launches.
RC=0
OUT=""
run_canary() {
  local repo="$1"
  shift
  local tmp
  tmp="$(mktemp)"
  (cd "$repo" && bash scripts/check-silent-revert.sh "$@") >"$tmp" 2>&1
  RC=$?
  OUT="$(cat "$tmp")"
  rm -f "$tmp"
}

# --------------------------------------------------------------------------
# 1. The incident shape itself.
# --------------------------------------------------------------------------
t_fires_on_silent_revert() {
  local repo out
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  filler "$repo" 2
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'SILENT REVERT SUSPECTED'; then
    ok "fires when a merge drops a block a recent commit had added"
  else
    fail "expected a finding (rc=1), got rc=$RC: $out"
  fi
}

# Requirement 4: a finding that only says "something changed" is useless. It has
# to name what vanished, which commit removed it, and which commit added it.
t_finding_is_actionable() {
  local repo out culprit remover
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  culprit="$(git -C "$repo" rev-parse --short=9 HEAD)"
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  remover="$(git -C "$repo" rev-parse --short=9 HEAD)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"

  local missing=""
  printf '%s' "$out" | grep -q "$culprit" || missing="$missing adding-commit"
  printf '%s' "$out" | grep -q "$remover" || missing="$missing removing-commit"
  printf '%s' "$out" | grep -q 'feature.txt' || missing="$missing file-name"
  printf '%s' "$out" | grep -q 'the alpha guard rejects' || missing="$missing removed-content"
  if [[ -z "$missing" ]]; then
    ok "finding names the content, the remover, the adder, and the file"
  else
    fail "finding omitted:$missing -- $out"
  fi
}

# --------------------------------------------------------------------------
# 2. False-positive controls.
# --------------------------------------------------------------------------
t_quiet_below_threshold() {
  local repo out
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha "chore: trim (#99)"
  SILENT_REVERT_THRESHOLD=500 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "stays quiet when the removal is below the volume threshold"
  else
    fail "expected clean below threshold, got rc=$RC: $out"
  fi
}

t_quiet_outside_recency_window() {
  local repo out
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  filler "$repo" 6
  drop_block "$repo" feature.txt alpha "chore: remove old guard (#99)"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_WINDOW=3 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "stays quiet when the removed content is older than the recency window"
  else
    fail "expected clean outside window, got rc=$RC: $out"
  fi
}

# Per-culprit aggregation, not a repo-wide sum. Ordinary work deletes a few
# recent lines from several commits at once; summing them would re-admit exactly
# the routine case the volume threshold exists to exclude.
t_does_not_sum_across_culprits() {
  local repo out
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 18 alpha
  add_block "$repo" feature.txt 18 beta
  grep -v 'guard rejects' "$repo/feature.txt" >"$repo/f.tmp" || true
  mv "$repo/f.tmp" "$repo/feature.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "chore: tidy (#99)"
  SILENT_REVERT_THRESHOLD=25 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "does not sum unrelated culprits into one finding (36 lines, 18 each, threshold 25)"
  else
    fail "expected clean; culprits must be counted separately: $out"
  fi
}

# Renaming a file is not deleting its content. Without git's rename detection a
# `git mv` decomposes into delete + add, and every line of a moved file would be
# attributed as removed -- so relocating a large file a recent commit had added
# would fire. This repo restructures skills and docs constantly, which makes
# that a live false-positive class rather than a hypothetical one.
t_rename_is_not_a_removal() {
  local repo out
  repo="$(mk_repo)"
  add_block "$repo" moved.txt 60 alpha
  git_test_config "$repo" mv moved.txt relocated.txt >/dev/null
  git_test_config "$repo" commit -qm "refactor: relocate the guard (#99)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "renaming a file a recent commit added is not reported as a removal"
  else
    fail "a pure rename must not fire, rc=$RC: $out"
  fi
}

# --------------------------------------------------------------------------
# 3. Declared-intent forms. Constrained matching only.
# --------------------------------------------------------------------------
assert_declared() {
  local label="$1" msg="$2" expect_rc="$3"
  local repo out
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha "$msg"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq "$expect_rc" ]]; then
    ok "$label"
  else
    fail "$label: expected rc=$expect_rc, got rc=$RC: $out"
  fi
}

t_declared_forms() {
  assert_declared 'a Revert-quote subject silences the canary' \
    'Revert "feat: add the alpha guard"' 0
  assert_declared 'a "This reverts commit <sha>" line silences the canary' \
    "$(printf 'chore: back out the guard\n\nThis reverts commit 0123456789abcdef0123456789abcdef01234567.\n')" 0
  assert_declared 'an Intentional-removal trailer silences the canary' \
    "$(printf 'refactor: drop the alpha guard (#99)\n\nIntentional-removal: superseded by the shared guard in #100\n')" 0
}

# The Conventional-Commits revert type (#2837). This is the ONLY revert subject
# this repo's required PR-title gate admits, and squash_merge_commit_title:
# PR_TITLE puts the PR title on main verbatim -- so without these three forms a
# deliberate revert reaches main wearing a subject the detector cannot read.
t_conventional_revert_subject_is_declared() {
  assert_declared 'a bare "revert:" subject silences the canary' \
    'revert: remove the alpha guard (#99)' 0
  assert_declared 'a scoped "revert(scope):" subject silences the canary' \
    'revert(disk-hygiene): remove the alpha guard (#99)' 0
  assert_declared 'a breaking "revert!:" subject silences the canary' \
    'revert!: remove the alpha guard (#99)' 0
  assert_declared 'a scoped breaking "revert(scope)!:" subject silences the canary' \
    'revert(disk-hygiene)!: remove the alpha guard (#99)' 0
}

# The reason why matching is constrained rather than a substring search: a
# message that merely mentions reverting must NOT silence a real finding, or the
# false-positive fix becomes a false-negative hole. Both halves are covered --
# the body (the original case) and the SUBJECT, which is what the new
# Conventional-Commits form reads and therefore what a substring bug would
# widen. `revert` must be the type token at position zero, nothing else.
t_prose_mentioning_revert_still_fires() {
  assert_declared 'prose mentioning "revert" does not silence the canary' \
    "$(printf 'feat: unrelated feature (#99)\n\nThis does not revert anything; the guard work is untouched.\n')" 1
  assert_declared 'a subject merely containing "revert" does not silence the canary' \
    'feat: do not revert the alpha guard (#99)' 1
  assert_declared 'a subject whose type merely starts with "revert" does not silence the canary' \
    'reverted: drop the alpha guard (#99)' 1
  assert_declared 'an uppercase "Revert:" subject the title gate would reject does not silence the canary' \
    'Revert: drop the alpha guard (#99)' 1
  assert_declared 'a "revert:" with no description does not silence the canary' \
    'revert:' 1
}

# An empty trailer would be a blanket mute with no accountability.
t_empty_trailer_still_fires() {
  assert_declared 'an empty Intentional-removal trailer does not silence the canary' \
    "$(printf 'refactor: drop the guard (#99)\n\nIntentional-removal:\n')" 1
}

# --------------------------------------------------------------------------
# 4. Retrospective acknowledgment.
# --------------------------------------------------------------------------
t_acknowledged_commit_is_cleared() {
  local repo out sha
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  sha="$(git -C "$repo" rev-parse HEAD)"
  printf '# ack\n%s  reviewed: intentional\n' "$sha" >"$repo/scripts/ack.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_ACK=scripts/ack.txt \
    run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q 'reviewed and cleared'; then
    ok "a reviewed commit recorded in the acknowledgment file is cleared"
  else
    fail "expected the acknowledged commit to clear, rc=$RC: $out"
  fi
}

# Abbreviations are refused so one row can never widen to cover a commit nobody
# reviewed -- the difference between an audit trail and a mute button.
t_abbreviated_ack_does_not_clear() {
  local repo out sha
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  sha="$(git -C "$repo" rev-parse --short=9 HEAD)"
  printf '%s  reviewed: intentional\n' "$sha" >"$repo/scripts/ack.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_ACK=scripts/ack.txt \
    run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 1 ]]; then
    ok "an abbreviated sha in the acknowledgment file does not clear a finding"
  else
    fail "expected an abbreviated ack to be refused, rc=$RC: $out"
  fi
}

# --------------------------------------------------------------------------
# 5. Shipped defaults, range mode, whole-file removal, fail-closed exits.
# --------------------------------------------------------------------------
# No env override here on purpose: this is the only case that would catch a
# broken shipped default.
t_default_threshold_is_wired() {
  local repo out
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 260 alpha
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 1 ]]; then
    ok "the shipped default threshold fires on a 260-line drop"
  else
    fail "shipped default did not fire on 260 lines, rc=$RC: $out"
  fi
  # And the shipped default must not fire on a drop well under it.
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 60 beta
  drop_block "$repo" feature.txt beta "feat: unrelated feature (#98)"
  run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "the shipped default threshold stays quiet on a 60-line drop"
  else
    fail "shipped default fired on 60 lines, rc=$RC: $out"
  fi
}

t_range_mode_scans_every_commit() {
  local repo out base
  repo="$(mk_repo)"
  base="$(git -C "$repo" rev-parse HEAD)"
  add_block "$repo" feature.txt 40 alpha
  filler "$repo" 1
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" "$base..HEAD"
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'SILENT REVERT SUSPECTED'; then
    ok "range mode scans every commit in the push"
  else
    fail "expected range mode to find the revert, rc=$RC: $out"
  fi
}

t_whole_file_deletion_is_attributed() {
  local repo out
  repo="$(mk_repo)"
  printf 'the alpha guard rejects relocation, case %s\n' $(seq 1 40) >"$repo/guard.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: add the guard file"
  rm "$repo/guard.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: unrelated feature (#99)"
  SILENT_REVERT_THRESHOLD=20 run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'guard.txt'; then
    ok "a wholly deleted file is attributed like any other removal"
  else
    fail "expected the deleted file to be attributed, rc=$RC: $out"
  fi
}

# Fail-closed: an unresolvable range must exit 2 (cannot run), never 0 (clean).
# A canary that reports success when it could not see the history is the exact
# false-green this whole check exists to eliminate.
t_unresolvable_range_fails_closed() {
  local repo out
  repo="$(mk_repo)"
  run_canary "$repo" "deadbeef..HEAD"
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "an unresolvable range exits 2 (cannot run), never a quiet pass"
  else
    fail "expected rc=2 on an unresolvable range, got rc=$RC: $out"
  fi
  run_canary "$repo" "not-a-range"
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "a malformed range argument exits 2"
  else
    fail "expected rc=2 on a malformed range, got rc=$RC: $out"
  fi
  run_canary "$repo"
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "no arguments exits 2 with usage"
  else
    fail "expected rc=2 with no arguments, got rc=$RC: $out"
  fi
}

t_root_commit_is_handled() {
  local repo out
  repo="$(mk_repo)"
  run_canary "$repo" --commit HEAD
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q 'root commit'; then
    ok "a root commit is reported as having no parent, not crashed on"
  else
    fail "expected the root commit to be handled, rc=$RC: $out"
  fi
}

# An empty range is a real state (a push that fast-forwards nothing) and must be
# distinguishable from a failure.
t_empty_range_is_clean() {
  local repo out head
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 5 alpha
  head="$(git -C "$repo" rev-parse HEAD)"
  run_canary "$repo" "$head..$head"
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q 'no commits in range'; then
    ok "an empty range is clean and says so"
  else
    fail "expected an empty range to be clean, rc=$RC: $out"
  fi
}

# --------------------------------------------------------------------------
# 6. The incident-replay harness must itself fail when an expectation breaks.
# --------------------------------------------------------------------------
t_replay_fails_on_broken_expectation() {
  local repo out sha
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  sha="$(git -C "$repo" rev-parse HEAD)"

  printf '# fixture\nfires %s a real drop\n' "$sha" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 0 ]]; then
    ok "replay passes when a recorded incident still fires"
  else
    fail "replay should have passed, rc=$RC: $out"
  fi

  # Same commit, wrong expectation: the harness must go red rather than
  # rubber-stamp whatever the detector currently happens to do.
  printf 'clean %s deliberately wrong\n' "$sha" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]]; then
    ok "replay fails when a recorded expectation no longer holds"
  else
    fail "replay should have failed on a wrong expectation, rc=$RC: $out"
  fi

  # An unreachable commit is a shallow clone, not a pass.
  printf 'fires 0123456789abcdef0123456789abcdef01234567 unreachable\n' \
    >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "replay exits 2 when a recorded commit is unreachable (shallow history)"
  else
    fail "expected rc=2 on an unreachable incident commit, rc=$RC: $out"
  fi
}

# The attribution field is the difference between "this commit still fires" and
# "this commit still fires FOR THE RECORDED REASON" (#2833). Exit status alone
# passes a row whose culprit or line count has silently moved, so each of those
# regressions is pinned here directly.
t_replay_asserts_the_recorded_attribution() {
  local repo out culprit other
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  culprit="$(git -C "$repo" rev-parse HEAD)"
  other="$(git -C "$repo" rev-parse HEAD~1)"
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  local sha
  sha="$(git -C "$repo" rev-parse HEAD)"

  # Baseline: the true culprit and the true count pass.
  printf 'fires %s [%s=40] a real drop\n' "$sha" "$culprit" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q 'attribution(s) reproduced exactly'; then
    ok "replay passes when the recorded culprit and line count both reproduce"
  else
    fail "replay should have passed on a correct attribution, rc=$RC: $out"
  fi

  # Right commit, right count, WRONG culprit. Exit status alone would pass this.
  printf 'fires %s [%s=40] wrong culprit\n' "$sha" "$other" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'fires, but NOT as recorded'; then
    ok "replay fails when the finding is attributed to a different culprit"
  else
    fail "a wrong recorded culprit must fail the replay, rc=$RC: $out"
  fi

  # Right commit, right culprit, WRONG count.
  printf 'fires %s [%s=39] wrong count\n' "$sha" "$culprit" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'fires, but NOT as recorded'; then
    ok "replay fails when the recorded line count no longer reproduces"
  else
    fail "a wrong recorded line count must fail the replay, rc=$RC: $out"
  fi

  # A recorded attribution the run does not produce at all -- the two-culprit
  # shape from cc58cbc53, where the surviving finding used to carry the row.
  printf 'fires %s [%s=40,%s=301] one attribution never reproduces\n' \
    "$sha" "$culprit" "$other" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'fires, but NOT as recorded'; then
    ok "replay fails when one of two recorded attributions stops reproducing"
  else
    fail "a missing recorded attribution must fail the replay, rc=$RC: $out"
  fi

  # A malformed field must be exit 2 (cannot run), never a FAIL and never a
  # pass: an expectation silently misread is the same false green the canary
  # exists to remove.
  local bad
  # The last two shapes have no closing bracket. They matter most: a leading `[`
  # that is never closed used to fail the field-detection glob outright, so the
  # remainder became free-text note and the row fell back to passing on exit
  # status alone -- reintroducing the pre-#2833 gap by the one route nobody
  # would think to look at. Raised on #2843 by two independent review lanes.
  for bad in "[${culprit:0:9}=40]" "[$culprit=many]" "[$culprit]" "[]" \
    "[$culprit=40" "["; do
    printf 'fires %s %s malformed\n' "$sha" "$bad" >"$repo/scripts/inc.txt"
    SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
      run_canary "$repo" --verify-known-incidents
    out="$OUT"
    if [[ "$RC" -eq 2 ]]; then
      ok "a malformed attribution field '$bad' exits 2 rather than passing or failing"
    else
      fail "expected rc=2 on malformed attribution '$bad', got rc=$RC: $out"
    fi
  done

  # An attribution on a `clean` row is nonsense -- clean rows have no findings.
  printf 'clean %s [%s=40] attribution on a clean row\n' "$sha" "$culprit" \
    >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "an attribution recorded on a 'clean' row exits 2"
  else
    fail "expected rc=2 for an attribution on a clean row, got rc=$RC: $out"
  fi

  # And a `fires` row with no attribution keeps working -- the field is optional
  # so a row can be pinned before its attribution has been measured.
  printf 'fires %s no attribution recorded\n' "$sha" >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q 'fires as recorded'; then
    ok "a fires row with no attribution field still replays on exit status alone"
  else
    fail "an attribution-less row must still work, rc=$RC: $out"
  fi
}

# The shipped data files must parse and be non-empty, so a truncated or
# malformed file cannot quietly turn the replay into a no-op.
t_shipped_data_files_are_wellformed() {
  local inc="$SELF_DIR/silent-revert-incidents.txt"
  local ack="$SELF_DIR/silent-revert-acknowledged.txt"
  local bad=0 n

  if [[ ! -f "$inc" ]]; then
    fail "missing $inc"
    return
  fi
  n="$(grep -cE '^(fires|clean)[[:space:]]+[0-9a-f]{40}[[:space:]]' "$inc")"
  [[ "$n" -ge 2 ]] || bad=1
  # Anything non-blank, non-comment must match the row grammar.
  grep -vE '^[[:space:]]*(#|$)' "$inc" |
    grep -qvE '^(fires|clean)[[:space:]]+[0-9a-f]{40}[[:space:]]' && bad=1
  if [[ "$bad" -eq 0 ]]; then
    ok "silent-revert-incidents.txt is well-formed with $n pinned rows"
  else
    fail "silent-revert-incidents.txt is malformed or has too few rows (n=$n)"
  fi

  # The attribution field is optional in the grammar, so nothing above would
  # notice a shipped `fires` row that quietly lost one and fell back to
  # asserting exit status alone -- which is exactly the weakness #2833 closed.
  # Every shipped `fires` row must carry a well-formed one.
  local fires_rows
  fires_rows="$(grep -cE '^fires[[:space:]]' "$inc")"
  bad=0
  [[ "$fires_rows" -ge 1 ]] || bad=1
  grep -E '^fires[[:space:]]' "$inc" |
    grep -qvE '^fires[[:space:]]+[0-9a-f]{40}[[:space:]]+\[[0-9a-f]{40}=[0-9]+(,[0-9a-f]{40}=[0-9]+)*\][[:space:]]' &&
    bad=1
  if [[ "$bad" -eq 0 ]]; then
    ok "every shipped fires row carries a well-formed attribution field ($fires_rows rows)"
  else
    fail "a shipped fires row is missing or has a malformed [<sha>=<lines>] attribution field"
  fi

  bad=0
  if [[ -f "$ack" ]]; then
    grep -vE '^[[:space:]]*(#|$)' "$ack" |
      grep -qvE '^[0-9a-f]{40}[[:space:]]+[^[:space:]]' && bad=1
    if [[ "$bad" -eq 0 ]]; then
      ok "silent-revert-acknowledged.txt rows are full shas with a recorded reason"
    else
      fail "silent-revert-acknowledged.txt has a row that is not <full-sha> <reason>"
    fi
  fi
}

t_fires_on_silent_revert
t_finding_is_actionable
t_quiet_below_threshold
t_quiet_outside_recency_window
t_does_not_sum_across_culprits
t_rename_is_not_a_removal
t_declared_forms
t_conventional_revert_subject_is_declared
t_prose_mentioning_revert_still_fires
t_empty_trailer_still_fires
t_acknowledged_commit_is_cleared
t_abbreviated_ack_does_not_clear
t_default_threshold_is_wired
t_range_mode_scans_every_commit
t_whole_file_deletion_is_attributed
t_unresolvable_range_fails_closed
t_root_commit_is_handled
t_empty_range_is_clean
t_replay_fails_on_broken_expectation
t_replay_asserts_the_recorded_attribution
t_shipped_data_files_are_wellformed

echo
echo "check-silent-revert.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
