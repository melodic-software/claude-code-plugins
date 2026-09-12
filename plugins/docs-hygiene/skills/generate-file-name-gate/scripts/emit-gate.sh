#!/usr/bin/env bash
# emit-gate.sh — render the file-name gate into a consuming repository.
#
# The gate is a plain bash script the consumer owns and runs from its own CI.
# It carries no dependency on this plugin at run time: the rule, the roots, and
# the exemptions are inlined at emission from the resolved configuration, so a
# checkout with the plugin uninstalled still enforces what the team agreed.
#
# A CONFIGURATION VALUE IS UNTRUSTED TEXT, AND THE EMITTED GATE RUNS IN CI.
# Three separate hazards, each closed at a different layer:
#
# 1. RENDERING IS LITERAL, AND NEVER A sed SUBSTITUTION. A consumer's regex
#    already carries backslashes, and a `&`, a `|`, or a `/` in one would break
#    the sed expression or be re-read as a back-reference. The replacement below
#    is index/substr, never a gsub whose pattern the value must also survive.
# 2. VALUES TRAVEL IN THE ENVIRONMENT, NOT THROUGH awk's `-v`. `-v` runs escape
#    processing: a doubled backslash arrives halved and a literal `\t` arrives
#    as a TAB. `ENVIRON[]` hands the bytes across unchanged.
# 3. EVERY VALUE REACHING THE EMITTED SHELL IS SINGLE-QUOTED. Otherwise a
#    backtick or a `$(...)` in a root or an exemption would execute on every CI
#    run of the gate, and a bare `"` would emit a file bash cannot parse.
#
# And the output is parsed before it is claimed: each rendered file goes through
# `bash -n` and a failure refuses the run rather than reporting a successful
# emission of a broken script.
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
    # The out-dir is a path INSIDE the root. An absolute path or a `..` segment
    # would write outside the repository being configured, and the emitted
    # checker's root hop, which counts segments, would not describe where it
    # landed either.
    [[ "$OUT_DIR" != /* ]] || die "--out-dir must be relative to the root, not '$OUT_DIR'"
    case "/$OUT_DIR/" in
    */../*) die "--out-dir must not leave the root: '$OUT_DIR'" ;;
    *) ;;
    esac
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

# The regex is validated here as well as by `setup check`: emission is the last
# point at which a rule that cannot compile is still a refusal rather than a
# gate that reports every tracked file as an offender.
printf 'probe-name.md\n' | grep -Eq "$REGEX" >/dev/null 2>&1
[[ "$?" -le 1 ]] || die "file_names.regex does not compile under grep -E: $REGEX"

# `list <jq-path>` prints one entry per line; `quoted` turns those into a shell
# array body; `human` turns them into a prose list for the headers.
list() {
  cfg "$1" 2>/dev/null
}

# EVERY VALUE THAT LANDS IN THE EMITTED SHELL IS SINGLE-QUOTED, WITH ITS OWN
# SINGLE QUOTES ESCAPED. A configuration value is text somebody typed, and the
# emitted checker runs in CI: a double-quoted splice would let a backtick or a
# `$(...)` in a root or an exemption execute on every run, and a bare `"` would
# emit a file bash cannot parse. Single quotes suspend every expansion bash has,
# and `'\''` is the one sequence that closes, escapes, and reopens them.
sq() {
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

quoted() {
  awk '
    NF {
      s = $0
      gsub(/\x27/, "\x27\\\x27\x27", s)
      printf "%s\x27%s\x27", (n++ ? " " : ""), s
    }
    END { print "" }
  '
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
# The comma-joined form, for the two places a value lands inside a
# single-quoted string in the emitted script rather than in an array.
ROOTS_PLAIN="$(sq "$(printf '%s\n' "$ROOTS_LIST" | awk 'NF {printf "%s%s", (n++ ? ", " : ""), $0} END {print ""}')")"
REGEX_SQ="$(sq "$REGEX")"
RULE_SQ="$(sq "$RULE")"
EXEMPT_BASENAMES_ARRAY="$(list '.file_names.exempt_basenames[]' | quoted)"
EXEMPT_BASENAMES_HUMAN="$(list '.file_names.exempt_basenames[]' | human)"
EXEMPT_PATHS_ARRAY="$(list '.file_names.exempt_paths[]' | quoted)"
EXEMPT_PATHS_HUMAN="$(list '.file_names.exempt_paths[]' | human)"
EXEMPT_EXTENSIONS_ARRAY="$(list '.file_names.exempt_extensions[]' | quoted)"
EXEMPT_EXTENSIONS_HUMAN="$(list '.file_names.exempt_extensions[]' | human)"

# One seed path per exempt_paths glob: the glob's literal prefix plus a
# basename the rule would reject, so the emitted case proves the exemption
# carried the file rather than the rule accepting it.
#
# Only entries that END in a glob get a seed. A plain-directory entry such as
# `docs/legacy` matches that one path and nothing under it, so a seed beneath it
# would be a case the emitted suite fails out of the box through no fault of the
# consumer's configuration.
EXEMPT_PATH_SEEDS_ARRAY="$(list '.file_names.exempt_paths[]' |
  awk '/\*$/ {sub(/\/*\**$/, ""); if (length($0)) print $0 "/Exempt_By-PATH.md"}' | quoted)"

# The suite's probe names come from the configuration, never from this file. A
# hardcoded `conforming-name.md` is only conforming under a rule that allows a
# hyphen, so a consumer with a different regex would receive a suite that fails
# on its own clean fixture.
probe_ok() {
  for cand in conforming-name.md conformingname.md conforming.md c1.md name.txt n.md n.txt; do
    printf '%s\n' "$cand" | grep -Eq "$REGEX" || continue
    exempt_by_list "$cand" "$(list '.file_names.exempt_basenames[]')" && continue
    exempt_by_list "${cand##*.}" "$(list '.file_names.exempt_extensions[]')" && continue
    printf '%s' "$cand"
    return 0
  done
  return 1
}

exempt_by_list() {
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    [[ "$entry" == "$1" ]] && return 0
  done <<EOF
$2
EOF
  return 1
}

PROBE_OK="$(probe_ok)" ||
  die "no probe name this contract knows passes file_names.regex without being exempt, so the emitted suite would have no clean case; widen the rule or emit by hand"

PROBE_BAD_ARRAY="$(
  for cand in UPPER-KEBAB.md snake_case.md Mixed.md double..dot.md BadName.txt; do
    printf '%s\n' "$cand" | grep -Eq "$REGEX" && continue
    exempt_by_list "$cand" "$(list '.file_names.exempt_basenames[]')" && continue
    exempt_by_list "${cand##*.}" "$(list '.file_names.exempt_extensions[]')" && continue
    printf '%s\n' "$cand"
  done | quoted
)"
[[ -n "${PROBE_BAD_ARRAY// /}" ]] ||
  die "no probe name this contract knows is rejected by file_names.regex, so the emitted suite could not prove the rule fires"

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

# awk's `-v` is NOT a transparent channel: it runs escape processing over the
# value, so a doubled backslash in a consumer's regex arrives halved and a
# literal `\t` arrives as a TAB. The emitted file still parses, it just quietly
# means something else. Values therefore travel in the ENVIRONMENT and are read
# from `ENVIRON[]`, which awk hands across byte for byte.
render() {
  GFG_REGEX="$REGEX" \
    GFG_REGEX_SQ="$REGEX_SQ" \
    GFG_RULE="$RULE" \
    GFG_RULE_SQ="$RULE_SQ" \
    GFG_ROOTS_ARRAY="$ROOTS_ARRAY" \
    GFG_ROOTS_HUMAN="$ROOTS_HUMAN" \
    GFG_ROOTS_PLAIN="$ROOTS_PLAIN" \
    GFG_EB_ARRAY="$EXEMPT_BASENAMES_ARRAY" \
    GFG_EB_HUMAN="$EXEMPT_BASENAMES_HUMAN" \
    GFG_EP_ARRAY="$EXEMPT_PATHS_ARRAY" \
    GFG_EP_HUMAN="$EXEMPT_PATHS_HUMAN" \
    GFG_EE_ARRAY="$EXEMPT_EXTENSIONS_ARRAY" \
    GFG_EE_HUMAN="$EXEMPT_EXTENSIONS_HUMAN" \
    GFG_EPS_ARRAY="$EXEMPT_PATH_SEEDS_ARRAY" \
    GFG_RULE_PATHS="$RULE_PATHS" \
    GFG_SCRIPT_NAME="$SCRIPT_NAME" \
    GFG_TEST_NAME="$TEST_NAME" \
    GFG_SCRIPT_PATH="$SCRIPT_PATH" \
    GFG_SCRIPT_STEM="$SCRIPT_STEM" \
    GFG_ROOT_HOP="$ROOT_HOP" \
    GFG_PRIMARY_ROOT="$PRIMARY_ROOT" \
    GFG_PROBE_OK="$PROBE_OK" \
    GFG_PROBE_BAD_ARRAY="$PROBE_BAD_ARRAY" \
    awk '
    BEGIN {
      split("REGEX REGEX_SQ RULE RULE_SQ ROOTS_ARRAY ROOTS_HUMAN ROOTS_PLAIN " \
            "EB_ARRAY EB_HUMAN EP_ARRAY EP_HUMAN EE_ARRAY EE_HUMAN EPS_ARRAY " \
            "RULE_PATHS SCRIPT_NAME TEST_NAME SCRIPT_PATH SCRIPT_STEM ROOT_HOP " \
            "PRIMARY_ROOT PROBE_OK PROBE_BAD_ARRAY", names, " ")
      # The placeholder for each name, and the value straight out of the
      # environment. The two arrays are indexed together.
      map["REGEX"] = "@@REGEX@@";                          map["REGEX_SQ"] = "@@REGEX_SQ@@"
      map["RULE"] = "@@RULE@@";                            map["RULE_SQ"] = "@@RULE_SQ@@"
      map["ROOTS_ARRAY"] = "@@ROOTS_ARRAY@@";              map["ROOTS_HUMAN"] = "@@ROOTS_HUMAN@@"
      map["ROOTS_PLAIN"] = "@@ROOTS_PLAIN@@"
      map["EB_ARRAY"] = "@@EXEMPT_BASENAMES_ARRAY@@";      map["EB_HUMAN"] = "@@EXEMPT_BASENAMES_HUMAN@@"
      map["EP_ARRAY"] = "@@EXEMPT_PATHS_ARRAY@@";          map["EP_HUMAN"] = "@@EXEMPT_PATHS_HUMAN@@"
      map["EE_ARRAY"] = "@@EXEMPT_EXTENSIONS_ARRAY@@";     map["EE_HUMAN"] = "@@EXEMPT_EXTENSIONS_HUMAN@@"
      map["EPS_ARRAY"] = "@@EXEMPT_PATH_SEEDS_ARRAY@@";    map["RULE_PATHS"] = "@@RULE_PATHS@@"
      map["SCRIPT_NAME"] = "@@SCRIPT_NAME@@";              map["TEST_NAME"] = "@@TEST_NAME@@"
      map["SCRIPT_PATH"] = "@@SCRIPT_PATH@@";              map["SCRIPT_STEM"] = "@@SCRIPT_STEM@@"
      map["ROOT_HOP"] = "@@ROOT_HOP@@";                    map["PRIMARY_ROOT"] = "@@PRIMARY_ROOT@@"
      map["PROBE_OK"] = "@@PROBE_OK@@";                    map["PROBE_BAD_ARRAY"] = "@@PROBE_BAD_ARRAY@@"
      n = 0
      for (i = 1; i in names; i++) {
        k[++n] = map[names[i]]
        v[n] = ENVIRON["GFG_" names[i]]
      }
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

# A rendered file is PARSED before it is claimed. Nothing else here can prove a
# configuration value did not break the shell it landed in, and an `EMITTED` row
# over a file bash refuses is worse than a refusal: the operator wires it into CI
# and finds out there.
emit_shell() {
  render "$2" >"$1" || die "cannot write $1"
  bash -n "$1" 2>"$1.parse.$$" || {
    reason="$(tr '\n' ' ' <"$1.parse.$$")"
    rm -f "$1.parse.$$" "$1"
    die "the rendered ${1##*/} is not valid bash, so nothing was emitted: ${reason:-parse error}. A quote or a control character in the configuration is the usual cause."
  }
  rm -f "$1.parse.$$"
  chmod +x "$1"
}

emit_shell "${targets[0]}" "$TEMPLATES/check-file-names.sh.tmpl"
emit_shell "${targets[1]}" "$TEMPLATES/check-file-names.test.sh.tmpl"
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
