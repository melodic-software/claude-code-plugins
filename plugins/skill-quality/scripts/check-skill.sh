#!/usr/bin/env bash
# Exit 0 = all checks pass; 1 = one or more check failures; 2 = usage/env error;
# 3 = no failure, but PLUGIN_TEST_DEADLINE left script tests unrun.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"

usage() {
  cat <<'EOF'
Static quality gate for Claude Code skills: one skill by name, or every skill under one or more skills roots.

Usage:
  bash check-skill.sh [--require-evals] <skill-name>
  bash check-skill.sh [--require-evals] <root> [<root> ...]
  bash check-skill.sh --help

  --require-evals                   FAIL when a skill has no evals/evals.json (or CHECK_SKILL_REQUIRE_EVALS=1)
  CHECK_SKILL_SKILLS_ROOT           skills root for the <skill-name> form
  CHECK_SKILL_BASE_REF              ref the git-backed checks diff against (default HEAD)
  CHECK_SKILL_SKIP_MARKDOWNLINT=1   skip the markdownlint check
  CHECK_SKILL_SKIP_SCRIPT_TESTS=1   skip the skill's scripts/*.test.sh
  PLUGIN_TEST_DEADLINE=<epoch>      leave script tests unrun past this time

Exit 0 = all checks pass; 1 = one or more check failures; 2 = usage/env error;
3 = no failure, but PLUGIN_TEST_DEADLINE left script tests unrun.
EOF
}

REQUIRE_EVALS="${CHECK_SKILL_REQUIRE_EVALS:-0}"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --require-evals)
    REQUIRE_EVALS=1
    shift
    ;;
  --)
    shift
    break
    ;;
  -*)
    printf 'Error: unknown option: %s\n' "$1" >&2
    exit 2
    ;;
  *)
    break
    ;;
  esac
done
if [[ -n "${CHECK_SKILL_ONLY:-}" && "$CHECK_SKILL_ONLY" != 25 ]]; then
  printf 'Error: CHECK_SKILL_ONLY=%s is not supported; only 25 can run alone\n' "$CHECK_SKILL_ONLY" >&2
  exit 2
fi
if [[ -n "${PLUGIN_TEST_DEADLINE+x}" && ! "$PLUGIN_TEST_DEADLINE" =~ ^[0-9]+$ ]]; then
  printf "Error: PLUGIN_TEST_DEADLINE must be epoch seconds (got '%s')\n" "$PLUGIN_TEST_DEADLINE" >&2
  exit 2
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
HAVE_GIT=0
if [[ -n "$REPO_ROOT" && -d "$REPO_ROOT" ]]; then
  HAVE_GIT=1
fi

GIT_UNSET=(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_PREFIX)
INVOKING_TOPLEVEL="$("${GIT_UNSET[@]}" git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
[[ -n "$INVOKING_TOPLEVEL" ]] && INVOKING_TOPLEVEL="$(cd -- "$INVOKING_TOPLEVEL" && pwd -P)"
INVOKING_TOPLEVEL="${CHECK_SKILL_INVOKING_TOPLEVEL-$INVOKING_TOPLEVEL}"

# shellcheck source=./skill-frontmatter.sh
source "$SCRIPT_DIR/skill-frontmatter.sh"

BASE_REF="${CHECK_SKILL_BASE_REF:-HEAD}"
BASE_REF_ERR=""
if [[ "$HAVE_GIT" == 1 && "$BASE_REF" != "HEAD" ]] &&
  ! git -C "$REPO_ROOT" rev-parse --verify --quiet "$BASE_REF^{commit}" >/dev/null 2>&1; then
  printf -v BASE_REF_ERR 'Error: CHECK_SKILL_BASE_REF=%s is not a valid commit' "$BASE_REF"
fi

SKILLS_ROOT=""
SKILLS_ROOT_ERR=""
if [[ -n "${CHECK_SKILL_SKILLS_ROOT:-}" ]]; then
  SKILLS_ROOT="$CHECK_SKILL_SKILLS_ROOT"
elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  SKILLS_ROOT="$CLAUDE_PROJECT_DIR/.claude/skills"
elif [[ "$HAVE_GIT" == 1 ]]; then
  SKILLS_ROOT="$REPO_ROOT/.claude/skills"
else
  SKILLS_ROOT_ERR='Error: not in a git repo and no skills root set: set CHECK_SKILL_SKILLS_ROOT (or CLAUDE_PROJECT_DIR), or run from inside a git repository'
fi

if [[ -n "$SKILLS_ROOT" && "$SKILLS_ROOT" != /* && ! "$SKILLS_ROOT" =~ ^[A-Za-z]:[\\/] ]]; then
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    SKILLS_ROOT="$CLAUDE_PROJECT_DIR/$SKILLS_ROOT"
  elif [[ "$HAVE_GIT" == 1 ]]; then
    SKILLS_ROOT="$REPO_ROOT/$SKILLS_ROOT"
  else
    printf -v SKILLS_ROOT_ERR 'Error: relative skills root %s needs CLAUDE_PROJECT_DIR or a git repository to anchor against' "$SKILLS_ROOT"
    SKILLS_ROOT=""
  fi
fi

DISPATCH_NAMES=()
DISPATCH_ROOTS=()
DISPATCH_BAD=()
DISPATCH_BAD_PATHS=()
for dispatch_arg in "$@"; do
  if [[ "$dispatch_arg" != */* && "$dispatch_arg" != *\\* &&
    -n "$SKILLS_ROOT" && -f "$SKILLS_ROOT/$dispatch_arg/SKILL.md" ]]; then
    DISPATCH_NAMES+=("$dispatch_arg")
  elif [[ -f "$dispatch_arg/SKILL.md" ]]; then
    printf 'Error: %s is a skill directory, not a skills root (it holds SKILL.md)\n' "$dispatch_arg" >&2
    printf 'Pass its parent directory as the root, or its bare leaf name as the skill.\n' >&2
    exit 2
  elif [[ -d "$dispatch_arg" ]]; then
    if ! dispatch_abs="$(CDPATH='' cd -- "$dispatch_arg" && pwd)"; then
      printf 'Error: skills root exists but could not be entered: %s\n' "$dispatch_arg" >&2
      exit 2
    fi
    DISPATCH_ROOTS+=("$dispatch_abs")
  elif [[ "$dispatch_arg" == */* || "$dispatch_arg" == *\\* ]]; then
    DISPATCH_BAD_PATHS+=("$dispatch_arg")
  else
    DISPATCH_BAD+=("$dispatch_arg")
  fi
done

if ((${#DISPATCH_ROOTS[@]} > 0)); then
  if ((${#DISPATCH_NAMES[@]} > 0)); then
    printf 'Error: mixed skill name and skills root in one call: %s\n' "${DISPATCH_NAMES[*]}" >&2
    printf 'Pass one <skill-name>, or one or more skills roots; never both.\n' >&2
    exit 2
  fi
  if ((${#DISPATCH_BAD[@]} > 0)); then
    if [[ -n "$SKILLS_ROOT" ]]; then
      printf 'Error: not a skills root and not a skill under %s: %s\n' "$SKILLS_ROOT" "${DISPATCH_BAD[*]}" >&2
    else
      printf 'Error: not a skills root, and no skills root resolved, so it cannot be a skill name either: %s\n' "${DISPATCH_BAD[*]}" >&2
    fi
    exit 2
  fi
  if ((${#DISPATCH_BAD_PATHS[@]} > 0)); then
    printf 'Error: skills root does not exist: %s\n' "${DISPATCH_BAD_PATHS[*]}" >&2
    exit 2
  fi

  DISPATCH_PASSED=0
  DISPATCH_FAILED=0
  DISPATCH_ENV_ERR=0
  DISPATCH_LEFT=0
  for dispatch_root in "${DISPATCH_ROOTS[@]}"; do
    printf '=== %s ===\n' "$dispatch_root"
    dispatch_found=0
    for dispatch_dir in "$dispatch_root"/*/; do
      [[ -f "$dispatch_dir/SKILL.md" ]] || continue
      dispatch_found=1
      dispatch_leaf="${dispatch_dir%/}"
      dispatch_leaf="${dispatch_leaf##*/}"
      (
        CDPATH='' cd -- "$dispatch_root" || exit 2
        CHECK_SKILL_SKILLS_ROOT="$dispatch_root" \
          CHECK_SKILL_REQUIRE_EVALS="$REQUIRE_EVALS" \
          CHECK_SKILL_INVOKING_TOPLEVEL="$INVOKING_TOPLEVEL" \
          exec bash "$SCRIPT_PATH" -- "$dispatch_leaf"
      )
      case $? in
      0) DISPATCH_PASSED=$((DISPATCH_PASSED + 1)) ;;
      1) DISPATCH_FAILED=$((DISPATCH_FAILED + 1)) ;;
      3) DISPATCH_LEFT=$((DISPATCH_LEFT + 1)) ;;
      *) DISPATCH_ENV_ERR=1 ;;
      esac
    done
    ((dispatch_found == 0)) && printf 'No skills found under: %s\n' "$dispatch_root"
  done
  printf '\n%d passed, %d failed\n' "$DISPATCH_PASSED" "$DISPATCH_FAILED"
  ((DISPATCH_LEFT == 0)) || printf '%d skill(s) left script tests to CI, counted in neither tally above\n' "$DISPATCH_LEFT"
  if ((DISPATCH_ENV_ERR)); then
    printf 'Error: one or more skill runs hit an environment error and are counted in neither tally above\n' >&2
    exit 2
  fi
  ((DISPATCH_FAILED > 0)) && exit 1
  ((DISPATCH_LEFT > 0)) && exit 3
  exit 0
elif ((${#DISPATCH_BAD_PATHS[@]} > 0)); then
  printf 'Error: skills root does not exist: %s\n' "${DISPATCH_BAD_PATHS[*]}" >&2
  exit 2
elif (($# > 1)); then
  printf 'Error: more than one skill name given: %s\n' "$*" >&2
  printf 'Pass one <skill-name>, or one or more skills roots.\n' >&2
  exit 2
fi

if [[ -n "$BASE_REF_ERR" ]]; then
  printf '%s\n' "$BASE_REF_ERR" >&2
  exit 2
fi

if (($# == 0)); then
  printf 'Usage: check-skill.sh [--require-evals] <skill-name> | <root> [<root> ...] (run with --help)\n' >&2
  exit 1
fi
SKILL_NAME="$1"

if [[ -z "$SKILLS_ROOT" ]]; then
  printf '%s\n' "$SKILLS_ROOT_ERR" >&2
  exit 2
fi

SKILL_DIR="$SKILLS_ROOT/$SKILL_NAME"
SKILL_MD="$SKILL_DIR/SKILL.md"

SKILL_REL=""
if [[ "$HAVE_GIT" == 1 ]]; then
  SKILL_REL="$(git -C "$SKILL_DIR" rev-parse --show-prefix 2>/dev/null | tr -d '\r')"
  SKILL_REL="${SKILL_REL%/}"
fi

DESC_CHAR_CAP=1536
DESC_FIELD_CAP=1024
DESC_FIELD_WARN_MARGIN=32
DESC_FIELD_BASELINE="${CHECK_SKILL_DESC_FIELD_BASELINE:-}"
NAME_MAX_LEN=64
NAME_RESERVED_WORDS='anthropic claude'
LINE_HARD_CAP=500
SYNCED_MAX_AGE_DAYS=180
TOC_LINE_THRESHOLD=300
TOC_HEAD_LINES=40
TOC_MIN_ANCHORS=3
POCOCK_DESC_MAX=419
POCOCK_BODY_MAX=160
POCOCK_DESC_MEDIAN=130
POCOCK_BODY_MEDIAN=70
DESC_TARGET_DEFAULT=250
DESC_WARN_DEFAULT=$POCOCK_DESC_MAX
ROUTER_TOKEN_CAP=5000
ROUTER_CHARS_PER_TOKEN=4

FAILED=0
WARNINGS=0
SCRIPT_TESTS_LEFT=0

err() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILED=$((FAILED + 1))
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
  WARNINGS=$((WARNINGS + 1))
}

note() {
  printf 'INFO: %s\n' "$*"
}

path_list_contains() {
  local file="$1" needle="$2" row
  while IFS= read -r row || [[ -n "$row" ]]; do
    row="${row%%#*}"
    row="${row#"${row%%[![:space:]]*}"}"
    row="${row%"${row##*[![:space:]]}"}"
    [[ "$row" == "$needle" ]] && return 0
  done <"$file"
  return 1
}

use_when_items() {
  sed "s/\\([[:alpha:]]\\)'\\([[:alpha:]]\\)/\\1\\2/g" 2>/dev/null |
    awk -v sq="'" '
      { text = text " " $0 }
      END {
        # text opens with a space, so a non-letter always precedes the match.
        if (!match(tolower(text), /[^a-z]use when/)) exit
        clause = substr(text, RSTART + 9) " "
        sub(/^:/, "", clause)
        if (match(clause, /[.;] /)) clause = substr(clause, 1, RSTART - 1)
        n = split(clause, items, ",")
        for (i = 1; i <= n; i++) {
          item = items[i]
          gsub(/^[ \t]+|[ \t]+$/, "", item)
          sub(/^(or|and)[ \t]+/, "", item)
          if (item != "" && !index(item, sq)) print sq item sq
        }
      }'
}

listing_triggers() {
  {
    printf '%s\n%s\n' "$1" "$2" | skill_frontmatter::extract_triggers
    printf '%s\n' "$1" | use_when_items
    printf '%s\n' "$2" | use_when_items
  } | sort -u
}

fm_listing_triggers() {
  local fm="$1"
  listing_triggers \
    "$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field description <<<"$fm")")" \
    "$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field when_to_use <<<"$fm")")"
}

base_ref_fm() {
  git -C "$REPO_ROOT" cat-file -e "$BASE_REF:$1/SKILL.md" 2>/dev/null || return 1
  git -C "$REPO_ROOT" show "$BASE_REF:$1/SKILL.md" 2>/dev/null | skill_frontmatter::extract
  return 0
}

if [[ ! -d "$SKILL_DIR" ]]; then
  if [[ "$SKILL_NAME" == *:* ]]; then
    q_leaf=$(printf '%q' "${SKILL_NAME##*:}")
    err "Skill not found: '$SKILL_NAME'. This looks like a plugin:skill name — the checker resolves a bare skill name under one skills root, not Claude Code's internal plugin-cache layout. To gate a marketplace-installed skill, point the root at its installed skills dir:
    CHECK_SKILL_SKILLS_ROOT=~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/skills bash \"\${CLAUDE_PLUGIN_ROOT}/scripts/check-skill.sh\" $q_leaf
  The cache is a copy, not a git checkout, so the git-backed checks (3/8/9) no-op there (a 'new skill / skipped' result is expected)."
  else
    err "Skill not found: $SKILL_DIR. Set CHECK_SKILL_SKILLS_ROOT (or skill-quality's skills_root) to the directory that CONTAINS '$SKILL_NAME' as a subdirectory."
  fi
  exit 1
fi
if [[ ! -f "$SKILL_MD" ]]; then
  err "SKILL.md not found: $SKILL_MD"
  exit 1
fi

IS_PLUGIN_SKILL=0
PLUGIN_DIR=""
[[ -f "$SKILL_DIR/../../.claude-plugin/plugin.json" ]] && IS_PLUGIN_SKILL=1
if [[ "$IS_PLUGIN_SKILL" == 1 ]]; then
  PLUGIN_DIR="$(cd "$SKILL_DIR/../.." && pwd)"
fi

summarize() {
  printf '\n'
  if ((FAILED > 0)); then
    printf 'CHECK-SKILL %s: FAIL — %d error(s), %d warning(s)\n' "$SKILL_NAME" "$FAILED" "$WARNINGS" >&2
    exit 1
  fi
  if ((SCRIPT_TESTS_LEFT > 0)); then
    printf 'CHECK-SKILL %s: INCOMPLETE — 0 errors, %d warning(s), %d script test(s) left to CI\n' "$SKILL_NAME" "$WARNINGS" "$SCRIPT_TESTS_LEFT"
    exit 3
  fi
  printf 'CHECK-SKILL %s: PASS — 0 errors, %d warning(s)\n' "$SKILL_NAME" "$WARNINGS"
  exit 0
}

vc_strip_negated_mutate() {
  printf '%s' "$1" | sed -E \
    's/(never|not|does not|do not)[[:space:]]+(rewrites?|fixes|remediates?|mutates|applies)[^.;]*//g'
}

vc_lead_mutate() {
  grep -qE \
    '(^|[[:space:]])remediates[[:space:]]|and[[:space:]]+remediate([^[:alnum:]]|$)|(^|[[:space:]])rewrites[[:space:]]+(the|your|files)|(^|[[:space:]])fixes[[:space:]]+(the|your|files)|applies[[:space:]]+(fixes|edits|changes|patches)|mutates[[:space:]]+(the|on|files)|and[[:space:]]+fix([^[:alnum:]]|$)' \
    < <(vc_strip_negated_mutate "$1")
}

vc_lead_readonly() {
  local t="$1"
  case "$t" in
  *"read-only by default"* | *"read only by default"*) return 1 ;;
  *) ;;
  esac
  vc_lead_mutate "$t" && return 1
  grep -qE \
    'read[- ]only|report[- ]only|findings[[:space:]]+(report|only)|no edits applied|never[[:space:]]+(writes|mutates|modifies|edits)|does not[[:space:]]+(modify|edit|write|mutate)|zero mutations|performs[[:space:]]+zero[[:space:]]+mutations' \
    <<<"$t"
}

vc_has_override() {
  grep -qE \
    -- '--fix|explicit[[:space:]]+(user[[:space:]]+)?override|only[[:space:]]+behind|never[[:space:]]+on[[:space:]]+bare|not[[:space:]]+on[[:space:]]+bare|read[- ]only[[:space:]]+on[[:space:]]+bare' \
    <<<"$1"
}

vc_body_bare_mutate() {
  printf '%s\n' "$1" | awk '
    { low = tolower($0) }
    low ~ /never|does not|do not|not on bare/ { next }
    low ~ /mutates on bare invocation|edits on bare invocation|writes on bare invocation/ { found = 1 }
    low ~ /on bare invocation[, ]+(edit|write|apply|rewrite|mutate)([^a-z]|$)/ { found = 1 }
    END { exit !found }
  '
}

vc_body_never_mutate() {
  grep -qE \
    'never[[:space:]]+mutates|does not[[:space:]]+modify|no edits applied|never[[:space:]]+writes|read[- ]only[[:space:]]+on[[:space:]]+bare|does not[[:space:]]+fix[[:space:]]+on[[:space:]]+bare|nothing edits' \
    < <(tr '[:upper:]' '[:lower:]' <<<"$1")
}

check_25() {
  local VC_BODY VC_LEAF VC_LEAD VC_LEAD_LC VC_ALL_LC VC_HIT
  VC_BODY="$(awk '
    NR == 1 && /^---[ \t]*$/ { fm = 1; next }
    fm { if (/^---[ \t]*$/) fm = 0; next }
    /^[[:space:]]*(```|~~~)/ {
      m = ($0 ~ /```/) ? "b" : "t"
      if (!fence) { fence = 1; ch = m } else if (m == ch) fence = 0
      next
    }
    fence { next }
    { print }
  ' "$SKILL_MD")"

  VC_LEAF="${SKILL_NAME%%-*}"
  VC_LEAD="$(printf '%s' "$CUR_DESC" | sed -E 's/[Uu]se[[:space:]]+[Ww]hen:.*//')"
  VC_LEAD_LC="$(printf '%s' "$VC_LEAD" | tr '[:upper:]' '[:lower:]')"
  VC_ALL_LC="$(printf '%s %s' "$CUR_DESC" "$CUR_WTU" | tr '[:upper:]' '[:lower:]')"

  VC_HIT=""
  if [[ "$VC_LEAF" == "audit" || "$VC_LEAF" == "scan" ]] &&
    vc_lead_mutate "$VC_LEAD_LC" && ! vc_has_override "$VC_ALL_LC"; then
    VC_HIT="leaf verb '$VC_LEAF' is a read-only findings report (plugin-philosophy Naming) but the description lead advertises mutation without an explicit override"
  elif [[ "$VC_LEAF" == "clean" || "$VC_LEAF" == "tidy" || "$VC_LEAF" == "fix" ]] &&
    vc_lead_readonly "$VC_LEAD_LC"; then
    VC_HIT="leaf verb '$VC_LEAF' mutates the target (plugin-philosophy Naming) but the description lead claims the skill is read-only/report-only"
  elif vc_lead_readonly "$VC_LEAD_LC" && vc_body_bare_mutate "$VC_BODY"; then
    VC_HIT="description lead claims read-only but the body mutates on bare invocation (or hides an unadvertised mutation path)"
  elif vc_lead_mutate "$VC_LEAD_LC" && ! vc_has_override "$VC_ALL_LC" &&
    vc_body_never_mutate "$VC_BODY"; then
    VC_HIT="description lead advertises fixing but the body claims the skill never mutates"
  fi

  if [[ -n "$VC_HIT" ]]; then
    err "description/verb-contract mismatch: $VC_HIT — a mismatch is a factual defect in the listing surface being routed on, not a style issue. Hand-verify; --fix in the description is the compliant override shape. Out of scope: whether this skill should gain a --fix path, and any rename"
  else
    note "description/verb-contract polarity consistent (or no Naming verb / no polarity language)"
  fi
}

FRONTMATTER="$(skill_frontmatter::extract <"$SKILL_MD")"
CUR_DESC="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field description <<<"$FRONTMATTER")")"
CUR_WTU="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::field when_to_use <<<"$FRONTMATTER")")"

if [[ "${CHECK_SKILL_ONLY:-}" == 25 ]]; then
  check_25
  summarize
fi

if [[ -z "$FRONTMATTER" ]]; then
  err "no YAML frontmatter block found (expected content between two '---' fences)"
else
  grep -qE '^description:[[:space:]]*[^[:space:]]' <<<"$FRONTMATTER" || err "frontmatter missing 'description:'"

  RAW_NAME="$(skill_frontmatter::field name <<<"$FRONTMATTER")"
  RAW_NAME="${RAW_NAME%%[[:space:]]#*}"
  RAW_NAME="${RAW_NAME%"${RAW_NAME##*[![:space:]]}"}"
  CUR_NAME="$(skill_frontmatter::strip_quotes "$RAW_NAME")"
  if [[ -n "$CUR_NAME" && ! "$CUR_NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    err "frontmatter name '$CUR_NAME' is not kebab-case ([a-z0-9] and hyphens, per the Agent Skills spec)"
  elif [[ -n "$CUR_NAME" && "$CUR_NAME" != "$SKILL_NAME" ]]; then
    err "frontmatter name '$CUR_NAME' does not match skill directory '$SKILL_NAME'"
  elif [[ -n "$CUR_NAME" && "$IS_PLUGIN_SKILL" == 1 ]]; then
    warn "frontmatter name '$CUR_NAME' repeats the plugin skill's directory — omit it unless the bare /$CUR_NAME alias is wanted"
  fi

  EFFECTIVE_NAME="${CUR_NAME:-$SKILL_NAME}"
  name_source="directory name"
  [[ -n "$CUR_NAME" ]] && name_source="declared name"
  NAME_CP_LEN="$(skill_frontmatter::codepoint_len "$EFFECTIVE_NAME")"
  if ((NAME_CP_LEN > NAME_MAX_LEN)); then
    err "skill name '$EFFECTIVE_NAME' is $NAME_CP_LEN codepoints (Agent Skills spec maximum $NAME_MAX_LEN); Claude Code loads it but the spec's validator rejects it, so shorten the $name_source"
  fi
  for reserved_word in $NAME_RESERVED_WORDS; do
    if [[ "$EFFECTIVE_NAME" == *"$reserved_word"* ]]; then
      warn "skill name '$EFFECTIVE_NAME' contains the word '$reserved_word', which a Skills API upload rejects ('anthropic' and 'claude' are reserved there; Claude Code loads it and ships bundled skills carrying the word); rename the $name_source if the skill will ever be uploaded"
    fi
  done

  if grep -qE '^model:' <<<"$FRONTMATTER"; then
    RAW_MODEL="$(skill_frontmatter::field model <<<"$FRONTMATTER")"
    CUR_MODEL="$(skill_frontmatter::strip_quotes "$RAW_MODEL")"
    if [[ -z "$CUR_MODEL" || "$CUR_MODEL" =~ [[:space:]] ]]; then
      err "frontmatter model '$CUR_MODEL' is empty or contains whitespace; use inherit or one model alias or id (characters such as ':', '/' and '@' in a provider id are allowed)"
    elif [[ "$RAW_MODEL" != "$CUR_MODEL" ]]; then
      :
    elif [[ "$CUR_MODEL" == [\[\{]* || "${CUR_MODEL,,}" =~ ^(true|false|yes|no|on|off|null|~)$ ]]; then
      err "frontmatter model '$CUR_MODEL' is not a string: YAML reads an unquoted collection, boolean or null as a non-string value; use inherit or one model alias or id"
    fi
  fi

  desc_lines="$(awk '
    !seen && /^description:/ { seen = 1; sub(/^description:[[:space:]]*/, ""); sub(/[[:space:]]+#.*$/, ""); print; next }
    seen && /^[^[:space:]]/ { exit }
    seen && !/^[[:space:]]*$/ { sub(/^[[:space:]]+/, ""); sub(/(^|[[:space:]]+)#.*$/, ""); print }
  ' <<<"$FRONTMATTER")"
  desc_first="${desc_lines%%$'\n'*}"
  desc_first="${desc_first%"${desc_first##*[![:space:]]}"}"
  case "$desc_first" in
  \"* | \'*) ;;
  \|* | \>*) ;; # portability-ok: case glob for a literal greater-than block scalar, not a GNU grep word boundary
  *)
    if grep -qE ':([[:space:]]|$)' <<<"$desc_lines"; then
      err "description is an unquoted plain scalar containing ': ' or a line ending in ':' (YAML mapping indicator). Quote it or reword it; unparsed frontmatter loads the skill with no fields set"
    fi
    ;;
  esac

  if grep -qE '^compatibility:[[:space:]]*' <<<"$FRONTMATTER"; then
    RAW_COMPAT="$(skill_frontmatter::field compatibility <<<"$FRONTMATTER")"
    CUR_COMPAT="$(skill_frontmatter::strip_quotes "$RAW_COMPAT")"
    COMPAT_LEN="$(skill_frontmatter::codepoint_len "$CUR_COMPAT")"
    if ((COMPAT_LEN < 1 || COMPAT_LEN > 500)); then
      err "compatibility is $COMPAT_LEN characters (Agent Skills spec requires 1-500 when the field is present); omit it when the skill has no environment requirement"
    fi
  fi
fi

JOINER_LEN=0
CUR_TRIG="$(listing_triggers "$CUR_DESC" "$CUR_WTU")"
DESC_LEN=${#CUR_DESC}
WTU_LEN=${#CUR_WTU}
((WTU_LEN > 0)) && JOINER_LEN=3
COMBINED_LEN=$((DESC_LEN + JOINER_LEN + WTU_LEN))
if ((COMBINED_LEN > DESC_CHAR_CAP)); then
  err "description+when_to_use is $COMBINED_LEN chars (cap $DESC_CHAR_CAP — overflow truncates the listing)"
elif ((WTU_LEN > 0)); then
  note "description+when_to_use $COMBINED_LEN/$DESC_CHAR_CAP chars (desc $DESC_LEN + joiner $JOINER_LEN + when_to_use $WTU_LEN)"
else
  note "description length $DESC_LEN/$DESC_CHAR_CAP chars"
fi

DESC_CP_LEN="$(skill_frontmatter::codepoint_len "$CUR_DESC")"

DESC_FIELD_BASELINED=0
if [[ -n "$DESC_FIELD_BASELINE" ]]; then
  if [[ ! -f "$DESC_FIELD_BASELINE" ]]; then
    err "CHECK_SKILL_DESC_FIELD_BASELINE=$DESC_FIELD_BASELINE does not exist — a missing baseline must not silently become a clean run"
  elif [[ -n "$SKILL_REL" ]] && path_list_contains "$DESC_FIELD_BASELINE" "$SKILL_REL"; then
    DESC_FIELD_BASELINED=1
  fi
fi

if ((DESC_CP_LEN > DESC_FIELD_CAP)); then
  if ((DESC_FIELD_BASELINED == 1)); then
    warn "description alone is $DESC_CP_LEN codepoints (Agent Skills spec field maximum $DESC_FIELD_CAP) — recorded as a pre-existing breach in $DESC_FIELD_BASELINE; still rejected on Skills API upload, and the row leaves the baseline once it is brought under the maximum"
  else
    err "description alone is $DESC_CP_LEN codepoints (Agent Skills spec field maximum $DESC_FIELD_CAP) — rejected on Skills API upload; shorten the description rather than dropping a trigger phrase"
  fi
elif ((DESC_FIELD_BASELINED == 1)); then
  err "stale baseline row in $DESC_FIELD_BASELINE: $SKILL_REL is now $DESC_CP_LEN/$DESC_FIELD_CAP codepoints and no longer breaches — remove the row"
elif ((DESC_CP_LEN > DESC_FIELD_CAP - DESC_FIELD_WARN_MARGIN)); then
  warn "$SKILL_NAME: description is $DESC_CP_LEN codepoints, within $DESC_FIELD_WARN_MARGIN of the Agent Skills spec field maximum $DESC_FIELD_CAP — $((DESC_FIELD_CAP - DESC_CP_LEN)) left, so the next added clause breaches it"
else
  note "description field $DESC_CP_LEN/$DESC_FIELD_CAP codepoints (spec field maximum)"
fi

HAVE_BASE_FM=0
BASE_FM=""
if [[ "$HAVE_GIT" == 1 ]] && BASE_FM="$(base_ref_fm "$SKILL_REL")"; then
  HAVE_BASE_FM=1
fi

if [[ "$HAVE_GIT" != 1 ]]; then
  note "not in a git repo — trigger-keyword preservation (check 3) skipped"
elif [[ "$HAVE_BASE_FM" == 1 ]]; then
  BASE_TRIG="$(fm_listing_triggers "$BASE_FM")"
  if [[ -n "$BASE_TRIG" ]]; then
    MISSING="$(comm -23 <(printf '%s\n' "$BASE_TRIG") <(printf '%s\n' "$CUR_TRIG"))"
    if [[ -n "$MISSING" ]]; then
      SKILLS_REL_PARENT=""
      [[ "$SKILL_REL" == */* ]] && SKILLS_REL_PARENT="${SKILL_REL%/*}"
      SIB_NAMES=()
      SIB_TRIGS=()
      for other_md in "$SKILLS_ROOT"/*/SKILL.md; do
        [[ -f "$other_md" && "$other_md" != "$SKILL_MD" ]] || continue
        sib_path="${other_md%/SKILL.md}"
        SIB_NAMES+=("${sib_path##*/}")
        SIB_TRIGS+=("$(fm_listing_triggers "$(skill_frontmatter::extract <"$other_md")")")
      done
      LOST=()
      while IFS= read -r phrase; do
        [[ -n "$phrase" ]] || continue
        MOVE_HOST=""
        for ((sib_i = 0; sib_i < ${#SIB_NAMES[@]}; sib_i++)); do
          grep -qxF -- "$phrase" <<<"${SIB_TRIGS[$sib_i]}" || continue
          OTHER_NAME="${SIB_NAMES[$sib_i]}"
          OTHER_REL="${SKILLS_REL_PARENT:+$SKILLS_REL_PARENT/}$OTHER_NAME"
          if OTHER_BASE_FM="$(base_ref_fm "$OTHER_REL")"; then
            grep -qxF -- "$phrase" <<<"$(fm_listing_triggers "$OTHER_BASE_FM")" && continue
          fi
          MOVE_HOST="$OTHER_NAME"
          break
        done
        if [[ -n "$MOVE_HOST" ]]; then
          warn "trigger phrase $phrase moved to sibling skill '$MOVE_HOST' — listing coverage preserved, confirm the move is deliberate"
        else
          LOST+=("$phrase")
        fi
      done <<<"$MISSING"
      if ((${#LOST[@]} > 0)); then
        warn "dropped trigger keyword(s) vs $BASE_REF: ${LOST[*]}. Confirm the description still names each intent these phrases carried (deliberate consolidation), or restore them"
      fi
    else
      note "all $(printf '%s\n' "$BASE_TRIG" | grep -c .) base-ref trigger phrase(s) preserved"
    fi
  fi
else
  note "no $BASE_REF version (new skill) — keyword-preservation check skipped"
fi

LINE_COUNT="$(grep -c '' "$SKILL_MD")"
if ((LINE_COUNT >= LINE_HARD_CAP)); then
  err "SKILL.md is $LINE_COUNT lines (hard cap $LINE_HARD_CAP)"
else
  note "SKILL.md $LINE_COUNT/$LINE_HARD_CAP lines"
fi

INTERNAL_DIRS='context|templates|scripts|reference|references|actions|evals|lanes|catalog|vendor'
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  resolve_base="$SKILL_DIR"
  check_ref="$ref"
  # shellcheck disable=SC2016  # single quotes deliberate: ${CLAUDE_PLUGIN_ROOT} is a literal placeholder prefix
  if [[ "$ref" == '${CLAUDE_PLUGIN_ROOT}/'* ]]; then
    # shellcheck disable=SC2016
    check_ref="${ref#'${CLAUDE_PLUGIN_ROOT}/'}"
    if [[ "$IS_PLUGIN_SKILL" != 1 || -z "$PLUGIN_DIR" ]]; then
      note "check-5 skip (plugin-root placeholder outside a plugin): $ref"
      continue
    fi
    resolve_base="$PLUGIN_DIR"
  fi
  if [[ "$HAVE_GIT" == 1 ]] && git -C "$REPO_ROOT" check-ignore -q "$resolve_base/$check_ref" 2>/dev/null; then
    note "check-5 skip (gitignored runtime path): $check_ref"
    continue
  fi
  if [[ ! -e "$resolve_base/$check_ref" ]]; then
    ref_line="$(grep -nF "$ref" "$SKILL_MD" 2>/dev/null | head -1 | cut -d: -f1)"
    REF_HOST=""
    for other_md in "$SKILLS_ROOT"/*/SKILL.md; do
      [[ -f "$other_md" && "$other_md" != "$SKILL_MD" ]] || continue
      if [[ -e "${other_md%/SKILL.md}/$check_ref" ]]; then
        REF_HOST="${other_md%/SKILL.md}"
        REF_HOST="${REF_HOST##*/}"
        break
      fi
    done
    if [[ -z "$REF_HOST" ]]; then
      if [[ "$resolve_base" == "$PLUGIN_DIR" ]]; then
        err "broken plugin-root ref: $ref (no such file under the plugin root; cited at SKILL.md:${ref_line:-?} — hand-verify the line before fixing, may be an illustrative example)"
      else
        err "broken skill-internal ref: $ref (no such file under the skill dir; cited at SKILL.md:${ref_line:-?} — hand-verify the line before fixing, may be an illustrative example)"
      fi
    else
      if [[ "$IS_PLUGIN_SKILL" == 1 ]]; then
        ref_fix="\${CLAUDE_PLUGIN_ROOT}/skills/$REF_HOST/$check_ref"
      else
        ref_fix="../$REF_HOST/$check_ref"
      fi
      err "broken skill-internal ref: $ref (no such file under the skill dir; cited at SKILL.md:${ref_line:-?} — hand-verify the line before fixing, may be an illustrative example). A file with that path DOES exist under sibling skill '$REF_HOST': if that is the file meant, this is a cross-skill citation, and a bare path always resolves against the CITING skill's dir — write it as $ref_fix. If the names merely collide, the ref is unrelated to that sibling."
    fi
  fi
done < <(
  {
    grep -oE "\`(\$\{CLAUDE_PLUGIN_ROOT\}/)?($INTERNAL_DIRS)/[A-Za-z0-9._/-]+\`" "$SKILL_MD" 2>/dev/null | tr -d '`'
    grep -oE "\]\((\$\{CLAUDE_PLUGIN_ROOT\}/)?($INTERNAL_DIRS)/[A-Za-z0-9._/#-]+\)" "$SKILL_MD" 2>/dev/null |
      sed -E 's/^\]\(//; s/\)$//; s/#.*$//'
  } | sort -u
)

BS="\\\\"
BACKSLASH_EXTS='md|sh|bash|py|json|jsonc|txt|yaml|yml|mjs|js|ts|ps1|csv|toml|xml|html'
while IFS= read -r bs_file; do
  [[ -f "$bs_file" ]] || continue
  bs_rel="${bs_file#"$SKILL_DIR"/}"
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    ref_line="$(grep -nF "$ref" "$bs_file" 2>/dev/null | head -1 | cut -d: -f1)"
    err "backslash path separator in skill-internal ref: $ref (cited at ${bs_rel}:${ref_line:-?}); a plugin component path with a backslash is rejected at load on macOS and Linux, so write it with forward slashes: ${ref//\\//}"
  done < <(
    {
      grep -oE "\`(\$\{CLAUDE_PLUGIN_ROOT\}[/$BS])?($INTERNAL_DIRS)(${BS}[A-Za-z0-9._-]+)*${BS}[A-Za-z0-9._-]+\.($BACKSLASH_EXTS)\`" "$bs_file" 2>/dev/null | tr -d '`'
      grep -oE "\]\((\$\{CLAUDE_PLUGIN_ROOT\}[/$BS])?($INTERNAL_DIRS)(${BS}[A-Za-z0-9._-]+)*${BS}[A-Za-z0-9._-]+\.($BACKSLASH_EXTS)(#[^)]*)?\)" "$bs_file" 2>/dev/null |
        sed -E 's/^\]\(//; s/\)$//; s/#.*$//'
    } | sort -u
  )
done < <(
  {
    printf '%s\n' "$SKILL_MD"
    for bs_dir in reference references context; do
      [[ -d "$SKILL_DIR/$bs_dir" ]] || continue
      find "$SKILL_DIR/$bs_dir" -type f -name '*.md'
    done
  } | sort -u
)

ML_CMD=(npx --no-install markdownlint-cli2)
ml_d="$(CDPATH='' cd -- "$SKILL_DIR" && pwd)"
while [[ -n "$ml_d" ]]; do
  if [[ -x "$ml_d/node_modules/.bin/markdownlint-cli2" ]]; then
    ML_CMD=("$ml_d/node_modules/.bin/markdownlint-cli2")
    break
  fi
  ml_d="${ml_d%/*}"
done
if [[ "${CHECK_SKILL_SKIP_MARKDOWNLINT:-}" == "1" ]]; then
  note "markdownlint check skipped (CHECK_SKILL_SKIP_MARKDOWNLINT=1)"
elif [[ "${ML_CMD[0]}" != npx ]] || command -v npx >/dev/null 2>&1; then
  ML_CWD="$(git -C "$SKILL_DIR" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  ML_FILE="$SKILL_MD"
  if [[ -n "$ML_CWD" ]]; then
    ML_FILE="$(git -C "$SKILL_DIR" rev-parse --show-prefix | tr -d '\r')SKILL.md"
  else
    ML_CWD=.
  fi
  if ML_OUT="$(cd -- "$ML_CWD" && "${ML_CMD[@]}" "$ML_FILE" 2>&1)"; then
    note "markdownlint clean"
  elif grep -qE '^[^[:space:]]+:[0-9]+' <<<"$ML_OUT"; then
    err "markdownlint failed:
$(printf '%s\n' "$ML_OUT" | grep -E '^[^[:space:]]+:[0-9]+' | head -10)"
  else
    warn "markdownlint-cli2 unavailable (not installed / not resolvable) — markdownlint check skipped"
  fi
else
  warn "npx not found — markdownlint check skipped"
fi

if [[ "${CHECK_SKILL_SKIP_SCRIPT_TESTS:-}" == "1" ]]; then
  note "script tests skipped (CHECK_SKILL_SKIP_SCRIPT_TESTS=1)"
elif [[ -d "$SKILL_DIR/scripts" ]]; then
  SKILL_TOPLEVEL="$("${GIT_UNSET[@]}" git -C "$SKILL_DIR" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  [[ -n "$SKILL_TOPLEVEL" ]] && SKILL_TOPLEVEL="$(cd -- "$SKILL_TOPLEVEL" && pwd -P)"
  while IFS= read -r test_sh; do
    [[ -z "$test_sh" ]] && continue
    if [[ -z "$INVOKING_TOPLEVEL" || "$SKILL_TOPLEVEL" != "$INVOKING_TOPLEVEL" ]]; then
      note "script tests skipped: the skill is outside the current repository"
      break
    fi
    test_real="$(cd -- "${test_sh%/*}" && pwd -P)/${test_sh##*/}"
    test_rel="${test_real#"$INVOKING_TOPLEVEL"/}"
    if [[ "$test_real" != "$INVOKING_TOPLEVEL"/* ]]; then
      note "script test skipped: ${test_sh#"$SKILL_DIR"/} is not tracked in the current repository"
      continue
    fi
    if ! "${GIT_UNSET[@]}" git -C "$INVOKING_TOPLEVEL" --literal-pathspecs \
      ls-files --error-unmatch -- "$test_rel" >/dev/null 2>&1; then
      if ! "${GIT_UNSET[@]}" git -C "$INVOKING_TOPLEVEL" --literal-pathspecs \
        ls-files --others --exclude-standard --error-unmatch -- "$test_rel" >/dev/null 2>&1; then
        note "script test skipped: ${test_sh#"$SKILL_DIR"/} is not tracked in the current repository"
        continue
      fi
      skills_real="$(cd -- "$SKILL_DIR/.." && pwd -P)/"
      if [[ "$skills_real" != "$INVOKING_TOPLEVEL"/* ]] ||
        [[ -z "$("${GIT_UNSET[@]}" git -C "$INVOKING_TOPLEVEL" --literal-pathspecs \
          ls-files -- "./${skills_real#"$INVOKING_TOPLEVEL"/}" 2>/dev/null | head -n 1)" ]]; then
        note "script test skipped: ${test_sh#"$SKILL_DIR"/} is not committed in the current repository yet"
        continue
      fi
    fi
    if [[ -n "${PLUGIN_TEST_DEADLINE:-}" ]] && (($(date +%s) >= PLUGIN_TEST_DEADLINE)); then
      printf 'SKIP %s (past the deadline, left to CI)\n' "$test_rel"
      SCRIPT_TESTS_LEFT=$((SCRIPT_TESTS_LEFT + 1))
      continue
    fi
    test_out=""
    if test_out="$("${GIT_UNSET[@]}" -u CHECK_SKILL_INVOKING_TOPLEVEL -u PLUGIN_TEST_DEADLINE bash "$test_sh" 2>&1 </dev/null)"; then
      note "script test passed: ${test_sh#"$SKILL_DIR"/}"
    else
      err "script test failed: ${test_sh#"$SKILL_DIR"/}"
      if (($(printf '%s\n' "$test_out" | wc -l) > 100)); then
        printf '... output truncated to the last 100 lines; run bash %s for all of it\n' "$test_sh" >&2
        printf '%s\n' "$test_out" | tail -n 100 >&2
      else
        printf '%s\n' "$test_out" >&2
      fi
    fi
  done < <(find "$SKILL_DIR/scripts" -name '*.test.sh' -type f 2>/dev/null | sort)
fi

VENDOR_SHA_DEFINITION="SHA-256 of the one non-dotfile under vendor/ with CR bytes removed; with several, SHA-256 of their '<sha>  <path under vendor/>' lines sorted bytewise"

vendor_content_sha() {
  local dir="$1" hasher f
  if command -v sha256sum >/dev/null 2>&1; then
    hasher=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    hasher=(shasum -a 256)
  else
    return 0
  fi
  local -a files=()
  while IFS= read -r -d '' f; do files+=("${f#"$dir"/}"); done < <(find "$dir" -name '.*' ! -path "$dir" -prune -o -type f -print0)
  if ((${#files[@]} == 1)); then
    tr -d '\r' <"$dir/${files[0]}" | "${hasher[@]}" | awk '{print $1}'
    return 0
  fi
  for f in "${files[@]}"; do
    printf '%s  %s\n' "$(tr -d '\r' <"$dir/$f" | "${hasher[@]}" | awk '{print $1}')" "$f"
  done | LC_ALL=C sort | "${hasher[@]}" | awk '{print $1}'
}

metadata_value() {
  skill_frontmatter::strip_quotes "$(skill_frontmatter::metadata_field "$1" <<<"$2")"
}

if [[ "$HAVE_GIT" != 1 ]]; then
  [[ -d "$SKILL_DIR/vendor" ]] && note "not in a git repo — vendor byte-identity (check 8) skipped"
elif [[ -d "$SKILL_DIR/vendor" && "$HAVE_BASE_FM" == 1 ]]; then
  VENDOR_STATUS="$(git -C "$REPO_ROOT" diff --name-status -M100% "$BASE_REF" -- "$SKILL_REL/vendor/" 2>/dev/null)"
  if git -C "$REPO_ROOT" diff --quiet "$BASE_REF" -- "$SKILL_REL/vendor/" 2>/dev/null; then
    note "vendor/ unchanged vs $BASE_REF"
  elif [[ -n "$VENDOR_STATUS" ]] && ! grep -qv '^R100' <<<"$VENDOR_STATUS"; then
    note "vendor/ only renamed vs $BASE_REF (contents byte-identical)"
  else
    BASE_UPSTREAM_VERSION="$(metadata_value upstream-version "$BASE_FM")"
    CUR_UPSTREAM_VERSION="$(metadata_value upstream-version "$FRONTMATTER")"
    BASE_UPSTREAM_SHA="$(metadata_value upstream-sha "$BASE_FM")"
    CUR_UPSTREAM_SHA="$(metadata_value upstream-sha "$FRONTMATTER")"
    if [[ -n "$CUR_UPSTREAM_VERSION" && "$CUR_UPSTREAM_VERSION" != "$BASE_UPSTREAM_VERSION" ]]; then
      note "vendor/ changed vs $BASE_REF, paired with an upstream-version bump ($BASE_UPSTREAM_VERSION -> $CUR_UPSTREAM_VERSION) — legitimate sync"
    elif [[ -n "$CUR_UPSTREAM_SHA" && "$CUR_UPSTREAM_SHA" != "$BASE_UPSTREAM_SHA" ]]; then
      VENDOR_SHA="$(vendor_content_sha "$SKILL_DIR/vendor")"
      if [[ -z "$VENDOR_SHA" ]]; then
        err "vendor/ changed vs $BASE_REF with an upstream-sha bump, but neither sha256sum nor shasum is on PATH to verify it"
      elif [[ "$CUR_UPSTREAM_SHA" == "$VENDOR_SHA" ]]; then
        note "vendor/ changed vs $BASE_REF, paired with an upstream-sha bump matching the vendored content ($VENDOR_SHA) — legitimate sync"
      else
        err "vendor/ changed vs $BASE_REF with metadata.upstream-sha $CUR_UPSTREAM_SHA, but the vendored content hashes to $VENDOR_SHA ($VENDOR_SHA_DEFINITION)"
      fi
    else
      err "vendor/ changed vs $BASE_REF — vendored content carries a byte-identical guarantee; rewrites must not touch vendor/ (no accompanying metadata.upstream-version bump, nor a metadata.upstream-sha bump matching the content: $VENDOR_SHA_DEFINITION)"
    fi
  fi
fi

if [[ "$HAVE_GIT" != 1 ]]; then
  note "not in a git repo — stale-tracking metadata (check 9) skipped"
elif [[ "$HAVE_BASE_FM" == 1 ]]; then
  for key in upstream-version synced upstream-sha; do
    if grep -qE "^[[:space:]]*$key:" <<<"$BASE_FM"; then
      grep -qE "^[[:space:]]*$key:" <<<"$FRONTMATTER" ||
        err "metadata key '$key' present at $BASE_REF but dropped (stale-tracking metadata for a vendored skill)"
    fi
  done
fi

if ! grep -qEi '^##+[[:space:]]+(gotchas|quirks)' "$SKILL_MD" &&
  [[ ! -f "$SKILL_DIR/context/gotchas.md" ]] &&
  [[ ! -f "$SKILL_DIR/reference/gotchas.md" ]] &&
  [[ ! -f "$SKILL_DIR/references/gotchas.md" ]]; then
  warn "no Gotchas surface (inline '## Gotchas' or context/gotchas.md) — confirm the skill has no observed failure history"
fi

if [[ -n "$CUR_DESC" ]]; then
  if ! grep -qi 'use when' <<<"$CUR_DESC$CUR_WTU" &&
    [[ -z "$(printf '%s\n' "$CUR_WTU" | skill_frontmatter::extract_triggers)" ]]; then
    warn "description has no 'Use when:' trigger phrasing — a description is a trigger spec, not a summary"
  fi
fi

if [[ "$HAVE_GIT" != 1 ]]; then
  note "not in a git repo — committed-artifact scan (check 13) skipped"
else
  CACHE_HITS="$(git -C "$REPO_ROOT" ls-files "$SKILL_REL" 2>/dev/null | grep -E '__pycache__|\.pyc$|/node_modules/' || true)"
  if [[ -n "$CACHE_HITS" ]]; then
    err "committed cache/build artifact(s) under the skill dir: $(printf '%s' "$CACHE_HITS" | head -3 | tr '\n' ' ')"
  fi
fi

evals_warrant_exemptions_file() {
  local d="${1:-}" parent
  while [[ -n "$d" && "$d" != "/" ]]; do
    if [[ -f "$d/scripts/evals-warrant-exemptions.txt" ]]; then
      printf '%s\n' "$d/scripts/evals-warrant-exemptions.txt"
      return 0
    fi
    parent="$(dirname -- "$d")"
    [[ "$parent" == "$d" ]] && break
    d="$parent"
  done
  return 1
}

evals_warrant_skip() {
  local file
  file="$(evals_warrant_exemptions_file "${REPO_ROOT:-$SKILL_DIR}")" || return 1
  path_list_contains "$file" "$1"
}

plugin_case_tags_skill() {
  local d re="^tags:[[:space:]]*\[(.*,)?[[:space:]]*['\"]?${SKILL_NAME}['\"]?[[:space:]]*(,.*)?\]"
  for d in "$(dirname -- "$SKILLS_ROOT")"/evals/*/; do
    [[ -f "$d/case.yaml" ]] && grep -qE "$re" "$d/case.yaml" && return 0
    [[ -f "$d/prompt.md" ]] &&
      grep -qE "$re" < <(awk 'NR == 1 { if ($0 != "---") exit; next } $0 == "---" { exit } { print }' "$d/prompt.md") &&
      return 0
  done
  return 1
}

evals_skill_rel=""
if [[ "$SKILLS_ROOT" =~ /plugins/([^/]+)/skills$ ]]; then
  evals_skill_rel="plugins/${BASH_REMATCH[1]}/skills/${SKILL_NAME}"
fi

if [[ ! -f "$SKILL_DIR/evals/evals.json" ]]; then
  if [[ "$REQUIRE_EVALS" == "1" ]]; then
    if [[ -n "$evals_skill_rel" ]] && plugin_case_tags_skill; then
      note "evals: a plugin suite case tags $SKILL_NAME"
    elif [[ -n "$evals_skill_rel" ]] && evals_warrant_skip "$evals_skill_rel"; then
      note "evals skip recorded in scripts/evals-warrant-exemptions.txt for $evals_skill_rel"
    else
      err "skill ships no evals/evals.json and no plugin suite case tags it — required when the skill is new or its SKILL.md changed"
    fi
  elif grep -qE '^##+[[:space:]]+Actions?([^[:alnum:]_]|$)' "$SKILL_MD" &&
    ! { [[ -n "$evals_skill_rel" ]] && plugin_case_tags_skill; }; then
    warn "action-router-shaped skill with no evals/evals.json — check whether the skill warrants triggering evals"
  fi
fi

for spoke_dir in context reference references templates lanes actions; do
  [[ -d "$SKILL_DIR/$spoke_dir" ]] || continue
  grep -q "$spoke_dir/" "$SKILL_MD" ||
    warn "orphan spoke: $spoke_dir/ exists but SKILL.md never references it (progressive-disclosure routing gap)"
done

if [[ -n "$FRONTMATTER" ]] && ! grep -q 'category:' < <(grep -A8 '^metadata:' <<<"$FRONTMATTER"); then
  note "no metadata.category in frontmatter (optional — category not machine-readable)"
fi

if [[ -d "$SKILL_DIR/vendor" ]]; then
  SYNCED_VAL="$(awk '/^metadata:/{m=1;next} m && /^[a-zA-Z]/{m=0} m && /^[[:space:]]+synced:/{print $2;exit}' <<<"$FRONTMATTER" | tr -d "\"'")"
  if [[ "$SYNCED_VAL" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    # portability-ok: GNU-first, BSD fallback co-located (#1510)
    if SYNCED_EPOCH="$(date -u -d "$SYNCED_VAL" +%s 2>/dev/null || date -u -j -f '%Y-%m-%d' "$SYNCED_VAL" +%s 2>/dev/null)"; then
      AGE_DAYS=$((($(date -u +%s) - SYNCED_EPOCH) / 86400))
      if ((AGE_DAYS > SYNCED_MAX_AGE_DAYS)); then
        warn "vendor last synced $AGE_DAYS days ago (> $SYNCED_MAX_AGE_DAYS) — run the skill's update action"
      fi
    fi
  fi
fi

precompute_readonly_line() {
  local line="$1"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line#\$ }"

  case "$line" in
  *'>'* | *'<'* | *';'* | *'&'*) return 1 ;;
  *) ;;
  esac
  # shellcheck disable=SC2016  # single quotes are deliberate: '$(' is a literal glob, not a shell expansion
  case "$line" in *'$('*) return 1 ;; *) ;; esac
  case "$line" in *'`'*) return 1 ;; *) ;; esac
  # shellcheck disable=SC2016  # single quotes deliberate: \|\| and $ are literal regex, not a shell expansion
  local sanitized
  sanitized="$(sed -E 's/\|\|[[:space:]]*echo([[:space:]]|$)/ /g' <<<"$line")"
  case "$sanitized" in *'|'*) return 1 ;; *) ;; esac

  # shellcheck disable=SC2016  # single quotes are deliberate: $ is an ERE end anchor, not a shell expansion
  grep -qE '(^|[[:space:]])(-exec|-execdir|-ok|-okdir|-delete|-fprintf|-fprint0|-fprint|-fls|--output|--ext-diff|--textconv|rm|mv|cp|tee|sed|mkdir|touch)([[:space:]=]|$)' <<<"$line" && return 1

  local cmd="${line%%[[:space:]]*}"
  case "$cmd" in
  ls | pwd | cat | find | date | uname | whoami | hostname | wc | head | tail | echo | printf | id | stat | du | df | basename | dirname | realpath | readlink | groups | tree | sw_vers) return 0 ;;
  git)
    local sub="${line#git}"
    sub="${sub#"${sub%%[![:space:]]*}"}"
    sub="${sub%%[[:space:]]*}"
    case "$sub" in
    status | log | diff | show | rev-parse | rev-list | describe | ls-files | ls-tree | symbolic-ref | shortlog | blame | cat-file | for-each-ref | name-rev | whatchanged) return 0 ;;
    *) return 1 ;;
    esac
    ;;
  gh)
    case " $line " in
    *" create "* | *" edit "* | *" delete "* | *" merge "* | *" close "* | *" comment "*) return 1 ;;
    *" view "* | *" diff "* | *" list "* | *" status "* | *" checks "*) return 0 ;;
    *) return 1 ;;
    esac
    ;;
  *) return 1 ;;
  esac
}

PRECOMPUTE_CANDIDATE=0
# shellcheck disable=SC2016  # single quotes are deliberate: the backticks are literal regex
if ! grep -qE '(^|[[:space:]])!`|^[[:space:]]*```+!' "$SKILL_MD"; then
  # shellcheck disable=SC2016  # single quotes are deliberate: backticks and $ are literal regex, not shell expansion
  fence_open_re='^(```+)([^`]*)$'
  in_block=0
  fence_len=0
  is_shell=0
  block_ok=1
  block_has_cmd=0
  while IFS= read -r bl || [[ -n "$bl" ]]; do
    trimmed="${bl#"${bl%%[![:space:]]*}"}"
    if [[ "$trimmed" =~ $fence_open_re ]]; then
      ticks="${BASH_REMATCH[1]}"
      info="${BASH_REMATCH[2]}"
      n=${#ticks}
      info="${info#"${info%%[![:space:]]*}"}"
      info_first="${info%%[[:space:]]*}"
      if ((in_block == 0)); then
        in_block=1
        fence_len=$n
        block_ok=1
        block_has_cmd=0
        case "$info_first" in
        bash | sh | shell | zsh | console | shell-session | shellsession | sh-session) is_shell=1 ;;
        *) is_shell=0 ;;
        esac
      elif ((n >= fence_len)) && [[ -z "$info" ]]; then
        if ((is_shell == 1 && block_ok == 1 && block_has_cmd == 1)); then
          PRECOMPUTE_CANDIDATE=1
        fi
        in_block=0
        is_shell=0
      fi
      continue
    fi
    if ((in_block == 1 && is_shell == 1)); then
      if [[ -n "$trimmed" && "$trimmed" != \#* ]]; then
        block_has_cmd=1
        precompute_readonly_line "$bl" || block_ok=0
      fi
    fi
  done <"$SKILL_MD"
fi

if ((PRECOMPUTE_CANDIDATE == 1)); then
  # shellcheck disable=SC2016  # single quotes are deliberate: the backticks and ! in the advisory text are literal, not shell expansion
  warn 'precompute opportunity: a fenced shell block runs read-only context-gathering commands the skill could inline at load time via `!`command`` / ```! dynamic-context injection (preprocessed once at load, no per-invocation tool call). If the block runs on every invocation to gather context, convert it; if it is an illustrative example, ignore. Heuristic over fenced shell blocks — see https://code.claude.com/docs/en/skills#inject-dynamic-context'
fi

INJECTIONS=()
inj_in_fence=0
inj_fence_len=0
inj_is_injection=0
# shellcheck disable=SC2016  # single quotes deliberate: backticks and $ are literal regex, not shell expansion
inj_fence_re='^(```+)([^`]*)$'
while IFS= read -r il || [[ -n "$il" ]]; do
  itrim="${il#"${il%%[![:space:]]*}"}"
  if [[ "$itrim" =~ $inj_fence_re ]]; then
    iticks="${BASH_REMATCH[1]}"
    iinfo="${BASH_REMATCH[2]}"
    ilen=${#iticks}
    iinfo="${iinfo#"${iinfo%%[![:space:]]*}"}"
    if ((inj_in_fence == 0)); then
      inj_in_fence=1
      inj_fence_len=$ilen
      [[ "$iinfo" == '!'* ]] && inj_is_injection=1 || inj_is_injection=0
    elif ((ilen >= inj_fence_len)) && [[ -z "$iinfo" ]]; then
      inj_in_fence=0
      inj_is_injection=0
    fi
    continue
  fi
  if ((inj_in_fence == 1)); then
    if ((inj_is_injection == 1)) && [[ -n "$itrim" && "$itrim" != \#* ]]; then
      INJECTIONS+=("$il")
    fi
    continue
  fi
  # shellcheck disable=SC2016  # single quotes deliberate: the backticks are literal delimiters, not shell expansion
  while IFS= read -r inj_match; do
    inj_match="${inj_match#*'!`'}"
    inj_match="${inj_match%'`'}"
    INJECTIONS+=("$inj_match")
  done < <(grep -oE '(^|[[:space:]])!`[^`]+`' <<<"$il")
done <"$SKILL_MD"

if ((${#INJECTIONS[@]} > 0)); then
  # shellcheck disable=SC2016  # single quotes deliberate: \| and $ are literal ERE, not shell expansion
  bash_only_re='/dev/null|(^|[[:space:]])command[[:space:]]+-v([[:space:]]|$)|\|[[:space:]]*(head|tail|grep|sed|awk|cut|tr|wc|xargs|rev|nl|fold|paste|comm|join|column|uniq)([[:space:]]|$)'
  if grep -qE '^shell:[[:space:]]*[^[:space:]]' <<<"$FRONTMATTER"; then
    note "shell: declared — dynamic-context injection portability is the author's explicit choice"
  else
    bash_only_hit="$(printf '%s\n' "${INJECTIONS[@]}" | grep -oE "$bash_only_re" | head -1 || true)"
    if [[ -n "$bash_only_hit" ]]; then
      # shellcheck disable=SC2016  # single quotes deliberate: the backticked tokens in the message are literal
      err "\`!\` dynamic-context injection uses bash-only syntax ('$bash_only_hit') with no \`shell:\` frontmatter — on a host without Git Bash the injection falls through to the PowerShell tool and breaks. Declare \`shell: bash\` (or write portable commands). See https://code.claude.com/docs/en/skills#inject-dynamic-context"
    else
      # shellcheck disable=SC2016  # single quotes deliberate: the backticked tokens in the message are literal
      warn "\`!\` dynamic-context injection present with no \`shell:\` frontmatter — the commands look portable but static analysis can't prove it. Declare \`shell:\` explicitly, or confirm the commands run under the host's default shell"
    fi
  fi

  missing_fallback=0
  for inj in "${INJECTIONS[@]}"; do
    [[ "$inj" == *'||'* ]] || missing_fallback=$((missing_fallback + 1))
  done
  if ((missing_fallback > 0)); then
    # shellcheck disable=SC2016  # single quotes deliberate: the backticked tokens in the message are literal
    warn "$missing_fallback \`!\`-injected command(s) carry no \`|| <fallback>\` — an unguarded command can inline an error string into the prompt (see https://code.claude.com/docs/en/skills#when-an-injected-command-fails). Add a \`|| echo \"<fallback>\"\` (or shell-appropriate) continuation"
  fi
fi

FRESH_EYES_PROXIMITY_LINES=8
FRESH_EYES_JUDGE_RE='(^|[^a-z])self[- ](review|audit|assess|score|grade|verif)|(^|[^a-z])(review|verify|assess|grade|score|judge|critique)[a-z]*[[:space:]]+(your|its|their)[[:space:]]+own|(^|[^a-z])spot[- ]check|(^|[^a-z])outcome[[:space:]]+gate|(^|[^a-z])score[[:space:]]+each|(^|[^a-z])(called|calling[[:space:]]+(it|them|the[[:space:]]+[a-z]+))[[:space:]]+done([^a-z]|$)'

FRESH_EYES_FILES=("$SKILL_MD")
for spoke_dir in context templates reference references actions lanes catalog; do
  [[ -d "$SKILL_DIR/$spoke_dir" ]] || continue
  while IFS= read -r f; do
    [[ -n "$f" ]] && FRESH_EYES_FILES+=("$f")
  done < <(find "$SKILL_DIR/$spoke_dir" -type f -name '*.md' \
    -not -path '*/vendor/*' -not -path '*/evals/*' 2>/dev/null | sort)
done

for fe_file in "${FRESH_EYES_FILES[@]}"; do
  fe_rel="${fe_file#"$SKILL_DIR"/}"
  while IFS= read -r fe_line; do
    fe_kind="${fe_line%% *}"
    fe_ln="${fe_line#* }"
    case "$fe_kind" in
    DIRECTIVE_MALFORMED)
      err "malformed fresh-eyes-exempt directive ($fe_rel:$fe_ln) — expected '<!-- fresh-eyes-exempt: <class> -- <reason> -->' with class deterministic-gate|external-input|deferred (spec: skill-quality plugin, skills/check/reference/fresh-eyes-declarations.md)"
      ;;
    DIRECTIVE_NOREASON)
      err "fresh-eyes-exempt directive missing its '-- <reason>' ($fe_rel:$fe_ln) — justification is recorded at the suppression site (spec: skill-quality plugin, skills/check/reference/fresh-eyes-declarations.md)"
      ;;
    HIT_BOTH)
      note "fresh-eyes: judgment language at $fe_rel:$fe_ln carries BOTH delegation wording and an exemption directive — contradictory declaration, hand-verify"
      ;;
    HIT_WORDING)
      note "fresh-eyes: judgment language at $fe_rel:$fe_ln — fresh-context delegation declared nearby"
      ;;
    HIT_DIRECTIVE)
      note "fresh-eyes: judgment language at $fe_rel:$fe_ln — exemption directive declared nearby"
      ;;
    HIT_NONE)
      warn "same-context judgment language with no fresh-context delegation or exemption directive within $FRESH_EYES_PROXIMITY_LINES lines ($fe_rel:$fe_ln) — declaration may live in a referenced spoke — hand-verify (spec: skill-quality plugin, skills/check/reference/fresh-eyes-declarations.md)"
      ;;
    DIRECTIVE_STALE)
      warn "stale fresh-eyes-exempt directive ($fe_rel:$fe_ln) — no judgment-language hit within $FRESH_EYES_PROXIMITY_LINES lines; the heuristic list, not the directive, may be the gap — verify before removing"
      ;;
    *)
      err "check 21 internal error: unknown scan record '$fe_kind' ($fe_rel)"
      ;;
    esac
  done < <(awk -v P="$FRESH_EYES_PROXIMITY_LINES" -v JR="$FRESH_EYES_JUDGE_RE" '
    # Start of file counts as a paragraph break, so an indented block opening on
    # line one is recognized as one.
    BEGIN { fe_blank = 1; cm_in_comment = 0 }
    # NO ERE INTERVALS IN THIS PROGRAM. The three-space indent cap is written as
    # three optional spaces (" ? ? ?") and the ordered-marker digit cap as one
    # digit plus eight optional ones, never as {0,3} / {1,9}. Two mawk failures
    # motivate the rule, and both are silent: mawk 1.3.4 PANICS ("REcompile() -
    # panic: values still on machine stack") when an interval is immediately
    # followed by a group, killing the program before it emits a record, so every
    # malformed directive PASSes; mawk 1.3.3 does not implement intervals at all
    # and matches them as literal characters, so the same scan quietly never
    # fires. Both leave check 21 reporting a clean run over a file it never read.
    # Same portability intent as the [[:space:]] note above, one layer deeper.
    # Blockquote nesting depth of a raw line: the number of leading `>` markers,
    # each optionally followed by one space, under the three-space indent cap.
    function fe_depth_of(s,   d) {
      d = 0
      while (match(s, /^ ? ? ?> ?/)) { d++; s = substr(s, RSTART + RLENGTH) }
      return d
    }
    { sub(/\r$/, "") }
    # YAML frontmatter is not markdown, so nothing in it is a fence, a span, or a
    # directive. Parsing it as markdown let a block-scalar description containing
    # an example fence open `fe_fence` that the closing `---` never ended, which
    # suppressed the whole body and passed the file silently. Skip the region and
    # reset every structural carry at its terminator.
    NR == 1 && /^---[ \t]*$/ { fe_fm = 1; next }
    fe_fm {
      if (/^---[ \t]*$/) {
        fe_fm = 0
        fe_fence = 0; fe_open_pre = 0; fe_icode = 0; fe_blank = 1; cm_in_comment = 0
      }
      next
    }
    # Block-container prefixes come off before anything else looks at the line, so
    # container content parses exactly like top-level content. Markers interleave
    # (`> - ```), so strip until neither form matches.
    #
    # Inside a fence the strip applies only when the OPENER itself carried a
    # prefix — otherwise a nested `> ``` ` in the quoted example a fence itself
    # contains becomes a closer and leaks the block.
    #
    # NOTE: this awk program is a single-quoted shell string. An apostrophe in a
    # comment here terminates it and breaks the script — keep prose apostrophe-free.
    {
      fe_raw = $0
      # A container-nested fence dies with its container. CommonMark ends a fence
      # inside a blockquote or list item when that container ends, but this fence
      # state is a single global flag: without the reset an unclosed
      # `> ```markdown` swallows every following top-level line, and a malformed
      # directive in later prose silently PASSes.
      if (fe_fence && fe_open_pre) {
        if (fe_open_bq) {
          # A blockquote marker must repeat on every line — a fenced block inside
          # a quote takes no lazy continuation, and a blank line ends the quote.
          # DEPTH matters, not mere presence: a fence opened at "> > " lives in the
          # inner quote, so a later depth-1 line has left that quote and ends the
          # fence even though it still carries a marker.
          if (fe_depth_of(fe_raw) < fe_open_depth) { fe_fence = 0; fe_open_pre = 0 }
        } else {
          # A list item continues by indentation to its content column: a blank
          # line stays inside the item, a dedent ends it.
          fe_ind = 0
          while (substr(fe_raw, fe_ind + 1, 1) == " ") fe_ind++
          if (fe_raw !~ /^[ \t]*$/ && fe_ind < fe_open_ind) { fe_fence = 0; fe_open_pre = 0 }
        }
      }
      if (!fe_fence || fe_open_pre) {
        do {
          fe_pre = $0
          sub(/^ ? ? ?> ?/, "", $0)
          sub(/^ ? ? ?([-*+]|[0-9][0-9]?[0-9]?[0-9]?[0-9]?[0-9]?[0-9]?[0-9]?[0-9]?[.)])[ \t]+/, "", $0)
        } while ($0 != fe_pre)
      }
      fe_stripped = ($0 != fe_raw)
      fe_bq_depth = fe_depth_of(fe_raw)
      fe_strip_len = length(fe_raw) - length($0)
    }
    # Fence matching. What this scanner models, what it does not attempt, and what
    # it does when it cannot tell are stated once in the Parsing contract section
    # of skills/check/reference/fresh-eyes-declarations.md — that doc is the claim
    # this code implements; do not restate it here.
    /^ ? ? ?(```+|~~~+)/ {
      fe_run = $0
      sub(/^ */, "", fe_run)
      fe_char = substr(fe_run, 1, 1)
      fe_len = 0
      while (substr(fe_run, fe_len + 1, 1) == fe_char) fe_len++
      fe_info = substr(fe_run, fe_len + 1)
      # A fence line is markdown structure, never the blank line or indented run
      # an indented code block needs, so it resets that tracking either way.
      fe_icode = 0; fe_blank = 0
      if (fe_fence) {
        if (fe_char == fe_open_char && fe_len >= fe_open_len \
            && fe_info ~ /^[ \t]*$/) fe_fence = 0
        next
      }
      # A backtick fence opener cannot carry backticks in its info string —
      # such a line is ordinary prose, so it falls through to the scanners
      # instead of opening a fence.
      if (!(fe_char == "`" && index(fe_info, "`"))) {
        fe_fence = 1; fe_open_char = fe_char; fe_open_len = fe_len; fe_open_pre = fe_stripped; fe_open_depth = fe_bq_depth
        fe_open_bq = (fe_bq_depth > 0); fe_open_ind = fe_strip_len
        next
      }
    }
    fe_fence { next }
    {
      line = $0
      # Structural ambiguity: a four-space-indented line here is either an
      # indented code block or a list-item continuation, and telling those
      # apart needs a block parser this scanner does not have. Rather than
      # guess, it declines its HARD verdicts on such a line — see the parsing
      # contract in skills/check/reference/fresh-eyes-declarations.md for the
      # asymmetry that makes declining the safe direction.
      if (line ~ /^[ \t]*$/) fe_blank = 1
      else {
        fe_ind2 = 0
        if (line ~ /^\t/) fe_ind2 = 4
        else while (substr(line, fe_ind2 + 1, 1) == " ") fe_ind2++
        fe_icode = (fe_ind2 >= 4 && (fe_icode || fe_blank))
        fe_blank = 0
      }
      # Inline code spans and backslash escapes are not reconstructed — a line
      # that carries either is ambiguous for directive hard verdicts and is
      # skipped by the Form 1 and judgment detectors. See the parsing contract.
      fe_bt_ambig = (index(line, "`") > 0)
      fe_esc_ambig = (index(line, "\\<") > 0) # portability-ok: index() for literal backslash+less-than, not a GNU grep word boundary
      fe_line_ambig = (fe_icode || fe_bt_ambig || fe_esc_ambig)
      # Classify each directive on the line independently, bounded at its own
      # `-->`. Testing the whole line let a valid directive elsewhere on it lend
      # its class and reason to a malformed neighbor, so an unknown-class
      # suppression could hide beside a well-formed one and never FAIL.
      dir_rest = line
      # The directive name needs a terminator after it, or a prefix-only match
      # reads an ordinary comment about `fresh-eyes-exemption` as a directive and
      # FAILs the skill on prose.
      while (match(dir_rest, /<!--[ \t]*fresh-eyes-exempt([ \t]|:|-->)/)) {
        dir_one = substr(dir_rest, RSTART)
        dir_rest = substr(dir_rest, RSTART + RLENGTH)
        dir_end = index(dir_one, "-->")
        if (dir_end) dir_one = substr(dir_one, 1, dir_end + 2)
        dir_n++
        d[dir_n] = NR
        damb[dir_n] = fe_line_ambig
        if (dir_one ~ /<!--[ \t]*fresh-eyes-exempt:[ \t]*(deterministic-gate|external-input|deferred)[ \t]+--[ \t]+[^ \t].*-->/) {
          dt[dir_n] = "valid"
        } else if (dir_one ~ /<!--[ \t]*fresh-eyes-exempt:[ \t]*(deterministic-gate|external-input|deferred)[ \t]*(--[ \t]*)?-->/) {
          dt[dir_n] = "noreason"
        } else {
          dt[dir_n] = "malformed"
        }
      }
      # Form 1 is VISIBLE PROSE by contract, so an HTML comment cannot carry it:
      # a hidden `<!-- dispatch this to a fresh-context agent -->` would be exactly
      # the parallel marker Form 1 exists to rule out, and it was satisfying the
      # delegation detector. Comments come off only AFTER the directives above are
      # classified, since a directive IS a comment. Comment state carries across
      # lines until the closing `-->`, so delegation wording split across a
      # multi-line comment does not satisfy Form 1.
      if (cm_in_comment) {
        cm_e = index(line, "-->")
        if (cm_e) {
          line = substr(line, cm_e + 3)
          cm_in_comment = 0
        } else {
          line = ""
        }
      }
      cm_keep = ""
      while ((cm_p = index(line, "<!--")) > 0) {
        cm_keep = cm_keep substr(line, 1, cm_p - 1) " "
        line = substr(line, cm_p + 4)
        cm_e = index(line, "-->")
        if (!cm_e) {
          if (!fe_bt_ambig && !fe_esc_ambig) cm_in_comment = 1
          line = ""
          break
        }
        line = substr(line, cm_e + 3)
      }
      line = cm_keep line
      if (fe_bt_ambig || fe_esc_ambig) next
      low = tolower(line)
      # Delegation wording needs a worker actually named on the line — bare
      # "in a fresh context" prose assigns no one and does not declare. Both
      # halves match as whole words with their inflections, so embedded stems
      # cannot satisfy the requirement: "agentless" is not a worker, and
      # "Refresh context" is not the fresh-context wording.
      if (low ~ /(^|[^a-z0-9_])fresh[- ]context([^a-z0-9_]|$)/ \
          && low ~ /(^|[^a-z0-9_])((sub-?)?agents?|workers?|advisors?|reviewers?|verifiers?|dispatch(es|ed|ing)?|delegat(e|es|ed|ing|ion|ions))([^a-z0-9_]|$)/) {
        word_n++; w[word_n] = NR
      }
      if (low ~ JR) { judge_n++; j[judge_n] = NR }
    }
    END {
      # A directive whose structural context was ambiguous yields no hard
      # verdict: both of these FAIL the skill, and failing an author on a
      # parser artifact is worse than missing one malformed directive.
      for (i = 1; i <= dir_n; i++) {
        if (damb[i]) continue
        if (dt[i] == "noreason") printf "DIRECTIVE_NOREASON %d\n", d[i]
        else if (dt[i] == "malformed") printf "DIRECTIVE_MALFORMED %d\n", d[i]
      }
      for (i = 1; i <= judge_n; i++) {
        hasw = 0; hasd = 0
        for (k = 1; k <= word_n; k++) if (w[k] >= j[i] - P && w[k] <= j[i] + P) hasw = 1
        # An ambiguous directive cannot satisfy a judgment step either: if the
        # scanner is not confident it is live markdown, a literal example inside
        # an indented code block would otherwise silence the WARN it deserves.
        for (k = 1; k <= dir_n; k++) if (dt[k] == "valid" && !damb[k] && d[k] >= j[i] - P && d[k] <= j[i] + P) hasd = 1
        if (hasw && hasd) printf "HIT_BOTH %d\n", j[i]
        else if (hasw) printf "HIT_WORDING %d\n", j[i]
        else if (hasd) printf "HIT_DIRECTIVE %d\n", j[i]
        else printf "HIT_NONE %d\n", j[i]
      }
      for (i = 1; i <= dir_n; i++) {
        # Ambiguous placement also withholds the stale WARN: the scanner is not
        # confident the directive is live markdown, so it makes no claim either way.
        if (dt[i] != "valid" || damb[i]) continue
        used = 0
        for (k = 1; k <= judge_n; k++) if (j[k] >= d[i] - P && j[k] <= d[i] + P) used = 1
        if (!used) printf "DIRECTIVE_STALE %d\n", d[i]
      }
    }
  ' "$fe_file")
done

if skill_frontmatter::has_metadata_field summary <<<"$FRONTMATTER"; then
  CUR_SUMMARY="$(skill_frontmatter::metadata_field summary --raw <<<"$FRONTMATTER")"
  if SUMMARY_ERR="$(skill_frontmatter::summary_error "$CUR_SUMMARY")"; then
    note "summary passes the shared contract"
  else
    err "metadata.$SUMMARY_ERR"
  fi
fi

CC_SIGNAL='done|complete|verified|verify|confirm|assert|exit|pass|green|criteria|criterion|until|settle|expect|observable|observed|succeed|fail'
CC_BLOCKS="$(awk -v sigre="$CC_SIGNAL" '
  function close_block() {
    if (steps >= 3 && !sig) bad = bad (bad ? "," : "") start "-" last
    steps = 0; sig = 0; had_blank = 0
  }
  /^[[:space:]]*(```|~~~)/ {
    m = ($0 ~ /^[[:space:]]*```/) ? "b" : "t"
    if (!fence) { fence = 1; fence_ch = m } else if (m == fence_ch) fence = 0
    next
  }
  fence { next }
  {
    lower = tolower($0)
    if ($0 ~ /^[[:space:]]*[0-9]+[.)][[:space:]]/) {
      n = $0
      sub(/^[[:space:]]*/, "", n)
      sub(/[.)].*$/, "", n)
      n = n + 0
      if (steps > 0 && had_blank && n <= last_n) close_block()
      if (steps == 0) start = NR
      steps++; last = NR; last_n = n; had_blank = 0
      if (lower ~ sigre) sig = 1
    } else if ($0 ~ /^[[:space:]]*$/) {
      had_blank = 1
    } else if (steps > 0 && $0 ~ /^[[:space:]]+[^[:space:]]/) {
      last = NR; had_blank = 0
      if (lower ~ sigre) sig = 1
    } else {
      close_block()
    }
  }
  END { close_block(); print bad }
' "$SKILL_MD")"
if [[ -n "$CC_BLOCKS" ]]; then
  warn "numbered procedure(s) at lines $CC_BLOCKS carry no completion-criteria signal — steps risk premature completion; give each step an observable done-condition (write-side doctrine: docs-hygiene:write-for-agents)"
else
  note "completion-criteria signal present (or no 3+-step numbered procedure)"
fi

INVOCATION_RUBRIC='docs/contracts/invocation-mode/README.md'
DMI_RAW="$(skill_frontmatter::field disable-model-invocation <<<"$FRONTMATTER")"
DMI_TRIMMED="${DMI_RAW#"${DMI_RAW%%[![:space:]]*}"}"
DMI_TRIMMED="${DMI_TRIMMED%"${DMI_TRIMMED##*[![:space:]]}"}"
DMI_VAL="${DMI_TRIMMED,,}"
case "$DMI_VAL" in
  true | yes | on | 1) DMI_BOOL=true ;;
  false | no | off | 0) DMI_BOOL=false ;;
  *) DMI_BOOL= ;;
esac
if [[ -z "$DMI_VAL" ]]; then
  if [[ "$SKILL_REL" == plugins/*/skills/* ]]; then
    err "frontmatter has no explicit disable-model-invocation key — every skill in this marketplace states its invocation mode (the absent-key default is false; write it out so the choice is auditable). Rubric: $INVOCATION_RUBRIC"
  else
    warn "frontmatter has no explicit disable-model-invocation key — the absent-key default is false, so behavior is unchanged; writing it out makes the choice auditable (marketplace-fleet convention: $INVOCATION_RUBRIC)"
  fi
elif [[ -z "$DMI_BOOL" ]]; then
  if [[ "$DMI_TRIMMED" == \"*\" || "$DMI_TRIMMED" == \'*\' ]]; then
    err "disable-model-invocation is the quoted string $DMI_TRIMMED — YAML reads that as a string, not a boolean; write it unquoted as true, yes, on or 1, or false, no, off or 0, in any letter case"
  else
    err "disable-model-invocation is '$DMI_TRIMMED' — expected a boolean: true, yes, on or 1, or false, no, off or 0, in any letter case"
  fi
elif [[ "$DMI_BOOL" == "true" ]]; then
  if [[ "$SKILL_NAME" == "setup" ]]; then
    note "invocation mode: user-invoked only — exception class (ii), setup contract"
  else
    note "invocation mode: user-invoked only — hand-verify it against an exception class ((i) side-effect/manual-timing, (ii) setup, (iii) maintainer-only) in $INVOCATION_RUBRIC; a static scan cannot attribute the class"
  fi
else
  note "invocation mode: model-invoked (fleet default)"
fi

check_25

while IFS= read -r toc_md; do
  [[ -f "$toc_md" ]] || continue
  toc_lines="$(grep -c '' "$toc_md")"
  ((toc_lines > TOC_LINE_THRESHOLD)) || continue
  toc_anchors="$(head -n "$TOC_HEAD_LINES" "$toc_md" | grep -o '](#' | wc -l | tr -d '[:space:]')"
  if ((toc_anchors < TOC_MIN_ANCHORS)); then
    warn "${toc_md#"$SKILL_DIR"/} is $toc_lines lines with no table of contents in its first $TOC_HEAD_LINES lines (${toc_anchors:-0} in-page anchor links; $TOC_MIN_ANCHORS or more count as a TOC); add a Contents block listing its section anchors so a reader jumps instead of scanning"
  fi
done < <(
  for toc_dir in reference references context; do
    [[ -d "$SKILL_DIR/$toc_dir" ]] || continue
    find "$SKILL_DIR/$toc_dir" -type f -name '*.md'
  done | sort
)

SKILL_TOKEN='/[a-z0-9-]+:[a-z0-9-]+'

section_block() {
  awk -v s="$1" 'NR > s { if ($0 ~ /^## /) exit; print }' "$SKILL_MD"
}

bullet_shapes() {
  awk -v tok="$SKILL_TOKEN" '
    function flush(   rest, n, lead, t) {
      if (b == "") return
      n = 0; rest = b; lead = ""; split("", seen)
      while (match(rest, tok)) {
        t = substr(rest, RSTART, RLENGTH)
        if (n == 0 && !(t in seen)) lead = substr(rest, 1, RSTART - 1)
        if (!(t in seen)) { seen[t] = 1; n++ }
        rest = substr(rest, RSTART + RLENGTH)
      }
      if (n == 0) notoken++
      else {
        if (n > 1) multi++
        sub(/^- /, "", lead)
        if (lead !~ /[[:alnum:]][^:]*:[[:space:]]/) nolead++
      }
      if (tolower(b) ~ /unsure/ && b ~ /\/session-flow:workflow/) filler++
      b = ""
    }
    /^- / { flush(); b = $0; next }
    /^[[:space:]]+[^[:space:]]/ { if (b != "") b = b " " $0; next }
    { flush() }
    END { flush(); print notoken + 0, multi + 0, nolead + 0, filler + 0 }'
}

NEXT_STAGE_BEARING='^(explore|research|plan|implement|test|review|verify|pr|retro)$'
NEXT_ROUTING_HEADING='^##[[:space:]]+(handoff|routing|integration|skill chaining)'

NEXT_LINE="$(grep -nE '^## Next[[:space:]]*$' "$SKILL_MD" | head -1 | cut -d: -f1)"
if [[ -z "$NEXT_LINE" ]]; then
  NEXT_STAGE="$(metadata_value workflow-stage "$FRONTMATTER")"
  if [[ "$NEXT_STAGE" =~ $NEXT_STAGE_BEARING ]] && ! grep -qiE "$NEXT_ROUTING_HEADING" "$SKILL_MD"; then
    warn "no '## Next' section on a stage-bearing skill (workflow-stage: $NEXT_STAGE): a mid-sequence skill names its successor in one, before '## Gotchas' (skill-bodies rule)"
  else
    note "no '## Next' section: fine for a terminal skill; a skill with a natural successor names it there (skill-bodies rule)"
  fi
else
  NEXT_GOTCHAS_LINE="$(grep -nEi '^##[[:space:]]+(gotchas|quirks)' "$SKILL_MD" | head -1 | cut -d: -f1)"
  NEXT_LAST_H2="$(grep -nE '^## ' "$SKILL_MD" | tail -1 | cut -d: -f1)"
  NEXT_HIT=""
  if [[ -n "$NEXT_GOTCHAS_LINE" ]] && ((NEXT_LINE > NEXT_GOTCHAS_LINE)); then
    NEXT_HIT="placed after '## Gotchas'; the rule puts it before"
  elif [[ -z "$NEXT_GOTCHAS_LINE" ]] && ((NEXT_LINE == NEXT_LAST_H2)); then
    NEXT_HIT="is the last section; the rule places it before the last H2"
  fi
  NEXT_BLOCK="$(section_block "$NEXT_LINE")"
  NEXT_BULLETS="$(grep -cE '^- ' <<<"$NEXT_BLOCK" || true)"
  if ((NEXT_BULLETS == 0)); then
    NEXT_FIRST="$(grep -vE '^[[:space:]]*$' <<<"$NEXT_BLOCK" | head -1 || true)"
    if [[ -z "$NEXT_FIRST" ]]; then
      NEXT_HIT="${NEXT_HIT:+$NEXT_HIT; }body is empty"
    elif ! grep -qE "^\`?${SKILL_TOKEN}(\`|[[:space:]]|[.,;:]|$)" <<<"$NEXT_FIRST"; then
      NEXT_HIT="${NEXT_HIT:+$NEXT_HIT; }first line does not open with a /plugin:skill invocation"
    fi
  else
    if ((NEXT_BULLETS == 1)); then
      NEXT_HIT="${NEXT_HIT:+$NEXT_HIT; }a single bullet; write it as the one-line form"
    fi
    read -r NEXT_NOTOKEN NEXT_MULTI NEXT_NOLEAD NEXT_FILLER <<<"$(bullet_shapes <<<"$NEXT_BLOCK")"
    if ((NEXT_NOTOKEN > 0)); then
      NEXT_HIT="${NEXT_HIT:+$NEXT_HIT; }$NEXT_NOTOKEN bullet(s) name no /plugin:skill successor"
    fi
    if ((NEXT_MULTI > 0)); then
      NEXT_HIT="${NEXT_HIT:+$NEXT_HIT; }$NEXT_MULTI bullet(s) name more than one skill; one target per bullet"
    fi
    if ((NEXT_NOLEAD > 0)); then
      NEXT_HIT="${NEXT_HIT:+$NEXT_HIT; }$NEXT_NOLEAD bullet(s) do not open with a '<result>: ' lead"
    fi
    if ((NEXT_FILLER > 0)); then
      NEXT_HIT="${NEXT_HIT:+$NEXT_HIT; }carries the 'unsure where this leaves the work' bullet; /session-flow:workflow is the fallback without it"
    fi
  fi
  NEXT_OPERATIVE="$(grep -oiE 'skill tool|installed|(^|[^[:alnum:]_])(is|are|if|when)( not)? enabled([^[:alnum:]_]|$)|fall ?back|otherwise' <<<"$NEXT_BLOCK" | head -1 | sed -E -e 's/^[^[:alpha:]]+//' -e 's/[^[:alpha:]]+$//' || true)"
  if [[ -n "$NEXT_OPERATIVE" ]]; then
    NEXT_HIT="${NEXT_HIT:+$NEXT_HIT; }carries operative-chain phrasing ('$NEXT_OPERATIVE'); a successor is a mention, with no Skill-tool phrasing, availability gate, or fallback clause"
  fi
  if [[ -n "$NEXT_HIT" ]]; then
    warn "'## Next' section $NEXT_HIT. The skill-bodies rule wants one /plugin:skill line, or two or more '<result>: <target>.' bullets with one target each, placed before '## Gotchas'"
  else
    note "'## Next' section present and in the mention-only shape"
  fi
fi

RELATED_LINE="$(grep -nE '^## Related[[:space:]]*$' "$SKILL_MD" | head -1 | cut -d: -f1)"
if [[ -n "$RELATED_LINE" ]]; then
  read -r RELATED_NOTOKEN _ RELATED_NOLEAD _ <<<"$(section_block "$RELATED_LINE" | bullet_shapes)"
  if ((RELATED_NOTOKEN + RELATED_NOLEAD > 0)); then
    warn "'## Related' has $((RELATED_NOTOKEN + RELATED_NOLEAD)) bullet(s) not in the '<condition>: /plugin:skill [args].' form (skill-bodies rule)"
  fi
fi

SEE_ALSO_LINE="$(grep -nE '^## See also[[:space:]]*$' "$SKILL_MD" | head -1 | cut -d: -f1)"
if [[ -n "$SEE_ALSO_LINE" ]]; then
  SEE_ALSO_SKILL="$(section_block "$SEE_ALSO_LINE" | grep -oE "$SKILL_TOKEN" | head -1 || true)"
  if [[ -n "$SEE_ALSO_SKILL" ]]; then
    warn "'## See also' names the skill $SEE_ALSO_SKILL; it holds files only, and a skill goes under '## Next' or '## Related' (skill-bodies rule)"
  fi
fi

DESC_PLUGINS_ROOT="$(cd "$SKILL_DIR/../../.." 2>/dev/null && pwd || true)"
while IFS= read -r desc_bare; do
  [[ -n "$desc_bare" && -f "$DESC_PLUGINS_ROOT/${desc_bare%%:*}/skills/${desc_bare#*:}/SKILL.md" ]] || continue
  warn "description names '$desc_bare' without the slash; write a skill token as /$desc_bare (skill-bodies rule)"
  break
done < <(grep -oE "(^|[[:space:](,;'\"])[a-z][a-z0-9-]*:[a-z][a-z0-9-]*([[:space:]).,;'\"]|$)" <<<"$CUR_DESC" | sed -E "s/^[[:space:](,;'\"]//; s/[[:space:]).,;'\"]$//" || true)

META_REGISTRY="$SCRIPT_DIR/metadata-registry.txt"
META_KEYS="$(awk '
  /^metadata:[[:space:]]*$/ { inmeta = 1; next }
  /^[^[:space:]]/ { inmeta = 0 }
  inmeta && /^[[:space:]]+[A-Za-z0-9_.-]+:/ {
    match($0, /^[[:space:]]+/)
    if (indent == "") indent = RLENGTH
    if (RLENGTH != indent) next
    key = $0
    sub(/^[[:space:]]+/, "", key)
    sub(/:.*/, "", key)
    print key
  }' <<<"$FRONTMATTER")"
if [[ -z "$META_KEYS" ]]; then
  :
elif [[ ! -f "$META_REGISTRY" ]]; then
  note "metadata registry $META_REGISTRY not found — metadata key check (28) skipped"
else
  META_KNOWN="$(awk -F '\t' '!/^[[:space:]]*(#|$)/ { print $1 }' "$META_REGISTRY")"
  META_UNKNOWN=0
  while IFS= read -r meta_key; do
    if ! grep -qxF -- "$meta_key" <<<"$META_KNOWN"; then
      warn "metadata key '$meta_key' is not in the metadata registry (scripts/metadata-registry.txt): name the consumer that reads it there, or drop the key (/playbooks:skill-authoring, Metadata)"
      META_UNKNOWN=$((META_UNKNOWN + 1))
    fi
  done <<<"$META_KEYS"
  ((META_UNKNOWN == 0)) && note "every metadata key is in the registry"
fi

HIST_HITS="$(awk '
  function cited(num, lower) {
    return lower ~ ("[a-z0-9_.-]+/[a-z0-9_.-]+#" num "([^0-9]|$)") ||
      lower ~ ("/(issues|pull)/" num "([^0-9]|$)")
  }
  # 1 when the line holds a bare #N the block does not cite upstream.
  function own_ref(s, lower,   m) {
    while (match(s, /(^|[^A-Za-z0-9_\/.&#-])#[0-9]+([^A-Za-z0-9_-]|$)/)) {
      m = substr(s, RSTART, RLENGTH)
      gsub(/[^0-9]/, "", m)
      if (!cited(m, lower)) return 1
      s = substr(s, RSTART + RLENGTH)
    }
    return 0
  }
  function flush(   i, s, lower) {
    if (n == 0) return
    lower = tolower(blk)
    if (!(lower ~ /as of[^0-9]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ && lower ~ /recheck/)) {
      for (i = 1; i <= n; i++) {
        s = txt[i]
        gsub(/`[^`]*`/, "", s)
        gsub(/\]\([^)]*\)/, "]", s)
        gsub(/<[^>]*>/, "", s)
        gsub(/https?:\/\/[^[:space:]]*/, "", s)
        if (own_ref(s, lower)) print num[i]
      }
    }
    n = 0
    blk = ""
  }
  NR == 1 && /^---[[:space:]]*$/ { infm = 1; next }
  infm { if (/^---[[:space:]]*$/) infm = 0; next }
  /^[[:space:]]*(```|~~~)/ { flush(); fence = !fence; next }
  fence { next }
  /^[[:space:]]*$/ { flush(); next }
  { n++; txt[n] = $0; num[n] = NR; blk = blk " " $0 }
  END { flush() }' "$SKILL_MD")"
if [[ -n "$HIST_HITS" ]]; then
  HIST_COUNT="$(grep -c . <<<"$HIST_HITS")"
  HIST_LINES="$(head -5 <<<"$HIST_HITS" | paste -sd, - | sed 's/,/, /g')"
  ((HIST_COUNT > 5)) && HIST_LINES="$HIST_LINES, and $((HIST_COUNT - 5)) more"
  warn "SKILL.md body cites this repository's history (#N) on line(s) $HIST_LINES: state the current rule and leave the issue or PR to the changelog, or put an upstream citation in a pointer record (/playbooks:skill-authoring, History and provenance)"
else
  note "no history references in the SKILL.md body"
fi

body_lines() {
  awk 'NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
    fm { if (/^---[[:space:]]*$/) fm = 0; next }
    { n++ }
    END { print n + 0 }'
}
SETTINGS_LIB="$SCRIPT_DIR/../lib"
SETTINGS_LAYERS=()
if [[ "$HAVE_GIT" == 1 ]]; then
  SETTINGS_HOME="$(bash "$SETTINGS_LIB/resolve-convention-home.sh" --root "$REPO_ROOT" 2>/dev/null)"
  case $? in
  0) SETTINGS_LAYERS=("$SETTINGS_HOME/skill-quality.yaml" "$SETTINGS_HOME/skill-quality.local.yaml") ;;
  1) SETTINGS_LAYERS=("docs/conventions/skill-quality.yaml" "docs/conventions/skill-quality.local.yaml") ;;
  3) warn "the convention-home pointer region does not resolve (see lib/resolve-convention-home.sh --explain): the description settings use their defaults" ;;
  *) ;;
  esac
fi
skill_quality_setting() {
  local key="$1" rel value status
  SETTING_VALUE="$2"
  SETTING_LAYER="default"
  for rel in ${SETTINGS_LAYERS[@]+"${SETTINGS_LAYERS[@]}"}; do
    [[ -f "$REPO_ROOT/$rel" ]] || continue
    value="$(bash "$SETTINGS_LIB/parse-concern-value.sh" --strict "$REPO_ROOT/$rel" "$key" 2>/dev/null)"
    status=$?
    value="${value//$'\r'/}"
    if ((status != 0)); then
      warn "$rel does not parse; that layer is dropped and $key resolves to $2 unless a later layer sets it"
    elif [[ -z "$value" ]]; then
      continue
    elif [[ "$value" =~ ^[1-9][0-9]{0,3}$ ]] && ((value <= DESC_FIELD_CAP)); then
      SETTING_VALUE="$value"
      SETTING_LAYER="$rel"
      continue
    else
      warn "$rel: $key is '$value', not a whole number from 1 to $DESC_FIELD_CAP; that layer is dropped and $key resolves to $2 unless a later layer sets it"
    fi
    SETTING_VALUE="$2"
    SETTING_LAYER="default"
  done
}
skill_quality_setting description_target "$DESC_TARGET_DEFAULT"
DESC_TARGET="$SETTING_VALUE"
DESC_TARGET_LAYER="$SETTING_LAYER"
skill_quality_setting description_warn "$DESC_WARN_DEFAULT"
DESC_WARN="$SETTING_VALUE"
DESC_WARN_LAYER="$SETTING_LAYER"

BODY_LINES="$(body_lines <"$SKILL_MD")"
note "size: description $DESC_CP_LEN chars, body $BODY_LINES lines (Pocock medians $POCOCK_DESC_MEDIAN chars, $POCOCK_BODY_MEDIAN lines; max $POCOCK_DESC_MAX, $POCOCK_BODY_MAX)"
note "description settings: target $DESC_TARGET ($DESC_TARGET_LAYER), warn above $DESC_WARN ($DESC_WARN_LAYER), fail above $DESC_FIELD_CAP (fixed)"
if ((DESC_CP_LEN > DESC_WARN)); then
  warn "description is $DESC_CP_LEN chars, above the description_warn setting $DESC_WARN from $DESC_WARN_LAYER (/playbooks:skill-authoring, Descriptions)"
elif ((DESC_CP_LEN > DESC_TARGET)); then
  note "description is $DESC_CP_LEN chars, above the description_target setting $DESC_TARGET from $DESC_TARGET_LAYER"
fi
((BODY_LINES > POCOCK_BODY_MAX)) &&
  warn "SKILL.md body is $BODY_LINES lines, above Pocock's measured max $POCOCK_BODY_MAX (/playbooks:skill-authoring, Body)"
if command -v iconv >/dev/null 2>&1; then
  ROUTER_CHARS=$(($(iconv -c -f UTF-8 -t UTF-32BE <"$SKILL_MD" 2>/dev/null | wc -c) / 4))
else
  ROUTER_CHARS=$(($(LC_ALL=C.UTF-8 wc -m <"$SKILL_MD")))
fi
ROUTER_TOKENS=$(((ROUTER_CHARS + ROUTER_CHARS_PER_TOKEN - 1) / ROUTER_CHARS_PER_TOKEN))
if ((ROUTER_TOKENS > ROUTER_TOKEN_CAP)); then
  warn "SKILL.md is about $ROUTER_TOKENS tokens ($ROUTER_CHARS chars / $ROUTER_CHARS_PER_TOKEN), above the router cap of $ROUTER_TOKEN_CAP: move per-action detail into actions/ (/playbooks:skill-authoring, Body)"
else
  note "SKILL.md about $ROUTER_TOKENS/$ROUTER_TOKEN_CAP tokens (router cap)"
fi

SIZE_BASE=""
SIZE_BASE_LABEL=""
if [[ "$HAVE_GIT" == 1 ]]; then
  if [[ -n "${CHECK_SKILL_BASE_REF:-}" ]]; then
    SIZE_BASE="$CHECK_SKILL_BASE_REF"
    SIZE_BASE_LABEL="$CHECK_SKILL_BASE_REF"
  else
    for size_upstream in origin/HEAD origin/main; do
      git -C "$REPO_ROOT" rev-parse --verify --quiet "$size_upstream^{commit}" >/dev/null 2>&1 || continue
      SIZE_BASE="$(git -C "$REPO_ROOT" merge-base HEAD "$size_upstream" 2>/dev/null)" || SIZE_BASE=""
      [[ -n "$SIZE_BASE" ]] && SIZE_BASE_LABEL="the merge-base with $size_upstream" && break
    done
  fi
fi
if [[ -z "$SIZE_BASE" ]]; then
  note "no base ref for the size-growth comparison (set CHECK_SKILL_BASE_REF, or fetch origin): growth check skipped"
elif ! git -C "$REPO_ROOT" cat-file -e "$SIZE_BASE:$SKILL_REL/SKILL.md" 2>/dev/null; then
  note "no $SIZE_BASE_LABEL version (new skill): size growth skipped"
else
  SIZE_BASE_MD="$(git -C "$REPO_ROOT" show "$SIZE_BASE:$SKILL_REL/SKILL.md" 2>/dev/null)"
  SIZE_BASE_DESC="$(skill_frontmatter::strip_quotes "$(skill_frontmatter::extract <<<"$SIZE_BASE_MD" | skill_frontmatter::field description)")"
  SIZE_BASE_DESC_LEN="$(skill_frontmatter::codepoint_len "$SIZE_BASE_DESC")"
  SIZE_BASE_BODY="$(body_lines <<<"$SIZE_BASE_MD")"
  ((DESC_CP_LEN > SIZE_BASE_DESC_LEN)) &&
    warn "description grew vs $SIZE_BASE_LABEL: $SIZE_BASE_DESC_LEN -> $DESC_CP_LEN chars (/playbooks:skill-authoring, Descriptions)"
  ((BODY_LINES > SIZE_BASE_BODY)) &&
    warn "SKILL.md body grew vs $SIZE_BASE_LABEL: $SIZE_BASE_BODY -> $BODY_LINES lines (/playbooks:skill-authoring, Body)"
fi

SETTINGS_TOKEN_BASELINE="${CHECK_SKILL_SETTINGS_TOKEN_BASELINE:-$SCRIPT_DIR/settings-token-baseline.txt}"
settings_token_hits() { # one .md file; prints "<line>\t<key>" per hit
  awk '
    function mask(t, re,   out, r) {
      out = ""
      while (match(t, re)) {
        r = substr(t, RSTART, RLENGTH)
        gsub(/./, "x", r)
        out = out substr(t, 1, RSTART - 1) r
        t = substr(t, RSTART + RLENGTH)
      }
      return out t
    }
    function spans(t,   out, r) {
      out = ""
      while (match(t, /`[^`]*`/)) {
        r = substr(t, RSTART, RLENGTH)
        if (r ~ /[$][{]user_config[.]/ || r ~ /^`(true|on|false)`$/) gsub(/`/, " ", r)
        else gsub(/./, "x", r)
        out = out substr(t, 1, RSTART - 1) r
        t = substr(t, RSTART + RLENGTH)
      }
      return out t
    }
    function judge(s, off,   low, rest, pos, tok, key, k, line) {
      low = tolower(s)
      if (low ~ /(unexpanded|unset).*means/ || (low ~ /substitut/ && low ~ /token|placeholder/)) return
      pos = 0
      rest = s
      while (match(rest, /[$][{]user_config[.][A-Za-z0-9_]+[}]/)) {
        tok = substr(rest, RSTART, RLENGTH)
        if (tolower(substr(s, 1, pos + RSTART - 1)) ~ /(^|[^a-z])(when|if|unless)[^a-z]/ &&
          tolower(substr(rest, RSTART + RLENGTH)) ~ /^[`)*_[:space:]]*is[[:space:]]+(true|on|false)([^a-z]|$)/) {
          key = tok
          sub(/^[$][{]user_config[.]/, "", key)
          sub(/[}]$/, "", key)
          line = lnum[1]
          for (k = 1; k <= nl; k++) if (lstart[k] <= off + pos + RSTART - 1) line = lnum[k]
          printf "%d\t%s\n", line, key
        }
        pos += RSTART + RLENGTH - 1
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
    function flush(   t, i, start, c, nx) {
      if (nl == 0) return
      t = spans(para)
      t = mask(t, "[]][(][^)]*[)]")
      t = mask(t, "<[a-z]+:[^>]*>")
      t = mask(t, "https?:[^[:space:]]*")
      t = mask(t, "(e[.]g|i[.]e|[Ee]tc|vs|cf)[.]")
      start = 1
      for (i = 1; i <= length(t); i++) {
        c = substr(t, i, 1)
        nx = substr(t, i + 1, 1)
        if ((c == "." || c == "!" || c == "?") && (nx == "" || nx == " ")) {
          judge(substr(t, start, i - start + 1), start)
          start = i + 1
        }
      }
      if (start <= length(t)) judge(substr(t, start), start)
      para = ""
      nl = 0
    }
    NR == 1 && /^---[[:space:]]*$/ { infm = 1; next }
    infm { if (/^---[[:space:]]*$/) infm = 0; next }
    # CommonMark fences: a run of 3 or more backticks or tildes opens one, and
    # only a bare run of the same character at least as long closes it. A fence
    # opened inside a blockquote ends when that quote does. No ERE intervals.
    {
      fl = $0
      fd = 0
      while (match(fl, /^ ? ? ?> ?/)) { fd++; fl = substr(fl, RSTART + RLENGTH) }
    }
    fence && fd < fdepth { fence = 0 }
    fence {
      if (match(fl, /^[[:space:]]*(`+|~+)[[:space:]]*$/)) {
        m = fl
        gsub(/[[:space:]]/, "", m)
        if (substr(m, 1, 1) == fch && length(m) >= flen) fence = 0
      }
      next
    }
    match(fl, /^[[:space:]]*(```+|~~~+)/) {
      m = substr(fl, RSTART, RLENGTH)
      gsub(/[[:space:]]/, "", m)
      flush()
      fence = 1
      fch = substr(m, 1, 1)
      flen = length(m)
      fdepth = fd
      next
    }
    /^[[:space:]]*$/ { flush(); next }
    /^[[:space:]]*(#|[-*+][[:space:]]|[0-9]+[.)][[:space:]]|[|>])/ { flush() }
    {
      if (nl > 0) para = para " "
      nl++
      lstart[nl] = length(para) + 1
      lnum[nl] = NR
      para = para $0
    }
    END { flush() }' "$1"
}
settings_token_row_count() { # baseline file, repo-relative path; prints the count or nothing
  awk -v want="$2" '{ sub(/#.*/, "") } NF >= 2 && $1 == want { print $2; exit }' "$1"
}
ST_LABEL="$SETTINGS_TOKEN_BASELINE"
[[ -z "${CHECK_SKILL_SETTINGS_TOKEN_BASELINE:-}" ]] && ST_LABEL="scripts/settings-token-baseline.txt"
ST_BASELINE_OK=0
ST_STRICT=0
if [[ -n "${CHECK_SKILL_SETTINGS_TOKEN_BASELINE:-}" ]]; then
  ST_STRICT=1
  if [[ -f "$SETTINGS_TOKEN_BASELINE" ]]; then
    ST_BASELINE_OK=1
  else
    err "CHECK_SKILL_SETTINGS_TOKEN_BASELINE=$SETTINGS_TOKEN_BASELINE does not exist — a missing baseline must not silently become a clean run"
  fi
elif [[ -f "$SETTINGS_TOKEN_BASELINE" && -n "$SKILL_REL" ]]; then
  st_own_root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  st_skill_root="$(git -C "$SKILL_DIR" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  if [[ -n "$st_own_root" && "$st_own_root" == "$st_skill_root" ]]; then
    ST_STRICT=1
    ST_BASELINE_OK=1
  fi
fi
ST_SEEN=""
ST_ANY=0
# shellcheck disable=SC2016  # backticks are literal Markdown in the message
st_fix='state the fallback in the same sentence, e.g. "(unexpanded, empty, or any other value means `false`)", as `/code-tidying:tidy` does for `hard_exclusions`'
while IFS= read -r st_md; do
  st_file="${st_md#"$SKILL_DIR"/}"
  st_hits="$(settings_token_hits "$st_md")"
  st_rel=""
  [[ -n "$SKILL_REL" ]] && st_rel="$SKILL_REL/$st_file"
  st_base=""
  if ((ST_BASELINE_OK == 1)) && [[ -n "$st_rel" ]]; then
    st_base="$(settings_token_row_count "$SETTINGS_TOKEN_BASELINE" "$st_rel")"
    ST_SEEN="$ST_SEEN$st_rel"$'\n'
  fi
  if [[ -n "$st_base" && ! "$st_base" =~ ^[0-9]+$ ]]; then
    err "settings-token baseline row for $st_rel in $ST_LABEL has a non-numeric count — fix the row"
    continue
  fi
  st_count=0
  [[ -n "$st_hits" ]] && st_count="$(grep -c . <<<"$st_hits")"
  if ((st_count == 0)); then
    [[ -n "$st_base" ]] &&
      err "stale settings-token baseline row in $ST_LABEL: $st_rel now has no hits — remove the row"
    continue
  fi
  ST_ANY=1
  st_where=""
  while IFS=$'\t' read -r st_line st_key; do
    st_where="${st_where:+$st_where, }$st_file:$st_line ($st_key)"
  done <<<"$st_hits"
  if [[ -z "$st_base" ]] && ((ST_STRICT == 0)); then
    warn "settings token used as a condition with no inline fallback at $st_where — advisory: no settings-token baseline applies to this run (set CHECK_SKILL_SETTINGS_TOKEN_BASELINE to a baseline file, empty for none, to make it a FAIL); $st_fix"
  elif [[ -z "$st_base" ]]; then
    err "settings token used as the subject of a condition with no inline fallback at $st_where: an unset key can arrive as the literal token, which reads as neither true nor false; $st_fix"
  elif ((st_count > st_base)); then
    err "settings-token hits in $st_rel rose from the baseline's $st_base to $st_count at $st_where: $st_fix"
  elif ((st_count < st_base)); then
    err "stale settings-token baseline row in $ST_LABEL: $st_rel now has $st_count hit(s), not $st_base — lower the row"
  else
    warn "settings token used as a condition with no inline fallback at $st_where — recorded in $ST_LABEL; $st_fix, then lower the row"
  fi
done < <(find "$SKILL_DIR" \( -path "$SKILL_DIR/evals" -o -path "$SKILL_DIR/vendor" -o -name node_modules \) -prune -o -type f -name '*.md' -print | sort)
if ((ST_BASELINE_OK == 1)) && [[ -n "$SKILL_REL" ]]; then
  while IFS= read -r st_row; do
    [[ -n "$st_row" ]] || continue
    grep -qxF -- "$st_row" <<<"$ST_SEEN" ||
      err "stale settings-token baseline row in $ST_LABEL: $st_row no longer exists — remove the row"
  done < <(awk -v pre="$SKILL_REL/" '{ sub(/#.*/, "") } NF >= 2 && index($1, pre) == 1 { print $1 }' "$SETTINGS_TOKEN_BASELINE")
fi
((ST_ANY == 0)) && note "no settings token used as a condition without a fallback"

summarize
