#!/bin/sh
# GENERATED from lib/resolve-convention-pattern.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Resolve the ENFORCEMENT pattern for a source-control convention key
# (`subject_pattern` / `pr_title_pattern`) to a POSIX-ERE regex a hook can hand
# straight to `[[ =~ ]]` or `grep -E`, cross-platform.
#
# WHY THIS EXISTS: the convention surface (`.claude/source-control.md`, one
# `## <key>` H2 per key) is authored for a MODEL to read — its `subject_pattern`
# value may be the keyword `Conventional Commits` or a regex in PCRE dialect
# (`(?:…)`, `\d`). A blocking hook cannot evaluate that: `grep -E` chokes on
# `(?:`, and neither ERE engine knows `\d`. This centralizes the read + the
# dialect normalization once, so `block-noncanonical-commit`, the CC-layer
# content gate, and the opt-in `commit-msg` hook all enforce the SAME pattern
# the SAME way — no per-hook re-fork, no drift.
#
# POSIX sh, so the commit-msg hook runs it with `sh`, needs no bash beside that
# sh, and never starts a bash by name: on Windows that can be System32's WSL
# launcher. It runs the same under bash.
#
# ENFORCEMENT ≠ DRAFTING — the policy-floor contract:
#   Enforcement reads the TEAM-TRACKED layer ONLY:
#   `${REPO_ROOT}/.claude/source-control.md`. The user-global
#   (`~/.claude/source-control.md`) and gitignored local
#   (`.claude/source-control.local.md`) overlays are DRAFTING inputs the model
#   merges per `reference/config-resolution.md`; a blocking gate never reads
#   them. That is the floor by construction: a personal/gitignored file cannot
#   weaken what the gate enforces because the gate never looks at it, and
#   "is regex A stricter than B" is undecidable so no merge could honor "tighten
#   only" anyway. A team with no tracked pattern gets NO enforcement (never the
#   bundled Conventional Commits default — that default is not lane-1-eligible,
#   so gating an un-opted-in repo against it violates the two-lane posture).
#
# SINGLE SOURCE OF TRUTH: lib/resolve-convention-pattern.sh at the marketplace
# repo root. Copies materialized into consuming plugins exist only because
# installed plugins are cache-isolated and must be self-contained — never edit a
# copy. Edit the source and run scripts/sync-shared-copies.sh; CI rejects
# drifted copies. Owner contract: docs/conventions/commit-convention/.
#
# Usage:
#   resolve-convention-pattern.sh <repo_root> <subject_pattern|pr_title_pattern>
#
# Output: the resolved ERE regex on stdout (no trailing newline sensitivity), or
#   NOTHING when the key is unresolved OR resolves to a pattern that cannot be
#   expressed in ERE. A non-enforceable pattern additionally writes a one-line
#   diagnostic to stderr. Exit status:
#     0  a pattern was emitted (enforce it)
#     1  no enforcement (unresolved, or non-ERE-expressible — stdout empty)
#     2  usage error
# shellcheck shell=sh
set -u

# The bundled Conventional Commits pattern — the ONE place the `Conventional
# Commits` keyword expands, so the model's interpretation and every hook's regex
# cannot drift. Mirrors /source-control:commit's documented expansion and is
# already pure ERE (capturing groups, no `\d`).
readonly CC_ERE='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+'
# shellcheck disable=SC2016  # backticks are a literal part of the deferral marker, not a substitution
readonly PR_DEFERRAL='Same as `subject_pattern`.'

# Well-known default path for the neutral convention SSOT — the marketplace's
# own dogfooded docs/conventions/<concern>/ layout. When the team file declares
# no explicit convention_source pointer, the resolver probes this path so the
# common case reads ONE tool-agnostic file with no markdown pointer-parse. An
# explicit pointer always overrides it; see the pointer-resolution block below.
readonly WELL_KNOWN_NEUTRAL="docs/conventions/source-control/commit-convention.yml"

case "${1:-}" in
--help | -h)
  # Stop at the first non-comment line rather than a fixed line number: the
  # header outgrew the hardcoded 40 and the banner silently lost its whole exit
  # status list. A blank-line terminator will not work here, because the header
  # runs straight into `set -u` with no blank line between them. The linter's
  # directive line is not for the reader, so it is skipped.
  awk 'NR > 1 { if ($0 !~ /^#/) exit; if ($0 ~ /^# shellcheck /) next; sub(/^# ?/, ""); print }' "$0"
  exit 0
  ;;
*) ;;
esac

repo_root="${1:-}"
key="${2:-}"

if [ -z "$repo_root" ] || [ -z "$key" ]; then
  echo "resolve-convention-pattern: usage: resolve-convention-pattern.sh <repo_root> <subject_pattern|pr_title_pattern>" >&2
  exit 2
fi
case "$key" in
subject_pattern | pr_title_pattern) ;;
*)
  echo "resolve-convention-pattern: key must be subject_pattern or pr_title_pattern, got '$key'" >&2
  exit 2
  ;;
esac

# Team-tracked layer only — the enforcement authority (see header).
readonly TEAM_FILE="$repo_root/.claude/source-control.md"

# --- Neutral convention SSOT (docs/conventions/commit-convention/, #1141) ---
# The team file MAY declare `## convention_source` naming a repo-relative
# flat-scalar YAML file (the tool-agnostic SSOT other consumers — commit-msg
# hooks, CI — read with one sed). When declared, that file is authoritative for
# the machine keys it carries; a key it omits falls back to the team markdown
# H2. The pointer is honored from the TEAM file only (same policy floor — a
# gitignored overlay must not redirect the gate), and a declared-but-broken
# pointer FAILS CLOSED to no-enforcement with a diagnostic rather than silently
# re-reading markdown values migration may have retired.
#
# POSIX sh has no `local`, so each function's working variables carry its own
# prefix and every caller that keeps a result reads it through `$( )`.

# h2_value <file> <key>: first non-empty body line under `## <key>`,
# CR-stripped. Empty when the section is absent or bodyless. Awk over sed:
# needs section-state, not a line match.
h2_value() {
  [ -f "$1" ] || return 0
  awk -v key="$2" '
    BEGIN { in_section = 0 }
    /^##[[:space:]]/ {
      # A new H2 ends the target section.
      hdr = $0; sub(/^##[[:space:]]+/, "", hdr); sub(/[[:space:]]+$/, "", hdr)
      in_section = (hdr == key) ? 1 : 0
      next
    }
    in_section {
      line = $0; gsub(/\r/, "", line)
      if (line ~ /^[[:space:]]*$/) next          # skip blank lines before the value
      sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
      print line; exit                            # first non-empty body line wins
    }
  ' "$1"
}

# yaml_value <file> <key>: first matching flat-scalar value for a key from the
# neutral YAML file: `^<key>:` at column 0, CR-stripped, surrounding whitespace
# trimmed, ONE pair of matching surrounding quotes ('…' or "…") removed. No YAML
# quote-escape processing — the one-sed extraction contract other consumers rely
# on can't either, so the seam doc tells authors to write patterns that need no
# escaping. Full-line `#` comments never match the key anchor; trailing `#` text
# is NOT stripped (a regex may legitimately contain `#`).
yaml_value() {
  [ -f "$1" ] || return 0
  yaml_line="$(grep -m1 -E "^${2}:" "$1" | tr -d '\r')"
  [ -n "$yaml_line" ] || return 0
  yaml_v="${yaml_line#"${2}":}"
  yaml_v="${yaml_v#"${yaml_v%%[![:space:]]*}"}"
  yaml_v="${yaml_v%"${yaml_v##*[![:space:]]}"}"
  case "$yaml_v" in
  \'*\' | \"*\")
    yaml_v="${yaml_v#?}"
    yaml_v="${yaml_v%?}"
    ;;
  *) ;;
  esac
  printf '%s' "$yaml_v"
}

# Resolve the optional neutral-file pointer. Sets NEUTRAL_FILE (empty when no
# pointer is declared). A declared pointer that cannot be honored — absolute or
# traversal path, missing file, or a dialect other than posix-ere — disables
# enforcement (exit 1) with a diagnostic: fail closed, never fall back.
NEUTRAL_FILE=""
ptr="$(h2_value "$TEAM_FILE" "convention_source")"
# Precedence: an explicit convention_source (rung 1) always wins. Absent one,
# probe the well-known default path (rung 2) so the common case needs no pointer
# at all; absent that too, resolution falls through to the markdown H2 (rung 3)
# with full back-compat. The default is a plain repo-relative path and passes the
# same safety checks below as any pointer.
#
# POLICY FLOOR: the well-known rung activates ONLY when the file is git-TRACKED.
# Unlike an explicit convention_source — whose opt-in is a tracked edit to the
# team file — this rung has no other tracked signal, so honoring an untracked or
# gitignored file at this path would let a generated/local artifact silently
# override team policy (or, if malformed, disable enforcement) on one checkout.
# git unavailable, or the file untracked -> skip this rung and fall through to
# the markdown H2 (fail toward the prior behavior, never toward the hole).
if [ -z "$ptr" ] && [ -f "$repo_root/$WELL_KNOWN_NEUTRAL" ] &&
  git -C "$repo_root" ls-files --error-unmatch -- "$WELL_KNOWN_NEUTRAL" >/dev/null 2>&1; then
  ptr="$WELL_KNOWN_NEUTRAL"
fi
if [ -n "$ptr" ]; then
  case "$ptr" in
  /* | [A-Za-z]:* | *\\* | *..*)
    # Repo-relative forward-slash paths only: no absolute paths (POSIX or
    # drive-lettered), no backslash separators, no `..` traversal — a tracked
    # pointer must not read outside the repository the gate governs.
    printf '%s\n' "resolve-convention-pattern: convention_source '$ptr' is not a plain repo-relative path (absolute, backslash, or '..' segment); enforcement disabled." >&2
    exit 1
    ;;
  *) ;; # plain repo-relative path — proceed
  esac
  NEUTRAL_FILE="$repo_root/$ptr"
  if [ ! -f "$NEUTRAL_FILE" ]; then
    printf '%s\n' "resolve-convention-pattern: convention_source declares '$ptr' but no such file exists under the repo root; enforcement disabled (fix the pointer or restore the file)." >&2
    exit 1
  fi
  # The lexical checks above don't stop a symlink escape: a repo-relative
  # pointer can name a symlink (or sit under a symlinked directory) whose
  # physical target is outside the repository, letting untracked external
  # content steer the gate. Require a REGULAR file whose physical directory
  # (pwd -P canonicalizes every symlinked path segment) stays under the
  # physical repo root. Pure shell on purpose — the vendored hook copy cannot
  # assume realpath exists on every consumer machine.
  if [ -L "$NEUTRAL_FILE" ]; then
    printf '%s\n' "resolve-convention-pattern: convention_source '$ptr' is a symlink; the neutral file must be a regular tracked file — enforcement disabled." >&2
    exit 1
  fi
  canon_root="$(cd "$repo_root" 2>/dev/null && pwd -P)"
  canon_dir="$(cd "$(dirname "$NEUTRAL_FILE")" 2>/dev/null && pwd -P)"
  # A literal prefix test, not a glob: the quoted "$canon_prefix" in the
  # removal below matches its own bytes, so a glob metacharacter in the
  # physical repo path (`[`, `*`, `?`) is compared, never interpreted. When
  # "$canon_dir/" does not start with "$canon_prefix", nothing is removed.
  canon_prefix="$canon_root/"
  canon_dir_slash="$canon_dir/"
  if [ -z "$canon_root" ] || [ -z "$canon_dir" ] ||
    [ "${canon_dir_slash#"$canon_prefix"}" = "$canon_dir_slash" ]; then
    printf '%s\n' "resolve-convention-pattern: convention_source '$ptr' resolves outside the repository root (symlinked path segment); enforcement disabled." >&2
    exit 1
  fi
  dialect="$(yaml_value "$NEUTRAL_FILE" dialect)"
  if [ -n "$dialect" ] && [ "$dialect" != "posix-ere" ]; then
    printf '%s\n' "resolve-convention-pattern: convention_source file declares dialect '$dialect'; enforcement consumes posix-ere only — enforcement disabled." >&2
    exit 1
  fi
fi

# check_neutral_key <key>: a key the neutral file CARRIES must hold a value.
# Present-but-empty (`subject_pattern:` or `subject_pattern: ''`) is a
# configuration error, not an omission — silently falling back to the markdown
# H2 would enforce a stale pattern the migration meant to retire. Runs at top
# level (not inside a command substitution) so the exit reaches the caller.
check_neutral_key() {
  [ -n "$NEUTRAL_FILE" ] || return 0
  grep -q -E "^${1}:" "$NEUTRAL_FILE" || return 0
  [ -n "$(yaml_value "$NEUTRAL_FILE" "$1")" ] && return 0
  printf '%s\n' "resolve-convention-pattern: convention_source file carries '$1' with an empty value; a carried key must hold a value (delete the line to fall back to the markdown H2) — enforcement disabled." >&2
  exit 1
}

# team_value <key>: the team-layer value for a machine key: the neutral file
# when the pointer is declared AND that file carries the key; the team markdown
# H2 otherwise.
team_value() {
  if [ -n "$NEUTRAL_FILE" ]; then
    team_v="$(yaml_value "$NEUTRAL_FILE" "$1")"
    if [ -n "$team_v" ]; then
      printf '%s' "$team_v"
      return 0
    fi
  fi
  h2_value "$TEAM_FILE" "$1"
}

# Enforcement patterns are POSIX ERE, NOT PCRE. The resolver does not translate
# a pattern (translating PCRE->ERE by string rewriting is unsound — bracket
# expressions, POSIX classes, and escaped backslashes all break naive
# substitution); it accepts a value that is already ERE and rejects one that
# uses a PCRE-only construct, so a pattern the ERE engines would misread takes
# the documented no-enforcement path instead of silently enforcing the wrong
# thing. A team wanting a digit class writes `[0-9]`, not `\d`.
is_non_ere() {
  case "$1" in
  # Any `(?...)` group — non-capturing `(?:`, lookaround `(?=`/`(?!`, named
  # `(?<`/`(?P<`. POSIX ERE has none of these.
  *'(?'*) return 0 ;;
  # Any backslash followed by a letter or digit: the shorthand classes
  # \d \w \s \D \S \W, the anchors \A \Z \z \b \B, control escapes \t \n \r …,
  # and backreferences \1..\9. POSIX ERE reads each as the literal character.
  # A backslash before a metacharacter (`\.`, `\(`, `\+`) is valid ERE and stays
  # allowed.
  *\\[a-zA-Z0-9]*) return 0 ;;
  *) return 1 ;;
  esac
}

# raw_value <key>: one key's raw value from the team layer (neutral file first
# when the pointer is declared — team_value), expanding the CC keyword. The
# keyword and the deferral marker work identically on both surfaces: one
# literal each, no per-surface variants to drift.
raw_value() {
  raw_v="$(team_value "$1")"
  [ -n "$raw_v" ] || return 0
  if [ "$raw_v" = "Conventional Commits" ]; then
    printf '%s' "$CC_ERE"
  else
    printf '%s' "$raw_v"
  fi
}

# Present-but-empty neutral keys fail closed BEFORE resolution (top-level so
# the exit propagates; both keys checked for pr_title_pattern since its
# deferral marker re-reads subject_pattern).
check_neutral_key "$key"
if [ "$key" = "pr_title_pattern" ]; then
  check_neutral_key "subject_pattern"
fi

value="$(raw_value "$key")"

# pr_title_pattern deferral: `Same as `subject_pattern`.` enforces the effective
# subject pattern. Resolve against the raw (pre-expansion) pr_title value.
if [ "$key" = "pr_title_pattern" ]; then
  raw_pr="$(team_value "pr_title_pattern")"
  if [ "$raw_pr" = "$PR_DEFERRAL" ]; then
    value="$(raw_value "subject_pattern")"
  fi
fi

# Unresolved -> no enforcement (exit 1, stdout empty). Never fall back to CC_ERE.
[ -n "$value" ] || exit 1

if is_non_ere "$value"; then
  printf '%s\n' "resolve-convention-pattern: $key is not POSIX ERE (a PCRE-only construct: a (?...) group, or a backslash-letter/backslash-digit escape such as \\d \\A \\t \\1); enforcement disabled -- author the pattern in POSIX ERE (e.g. [0-9] not \\d) to enable the gate." >&2
  exit 1
fi

# Safety net: reject anything that still does not compile as POSIX ERE (e.g. an
# unbalanced `^[$`) so a bad config takes the no-enforcement path, never a hook
# that would then error or wrongly block on it. grep -E exits >=2 on an invalid
# expression, 0/1 on a valid one.
grep_rc=0
grep -E -- "$value" </dev/null >/dev/null 2>&1 || grep_rc=$?
if [ "$grep_rc" -ge 2 ]; then
  printf '%s\n' "resolve-convention-pattern: $key does not compile as POSIX ERE; enforcement disabled." >&2
  exit 1
fi

printf '%s\n' "$value"
exit 0
