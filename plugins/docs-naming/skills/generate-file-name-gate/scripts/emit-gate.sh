#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/../templates"
RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-config.sh"
ROOT_SCOPES="$SCRIPT_DIR/../../../scripts/root-scopes.jq"
# shellcheck source=../../../lib/load-config.sh
. "$SCRIPT_DIR/../../../lib/load-config.sh"

die() {
  printf 'emit-gate: %s\n' "$1" >&2
  exit "${2:-2}"
}

refused() {
  printf 'emit-gate: refused: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Render the file-name gate into a consuming repository.
Usage: emit-gate.sh [--config <json>] [--root <dir>] [--out-dir <dir>] [--rule] [--force]
  --config <json>  a resolved configuration document
  --root <dir>     the consuming repository
  --out-dir <dir>  where the checker and its suite go, relative to the root (default scripts)
  --rule           also write .claude/rules/file-names.md
  --force          overwrite files that already exist
Exit: 0 emitted; 1 refused (a target exists and --force was not given); 2 usage or a missing prerequisite.
EOF
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
  --user-config)
    shift
    [[ $# -gt 0 ]] || die "--user-config needs a value"
    export CLAUDE_PLUGIN_OPTION_FILE_NAMES="$1"
    ;;
  --out-dir)
    shift
    [[ $# -gt 0 ]] || die "--out-dir needs a directory"
    OUT_DIR="${1%/}"
    [[ "$OUT_DIR" != /* ]] || die "--out-dir must be relative to the root, not '$OUT_DIR'"
    case "/$OUT_DIR/" in
    */../*) die "--out-dir must not leave the root: '$OUT_DIR'" ;;
    *) ;;
    esac
    [[ "$OUT_DIR" =~ ^[A-Za-z0-9._/-]*$ ]] ||
      die "--out-dir may use letters, digits, dot, dash, underscore, and slash only: '$OUT_DIR'"
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

load_config

REGEX="$(cfg '.file_names.regex')"
RULE="$(cfg '.file_names.rule')"
[[ -n "$REGEX" && "$REGEX" != "null" ]] || die "the configuration declares no file_names.regex"
[[ -n "$RULE" && "$RULE" != "null" ]] || die "the configuration declares no file_names.rule"
[[ "$REGEX$RULE" != *$'\n'* ]] || die "file_names.regex or file_names.rule carries a newline"

grep -Eq "$REGEX" <<<'probe-name.md' >/dev/null 2>&1
[[ "$?" -le 1 ]] || die "file_names.regex does not compile under grep -E: $REGEX"

EXEMPT_BASENAMES="$(cfg '.file_names.exempt_basenames[]')"
EXEMPT_PATHS="$(cfg '.file_names.exempt_paths[]')"
EXEMPT_EXTENSIONS="$(cfg '.file_names.exempt_extensions[]')"

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

SCOPES="$(printf '%s' "$CONFIG" | jq -c -f "$ROOT_SCOPES" 2>/dev/null | tr -d '\r')" ||
  die "file_names.roots must hold strings or {path, extensions, exempt_paths} objects"
[[ "$(printf '%s' "$SCOPES" | jq 'length')" -gt 0 ]] || die "the configuration declares no file_names.roots"
printf '%s' "$SCOPES" | jq -e 'all(.[]; all(.extensions[]; test("^[A-Za-z0-9]+$")))' >/dev/null ||
  die "a root's extensions may use letters and digits only"
UNSAFE="$(printf '%s' "$SCOPES" | jq -r '[.[].unsafe | values][0] // empty' | tr -d '\r')"
[[ -z "$UNSAFE" ]] || die "a root's path or exempt_paths entry $UNSAFE"

PRIMARY_JSON="$(printf '%s' "$SCOPES" | jq -c '(map(select(.extensions == [])) + .)[0]')"
PRIMARY_EXTS=" $(printf '%s' "$PRIMARY_JSON" | jq -r '.extensions | map(ascii_downcase) | join(" ")' | tr -d '\r') "
PRIMARY_ROOT="$(sq "$(printf '%s' "$PRIMARY_JSON" | jq -r '.path' | tr -d '\r')")"

SCOPE_SPECS_ARRAY="$(printf '%s' "$SCOPES" | jq -r '[.[] | .specs[]] | @sh' | tr -d '\r')"
SCOPE_EXEMPTS_ARRAY="$(printf '%s' "$SCOPES" |
  jq -r '[.[] | . as $r | .specs[] | $r.exempt | map(":(glob)" + .) | join("\n")] | @sh' | tr -d '\r')"
ROOTS_HUMAN="$(printf '%s' "$SCOPES" | jq -r '.[] |
  "`\(.path)`"
  + (if .extensions == [] and .exempt == [] then ""
     else " (" + (if .extensions == [] then "every file" else (.extensions | map("`*.\(ascii_downcase)`") | join(", ")) + " files" end)
       + (if .exempt == [] then "" else ", except under " + (.exempt | map("`\(.)`") | join(", ")) end) + ")"
     end)' | tr -d '\r' | awk 'NF {a[++n] = $0} END {
    for (i = 1; i <= n; i++) s = s (i == 1 ? "" : (i == n ? (n == 2 ? " and " : ", and ") : ", ")) a[i]
    print s
  }')"
ROOTS_PLAIN="$(sq "$(printf '%s' "$SCOPES" | jq -r 'map(.label) | join(", ")' | tr -d '\r')")"
REGEX_SQ="$(sq "$REGEX")"
RULE_SQ="$(sq "$RULE")"
EXEMPT_BASENAMES_ARRAY="$(printf '%s\n' "$EXEMPT_BASENAMES" | quoted)"
EXEMPT_BASENAMES_HUMAN="$(printf '%s\n' "$EXEMPT_BASENAMES" | human)"
EXEMPT_PATHS_ARRAY="$(printf '%s\n' "$EXEMPT_PATHS" | quoted)"
EXEMPT_PATHS_HUMAN="$(printf '%s\n' "$EXEMPT_PATHS" | human)"
EXEMPT_EXTENSIONS_ARRAY="$(printf '%s\n' "$EXEMPT_EXTENSIONS" | quoted)"
EXEMPT_EXTENSIONS_HUMAN="$(printf '%s\n' "$EXEMPT_EXTENSIONS" | human)"

EXEMPT_PATH_SEEDS_ARRAY="$(printf '%s\n' "$EXEMPT_PATHS" |
  awk '/\*$/ {sub(/\/*\**$/, ""); if (length($0)) print $0 "/Exempt_By-PATH.md"}' | quoted)"

probe_names() {
  local stem ext
  {
    printf '%s\n' "$@"
    for ext in $PRIMARY_EXTS; do
      for stem in "${@%.*}"; do printf '%s.%s\n' "$stem" "$ext"; done
    done
  } | awk '!seen[$0]++'
}

probe_ok() {
  for cand in $(probe_names conforming-name.md conformingname.md conforming.md c1.md name.txt n.md n.txt); do
    grep -Eq "$REGEX" <<<"$cand" || continue
    probe_eligible "$cand" || continue
    printf '%s' "$cand"
    return 0
  done
  return 1
}

probe_eligible() {
  ! exempt_by_list "$1" "$EXEMPT_BASENAMES" &&
    ! exempt_by_list "${1##*.}" "$EXEMPT_EXTENSIONS" &&
    in_primary_root "$1"
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

in_primary_root() {
  local ext
  ext="$(printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]')"
  [[ "$PRIMARY_EXTS" == "  " || "$PRIMARY_EXTS" == *" $ext "* ]]
}

PROBE_OK="$(probe_ok)" ||
  die "no probe name this contract knows passes file_names.regex without being exempt, so the emitted suite would have no clean case; widen the rule or emit by hand"

PROBE_BAD_ARRAY="$(
  for cand in $(probe_names UPPER-KEBAB.md snake_case.md Mixed.md double..dot.md BadName.txt); do
    grep -Eq "$REGEX" <<<"$cand" && continue
    probe_eligible "$cand" || continue
    printf '%s\n' "$cand"
  done | quoted
)"
[[ -n "${PROBE_BAD_ARRAY// /}" ]] ||
  die "no probe name this contract knows is rejected by file_names.regex, so the emitted suite could not prove the rule fires"

EXEMPT_EXT_SEEDS_ARRAY="$(printf '%s\n' "$EXEMPT_EXTENSIONS" | while IFS= read -r e; do
  [[ -n "$e" ]] && in_primary_root "x.$e" && printf '%s\n' "$e"
done | quoted)"

RULE_PATHS="$(printf '%s' "$SCOPES" | jq -r '[.[].rule_paths[]] | join(", ")' | tr -d '\r')"

SHEBANG='#!/usr/bin/env bash'
SCRIPT_NAME="check-file-names.sh"
TEST_NAME="check-file-names.test.sh"
SCRIPT_STEM="${SCRIPT_NAME%.sh}"
if [[ -n "$OUT_DIR" && "$OUT_DIR" != "." ]]; then
  SCRIPT_PATH="$OUT_DIR/$SCRIPT_NAME"
  TEST_PATH="$OUT_DIR/$TEST_NAME"
  ROOT_HOP="$(printf '%s\n' "$OUT_DIR" | awk -F/ '{for (i = 1; i <= NF; i++) printf "%s..", (i > 1 ? "/" : ""); print ""}')"
else
  SCRIPT_PATH="$SCRIPT_NAME"
  TEST_PATH="$TEST_NAME"
  ROOT_HOP="."
fi

render() {
  GFG_REGEX="$REGEX" \
    GFG_REGEX_SQ="$REGEX_SQ" \
    GFG_RULE="$RULE" \
    GFG_RULE_SQ="$RULE_SQ" \
    GFG_SCOPE_SPECS_ARRAY="$SCOPE_SPECS_ARRAY" \
    GFG_SCOPE_EXEMPTS_ARRAY="$SCOPE_EXEMPTS_ARRAY" \
    GFG_ROOTS_HUMAN="$ROOTS_HUMAN" \
    GFG_ROOTS_PLAIN="$ROOTS_PLAIN" \
    GFG_EXEMPT_BASENAMES_ARRAY="$EXEMPT_BASENAMES_ARRAY" \
    GFG_EXEMPT_BASENAMES_HUMAN="$EXEMPT_BASENAMES_HUMAN" \
    GFG_EXEMPT_PATHS_ARRAY="$EXEMPT_PATHS_ARRAY" \
    GFG_EXEMPT_PATHS_HUMAN="$EXEMPT_PATHS_HUMAN" \
    GFG_EXEMPT_EXTENSIONS_ARRAY="$EXEMPT_EXTENSIONS_ARRAY" \
    GFG_EXEMPT_EXTENSIONS_HUMAN="$EXEMPT_EXTENSIONS_HUMAN" \
    GFG_EXEMPT_PATH_SEEDS_ARRAY="$EXEMPT_PATH_SEEDS_ARRAY" \
    GFG_EXEMPT_EXT_SEEDS_ARRAY="$EXEMPT_EXT_SEEDS_ARRAY" \
    GFG_RULE_PATHS="$RULE_PATHS" \
    GFG_SCRIPT_NAME="$SCRIPT_NAME" \
    GFG_TEST_NAME="$TEST_NAME" \
    GFG_SCRIPT_PATH="$SCRIPT_PATH" \
    GFG_SCRIPT_STEM="$SCRIPT_STEM" \
    GFG_ROOT_HOP="$ROOT_HOP" \
    GFG_PRIMARY_ROOT="$PRIMARY_ROOT" \
    GFG_PROBE_OK="$PROBE_OK" \
    GFG_PROBE_BAD_ARRAY="$PROBE_BAD_ARRAY" \
    GFG_SHEBANG="$SHEBANG" \
    awk '
    BEGIN {
      split("REGEX REGEX_SQ RULE RULE_SQ SCOPE_SPECS_ARRAY SCOPE_EXEMPTS_ARRAY ROOTS_HUMAN ROOTS_PLAIN " \
            "EXEMPT_BASENAMES_ARRAY EXEMPT_BASENAMES_HUMAN EXEMPT_PATHS_ARRAY EXEMPT_PATHS_HUMAN " \
            "EXEMPT_EXTENSIONS_ARRAY EXEMPT_EXTENSIONS_HUMAN EXEMPT_PATH_SEEDS_ARRAY EXEMPT_EXT_SEEDS_ARRAY " \
            "RULE_PATHS SCRIPT_NAME TEST_NAME SCRIPT_PATH SCRIPT_STEM ROOT_HOP " \
            "PRIMARY_ROOT PROBE_OK PROBE_BAD_ARRAY SHEBANG", names, " ")
      # Each name is the placeholder `@@<name>@@` and the variable `GFG_<name>`.
      for (n = 1; n in names; n++) {
        k[n] = "@@" names[n] "@@"
        v[n] = ENVIRON["GFG_" names[n]]
      }
      n--
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

targets=("$ROOT/$SCRIPT_PATH" "$ROOT/$TEST_PATH")
[[ "$WITH_RULE" -eq 1 ]] && targets+=("$ROOT/.claude/rules/file-names.md")

if [[ "$FORCE" -eq 0 ]]; then
  for t in "${targets[@]}"; do
    [[ -e "$t" ]] && refused "'${t#"$ROOT"/}' already exists; re-run with --force to overwrite it"
  done
fi

for t in "${targets[@]}"; do
  mkdir -p "$(dirname "$t")" || die "cannot create $(dirname "$t")"
done

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

printf 'NOT-WIRED\ta CI step invoking %s\n' "$SCRIPT_PATH"
printf 'NOT-WIRED\ta row in whatever registry lists this repository gates\n'
printf 'NOT-WIRED\tan architecture decision record for the rule\n'
exit 0
