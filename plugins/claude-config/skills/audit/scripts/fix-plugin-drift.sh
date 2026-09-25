#!/usr/bin/env bash
# Apply plugin drift fixes to .claude/settings.json based on
# check-plugin-drift.sh findings.
#
# Auto-fix policy (audit Category E):
#
#   ORPHAN, enabled=false  →  AUTO-REMOVE from enabledPlugins
#                              (behaviorally a no-op: false ≡ absent for plugin
#                              loading, and the entry references a nonexistent
#                              upstream plugin generating /doctor errors)
#
#   ORPHAN, enabled=true   →  REPORT ONLY (manual review required)
#                              (user explicitly enabled a plugin that is now
#                              gone upstream; auto-removing silently breaks
#                              their intent. Surface and let them decide)
#
#   NEW upstream            →  AUTO-ADD as enabledPlugins["<name>@<market>"] = false
#                              (records the discovery as an explicit opt-out,
#                              which keeps per-developer settings.local.json
#                              overrides functional)
#
#   RENAME                  →  REPORT ONLY (heuristic match, human reviews)
#
# Modes:
#   --dry-run  (default)   print plan, no writes
#   --yes      / -y        apply changes
#   --input <path>         consume existing JSON from check-plugin-drift.sh
#                          (otherwise re-runs the check internally)
#   --help                 print usage
#
# Env overrides:
#   CLAUDE_SETTINGS_FILE    path to project settings.json
#   SETTINGS_AUDIT_FIXTURE_DIR forwarded to check-plugin-drift.sh
#
# Apply behavior:
#   A check that fails is fatal. The run never reports an audit it did not
#   complete. A check that completes with no marketplace to audit says so
#   instead of reporting no drift.
#   The settings file is copied to <settings>.<UTC stamp>.bak before it is
#   replaced, created under a 0077 umask so it is 0600 wherever the platform
#   honors mode bits (MSYS does not). Nothing is replaced if that copy cannot be
#   made, and a second apply in the same second is refused rather than
#   overwriting the first one's backup.
#   The file's own line-ending style survives the jq round trip.
#   An apply is refused when the project-root ladder resolved the path to the
#   user settings file. Set CLAUDE_SETTINGS_FILE to write that file on purpose.
#   An apply is refused when the settings path is a symlink, because the
#   replacement is a rename and would replace the link itself.
#   A read-only settings file is still applied, and comes back read-only.
#   "Applied" is printed only after the settings file is read back and found to
#   hold the edit. Any failure before that is fatal, and an interrupting signal
#   ends the run rather than letting it continue with its temporaries deleted.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Args --------------------------------------------------------------------

MODE="dry-run"
INPUT_JSON=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --yes | -y)
    MODE="apply"
    shift
    ;;
  --dry-run)
    MODE="dry-run"
    shift
    ;;
  --input)
    if [[ $# -lt 2 ]]; then
      echo "Missing value for --input" >&2
      exit 2
    fi
    INPUT_JSON="$2"
    shift 2
    ;;
  --help | -h)
    # Two expressions, not GNU's `\?`: BSD sed has no optional-quantifier escape.
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# //' -e 's/^#//'
    exit 0
    ;;
  *)
    echo "Unknown arg: $1" >&2
    exit 2
    ;;
  esac
done

# --- Config resolution -------------------------------------------------------

# The project-root ladder is shared vocabulary (lib/resolve-scopes.sh), not this
# script's to restate. Fail loudly rather than fall through: an unsourced library
# leaves the root empty and this script writes to the settings path it resolves.
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RESOLVE_SCOPES_LIB="$PLUGIN_ROOT/lib/resolve-scopes.sh"
if [[ ! -r "$RESOLVE_SCOPES_LIB" ]]; then
  echo "ERROR: cannot read $RESOLVE_SCOPES_LIB; the plugin's shared scope-resolution library is missing" >&2
  exit 2
fi
# shellcheck source=../../../lib/resolve-scopes.sh
source "$RESOLVE_SCOPES_LIB"

# SETTINGS_FROM_LADDER records how the path was reached: an explicit
# CLAUDE_SETTINGS_FILE is the operator's deliberate target, an inferred path is
# not, and only the inferred one is refused when it lands on the user file.
if [[ -n "${CLAUDE_SETTINGS_FILE:-}" ]]; then
  SETTINGS="$CLAUDE_SETTINGS_FILE"
  SETTINGS_FROM_LADDER=0
else
  # Initialized here so ShellCheck SC2154 sees the assignment; the ladder fills it in.
  PROJECT_ROOT=""
  scopes::project_root_to PROJECT_ROOT
  SETTINGS="$PROJECT_ROOT/.claude/settings.json"
  SETTINGS_FROM_LADDER=1
fi

if [[ ! -f "$SETTINGS" ]]; then
  echo "ERROR: settings file not found: $SETTINGS" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2
  exit 2
fi

# --- Output helpers ----------------------------------------------------------

if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
  RED="" YELLOW="" GREEN="" CYAN="" RESET=""
else
  RED=$'\033[31m' YELLOW=$'\033[33m' GREEN=$'\033[32m' CYAN=$'\033[36m' RESET=$'\033[0m'
fi

# --- Obtain findings ---------------------------------------------------------

TMP_JSON=""
TMP_SETTINGS=""
TMP_EOL=""

# One cleanup, installed once, for every temp this run can create. `rm -f ""` is
# a silent no-op, so an unset path costs nothing.
#
# The signal traps EXIT the script; they do not merely delete. A trap that only
# removed files let an interrupted run CONTINUE with its temps gone, and every
# step after that worked on a stage still holding the original bytes, so the run
# printed "Applied" and changed nothing.
# shellcheck disable=SC2329  # invoked by the traps installed immediately below
cleanup_temps() {
  rm -f "${TMP_JSON:-}" "${TMP_SETTINGS:-}" "${TMP_EOL:-}"
}
trap cleanup_temps EXIT
trap 'cleanup_temps; exit 130' INT
trap 'cleanup_temps; exit 143' TERM HUP

# Set when the internal check completed with no marketplace to compare, so the
# no-drift branch below can say that instead of claiming a clean audit.
NOTHING_AUDITED=0
if [[ -z "$INPUT_JSON" ]]; then
  # Positional absolute template with trailing Xs — the one mktemp form both
  # GNU and BSD accept (see docs/conventions/topic-docs ephemeral tier, #1709).
  # GNU marks -t deprecated, and BSD -t treats the argument as a prefix, not a
  # template. The .json extension was cosmetic; BSD substitutes trailing Xs
  # only, so the template cannot carry one.
  TMP_JSON=$(mktemp "${TMPDIR:-/tmp}/plugin-drift-json-XXXXXX")
  printf '%sRunning check-plugin-drift.sh...%s\n' "$CYAN" "$RESET" >&2
  check_status=0
  SETTINGS_AUDIT_OUTPUT_JSON="$TMP_JSON" CLAUDE_SETTINGS_FILE="$SETTINGS" \
    bash "$SCRIPT_DIR/check-plugin-drift.sh" >/dev/null || check_status=$?
  # 0 is "no drift", 1 is "drift detected" (advisory). Anything else is fatal.
  if [[ "$check_status" -gt 1 ]]; then
    echo "ERROR: check-plugin-drift.sh failed with status $check_status, so no findings were produced" >&2
    exit 2
  fi
  if [[ "$check_status" -eq 1 && ! -s "$TMP_JSON" ]]; then
    echo "ERROR: check-plugin-drift.sh reported drift but wrote no findings document" >&2
    exit 2
  fi
  # mktemp already created $TMP_JSON as a zero-byte file, so emptiness alone
  # cannot separate a truncated write from the check's legitimate status-0 exit
  # when the settings file declares no extraKnownMarketplaces. That case is a
  # pass, but it is not an audit, so it must not borrow the wording of one. The
  # check's own explanation went to the /dev/null above, so say it here and
  # again on stdout where the plan is rendered.
  if [[ ! -s "$TMP_JSON" ]]; then
    NOTHING_AUDITED=1
    echo "NOTE: check-plugin-drift.sh produced no findings document, so no marketplace was audited" >&2
  fi
  INPUT_JSON="$TMP_JSON"
fi

if [[ ! -f "$INPUT_JSON" ]]; then
  echo "ERROR: findings JSON not found: $INPUT_JSON" >&2
  exit 2
fi

if ! jq empty "$INPUT_JSON" 2>/dev/null; then
  echo "ERROR: findings JSON is not valid: $INPUT_JSON" >&2
  exit 2
fi

# --- Build action plan -------------------------------------------------------

# findings <jq-suffix> — sorted unique lines extracted from every status:"ok"
# marketplace block. The suffix is always a static literal from this file, never
# data (plugin names stay --argjson-bound below), so composing the filter here
# cannot inject.
findings() {
  jq -r ".[] | select(.status == \"ok\") | $1" "$INPUT_JSON" | sort -u
}

auto_remove=$(findings '.orphans[] | select(.enabled == false) | "\(.name)@\(.marketplace)"')

manual_orphans=$(findings '.orphans[] | select(.enabled == true) | "\(.name)@\(.marketplace)"')

auto_add=$(findings '.new_upstream[] | "\(.name)@\(.marketplace)"')

# Rename candidates (informational).
rename_candidates=$(findings '.renames[] | "\(.from) -> \(.to)  (\(.marketplace))"')

remove_count=$(echo "$auto_remove" | grep -c . || true)
add_count=$(echo "$auto_add" | grep -c . || true)
manual_count=$(echo "$manual_orphans" | grep -c . || true)
rename_count=$(echo "$rename_candidates" | grep -c . || true)

# --- Render plan -------------------------------------------------------------

# print_entries <bullet-indent> <newline-separated entries> — list one entry per
# line, skipping the blank line an empty list expands to.
print_entries() {
  local indent="$1" entry
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    printf '%s- %s\n' "$indent" "$entry"
  done <<<"$2"
}

printf '\n%sPlugin drift fix plan%s (mode: %s)\n' "$CYAN" "$RESET" "$MODE"
printf 'Settings file: %s\n\n' "$SETTINGS"

if [[ "$remove_count" -gt 0 ]]; then
  printf '%sAUTO-REMOVE%s %d orphan entries (enabled=false):\n' "$YELLOW" "$RESET" "$remove_count"
  print_entries '  ' "$auto_remove"
  echo
fi

if [[ "$add_count" -gt 0 ]]; then
  # shellcheck disable=SC2016  # backticks are intentional markdown literal in user-facing output
  printf '%sAUTO-ADD%s %d new upstream plugins as `false`:\n' "$CYAN" "$RESET" "$add_count"
  print_entries '  ' "$auto_add"
  echo
fi

if [[ "$manual_count" -gt 0 ]]; then
  printf '%sMANUAL REVIEW%s %d orphans currently enabled (true):\n' "$RED" "$RESET" "$manual_count"
  printf '  These plugins were intentionally enabled but are now gone upstream.\n'
  printf '  Auto-fix would silently break user intent — surfacing only:\n'
  print_entries '    ' "$manual_orphans"
  echo
fi

if [[ "$rename_count" -gt 0 ]]; then
  printf '%sRENAME?%s %d possible rename pairs (heuristic — review manually):\n' "$YELLOW" "$RESET" "$rename_count"
  print_entries '  ' "$rename_candidates"
  echo
fi

if [[ "$remove_count" -eq 0 && "$add_count" -eq 0 && "$manual_count" -eq 0 && "$rename_count" -eq 0 ]]; then
  # "Nothing found" and "nothing looked at" are different statements, and stderr
  # is routinely discarded, so the distinction is made here on stdout too.
  if [[ "$NOTHING_AUDITED" -eq 1 ]]; then
    printf '%sNo marketplace was audited, so there is nothing to report.%s\n' "$YELLOW" "$RESET"
  else
    printf '%sNo drift detected, nothing to do.%s\n' "$GREEN" "$RESET"
  fi
  exit 0
fi

# --- Apply (only with --yes) -------------------------------------------------

if [[ "$MODE" != "apply" ]]; then
  printf '%sDry-run only.%s Re-run with %s--yes%s to apply auto-fixes.\n' \
    "$YELLOW" "$RESET" "$CYAN" "$RESET"
  exit 0
fi

if [[ "$remove_count" -eq 0 && "$add_count" -eq 0 ]]; then
  printf '%sNothing to apply%s (manual review items only).\n' "$YELLOW" "$RESET"
  exit 0
fi

# The replacement below is a rename, which replaces a symlink rather than the
# file it points at: the real settings file would go unfixed while this script
# reported success, and the backup would deposit the link target's content in
# this directory. Resolving the link portably needs a realpath/readlink dance
# this script does not otherwise carry, so a symlink is refused instead of
# silently mishandled. Placed after the exits that write nothing.
if [[ -L "$SETTINGS" ]]; then
  echo "ERROR: the settings path is a symlink, $SETTINGS" >&2
  echo "The replacement is a rename and would replace the link itself. Point CLAUDE_SETTINGS_FILE at the file the link resolves to." >&2
  exit 2
fi

# An inferred path that lands on the user settings file is refused. The ladder
# falls through to $PWD outside a repository, so a session started in a home
# directory resolves this script's project-scope target to the live user file.
# An explicit CLAUDE_SETTINGS_FILE is the operator's deliberate target and is
# honored, but it is still announced, because a settings.json `env` block can
# export that variable and the file under audit is exactly the one that drifted.
#
# Candidates: the resolved user dir, plus $HOME/.claude, because with
# CLAUDE_CONFIG_DIR relocated a home-directory session still resolves $SETTINGS
# to $HOME/.claude/settings.json, which is the hazard itself. The list is built
# rather than written inline so an unset HOME contributes no candidate at all
# instead of the bare "/.claude" that "${HOME:-}/.claude" would expand to.
#
# `-ef` compares device and inode, so it is immune to the /c/... against C:/...
# spelling split a string comparison hits on Git Bash. It is false when the
# candidate does not exist, which is safe: $SETTINGS was proved to exist above,
# so a user settings file that is missing cannot be the file about to be
# written. On MSYS the inode is synthesized, so treat this as a strong check
# rather than a proof.
user_candidates=()
# Initialized here so ShellCheck SC2154 sees the assignment.
USER_DIR=""
scopes::user_dir_to USER_DIR
[[ -n "$USER_DIR" ]] && user_candidates+=("$USER_DIR")
[[ -n "${HOME:-}" ]] && user_candidates+=("$HOME/.claude")
if [[ "${#user_candidates[@]}" -eq 0 ]]; then
  echo "NOTE: no user config directory could be resolved, so the user-settings guard checked nothing" >&2
fi
for candidate in "${user_candidates[@]+"${user_candidates[@]}"}"; do
  [[ "$SETTINGS" -ef "$candidate/settings.json" ]] || continue
  if [[ "$SETTINGS_FROM_LADDER" -eq 1 ]]; then
    echo "ERROR: the project-root ladder resolved to the user settings file, $SETTINGS" >&2
    echo "This script writes project scope. Run it from the project, or set CLAUDE_SETTINGS_FILE to the file you mean." >&2
    exit 2
  fi
  echo "WARNING: CLAUDE_SETTINGS_FILE points at the user settings file, $SETTINGS" >&2
  echo "The guard that would refuse this target is waived because the path was given explicitly." >&2
  break
done

# Atomic edit: read-modify-write via jq + temp + rename.
# Same portable mktemp form as TMP_JSON above (#1709).
TMP_SETTINGS=$(mktemp "${TMPDIR:-/tmp}/settings-json-XXXXXX")

# No `set -e` here, so a failed mktemp would otherwise carry an empty path into
# the jq redirect below and report the filter as the failure.
if [[ -z "$TMP_SETTINGS" ]]; then
  echo "ERROR: cannot create a working copy under ${TMPDIR:-/tmp}, settings unchanged" >&2
  exit 2
fi

# The replacement is staged beside the settings file, not under $TMPDIR: /tmp is
# commonly a separate mount, where the final `mv` degrades to a copy plus an
# unlink and an interruption leaves the settings file truncated. A
# same-directory temp makes the last step a rename, which is atomic.
TMP_EOL=$(mktemp "$(dirname "$SETTINGS")/.settings-json-XXXXXX")
# No `set -e` here, so a failed mktemp (an unwritable settings directory, say)
# would otherwise carry an empty path through cp, the redirect, and finally mv.
if [[ -z "$TMP_EOL" ]]; then
  echo "ERROR: cannot stage a replacement beside $SETTINGS, settings unchanged" >&2
  exit 2
fi

# Plugin names come from upstream marketplace JSON — pass them to jq as data
# (--argjson arrays consumed by reduce), never interpolated into the filter
# program, so a crafted upstream name cannot inject jq code.
remove_json=$(jq -nR '[inputs | select(. != "")]' <<<"$auto_remove") || remove_json=""
add_json=$(jq -nR '[inputs | select(. != "")]' <<<"$auto_add") || add_json=""
if [[ -z "$remove_json" || -z "$add_json" ]]; then
  echo "ERROR: cannot encode the plugin lists for the edit, settings unchanged" >&2
  exit 2
fi

if ! jq --argjson rm "$remove_json" --argjson add "$add_json" '
  reduce $rm[] as $k (.; del(.enabledPlugins[$k])) |
  reduce $add[] as $k (.; .enabledPlugins[$k] = false)
' "$SETTINGS" >"$TMP_SETTINGS"; then
  echo "ERROR: jq filter failed — settings unchanged" >&2
  exit 2
fi

# `jq empty` exits 0 on a zero-byte file, so it cannot tell valid JSON from
# nothing written at all. A settings file is always an object, so the stronger
# predicate costs nothing and catches a truncated write.
if ! jq -e 'type == "object"' "$TMP_SETTINGS" >/dev/null 2>&1; then
  echo "ERROR: post-edit JSON invalid, settings unchanged" >&2
  exit 2
fi

# Copy the original onto the stage so the replacement inherits its mode and not
# mktemp's 0600. The content that lands here is overwritten below; only the mode
# survives, which is the point.
if ! cp -p "$SETTINGS" "$TMP_EOL"; then
  echo "ERROR: cannot stage the replacement beside $SETTINGS, settings unchanged" >&2
  exit 2
fi

# That copy also carries a read-only mode, and the normalization below writes to
# this file. Make the stage writable for the duration and put the restriction
# back before the replace, so a settings file the operator marked read-only is
# still applied and comes back read-only. `mv` needs no write bit on the file, only on the directory.
SETTINGS_WAS_WRITABLE=1
[[ -w "$SETTINGS" ]] || SETTINGS_WAS_WRITABLE=0
if ! chmod u+w "$TMP_EOL"; then
  echo "ERROR: cannot make the staged replacement writable, settings unchanged: $TMP_EOL" >&2
  exit 2
fi

# jq emits whatever its build emits: the native Windows build writes CRLF
# through a text-mode stdout, an MSYS or Linux build writes LF. Either one
# rewrites every line ending in a file of the other style, so the emitted
# document is normalized back to the style the original carried. `tr`, not
# grep, because Git Bash grep never matches a carriage return; arithmetic
# comparison, never string equality, because BSD `wc -c` pads with spaces.
cr=$(tr -dc '\r' <"$SETTINGS" | wc -c) || cr=""
lf=$(tr -dc '\n' <"$SETTINGS" | wc -c) || lf=""
if [[ -z "$cr" || -z "$lf" ]]; then
  echo "ERROR: cannot measure the settings file's line endings, settings unchanged" >&2
  exit 2
fi

# Both terms are required. A lone carriage return used as JSON whitespace in an
# LF file would make a bare `cr -gt 0` rewrite every line ending, and a bare
# `cr -ge lf` holds for a newline-less minified file and would CRLF-ify it.
# This counts bytes, it does not pair them: a mixed file goes whichever way its
# majority points and comes back uniform. That is a style change, never a loss.
# BOTH arms are checked. An unchecked redirect here is the whole hazard: the
# stage already holds the `cp -p` copy of the ORIGINAL, so a write that never
# lands leaves a document that is valid JSON and a valid object, passes every
# check below, and gets renamed over the settings file while the run reports
# the edit it did not make.
if [[ "$cr" -gt 0 && "$cr" -ge "$lf" ]]; then
  # A read loop, not `sed 's/$/\r/'`: BSD sed reads \r as a literal r. The
  # `|| [[ -n "$line" ]]` arm keeps a final line that carries no terminator.
  if ! {
    while IFS= read -r line || [[ -n "$line" ]]; do
      printf '%s\r\n' "${line%$'\r'}"
    done <"$TMP_SETTINGS" >"$TMP_EOL"
  }; then
    echo "ERROR: cannot write the staged replacement, settings unchanged: $TMP_EOL" >&2
    exit 2
  fi
elif ! tr -d '\r' <"$TMP_SETTINGS" >"$TMP_EOL"; then
  echo "ERROR: cannot write the staged replacement, settings unchanged: $TMP_EOL" >&2
  exit 2
fi

if ! jq -e 'type == "object"' "$TMP_EOL" >/dev/null 2>&1; then
  echo "ERROR: line-ending normalization produced invalid JSON, settings unchanged" >&2
  exit 2
fi

# The last guard on the class, and the one that does not depend on predicting
# which step failed: at least one removal or addition is pending by now, so a
# stage identical to the current file means the edit never reached it.
if cmp -s "$SETTINGS" "$TMP_EOL"; then
  echo "ERROR: the staged replacement is identical to the current settings file, so the edit did not reach it; settings unchanged" >&2
  exit 2
fi

# Put the original's read-only mode back before the replace, so the file the
# operator gets is the one they had, edited.
if [[ "$SETTINGS_WAS_WRITABLE" -eq 0 ]] && ! chmod u-w "$TMP_EOL"; then
  echo "ERROR: cannot restore the read-only mode on the staged replacement, settings unchanged: $TMP_EOL" >&2
  exit 2
fi

# The backup is taken last, so a run refused earlier leaves none behind. Once it
# exists the original is recoverable whatever happens next, so no path here
# deletes it. Refuse rather than clobber an earlier backup made in the same
# second.
STAMP=$(date -u +%Y%m%dT%H%M%SZ) || STAMP=""
if [[ -z "$STAMP" ]]; then
  echo "ERROR: cannot read the clock for the backup name, settings unchanged" >&2
  exit 2
fi
BACKUP="$SETTINGS.$STAMP.bak"
# Created and filled through ONE descriptor, under noclobber and a 0077 umask.
# noclobber opens with O_EXCL, which refuses an existing file AND a symlink,
# including a dangling one that `[[ -e ]]` reads as absent and that a bare `cp`
# would follow to whatever it names. Creating it empty and then reopening the
# path with `cp` would reintroduce that: the name is predictable, so between the
# two opens it can be unlinked and replaced with a symlink, and the copy follows
# it. Writing through the descriptor the exclusive open returned leaves no such
# window. The umask is why this is not `cp -p`: the backup is a verbatim copy of
# a file that can hold tokens and permission rules, so it is 0600 wherever the
# platform honors mode bits. Both settings are scoped to the subshell.
#
# A failure here leaves nothing to clean up in the case that matters: when the
# open is refused the file is not ours to remove, and the only way to get a
# short write is a read failure on a file this script has already read.
if ! (
  set -C
  umask 077
  cat "$SETTINGS" >"$BACKUP"
) 2>/dev/null; then
  echo "ERROR: cannot write the backup, settings unchanged: $BACKUP" >&2
  echo "The path already exists, is a symlink, or is not writable. A second apply within the same second hits this." >&2
  exit 2
fi

if ! mv "$TMP_EOL" "$SETTINGS"; then
  echo "ERROR: cannot replace $SETTINGS; it is unchanged and backed up at $BACKUP" >&2
  exit 2
fi

# Read the result back rather than trusting the pipeline that produced it. The
# backup holds the pre-apply bytes, so a settings file still equal to it is a
# run that reported an edit it did not make. Nothing above may report success
# on this script's own say-so.
if ! jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1 || cmp -s "$BACKUP" "$SETTINGS"; then
  echo "ERROR: $SETTINGS does not hold the edited document after the replace; the pre-apply copy is at $BACKUP" >&2
  exit 2
fi

printf '%sApplied:%s %d removals, %d additions to %s (backup: %s)\n' "$GREEN" "$RESET" \
  "$remove_count" "$add_count" "$SETTINGS" "$BACKUP"

if [[ "$manual_count" -gt 0 ]]; then
  printf '%sManual review still required for %d enabled-true orphans (see above).%s\n' \
    "$RED" "$manual_count" "$RESET"
fi

exit 0
