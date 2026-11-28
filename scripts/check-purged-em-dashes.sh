#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

ROOT="${EM_DASH_PURGED_ROOT:-$SCRIPT_DIR/..}"
cd "$ROOT" || {
  echo "check-purged-em-dashes: cannot enter root: $ROOT" >&2
  exit 2
}
ROOT="$(pwd)"

# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

ALLOWLIST="${EM_DASH_PURGED_PATHS:-scripts/em-dash-purged-paths.txt}"
SLOP_CONFIG="${EM_DASH_SLOP_CONFIG:-docs/conventions/ai-slop.yaml}"
DETECT="${EM_DASH_DETECT:-plugins/ai-slop/skills/audit/scripts/detect.sh}"
PARSE_YAML="$(dirname "$DETECT")/../../../lib/parse-concern-value.sh"

MODE=check
case "${1-}" in
"" | --check) ;;
--list) MODE=list ;;
*)
  echo "usage: check-purged-em-dashes.sh [--check|--list]" >&2
  exit 2
  ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "check-purged-em-dashes: jq not found; cannot build the detector config layer" >&2
  exit 2
fi
if [[ ! -r "$SLOP_CONFIG" ]]; then
  echo "check-purged-em-dashes: detector config not readable: $SLOP_CONFIG" >&2
  exit 2
fi
if [[ ! -r "$DETECT" ]]; then
  echo "check-purged-em-dashes: detector not readable: $DETECT" >&2
  exit 2
fi
if [[ ! -r "$PARSE_YAML" ]]; then
  echo "check-purged-em-dashes: detector YAML reader not readable: $PARSE_YAML" >&2
  exit 2
fi

declare -a GLOBS=()
read_list::into GLOBS "$ALLOWLIST" --comments inline || exit 2
if ((${#GLOBS[@]} == 0)); then
  echo "check-purged-em-dashes: no active entries in $ALLOWLIST; a gate with an empty allowlist enforces nothing" >&2
  exit 2
fi

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

glob_matches_path() {
  local glob="$1" path="$2"
  local -a gparts pparts
  local i
  IFS=/ read -ra gparts <<<"$glob"
  IFS=/ read -ra pparts <<<"$path"
  ((${#gparts[@]} == ${#pparts[@]})) || return 1
  for ((i = 0; i < ${#gparts[@]}; i++)); do
    if [[ -z "${gparts[i]}" ]]; then
      [[ -z "${pparts[i]}" ]] || return 1
      continue
    fi
    # The unquoted right side is a glob on purpose; quoting would compare literals.
    # shellcheck disable=SC2053,SC2254
    [[ "${pparts[i]}" == ${gparts[i]} ]] || return 1
  done
  return 0
}

pathspecs=()
for glob in "${GLOBS[@]}"; do
  pathspecs+=(":(glob)$glob")
done
if ! git ls-files -z -- "${pathspecs[@]}" >"$TMP/union.z"; then
  echo "check-purged-em-dashes: git ls-files failed" >&2
  exit 2
fi
declare -a UNION=()
while IFS= read -r -d '' f; do
  [[ -n "$f" ]] && UNION+=("$f")
done <"$TMP/union.z"

FILES="$TMP/files.txt"
: >"$FILES"
if ((${#UNION[@]})); then
  printf '%s\n' "${UNION[@]}" >"$FILES"
fi
declare -A BUCKET=()
for idx in "${!UNION[@]}"; do
  IFS=/ read -ra pparts <<<"${UNION[idx]}"
  n=${#pparts[@]} prefix=""
  BUCKET["$n|0|"]+=" $idx"
  for ((k = 0; k < n; k++)); do
    prefix+="${pparts[k]}/"
    BUCKET["$n|$((k + 1))|$prefix"]+=" $idx"
  done
done
pattern_char='[][*?+@!(\]'

stale=0
excluded=0
for glob in "${GLOBS[@]}"; do
  IFS=/ read -ra gparts <<<"$glob"
  n=${#gparts[@]} k=0 prefix=""
  while ((k < n)) && ! [[ "${gparts[k]}" =~ $pattern_char ]]; do
    prefix+="${gparts[k]}/"
    k=$((k + 1))
  done
  count=0
  for idx in ${BUCKET["$n|$k|$prefix"]-}; do
    glob_matches_path "$glob" "${UNION[idx]}" && count=$((count + 1))
  done
  if ((count == 0)); then
    echo "check-purged-em-dashes: stale allowlist entry matches no tracked file: $glob" >&2
    stale=1
    [[ "$MODE" == list ]] && printf 'STALE  %s\n' "$glob"
    continue
  fi
  [[ "$MODE" == list ]] && printf 'ok     %s (%s files)\n' "$glob" "$count"
done

sort -u -o "$FILES" "$FILES"
EXPECTED="$(wc -l <"$FILES" | tr -d ' ')"

if ((stale == 1)); then
  echo "check-purged-em-dashes: remove or repoint the stale entries above" >&2
  exit 1
fi
if ((EXPECTED == 0)); then
  echo "check-purged-em-dashes: allowlist expanded to zero files" >&2
  exit 2
fi

if [[ "$MODE" == list ]]; then
  printf 'check-purged-em-dashes: %s declared paths, %s files.\n' "${#GLOBS[@]}" "$EXPECTED"
  exit 0
fi

mkdir -p "$TMP/root/docs/conventions" "$TMP/home" || exit 2
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git init -q "$TMP/root" || exit 2

mapfile -t DETECT_SLUGS < <(sed -n 's/^  "\(rule-[a-z0-9-]*\)|.*/\1/p' "$DETECT")
if ((${#DETECT_SLUGS[@]} == 0)); then
  echo "check-purged-em-dashes: could not read the detector rule roster from $DETECT" >&2
  exit 2
fi
have_em_dash=0
for slug in "${DETECT_SLUGS[@]}"; do
  [[ "$slug" == rule-em-dash ]] && have_em_dash=1 && break
done
if ((have_em_dash == 0)); then
  echo "check-purged-em-dashes: detector roster from $DETECT does not include rule-em-dash" >&2
  exit 2
fi
other_rules="$(printf '%s\n' "${DETECT_SLUGS[@]}" | grep -vx 'rule-em-dash' | jq -rR '"  - " + tojson')"
if [[ -z "$other_rules" ]]; then
  echo "check-purged-em-dashes: detector roster from $DETECT has no rules to disable besides rule-em-dash" >&2
  exit 2
fi

if ! bash "$PARSE_YAML" --strict "$SLOP_CONFIG" disabled_rules >/dev/null ||
  ! cp "$SLOP_CONFIG" "$TMP/root/docs/conventions/ai-slop.yaml" ||
  ! printf '%s\n' 'disabled_rules:' "$other_rules" 'em_dash_allowed_paths: []' \
    'rule_allowed_paths:' '  rule-em-dash: []' \
    >"$TMP/root/docs/conventions/ai-slop.local.yaml"; then
  echo "check-purged-em-dashes: could not derive the detector config from $SLOP_CONFIG" >&2
  exit 2
fi

OUT="$TMP/findings.txt"
if ! HOME="$TMP/home" CLAUDE_PROJECT_DIR="$TMP/root" \
  bash "$DETECT" --paths-file "$FILES" >"$OUT" 2>"$TMP/detect.err"; then
  echo "check-purged-em-dashes: detector failed" >&2
  cat "$TMP/detect.err" >&2
  exit 2
fi

summary="$(grep -m1 '^Summary rule=ai-slop/audit/rule-em-dash ' "$OUT")"
if [[ -z "$summary" ]]; then
  echo "check-purged-em-dashes: detector emitted no rule-em-dash summary; cannot confirm the rule ran" >&2
  exit 2
fi
if [[ "$summary" != *" disabled=0"* ]]; then
  echo "check-purged-em-dashes: rule-em-dash was disabled for this run ($summary); the config layer did not take effect" >&2
  exit 2
fi

enabled_rules="$(grep -c '^Summary rule=.* disabled=0$' "$OUT" || true)"
if ((enabled_rules != 1)); then
  echo "check-purged-em-dashes: expected only rule-em-dash enabled, found $enabled_rules enabled rule(s)" >&2
  exit 2
fi

scanned="$(sed -n 's/^Summary total: [0-9]* findings across \([0-9]*\) files scanned ([0-9]* files declined)$/\1/p' "$OUT")"
if [[ -z "$scanned" ]]; then
  echo "check-purged-em-dashes: detector emitted no total summary; cannot confirm coverage" >&2
  exit 2
fi
excluded="$(grep -c '^Declined: file=.* cause=excluded-glob$' "$OUT" || true)"
handled=$((scanned + excluded))
if ((handled != EXPECTED)); then
  echo "check-purged-em-dashes: detector handled $handled files but $EXPECTED were declared; coverage is not what the allowlist claims" >&2
  exit 2
fi

verdict=0
if ((excluded > 0)); then
  echo "check-purged-em-dashes: $excluded declared file(s) are excluded by $SLOP_CONFIG and were NOT checked:" >&2
  sed -n 's/^Declined: file=\([^ ]*\) cause=excluded-glob$/  \1/p' "$OUT" >&2
  echo "check-purged-em-dashes: remove them from $ALLOWLIST or from the config's excluded_paths; declaring a path the detector never reads enforces nothing" >&2
  verdict=1
fi

findings="$(grep '^Finding: rule=ai-slop/audit/rule-em-dash ' "$OUT")"
if [[ -z "$findings" ]]; then
  if ((verdict == 0)); then
    printf 'check-purged-em-dashes: %s declared paths, %s files scanned, no em dashes.\n' "${#GLOBS[@]}" "$scanned"
  else
    echo "check-purged-em-dashes: the $scanned file(s) that were checked carry no em dashes, but the excluded file(s) above were not checked at all" >&2
  fi
  exit "$verdict"
fi

count="$(grep -c '' <<<"$findings")"
echo "check-purged-em-dashes: $count em-dash line(s) on surfaces declared purged in $ALLOWLIST" >&2
printf '%s\n' "$findings" |
  sed -n 's|^Finding: rule=ai-slop/audit/rule-em-dash file=\([^ ]*\) line=\([0-9]*\) .*excerpt=\(.*\)$|  \1:\2: \3|p' >&2
cat >&2 <<'EOF'

These paths are declared already purged, so an em dash here is a regression.
Rewrite the line: a period, a comma, or a restructured sentence. Do not
substitute parentheses, en dashes, or spaced hyphens, and do not "fix" an em
dash that is quoted data, a fixture, or third-party text. Take that path off
the allowlist instead, with the reason.
EOF
exit 1
