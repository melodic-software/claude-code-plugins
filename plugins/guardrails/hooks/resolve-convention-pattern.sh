#!/bin/sh
# GENERATED from lib/resolve-convention-pattern.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Resolve the ENFORCEMENT pattern for a source-control convention key
# (`subject_pattern` / `pr_title_pattern`) to a POSIX-ERE regex a hook can hand
# straight to `[[ =~ ]]` or `grep -E`, cross-platform.
#
# WHY THIS EXISTS: the convention value is authored for a MODEL to read: it may
# be the keyword `Conventional Commits` or a regex in PCRE dialect (`(?:…)`,
# `\d`). A blocking hook cannot evaluate that: `grep -E` chokes on `(?:`, and
# neither ERE engine knows `\d`. This centralizes the read + the dialect
# normalization once, so `block-convention-violation` and the opt-in
# `commit-msg` hook enforce the SAME pattern the SAME way — no per-hook re-fork,
# no drift.
#
# WHERE THE TEAM VALUE LIVES, per key, first match wins:
#   1. `docs/conventions/source-control.yaml`, the source-control plugin's team
#      file (ADR 0064), validated by its schema. Read with yaml-subset.awk, the
#      shared YAML-subset parser, which sits beside this script in every copy.
#      Not through parse-concern-value.sh: that reader needs bash, which this
#      script never starts, and it strips a trailing slash, which would change
#      a regex.
#   2. For one release, a key that file lacks is read from the legacy surfaces:
#      the flat-scalar neutral file (an explicit `## convention_source` pointer
#      in `.claude/source-control.md`, else the well-known
#      `docs/conventions/source-control/commit-convention.yml`), then the
#      `## <key>` H2 of `.claude/source-control.md`.
#   A team YAML file counts only while git tracks it.
#
# POSIX sh, so the commit-msg hook runs it with `sh`, needs no bash beside that
# sh, and never starts a bash by name: on Windows that can be System32's WSL
# launcher. It runs the same under bash.
#
# ENFORCEMENT ≠ DRAFTING — the policy-floor contract:
#   Enforcement reads the TEAM-TRACKED layer: the files above. The user-global
#   (`~/.claude/source-control.md`) and gitignored local
#   (`.claude/source-control.local.md`) overlays are DRAFTING inputs the model
#   merges per `reference/config-resolution.md`; a blocking gate never reads
#   them. "Is regex A stricter than B" is undecidable, so no merge of a personal
#   pattern with a team one could honor "tighten only".
#
#   THE PERSONAL LAYER IS FALLBACK-ONLY: `subject_pattern` in
#   `docs/conventions/source-control.local.yaml` (ADR 0075's
#   `<home>/<concern>.local.<ext>`) applies only when the team layer supplies no
#   `subject_pattern`, and is never merged with a team pattern. Adding
#   enforcement where the team sets none only tightens the floor. A team pattern
#   always wins, and a broken or non-ERE team value disables enforcement rather
#   than falling back to the personal one, so the personal file can never weaken
#   or replace a team pattern. The file is read only while git ignores it
#   (`.gitignore`, `.git/info/exclude` or `core.excludesFile`; git never reports
#   a tracked file ignored), and it fails closed on the same checks as the team
#   file. `pr_title_pattern` never reads it, a deferral included: a PR title is
#   the team's record. A git hook cannot read `userConfig`, so this file is the
#   personal source.
#
#   With neither a team pattern nor a personal one there is NO enforcement
#   (never the bundled Conventional Commits default — that default is not
#   lane-1-eligible, so gating an un-opted-in repo against it violates the
#   two-lane posture).
#
# SINGLE SOURCE OF TRUTH: lib/resolve-convention-pattern.sh at the marketplace
# repo root, beside lib/yaml-subset.awk. Copies materialized into consuming
# plugins exist only because installed plugins are cache-isolated and must be
# self-contained — never edit a copy. Edit the source and run
# scripts/sync-shared-copies.sh; CI rejects drifted copies. Owner contract:
# docs/contracts/commit-convention/.
#
# Usage:
#   resolve-convention-pattern.sh [--layer] <repo_root> <subject_pattern|pr_title_pattern>
#
#   --layer   print the repo-relative file that supplied the key's own value
#             instead of the pattern; same exit status and diagnostics
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

# The team file, at the fixed root the source-control plugin reads it from.
readonly TEAM_YAML_REL="docs/conventions/source-control.yaml"
# The personal file beside it, read only where the team sets no subject_pattern.
readonly PERSONAL_YAML_REL="docs/conventions/source-control.local.yaml"
# The legacy markdown team file, read for one release.
readonly LEGACY_MD_REL=".claude/source-control.md"
# Well-known default path for the legacy neutral convention file. When the
# markdown team file declares no explicit convention_source pointer, the
# resolver probes this path; see the pointer-resolution block below.
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

layer_mode=0
if [ "${1:-}" = "--layer" ]; then
  layer_mode=1
  shift
fi

repo_root="${1:-}"
key="${2:-}"

if [ -z "$repo_root" ] || [ -z "$key" ]; then
  echo "resolve-convention-pattern: usage: resolve-convention-pattern.sh [--layer] <repo_root> <subject_pattern|pr_title_pattern>" >&2
  exit 2
fi
case "$key" in
subject_pattern | pr_title_pattern) ;;
*)
  echo "resolve-convention-pattern: key must be subject_pattern or pr_title_pattern, got '$key'" >&2
  exit 2
  ;;
esac

case "$0" in
*/*) self_dir="${0%/*}" ;;
*) self_dir=. ;;
esac
readonly YAML_PARSER="$self_dir/yaml-subset.awk"

readonly TEAM_YAML="$repo_root/$TEAM_YAML_REL"
readonly TEAM_FILE="$repo_root/$LEGACY_MD_REL"

nl='
'
tab="$(printf '\t')"
cr="$(printf '\r')"
bom="$(printf '\357\273\277')"

# POSIX sh has no `local`, so each function's working variables carry its own
# prefix. A function that must stop the run (`exit 1`) is called at top level,
# never inside `$( )`, so the exit reaches the caller; the others hand results
# back in named variables or through `$( )`.

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

# yaml_scalar <key> <line>: sets yaml_v to the flat-scalar value of a `<key>:`
# line from the legacy neutral YAML file: surrounding whitespace trimmed (a CRLF
# line's CR included, since [:space:] holds CR), ONE pair of matching
# surrounding quotes ('…' or "…") removed. No YAML quote-escape processing — the
# one-sed extraction contract other consumers rely on can't either, so the seam
# doc tells authors to write patterns that need no escaping. Trailing `#` text
# is NOT stripped (a regex may legitimately contain `#`).
yaml_scalar() {
  yaml_v="${2#"${1}":}"
  yaml_v="${yaml_v#"${yaml_v%%[![:space:]]*}"}"
  yaml_v="${yaml_v%"${yaml_v##*[![:space:]]}"}"
  case "$yaml_v" in
  \'*\' | \"*\")
    yaml_v="${yaml_v#?}"
    yaml_v="${yaml_v%?}"
    ;;
  *) ;;
  esac
}

# The legacy neutral file's keys, read ONCE (read_neutral) with shell builtins:
# the guard runs this resolver on every commit it judges, and a grep per key
# lookup was most of its process cost. For each key, NEUTRAL_HAS_* is 1 when a
# line starts `<key>:` at column 0 and NEUTRAL_* holds the first such line's
# value. Full-line `#` comments never match a key.
NEUTRAL_HAS_DIALECT=""
NEUTRAL_DIALECT=""
NEUTRAL_HAS_SUBJECT=""
NEUTRAL_SUBJECT=""
NEUTRAL_HAS_PR_TITLE=""
NEUTRAL_PR_TITLE=""

# read_neutral: fill the NEUTRAL_* values from NEUTRAL_FILE. An unreadable file
# is a declared-but-broken pointer: it fails closed (exit 1) with a diagnostic,
# like the sibling pointer checks, rather than falling back to the markdown H2.
# Called at top level (through resolve_legacy) so the exit reaches the caller.
# The -r test keeps a failed redirection from exiting the shell without the
# diagnostic.
read_neutral() {
  [ -n "$NEUTRAL_FILE" ] || return 0
  if [ ! -r "$NEUTRAL_FILE" ]; then
    printf '%s\n' "resolve-convention-pattern: cannot read convention_source file '$ptr'; enforcement disabled (fix the file's permissions)." >&2
    exit 1
  fi
  while IFS= read -r rn_line || [ -n "$rn_line" ]; do
    case "$rn_line" in
    dialect:*)
      [ -z "$NEUTRAL_HAS_DIALECT" ] || continue
      yaml_scalar dialect "$rn_line"
      NEUTRAL_HAS_DIALECT=1
      NEUTRAL_DIALECT="$yaml_v"
      ;;
    subject_pattern:*)
      [ -z "$NEUTRAL_HAS_SUBJECT" ] || continue
      yaml_scalar subject_pattern "$rn_line"
      NEUTRAL_HAS_SUBJECT=1
      NEUTRAL_SUBJECT="$yaml_v"
      ;;
    pr_title_pattern:*)
      [ -z "$NEUTRAL_HAS_PR_TITLE" ] || continue
      yaml_scalar pr_title_pattern "$rn_line"
      NEUTRAL_HAS_PR_TITLE=1
      NEUTRAL_PR_TITLE="$yaml_v"
      ;;
    *) ;;
    esac
  done <"$NEUTRAL_FILE"
}

# neutral_key <key>: sets nk_has and nk_v to the neutral file's NEUTRAL_HAS_ and
# NEUTRAL_ values for a pattern key.
neutral_key() {
  case "$1" in
  subject_pattern)
    nk_has="$NEUTRAL_HAS_SUBJECT"
    nk_v="$NEUTRAL_SUBJECT"
    ;;
  *)
    nk_has="$NEUTRAL_HAS_PR_TITLE"
    nk_v="$NEUTRAL_PR_TITLE"
    ;;
  esac
}

# in_repo_or_exit <repo-relative path> <name>: the file must be a regular file
# whose physical directory stays under the physical repo root, or enforcement
# is disabled (exit 1). Lexical path checks don't stop a symlink escape: a
# repo-relative path can name a symlink (or sit under a symlinked directory)
# whose physical target is outside the repository, letting untracked external
# content steer the gate. pwd -P canonicalizes every symlinked path segment.
# Pure shell on purpose — the vendored hook copy cannot assume realpath exists
# on every consumer machine.
in_repo_or_exit() {
  ir_file="$repo_root/$1"
  if [ -L "$ir_file" ]; then
    printf '%s\n' "resolve-convention-pattern: $2 '$1' is a symlink; the file must be a regular file — enforcement disabled." >&2
    exit 1
  fi
  canon_root="$(cd "$repo_root" 2>/dev/null && pwd -P)"
  canon_dir="$(cd "${ir_file%/*}" 2>/dev/null && pwd -P)"
  # A literal prefix test, not a glob: the quoted "$canon_prefix" in the
  # removal below matches its own bytes, so a glob metacharacter in the
  # physical repo path (`[`, `*`, `?`) is compared, never interpreted. When
  # "$canon_dir/" does not start with "$canon_prefix", nothing is removed.
  canon_prefix="$canon_root/"
  canon_dir_slash="$canon_dir/"
  if [ -z "$canon_root" ] || [ -z "$canon_dir" ] ||
    [ "${canon_dir_slash#"$canon_prefix"}" = "$canon_dir_slash" ]; then
    printf '%s\n' "resolve-convention-pattern: $2 '$1' resolves outside the repository root (symlinked path segment); enforcement disabled." >&2
    exit 1
  fi
}

# --- The team file: docs/conventions/source-control.yaml (ADR 0064) ---
# Read only while git tracks it: an untracked or gitignored file at that path is
# a generated/local artifact, and honoring it would let one checkout override
# team policy (or, if malformed, disable enforcement). git unavailable, or the
# file untracked -> the file is not a layer. A tracked file the shared parser
# rejects (a duplicate key included) disables enforcement with a diagnostic,
# never a fallback to legacy values the migration retired. The records are read
# once; every lookup below is shell builtins.
#
# One YAML file is loaded at a time: the team file here, and the personal file
# later, once every team lookup is done. YAML_REL and YAML_PATH name the loaded
# file for yaml_lookup, check_yaml_key, yaml_bare_key and check_yaml_dialect.
YAML_ACTIVE=0
YAML_RECORDS=""
YAML_REL=""
YAML_PATH=""

# load_yaml <repo-relative path> <name>: parse the file into YAML_RECORDS and
# make it the loaded file, or disable enforcement (exit 1) with a diagnostic
# when it is a symlink or leaves the repository, its parser is missing, or the
# parser rejects it. Called at top level so the exit reaches the caller.
load_yaml() {
  YAML_REL="$1"
  YAML_PATH="$repo_root/$1"
  in_repo_or_exit "$1" "$2"
  if [ ! -f "$YAML_PARSER" ]; then
    printf '%s\n' "resolve-convention-pattern: cannot read $1: its parser, yaml-subset.awk, is not beside the resolver; enforcement disabled." >&2
    exit 1
  fi
  # On stdin, so awk never reads a root holding `=` as an assignment operand.
  if ! YAML_RECORDS="$(LC_ALL=C awk -v STRICT=1 -f "$YAML_PARSER" <"$YAML_PATH" 2>/dev/null)"; then
    # The parser's last record is `error<TAB><line><TAB><message>`.
    yaml_err="${YAML_RECORDS##*"$nl"}"
    yaml_err="${yaml_err#error"$tab"}"
    printf '%s\n' "resolve-convention-pattern: $1 does not parse (line ${yaml_err%%"$tab"*}: ${yaml_err#*"$tab"}); enforcement disabled." >&2
    exit 1
  fi
  YAML_ACTIVE=1
}

if [ -f "$TEAM_YAML" ] &&
  git -C "$repo_root" ls-files --error-unmatch -- "$TEAM_YAML_REL" >/dev/null 2>&1; then
  load_yaml "$TEAM_YAML_REL" "the team file"
fi

# yaml_lookup <key>: YAML_HAS=1 and YAML_VAL=<value> when the loaded file carries
# <key> as a root scalar (the value may be empty); YAML_HAS=0 and YAML_VAL
# empty otherwise.
yaml_lookup() {
  YAML_HAS=0
  YAML_VAL=""
  [ "$YAML_ACTIVE" -eq 1 ] || return 0
  yl_rest="$nl$YAML_RECORDS"
  case "$yl_rest" in
  *"$nl$1$tab"*)
    yl_rest="${yl_rest#*"$nl$1$tab"}"
    YAML_VAL="${yl_rest%%"$nl"*}"
    YAML_HAS=1
    ;;
  *) ;;
  esac
  return 0
}

# yaml_bare_key <key>: true when the loaded file has a root `<key>:` line (the
# key plain or quoted) with no value, which the parser reports no record for.
yaml_bare_key() {
  yb_first=1
  while IFS= read -r yb_line || [ -n "$yb_line" ]; do
    yb_line="${yb_line%"$cr"}"
    if [ "$yb_first" -eq 1 ]; then
      yb_line="${yb_line#"$bom"}"
      yb_first=0
    fi
    case "$yb_line" in
    "$1:"*) yb_rest="${yb_line#"$1:"}" ;;
    "\"$1\":"*) yb_rest="${yb_line#"\"$1\":"}" ;;
    "'$1':"*) yb_rest="${yb_line#"'$1':"}" ;;
    *) continue ;;
    esac
    yb_rest="${yb_rest#"${yb_rest%%[![:space:]]*}"}"
    case "$yb_rest" in
    "" | "#"*) return 0 ;;
    *) ;;
    esac
  done <"$YAML_PATH"
  return 1
}

# check_yaml_key <key>: a key the loaded file CARRIES must hold one value.
# Present-but-empty (`subject_pattern: ''`, or `subject_pattern:` alone) or a
# list or mapping in its place is a configuration error, not an omission —
# falling back to a legacy value would enforce a stale pattern the migration
# meant to retire.
check_yaml_key() {
  [ "$YAML_ACTIVE" -eq 1 ] || return 0
  yaml_lookup "$1"
  if [ "$YAML_HAS" -eq 1 ]; then
    [ -n "$YAML_VAL" ] && return 0
  else
    case "$nl$YAML_RECORDS" in
    *"$nl$1."*) ;; # carried as a list or a mapping
    *) yaml_bare_key "$1" || return 0 ;;
    esac
  fi
  printf '%s\n' "resolve-convention-pattern: $YAML_REL carries '$1' without one non-empty value; a carried key must hold one value (delete the line to fall back) — enforcement disabled." >&2
  exit 1
}

# check_yaml_dialect: `dialect:` (optional, default posix-ere) names the dialect
# the loaded file's patterns are written in. Enforcement consumes posix-ere only.
check_yaml_dialect() {
  yaml_lookup dialect
  if [ -n "$YAML_VAL" ] && [ "$YAML_VAL" != "posix-ere" ]; then
    printf '%s\n' "resolve-convention-pattern: $YAML_REL declares dialect '$YAML_VAL'; enforcement consumes posix-ere only — enforcement disabled." >&2
    exit 1
  fi
}
check_yaml_dialect

# --- Legacy surfaces, read for one release: the neutral file and the markdown ---
# The markdown team file MAY declare `## convention_source` naming a
# repo-relative flat-scalar YAML file (the tool-agnostic SSOT other consumers —
# commit-msg hooks, CI — read with one sed). When declared, that file is
# authoritative for the machine keys it carries; a key it omits falls back to
# the markdown H2. The pointer is honored from the TEAM file only (same policy
# floor — a gitignored overlay must not redirect the gate), and a
# declared-but-broken pointer FAILS CLOSED to no-enforcement with a diagnostic
# rather than silently re-reading markdown values migration may have retired.
#
# resolve_legacy runs only for a key the team YAML lacks, so a broken pointer
# never disables a key the YAML supplies. It sets NEUTRAL_FILE and NEUTRAL_REL
# (empty when no neutral file applies) and exits 1 on a pointer it cannot honor:
# an absolute or traversal path, a missing file, or a dialect other than
# posix-ere.
NEUTRAL_FILE=""
NEUTRAL_REL=""
LEGACY_READY=0
resolve_legacy() {
  LEGACY_READY=1
  ptr="$(h2_value "$TEAM_FILE" "convention_source")"
  # Precedence: an explicit convention_source (rung 1) always wins. Absent one,
  # probe the well-known default path (rung 2) so the common case needs no
  # pointer at all; absent that too, resolution falls through to the markdown H2
  # (rung 3). The default is a plain repo-relative path and passes the same
  # safety checks below as any pointer.
  #
  # POLICY FLOOR: the well-known rung activates ONLY when the file is
  # git-TRACKED. Unlike an explicit convention_source — whose opt-in is a
  # tracked edit to the team file — this rung has no other tracked signal, so
  # honoring an untracked or gitignored file at this path would let a
  # generated/local artifact silently override team policy (or, if malformed,
  # disable enforcement) on one checkout. git unavailable, or the file untracked
  # -> skip this rung and fall through to the markdown H2 (fail toward the prior
  # behavior, never toward the hole).
  if [ -z "$ptr" ] && [ -f "$repo_root/$WELL_KNOWN_NEUTRAL" ] &&
    git -C "$repo_root" ls-files --error-unmatch -- "$WELL_KNOWN_NEUTRAL" >/dev/null 2>&1; then
    ptr="$WELL_KNOWN_NEUTRAL"
  fi
  [ -n "$ptr" ] || return 0
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
  NEUTRAL_REL="$ptr"
  if [ ! -f "$NEUTRAL_FILE" ]; then
    printf '%s\n' "resolve-convention-pattern: convention_source declares '$ptr' but no such file exists under the repo root; enforcement disabled (fix the pointer or restore the file)." >&2
    exit 1
  fi
  in_repo_or_exit "$ptr" "convention_source"
  read_neutral
  if [ -n "$NEUTRAL_DIALECT" ] && [ "$NEUTRAL_DIALECT" != "posix-ere" ]; then
    printf '%s\n' "resolve-convention-pattern: convention_source file declares dialect '$NEUTRAL_DIALECT'; enforcement consumes posix-ere only — enforcement disabled." >&2
    exit 1
  fi
}

# check_neutral_key <key>: a key the neutral file CARRIES must hold a value.
# Present-but-empty (`subject_pattern:` or `subject_pattern: ''`) is a
# configuration error, not an omission — silently falling back to the markdown
# H2 would enforce a stale pattern the migration meant to retire.
check_neutral_key() {
  neutral_key "$1"
  [ -n "$nk_has" ] || return 0
  [ -n "$nk_v" ] && return 0
  printf '%s\n' "resolve-convention-pattern: convention_source file carries '$1' with an empty value; a carried key must hold a value (delete the line to fall back to the markdown H2) — enforcement disabled." >&2
  exit 1
}

# team_value <key>: TV is the key's team value and TV_LAYER the repo-relative
# file that supplied it, both empty when none does: the team YAML when it
# carries the key; otherwise, once resolve_legacy has run, the neutral file when
# it carries the key, then the markdown H2.
team_value() {
  TV=""
  TV_LAYER=""
  yaml_lookup "$1"
  if [ "$YAML_HAS" -eq 1 ]; then
    TV="$YAML_VAL"
    TV_LAYER="$TEAM_YAML_REL"
    return 0
  fi
  [ "$LEGACY_READY" -eq 1 ] || return 0
  neutral_key "$1"
  if [ -n "$nk_v" ]; then
    TV="$nk_v"
    TV_LAYER="$NEUTRAL_REL"
    return 0
  fi
  TV="$(h2_value "$TEAM_FILE" "$1")"
  [ -z "$TV" ] || TV_LAYER="$LEGACY_MD_REL"
  return 0
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

# raw_value <key>: team_value with the CC keyword expanded, into RV and
# RV_LAYER; TV keeps the pre-expansion value. The keyword and the deferral
# marker work identically on every surface: one literal each, no per-surface
# variants to drift.
raw_value() {
  team_value "$1"
  RV="$TV"
  RV_LAYER="$TV_LAYER"
  [ "$RV" = "Conventional Commits" ] && RV="$CC_ERE"
  return 0
}

# Which keys this lookup reads: the key itself, and subject_pattern too when a
# pr_title_pattern may defer to it (the YAML lacks pr_title_pattern, or carries
# the deferral marker). Present-but-empty keys fail closed BEFORE resolution, on
# whichever surface carries them; the legacy surfaces are resolved only when the
# YAML lacks one of those keys.
check_yaml_key "$key"
yaml_lookup "$key"
need_legacy=0
[ "$YAML_HAS" -eq 1 ] || need_legacy=1
need_subject=0
if [ "$key" = "pr_title_pattern" ] &&
  { [ "$YAML_HAS" -eq 0 ] || [ "$YAML_VAL" = "$PR_DEFERRAL" ]; }; then
  need_subject=1
  check_yaml_key subject_pattern
  yaml_lookup subject_pattern
  [ "$YAML_HAS" -eq 1 ] || need_legacy=1
fi
if [ "$need_legacy" -eq 1 ]; then
  resolve_legacy
  yaml_lookup "$key"
  [ "$YAML_HAS" -eq 1 ] || check_neutral_key "$key"
  if [ "$need_subject" -eq 1 ]; then
    yaml_lookup subject_pattern
    [ "$YAML_HAS" -eq 1 ] || check_neutral_key subject_pattern
  fi
fi

raw_value "$key"
value="$RV"
layer="$RV_LAYER"

# pr_title_pattern deferral: `Same as `subject_pattern`.` enforces the effective
# subject pattern. Resolve against the raw (pre-expansion) pr_title value. The
# layer stays the one that supplied pr_title_pattern's own value.
if [ "$key" = "pr_title_pattern" ] && [ "$TV" = "$PR_DEFERRAL" ]; then
  raw_value "subject_pattern"
  value="$RV"
fi

# --- The personal layer: docs/conventions/source-control.local.yaml ---
# Read only for subject_pattern and only when the team layer supplied none (see
# the policy-floor contract in the header). git check-ignore exits 0 only for a
# path an exclude rule matches that the index does not track. A file present but
# not ignored is reported and not read, since a plain `git add` would commit it
# as a pattern for everyone. The CC keyword expands as on every surface.
read_personal() {
  [ -f "$repo_root/$PERSONAL_YAML_REL" ] || return 0
  ignore_rc=0
  git -C "$repo_root" check-ignore -q -- "$PERSONAL_YAML_REL" >/dev/null 2>&1 || ignore_rc=$?
  if [ "$ignore_rc" -eq 1 ]; then
    printf '%s\n' "resolve-convention-pattern: $PERSONAL_YAML_REL is not ignored by git (it is tracked, or no .gitignore, .git/info/exclude or core.excludesFile rule matches it); the personal layer is read only while git ignores it — enforcement disabled." >&2
    exit 1
  fi
  if [ "$ignore_rc" -ne 0 ]; then
    printf '%s\n' "resolve-convention-pattern: git could not tell whether $PERSONAL_YAML_REL is ignored (git check-ignore exit $ignore_rc); the personal layer is read only while git ignores it — enforcement disabled." >&2
    exit 1
  fi
  load_yaml "$PERSONAL_YAML_REL" "the personal file"
  check_yaml_dialect
  check_yaml_key subject_pattern
  yaml_lookup subject_pattern
  value="$YAML_VAL"
  layer="$PERSONAL_YAML_REL"
  [ "$value" != "Conventional Commits" ] || value="$CC_ERE"
}
if [ -z "$value" ] && [ "$key" = "subject_pattern" ]; then
  read_personal
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

if [ "$layer_mode" -eq 1 ]; then
  printf '%s\n' "$layer"
else
  printf '%s\n' "$value"
fi
exit 0
