#!/usr/bin/env bash
# Report a pull request's `skill-evidence` block to its author, from the
# `ci-status` job.
#
#   scripts/pr-skill-evidence-ci.sh
#
# Input arrives in the environment, the way a workflow step supplies it:
# GH_TOKEN, GITHUB_REPOSITORY, GITHUB_EVENT_NAME, PR_NUMBER, HEAD_SHA,
# IS_DRAFT, HEAD_REPO, and GITHUB_STEP_SUMMARY when the runner sets it.
# SKILL_EVIDENCE_BIN overrides the engine path, which is what the co-located
# suite stubs so the transitions below are tested without a git fixture.
#
# WHAT IT DOES. Fetches the pull request body and its changed paths over REST,
# fetches one compare payload per distinct non-head row SHA the block carries,
# and hands all three to plugins/source-control/scripts/skill-evidence.sh,
# which owns the mandatory map and the freshness rule. On `verdict=gap` it
# upserts ONE comment and adds the `needs-skill-evidence` label; on
# `verdict=clean` it rewrites that comment and removes the label; on
# `verdict=inert` it writes nothing at all.
#
# ADVISORY BY CONSTRUCTION. Every path exits 0, through an EXIT trap rather
# than through discipline at each return: this step runs inside the one job
# that is the required check, and a reporter that can red it would be a gate
# nobody decided to build. A failing `gh`, an unreachable API, a malformed
# body: each is a `::warning::` or a `::notice::` and a zero exit. The
# co-located suite proves that with a stubbed `gh` that fails on every call.
#
# THE HEAD IS THE EVENT'S HEAD, NEVER THE CHECKOUT'S. On a pull request the
# runner checks out `refs/pull/N/merge`, a commit no skill was ever invoked at
# and that exists on no branch. Evidence is owed for
# `github.event.pull_request.head.sha`, which the workflow passes in.
#
# THE COMMENT KEEPS EVERY MARKER LINE. One comment per pull request, whose
# VISIBLE text is rewritten to the current verdict, and whose marker lines
# (`<!-- pr-skill-evidence head=<sha> verdict=gap|clean -->`) are appended to,
# never replaced. The promotion report (`skill-evidence.sh report`) counts a
# firing from a gap marker and an agreement from a later clean marker at a
# different head, so a rewrite that dropped the earlier marker would erase the
# pair it exists to count.
#
# LABEL WRITES ARE STATE-DIFFED. `labeled` and `unlabeled` re-run `ci-status`,
# so an unconditional add or remove would make this step re-trigger the job it
# runs in. The label is written only when the PR is not already in the target
# state, and a label the repository does not carry is a notice naming its
# owner, never an error: label provisioning belongs to the infrastructure
# repository, not to a lane.
set -u

PROG="pr-skill-evidence-ci.sh"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="${SKILL_EVIDENCE_BIN:-$SELF_DIR/../plugins/source-control/scripts/skill-evidence.sh}"
LABEL="needs-skill-evidence"
MARKER_PREFIX="<!-- pr-skill-evidence"
# The compare budget. A legitimate block carries one row per mandatory skill,
# a single-digit number; a body is attacker-supplied text, so an unbounded
# loop over its rows is an unbounded number of API calls.
MAX_COMPARES=20

WORKDIR=""
finish() {
  if [[ -n "$WORKDIR" ]] && [[ -d "$WORKDIR" ]]; then
    rm -rf "$WORKDIR"
  fi
  exit 0
}
trap finish EXIT

notice() { printf '::notice::%s\n' "$*"; }
warn() { printf '::warning::%s\n' "$*"; }

# summary <text> — append one line to the job summary when the runner offers
# one. A summary file the step cannot write is not worth a failure here.
summary() {
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] || return 0
  printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY" 2>/dev/null || true
}

# gh_write <args...> — a GitHub write whose failure is a warning and nothing
# more. Reads stdin when the caller pipes a payload.
gh_write() {
  local out
  if out=$(gh "$@" 2>&1); then
    return 0
  fi
  warn "a GitHub write failed and was skipped: gh $* ($(printf '%s' "$out" | tr '\n' ' '))"
  return 0
}

main() {
  local repo="${GITHUB_REPOSITORY:-}" number="${PR_NUMBER:-}" head="${HEAD_SHA:-}"
  local event="${GITHUB_EVENT_NAME:-}" draft="${IS_DRAFT:-}" head_repo="${HEAD_REPO:-}"

  if [[ "$event" != "pull_request" ]]; then
    notice "$PROG: declined on a ${event:-unknown} event; the skill-evidence block is a pull-request surface."
    return 0
  fi
  if [[ "$draft" == "true" ]]; then
    notice "$PROG: declined on a draft pull request; the block is rendered by the flip to ready."
    return 0
  fi
  if [[ -n "$head_repo" ]] && [[ "$head_repo" != "$repo" ]]; then
    notice "$PROG: declined on a fork head ($head_repo); the workflow token is read-only there."
    return 0
  fi
  if [[ -z "$repo" ]] || [[ -z "$number" ]] || [[ -z "$head" ]]; then
    notice "$PROG: declined: GITHUB_REPOSITORY, PR_NUMBER and HEAD_SHA must all be set."
    return 0
  fi
  case "$number" in
  '' | *[!0-9]*)
    notice "$PROG: declined: PR_NUMBER is not a number ($number)."
    return 0
    ;;
  *) ;;
  esac
  case "$head" in
  *[!0-9a-fA-F]* | '')
    notice "$PROG: declined: HEAD_SHA is not a hexadecimal commit id."
    return 0
    ;;
  *) ;;
  esac
  if ! command -v gh >/dev/null 2>&1; then
    notice "$PROG: declined: gh is not on PATH."
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    notice "$PROG: declined: jq is not on PATH."
    return 0
  fi
  if [[ ! -f "$ENGINE" ]]; then
    notice "$PROG: declined: the evidence engine is not in this checkout ($ENGINE)."
    return 0
  fi

  WORKDIR=$(mktemp -d) || {
    notice "$PROG: declined: cannot create a temporary directory."
    return 0
  }

  local body_file="$WORKDIR/body.md" paths_file="$WORKDIR/paths.txt"
  local compare_file="$WORKDIR/compare.json" report_file="$WORKDIR/report.txt"

  if ! gh api "repos/$repo/pulls/$number" --jq '.body // ""' >"$body_file" 2>"$WORKDIR/body.err"; then
    warn "$PROG: could not read the pull request body; nothing reported. $(tr '\n' ' ' <"$WORKDIR/body.err")"
    return 0
  fi
  if ! collect_paths "$repo" "$number" "$paths_file"; then
    warn "$PROG: could not read the changed files; nothing reported."
    return 0
  fi
  collect_compares "$repo" "$head" "$body_file" "$compare_file"

  if ! "$ENGINE" check --head "$head" --body "$body_file" --files "$paths_file" \
    --compare "$compare_file" >"$report_file" 2>"$WORKDIR/engine.err"; then
    warn "$PROG: the evidence engine reported a usage error; nothing reported. $(tr '\n' ' ' <"$WORKDIR/engine.err")"
    return 0
  fi

  local verdict
  verdict=$(awk -F= '/^verdict=/ { v = $2 } END { print v }' "$report_file")
  case "$verdict" in
  gap | clean | inert) ;;
  *)
    warn "$PROG: the evidence engine printed no verdict; nothing reported."
    return 0
    ;;
  esac

  act_on_verdict "$repo" "$number" "$head" "$verdict" "$report_file"
  return 0
}

# collect_paths <repo> <number> <out> — every path the pull request touches,
# plus the PREVIOUS name of each rename. Both names is what a local
# `git diff --name-only` over the same range yields, so a rename out of a
# matched class is detected here exactly as it is on a developer's machine.
# The map's `@renamed` pseudo-pattern is not expressible through the engine's
# `--files` mode and is not detected from CI.
collect_paths() {
  local repo="$1" number="$2" out="$3"
  local endpoint="repos/$repo/pulls/$number/files?per_page=100"
  : >"$out"
  gh api --paginate "$endpoint" --jq '.[].filename' >>"$out" 2>/dev/null || return 1
  gh api --paginate "$endpoint" \
    --jq '.[] | select(.status == "renamed") | .previous_filename // empty' >>"$out" 2>/dev/null || true
  return 0
}

# block_shas <body> — the distinct row SHAs of the FIRST fenced
# `skill-evidence` block, one per line. A cheap reader on purpose: it feeds
# compare calls, and the engine reads the block itself for the verdict.
block_shas() {
  local body="$1"
  tr -d '\r' <"$body" | awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    {
      t = trim($0)
      if (infence) {
        if (t == "```" || t == "~~~") { infence = 0; done = 1; next }
        n = split(t, f, /[ \t]+/)
        if (n >= 2 && f[2] ~ /^[0-9a-fA-F]+$/ && !seen[f[2]]++) print f[2]
        next
      }
      if (!done && (t == "```skill-evidence" || t == "~~~skill-evidence")) infence = 1
    }
  '
}

# collect_compares <repo> <head> <body> <out> — one REST compare payload per
# distinct non-head row SHA, collected into a JSON array. The engine matches a
# row against `.base_commit.sha` and `.merge_base_commit.sha`; a row the array
# does not carry is reported stale, which is the safe direction for a compare
# call that 404s on a SHA this repository never had.
collect_compares() {
  local repo="$1" head="$2" body="$3" out="$4"
  local dir="$WORKDIR/compare" sha count=0 kept=0
  mkdir -p "$dir"
  while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue
    [[ "$sha" != "$head" ]] || continue
    if [[ "$count" -ge "$MAX_COMPARES" ]]; then
      notice "$PROG: the block carries more than $MAX_COMPARES distinct row commits; the rest are read as stale."
      break
    fi
    count=$((count + 1))
    if gh api "repos/$repo/compare/$sha...$head" >"$dir/$count.json" 2>/dev/null; then
      kept=$((kept + 1))
    else
      rm -f "$dir/$count.json"
    fi
  done < <(block_shas "$body")

  if [[ "$kept" -gt 0 ]]; then
    jq -s '.' "$dir"/*.json >"$out" 2>/dev/null || printf '[]\n' >"$out"
  else
    printf '[]\n' >"$out"
  fi
  return 0
}

# act_on_verdict <repo> <number> <head> <verdict> <report>
act_on_verdict() {
  local repo="$1" number="$2" head="$3" verdict="$4" report="$5"
  local gaps line

  if [[ "$verdict" == "inert" ]]; then
    notice "$PROG: the mandatory map is inert in this repository; nothing to report."
    summary "### Skill evidence"
    summary ""
    summary "The mandatory map (\`pr_skill_evidence\`) is absent or \`none\`, so no evidence is owed."
    return 0
  fi

  gaps=$(awk '/^class=/ || /^missing=/ || /^stale=/ || /^warning=/ { print }' "$report")

  if [[ "$verdict" == "gap" ]]; then
    notice "$PROG: skill-evidence gap at $head."
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      notice "$PROG: $line"
    done <<<"$gaps"
  else
    notice "$PROG: skill-evidence clean at $head."
  fi

  summary "### Skill evidence: $verdict at \`$head\`"
  summary ""
  summary "Advisory. This step turns no check red."
  if [[ -n "$gaps" ]]; then
    summary ""
    summary '```text'
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      summary "$line"
    done <<<"$gaps"
    summary '```'
  fi

  upsert_comment "$repo" "$number" "$head" "$verdict" "$gaps"
  move_label "$repo" "$number" "$verdict"
  return 0
}

# comment_id <repo> <number> — the id of this validator's comment, empty when
# it has not written one yet.
comment_id() {
  local repo="$1" number="$2" ids
  ids=$(gh api --paginate "repos/$repo/issues/$number/comments?per_page=100" \
    --jq ".[] | select((.body // \"\") | contains(\"$MARKER_PREFIX\")) | .id" 2>/dev/null) || ids=""
  printf '%s\n' "$ids" | awk 'NF > 0 { print; exit }'
}

# upsert_comment <repo> <number> <head> <verdict> <gaps>
upsert_comment() {
  local repo="$1" number="$2" head="$3" verdict="$4" gaps="$5"
  local id old="$WORKDIR/old-comment.md" new="$WORKDIR/comment.md"
  local marker="$MARKER_PREFIX head=$head verdict=$verdict -->" last=""

  id=$(comment_id "$repo" "$number")

  {
    if [[ "$verdict" == "gap" ]]; then
      cat <<EOF
### Skill evidence: a gap at \`$head\`

The \`skill-evidence\` block under \`## Verification\` does not cover every mandatory
skill for the files this pull request changes, read against the map in
\`.claude/source-control.md\`:

\`\`\`text
$gaps
\`\`\`

Run \`/source-control:pull-request ready\` to re-render the block at the current head.
This is advisory: no check turns red on it.
EOF
    else
      cat <<EOF
### Skill evidence: clean at \`$head\`

Every mandatory skill for the changed files has a row at this head or on its
history. This is advisory: no check turns red on it.
EOF
    fi
    printf '\n'
  } >"$new"

  if [[ -n "$id" ]]; then
    if gh api "repos/$repo/issues/comments/$id" --jq '.body // ""' >"$old" 2>/dev/null; then
      tr -d '\r' <"$old" |
        grep -o "$MARKER_PREFIX head=[0-9a-fA-F]* verdict=[a-z]* -->" >>"$new" || true
    else
      warn "$PROG: could not read the existing comment; its earlier markers are not carried forward."
    fi
  fi
  # One marker per evaluated HEAD, not one per run: a label flip or a body edit
  # re-runs `ci-status` at the same head, and appending the same line again
  # would grow the comment without recording anything new. A marker identical
  # to the one already at the foot is skipped; every transition still lands,
  # because a different head or a different verdict is a different line.
  last=$(awk 'NF > 0 { line = $0 } END { print line }' "$new")
  if [[ "$last" != "$marker" ]]; then
    printf '%s\n' "$marker" >>"$new"
  fi

  if [[ -n "$id" ]]; then
    jq -n --rawfile body "$new" '{body: $body}' |
      gh_write api --method PATCH "repos/$repo/issues/comments/$id" --input -
  else
    jq -n --rawfile body "$new" '{body: $body}' |
      gh_write api --method POST "repos/$repo/issues/$number/comments" --input -
  fi
  return 0
}

# move_label <repo> <number> <verdict> — add on a gap, remove on a clean
# verdict, and write nothing when the pull request already carries the target
# state.
move_label() {
  local repo="$1" number="$2" verdict="$3" carried=false names name
  if ! gh api "repos/$repo/labels/$LABEL" >/dev/null 2>&1; then
    notice "$PROG: the label $LABEL does not exist in $repo; the verdict is reported by comment only. The label is provisioned by the github-iac repository, which owns every label here."
    return 0
  fi

  names=$(gh api "repos/$repo/issues/$number/labels" --jq '.[].name' 2>/dev/null) || {
    warn "$PROG: could not read the pull request's labels; leaving $LABEL untouched."
    return 0
  }
  while IFS= read -r name; do
    [[ "$name" == "$LABEL" ]] && carried=true
  done <<<"$names"

  if [[ "$verdict" == "gap" ]] && [[ "$carried" == false ]]; then
    gh_write api --method POST "repos/$repo/issues/$number/labels" -f "labels[]=$LABEL"
  elif [[ "$verdict" == "clean" ]] && [[ "$carried" == true ]]; then
    gh_write api --method DELETE "repos/$repo/issues/$number/labels/$LABEL"
  fi
  return 0
}

main "$@"
