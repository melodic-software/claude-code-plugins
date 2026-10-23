#!/usr/bin/env bash
# guardrails pre-commit-content sha256:619d1826b86672be22ccaa584b1b2503fafcb799e8547149406d6118dc4b6100
# guardrails-pre-commit-content v2
# guardrails pre-commit check: secrets and machine-specific paths in the lines
# this commit adds.
#
#   pre-commit-content.sh               the staged changes (git runs it as pre-commit)
#   pre-commit-content.sh --worktree    the uncommitted changes against HEAD,
#                                       untracked files included
#
# The write-path-independent layer for what the secret-pattern-detection and
# hardcoded-path-check guards stop on Write and Edit: a shell command, a script
# or another tool can write a file no Claude Code guard sees, and this check
# reads what reaches a commit. It uses the same pattern libraries, installed
# beside this script as entry assets.
#
# Each file is judged the way a Write or Edit of it would be: a new file on its
# whole content, a changed file on the lines the commit adds, read from the
# index (the work tree with --worktree). Every staged path is judged, a
# force-added gitignored one included; --worktree leaves out untracked
# gitignored files. Skipped: symbolic links, submodules and files over 1 MiB.
# A file holding a NUL byte (whatever a `-diff` attribute says) is judged
# whole for secrets only. The two
# guards' path exemptions apply (tests/fixtures for secrets only).
#
# Findings print as "<path>:<line>: <message>" on stderr and exit 1. The
# message says how to fix the content; this hook never suggests skipping it.
set -uo pipefail

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.
lib="$here/check-lib.sh"
[[ -f "$lib" ]] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../lib/git-hooks/check-lib.sh
. "$lib" || exit 1

# The pattern libraries: beside an installed copy (entry assets), or in the
# plugin's lib/ when run from the plugin itself.
secret_lib="$here/secret-patterns.sh"
[[ -f "$secret_lib" ]] || secret_lib="$here/../lib/secret-detection/secret-patterns.sh"
path_lib="$here/hardcoded-path-patterns.sh"
[[ -f "$path_lib" ]] || path_lib="$here/../lib/path-detection/hardcoded-path-patterns.sh"
# shellcheck source=../lib/secret-detection/secret-patterns.sh
. "$secret_lib" || exit 1
# shellcheck source=../lib/path-detection/hardcoded-path-patterns.sh
. "$path_lib" || exit 1

checks_init pre-commit "$@" || exit 0
MAX_BYTES=1048576

# Hardcoded-path exemptions, as hardcoded-path-check.sh has them.
path_exempt() {
  case "$1" in
  *.claude/hooks/* | *.lefthook/*) return 0 ;;
  *settings.local.json | *CLAUDE.local.md) return 0 ;;
  */.venv/* | .venv/* | */node_modules/* | node_modules/*) return 0 ;;
  *.env.example | *.env.sample | *.env.template) return 0 ;;
  *.claude/skills/*/context/* | *.claude/skills/*/completed/*) return 0 ;;
  */lib/secret-detection/* | */lib/path-detection/*) return 0 ;;
  # The same libraries as this entry's shared-scope assets.
  .githooks/guardrails/secret-patterns.sh | .githooks/guardrails/hardcoded-path-patterns.sh | \
    .githooks/guardrails/machine-path-patterns.sh) return 0 ;;
  *) return 1 ;;
  esac
}

# Secret exemptions, as secret-pattern-detection.sh has them: the path set
# plus test fixtures.
secret_exempt() {
  case "$1" in
  *tests/fixtures/* | *tests/testdata/* | *Tests/fixtures/* | *Tests/testdata/*) return 0 ;;
  *) path_exempt "$1" ;;
  esac
}

# The repository path itself is a finding, unless the checkout sits at, above
# or below the home directory, where every home path would match it.
scan_root="$PWD"
home="${HOME:-${USERPROFILE:-}}"
home="${home%/}"
if [[ -n "$home" ]]; then
  case "$PWD/" in
  "$home/" | "$home"/*) scan_root="" ;;
  *) ;;
  esac
  case "$home/" in
  "$PWD"/*) scan_root="" ;;
  *) ;;
  esac
fi

# index_mode <path>: the staged mode, empty when the path is not staged.
index_mode() {
  local entry
  entry="$(git ls-files -s -- ":(literal)$1" 2>/dev/null)"
  printf '%s' "${entry%% *}"
}

file_size() {
  if [[ "$CHECKS_MODE" == worktree ]]; then
    wc -c <"$1" | tr -d ' '
  else
    git cat-file -s ":$1" 2>/dev/null || echo 0
  fi
}

checks_changed_lines

# added_only <path>: the file with every line the commit does not add blanked,
# so line numbers hold and only added text is scanned.
added_only() {
  awk -v want="$1" -v ranges="$CHECKS_TMP/ranges" '
    BEGIN { while ((getline l < ranges) > 0) { split(l, r, "\t"); if (r[1] == want) { n++; s[n] = r[2] + 0; e[n] = r[3] + 0 } } }
    { keep = 0; for (i = 1; i <= n; i++) if (NR >= s[i] && NR <= e[i]) { keep = 1; break } print (keep ? $0 : "") }'
}

# secret_findings <path>: secrets::scan_text output on stdin, as findings.
secret_findings() {
  sed -n 's/^\(.*\) (line \([0-9,]*\))$/\2 \1/p' |
    while read -r nums label; do
      for n in ${nums//,/ }; do
        printf '%s:%s: secret or credential pattern: %s\n' "$1" "$n" "$label"
      done
    done
}

out="$CHECKS_TMP/findings"
whole="$CHECKS_TMP/findings-whole"
: >"$out"
: >"$whole"
while IFS= read -r -d '' f; do
  if [[ "$CHECKS_MODE" == worktree ]]; then
    [[ -f "$f" && ! -L "$f" ]] || continue
  else
    case "$(index_mode "$f")" in
    100644 | 100755) ;;
    *) continue ;;
    esac
  fi
  (($(file_size "$f") <= MAX_BYTES)) || continue
  if checks_has_nul "$f"; then
    # A NUL byte must not hide a secret: scan the whole raw content for the
    # secret patterns twice, each NUL read as a space, then each NUL deleted
    # (UTF-16LE text puts one after every ASCII byte). Both keep newlines, so
    # line numbers hold; the second pass reports only labels the first missed.
    # Path patterns are not judged here, so an ordinary binary still commits.
    secret_exempt "$f" && continue
    text="$(checks_file_text "$f" | tr '\0' ' '; printf x)"
    packed="$(checks_file_text "$f" | tr -d '\0'; printf x)"
    {
      secrets::scan_text "${text%x}"
      echo --
      secrets::scan_text "${packed%x}"
    } | awk '$0 == "--" { p2 = 1; next }
      { l = $0; sub(/ \(line [0-9,]*\)$/, "", l) }
      p2 && (l in seen) { next }
      !p2 { seen[l] } { print }' | secret_findings "$f" >>"$whole"
    continue
  fi
  sink="$out"
  if [[ "$f" == *[\"\\[:cntrl:]]* ]]; then
    # Git quotes such a name whatever core.quotePath says, so the range table
    # holds no entry for it: the file is judged whole, past the range filter.
    text="$(checks_file_text "$f"; printf x)"
    sink="$whole"
  else
    text="$(checks_file_text "$f" | added_only "$f"; printf x)"
  fi
  text="${text%x}"
  [[ -n "${text//[[:space:]]/}" ]] || continue

  if ! secret_exempt "$f"; then
    secrets::scan_text "$text" | secret_findings "$f" >>"$sink"
  fi
  if ! path_exempt "$f"; then
    hpp::scan_text "$text" "$scan_root" "$PWD/$f" |
      awk -v f="$f" '
        /^[^ \t].*:$/ && !/^[0-9]+:/ { label = substr($0, 1, length($0) - 1); next }
        match($0, /^[0-9]+:/) { printf "%s:%s: machine-specific path (%s)\n", f, substr($0, 1, RLENGTH - 1), label }' >>"$sink"
  fi
done < <(checks_files)

{
  checks_filter_findings <"$out"
  cat "$whole"
} | sort -u -t: -k1,1 -k2,2n >"$CHECKS_TMP/blocking"
[[ -s "$CHECKS_TMP/blocking" ]] || exit 0
cat "$CHECKS_TMP/blocking" >&2
printf 'guardrails: remove the secrets or machine-specific paths above from the change (use a placeholder, an environment variable or a portable path), then commit again.\n' >&2
exit 1
