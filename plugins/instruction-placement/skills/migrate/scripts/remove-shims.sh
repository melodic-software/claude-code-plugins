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
# CHANGELOG `## [<version>]` heading: claude-memory 0.12.9 corrected its fix
# path, and instruction-placement 0.15.0 is where the last of the old doctrine
# went (`realign/context/apply-recipes.md` and `context/routing-rubric.md` both
# still sent Claude-specific text to the CLAUDE.md below the import at 0.14.0).
# An installed build below either one advises a de-shimmed repository back to
# the old shape.
FLOOR_INSTRUCTION_PLACEMENT="0.15.0"
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
# The LOWEST version installed anywhere, not the highest. A plugin is installed
# per scope, and the scope that answers in a given project is not the newest
# one: a user-scope 0.15.0 beside a project-scope 0.13.11 would otherwise
# report 0.15.0 and let the stale copy give the old advice in the very
# repository being de-shimmed.
installed_version() { # <plugin name>
  command -v jq >/dev/null 2>&1 || return 1
  [[ -f "$INSTALLED_PLUGINS" ]] || return 1
  local worst="" v
  while IFS= read -r v; do
    v="${v%$'\r'}"
    [[ -n "$v" ]] || continue
    if [[ -z "$worst" ]] || ver_ge "$worst" "$v"; then worst="$v"; fi
  done < <(jq -r --arg p "$1@" '.plugins | to_entries[]
             | select(.key | startswith($p)) | .value[].version' \
    "$INSTALLED_PLUGINS" 2>/dev/null)
  [[ -n "$worst" ]] || return 1
  printf '%s' "$worst"
}

for pair in "instruction-placement:$FLOOR_INSTRUCTION_PLACEMENT" "claude-memory:$FLOOR_CLAUDE_MEMORY"; do
  name="${pair%%:*}"
  floor="${pair##*:}"
  if ! have="$(installed_version "$name")"; then
    refuse "cannot read the installed version of $name from $INSTALLED_PLUGINS (jq missing, file absent, or the plugin is not installed). An unread version is not a version that carries the corrected doctrine."
  fi
  if ! ver_ge "$have" "$floor"; then
    refuse "installed $name is $have (the lowest copy across every scope), below the corrected-doctrine release $floor. An older build tells a de-shimmed repository to put the shim back."
  fi
  echo "  installed $name $have (lowest across scopes), at or above $floor"
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

# One EXIT trap carries the restore, rather than a list of signals that has to
# stay complete. Naming INT and TERM left HUP and PIPE out, and a run killed by
# either left the repository de-shimmed and unverified: `remove-shims | head`
# is enough to reach that state. The signal traps below only exit; EXIT is what
# restores, so an exit this script never anticipated restores too.
CLEANUP_STARTED=0
# shellcheck disable=SC2329 # invoked by the EXIT trap set below
on_exit() {
  local rc=$?
  ((CLEANUP_STARTED == 1)) && return
  CLEANUP_STARTED=1
  rm -f "$PLAN" "${AGENTS_LINES:-}"
  if ((${#REMOVED[@]} > 0)) && ((CANARY_PASSED == 0)); then
    printf '\nexiting with shims removed and unverified; restoring:\n'
    restore_all || :
  fi
  exit "$rc"
}
trap on_exit EXIT
trap 'exit 1' INT TERM HUP
# SIGPIPE is IGNORED rather than trapped. A trapped one still kills the shell
# on the default disposition path, and a script killed mid-removal leaves the
# repository de-shimmed and unverified with no trap run at all: `remove-shims
# --confirm | head` did exactly that on Linux. Ignored, the write returns EPIPE,
# this script has no errexit to trip over it, and the run finishes through its
# own logic and its own EXIT trap. A reader that left does not get to decide
# whether a repository keeps its instruction files.
trap '' PIPE

# Declared before the trap can read them, so an early exit sees an empty list
# rather than an unbound variable.
REMOVED=()
CANARY_PASSED=0
bash "$PLAN_MIGRATION" --root "$REPO" >"$PLAN" 2>/dev/null ||
  refuse "plan-migration.sh could not plan $REPO"

SHIM_DIRS=()
AGENTS_DIRS=()
while IFS=$'\t' read -r kind dir state cb ab; do
  [[ "$kind" == "DIR" ]] || continue
  [[ "$ab" != "0" ]] && AGENTS_DIRS+=("$dir")
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
# A session in a nested directory loads that directory's AGENTS.md AND every
# ancestor's, measured 2026-09-20 on 2.1.278 with no tools available: running
# from the nested directory is itself the trigger, so no Read is needed, and
# both files came back. That is also why the line has to be UNIQUE. A line the
# nested file shares with the root file is answered by the root file, and the
# nested surface would pass its canary while loading nothing of its own.
AGENTS_LINES="$(mktemp)"
build_line_index() {
  local d file
  : >"$AGENTS_LINES"
  for d in ${AGENTS_DIRS[@]+"${AGENTS_DIRS[@]}"}; do
    if [[ "$d" == "." ]]; then file="$REPO/AGENTS.md"; else file="$REPO/$d/AGENTS.md"; fi
    [[ -f "$file" ]] || continue
    awk -v f="$d" '{ sub(/\r$/, ""); gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 != "") print f "\t" $0 }' \
      "$file" >>"$AGENTS_LINES"
  done
}

# The longest line of this directory's AGENTS.md that is plain prose, long
# enough to be distinctive, and present in NO other AGENTS.md in the repository.
canary_line() { # <dir>
  local file line best="" seen
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
    ((${#line} > ${#best})) || continue
    seen="$(awk -F'\t' -v want="$line" '$2 == want { n++ } END { print n + 0 }' "$AGENTS_LINES")"
    ((seen == 1)) || continue
    best="$line"
  done <"$file"
  [[ -n "$best" ]] || return 1
  printf '%s' "$best"
}

build_line_index
declare -A CANARY_LINE
for dir in "${SHIM_DIRS[@]}"; do
  if ! CANARY_LINE[$dir]="$(canary_line "$dir")"; then
    refuse "$dir/AGENTS.md carries no line that is both distinctive and unique to it. A line an ancestor AGENTS.md also carries is answered by the ancestor, so that surface cannot be verified, so it is not de-shimmed."
  fi
done

# --- 7. removal, root and nested together ---------------------------------
# Past this point the repository is half-shaped until the canaries pass, and
# the EXIT trap above is what puts it back: a failed removal, any signal, a
# canary that did not return its line, and an exit nobody wrote all restore.
SHIM_LINE='@AGENTS.md'

shim_path() {
  if [[ "$1" == "." ]]; then printf 'CLAUDE.md'; else printf '%s/CLAUDE.md' "$1"; fi
}

# Gate 5 proved every one of these files is EXACTLY the import line, so the
# restore writes that line rather than asking git for the index copy, which a
# staged edit would have replaced. The write is verified byte for byte, and a
# restore that did not land says so and takes the exit code with it.
restore_all() {
  local d path target failed=0 got size
  for d in ${REMOVED[@]+"${REMOVED[@]}"}; do
    path="$(shim_path "$d")"
    target="$REPO/$path"
    printf '%s\n' "$SHIM_LINE" >"$target" 2>/dev/null
    got="$(cat "$target" 2>/dev/null)"
    # Byte count as well as content: `$(...)` strips trailing newlines, so the
    # text comparison alone would accept a file missing the one this writes.
    size="$(wc -c <"$target" 2>/dev/null | tr -d ' \t\r')"
    if [[ "$got" == "$SHIM_LINE" && "$size" == "$((${#SHIM_LINE} + 1))" ]]; then
      printf '%s\n' "  restored $path"
    else
      failed=$((failed + 1))
      printf '%s\n' "  COULD NOT RESTORE $path; write it back by hand as one line: $SHIM_LINE"
    fi
  done
  REMOVED=()
  return "$failed"
}

for dir in "${SHIM_DIRS[@]}"; do
  target="$REPO/$(shim_path "$dir")"
  if ! rm -f "$target"; then
    echo "could not remove $target; restoring every shim this run removed:"
    restore_all || :
    refuse "removal failed part way through; the repository is back at the shim shape."
  fi
  REMOVED+=("$dir")
  echo "  removed $(shim_path "$dir")"
done
echo

# --- 8. one canary per de-shimmed directory -------------------------------
# NO TOOLS (`--tools ""`). A canary that let the model read the file would
# prove only that the file is readable; instructions load at session start, so
# a reply from a session that could not read anything is evidence of a load.
echo "Canaries (the repository's own text, no token written, no tools available):"
MISS=0
for dir in "${SHIM_DIRS[@]}"; do
  line="${CANARY_LINE[$dir]}"
  probe="${line:0:30}"
  cwd="$REPO"
  [[ "$dir" == "." ]] || cwd="$REPO/$dir"
  rc=0
  reply="$(cd "$cwd" && "$CLAUDE_BIN" -p \
    "Quote back, verbatim, every line of your project instructions that contains \"$probe\". If there are none, say NONE." \
    --model haiku --tools "" </dev/null 2>/dev/null)" || rc=$?
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
  restore_rc=0
  restore_all || restore_rc=$?
  echo
  if ((restore_rc > 0)); then
    refuse "the de-shimmed repository did not verify, and $restore_rc shim(s) could NOT be put back. Restore them by hand before any further work in this repository."
  fi
  refuse "the de-shimmed repository did not verify; it is back at the shim shape."
fi

CANARY_PASSED=1
REMOVED_COUNT=${#REMOVED[@]}
echo "=== Removed $REMOVED_COUNT shim(s) from $REPO; every canary returned its AGENTS.md line. ==="
echo "Commit the deletions, and re-run the canaries after the merge."
exit 0
