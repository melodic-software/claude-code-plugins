#!/usr/bin/env bash
# Keep a sweep's closure ledger, running fetch spend and source cache in one file.
#
#   sweep-ledger.sh --topic SLUG init
#   sweep-ledger.sh --topic SLUG close FILE --dispositions T --pointer-liveness T
#                   --semantic-diff T --in-span T --carve-out T
#   sweep-ledger.sh --topic SLUG spend N
#   sweep-ledger.sh --topic SLUG cache-add URL SHA256
#   sweep-ledger.sh --topic SLUG cache-check URL
#   sweep-ledger.sh --topic SLUG status
#   sweep-ledger.sh [--topic SLUG] --show-config
#
# Reasoning-free (Brief constraint C1): this script checks that an entry has the
# fields the ledger needs and that the spend adds up. Whether a disposition is
# RIGHT, or whether a file's findings are all accounted for, is not knowable from
# an entry and is never asserted here; every field is the run's own claim.
#
# The ledger is `.work/SLUG/sweep-ledger.md` under the checkout's toplevel, so a
# worktree keeps its own and no other checkout sees it. `init` writes the sweep's
# id and the checkout it started in on the first line after the header, and every
# call refuses a ledger that does not name this checkout, so a copy carried to
# another checkout is not resumed as the same sweep. The script reads and
# writes that one file, plus the config cascade for `budgets.corpus_fetch_ceiling`.
# It is append-only: the running spend is the sum of the `spend` lines, and the
# newest `cache` line for a URL wins.
#
# Contract: reference/dispositions.md "Sweep closure".
# Exit: 0 on success, 1 when `status` finds spend at or over the ceiling, 2 on
# usage or input error (a `close` missing a field included), 3 when the ledger's
# state refuses the call (no ledger for a write, a file already closed, a ledger
# from another checkout), 4 when
# `status` needs jq to read the config layers and it is absent, 5 when the ledger
# could not be written.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -r "$SCRIPT_DIR/lib.sh" ]]; then
  echo "sweep-ledger.sh: cannot read $SCRIPT_DIR/lib.sh" >&2
  for arg in "$@"; do
    if [[ "$arg" == "--show-config" ]]; then
      echo "detector unavailable"
      exit 0
    fi
  done
  exit 2
fi
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
sweep-ledger.sh: the sweep ledger, holding closures, fetch spend and the source cache.

Usage:
  sweep-ledger.sh --topic SLUG init
  sweep-ledger.sh --topic SLUG close FILE --dispositions T --pointer-liveness T
                  --semantic-diff T --in-span T --carve-out T
  sweep-ledger.sh --topic SLUG spend N
  sweep-ledger.sh --topic SLUG cache-add URL SHA256
  sweep-ledger.sh --topic SLUG cache-check URL
  sweep-ledger.sh --topic SLUG status
  sweep-ledger.sh [--topic SLUG] --show-config

  init         create the ledger with a sweep id, or report that it exists (a resume)
  close        record a closed file; refuses a missing field or a file already closed
  spend        add N fetches to the running total
  cache-add    record a fetched source with its hash and fetch time
  cache-check  look a source up; a hit is reported for re-validation, never as reusable
  status       sweep id, closed files, spend against corpus_fetch_ceiling, cache size;
               exits 1 when spend is at or over the ceiling

Values may not contain a newline or '|'. A ledger is checkout-local: none here means
a new sweep, and a ledger copied in from another checkout is refused (exit 3).
EOF
}

die() {
  echo "sweep-ledger.sh: $2" >&2
  exit "$1"
}

SHOW_CONFIG=0
ARGS=()
declare -A OPT=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --topic | --dispositions | --pointer-liveness | --semantic-diff | --in-span | --carve-out)
    require_opt_value "sweep-ledger.sh" "$@"
    OPT["${1#--}"]="$2"
    shift 2
    ;;
  --show-config)
    SHOW_CONFIG=1
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  -*)
    echo "sweep-ledger.sh: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  *)
    ARGS+=("$1")
    shift
    ;;
  esac
done

TOPIC="${OPT[topic]:-}"
CMD="${ARGS[0]:-}"
ARGS=(${ARGS[@]+"${ARGS[@]:1}"})

# --- Roots and config ------------------------------------------------------------
#
# The ledger lives in the checkout; the config is read from CLAUDE_PROJECT_DIR,
# falling back to the checkout, as the sibling scripts do.

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG_ROOT="${CLAUDE_PROJECT_DIR:-$REPO_ROOT}"
cfg_layers_init "$CONFIG_ROOT"

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0
if [[ "$HAVE_JQ" -eq 0 && "${#CFG_LAYERS[@]}" -gt 0 ]]; then
  echo "sweep-ledger.sh: jq not found; config layers present but unread, using defaults" >&2
fi

# The last layer that defines a whole-number ceiling wins. Not read through a
# command substitution: the layer's name has to reach --show-config and status.
CEILING=200
CEILING_FROM=""
if [[ "$HAVE_JQ" -eq 1 ]]; then
  for layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    v="$(jq -r '.budgets.corpus_fetch_ceiling // empty' "$layer" 2>/dev/null)" || continue
    v="${v//$'\r'/}"
    if [[ "$v" =~ ^[0-9]+$ ]]; then
      CEILING="$((10#$v))"
      CEILING_FROM="$layer"
    fi
  done
fi
CEILING_LABEL="(bundled default)"
[[ -z "$CEILING_FROM" ]] || CEILING_LABEL="(from $CEILING_FROM)"

if [[ "$SHOW_CONFIG" -eq 1 ]]; then
  cfg_layers_print
  echo "Ledger: $REPO_ROOT/.work/${TOPIC:-<topic-slug>}/sweep-ledger.md"
  echo "Effective: corpus_fetch_ceiling=$CEILING $CEILING_LABEL"
  exit 0
fi

# --- Inputs ----------------------------------------------------------------------

[[ -n "$CMD" ]] || {
  usage >&2
  exit 2
}
[[ "$TOPIC" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] ||
  die 2 "--topic is required and takes a slug of letters, digits, '.', '_' and '-'"

LEDGER="$REPO_ROOT/.work/$TOPIC/sweep-ledger.md"
NO_LEDGER="no ledger here: this is a new sweep (no closures, no spend, no cache)"

# want <count> <what>: the subcommand's positional arguments.
want() {
  [[ "${#ARGS[@]}" -eq "$1" ]] || die 2 "$CMD takes $2"
}

# plain <name> <value>: a ledger line is one line of ' | ' separated fields.
plain() {
  [[ "$2" != *[$'\n\r|']* ]] || die 2 "$1 may not contain a newline or '|'"
}

append() {
  printf '%s\n' "$1" >>"$LEDGER" || die 5 "cannot write $LEDGER"
}

SPEND=0
SWEEP_ID=""
SWEEP_ROOT=""
SWEEP_AT=""
declare -A CLOSED=()
declare -A CACHE=()

# load_ledger: one pass over the ledger, filling SWEEP_*, SPEND, CLOSED (file set)
# and CACHE (URL to "sha256 | fetch time", the newest line winning). A ledger that
# does not record this checkout is refused: a copy carried here is not this sweep.
load_ledger() {
  local line rest n
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    case "$line" in
    "- sweep: "*)
      rest="${line#- sweep: }"
      SWEEP_ID="${rest%% | checkout: *}"
      rest="${rest#* | checkout: }"
      SWEEP_ROOT="${rest%% | started: *}"
      SWEEP_AT="${rest#* | started: }"
      ;;
    "- spend: "*)
      n="${line#- spend: }"
      [[ "$n" =~ ^[0-9]+$ ]] && SPEND=$((SPEND + 10#$n))
      ;;
    "- closed: "*)
      rest="${line#- closed: }"
      CLOSED["${rest%% | *}"]=1
      ;;
    "- cache: "*)
      rest="${line#- cache: }"
      CACHE["${rest%% | *}"]="${rest#* | }"
      ;;
    *) ;;
    esac
  done <"$LEDGER"
  [[ "$SWEEP_ROOT" == "$REPO_ROOT" ]] ||
    die 3 "$LEDGER is not this checkout's sweep (${SWEEP_ID:-no sweep line}, started in ${SWEEP_ROOT:-no checkout recorded}): this is a new sweep; move the file aside to start one here"
}

# need_ledger: every subcommand but init and a bare status refuses without one.
need_ledger() {
  [[ -f "$LEDGER" ]] || die 3 "$NO_LEDGER; run init to start one"
  load_ledger
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

case "$CMD" in
init)
  want 0 "no arguments"
  if [[ -f "$LEDGER" ]]; then
    load_ledger
    echo "ledger exists: $LEDGER (a resume of sweep $SWEEP_ID; run status)"
  else
    mkdir -p "$(dirname "$LEDGER")" || die 5 "cannot create $(dirname "$LEDGER")"
    at="$(now)"
    SWEEP_ID="$TOPIC-${at//[-:]/}"
    printf '%s\n' \
      "# Sweep ledger" \
      "" \
      "Checkout-local and never tracked. One appended line per event: the running spend is the" \
      "sum of the \`spend\` lines, and the newest \`cache\` line for a URL wins." \
      "" \
      "- sweep: $SWEEP_ID | checkout: $REPO_ROOT | started: $at" >"$LEDGER" || die 5 "cannot write $LEDGER"
    echo "created: $LEDGER (sweep $SWEEP_ID)"
  fi
  ;;
close)
  want 1 "one argument, the repo-relative file that closed"
  file="${ARGS[0]#./}"
  [[ -n "$file" ]] || die 2 "close takes a repo-relative path, not an empty one"
  [[ "$file" != /* ]] || die 2 "close takes a repo-relative path, not $file"
  plain file "$file"
  missing=""
  entry="- closed: $file"
  for field in dispositions pointer-liveness semantic-diff in-span carve-out; do
    if [[ -z "${OPT[$field]:-}" ]]; then
      missing+=" --$field"
    else
      plain "--$field" "${OPT[$field]}"
      entry+=" | $field: ${OPT[$field]}"
    fi
  done
  [[ -z "$missing" ]] || die 2 "close refused for $file, missing:$missing"
  need_ledger
  [[ -z "${CLOSED[$file]+x}" ]] || die 3 "already closed: $file"
  append "$entry | spent: $SPEND"
  echo "closed: $file ($((${#CLOSED[@]} + 1)) closed, spend $SPEND)"
  ;;
spend)
  want 1 "one argument, a whole number of fetches"
  n="${ARGS[0]}"
  [[ "$n" =~ ^[0-9]+$ && "${#n}" -le 9 ]] || die 2 "spend takes a whole number of fetches (at most 9 digits), not $n"
  need_ledger
  n=$((10#$n))
  append "- spend: $n"
  echo "spend: +$n, $((SPEND + n)) so far"
  ;;
cache-add)
  want 2 "two arguments, a URL and its sha256"
  url="${ARGS[0]}"
  sha="${ARGS[1]}"
  [[ "$url" =~ ^https?://[^[:space:]\|]+$ ]] || die 2 "cache-add takes an http(s) URL with no whitespace or '|', not $url"
  [[ "${#sha}" -eq 64 && "$sha" =~ ^[0-9a-f]+$ ]] || die 2 "cache-add takes a lowercase hex sha256 (64 characters)"
  need_ledger
  at="$(now)"
  append "- cache: $url | $sha | $at"
  echo "cached: $url at $at"
  ;;
cache-check)
  want 1 "one argument, a URL"
  url="${ARGS[0]}"
  need_ledger
  entry="${CACHE[$url]-}"
  if [[ -z "$entry" ]]; then
    echo "not cached: $url (fetch it, spend the fetch, then cache-add it)"
  else
    echo "re-validate: $url was fetched at ${entry#* | } with sha256 ${entry%% | *}; fetch it again and compare the hash before reusing it, spend that fetch, then cache-add the result"
  fi
  ;;
status)
  want 0 "no arguments"
  if [[ ! -f "$LEDGER" ]]; then
    echo "$NO_LEDGER"
    exit 0
  fi
  [[ "$HAVE_JQ" -eq 1 || "${#CFG_LAYERS[@]}" -eq 0 ]] ||
    die 4 "jq is required to read corpus_fetch_ceiling from the config layers"
  load_ledger
  echo "ledger: $LEDGER"
  echo "sweep: $SWEEP_ID (started $SWEEP_AT)"
  echo "closed files: ${#CLOSED[@]}"
  [[ "${#CLOSED[@]}" -eq 0 ]] || printf '  %s\n' "${!CLOSED[@]}" | sort
  echo "spend: $SPEND of $CEILING corpus_fetch_ceiling $CEILING_LABEL"
  echo "cache entries: ${#CACHE[@]}"
  if [[ "$SPEND" -ge "$CEILING" ]]; then
    echo "at or over corpus_fetch_ceiling: stop fetching; a candidate still unresolved takes the budget-exhausted neutral outcome"
    exit 1
  fi
  ;;
*)
  echo "sweep-ledger.sh: unknown subcommand: $CMD" >&2
  usage >&2
  exit 2
  ;;
esac
