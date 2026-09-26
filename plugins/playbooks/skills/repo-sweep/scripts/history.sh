#!/usr/bin/env bash
# Recommend run, rerun, or rerun-optional per catalog entry from what last ran in this repo.
#
#   history.sh <catalog-file>   one TSV row per entry, in catalog order: id, recommendation, reason
#
# Last version run per skill, first source holding the skill wins:
#   1. Merged sweep PRs (head branch chore/repo-sweep-*), newest merge first: the done lines
#      ("- [x] <id>: <skill@version, ...>, ...") between the repo-sweep markers. Survives
#      squash merges.
#   2. Playbook-Step trailers on the default branch (origin/HEAD, else HEAD), newest first.
# gh absent, unauthenticated, or failing: trailers only, with a warning on stderr.
# Current versions come from skill-version.sh (same env overrides).
#
# recommendation (reason names the skills behind it):
#   run             a skill of the entry never ran
#   rerun           a skill ran at another version than the current one
#   rerun-optional  every skill ran at its current version, or its current version is
#                   @builtin or @unknown (not comparable, so never rerun)
# not-applicable is the caller's applies-when judgment; history.sh never prints it.
# Exit: 0 ok; 1 catalog error; 2 usage.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ $# -ne 1 || ! -f $1 ]]; then
  printf 'usage: history.sh <catalog-file>\n' >&2
  exit 2
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bash "$dir/catalog.sh" "$1" >"$tmp/rows"

# Last-run lines, "<skill>@<version>", newest and highest-priority source first.
if prs=$(gh pr list --state merged --search "head:chore/repo-sweep-" --limit 1000 \
  --json headRefName,body,mergedAt,isCrossRepository 2>/dev/null); then
  jq -r '[.[] | select((.isCrossRepository | not) and (.headRefName | startswith("chore/repo-sweep-")))]
    | sort_by(.mergedAt) | reverse | .[].body' <<<"$prs" | awk '
    { sub(/\r$/, "") }
    /^<!-- repo-sweep:begin / { inb = 1; next }
    /^<!-- repo-sweep:end -->/ { inb = 0; next }
    inb && /^- \[[xX]\] / {
      n = split(substr($0, index($0, ": ") + 2), t, /, */)
      for (i = 1; i <= n; i++) if (t[i] ~ /^[^ @]+@[^ @]+$/) print t[i]
    }' >"$tmp/last"
else
  printf 'history.sh: gh unavailable or unauthenticated; using commit trailers only\n' >&2
  : >"$tmp/last"
fi
ref=HEAD
git rev-parse -q --verify origin/HEAD >/dev/null && ref=origin/HEAD
git log --format='%(trailers:key=Playbook-Step,valueonly)' "$ref" | awk 'NF' >>"$tmp/last"
# PR bodies and trailers are editable text that ends up in the agent's context and a new PR body.
grep -E '^[a-z0-9-]+(:[a-z0-9-]+)?@[A-Za-z0-9._+-]+$' "$tmp/last" >"$tmp/safe" || true
mv "$tmp/safe" "$tmp/last"

skills=()
while IFS= read -r s; do skills+=("$s"); done < <(awk -F'\t' '{
  n = split($3, s, /, */); for (i = 1; i <= n; i++) print s[i] }' "$tmp/rows" | sort -u)
bash "$dir/skill-version.sh" "${skills[@]+"${skills[@]}"}" >"$tmp/current"

awk -F'\t' -v curf="$tmp/current" -v lastf="$tmp/last" '
function at(line, part,   i) { i = match(line, /@[^@]*$/); return part == 1 ? substr(line, 1, i - 1) : substr(line, i + 1) }
function add(list, item) { return list == "" ? item : list ", " item }
BEGIN {
  while ((getline l < curf) > 0) cur[at(l, 1)] = at(l, 2)
  while ((getline l < lastf) > 0) if (!(at(l, 1) in last)) last[at(l, 1)] = at(l, 2)
  OFS = "\t"
}
{
  run = ""; rerun = ""; same = ""
  n = split($3, s, /, */)
  for (i = 1; i <= n; i++) {
    k = s[i]; c = cur[k]
    if (!(k in last)) run = add(run, k)
    else if (c == "unknown") same = add(same, k "@" last[k] " (current version unknown)")
    else if (c == "builtin" || c == last[k]) same = add(same, k "@" last[k])
    else rerun = add(rerun, k " " last[k] " -> " c)
  }
  if (run != "") print $1, "run", "never ran: " run
  else if (rerun != "") print $1, "rerun", "version changed: " rerun
  else print $1, "rerun-optional", "same version ran: " same
}' "$tmp/rows"
