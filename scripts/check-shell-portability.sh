#!/usr/bin/env bash
#      `realpath ... || readlink -f ...`;
#   2. a per-site recorded exemption `portability-ok: <reason>` on the hit line
# `grep -P` only to explain the portable branch below them, and scanning
# comments would flag documentation, not code. A `portability-ok:` marker is
# statically unambiguous marker word inside the matched extent.
# `portability-ok: <reason>` is the one-line escape for a diagnostic
# Exit 0 = clean (or nothing in scope); 1 = one or more violations; 2 = usage /
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "${CHECK_DATA_ROOT:-$SCRIPT_DIR/..}" || exit 2
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2
# shellcheck source=lib/gate-entry.sh
. "$SCRIPT_DIR/lib/gate-entry.sh" || exit 2
# shellcheck source=lib/token-scan.sh
. "$SCRIPT_DIR/lib/token-scan.sh" || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2
# shellcheck source=lib/awk-probe.sh
. "$SCRIPT_DIR/lib/awk-probe.sh" || exit 2

if [[ "${1:-}" == "--awk-probe" ]]; then
  shift
  if (($# == 0)); then
    printf 'usage: check-shell-portability.sh --awk-probe SUITE...\n' >&2
    exit 2
  fi
  awk_probe::run "$@"
  exit
fi

SCAN_AWK="$SCRIPT_DIR/lib/shell-portability-scan.awk"
if [[ ! -f "$SCAN_AWK" ]]; then
  printf 'Error: scanner program not found: %s\n' "$SCAN_AWK" >&2
  exit 2
fi

TOKENS_SRC="${SHELL_PORTABILITY_TOKENS:-scripts/shell-portability-tokens.txt}"
# shellcheck disable=SC2034 # TOKENS_ACTIVE is set by load_active and read by its EXIT trap
TOKENS_ACTIVE='' TOKENS=''
token_scan::load_active "$TOKENS_SRC" TOKENS_ACTIVE TOKENS || exit 2

BASELINE="${SHELL_PORTABILITY_MD_BASELINE:-scripts/shell-portability-skill-md-baseline.txt}"

usage() {
  printf 'usage: check-shell-portability.sh <base-ref> | --all | --paths FILE... | --awk-probe SUITE...\n' >&2
  exit 2
}

sync_copies=()
if [[ -r scripts/cross-plugin-source-registry.txt ]]; then
  while IFS= read -r line; do
    case "$line" in '' | \#*) continue ;; *) ;; esac
    sync_copies+=("$line")
  done <scripts/cross-plugin-source-registry.txt
fi
is_scannable() {
  local f="$1"
  case "$f" in
  */vendor/* | */evals/*) return 1 ;;
  *.sh) ;;
  plugins/*/skills/*.md) ;;
  plugins/*/reference/*.md) ;;
  *) return 1 ;;
  esac
  local rel copy
  if [[ "$f" == plugins/*/* ]]; then
    rel="${f#plugins/}"
    rel="${rel#*/}"
    for copy in ${sync_copies[@]+"${sync_copies[@]}"}; do
      [[ "$rel" == "$copy" ]] && return 1
    done
  fi
  return 0
}

baseline_entries=()
if [[ -f "$BASELINE" ]]; then
  read_list::into baseline_entries "$BASELINE" --comments inline || exit 2
fi

baselined() {
  local path="$1" entry
  for entry in "${baseline_entries[@]}"; do
    [[ "$path" == "$entry" ]] && return 0
  done
  return 1
}

files=()
apply_baseline=0
if ! gate_entry::classify "$@"; then
  usage
fi

case "$GE_MODE" in
all)
  apply_baseline=1
  while IFS= read -r f; do
    is_scannable "$f" && files+=("$f")
  done < <(
    {
      find . -type f -name '*.sh' -not -path '*/node_modules/*' -not -path '*/.git/*'
      find plugins -type f \( -path 'plugins/*/skills/*' -o -path 'plugins/*/reference/*' \) -name '*.md' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
    } | sed 's|^\./||' | sort -u
  )
  ;;
paths)
  files=("${GE_PATHS[@]}")
  ;;
base)
  apply_baseline=1
  base="$GE_REF"
  changed=()
  gate_entry::collect_changed changed "$base" -- '*.sh' 'plugins/'
  for f in ${changed[@]+"${changed[@]}"}; do
    is_scannable "$f" || continue
    [[ -f "$f" ]] || continue
    files+=("$f")
  done
  ;;
*)
  printf 'Error: unrecognized gate mode: %s\n' "$GE_MODE" >&2
  gate_entry::finish 2
  ;;
esac

if ((${#files[@]} == 0)); then
  echo "No shell files in scope — nothing to gate."
  gate_entry::finish 0
fi

scan_file() {
  local file="$1"
  local awk_file
  awk_file="$(token_scan::awk_operand "$file")"
  awk -f "$SCAN_AWK" "$TOKENS" "$awk_file"
}

violations=0
amp_violation=0
declare -A baseline_still_hot=()
declare -A files_in_scope=()
for file in "${files[@]}"; do
  files_in_scope["$file"]=1
  if [[ ! -f "$file" ]]; then
    printf 'Error: no such file: %s\n' "$file" >&2
    exit 2
  fi
  out="$(scan_file "$file")" || {
    printf 'Error: gate scanner failed on %s — failing closed\n' "$file" >&2
    exit 2
  }
  if [[ -n "$out" ]]; then
    # shellcheck disable=SC2310 # baselined only walks a static array
    if ((apply_baseline)) && baselined "$file"; then
      baseline_still_hot["$file"]=1
      continue
    fi
    while IFS= read -r v; do
      echo "PORTABILITY: ${file}:${v}" >&2
      violations=$((violations + 1))
      case "$v" in
      *"!subst-replacement-ampersand"*) amp_violation=1 ;;
      *) ;;
      esac
    done <<<"$out"
  fi
done

if ((apply_baseline)) && ((${#baseline_entries[@]} > 0)); then
  for entry in "${baseline_entries[@]}"; do
    if [[ "$GE_MODE" == "all" || -n "${files_in_scope[$entry]:-}" ]]; then
      if [[ ! -f "$entry" ]]; then
        echo "STALE BASELINE: $BASELINE: '$entry' names a missing file — remove it" >&2
        violations=$((violations + 1))
        continue
      fi
      if [[ -z "${baseline_still_hot[$entry]:-}" ]]; then
        if is_scannable "$entry"; then
          echo "STALE BASELINE: $BASELINE: '$entry' no longer has unexcused hits — remove it" >&2
        else
          echo "STALE BASELINE: $BASELINE: '$entry' is outside the scannable skill-md set — remove it" >&2
        fi
        violations=$((violations + 1))
      fi
    fi
  done
fi

if ((violations > 0)); then
  {
    echo
    echo "A GNU-only construct in a shell script is silently incompatible with"
    echo "BSD userland (macOS system grep/sed/date/stat/mktemp/sort) — no CI"
    echo "runner in this repo covers that platform, so a regression here ships"
    echo "undetected. Resolve the construct with a POSIX-portable form, or —"
    echo "when the use is legitimate and reviewed — add a"
    echo "'portability-ok: <reason>' comment at the site."
  } >&2
  if ((amp_violation > 0)); then
    {
      echo
      echo "!subst-replacement-ampersand names the one class above that is a bash"
      echo "VERSION divergence rather than a utility one: since bash 5.2 an"
      echo "unquoted '&' in the replacement half of \${var//pat/repl} expands to"
      echo "the text the pattern just matched, so the same line means two things"
      echo "on macOS (bash 3.2) and on this repo's runners (5.2+). Spell a literal"
      echo "ampersand '\\&': the manual states the backslash is removed to permit"
      echo "a literal '&', and the quoted spellings carry their own pre-4.3"
      echo "quote-removal divergence."
    } >&2
  fi
  gate_entry::finish 1
fi
echo "No unexcused GNU-only constructs in ${#files[@]} shell file(s)."
gate_entry::finish 0
