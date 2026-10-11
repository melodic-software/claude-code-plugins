#!/usr/bin/env bash
# inventory.sh — list the file names in a tree that break the configured rule.
#
# Read-only. Walks the tracked files under the configured roots, applies the
# exemptions, checks each basename against the casing regex, proposes a new name
# for each offender, and refuses the whole run when any proposed name would
# collide with an existing path by case alone.
#
# WHY THE COLLISION PASS IS SEPARATE AND FATAL. On a case-insensitive checkout
# (the macOS and Windows defaults) two paths differing only by case cannot
# coexist: checking out both writes the second over the first. A rename plan that
# would produce such a pair is not a plan to review, it is a corrupted tree, so
# it is reported and nothing is proposed. The fold-and-intersect algorithm is
# pre-commit's `check-case-conflict`: fold every tracked path AND every parent
# directory, then intersect.
#
# EXISTENCE IS ASKED OF THE INDEX, NEVER THE FILESYSTEM. `[[ -e docs/foo.md ]]`
# is true on a case-insensitive checkout while only `docs/Foo.md` exists, so a
# filesystem test would refuse every case-only rename on exactly the platforms
# the rule protects.
#
# Every single-quoted `${...}` below is a jq program argument, substituted by jq
# from --arg/--argjson, never by the shell.
# shellcheck disable=SC2016
#
# Usage:
#   inventory.sh [--config <json>] [--root <dir>]
#   inventory.sh --help
#
#   --config  a resolved configuration document. Omitted, the sibling
#             resolve-config.sh resolves it for the same root.
#   --root    the repository to inventory. Default: the git toplevel of the
#             working directory, never the directory this script lives in.
#
# Output, tab-separated, one record per line:
#   OFFENDER   <old path>       <proposed path>
#   COLLISION  <proposed path>  <the existing path it would collide with>
#   EXEMPT     <path>           <the exemption that covered it>
#   SCANNED    <count>          <roots>
#
# A run that scans zero files still prints SCANNED and exits 0, and also warns
# on stderr that the roots are empty rather than clean.
#
# Exit: 0 the inventory ran (offenders are findings, not failures),
#       2 usage, a missing prerequisite, an unreadable configuration, or an
#         unimplemented rule.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/../../../scripts/resolve-config.sh"
ROOT_SCOPES="$SCRIPT_DIR/../../../scripts/root-scopes.jq"

die() {
  printf 'inventory: %s\n' "$1" >&2
  exit "${2:-2}"
}

usage() {
  sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'
}

CONFIG_FILE=""
ROOT=""

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

if [[ -z "$ROOT" ]]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
  [[ -n "$ROOT" ]] || die "not inside a git repository and no --root given"
fi
[[ -d "$ROOT" ]] || die "--root '$ROOT' is not a directory"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "'$ROOT' is not a git repository"

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

RULE="$(cfg '.file_names.rule')"
REGEX="$(cfg '.file_names.regex')"
[[ "$RULE" == "lower-kebab" ]] || die "rule '$RULE' is not implemented by this version (known: lower-kebab)"
[[ -n "$REGEX" ]] || die "the configuration carries no regex"

# Propose a legal name for one basename under the configured rule.
# lower-kebab: lowercase, underscores and spaces become single hyphens, runs of
# hyphens collapse, and a leading or trailing hyphen in the stem is dropped.
propose() {
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    tr '_ ' '--' |
    sed -e 's/--*/-/g' -e 's/^-//' -e 's/-\(\.[^.]*\)$/\1/' -e 's/-$//'
}

# --- the file set ------------------------------------------------------------

# What each root claims comes from root-scopes.jq, the definition the emitted
# gate is rendered from too.
SCOPES="$(printf '%s' "$CONFIG" | jq -c -f "$ROOT_SCOPES" 2>/dev/null | tr -d '\r')" ||
  die "the configuration's roots are not strings or {path, extensions, exempt_paths} objects"
n_scopes="$(printf '%s' "$SCOPES" | jq 'length')"
[[ "${n_scopes:-0}" -gt 0 ]] || die "the configuration declares no roots"
# One pathspec outside the repository makes `git ls-files` print nothing for
# every root, and the audit would report an empty scan as a clean tree.
unsafe="$(printf '%s' "$SCOPES" | jq -r '[.[].unsafe | values][0] // empty' | tr -d '\r')"
[[ -z "$unsafe" ]] || die "a root's path or exempt_paths entry $unsafe"

roots_pathspec=()
while IFS= read -r r; do
  [[ -n "$r" ]] && roots_pathspec+=("$r")
done < <(printf '%s' "$SCOPES" | jq -r '.[].specs[]' | tr -d '\r')

exempt_paths_pathspec=()
while IFS= read -r p; do
  [[ -n "$p" ]] || continue
  exempt_paths_pathspec+=(":(glob)$p")
done < <(cfg '.file_names.exempt_paths[]')

# Every tracked path under the roots, and separately those an exempt_paths
# pathspec claims. Matching is git's own, so one matcher decides what `**` means.
ALL_PATHS="$(git -C "$ROOT" ls-files -- "${roots_pathspec[@]}")" ||
  die "git ls-files refused the roots' pathspecs"
if [[ "${#exempt_paths_pathspec[@]}" -gt 0 ]]; then
  EXEMPT_BY_PATH="$(git -C "$ROOT" ls-files -- "${exempt_paths_pathspec[@]}")" ||
    die "git ls-files refused file_names.exempt_paths"
else
  EXEMPT_BY_PATH=""
fi

# A root's own exempt_paths cover a path only when no root claims it without
# exempting it: the judged set is the union of each root's claim minus its own
# exemptions, and the root-exempt set is what the roots claim beyond that. The
# exemptions are their own positive listing, never an `:(exclude)` pathspec
# beside the root's: git matches an exclude glob against the wrong base once
# the positive pathspecs share a directory prefix.
JUDGED=""
s=0
while [[ "$s" -lt "$n_scopes" ]]; do
  spec=()
  while IFS= read -r one; do
    [[ -n "$one" ]] && spec+=("$one")
  done < <(printf '%s' "$SCOPES" | jq -r --argjson s "$s" '.[$s].specs[]' | tr -d '\r')
  exspec=()
  while IFS= read -r one; do
    [[ -n "$one" ]] && exspec+=(":(glob)$one")
  done < <(printf '%s' "$SCOPES" | jq -r --argjson s "$s" '.[$s].exempt[]' | tr -d '\r')
  claimed="$(git -C "$ROOT" ls-files -- "${spec[@]}" | LC_ALL=C sort -u)"
  if [[ "${#exspec[@]}" -gt 0 ]]; then
    claimed="$(LC_ALL=C comm -23 <(printf '%s\n' "$claimed") \
      <(git -C "$ROOT" ls-files -- "${exspec[@]}" | LC_ALL=C sort -u))"
  fi
  JUDGED="$JUDGED$claimed
"
  s=$((s + 1))
done
EXEMPT_BY_ROOT="$(LC_ALL=C comm -23 <(printf '%s\n' "$ALL_PATHS" | LC_ALL=C sort -u) \
  <(printf '%s' "$JUDGED" | LC_ALL=C sort -u) | sed '/^$/d')"

EXEMPT_BASENAMES=" $(cfg '.file_names.exempt_basenames[]' | tr '\n' ' ')"
EXEMPT_EXTENSIONS=" $(cfg '.file_names.exempt_extensions[]' | tr '\n' ' ')"

# in_list <path> <newline-separated list>
in_list() {
  case "
$2
" in
  *"
$1
"*) return 0 ;;
  *) return 1 ;;
  esac
}

# --- the walk ----------------------------------------------------------------

scanned=0
offenders=""

while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  scanned=$((scanned + 1))
  base="${path##*/}"
  ext="${base##*.}"
  [[ "$ext" == "$base" ]] && ext=""

  if in_list "$path" "$EXEMPT_BY_PATH"; then
    printf 'EXEMPT\t%s\texempt_paths\n' "$path"
    continue
  fi
  if in_list "$path" "$EXEMPT_BY_ROOT"; then
    printf 'EXEMPT\t%s\troot exempt_paths\n' "$path"
    continue
  fi
  case "$EXEMPT_BASENAMES" in
  *" $base "*)
    printf 'EXEMPT\t%s\texempt_basenames\n' "$path"
    continue
    ;;
  *) ;;
  esac
  if [[ -n "$ext" ]]; then
    case "$EXEMPT_EXTENSIONS" in
    *" $ext "*)
      printf 'EXEMPT\t%s\texempt_extensions\n' "$path"
      continue
      ;;
    *) ;;
    esac
  fi

  if printf '%s' "$base" | grep -Eq "$REGEX"; then
    continue
  fi

  proposed_base="$(propose "$base")"
  if [[ -z "$proposed_base" || "$proposed_base" == "$base" ]]; then
    printf 'EXEMPT\t%s\tno-legal-proposal\n' "$path"
    continue
  fi
  offenders="$offenders$path	${path%/*}/$proposed_base
"
done <<EOF
$ALL_PATHS
EOF

# A root-level file has no directory part, so `${path%/*}` returned the path
# itself; repair those rows.
offenders="$(printf '%s' "$offenders" | awk -F'\t' 'NF==2 {
  old = $1; new = $2
  if (index(old, "/") == 0) { sub(/^.*\//, "", new); }
  print old "\t" new
}')"

# --- the case-collision pass -------------------------------------------------

# The whole tracked set, and separately every parent directory of it, so a
# proposal that collides with a DIRECTORY by case is caught as well as one that
# collides with a file.
TRACKED="$(git -C "$ROOT" ls-files)"
folded_dirs="$(printf '%s\n' "$TRACKED" |
  awk '{
    p = $0
    while (match(p, "/")) { p = substr(p, 1, RSTART - 1); print tolower(p); if (index(p, "/") == 0) break }
  }' | sort -u)"

collisions=0
while IFS="$(printf '\t')" read -r old new; do
  [[ -n "$old" ]] || continue
  folded_new="$(printf '%s' "$new" | tr '[:upper:]' '[:lower:]')"

  # A tracked file OTHER THAN the one being renamed already folds to the
  # proposed name. Excluding the old path is what lets a genuine case-only
  # rename through: `docs/BETA.md` to `docs/beta.md` is the rename, not a clash,
  # but a distinct `docs/beta.md` sitting there already is.
  twin="$(printf '%s\n' "$TRACKED" | awk -v f="$folded_new" -v o="$old" 'tolower($0) == f && $0 != o {print; exit}')"
  if [[ -n "$twin" ]]; then
    printf 'COLLISION\t%s\t%s\n' "$new" "$twin"
    collisions=$((collisions + 1))
    continue
  fi

  if printf '%s\n' "$folded_dirs" | grep -Fxq "$folded_new"; then
    printf 'COLLISION\t%s\t%s\n' "$new" "a directory already folds to this path"
    collisions=$((collisions + 1))
  fi
done <<EOF
$offenders
EOF

# Two offenders proposing the same name collide with each other.
dupes="$(printf '%s' "$offenders" | awk -F'\t' 'NF==2 {print tolower($2)}' | sort | uniq -d)"
while IFS= read -r d; do
  [[ -n "$d" ]] || continue
  printf 'COLLISION\t%s\ttwo offenders propose this same name\n' "$d"
  collisions=$((collisions + 1))
done <<EOF
$dupes
EOF

if [[ "$collisions" -eq 0 ]]; then
  printf '%s' "$offenders" | awk -F'\t' 'NF==2 {print "OFFENDER\t" $1 "\t" $2}'
fi

roots_joined="$(printf '%s' "$SCOPES" | jq -r 'map(.label) | join(",")' | tr -d '\r')"
if [[ "$scanned" -eq 0 ]]; then
  printf 'inventory: no tracked files under the configured roots (%s); this is an empty root, not a clean tree\n' "$roots_joined" >&2
fi
printf 'SCANNED\t%d\t%s\n' "$scanned" "$roots_joined"
exit 0
