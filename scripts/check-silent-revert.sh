#!/usr/bin/env bash
# Post-merge canary: detect a merge that silently DELETED content another
# recently-merged commit had just added, with nothing in its own message saying
# it meant to.
#
#   scripts/check-silent-revert.sh <range>        scan commits in a range (A..B)
#   scripts/check-silent-revert.sh --commit <sha> scan one commit
#   scripts/check-silent-revert.sh --verify-known-incidents
#                                                 replay the recorded incidents
#   scripts/check-silent-revert.sh --verify-restoration [<rev>]
#                                                 assert the recorded incidents'
#                                                 content is back (default: the
#                                                 working tree)
#
# Exit 0 clean, 1 findings, 2 the canary could not run (never a quiet pass).
#
# WHY THIS EXISTS (#2691)
# ----------------------
# On 2026-08-15, three squash merges each landed a tree that dropped work a
# sibling PR had merged minutes earlier. #2633 dropped #2644's finding rollups
# (853 lines) AND #2642's aliased GraphQL merge evidence (301) in one squash --
# plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh went 2178 ->
# 1700 lines with every `rollup` and `graphql` marker at zero; #2639 dropped
# #2635's report-ordering fix (346); #2641 dropped #2639's guard work (451) --
# destructive_guard.py went 1643 -> 1424 lines.
#
# Every PARENTHESIZED line count above is a blame attribution: the number of
# lines the reverting squash deleted that `git blame` credits to that one
# culprit commit. It is not the squash's diffstat (cc58cbc53 removed 1165
# lines in total) and not the number of lines the culprit added. The bare
# `2178 -> 1700` and `1643 -> 1424` figures are a different measurement --
# whole-file line counts before and after.
#
# Every check stayed green through all three, and that is the point: each
# reverting squash removed the code AND the tests covering it in the same
# commit, so no suite could fail for a behavior whose tests no longer existed.
# A squash that merely omits content leaves no `Revert:` commit either, so the
# log reads clean. Two issues sat CLOSED as COMPLETED with their fixes absent
# from origin/main, and it took a from-scratch content audit to notice.
#
# WHAT THIS IS NOT A SUBSTITUTE FOR -- and why the obvious guards do not cover it
# ------------------------------------------------------------------------------
# The intuitive reading of #2691 is "stale base", whose fix is GitHub's
# `strict_required_status_checks_policy` (require branches up to date before
# merging). That reading does not survive the evidence. pull request 2641's head commit
# a1cc5cf6 has f603880d (#2639) IN ITS ANCESTRY -- `git merge-base --is-ancestor
# f603880d refs/pull/2641/head` is true -- while its TREE carried zero
# occurrences of #2639's marker strings. #2639 shows the identical shape against
# #2635. The branches were up to date with main in history and stale in content:
# a bad conflict resolution or a force-push from an older worktree, not a stale
# base.
#
# So `strict` would have passed all three merges, and so would a merge queue
# (CI was green -- the tests were deleted alongside the code). That is why this
# canary is not defence in depth behind a real fix; for this failure class it is
# the only control that fires at all. It is also why the global strict toggle
# stays off, which is separately governed by an accepted ADR in
# melodic-software/github-iac (docs/adr/0001-relax-strict-required-status-checks.md).
#
# WHY BLAME-OF-DELETED-LINES, AND NOT THE ALTERNATIVES
# ---------------------------------------------------
# Three designs were measured against the real history before this one was
# chosen.
#
#   Curated marker strings (#2691's own suggestion 3). Catches only what
#   somebody pre-registered. Nobody had registered #2644, #2642, #2635 or
#   #2639 -- registration happens after you already know a fix matters, which
#   is exactly the knowledge the incident destroys. It also decays: the list is
#   only as fresh as the last person who remembered to append to it.
#
#   Merge-base staleness (the PR's branch point vs. what landed since).
#   Tested and REJECTED on evidence: it exonerates all three real incidents,
#   because all three branches were up to date in history. It is a
#   false-negative machine for the exact class it is meant to catch.
#
#   PR-creation-time overlap (culprit landed after the PR was opened).
#   Tested and rejected as non-discriminating: at the 17-concurrent-PR rate the
#   ADR records for this repo, nearly every PR has siblings landing while it is
#   open, so it fires on almost everything.
#
# What is left is content: blame the lines a merge deleted and see who had just
# added them. Measured over the last 500 first-parent commits of main, the
# three known incidents score 853 / 451 / 346 lines against a single recent
# commit -- plus a fourth attribution of 301 lines on the SAME #2633 squash,
# whose deletions trace to two different culprits and are reported separately.
# The highest verified-legitimate commit scores well below the threshold below.
# The separation is what makes the canary livable.
#
# FALSE-POSITIVE STRATEGY (the whole design rests on this)
# -------------------------------------------------------
# A canary that cries wolf gets disabled, which is worse than not having one.
# Four constraints keep the firing rate near the true-incident rate:
#
#   1. VOLUME. Only a large block of removed content counts, and the lines must
#      all trace to ONE culprit commit. Ordinary iteration deletes a handful of
#      recent lines from several places; a wholesale revert deletes hundreds
#      from one. Per-culprit aggregation is deliberate -- summing across
#      culprits would re-admit the routine case.
#
#   2. RECENCY. The culprit must be within the last SILENT_REVERT_WINDOW
#      first-parent commits. This class is created by PRs open CONCURRENTLY, so
#      the culprit is always a near neighbour. Corollary limitation, stated
#      plainly: content reverted from OUTSIDE that window is missed by design.
#      Widening the window buys little (deletions of older code are normal
#      maintenance) and costs a lot of noise.
#
#   3. INTENT, matched in CONSTRAINED FORMS ONLY -- a `Revert "` subject, a
#      `This reverts commit <sha>` line, or an explicit `Intentional-removal:`
#      trailer. Deliberately NOT a substring search for "revert": a body
#      reading "this does not revert X" would silence a real finding, turning
#      the false-positive fix into a false-negative hole.
#
#   4. NON-BLOCKING. It runs post-merge on main only, never as a PR gate, and
#      is never wired into ci-status's needs. Detection, not prevention. A
#      canary that can block a merge acquires a constituency for disabling it.
#
# THE RESIDUAL FALSE POSITIVE, MEASURED RATHER THAN ASSUMED
# ---------------------------------------------------------
# At these settings, over the last 500 first-parent commits of main, the canary
# fires on 5 commits -- 1%. (Six findings, not five: #2633's squash deleted
# content from two different culprits and each attribution is reported on its
# own.) Three of the five commits are the confirmed incidents. The other two
# are both real, and neither is a bug in the detector:
#
#   6f0a31109 (#2640, 390 lines) is the manual RESTORE of #2633's revert. To
#   put back what #2633 dropped it had to delete what #2633 had added, so a
#   large deliberate removal of very recent content is exactly what it is.
#
#   91e77fc16 (#2135, 340 lines) is a deliberate merge reconciliation: main
#   moved under the PR, the author merged origin/main in and consciously chose
#   which side won, and the PR body argues the choice at length.
#
# State the uncomfortable part plainly: 340 is the largest false positive and
# 346 is the smallest true one. NO THRESHOLD SEPARATES THEM. Picking a number
# in that 2% gap would be overfitting to this corpus, so the threshold is set
# at 200 instead -- which costs nothing (200 and 300 fire on the identical five
# commits here) and leaves headroom for a smaller future revert.
#
# So the canary is calibrated to fire roughly once a month, on something a
# human should genuinely glance at, and precision is deliberately traded for
# recall because the miss is expensive and the fire is cheap. Cheap requires a
# disposition path for BOTH directions in time, which is why there are two:
#
#   PROSPECTIVE -- `Intentional-removal:` in the PR body, which GitHub carries
#   into the squash message. Costs one line and the canary never fires.
#
#   RETROSPECTIVE -- scripts/silent-revert-acknowledged.txt. A commit message
#   cannot be amended after the merge, so a fire that turns out to be fine is
#   cleared by recording the reviewed SHA and its disposition, the same shape
#   as scripts/changelog-parity-baseline.txt and
#   scripts/orphaned-fixtures-baseline.txt. Without this, one legitimate fire
#   would leave main's canary permanently red, and a permanently red canary is
#   a canary on its way to being deleted.
#
# The acknowledgment file is an audit trail, not a mute button: every entry
# records a human decision about a specific commit, and a reviewer can read
# back exactly which removals were judged intentional and why.
#
# DETECTION IS NOT RESTORATION (#2855)
# ------------------------------------
# Everything above answers one question about a recorded incident -- does this
# commit still produce a finding -- and never the other one: is the content it
# deleted on main TODAY. #2828 is the proof that the gap is real rather than
# theoretical. The f603880da row printed `ok  f603880da fires as recorded` and
# the replay exited 0 for 31h28m while the content #2635 had added to
# plugins/disk-hygiene/README.md and
# plugins/disk-hygiene/skills/clean/evals/evals.json was absent from main. Two
# separate re-lands (#2714, #2803) each missed it, and a hand audit found it,
# not this canary.
#
# Say CONTENT rather than "files", precisely. Both files existed at every rev in
# that window -- #2829 shows as `README.md | 14 ++---` and `evals.json | 15 ++-`,
# modifications, not additions. That is exactly why the gap survived: a
# file-level or path-level check sees two present, recently-touched files and
# has nothing to report.
#
# So a `fires` row also carries one or more CONTENT MARKERS, each bound to the
# path it must be found in, and --verify-restoration asserts every one of them
# still resolves path-scoped against a rev (the working tree by default).
#
# This is NOT the curated-marker design rejected above, and the distinction is
# the whole reason it works. That rejection is about DISCOVERY: a marker list
# cannot find an incident nobody registered, because registration happens after
# you already know a fix matters. These markers hang off a row that is ALREADY
# in scripts/silent-revert-incidents.txt -- the knowledge exists and recording
# it costs one line. #2691's own suggestion 3 asked for exactly this; only
# suggestion 2's shape was ever built.
#
# Two cheaper designs were measured against the real instance and both fail:
#
#   PATH-LEVEL ("was this path revisited since?") is a false NEGATIVE here.
#   9239f1541 touched BOTH files ten minutes after the incident, so the answer
#   is yes for both on a tree where the content is gone.
#
#   VERBATIM HUNK ("is the deleted diff back byte-for-byte?") is permanently
#   RED on the README half. #2828 records that #2635's README hunk was
#   malformed and must NOT be restored byte-for-byte, and #2829 restored the
#   intent instead. A marker survives that rewrite; the hunk cannot.
#
# Markers resolve PATH-SCOPED, which is load-bearing rather than tidy. Both
# markers on the f603880da row also occur elsewhere in the same plugin on
# current main -- the engine script, its test file, CHANGELOG.md -- so a
# repo-wide `git grep` would have reported both files restored while both were
# missing.
#
# Cost: one exact-path read per marker over a four-row corpus -- `git cat-file`
# at a rev, a tracked-path read in the working tree -- with the match done by
# `grep -qF` on the file's contents. Not `git grep`: its pathspec semantics are
# the very thing marker_present() below refuses, because a pathspec can widen a
# bound path back into the repo-wide search this design exists to avoid. That
# cost is why the assertion runs in the same `push: main` job as the replay
# instead of behind an on-demand flag. "Nobody thought to check" is the failure that produced #2828,
# so an on-demand-only mode would reproduce it.
#
# The self-test (scripts/check-silent-revert.test.sh) runs BEFORE this script in
# CI, so a broken detector cannot mask a regression behind a green canary --
# the same never-skip, self-test-first, fail-closed shape the ci.yml gates use.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || {
  echo "check-silent-revert: cannot reach the repository root" >&2
  exit 2
}

# Tunables. Defaults are the measured values; the env vars exist so the
# self-test can drive small synthetic repos without shipping a second code path.
THRESHOLD="${SILENT_REVERT_THRESHOLD:-200}"
WINDOW="${SILENT_REVERT_WINDOW:-40}"
# Sample lines quoted back in a finding, and the minimum length for a line to be
# worth quoting (a bare brace tells a reader nothing).
SAMPLES="${SILENT_REVERT_SAMPLES:-5}"
SAMPLE_MIN_LEN=25

INCIDENTS_FILE="${SILENT_REVERT_INCIDENTS:-scripts/silent-revert-incidents.txt}"
ACK_FILE="${SILENT_REVERT_ACK:-scripts/silent-revert-acknowledged.txt}"

# Field separator of the parsed marker view (ASCII Unit Separator).
#
# Deliberately NOT a tab. A tab is an IFS *whitespace* character, so `IFS=$'\t'
# read -r a b c d` collapses runs of tabs into one delimiter and drops empty
# fields -- which silently shifts every field left whenever the optional
# disposition reason is empty, i.e. on the ordinary row. Measured here: the
# marker text landed in the reason variable and the marker came back as the
# empty string, which `grep -F` matches against everything, so every marker
# reported present. That is precisely the false green this file exists to
# remove, so the separator is a non-whitespace character whose empty fields
# survive.
SEP=$'\037'

die() {
  echo "check-silent-revert: $*" >&2
  exit 2
}

usage() {
  cat >&2 <<'EOF'
usage:
  scripts/check-silent-revert.sh <range>                  e.g. abc123..def456
  scripts/check-silent-revert.sh --commit <sha>
  scripts/check-silent-revert.sh --verify-known-incidents
  scripts/check-silent-revert.sh --verify-restoration [<rev>]
EOF
  exit 2
}

command -v git >/dev/null 2>&1 || die "git is required"

# ---------------------------------------------------------------------------
# Intent markers. Constrained forms only -- see FALSE-POSITIVE STRATEGY above.
# ---------------------------------------------------------------------------
# Returns 0 when the commit declares the removal, printing the clause matched.
declares_removal() {
  local sha="$1" msg subject
  msg="$(git log -1 --format=%B "$sha")" || return 1
  subject="$(printf '%s\n' "$msg" | head -n 1)"

  case "$subject" in
    'Revert "'*)
      printf 'the subject begins with a Revert quote, as git revert writes it\n'
      return 0
      ;;
    *) ;;
  esac
  if printf '%s\n' "$msg" | grep -Eq '^This reverts commit [0-9a-f]{7,40}'; then
    printf 'the body carries a "This reverts commit <sha>" line\n'
    return 0
  fi
  # The explicit ack. Requires a non-empty reason so an empty trailer cannot be
  # pasted in as a blanket mute.
  if printf '%s\n' "$msg" | grep -Eq '^Intentional-removal:[[:space:]]*[^[:space:]]'; then
    printf 'the body carries an Intentional-removal trailer\n'
    return 0
  fi
  return 1
}

# Retrospective disposition: prints the recorded reason and returns 0 when this
# exact commit has been reviewed and cleared by a human.
#
# Full 40-character shas only. An abbreviation would let one entry silence
# whatever else happened to share its prefix, which is the difference between an
# audit trail and a mute button.
ack_reason() {
  local sha="$1"
  [[ -f "$ACK_FILE" ]] || return 1
  local recorded reason
  while read -r recorded reason; do
    case "$recorded" in
      '' | '#'*) continue ;;
      *) ;;
    esac
    if [[ "$recorded" = "$sha" ]]; then
      printf '%s\n' "${reason:-<no reason recorded>}"
      return 0
    fi
  done <"$ACK_FILE"
  return 1
}

# ---------------------------------------------------------------------------
# Deleted-line attribution.
# ---------------------------------------------------------------------------
# For one file, emit "<culprit-sha> <TAB> <deleted line text>" for every line the
# commit removed, attributed to whoever last touched it in the parent.
#
# One blame invocation per FILE, not per hunk: git blame accepts repeated -L
# ranges, and a commit touching a 900-line test file produces hundreds of hunks.
#
# Rename detection is left ON (git's default) everywhere in this script, and
# that is load-bearing rather than incidental. With --no-renames a `git mv`
# decomposes into a delete plus an add, the delete side reaches the enumeration
# below as a whole-file removal, and every line in a moved file gets attributed
# to whoever last touched it -- so relocating a large file a recent commit had
# added would fire. This repo restructures skills and docs constantly, so that
# is a live false-positive class, not a hypothetical one. With detection on, a
# rename reports as R and the --diff-filter=MD enumeration skips it.
#
# The measured false-positive rate in the header was taken with detection on,
# so this is also what keeps the shipped behaviour and the calibrated number
# describing the same detector.
#
# The cost is a narrow blind spot, stated rather than hidden: content gutted in
# the same commit that renames its file is not attributed. A rename that git
# still pairs is a mostly-similar file, which bounds how much content can vanish
# inside one; the incident class this canary targets modifies existing paths.
attribute_file() {
  local parent="$1" commit="$2" file="$3"
  local -a ranges=()

  # Old-side hunk ranges (the parent's line numbers) with at least one deleted
  # line. --unified=0 keeps each hunk tight to its own deletions.
  while read -r start count; do
    [[ -n "$start" ]] || continue
    [[ "$count" -gt 0 ]] || continue
    ranges+=(-L "$start,$((start + count - 1))")
  done < <(
    git diff --unified=0 --no-color "$parent" "$commit" -- "$file" 2>/dev/null |
      awk '/^@@ /{
             split($2, a, ",")
             start = substr(a[1], 2) + 0
             count = (length(a) > 1) ? a[2] + 0 : 1
             if (start > 0) print start, count
           }'
  )

  [[ "${#ranges[@]}" -gt 0 ]] || return 0

  # --line-porcelain repeats the header for every line, so sha and text stay
  # paired without tracking porcelain's abbreviated continuation form.
  #
  # The header match deliberately avoids an ERE interval ({40}): interval
  # support is an awk-implementation variable, and the runner's default awk is
  # mawk while most development machines run gawk. A pattern that silently
  # fails to match would make attribute_file emit nothing and every commit
  # report `ok` -- a false green, which is precisely the failure this canary
  # exists to remove. The porcelain header is `<sha> <orig> <final> [<n>]`, so
  # matching hex-then-two-numbers and checking the length explicitly is both
  # interval-free and unambiguous against the `author`/`filename`/`summary`
  # lines it must not match.
  git blame --line-porcelain "${ranges[@]}" "$parent" -- "$file" 2>/dev/null |
    awk '
      /^[0-9a-f]+ [0-9]+ [0-9]+/ { if (length($1) == 40) { sha = $1; next } }
      /^\t/ { if (sha != "") printf "%s\t%s\n", sha, substr($0, 2) }
    '
}

# ---------------------------------------------------------------------------
# Scan one commit. Returns 0 clean, 1 findings.
# ---------------------------------------------------------------------------
scan_commit() {
  local commit="$1"
  local sha subject parent
  sha="$(git rev-parse --verify "${commit}^{commit}" 2>/dev/null)" ||
    die "not a commit: $commit"
  subject="$(git log -1 --format=%s "$sha")"

  # Root commits delete nothing. Merge commits cannot occur here (the branch
  # ruleset requires linear history) but are handled rather than crashed on:
  # first-parent is the mainline view this canary reasons about.
  parent="$(git rev-parse --verify "${sha}^1" 2>/dev/null)" || {
    printf 'skip %s (root commit, no parent to compare against)\n' "${sha:0:9}"
    return 0
  }

  local why
  if why="$(declares_removal "$sha")"; then
    printf 'declared %s %s\n' "${sha:0:9}" "$subject"
    printf '         removal is declared: %s' "$why"
    return 0
  fi

  # Retrospective disposition. Matched on the FULL 40-char sha so an
  # abbreviation can never widen into an unintended commit.
  local ack_note
  if ack_note="$(ack_reason "$sha")"; then
    printf 'acknowledged %s %s\n' "${sha:0:9}" "$subject"
    printf '             reviewed and cleared: %s\n' "$ack_note"
    return 0
  fi

  # The recency window: commits reachable from the parent along first-parent.
  local window_file
  window_file="$(mktemp)" || die "mktemp failed"
  git rev-list --first-parent -n "$WINDOW" "$parent" >"$window_file" 2>/dev/null

  if [[ ! -s "$window_file" ]]; then
    rm -f "$window_file"
    printf 'skip %s (no history behind the parent to compare against)\n' "${sha:0:9}"
    return 0
  fi

  # Attribute every deleted line across every modified/deleted file.
  local attributed
  attributed="$(mktemp)" || die "mktemp failed"
  local file
  while IFS= read -r -d '' file; do
    attribute_file "$parent" "$sha" "$file" |
      awk -v f="$file" -F '\t' '{printf "%s\t%s\t%s\n", $1, f, $2}' >>"$attributed"
  done < <(git diff --name-only -z --diff-filter=MD "$parent" "$sha")

  # Keep only lines whose culprit is inside the recency window.
  local in_window
  in_window="$(mktemp)" || die "mktemp failed"
  if [[ -s "$attributed" ]]; then
    awk -F '\t' 'NR == FNR { w[$1] = 1; next } ($1 in w)' \
      "$window_file" "$attributed" >"$in_window"
  fi

  local findings=0 culprit count
  while read -r count culprit; do
    [[ -n "$culprit" ]] || continue
    [[ "$count" -ge "$THRESHOLD" ]] || continue
    findings=$((findings + 1))
    report_finding "$sha" "$subject" "$parent" "$culprit" "$count" "$in_window"
  done < <(awk -F '\t' '{c[$1]++} END {for (k in c) print c[k], k}' "$in_window" |
    sort -rn)

  rm -f "$window_file" "$attributed" "$in_window"

  if [[ "$findings" -eq 0 ]]; then
    printf 'ok %s %s\n' "${sha:0:9}" "$subject"
    return 0
  fi
  return 1
}

# report_finding <sha> <subject> <parent> <culprit> <count> <attributed-file>
# Names WHAT disappeared, WHICH commit removed it, and WHICH commit had added
# it -- a finding that says only "something changed" is not worth having.
report_finding() {
  local sha="$1" subject="$2" parent="$3" culprit="$4" count="$5" data="$6"
  local distance
  distance="$(git rev-list --first-parent --count "${culprit}..${parent}" 2>/dev/null)"

  printf '\n'
  printf 'SILENT REVERT SUSPECTED\n'
  printf '\n'
  printf '  removed by   %s  %s\n' "${sha:0:9}" "$subject"
  printf '               %s\n' "$(git log -1 --format=%ci "$sha")"
  printf '  content from %s  %s\n' "${culprit:0:9}" "$(git log -1 --format=%s "$culprit")"
  printf '               %s  (%s commit(s) earlier on main)\n' \
    "$(git log -1 --format=%ci "$culprit")" "$((distance + 1))"
  printf '  lines lost   %s  (threshold %s, window %s commits)\n' \
    "$count" "$THRESHOLD" "$WINDOW"
  printf '\n'
  printf '  by file:\n'
  awk -F '\t' -v c="$culprit" '$1 == c {n[$2]++} END {for (f in n) printf "%8d  %s\n", n[f], f}' \
    "$data" | sort -rn
  printf '\n'
  printf '  sample of the removed content:\n'
  awk -F '\t' -v c="$culprit" -v min="$SAMPLE_MIN_LEN" -v max="$SAMPLES" '
    $1 == c {
      line = $3
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (length(line) >= min) {
        printf "      | %s\n", substr(line, 1, 100)
        if (++shown >= max) exit
      }
    }' "$data"
  printf '\n'
  printf '  What to do:\n'
  printf '    Compare the merged tree against what %s landed:\n' "${culprit:0:9}"
  printf '      git diff %s %s -- <file>\n' "${culprit:0:9}" "${sha:0:9}"
  printf '    If the content should still be on main, re-land it.\n'
  printf '    If the removal was intended, record the review in %s:\n' "$ACK_FILE"
  printf '      %s  <why it was intended>\n' "$sha"
  printf '    Next time, saying it in the PR body up front avoids the fire\n'
  printf '    entirely -- GitHub carries the body into the squash message:\n'
  printf '      Intentional-removal: <why>\n'
  printf '\n'
}

# ---------------------------------------------------------------------------
# Replay of the recorded incidents. This is the proof the canary catches the
# real thing rather than merely being plausible: the shipped thresholds are run
# against the actual merges from #2691 and must fire, and against a verified
# legitimate commit and must not.
# ---------------------------------------------------------------------------
verify_known_incidents() {
  [[ -f "$INCIDENTS_FILE" ]] || die "incident file not found: $INCIDENTS_FILE"

  local rc=0 expect sha note
  while read -r expect sha note; do
    case "$expect" in
      '' | '#'*) continue ;;
      # Restoration markers (#2855) are a different assertion about the same
      # incident and belong to --verify-restoration. Skipped HERE, above the
      # reachability check, because a marker row's second field is a path
      # rather than a sha -- reading it as one would die on every marker row.
      marker) continue ;;
      *) ;;
    esac
    if ! git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null; then
      die "incident commit $sha is unreachable -- the canary self-check needs full history (fetch-depth: 0)"
    fi
    local out status
    out="$(scan_commit "$sha" 2>&1)"
    status=$?
    case "$expect" in
      fires)
        if [[ "$status" -eq 1 ]]; then
          printf 'ok   %s fires as recorded  (%s)\n' "${sha:0:9}" "$note"
        else
          printf 'FAIL %s should fire and did not  (%s)\n' "${sha:0:9}" "$note"
          printf '%s\n' "$out"
          rc=1
        fi
        ;;
      clean)
        if [[ "$status" -eq 0 ]]; then
          printf 'ok   %s stays clean as recorded  (%s)\n' "${sha:0:9}" "$note"
        else
          printf 'FAIL %s should stay clean and fired  (%s)\n' "${sha:0:9}" "$note"
          printf '%s\n' "$out"
          rc=1
        fi
        ;;
      *) die "unknown expectation '$expect' in $INCIDENTS_FILE" ;;
    esac
  done <"$INCIDENTS_FILE"

  if [[ "$rc" -ne 0 ]]; then
    echo
    echo "The canary no longer reproduces the incidents it was built for."
    echo "Do not relax the recorded expectations to make this pass."
    return 1
  fi
  echo
  echo "Canary reproduces every recorded incident at the shipped settings."
  return 0
}

# ---------------------------------------------------------------------------
# The restoration assertion (#2855). See DETECTION IS NOT RESTORATION above for
# why a `fires` row alone is only half a proof.
# ---------------------------------------------------------------------------
# A `marker` row records one line of the content an incident removed, and the
# path it must live in:
#
#   marker <incident-full-sha> <path> <marker text to end of line>
#   marker <incident-full-sha> <path> [not-restored: <reason>] <marker text>
#
# The marker text is the whole tail of the line, unparsed and matched with
# `grep -F`, so it may contain any character -- no separator is reserved inside
# it. Interior whitespace is preserved exactly; only leading and trailing
# whitespace is trimmed, by the field read itself. That is why a marker must be
# chosen as a line of content rather than as indentation-sensitive text: a
# marker whose distinguishing feature is its leading spaces would be recorded
# without them and match more loosely than the reader intended.
# The ONE reserved position is a LEADING `[`, which commits the row to
# carrying a disposition, in the same positional slot-after-the-key the
# attribution field uses on a `fires` row. An unterminated `[` is exit 2 rather
# than being re-read as ordinary marker text: a row that quietly degrades into
# "no disposition, strange marker" is the false green this file exists to
# remove, reached by the one route nobody would look at.
#
# The disposition requires a NON-EMPTY reason, exactly as declares_removal()
# requires of `Intentional-removal:`. `[not-restored:]` is rejected, not read as
# a mute -- a marker nobody has to justify is a mute button, and this corpus is
# an audit trail.
#
# The disposition ends at the FIRST `]`, so a REASON may not contain `]`. That
# is the only qualification on "any character", it applies to the reason alone,
# and the marker text after the disposition is still unrestricted. It cannot be
# enforced after the fact: a truncated reason and a legitimate row whose marker
# happens to contain `]` are byte-indistinguishable, so any check that rejects
# the first rejects the second too. A reason truncated at a stray `]` shows up
# in the `noted` line, which prints it verbatim to the human reading the trail.

# parse_incidents_file <fires-shas-out> <markers-out>
#
# Validates every row and writes the two views the assertion needs: one sha per
# line for `fires` rows, and `<sha><SEP><path><SEP><reason><SEP><marker>` for
# `marker` rows, where an empty reason field means "no disposition recorded".
#
# Call it with plain arguments, never through `$(...)` or a pipe: those run it
# in a subshell where `die`'s exit 2 is swallowed, and a malformed corpus would
# degrade into a confusing empty-result pass instead of a hard stop.
#
# Fields after the sha on a `fires` / `clean` row are free text to this parser,
# which is what keeps it forward-compatible with the bracketed attribution
# field #2833 adds in that position.
parse_incidents_file() {
  local fires_out="$1" markers_out="$2"
  : >"$fires_out"
  : >"$markers_out"

  local line kind sha path rest reason marker
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Split FIRST, then decide what the row is, so blank/comment recognition is
    # done on the trimmed leading field rather than on the raw line.
    #
    # Testing the raw line instead would make an INDENTED comment ("  # note")
    # or a whitespace-only line an "unknown row kind" and exit 2 -- while
    # verify_known_incidents (which reads the same file through `read`) skips
    # both, and t_shipped_data_files_are_wellformed explicitly accepts
    # `^[[:space:]]*(#|$)`. Three readers of one file must not disagree about
    # what a comment is: a formatting-only edit to this corpus would otherwise
    # turn the canary red for a reason having nothing to do with the canary.
    read -r kind sha path rest <<<"$line"

    case "$kind" in
      '' | '#'*) continue ;;
      fires | clean)
        [[ "$sha" =~ ^[0-9a-f]{40}$ ]] ||
          die "incident sha '$sha' in $INCIDENTS_FILE is not a full 40-character sha"
        if [[ "$kind" = "fires" ]]; then
          printf '%s\n' "$sha" >>"$fires_out"
        fi
        ;;
      marker)
        # The parsed view below is SEP-delimited, so a row already carrying
        # that byte is refused up front rather than split at the wrong field
        # boundary without anyone noticing. It is a
        # control character no editor writes by accident; the check exists so
        # the invariant is stated rather than assumed.
        case "$line" in
          *"$SEP"*) die "marker row for $sha in $INCIDENTS_FILE contains a control character" ;;
          *) ;;
        esac
        [[ "$sha" =~ ^[0-9a-f]{40}$ ]] ||
          die "marker row sha '$sha' in $INCIDENTS_FILE is not a full 40-character sha"
        [[ -n "$path" ]] ||
          die "marker row for $sha in $INCIDENTS_FILE records no path"
        # The path names a file INSIDE this repository, relative to its root.
        # An absolute path or a `..` component would reach outside the tree the
        # assertion is about, so a marker could be satisfied by content that is
        # not on main at all. Refused here rather than at resolution time, so
        # both modes are held to it identically.
        case "$path" in
          \[*) die "marker row for $sha in $INCIDENTS_FILE has a disposition where its path should be" ;;
          /* | [A-Za-z]:[/\\]* | \\*)
            die "marker path '$path' for $sha in $INCIDENTS_FILE is absolute -- use a path relative to the repository root" ;;
          .. | ../* | */../* | */..)
            die "marker path '$path' for $sha in $INCIDENTS_FILE escapes the repository with '..'" ;;
          # Glob and pathspec metacharacters are refused rather than resolved.
          # They are the widening vectors, and refusing them at parse time is
          # what keeps BOTH modes answering identically: `git cat-file` would
          # simply not find such a path (absent, exit 1) while `git ls-files`
          # would expand it (present, exit 0). A marker path is a literal file
          # path or it is a corpus error.
          :*)
            die "marker path '$path' for $sha in $INCIDENTS_FILE uses pathspec magic -- a marker binds to one literal file path" ;;
          *[*?[]*)
            die "marker path '$path' for $sha in $INCIDENTS_FILE contains a glob character -- a marker binds to one literal file path" ;;
          *) ;;
        esac

        reason=""
        marker="$rest"
        if [[ "$rest" == \[* ]]; then
          [[ "$rest" == \[*\]* ]] ||
            die "unterminated disposition on the marker row for $sha in $INCIDENTS_FILE (no closing ']'): $rest"
          local disposition="${rest%%\]*}"
          disposition="${disposition#\[}"
          printf '%s\n' "$disposition" |
            grep -Eq '^not-restored:[[:space:]]*[^[:space:]]' ||
            die "disposition '[$disposition]' on the marker row for $sha in $INCIDENTS_FILE must be [not-restored: <non-empty reason>]"
          reason="${disposition#not-restored:}"
          reason="${reason#"${reason%%[![:space:]]*}"}"
          # The disposition ends at the FIRST `]`. That is the grammar, stated
          # up front, and it is why a reason may not itself contain `]`.
          #
          # It cannot be an after-the-fact check, and trying was a mistake worth
          # recording. `[not-restored: see note (ref] for detail)] TEXT` (a
          # truncated reason) and `[not-restored: reason] some ] text` (a
          # perfectly good row whose MARKER happens to contain a bracket) are
          # byte-indistinguishable in shape. Any rule that rejects the first
          # also rejects the second, and the second is legitimate -- the header
          # above promises marker text may contain any character.
          #
          # So the grammar is documented rather than policed, and the safety net
          # is the report: a `noted` line prints the recorded reason verbatim,
          # so a reason truncated at a stray `]` is visible to the human reading
          # the audit trail. Dispositioned rows are the rare, hand-reviewed
          # case; that is the right place for a documented restriction.
          marker="${rest#*\]}"
          marker="${marker#"${marker%%[![:space:]]*}"}"
        fi
        [[ -n "$marker" ]] ||
          die "marker row for $sha in $INCIDENTS_FILE records no marker text"

        printf '%s%s%s%s%s%s%s\n' \
          "$sha" "$SEP" "$path" "$SEP" "$reason" "$SEP" "$marker" >>"$markers_out"
        ;;
      *) die "unknown row kind '$kind' in $INCIDENTS_FILE" ;;
    esac
  done <"$INCIDENTS_FILE"
}

# marker_present <rev> <path> <marker>
# 0 present, 1 absent. An empty rev means the working tree.
#
# The path is resolved to EXACTLY ONE FILE, never handed to a pathspec.
#
# That is the difference between this assertion meaning something and meaning
# nothing, and it is not theoretical. `git grep -- <path>` reads its argument as
# a PATHSPEC, so a path that is a directory (`plugins/disk-hygiene`), a glob
# (`plugins/*`), a bare `.`, or pathspec magic (`:/`, `:(glob)**`) silently
# widens the search to a SUPERSET of the file the marker is bound to. Nothing
# about such a row looks wrong to a reviewer.
#
# The amplifier that makes it fatal: every marker string is, by construction,
# also present in scripts/silent-revert-incidents.txt itself, because that is
# where the marker is written down. So a widened path does not merely risk a
# stray match -- it makes the assertion TAUTOLOGICALLY satisfiable by its own
# corpus. Measured: with every shipped path replaced by `.`, all five markers
# report restored on a tree with plugins/disk-hygiene and
# plugins/repo-fleet-hygiene deleted outright.
#
# `git cat-file <rev>:<path>` has no pathspec semantics at all -- it is an exact
# object lookup -- so the widening class cannot be expressed. A path that names
# no object at the rev returns 1 (absent), which is a legitimate finding: content
# cannot be restored to a file that is not there. A path that resolves to a tree
# rather than a blob is a corpus error, not a finding, and exits 2.
#
# grep's exit status is then read explicitly rather than through `if`, because 1
# (no match) and >1 (could not run) must not collapse. A broken invocation
# reported as "marker absent" would be the false-RED twin of the false green the
# rest of this script exists to remove. grep reads a here-string rather than a
# pipe from cat-file: under `set -o pipefail`, `grep -q` exiting early on a match
# SIGPIPEs the upstream and the pipeline status becomes 141, which would take
# that very cannot-run branch on a marker that is present.
marker_present() {
  local rev="$1" path="$2" marker="$3" status kind mode content
  if [[ -n "$rev" ]]; then
    kind="$(git cat-file -t "${rev}:${path}" 2>/dev/null)" || return 1
    [[ "$kind" = "blob" ]] ||
      die "marker path '$path' resolves to a $kind at $rev, not a file -- bind a marker to exactly one file"
    # A symlink is a blob too, holding its TARGET PATH as content -- so the
    # `blob` check above passes it, and `git cat-file blob` would answer this
    # marker with a filename instead of file content. Refused, for the same
    # reason the working-tree branch refuses one: a marker binds to the file
    # that HOLDS the content.
    #
    # Two deliberate choices here, both about not building a guard that fails
    # OPEN. The mode is read from `ls-tree`'s DEFAULT output rather than
    # `--format=%(objectmode)`, which needs git >= 2.36 -- on an older git the
    # format string is an error, the capture is empty, and a "not 120000" test
    # would wave the symlink straight through. And the accepted set is the
    # REGULAR-FILE modes rather than "anything but a symlink", so an empty or
    # unparsed reading lands on `die` instead of falling through to the read.
    # A guard that goes quiet when it cannot tell is the false green this file
    # exists to remove.
    mode="$(git ls-tree "$rev" -- "$path" 2>/dev/null)"
    mode="${mode%% *}"
    case "$mode" in
      100644 | 100755) ;;
      120000)
        die "marker path '$path' is a symlink at $rev -- bind a marker to the file that holds the content"
        ;;
      *)
        die "marker path '$path' is not a regular file at $rev (mode '${mode:-unreadable}') -- bind a marker to exactly one file"
        ;;
    esac
    content="$(git cat-file blob "${rev}:${path}" 2>/dev/null)" ||
      die "could not read '$path' at $rev"
  else
    # Working-tree mode must stay REPO-SCOPED, or the two modes disagree about
    # what they are asserting. Reading the filesystem directly would let a
    # marker be satisfied by an untracked file, a .gitignore'd file, or a
    # symlink pointing outside the repository entirely -- content that is not
    # on main and never will be. `git ls-files --error-unmatch` is the cheap
    # form of "is this a tracked path", and it makes the default mode assert
    # the same universe the explicit-rev mode does.
    git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || return 1
    # A tracked SYMLINK is tracked as the link, but `-f` and the read below
    # follow it -- so a link committed into the repo could still be answered
    # with content from outside it. At a rev the same row reads the link's
    # blob (its target string) instead. Refuse rather than let the two modes
    # answer a different question.
    if [[ -L "$path" ]]; then
      die "marker path '$path' is a symlink -- bind a marker to the file that holds the content"
    fi
    [[ -f "$path" ]] ||
      die "marker path '$path' is not a regular file -- bind a marker to exactly one file"
    content="$(<"$path")" || die "could not read '$path'"
  fi
  grep -qF -e "$marker" <<<"$content"
  status=$?
  case "$status" in
    0) return 0 ;;
    1) return 1 ;;
    *) die "grep failed (status $status) resolving a marker in $path at ${rev:-the working tree}" ;;
  esac
}

verify_restoration() {
  local rev="${1:-}"
  [[ -f "$INCIDENTS_FILE" ]] || die "incident file not found: $INCIDENTS_FILE"

  local where="the working tree"
  if [[ -n "$rev" ]]; then
    git rev-parse --verify --quiet "${rev}^{commit}" >/dev/null ||
      die "cannot resolve rev '$rev' -- the restoration assertion needs full history (fetch-depth: 0)"
    where="$rev"
  fi

  local fires markers
  fires="$(mktemp)" || die "mktemp failed"
  markers="$(mktemp)" || die "mktemp failed"
  # Every refusal below leaves through `die`, and there are a dozen of them, so
  # cleanup is a trap rather than a straight-line rm at the end -- the same
  # pairing scripts/affected-tests.sh and scripts/check-fleet-audit-doc-grammar.sh
  # use. Without it the self-test alone leaks two files per refusal path.
  #
  # EXIT, not RETURN: `die` exits the shell rather than returning, so a RETURN
  # trap would never fire on exactly the paths that leak. verify_restoration is
  # called once and the script exits straight after, so the global trap is not
  # shared with anything.
  # shellcheck disable=SC2064  # expand the paths now, while they are in scope.
  trap "rm -f '$fires' '$markers'" EXIT
  parse_incidents_file "$fires" "$markers"

  # A corpus with no `fires` row at all must not report a serene pass. The
  # marker-per-fires-row rule below only bites while a `fires` row exists, so
  # deleting a row together with its markers would otherwise leave
  # "Every recorded incident has its content (0 marker(s))" and exit 0 -- the
  # mute button this corpus exists in order not to have, reached by removal
  # instead of by editing.
  [[ -s "$fires" ]] ||
    die "$INCIDENTS_FILE records no 'fires' row -- the restoration assertion would pass while covering nothing"

  # The whole file is validated, and both directions of the sha binding are
  # checked, BEFORE any marker is resolved -- so a corpus problem can never
  # pre-empt the walk and leave a partially reported failure looking complete.
  local sha
  while read -r sha; do
    [[ -n "$sha" ]] || continue
    # The incident has to be a real commit. A well-formed sha nobody can
    # resolve is either a shallow clone (in which case this mode cannot run) or
    # a typo, and a matched typo on a row and its marker would otherwise assert
    # content for an incident that never happened.
    git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null ||
      die "incident commit $sha is unreachable -- the restoration assertion needs full history (fetch-depth: 0)"
    # A `fires` row with no marker is refused rather than skipped. Skipping it
    # would let this whole assertion be satisfied by recording markers for one
    # historical incident while silently covering no future one -- a green
    # signal that has stopped meaning what a reader takes it to mean, which is
    # #2691 wearing a new hat.
    # cut's delimiter is SEP, never its TAB default: the parsed view is
    # SEP-delimited, so `cut -f1` would hand back the WHOLE line and the
    # `grep -qxF` below could never match -- turning "does this fires row have
    # a marker" into "no fires row has a marker" and dying on every corpus.
    cut -d"$SEP" -f1 "$markers" | grep -qxF "$sha" ||
      die "the 'fires' row for ${sha:0:9} in $INCIDENTS_FILE carries no marker. Record at least one: marker $sha <path> <a line of the content it removed>"
  done <"$fires"

  local mpath mreason mtext
  while IFS="$SEP" read -r sha mpath mreason mtext; do
    [[ -n "$sha" ]] || continue
    # And the reverse: a marker on a `clean` row, or on a sha with no row at
    # all, is a typo rather than coverage. Only a removal has content to
    # restore.
    grep -qxF "$sha" "$fires" ||
      die "marker row for $sha in $INCIDENTS_FILE names no recorded 'fires' incident"
  done <"$markers"

  local rc=0 checked=0 absent=0 excused=0
  printf 'Restoration of recorded incident content, resolved at %s:\n\n' "$where"
  while IFS="$SEP" read -r sha mpath mreason mtext; do
    [[ -n "$sha" ]] || continue
    checked=$((checked + 1))
    if marker_present "$rev" "$mpath" "$mtext"; then
      printf 'ok    %s  %s\n' "${sha:0:9}" "$mpath"
      printf '        present: %s\n' "$mtext"
    elif [[ -n "$mreason" ]]; then
      excused=$((excused + 1))
      printf 'noted %s  %s\n' "${sha:0:9}" "$mpath"
      printf '        deliberately not restored: %s\n' "$mreason"
      printf '        marker: %s\n' "$mtext"
    else
      # Never break out of the walk on the first failure: the point of the
      # report is WHICH content is still missing, and a run that stops at the
      # first one answers a question nobody asked.
      absent=$((absent + 1))
      rc=1
      printf 'FAIL  %s  %s\n' "${sha:0:9}" "$mpath"
      printf '        NOT RESTORED: %s\n' "$mtext"
    fi
  done <"$markers"

  if [[ "$rc" -ne 0 ]]; then
    printf '\n'
    printf '%s of %s recorded marker(s) are absent from %s.\n' "$absent" "$checked" "$where"
    echo "Those incidents still FIRE as recorded, which is only half the proof:"
    echo "the removal was detected and never fully undone. Re-land the content."
    echo "If it is deliberately staying out, say so on its marker row -- with a"
    echo "reason, the same shape an Intentional-removal: trailer needs:"
    echo "  marker <incident-sha> <path> [not-restored: <why>] <marker text>"
    echo "Do NOT delete the marker row. That is the mute button this corpus"
    echo "exists in order not to have."
    return 1
  fi

  printf '\n'
  printf 'Every recorded incident has its content at %s (%s marker(s), %s dispositioned).\n' \
    "$where" "$checked" "$excused"
  return 0
}

# ---------------------------------------------------------------------------
main() {
  [[ $# -ge 1 ]] || usage

  case "$1" in
    --verify-known-incidents)
      verify_known_incidents
      exit $?
      ;;
    --verify-restoration)
      # The rev is optional and defaults to the working tree, which is what the
      # canary workflow wants (is the content on main RIGHT NOW) while the
      # explicit form is what lets a reviewer replay the assertion against the
      # historical tree an incident was measured on.
      [[ $# -le 2 ]] || usage
      verify_restoration "${2:-}"
      exit $?
      ;;
    --commit)
      [[ $# -eq 2 ]] || usage
      scan_commit "$2"
      exit $?
      ;;
    -h | --help) usage ;;
    -*) usage ;;
    # Anything else is a range, handled below.
    *) ;;
  esac

  local range="$1"
  case "$range" in
    *..*) ;;
    *) die "expected a commit range like A..B, got '$range'" ;;
  esac

  local commits
  commits="$(git rev-list --first-parent --reverse "$range" 2>/dev/null)" ||
    die "cannot resolve range '$range' -- is the full history fetched (fetch-depth: 0)?"

  if [[ -z "$commits" ]]; then
    echo "check-silent-revert: no commits in range '$range'; nothing to scan."
    exit 0
  fi

  local rc=0 c
  for c in $commits; do
    scan_commit "$c" || rc=1
  done

  if [[ "$rc" -ne 0 ]]; then
    echo
    echo "One or more merges removed a large block of content that had just"
    echo "landed on main, without declaring the removal. See each finding above."
    echo "This check NEVER blocks a merge -- the merge has already happened."
  fi
  exit "$rc"
}

main "$@"
