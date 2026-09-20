#!/usr/bin/env bash
# remove-shims.sh — take the `@AGENTS.md` CLAUDE.md shims out of one repository.
#
# The only mutating script in this skill, and it refuses far more often than it
# acts. In order, and every gate fails closed:
#
#   1. It prints what removal costs. A directly read AGENTS.md is absent from
#      /memory and /context, and fires no InstructionsLoaded hook. The record
#      is in reference/sources.md.
#   2. It refuses without --confirm. There is no blanket-yes and no all-repos
#      mode: one repository per run, one confirmation per run.
#   3. It refuses unless the INSTALLED claude-memory and instruction-placement
#      carry the corrected shim doctrine. An older cached build tells a
#      de-shimmed repository to put the shim back.
#   4. It refuses unless cutover-check.sh reports every graded condition [MET]
#      in this same run.
#   5. It refuses unless every instruction directory is already at the target
#      shape. A CLAUDE.md still carrying content, or an AGENTS.md of zero
#      bytes, is a migration that is not finished, and a zero-byte AGENTS.md
#      cannot be canaried at all.
#   6. It resolves a canary line and a trigger file for every directory BEFORE
#      it removes anything, so a repository that cannot be verified is never
#      left unverified.
#
# Root and nested shims come out together or not at all: a lone nested
# AGENTS.md never attaches while a root CLAUDE.md exists. After removal it runs
# one canary per de-shimmed directory against that directory's own existing
# text, with no token inserted into a real repository. Any miss, and any canary
# that could not measure, restores every shim it removed.
#
# Usage:
#   remove-shims.sh --root <dir> --confirm [options]
#   remove-shims.sh --help
#
# Exit: 0 shims removed and every canary passed; 1 refused, or removed and
# restored; 2 usage error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN_MIGRATION="$SCRIPT_DIR/plan-migration.sh"
CUTOVER_CHECK="$SCRIPT_DIR/cutover-check.sh"
SOURCES_MD="$SCRIPT_DIR/../reference/sources.md"

# The releases that corrected the shim doctrine, from each plugin's own
# CHANGELOG `## [<version>]` heading: instruction-placement 0.14.0 added the
# migrate skill and the corrected reachability verdicts, claude-memory 0.12.9
# corrected its fix path. An installed build below either one advises a
# de-shimmed repository back to the old shape.
FLOOR_INSTRUCTION_PLACEMENT="0.14.0"
FLOOR_CLAUDE_MEMORY="0.12.9"

ROOT=""
CONFIRM=0
CLAUDE_BIN="claude"
INSTALLED_PLUGINS="${HOME:-}/.claude/plugins/installed_plugins.json"
CHECK_ARGS=()

usage() {
  cat <<'EOF'
remove-shims.sh — take the `@AGENTS.md` CLAUDE.md shims out of one repository.

Usage: remove-shims.sh --root <dir> --confirm [options]

  --root <dir>              the repository to de-shim; required, no
                            current-directory default
  --confirm                 remove. Without it the script reports what it
                            would do, and what that costs, and stops
  --claude-bin <path>       the CLI the post-removal canary runs (default: claude)
  --installed-plugins <f>   the installed-plugin manifest to read the doctrine
                            floors from (default: ~/.claude/plugins/installed_plugins.json)
  --check-arg <arg>         one argument passed through to cutover-check.sh;
                            repeatable (for example --check-arg --bundle
                            --check-arg /path/to/bundle)
  --help                    this message

Root and nested shims are removed together or not at all. Every gate fails
closed, and any canary miss restores every shim this run removed.

Exit: 0 removed and verified, 1 refused or restored, 2 usage error.
EOF
}

need_arg() {
  [[ $2 -ge 2 ]] || {
    echo "remove-shims: $1 needs a value" >&2
    exit 2
  }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --root)
    need_arg "$1" $#
    ROOT="$2"
    shift 2
    ;;
  --confirm)
    CONFIRM=1
    shift
    ;;
  --claude-bin)
    need_arg "$1" $#
    CLAUDE_BIN="$2"
    shift 2
    ;;
  --installed-plugins)
    need_arg "$1" $#
    INSTALLED_PLUGINS="$2"
    shift 2
    ;;
  --check-arg)
    need_arg "$1" $#
    CHECK_ARGS+=("$2")
    shift 2
    ;;
  *)
    echo "remove-shims: unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

[[ -n "$ROOT" ]] || {
  echo "remove-shims: --root is required" >&2
  exit 2
}
REPO="$(cd "$ROOT" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
[[ -n "$REPO" ]] || {
  echo "remove-shims: not inside a git repository: $ROOT" >&2
  exit 2
}

refuse() {
  printf 'REFUSED: %s\n' "$1"
  exit 1
}

ver_ge() {
  local -a a b
  local i x y
  IFS=. read -r -a a <<<"$1"
  IFS=. read -r -a b <<<"$2"
  for i in 0 1 2; do
    x="${a[i]:-0}"
    y="${b[i]:-0}"
    ((10#$x > 10#$y)) && return 0
    ((10#$x < 10#$y)) && return 1
  done
  return 0
}

# --- 1. the price ---------------------------------------------------------
echo "=== remove-shims: $REPO ==="
echo
echo "What removing the shims costs (reference/sources.md, 'What shim removal costs'):"
if [[ -f "$SOURCES_MD" ]]; then
  tr -d '\r' <"$SOURCES_MD" |
    awk '/^## What shim removal costs/ { f = 1; next }
         f && /^- \*\*Claim\*\*/ { p = 1 }
         p && /^- \*\*Basis\*\*/ { exit }
         p { print "  " $0 }'
else
  echo "  (records file not found at $SOURCES_MD)"
fi
echo

# --- 2. the confirmation --------------------------------------------------
if ((CONFIRM == 0)); then
  echo "Not confirmed. Re-run with --confirm to remove the shims in this repository."
  echo "One repository per run; there is no all-repositories mode."
  exit 1
fi

# --- 3. the installed doctrine --------------------------------------------
installed_version() { # <plugin name>
  command -v jq >/dev/null 2>&1 || return 1
  [[ -f "$INSTALLED_PLUGINS" ]] || return 1
  local best="" v
  while IFS= read -r v; do
    v="${v%$'\r'}"
    [[ -n "$v" ]] || continue
    if [[ -z "$best" ]] || ver_ge "$v" "$best"; then best="$v"; fi
  done < <(jq -r --arg p "$1@" '.plugins | to_entries[]
             | select(.key | startswith($p)) | .value[].version' \
    "$INSTALLED_PLUGINS" 2>/dev/null)
  [[ -n "$best" ]] || return 1
  printf '%s' "$best"
}

for pair in "instruction-placement:$FLOOR_INSTRUCTION_PLACEMENT" "claude-memory:$FLOOR_CLAUDE_MEMORY"; do
  name="${pair%%:*}"
  floor="${pair##*:}"
  if ! have="$(installed_version "$name")"; then
    refuse "cannot read the installed version of $name from $INSTALLED_PLUGINS (jq missing, file absent, or the plugin is not installed). An unread version is not a version that carries the corrected doctrine."
  fi
  if ! ver_ge "$have" "$floor"; then
    refuse "installed $name is $have, below the corrected-doctrine release $floor. An older build tells a de-shimmed repository to put the shim back."
  fi
  echo "  installed $name $have, at or above $floor"
done
echo

# --- 4. the cutover conditions --------------------------------------------
echo "Running the cutover check against $REPO:"
echo
CHECK_RC=0
bash "$CUTOVER_CHECK" --repo "$REPO" "${CHECK_ARGS[@]+"${CHECK_ARGS[@]}"}" || CHECK_RC=$?
echo
((CHECK_RC == 0)) || refuse "cutover-check reported a condition that is not [MET] (exit $CHECK_RC). Nothing was removed."

# --- 5. the target shape --------------------------------------------------
PLAN="$(mktemp)"
trap 'rm -f "$PLAN"' EXIT
bash "$PLAN_MIGRATION" --root "$REPO" >"$PLAN" 2>/dev/null ||
  refuse "plan-migration.sh could not plan $REPO"

SHIM_DIRS=()
while IFS=$'\t' read -r kind dir state cb ab; do
  [[ "$kind" == "DIR" ]] || continue
  case "$state" in
  shim) SHIM_DIRS+=("$dir") ;;
  agents-only) echo "  $dir: already unshimmed ($ab bytes of AGENTS.md)" ;;
  *)
    if [[ "$ab" == "0" ]]; then
      refuse "$dir is '$state' with an AGENTS.md of 0 bytes. A zero-byte AGENTS.md cannot be canaried, so it is never de-shimmed."
    fi
    refuse "$dir is '$state' ($cb bytes of CLAUDE.md, $ab of AGENTS.md), not the target shape. Finish the migration there first."
    ;;
  esac
done <"$PLAN"

[[ ${#SHIM_DIRS[@]} -gt 0 ]] || {
  echo "Nothing to remove: no directory in $REPO carries a shim."
  exit 0
}

# --- 6. canary inputs, resolved before anything is removed ----------------
# The canary runs against the repository's OWN text: no token is written into a
# real repository. The probe is the head of a distinctive existing line and the
# proof is the whole line, so a reply that merely echoes the prompt is not
# mistaken for a load.
canary_line() { # <dir> — the longest plain prose line of that directory's AGENTS.md
  local file line best=""
  if [[ "$1" == "." ]]; then file="$REPO/AGENTS.md"; else file="$REPO/$1/AGENTS.md"; fi
  [[ -f "$file" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in
    '' | '#'* | '|'* | '-'* | '>'* | '!'* | '<'* | *http*) continue ;;
    *) ;;
    esac
    ((${#line} >= 45)) || continue
    ((${#line} > ${#best})) && best="$line"
  done <"$file"
  [[ -n "$best" ]] || return 1
  printf '%s' "$best"
}

trigger_file() { # <dir> — a tracked file in that directory that is not an instruction file
  local dir="$1" here f
  if [[ "$dir" == "." ]]; then here="$REPO"; else here="$REPO/$dir"; fi
  while IFS= read -r f; do
    f="${f%$'\r'}"
    case "$f" in
    '' | */* | 'AGENTS.md' | 'CLAUDE.md' | 'CLAUDE.local.md') continue ;;
    *) ;;
    esac
    printf '%s' "$f"
    return 0
  done < <(cd "$here" && git ls-files . 2>/dev/null)
  return 1
}

declare -A CANARY_LINE
declare -A CANARY_TRIGGER
for dir in "${SHIM_DIRS[@]}"; do
  if ! CANARY_LINE[$dir]="$(canary_line "$dir")"; then
    refuse "$dir/AGENTS.md carries no line distinctive enough to canary. A surface that cannot be verified is not de-shimmed."
  fi
  if ! CANARY_TRIGGER[$dir]="$(trigger_file "$dir")"; then
    refuse "$dir has no tracked file besides its instruction files for the canary to read. A surface that cannot be verified is not de-shimmed."
  fi
done

# --- 7. removal, root and nested together ---------------------------------
REMOVED=()
for dir in "${SHIM_DIRS[@]}"; do
  target="$REPO/CLAUDE.md"
  [[ "$dir" == "." ]] || target="$REPO/$dir/CLAUDE.md"
  rm -f "$target" || refuse "could not remove $target"
  REMOVED+=("$dir")
  echo "  removed ${dir%/}/CLAUDE.md"
done
echo

restore_all() {
  local d path
  for d in "${REMOVED[@]}"; do
    path="CLAUDE.md"
    [[ "$d" == "." ]] || path="$d/CLAUDE.md"
    (cd "$REPO" && git checkout -- "$path") 2>/dev/null ||
      printf '%s\n' "  could not restore $path; write it back by hand as one line: @AGENTS.md"
    printf '%s\n' "  restored $path"
  done
}

# --- 8. one canary per de-shimmed directory -------------------------------
echo "Canaries (the repository's own text, no token written):"
MISS=0
for dir in "${SHIM_DIRS[@]}"; do
  line="${CANARY_LINE[$dir]}"
  probe="${line:0:30}"
  cwd="$REPO"
  [[ "$dir" == "." ]] || cwd="$REPO/$dir"
  rc=0
  reply="$(cd "$cwd" && "$CLAUDE_BIN" -p \
    "Call the Read tool on the file ${CANARY_TRIGGER[$dir]}. Then quote back, verbatim, every line of your project instructions that contains \"$probe\". If there are none, say NONE." \
    --model haiku --allowedTools Read </dev/null 2>/dev/null)" || rc=$?
  if ((rc != 0)); then
    echo "  $dir: UNREACH, the CLI exited $rc"
    MISS=$((MISS + 1))
    continue
  fi
  case "$reply" in
  *"$line"*) echo "  $dir: the AGENTS.md line came back" ;;
  *NONE*)
    echo "  $dir: clean NONE, the AGENTS.md did not load"
    MISS=$((MISS + 1))
    ;;
  *)
    echo "  $dir: UNREACH, neither the line nor NONE came back"
    MISS=$((MISS + 1))
    ;;
  esac
done
echo

if ((MISS > 0)); then
  echo "$MISS canary result(s) were not a pass. Restoring every shim this run removed:"
  restore_all
  echo
  refuse "the de-shimmed repository did not verify; it is back at the shim shape."
fi

echo "=== Removed ${#REMOVED[@]} shim(s) from $REPO; every canary returned its AGENTS.md line. ==="
echo "Commit the deletions, and re-run the canaries after the merge."
exit 0
