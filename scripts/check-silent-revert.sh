#!/usr/bin/env bash
# Post-merge canary: detect a merge that silently DELETED content another
# recently-merged commit had just added, with nothing in its own message saying
# it meant to.
#
#   scripts/check-silent-revert.sh <range>        scan commits in a range (A..B)
#   scripts/check-silent-revert.sh --commit <sha> scan one commit
#   scripts/check-silent-revert.sh --verify-known-incidents
#                                                 replay the recorded incidents
#
# Exit 0 clean, 1 findings, 2 the canary could not run (never a quiet pass).
#
# WHY THIS EXISTS (#2691)
# ----------------------
# On 2026-08-15, three squash merges each landed a tree that dropped work a
# sibling PR had merged minutes earlier. #2633 dropped #2644's finding rollups
# (853 lines) AND #2642's aliased GraphQL merge evidence (298) in one squash --
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
# Every count here is measured with the diff flags attribute_file now pins
# explicitly (`--diff-algorithm=myers -M`, both git's defaults). #2642's figure
# reads 298 rather than the 301 recorded before #2837: 301 is the same
# attribution measured under `diff.algorithm = histogram`, which a developer may
# carry in global config, and the detector used to inherit whichever setting the
# caller happened to have. Do not "correct" 298 back to 301 after re-measuring
# on a machine that sets histogram -- pin the flags and re-measure instead.
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
# commit -- plus a fourth attribution of 298 lines on the SAME #2633 squash,
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
#      Conventional-Commits `revert:` / `revert(<scope>):` / `revert!:` subject,
#      a `This reverts commit <sha>` line, or an explicit `Intentional-removal:`
#      trailer. Deliberately NOT a substring search for "revert": a message
#      reading "this does not revert X" would silence a real finding, turning
#      the false-positive fix into a false-negative hole. Every form is anchored
#      at the start of the subject or of a body line for that reason.
#
#      The `revert:` form was added by #2837, which measured that the other
#      three cannot describe a revert that actually merges here. Squash-only
#      with squash_merge_commit_title: PR_TITLE makes the PR title the squash
#      subject, and the required Conventional-Commits title gate admits
#      `revert:` but has no entry a `Revert "…"` subject could match -- so the
#      one deliberate revert in main's 1527-commit history (1d1fca6e8, #1839)
#      was reported as a suspected silent revert by the shipped detector.
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
  # The Conventional-Commits revert type, and the ONLY revert spelling that can
  # reach main here (#2837). This repo is squash-only with
  # squash_merge_commit_title: PR_TITLE, so the squash subject is the PR title,
  # and .github/workflows/pr-title.yml gates every title through a required
  # Conventional-Commits check whose default type list is all-lowercase and
  # contains `revert` but nothing a `Revert "…"` subject could match. Measured
  # over all 1527 first-parent commits of main: `Revert "` 0, `revert:` 1.
  #
  # Kept exactly as constrained as the three forms around it: anchored at the
  # start of the SUBJECT, the literal lowercase type token, its optional
  # `(scope)` and/or `!`, its colon, and a non-empty description. Never a
  # substring search for "revert" -- `feat: do not revert the guard` must still
  # fire, which is what the FALSE-POSITIVE STRATEGY note above is protecting.
  if printf '%s\n' "$subject" | grep -Eq '^revert(\([^()]+\))?!?:[[:space:]]*[^[:space:]]'; then
    printf 'the subject carries the Conventional-Commits revert type\n'
    return 0
  fi
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
  #
  # EVERY config knob that can move a count is pinned on the command line, in
  # BOTH the diff below and the blame beneath it -- see the blame call for its
  # own pins. All of them are the git defaults, so this changes nothing about
  # what CI detects; it makes a local run match CI rather than the reverse.
  #
  # This is not defensive decoration. The algorithm choice changes which lines a
  # hunk calls deleted, and therefore the per-culprit counts this canary
  # thresholds on. Measured on the real corpus, pre-pin, once under each
  # algorithm -- every calibration figure in the header above was taken on a
  # machine carrying `diff.algorithm = histogram`, and git's default disagrees:
  #
  #        commit                          histogram   myers (git default)
  #        6f0a31109 (#2640)                     390                   447
  #        91e77fc16 (#2135)                     340                   323
  #        eda5ae5ed's share of cc58cbc53        301                   298
  #
  # Those are not rounding. 390 -> 447 is 15%, and the same drift can carry a
  # count across the 200-line threshold and make a commit fire on one machine
  # and stay silent on another. The header's calibration describes ONE
  # configuration, and these pins are what keep the shipped detector and those
  # numbers talking about the same thing. Found via #2833, whose exact-count
  # replay assertions turned a silent divergence into a red build.
  #
  # -M pins the same exposure for rename detection, which the note above calls
  # load-bearing: `diff.renames = false` in a developer's config would decompose
  # a `git mv` into delete + add and make relocating a large recent file fire.
  while read -r start count; do
    [[ -n "$start" ]] || continue
    [[ "$count" -gt 0 ]] || continue
    ranges+=(-L "$start,$((start + count - 1))")
  done < <(
    git diff --unified=0 --no-color --diff-algorithm=myers -M \
      "$parent" "$commit" -- "$file" 2>/dev/null |
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
  #
  # blame gets the same ambient-config treatment as the diff above, and it is
  # the bigger exposure of the two. `blame.ignoreRevsFile` REASSIGNS authorship
  # away from the listed commits, which is precisely the quantity the replay's
  # attribution expectations assert on: measured on cc58cbc53 with that setting
  # naming bfb66beb8, its attribution collapses 853 -> 259 while eda5ae5ed's
  # rises 298 -> 322. A developer carrying that config globally -- a normal
  # thing to do in a repo with a bulk-reformat commit -- would get
  # `FAIL ... NOT as recorded` on a clean tree.
  #
  # It has to be the --no-ignore-revs-file OPTION. `-c blame.ignoreRevsFile=`
  # does NOT clear it: the documented "an empty file name resets the list"
  # applies to the option, and the -c form was measured leaving the hostile
  # value fully in effect (853 -> 259 with the reset supposedly applied). The
  # negated option is the only form that actually resets, so the obvious
  # symmetry with the -c pins above is wrong here and is deliberately not used.
  git blame --no-ignore-revs-file --line-porcelain \
    "${ranges[@]}" "$parent" -- "$file" 2>/dev/null |
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
    # -M pinned here for the same reason as in attribute_file: the enumeration
    # relies on a rename reporting as R so --diff-filter=MD skips it, and that
    # is git's default only until someone sets diff.renames = false.
  done < <(git diff --name-only -z -M --diff-filter=MD "$parent" "$sha")

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
#
# When FINDINGS_SINK names a file, each finding is ALSO appended to it as
# `<full-culprit-sha> <count>`. That is the machine-readable channel
# verify_known_incidents asserts against (#2833); nothing else sets it, so
# --commit and range mode are byte-identical to before. Parsing the human
# report back would couple the replay to the report's wording and to the
# 9-character abbreviation it prints, which is not enough sha to assert on.
report_finding() {
  local sha="$1" subject="$2" parent="$3" culprit="$4" count="$5" data="$6"
  local distance
  distance="$(git rev-list --first-parent --count "${culprit}..${parent}" 2>/dev/null)"

  if [[ -n "${FINDINGS_SINK:-}" ]]; then
    printf '%s %s\n' "$culprit" "$count" >>"$FINDINGS_SINK"
  fi

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
#
# WHAT A `fires` ROW ACTUALLY ASSERTS (#2833)
# ------------------------------------------
# Exit status alone proves only "this commit still produces at least one
# finding" -- while the row PRINTS a note claiming a specific culprit and a
# specific line count. The gap is not academic: cc58cbc53's deletions trace to
# two different culprits, so if the eda5ae5ed attribution ever stopped
# reproducing, the row would still pass on the surviving bfb66beb8 finding and
# announce a reproduction it did not perform.
#
# So a row may carry a bracketed ATTRIBUTION EXPECTATION after its sha:
#
#   fires <sha> [<culprit-sha>=<lines>,<culprit-sha>=<lines>] <note>
#
# and the replay then asserts the run's findings are EXACTLY that set -- same
# culprits, same per-culprit line counts, no extras and no omissions. Full
# 40-character culprit shas, the same discipline the acknowledgment file uses,
# so an abbreviation can never widen to a commit nobody recorded. The counts
# come from FINDINGS_SINK, which report_finding writes, rather than from
# scraping the human report.
#
# The field is optional so a row can be recorded before its attribution is
# measured, but every shipped `fires` row carries one. A malformed field is
# exit 2 (cannot run), never a FAIL and never a pass: an expectation silently
# misread is the same false-green this whole file exists to remove.
#
# Do NOT loosen a count to a minimum or a tolerance to make CI pass. If a
# number legitimately changes, measure the new one and record it with the
# reason -- that is a decision, not a threshold.
# ---------------------------------------------------------------------------

# Parses `[<sha>=<n>,<sha>=<n>]` into normalized `<sha> <n>` lines on stdout.
# Exits 2 on anything that is not exactly that grammar.
#
# Call it with a plain redirect, never through a pipe or `$(...)`: those run it
# in a subshell where `die`'s exit 2 would be swallowed and a malformed row
# would degrade into a confusing comparison failure instead of a hard stop.
parse_attribution_field() {
  local field="$1" entry
  field="${field#\[}"
  field="${field%\]}"
  [[ -n "$field" ]] || die "empty attribution field in $INCIDENTS_FILE"
  local IFS=','
  for entry in $field; do
    case "$entry" in
      *=*) ;;
      *) die "malformed attribution entry '$entry' in $INCIDENTS_FILE (want <40-char-sha>=<lines>)" ;;
    esac
    local culprit="${entry%%=*}" lines="${entry#*=}"
    [[ "$culprit" =~ ^[0-9a-f]{40}$ ]] ||
      die "attribution culprit '$culprit' in $INCIDENTS_FILE is not a full 40-character sha"
    [[ "$lines" =~ ^[0-9]+$ ]] ||
      die "attribution line count '$lines' for $culprit in $INCIDENTS_FILE is not a number"
    printf '%s %s\n' "$culprit" "$lines"
  done
}

verify_known_incidents() {
  [[ -f "$INCIDENTS_FILE" ]] || die "incident file not found: $INCIDENTS_FILE"

  local rc=0 expect sha rest note attribution
  local expected_file observed_file
  expected_file="$(mktemp)" || die "mktemp failed"
  observed_file="$(mktemp)" || die "mktemp failed"

  while read -r expect sha rest; do
    case "$expect" in
      '' | '#'*) continue ;;
      *) ;;
    esac
    if ! git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null; then
      die "incident commit $sha is unreachable -- the canary self-check needs full history (fetch-depth: 0)"
    fi

    # Split the optional bracketed attribution field off the free-text note.
    #
    # A leading `[` COMMITS the row to carrying an attribution. Testing for the
    # closing bracket as part of the same condition would be a silent trapdoor:
    # a truncated or typo'd row like `fires <sha> [culprit=40 a note` would fail
    # the glob, the whole remainder would become free text, and the row would
    # fall back to passing on exit status alone -- the exact pre-#2833 gap this
    # replay exists to close, reached by the one route nobody would look at.
    # An unterminated field is malformed, so it takes the malformed path.
    attribution=""
    note="$rest"
    if [[ "$rest" == \[* ]]; then
      [[ "$rest" == \[*\]* ]] ||
        die "unterminated attribution field for $sha in $INCIDENTS_FILE (no closing ']'): $rest"
      attribution="${rest%%\]*}]"
      note="${rest#*\]}"
      note="${note# }"
    fi

    : >"$expected_file"
    if [[ -n "$attribution" ]]; then
      [[ "$expect" = "fires" ]] ||
        die "row for $sha in $INCIDENTS_FILE records an attribution on a '$expect' row; only 'fires' rows have findings"
      parse_attribution_field "$attribution" >"$expected_file"
      sort -o "$expected_file" "$expected_file"
    fi

    local out status
    : >"$observed_file"
    out="$(FINDINGS_SINK="$observed_file" scan_commit "$sha" 2>&1)"
    status=$?
    sort -o "$observed_file" "$observed_file"

    case "$expect" in
      fires)
        if [[ "$status" -ne 1 ]]; then
          printf 'FAIL %s should fire and did not  (%s)\n' "${sha:0:9}" "$note"
          printf '%s\n' "$out"
          rc=1
        elif [[ -n "$attribution" ]] && ! cmp -s "$expected_file" "$observed_file"; then
          printf 'FAIL %s fires, but NOT as recorded  (%s)\n' "${sha:0:9}" "$note"
          printf '     recorded attribution:\n'
          sed 's/^/       /' "$expected_file"
          printf '     what the detector reported:\n'
          sed 's/^/       /' "$observed_file"
          printf '     A row that fires for the wrong reason is not a reproduction.\n'
          printf '     Do NOT edit the row to match; find out why the attribution moved.\n'
          rc=1
        elif [[ -n "$attribution" ]]; then
          printf 'ok   %s fires as recorded, %s attribution(s) reproduced exactly  (%s)\n' \
            "${sha:0:9}" "$(wc -l <"$expected_file" | tr -d '[:space:]')" "$note"
        else
          printf 'ok   %s fires as recorded  (%s)\n' "${sha:0:9}" "$note"
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

  rm -f "$expected_file" "$observed_file"

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
main() {
  [[ $# -ge 1 ]] || usage

  case "$1" in
    --verify-known-incidents)
      verify_known_incidents
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
