#!/usr/bin/env bash
# Every single-quoted `${...}` below is a jq or awk program argument, never a shell expansion.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-config.sh"
# shellcheck source=../../../lib/load-config.sh
. "$SCRIPT_DIR/../../../lib/load-config.sh"

die() {
  printf 'sweep: %s\n' "$1" >&2
  exit "${2:-2}"
}

usage() {
  cat <<'EOF'
Find every reference to the files a rename plan would move.
Usage: sweep.sh --pairs <tsv|-> [--config <json>] [--root <dir>]
  --pairs <tsv|->  old<TAB>new lines, or - for standard input
  --config <json>  a resolved configuration document
  --root <dir>     repository to sweep
Exit: 0 the sweep ran; 2 usage, a missing prerequisite, or an unreadable configuration.
EOF
}

CONFIG_FILE=""
ROOT=""
PAIRS_FILE=""

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
  --pairs)
    shift
    [[ $# -gt 0 ]] || die "--pairs needs a file or -"
    PAIRS_FILE="$1"
    ;;
  --user-config)
    shift
    [[ $# -gt 0 ]] || die "--user-config needs a value"
    export CLAUDE_PLUGIN_OPTION_FILE_NAMES="$1"
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    die "unknown argument '$1'"
    ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || die "jq is required and is not on PATH"
command -v git >/dev/null 2>&1 || die "git is required and is not on PATH"
[[ -n "$PAIRS_FILE" ]] || die "--pairs is required"

resolve_git_root

if [[ "$PAIRS_FILE" == "-" ]]; then
  PAIRS="$(cat)"
else
  [[ -r "$PAIRS_FILE" ]] || die "cannot read the pairs file at $PAIRS_FILE"
  PAIRS="$(cat "$PAIRS_FILE")"
fi

load_config

search_pathspec=()
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  search_pathspec+=(":(exclude,glob)$p")
done < <(cfg '.file_names.sweep_exclude[]')

GENERATED=" $(cfg '.file_names.generated[].path' | tr '\n' ' ')"
EXCLUDE_SITES="$(cfg '.file_names.sweep_exclude_sites[]')"

TIER_MAP=""
tier_count="$(cfg '.file_names.tiers | length')"
i=0
while [[ "$i" -lt "$tier_count" ]]; do
  tname="$(cfg ".file_names.tiers[$i].name")"
  tforms="$(cfg ".file_names.tiers[$i].forms")"
  tlayer="$(cfg ".file_names.tiers[$i]._layer")"
  case "$tlayer" in
  user-global | userConfig | personal-override) tauth=0 ;;
  *) tauth=1 ;;
  esac
  matched=0
  while IFS= read -r glob; do
    [[ -n "$glob" ]] || continue
    segments="$(printf '%s' "$glob" | tr -cd '/' | wc -c | tr -d ' ')"
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      TIER_MAP="$TIER_MAP$f	$tname	$tforms	$segments	$i	$tauth
"
      matched=$((matched + 1))
    done < <(git -C "$ROOT" ls-files -- ":(glob)$glob" 2>/dev/null)
  done < <(cfg ".file_names.tiers[$i].paths[]")
  printf 'TIER\t%s\t%s\t%d\n' "$tname" "$tforms" "$matched"
  i=$((i + 1))
done

TIER_WINNER="$(printf '%s' "$TIER_MAP" | awk -F'\t' 'NF==6 {
  f = $1
  if (!(f in best) ||
      $6 > auth[f] ||
      ($6 == auth[f] && ($4 > seg[f] || ($4 == seg[f] && $5 < ord[f])))) {
    best[f] = $2 "\t" $3; seg[f] = $4; ord[f] = $5; auth[f] = $6
  }
} END { for (f in best) print f "\t" best[f] }')"

tier_of() {
  printf '%s' "$TIER_WINNER" | awk -F'\t' -v f="$1" 'NF==3 && $1 == f {print $2 "\t" $3; found=1; exit}
    END { if (!found) print "current\tall" }'
}

RE_RAW=""
RE_GH=""
RE_LINK=""
RE_TICK=""
RE_TABLE=""

ere_escape() {
  printf '%s' "$1" | sed 's/[][\\.^$*+?(){}|]/\\&/g'
}

set_form_patterns() {
  esc="$(ere_escape "$1")"
  RE_RAW="raw\\.githubusercontent\\.com[^ )\"']*$esc"
  RE_GH="github\\.com[^ )\"']*$esc"
  RE_LINK="\\]\\([^)]*$esc"
  RE_TICK="\`[^\`]*${esc}[^\`]*\`"
  RE_TABLE="(^\\|.*$esc|${esc}[[:space:]]*:)"
}

classify_forms() {
  if [[ $1 =~ $RE_RAW ]]; then printf 'raw-url\n'; fi
  if [[ $1 =~ $RE_GH ]]; then printf 'github-url\n'; fi
  if [[ $1 =~ $RE_LINK ]]; then printf 'md-link\n'; fi
  if [[ $1 =~ $RE_TICK ]]; then printf 'backtick-path\n'; fi

  residue="$1"
  while [[ "$residue" =~ \][(][^\)]*[)] ]]; do
    residue="${residue/"${BASH_REMATCH[0]}"/]}"
  done
  while [[ "$residue" =~ \`[^\`]*\` ]]; do
    residue="${residue/"${BASH_REMATCH[0]}"/}"
  done
  while [[ "$residue" =~ https?://[^\ \)\"\']* ]]; do
    residue="${residue/"${BASH_REMATCH[0]}"/}"
  done

  if [[ "$residue" == *"$2"* ]]; then
    if [[ $residue =~ $RE_TABLE ]]; then
      printf 'table-or-key\n'
    else
      printf 'plain\n'
    fi
  fi
}

action_for() {
  case "$1" in
  all) printf 'edit' ;;
  none) printf 'report' ;;
  links-and-paths)
    case "$2" in
    md-link | backtick-path | raw-url | github-url) printf 'edit' ;;
    *) printf 'report' ;;
    esac
    ;;
  *) printf 'report' ;;
  esac
}

is_excluded_site() {
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    efile="${entry%%:*}"
    eliteral="${entry#*:}"
    [[ "$efile" == "$1" ]] || continue
    case "$2" in
    *"$eliteral"*) return 0 ;;
    *) ;;
    esac
  done <<EOF
$EXCLUDE_SITES
EOF
  return 1
}

trim() {
  printf '%s' "$1" | tr '\t' ' ' | cut -c1-160
}

read_hit() {
  file="${1%%:*}"
  rest="${1#*:}"
  lineno="${rest%%:*}"
  text="${rest#*:}"
}

read_tier() {
  tinfo="$(tier_of "$file")"
  tname="${tinfo%%	*}"
  tforms="${tinfo#*	}"
}

override_action() {
  case "$GENERATED" in
  *" $file "*) action='regenerate' ;;
  *) ;;
  esac
  if is_excluded_site "$file" "$text"; then action='skip'; fi
}

sites=0
sorted_pairs="$(printf '%s' "$PAIRS" | awk -F'\t' 'NF>=2 {print length($1) "\t" $0}' | sort -rn | cut -f2-)"

while IFS="$(printf '\t')" read -r old _new; do
  [[ -n "$old" ]] || continue
  base="${old##*/}"
  set_form_patterns "$base"
  stem="${base%.*}"
  stem_esc="$(ere_escape "$stem")"
  seen=""

  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    read_hit "$hit"
    read_tier
    seen="$seen$file:$lineno
"
    while IFS= read -r form; do
      [[ -n "$form" ]] || continue
      action="$(action_for "$tforms" "$form")"
      override_action
      printf 'REF\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$old" "$file" "$lineno" "$form" "$tname" "$action" "$(trim "$text")"
      sites=$((sites + 1))
    done < <(classify_forms "$text" "$base")
  done < <(git -C "$ROOT" grep -n -F -- "$base" "${search_pathspec[@]+"${search_pathspec[@]}"}" 2>/dev/null)

  stem_pattern="(^|[^A-Za-z0-9_-])$stem_esc([^A-Za-z0-9_-]|\$)"
  stem_outside_basename() {
    residue="${1//"$base"/}"
    [[ "$residue" =~ $stem_pattern ]]
  }
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    read_hit "$hit"
    case "
$seen" in
    *"
$file:$lineno
"*) stem_outside_basename "$text" || continue ;;
    *) ;;
    esac
    read_tier
    action="$(action_for "$tforms" bare-stem)"
    case "$stem" in
    *-* | *[0-9]*) ;;
    *) [[ "$action" == "edit" ]] && action='review' ;;
    esac
    override_action
    printf 'REF\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$old" "$file" "$lineno" "bare-stem" "$tname" "$action" "$(trim "$text")"
    sites=$((sites + 1))
  done < <(git -C "$ROOT" grep -nE -- "$stem_pattern" "${search_pathspec[@]+"${search_pathspec[@]}"}" 2>/dev/null)
done <<EOF
$sorted_pairs
EOF

printf 'SITES\t%d\n' "$sites"
exit 0
