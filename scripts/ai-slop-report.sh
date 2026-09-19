#!/usr/bin/env bash
# Annotate the ai-slop findings of a pull request's changed markdown, as
# workflow warnings on the lines that carry them.
#
#   scripts/ai-slop-report.sh <base-ref>
#
# Reports; never gates. Every path exits 0, so the lint job's verdict is
# unchanged by what the detector finds: the promotion window measures these
# annotations before anything is allowed to block on them. That is also why
# this step carries no `continue-on-error` and no aggregator feed row: a step
# that cannot fail needs neither.
#
# The detector is the ai-slop audit skill's own
# (plugins/ai-slop/skills/audit/scripts/detect.sh), invoked over the changed
# markdown only, so a finding that predates the pull request is never charged
# to it. The event branch is HERE rather than in the workflow's `if:` because a
# push has no base ref to diff against and a step cannot carry both an event
# gate and the docs-only resolver's.
#
# The annotation cap is 50. GitHub renders at most a few dozen annotations per
# step, and a pull request that would exceed the cap is better served by the
# total on the summary line than by a wall the reader scrolls past.
set -u

PROG="ai-slop-report.sh"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECTOR="${AI_SLOP_DETECTOR:-$SELF_DIR/../plugins/ai-slop/skills/audit/scripts/detect.sh}"
CAP=50

WORKDIR=""
finish() {
  if [[ -n "$WORKDIR" ]] && [[ -d "$WORKDIR" ]]; then
    rm -rf "$WORKDIR"
  fi
  exit 0
}
trap finish EXIT

notice() { printf '::notice::%s\n' "$*"; }

main() {
  local base="${1:-}" event="${GITHUB_EVENT_NAME:-}"

  if [[ "$event" != "pull_request" ]]; then
    notice "$PROG: declined on a ${event:-unknown} event; there is no base ref to diff against."
    return 0
  fi
  if [[ -z "$base" ]]; then
    notice "$PROG: declined: no base ref was given."
    return 0
  fi
  if ! git rev-parse --verify --quiet "$base" >/dev/null 2>&1; then
    notice "$PROG: declined: the base ref <$base> does not resolve in this checkout."
    return 0
  fi
  if [[ ! -x "$DETECTOR" ]] && [[ ! -f "$DETECTOR" ]]; then
    notice "$PROG: declined: the ai-slop detector is not in this checkout ($DETECTOR)."
    return 0
  fi

  WORKDIR=$(mktemp -d) || {
    notice "$PROG: declined: cannot create a temporary directory."
    return 0
  }

  local paths="$WORKDIR/paths.txt" findings="$WORKDIR/findings.txt" files
  git diff --name-only --diff-filter=ACMR "$base...HEAD" -- '*.md' >"$paths" 2>/dev/null || : >"$paths"
  files=$(awk 'NF > 0' "$paths" | wc -l | tr -d ' ')
  if [[ "$files" -eq 0 ]]; then
    notice "$PROG: the pull request changes no markdown file; nothing scanned."
    return 0
  fi

  if ! bash "$DETECTOR" --paths-file "$paths" >"$findings" 2>"$WORKDIR/err"; then
    notice "$PROG: the detector reported a usage error; nothing annotated. $(tr '\n' ' ' <"$WORKDIR/err")"
    return 0
  fi

  annotate "$findings" "$files"
  return 0
}

# annotate <findings> <file-count> — one `::warning file=,line=::` per finding
# up to the cap, then the total. `%` is percent-escaped because a workflow
# command reads `%xx` in its message as an escape sequence.
annotate() {
  local findings="$1" files="$2" total

  awk -v cap="$CAP" '
    /^Finding: / {
      if (emitted >= cap) next
      i = index($0, "rule="); j = index($0, " file=")
      k = index($0, " line="); m = index($0, " fired="); n = index($0, " excerpt=")
      if (i == 0 || j == 0 || k == 0 || m == 0 || n == 0) next
      rule = substr($0, i + 5, j - (i + 5))
      file = substr($0, j + 6, k - (j + 6))
      line = substr($0, k + 6, m - (k + 6))
      excerpt = substr($0, n + 9)
      gsub(/%/, "%25", excerpt)
      gsub(/%/, "%25", rule)
      printf "::warning file=%s,line=%s::%s: %s\n", file, line, rule, excerpt
      emitted++
    }
  ' "$findings"

  total=$(awk '/^Finding: / { n++ } END { print n + 0 }' "$findings")

  if [[ "$total" -eq 0 ]]; then
    notice "$PROG: no ai-slop findings in $files changed markdown file(s)."
  elif [[ "$total" -gt "$CAP" ]]; then
    notice "$PROG: $total ai-slop finding(s) in $files changed markdown file(s); the first $CAP are annotated above. Run /ai-slop:audit for the rest."
  else
    notice "$PROG: $total ai-slop finding(s) in $files changed markdown file(s). Advisory: this step turns no check red."
  fi
  return 0
}

main "$@"
