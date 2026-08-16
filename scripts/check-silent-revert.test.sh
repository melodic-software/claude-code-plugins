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
mk_repo() {
  local dir
  dir="$(mktemp -d)"
  TMPDIRS+=("$dir")
  git_init_test_repo "$dir" >/dev/null || return 1
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

# The reason why matching is constrained rather than a substring search: a body
# that merely mentions reverting must NOT silence a real finding, or the
# false-positive fix becomes a false-negative hole.
t_prose_mentioning_revert_still_fires() {
  assert_declared 'prose mentioning "revert" does not silence the canary' \
    "$(printf 'feat: unrelated feature (#99)\n\nThis does not revert anything; the guard work is untouched.\n')" 1
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

# --------------------------------------------------------------------------
# 7. The restoration assertion (#2855). A `fires` row proves the removal is
#    still DETECTED; these cases pin the other half -- that the content came
#    back -- and every way that assertion could go quietly green.
# --------------------------------------------------------------------------

# mk_restoration_repo <repo>
#
# Lays out the three shapes the assertion has to tell apart:
#   guarded.txt   holds the marker that IS restored
#   elsewhere.txt holds a string that exists ONLY outside its bound path
# and nothing anywhere holds the absent marker. Echoes the head sha.
mk_restoration_repo() {
  local repo="$1"
  printf 'the restored guard rejects a relocation\nRESTORED_MARKER_SENTINEL\n' \
    >"$repo/guarded.txt"
  printf 'SCOPED_ONLY_ELSEWHERE lives here and nowhere else\n' >"$repo/elsewhere.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "feat: the content an incident removed"
  git -C "$repo" rev-parse HEAD
}

t_restoration_reports_present_and_absent_markers() {
  local repo out sha
  repo="$(mk_repo)"
  sha="$(mk_restoration_repo "$repo")"

  # A restored marker passes.
  #
  # This case is also the regression pin for a defect that made the whole mode
  # inert in the other direction: the parsed marker view is delimited with an
  # ASCII Unit Separator, and reading its first field back with a bare `cut -f1`
  # (whose default delimiter is TAB) returned the WHOLE line, so the
  # "does this fires row have a marker" lookup could never match and every
  # corpus died with `carries no marker`. A green here proves the two views
  # still agree on their separator.
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q 'present: RESTORED_MARKER_SENTINEL'; then
    ok "a restored marker resolves and the assertion exits 0"
  else
    fail "a restored marker should have passed, rc=$RC: $out"
  fi

  # An absent marker is the finding this mode exists for.
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt NEVER_PRESENT_ANYWHERE\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'NOT RESTORED: NEVER_PRESENT_ANYWHERE'; then
    ok "an absent marker fails the restoration assertion and names the content"
  else
    fail "an absent marker must fail the assertion, rc=$RC: $out"
  fi

  # A dispositioned absent marker is a recorded decision, not a failure -- and
  # the reason has to be printed, or the disposition is a mute button.
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt [not-restored: superseded by the shared guard] NEVER_PRESENT_ANYWHERE\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 0 ]] &&
    printf '%s' "$out" | grep -q 'deliberately not restored: superseded by the shared guard'; then
    ok "a dispositioned absent marker passes and prints its recorded reason"
  else
    fail "a dispositioned absent marker should have passed, rc=$RC: $out"
  fi

  # THE path-scoping case. The string exists in the repo, just not in the file
  # it is bound to. A repo-wide grep reports this restored; that false green is
  # exactly what happened on the real corpus, where both #2828 markers also
  # occur in the engine script, its tests and CHANGELOG.md.
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt SCOPED_ONLY_ELSEWHERE\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 1 ]] && printf '%s' "$out" | grep -q 'NOT RESTORED: SCOPED_ONLY_ELSEWHERE'; then
    ok "a marker present only OUTSIDE its bound path still fails (path-scoped)"
  else
    fail "a marker matched outside its bound path is a false green, rc=$RC: $out"
  fi

  # Same corpus, resolved at an explicit rev rather than the working tree --
  # the form a reviewer replays an incident with.
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration "$sha"
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -qF "resolved at $sha"; then
    ok "the assertion resolves markers at an explicitly supplied rev"
  else
    fail "an explicit rev should have resolved, rc=$RC: $out"
  fi

  # A rev that does not exist is a shallow clone, not a pass.
  SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-restoration 0123456789abcdef0123456789abcdef01234567
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "an unresolvable rev exits 2 rather than reporting content it never read"
  else
    fail "expected rc=2 on an unresolvable rev, got rc=$RC: $out"
  fi
}

# Every way the corpus itself can be wrong must be exit 2 (cannot run), never a
# pass. A marker list that quietly covers nothing is the same false green as a
# detector that has stopped detecting.
t_restoration_refuses_a_malformed_corpus() {
  local repo out sha
  repo="$(mk_repo)"
  sha="$(mk_restoration_repo "$repo")"

  # THE central refusal: a `fires` row with no marker. Skipping it would let
  # this whole assertion be satisfied by pinning one historical incident while
  # covering no future one.
  printf 'fires %s a real drop with nothing recorded\n' "$sha" >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && printf '%s' "$out" | grep -q 'carries no marker'; then
    ok "a fires row carrying no marker exits 2 rather than passing vacuously"
  else
    fail "a marker-less fires row must exit 2, rc=$RC: $out"
  fi

  # A marker naming no `fires` row covers nothing; it is a typo, not coverage.
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
    printf 'marker 0123456789abcdef0123456789abcdef01234567 guarded.txt RESTORED_MARKER_SENTINEL\n'
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && printf '%s' "$out" | grep -q "names no recorded 'fires' incident"; then
    ok "a marker naming no fires row exits 2"
  else
    fail "an orphan marker row must exit 2, rc=$RC: $out"
  fi

  # Malformed marker rows. The last two are the ones that matter most: an
  # EMPTY disposition reason must be rejected rather than read as a mute, and
  # an unterminated `[` must not degrade back into ordinary marker text -- the
  # false green reached by the one route nobody would look at.
  local bad desc
  while read -r desc bad; do
    {
      printf 'fires %s a real drop\n' "$sha"
      printf 'marker %s %s\n' "$sha" "$bad"
    } >"$repo/scripts/inc.txt"
    SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
    out="$OUT"
    if [[ "$RC" -eq 2 ]]; then
      ok "a marker row with $desc exits 2"
    else
      fail "expected rc=2 for a marker row with $desc, got rc=$RC: $out"
    fi
  done <<'BAD_ROWS'
no-marker-text guarded.txt
a-disposition-where-the-path-should-be [not-restored: why] RESTORED_MARKER_SENTINEL
an-empty-disposition-reason guarded.txt [not-restored:] RESTORED_MARKER_SENTINEL
a-whitespace-only-disposition-reason guarded.txt [not-restored:   ] RESTORED_MARKER_SENTINEL
an-unknown-disposition-keyword guarded.txt [ignored: why] RESTORED_MARKER_SENTINEL
an-unterminated-disposition guarded.txt [not-restored: why RESTORED_MARKER_SENTINEL
BAD_ROWS

  # A corpus with no `fires` row at all must not report a serene pass. The
  # marker-per-fires-row rule only bites while a `fires` row exists, so removing
  # a row together with its markers is a mute button reached by deletion rather
  # than by editing.
  printf '# only comments here\n' >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && printf '%s' "$out" | grep -q "no 'fires' row"; then
    ok "a corpus with no fires row exits 2 rather than passing while covering nothing"
  else
    fail "an empty corpus must exit 2, rc=$RC: $out"
  fi
  printf 'clean %s only a clean row\n' "$sha" >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "a corpus of only 'clean' rows exits 2"
  else
    fail "a clean-only corpus must exit 2, rc=$RC: $out"
  fi

  # A well-formed sha nobody can resolve is a shallow clone or a typo. A matched
  # typo on a row AND its marker would otherwise assert content for an incident
  # that never happened.
  {
    printf 'fires 0123456789abcdef0123456789abcdef01234567 not a real commit\n'
    printf 'marker 0123456789abcdef0123456789abcdef01234567 guarded.txt RESTORED_MARKER_SENTINEL\n'
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && printf '%s' "$out" | grep -q 'unreachable'; then
    ok "a fires row naming an unreachable commit exits 2 even with a resolving marker"
  else
    fail "an unreachable incident commit must exit 2, rc=$RC: $out"
  fi

  # An abbreviated sha would let a marker widen to a commit nobody recorded --
  # the same discipline the acknowledgment file holds.
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "${sha:0:9}"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]]; then
    ok "an abbreviated sha on a marker row exits 2"
  else
    fail "expected rc=2 on an abbreviated marker sha, got rc=$RC: $out"
  fi

  # An unknown row kind is a corpus nobody can read, not a row to skip.
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
    printf 'markers %s guarded.txt typo in the row kind\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && printf '%s' "$out" | grep -q 'unknown row kind'; then
    ok "an unknown row kind exits 2"
  else
    fail "expected rc=2 on an unknown row kind, got rc=$RC: $out"
  fi
}

# A marker's path must resolve to exactly ONE FILE. Handing it to a pathspec
# instead lets a directory, a glob, a bare `.` or pathspec magic widen the
# search to a SUPERSET of the bound file -- and because every marker string is
# by construction also written in the corpus file itself, a widened path makes
# this whole assertion tautologically satisfiable by its own corpus. That is a
# false green reachable by a row that looks entirely reasonable, so each shape
# is pinned here rather than left to reviewer vigilance.
t_restoration_binds_a_marker_to_exactly_one_file() {
  local repo out sha widened
  repo="$(mk_repo)"
  sha="$(mk_restoration_repo "$repo")"

  # THE amplifier case, in its strongest form: the target content is nowhere in
  # the repo, but the marker text is sitting in the corpus file itself. A
  # pathspec of `.` used to report it restored.
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s . NEVER_PRESENT_ANYWHERE\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -ne 0 ]]; then
    ok "a marker bound to '.' cannot be satisfied by the corpus file itself"
  else
    fail "a '.' path let the corpus satisfy its own marker, rc=$RC: $out"
  fi

  # Every widening shape, at the working tree and at a rev. None may report the
  # marker present, because the content lives only in guarded.txt while the
  # marker is bound to something broader.
  for widened in "." ".." "*" "plugins" "" "scripts" ":/" ":(glob)**/*"; do
    [[ -n "$widened" ]] || continue
    {
      printf 'fires %s a real drop\n' "$sha"
      printf 'marker %s %s RESTORED_MARKER_SENTINEL\n' "$sha" "$widened"
    } >"$repo/scripts/inc.txt"
    SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
    out="$OUT"
    local wt_rc="$RC"
    SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration "$sha"
    if [[ "$wt_rc" -ne 0 ]] && [[ "$RC" -ne 0 ]]; then
      ok "a widened marker path '$widened' never reports the marker present"
    else
      fail "widened path '$widened' gave a false green (worktree rc=$wt_rc, rev rc=$RC): $out"
    fi
  done

  # A directory is a corpus error rather than a finding, and says so.
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s scripts RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 2 ]] && printf '%s' "$out" | grep -q 'bind a marker to exactly one file'; then
    ok "a marker path naming a directory exits 2 and names the fix"
  else
    fail "a directory marker path must exit 2, rc=$RC: $out"
  fi

  # Working-tree mode must stay REPO-SCOPED. Reading the filesystem directly
  # would let an untracked file -- content that is not on main and never was --
  # satisfy a marker in exactly the mode the canary job runs, while the same row
  # reports NOT RESTORED at an explicit rev. The two modes must agree.
  printf 'RESTORED_MARKER_SENTINEL\n' >"$repo/untracked.txt"
  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s untracked.txt RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 1 ]]; then
    ok "an untracked file cannot satisfy a marker in working-tree mode"
  else
    fail "an untracked path must not satisfy a marker, rc=$RC: $out"
  fi
  rm -f "$repo/untracked.txt"

  # A path that leaves the repository is refused outright, in both modes,
  # because a marker resolved outside the tree asserts nothing about main.
  local escaping
  for escaping in "/etc/hostname" "../guarded.txt" "a/../../guarded.txt" ".."; do
    {
      printf 'fires %s a real drop\n' "$sha"
      printf 'marker %s %s RESTORED_MARKER_SENTINEL\n' "$sha" "$escaping"
    } >"$repo/scripts/inc.txt"
    SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
    out="$OUT"
    if [[ "$RC" -eq 2 ]]; then
      ok "a marker path escaping the repository ('$escaping') exits 2"
    else
      fail "escaping path '$escaping' must exit 2, rc=$RC: $out"
    fi
  done

  # A glob that WOULD match the bound file under a pathspec is a corpus error,
  # refused at parse time so both modes answer identically. Left to resolution,
  # `git cat-file` would report absent (exit 1) while `git ls-files` would
  # expand the glob and report present (exit 0) -- the two modes disagreeing on
  # the same row is how a false green gets in.
  local globbed
  for globbed in "guarded*.txt" "guarded?.txt" "guarded[0-9].txt" ":(glob)guarded.txt"; do
    {
      printf 'fires %s a real drop\n' "$sha"
      printf 'marker %s %s RESTORED_MARKER_SENTINEL\n' "$sha" "$globbed"
    } >"$repo/scripts/inc.txt"
    SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
    out="$OUT"
    local wt_rc="$RC"
    SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration "$sha"
    if [[ "$wt_rc" -eq 2 ]] && [[ "$RC" -eq 2 ]]; then
      ok "a glob marker path '$globbed' is refused identically in both modes"
    else
      fail "glob path '$globbed' must exit 2 in both modes (worktree=$wt_rc, rev=$RC): $out"
    fi
  done
}

# The two modes read the SAME file and must not disturb each other. The replay
# has to step over marker rows (their second field is a path, not a sha), and
# the restoration assertion has to step over the bracketed attribution field
# #2833 puts after a fires row's sha.
t_restoration_and_replay_share_the_corpus() {
  local repo out sha culprit
  repo="$(mk_repo)"
  add_block "$repo" feature.txt 40 alpha
  culprit="$(git -C "$repo" rev-parse HEAD)"
  drop_block "$repo" feature.txt alpha "feat: unrelated feature (#99)"
  sha="$(git -C "$repo" rev-parse HEAD)"
  printf 'RESTORED_MARKER_SENTINEL\n' >"$repo/guarded.txt"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm "fix: re-land the content"

  {
    printf 'fires %s a real drop\n' "$sha"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_THRESHOLD=20 SILENT_REVERT_INCIDENTS=scripts/inc.txt \
    run_canary "$repo" --verify-known-incidents
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q 'fires as recorded'; then
    ok "the replay steps over marker rows instead of reading a path as a sha"
  else
    fail "marker rows must not disturb --verify-known-incidents, rc=$RC: $out"
  fi

  # Forward-compatibility with #2833/#2843: a bracketed attribution field after
  # the sha is free text to the restoration parser, which validates the sha and
  # nothing else on a fires row. This case is what keeps the two row-format
  # extensions composable rather than colliding.
  {
    printf 'fires %s [%s=40] a real drop\n' "$sha" "$culprit"
    printf 'marker %s guarded.txt RESTORED_MARKER_SENTINEL\n' "$sha"
  } >"$repo/scripts/inc.txt"
  SILENT_REVERT_INCIDENTS=scripts/inc.txt run_canary "$repo" --verify-restoration
  out="$OUT"
  if [[ "$RC" -eq 0 ]] && printf '%s' "$out" | grep -q 'present: RESTORED_MARKER_SENTINEL'; then
    ok "a fires row carrying a bracketed attribution field still resolves its markers"
  else
    fail "the restoration parser must ignore a fires row's extra fields, rc=$RC: $out"
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
  # Anything non-blank, non-comment must match the row grammar. `marker` rows
  # (#2855) are part of that grammar: they carry the incident sha in the same
  # second field, then a path, then free-text marker content.
  grep -vE '^[[:space:]]*(#|$)' "$inc" |
    grep -qvE '^(fires|clean|marker)[[:space:]]+[0-9a-f]{40}[[:space:]]' && bad=1
  if [[ "$bad" -eq 0 ]]; then
    ok "silent-revert-incidents.txt is well-formed with $n pinned rows"
  else
    fail "silent-revert-incidents.txt is malformed or has too few rows (n=$n)"
  fi

  # Every shipped `fires` row must carry at least one marker (#2855).
  #
  # --verify-restoration enforces this at run time too, but only in the canary
  # job with full history. Pinning it HERE means a `fires` row landing without
  # a marker is a red unit test on the PR that adds it, rather than a red
  # canary after the merge -- and the whole point of this issue is that the
  # restoration half must not depend on someone reading a post-merge log.
  bad=0
  local row_sha marker_shas
  marker_shas="$(awk '$1 == "marker" { print $2 }' "$inc" | sort -u)"
  while read -r row_sha; do
    [[ -n "$row_sha" ]] || continue
    printf '%s\n' "$marker_shas" | grep -qxF "$row_sha" || bad=1
  done < <(awk '$1 == "fires" { print $2 }' "$inc")
  if [[ "$bad" -eq 0 ]]; then
    ok "every shipped fires row carries at least one restoration marker"
  else
    fail "a shipped fires row in silent-revert-incidents.txt carries no marker row"
  fi

  # And the reverse: a marker whose sha names no `fires` row is a typo that
  # would silently cover nothing.
  bad=0
  while read -r row_sha; do
    [[ -n "$row_sha" ]] || continue
    awk '$1 == "fires" { print $2 }' "$inc" | grep -qxF "$row_sha" || bad=1
  done < <(printf '%s\n' "$marker_shas")
  if [[ "$bad" -eq 0 ]]; then
    ok "every shipped marker row names a recorded fires incident"
  else
    fail "a marker row in silent-revert-incidents.txt names no fires row"
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
t_restoration_reports_present_and_absent_markers
t_restoration_refuses_a_malformed_corpus
t_restoration_binds_a_marker_to_exactly_one_file
t_restoration_and_replay_share_the_corpus
t_shipped_data_files_are_wellformed

echo
echo "check-silent-revert.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
