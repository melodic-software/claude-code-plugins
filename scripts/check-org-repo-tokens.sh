#!/usr/bin/env bash
# Rule: https://github.com/melodic-software/claude-code-plugins/blob/main/docs/plugin-philosophy.md#design-boundary
set -uo pipefail

ORG=melodic-software
OWN_REPO=claude-code-plugins

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
ROOT="${ORG_REPO_TOKENS_ROOT:-$SCRIPT_DIR/..}"
case "${1-}" in
"" | --check) ;;
*)
  echo "usage: check-org-repo-tokens.sh [--check]" >&2
  exit 2
  ;;
esac
cd "$ROOT" || {
  echo "check-org-repo-tokens: cannot enter root: $ROOT" >&2
  exit 2
}
if ! command -v git >/dev/null 2>&1; then
  echo "check-org-repo-tokens: git not found; the tracked plugin files cannot be listed" >&2
  exit 2
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "check-org-repo-tokens: $ROOT is not inside a git work tree" >&2
  exit 2
fi
ALLOW="${ORG_REPO_TOKENS_ALLOW:-scripts/org-repo-tokens-allow.tsv}"
if [[ ! -r "$ALLOW" ]]; then
  echo "check-org-repo-tokens: allow file not readable: $ALLOW" >&2
  exit 2
fi

hits=$(git grep -n -I -E "$ORG(/|\.github\.io/)[A-Za-z0-9._-]+" -- plugins/ \
  ':!plugins/*/CHANGELOG.md' ':!plugins/*/.claude-plugin/plugin.json' ':!*.test.*' \
  ':!*/evals/*' ':!*/tests/*' ':!*/test/*' ':!*/fixtures/*' ':!*/test_*.py')
rc=$?
if ((rc > 1)); then
  echo "check-org-repo-tokens: git grep failed (exit $rc)" >&2
  exit 2
fi

printf '%s\n' "$hits" | LC_ALL=C awk -v org="$ORG" -v own="$OWN_REPO" -v allow="$ALLOW" '
BEGIN {
  FS = "\t"
  while ((getline line < allow) > 0) {
    if (line ~ /^#/ || line == "") continue
    n = split(line, f, "\t")
    if (n < 4 || f[3] !~ /^[0-9]+$/ || f[4] == "") {
      printf "check-org-repo-tokens: %s: malformed entry (want path, token, count, reason): %s\n", allow, line > "/dev/stderr"
      bad = 1
      continue
    }
    allowed[f[1] SUBSEP f[2]] = f[3]
  }
  if (bad) exit 2
  own_link = "github\\.com/" org "/" own "/(blob|tree|issues|pull|discussions|releases|commit|compare)/"
  install = "marketplace add " org "/" own
  token = org "(/|\\.github\\.io/)[A-Za-z0-9._-]+"
}
$0 == "" { next }
{
  i = index($0, ":"); path = substr($0, 1, i - 1); rest = substr($0, i + 1)
  j = index(rest, ":"); lineno = substr(rest, 1, j - 1); text = substr(rest, j + 1)
  if (text ~ /Pointer:|Basis:|As of/) next
  gsub(own_link, "", text)
  gsub(install, "", text)
  while (match(text, token)) {
    t = substr(text, RSTART, RLENGTH)
    sub(/\.git$/, "", t)
    k = path SUBSEP t
    count[k]++
    where[k] = where[k] " " lineno
    text = substr(text, RSTART + RLENGTH)
  }
}
END {
  if (bad) exit 2
  for (k in count) {
    split(k, p, SUBSEP)
    a = (k in allowed) ? allowed[k] : 0
    if (count[k] > a) {
      printf "%s: %d occurrence(s) of %s (allowed %d), line(s)%s\n", p[1], count[k], p[2], a, where[k] > "/dev/stderr"
      fail++
    }
  }
  for (k in allowed) {
    c = (k in count) ? count[k] : 0
    if (c < allowed[k]) {
      split(k, p, SUBSEP)
      printf "notice: %s allows %d of %s, now %d: lower or remove the entry\n", p[1], allowed[k], p[2], c
    }
  }
  if (fail) {
    printf "check-org-repo-tokens: %d file/token pair(s) name a repository of this organization in shipped plugin content. Cite it for a reader (a Pointer: or Basis: line, or a link into this repository), make the value a setting, or add a counted entry with a reason to %s.\n", fail, allow > "/dev/stderr"
    exit 1
  }
  print "check-org-repo-tokens: no unexcused organization repository token in shipped plugin content"
}'
