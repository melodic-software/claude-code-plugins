#!/usr/bin/env bash
# emit-gate.sh — render the file-name gate into a consuming repository.
#
# The gate is a plain bash script the consumer owns and runs from its own CI.
# It carries no dependency on this plugin at run time: the rule, the roots, and
# the exemptions are inlined at emission from the resolved configuration, so a
# checkout with the plugin uninstalled still enforces what the team agreed.
#
# RENDERING GOES THROUGH awk WITH `-v`, NEVER A sed SUBSTITUTION. A consumer's
# regex is arbitrary text: `^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z0-9]+$` already
# carries backslashes, and a `&`, a `|`, or a `/` in one would either break the
# sed expression or be re-read as a back-reference and silently corrupt the
# emitted script. `-v` hands the value across untouched, and the replacement
# below is literal (index/substr), never a gsub whose pattern the value would
# also have to survive.
#
# WHY THIS IS NOT PART OF `setup apply`. The setup contract scopes `apply` to
# the plugin's own configuration artifact. Emission writes consumer-owned files
# under the consumer's `scripts/` and `.claude/rules/`, which is outside it.
#
# Usage:
#   emit-gate.sh [--config <json>] [--root <dir>] [--out-dir <dir>]
#                [--rule] [--force]
#   emit-gate.sh --help
#
#   --out-dir  where the checker and its suite go, relative to the root.
#              Default `scripts`.
#   --rule     also write `.claude/rules/file-names.md`, the path-scoped rule.
#   --force    overwrite files that already exist. Without it an existing
#              target refuses the run and nothing is written.
#
# Exit: 0 emitted, 1 refused (a target exists and --force was not given), 2
#       usage or a missing prerequisite.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/../templates"
RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-config.sh"

die() {
  printf 'emit-gate: %s\n' "$1" >&2
  exit "${2:-2}"
}

refused() {
  printf 'emit-gate: refused: %s\n' "$1" >&2
  exit 1
}

usage() {
  sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'
}

CONFIG_FILE=""
ROOT=""
OUT_DIR="scripts"
WITH_RULE=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --config)
    shift
    [[ $# -gt 0 ]] || die "--config needs a file"
    CONFIG_FILE="$1"
    ;;
  --root)
    shift
    [[ $# -gt 0 ]] || die "--root needs a directory"
    ROOT="$1"
    ;;
  --out-dir)
    shift
    [[ $# -gt 0 ]] || die "--out-dir needs a directory"
    OUT_DIR="${1%/}"
    ;;
  --rule) WITH_RULE=1 ;;
  --force) FORCE=1 ;;
  --help | -h)
    usage
    exit 0
    ;;
  *) die "unknown argument '$1'" ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || die "jq is required and is not on PATH"
[[ -d "$TEMPLATES" ]] || die "templates missing at $TEMPLATES"

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
  [[ -n "$ROOT" ]] || die "not inside a git repository and no --root given"
fi
[[ -d "$ROOT" ]] || die "--root '$ROOT' is not a directory"

if [[ -n "$CONFIG_FILE" ]]; then
  [[ -r "$CONFIG_FILE" ]] || die "cannot read the configuration at $CONFIG_FILE"
  CONFIG="$(jq -e . "$CONFIG_FILE" 2>/dev/null | tr -d '\r')" || die "the configuration at $CONFIG_FILE is not valid JSON"
else
  [[ -f "$RESOLVER" ]] || die "resolver missing at $RESOLVER"
  CONFIG="$(bash "$RESOLVER" resolve --root "$ROOT")" || exit 2
fi

cfg() {
  printf '%s' "$CONFIG" | jq -r "$1" 2>/dev/null | tr -d '\r'
}

# --- the values the templates carry ------------------------------------------

REGEX="$(cfg '.file_names.regex')"
RULE="$(cfg '.file_names.rule')"
[[ -n "$REGEX" && "$REGEX" != "null" ]] || die "the configuration declares no file_names.regex"
[[ -n "$RULE" && "$RULE" != "null" ]] || die "the configuration declares no file_names.rule"

# `list <jq-path>` prints one entry per line; `quoted` turns those into a shell
# array body; `human` turns them into a prose list for the headers.
list() {
  cfg "$1" 2>/dev/null
}

quoted() {
  awk 'NF {printf "%s\"%s\"", (n++ ? " " : ""), $0} END {print ""}'
}

human() {
  awk 'NF {a[++n] = $0} END {
    if (n == 0) { print "(none)"; exit }
    for (i = 1; i <= n; i++) {
      s = s (i == 1 ? "" : (i == n ? (n == 2 ? " and " : ", and ") : ", ")) "`" a[i] "`"
    }
    print s
  }'
}

ROOTS_LIST="$(list '.file_names.roots[]')"
[[ -n "$ROOTS_LIST" ]] || die "the configuration declares no file_names.roots"
PRIMARY_ROOT="$(printf '%s\n' "$ROOTS_LIST" | head -1)"

ROOTS_ARRAY="$(printf '%s\n' "$ROOTS_LIST" | quoted)"
ROOTS_HUMAN="$(printf '%s\n' "$ROOTS_LIST" | human)"
# Backtick-free, for the one place the value lands inside a single-quoted
# printf format in the emitted script: a backtick there reads as a command
# substitution to every reviewer and to shellcheck, whatever the quoting says.
ROOTS_PLAIN="$(printf '%s\n' "$ROOTS_LIST" | awk 'NF {printf "%s%s", (n++ ? ", " : ""), $0} END {print ""}')"
EXEMPT_BASENAMES_ARRAY="$(list '.file_names.exempt_basenames[]' | quoted)"
EXEMPT_BASENAMES_HUMAN="$(list '.file_names.exempt_basenames[]' | human)"
EXEMPT_PATHS_ARRAY="$(list '.file_names.exempt_paths[]' | quoted)"
EXEMPT_PATHS_HUMAN="$(list '.file_names.exempt_paths[]' | human)"
EXEMPT_EXTENSIONS_ARRAY="$(list '.file_names.exempt_extensions[]' | quoted)"
EXEMPT_EXTENSIONS_HUMAN="$(list '.file_names.exempt_extensions[]' | human)"

# One seed path per exempt_paths glob: the glob's literal prefix plus a
# basename the rule would reject, so the emitted case proves the exemption
# carried the file rather than the rule accepting it.
EXEMPT_PATH_SEEDS_ARRAY="$(list '.file_names.exempt_paths[]' |
  sed 's|/*\*\**$||' | awk 'NF {print $0 "/Exempt_By-PATH.md"}' | quoted)"

# The rule file's `paths:` frontmatter, one glob per root.
RULE_PATHS="$(printf '%s\n' "$ROOTS_LIST" | awk 'NF {printf "%s%s/**", (n++ ? ", " : ""), $0} END {print ""}')"

SCRIPT_NAME="check-file-names.sh"
TEST_NAME="check-file-names.test.sh"
SCRIPT_STEM="${SCRIPT_NAME%.sh}"
if [[ -n "$OUT_DIR" && "$OUT_DIR" != "." ]]; then
  SCRIPT_PATH="$OUT_DIR/$SCRIPT_NAME"
  # One `..` per segment of the out-dir, so the emitted checker resolves the
  # repository root from its own location rather than from the caller's cwd.
  ROOT_HOP="$(printf '%s\n' "$OUT_DIR" | awk -F/ '{for (i = 1; i <= NF; i++) printf "%s..", (i > 1 ? "/" : ""); print ""}')"
else
  SCRIPT_PATH="$SCRIPT_NAME"
  ROOT_HOP="."
fi

# --- render -------------------------------------------------------------------

render() {
  awk \
    -v regex="$REGEX" -v rule="$RULE" \
    -v roots_array="$ROOTS_ARRAY" -v roots_human="$ROOTS_HUMAN" \
    -v roots_plain="$ROOTS_PLAIN" \
    -v eb_array="$EXEMPT_BASENAMES_ARRAY" -v eb_human="$EXEMPT_BASENAMES_HUMAN" \
    -v ep_array="$EXEMPT_PATHS_ARRAY" -v ep_human="$EXEMPT_PATHS_HUMAN" \
    -v ee_array="$EXEMPT_EXTENSIONS_ARRAY" -v ee_human="$EXEMPT_EXTENSIONS_HUMAN" \
    -v eps_array="$EXEMPT_PATH_SEEDS_ARRAY" -v rule_paths="$RULE_PATHS" \
    -v script_name="$SCRIPT_NAME" -v test_name="$TEST_NAME" \
    -v script_path="$SCRIPT_PATH" -v script_stem="$SCRIPT_STEM" \
    -v root_hop="$ROOT_HOP" -v primary_root="$PRIMARY_ROOT" '
    BEGIN {
      k[1] = "@@REGEX@@";                     v[1] = regex
      k[2] = "@@RULE@@";                      v[2] = rule
      k[3] = "@@ROOTS_ARRAY@@";               v[3] = roots_array
      k[4] = "@@ROOTS_HUMAN@@";               v[4] = roots_human
      k[5] = "@@EXEMPT_BASENAMES_ARRAY@@";    v[5] = eb_array
      k[6] = "@@EXEMPT_BASENAMES_HUMAN@@";    v[6] = eb_human
      k[7] = "@@EXEMPT_PATHS_ARRAY@@";        v[7] = ep_array
      k[8] = "@@EXEMPT_PATHS_HUMAN@@";        v[8] = ep_human
      k[9] = "@@EXEMPT_EXTENSIONS_ARRAY@@";   v[9] = ee_array
      k[10] = "@@EXEMPT_EXTENSIONS_HUMAN@@";  v[10] = ee_human
      k[11] = "@@EXEMPT_PATH_SEEDS_ARRAY@@";  v[11] = eps_array
      k[12] = "@@RULE_PATHS@@";               v[12] = rule_paths
      k[13] = "@@SCRIPT_NAME@@";              v[13] = script_name
      k[14] = "@@TEST_NAME@@";                v[14] = test_name
      k[15] = "@@SCRIPT_PATH@@";              v[15] = script_path
      k[16] = "@@SCRIPT_STEM@@";              v[16] = script_stem
      k[17] = "@@ROOT_HOP@@";                 v[17] = root_hop
      k[18] = "@@PRIMARY_ROOT@@";             v[18] = primary_root
      k[19] = "@@ROOTS_PLAIN@@";              v[19] = roots_plain
      n = 19
    }
    {
      line = $0
      for (i = 1; i <= n; i++) {
        out = ""
        rest = line
        while ((p = index(rest, k[i])) > 0) {
          out = out substr(rest, 1, p - 1) v[i]
          rest = substr(rest, p + length(k[i]))
        }
        line = out rest
      }
      print line
    }
  ' "$1"
}

# --- write --------------------------------------------------------------------

targets=("$ROOT/$SCRIPT_PATH")
if [[ -n "$OUT_DIR" && "$OUT_DIR" != "." ]]; then
  targets+=("$ROOT/$OUT_DIR/$TEST_NAME")
else
  targets+=("$ROOT/$TEST_NAME")
fi
[[ "$WITH_RULE" -eq 1 ]] && targets+=("$ROOT/.claude/rules/file-names.md")

if [[ "$FORCE" -eq 0 ]]; then
  for t in "${targets[@]}"; do
    [[ -e "$t" ]] && refused "'${t#"$ROOT"/}' already exists; re-run with --force to overwrite it"
  done
fi

for t in "${targets[@]}"; do
  mkdir -p "$(dirname "$t")" || die "cannot create $(dirname "$t")"
done

render "$TEMPLATES/check-file-names.sh.tmpl" >"${targets[0]}" || die "cannot write ${targets[0]}"
chmod +x "${targets[0]}"
render "$TEMPLATES/check-file-names.test.sh.tmpl" >"${targets[1]}" || die "cannot write ${targets[1]}"
chmod +x "${targets[1]}"
printf 'EMITTED\t%s\n' "${targets[0]#"$ROOT"/}"
printf 'EMITTED\t%s\n' "${targets[1]#"$ROOT"/}"

if [[ "$WITH_RULE" -eq 1 ]]; then
  render "$TEMPLATES/file-names-rule.md.tmpl" >"${targets[2]}" || die "cannot write ${targets[2]}"
  printf 'EMITTED\t%s\n' "${targets[2]#"$ROOT"/}"
  for index_file in AGENTS.md CLAUDE.md; do
    if [[ -f "$ROOT/$index_file" ]] &&
      grep -q 'BEGIN GENERATED: instruction-placement rules index' "$ROOT/$index_file" 2>/dev/null; then
      printf 'REINDEX\t%s\n' "$index_file"
    fi
  done
fi

# What emission deliberately leaves to the consumer. Each of these is a
# repository-shaped decision with no single right answer, and a generator that
# guessed would be editing files it does not own.
printf 'NOT-WIRED\ta CI step invoking %s\n' "$SCRIPT_PATH"
printf 'NOT-WIRED\ta row in whatever registry lists this repository gates\n'
printf 'NOT-WIRED\tan architecture decision record for the rule\n'
exit 0
