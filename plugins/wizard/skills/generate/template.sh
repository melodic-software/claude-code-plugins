#!/usr/bin/env bash
set -euo pipefail

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  BOLD=$(tput bold || true)
  DIM=$(tput dim || true)
  RESET=$(tput sgr0 || true)
  BLUE=$(tput setaf 4 || true)
  GREEN=$(tput setaf 2 || true)
  YELLOW=$(tput setaf 3 || true)
  RED=$(tput setaf 1 || true)
else
  BOLD="" DIM="" RESET="" BLUE="" GREEN="" YELLOW="" RED=""
fi

fatal() {
  printf '%s✗ %s%s\n' "$RED" "$1" "$RESET" >&2
  exit 1
}

if ! { exec 3</dev/tty; } 2>/dev/null; then
  fatal "no interactive terminal (/dev/tty unavailable); run this wizard from a real terminal, not a pipe or CI"
fi

TOTAL_STAGES=0

_WIZARD_DRY_RUN=0
for __wiz_arg in "$@"; do
  case "$__wiz_arg" in
  --dry-run) _WIZARD_DRY_RUN=1 ;;
  *) fatal "unknown option: $__wiz_arg (the only option is --dry-run)" ;;
  esac
done
unset __wiz_arg

# shellcheck disable=SC2329  # library API; the example stage does not call it
dry_run() { ((_WIZARD_DRY_RUN)); }

_STAGE_INDEX=0
ENV_FILE="${ENV_FILE:-.env}"
_WIZARD_PROJECT_DIR="$(pwd -P)"
WRITTEN_ENV=()
WRITTEN_SECRET=()
WRITTEN_VAR=()
SKIPPED=()
_WIZARD_RECORDED=()
_WIZARD_TEMPORARY=()
_WIZARD_FIXED=()
_WIZARD_SECRET_KEYS=()

_WIZARD_TMP=""
# shellcheck disable=SC2329  # invoked by the EXIT trap below
_cleanup() { if [[ -n "$_WIZARD_TMP" && -f "$_WIZARD_TMP" ]]; then rm -f -- "$_WIZARD_TMP"; fi; }

_WIZARD_EXIT_HANDLERS=()
# shellcheck disable=SC2310,SC2329  # fatal exits the script directly; library API, run_wizard calls it
on_exit() {
  if ! declare -F -- "$1" >/dev/null; then fatal "on_exit: '$1' is not a function"; fi
  _WIZARD_EXIT_HANDLERS+=("$1")
}

# shellcheck disable=SC2329  # invoked by the EXIT trap below
_run_exit() {
  local status=$? i
  for ((i = ${#_WIZARD_EXIT_HANDLERS[@]} - 1; i >= 0; i--)); do
    "${_WIZARD_EXIT_HANDLERS[i]}" "$status" || true
  done
  _cleanup
}
trap _run_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

_valid_key() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fatal "invalid key name: '$1' (must match ^[A-Za-z_][A-Za-z0-9_]*$)"
}

_clear() {
  [[ -t 1 ]] || return 0
  if command -v tput >/dev/null 2>&1; then tput clear 2>/dev/null || true; else printf '\033[2J\033[3J\033[H'; fi
}

banner() {
  local title="$1" noun=stages line
  shift
  ((TOTAL_STAGES != 1)) || noun=stage
  _clear
  printf '\n%s%s  %s%s\n' "$BOLD" "$BLUE" "$title" "$RESET"
  printf '%s  %s %s%s\n\n' "$DIM" "$TOTAL_STAGES" "$noun" "$RESET"
  if (($#)); then
    for line in "$@"; do printf '%s  %s%s\n' "$DIM" "$line" "$RESET"; done
  else
    printf '%s  This wizard walks you through %s %s and asks before each change. Ctrl-C stops it.%s\n' \
      "$DIM" "$TOTAL_STAGES" "$noun" "$RESET"
  fi
  if ((_WIZARD_DRY_RUN)); then
    printf '\n'
    warn "Dry run: nothing is written, saved or sent, and value prompts are skipped."
  fi
  pause "Ready to start?"
}

stage() {
  _clear
  _STAGE_INDEX=$((_STAGE_INDEX + 1))
  printf '\n%s%s▸ Stage %s/%s · %s%s\n' \
    "$BOLD" "$BLUE" "$_STAGE_INDEX" "$TOTAL_STAGES" "$1" "$RESET"
}

say() { printf '  %s\n' "$1"; }
step() { printf '  %s•%s %s\n' "$BLUE" "$RESET" "$1"; }
note() { printf '  %s%s%s\n' "$DIM" "$1" "$RESET"; }
warn() { printf '  %s⚠ %s%s\n' "$YELLOW" "$1" "$RESET"; }

# shellcheck disable=SC2310  # warn always succeeds; the || branch is the handled fallback
open_url() {
  local url="$1"
  if [[ "$url" != https://* ]]; then
    warn "refusing to open non-https URL: $url"
    return 0
  fi
  if ((_WIZARD_DRY_RUN)); then
    printf '  would open %s\n' "$url"
    return 0
  fi
  printf '  %s↗ opening%s %s\n' "$GREEN" "$RESET" "$url"
  {
    if command -v wslview >/dev/null 2>&1; then
      wslview "$url"
    elif command -v explorer.exe >/dev/null 2>&1; then
      explorer.exe "$url" || true
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$url"
    elif command -v open >/dev/null 2>&1; then
      open "$url"
    else false; fi
  } >/dev/null 2>&1 || warn "the browser did not open; open this address yourself: $url"
}

_drain_tty() {
  while read -r -t 0 -u 3; do
    IFS= read -r -u 3 _ || break
  done
}

# shellcheck disable=SC2310  # fatal exits the script directly; set -e suppression is moot
pause() {
  _drain_tty
  printf '  %s%s%s ' "$DIM" "${1:-Done? Press Enter.}" "$RESET"
  read -r -u 3 _ || fatal "terminal closed at a pause gate, aborting"
}

# shellcheck disable=SC2310  # fatal exits the script directly; set -e suppression is moot
confirm() {
  local reply=""
  _drain_tty
  printf '  %s? %s [y/N]%s ' "$YELLOW" "$1" "$RESET"
  read -r -u 3 reply || fatal "terminal closed at a confirmation gate, aborting"
  [[ "$reply" =~ ^[Yy] ]]
}

# shellcheck disable=SC2310  # confirm's no-branch is the handled stop; fatal exits directly
gate() {
  confirm "$1" || fatal "stopped: $2"
}

# shellcheck disable=SC2310  # confirm's no-branch is the handled stop; fatal exits directly
_offer_fix() {
  warn "$1"
  say "To finish this stage by hand:"
  step "$2"
  if confirm "Done it by hand? (no stops the wizard)"; then
    _WIZARD_FIXED+=("$2")
  else
    fatal "stopped: $1"
  fi
}

# shellcheck disable=SC2329  # library API; the example stage does not call it
attempt() {
  local fix="$1" rc=0
  shift
  if ((_WIZARD_DRY_RUN)); then
    printf '  would run: %s\n' "$1"
    return 0
  fi
  "$@" || rc=$?
  ((rc == 0)) || _offer_fix "$1 failed (exit $rc)" "$fix"
}

_existing() {
  _valid_key "$1"
  [[ -f "$ENV_FILE" ]] || return 1
  local line val esc="'\\''"
  line=$(grep -E "^${1}=" "$ENV_FILE" | tail -n1)
  [[ -n "$line" ]] || return 1
  val="${line#*=}"
  if [[ ${#val} -ge 2 ]]; then
    case "$val" in
    \'*\')
      val="${val:1:${#val}-2}"
      val="${val//"$esc"/\'}"
      ;;
    \"*\")
      val="${val:1:${#val}-2}"
      [[ "$val" != *[\\\$\"\`]* ]] || return 1
      ;;
    *) ;;
    esac
  fi
  printf '%s' "$val"
}

_ask_prompt() {
  if [[ -n "$2" ]]; then
    printf '  %s%s%s %s[Enter keeps current]%s ' "$BOLD" "$1" "$RESET" "$DIM" "$RESET"
  else
    printf '  %s%s%s ' "$BOLD" "$1" "$RESET"
  fi
}

_resolve_link() {
  local path="$1" link dir hops=0
  while [[ -L "$path" ]]; do
    hops=$((hops + 1))
    ((hops <= 40)) || return 1
    link=$(readlink -- "$path") || return 1
    case "$link" in
    /*) path="$link" ;;
    *) path="$(dirname -- "$path")/$link" ;;
    esac
  done
  dir=$(CDPATH='' cd -P -- "$(dirname -- "$path")" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s' "$dir" "$(basename -- "$path")"
}

_ENV_TARGET_CONFIRMED=""
# shellcheck disable=SC2310  # every || branch is fatal, which exits the script directly
_check_env_target() {
  local target rel
  if ! target=$(_resolve_link "$ENV_FILE"); then
    [[ ! -L "$ENV_FILE" ]] || fatal "couldn't resolve where the symlink $ENV_FILE points; nothing written"
    return 0 # its directory does not exist, so nothing can be written there
  fi
  [[ "$target" != "$_ENV_TARGET_CONFIRMED" ]] || return 0
  rel=$(printf '/%s/' "${target#"$_WIZARD_PROJECT_DIR"/}" | LC_ALL=C tr '[:upper:]' '[:lower:]')
  if [[ "$target" != "$_WIZARD_PROJECT_DIR"/* ]]; then
    warn "$ENV_FILE resolves to a file outside this project: $target"
  elif [[ "$rel" == */.git/* ]]; then
    warn "$ENV_FILE resolves into git metadata: $target"
  else
    return 0
  fi
  confirm "Write values to $target?" || fatal "declined writing through $ENV_FILE to $target; nothing written"
  _ENV_TARGET_CONFIRMED="$target"
}

_assignable_key() {
  local __wiz_decl
  case "$1" in
  __wiz_* | _WIZARD_* | _ENV_* | _STAGE_INDEX | ENV_FILE | TOTAL_STAGES | \
    WRITTEN_ENV | WRITTEN_SECRET | WRITTEN_VAR | SKIPPED | GH_REPO | \
    GH_REPO_DECLINED | BOLD | DIM | RESET | BLUE | GREEN | YELLOW | RED)
    fatal "reserved key name: '$1' (the wizard library uses it; pick another name)"
    ;;
  BASH | BASHOPTS | BASHPID | BASH_* | COMP_* | COMPREPLY | COPROC | DIRSTACK | \
    EPOCHREALTIME | EPOCHSECONDS | EUID | FUNCNAME | GROUPS | HISTCMD | HOSTNAME | \
    HOSTTYPE | LINENO | MACHTYPE | MAPFILE | OLDPWD | OPTARG | OPTIND | OSTYPE | \
    PIPESTATUS | PPID | PWD | RANDOM | READLINE_* | REPLY | SECONDS | SHELLOPTS | \
    SHLVL | SRANDOM | UID | CDPATH | CHILD_MAX | COLUMNS | EMACS | ENV | EXECIGNORE | \
    FCEDIT | FIGNORE | FUNCNEST | GLOBIGNORE | GLOBSORT | HISTCONTROL | HISTFILE | \
    HISTFILESIZE | HISTIGNORE | HISTSIZE | HISTTIMEFORMAT | HOME | HOSTFILE | IFS | \
    IGNOREEOF | INPUTRC | INSIDE_EMACS | LANG | LC_* | LINES | MAIL | MAILCHECK | \
    MAILPATH | OPTERR | PATH | POSIXLY_CORRECT | PROMPT_COMMAND | PROMPT_DIRTRIM | \
    PS0 | PS1 | PS2 | PS3 | PS4 | SHELL | TIMEFORMAT | TMOUT | TMPDIR | LD_* | DYLD_*)
    fatal "reserved key name: '$1' (the shell itself uses it; pick another name)"
    ;;
  *) ;;
  esac
  __wiz_decl=$(declare -p -- "$1" 2>/dev/null) || return 0
  __wiz_decl=${__wiz_decl#declare -}
  if [[ "${__wiz_decl%% *}" == *x* ]]; then
    fatal "exported key name: '$1' (already exported, so a value the wizard assigns would reach gh, git and the browser opener; pick another name)"
  fi
}

# shellcheck disable=SC2310  # fatal exits the script directly; set -e suppression is moot
ask() {
  local __wiz_key="$1" __wiz_prompt="$2" __wiz_current __wiz_input
  _valid_key "$__wiz_key"
  _assignable_key "$__wiz_key"
  _check_env_target
  if ((_WIZARD_DRY_RUN)); then
    note "$__wiz_prompt (dry run: not asked)"
    printf -v "$__wiz_key" '%s' ""
    return 0
  fi
  __wiz_current=$(_existing "$__wiz_key" || true)
  _ask_prompt "$__wiz_prompt" "$__wiz_current"
  read -r -e -u 3 __wiz_input || fatal "terminal closed while reading $__wiz_key, aborting"
  [[ -z "$__wiz_input" && -n "$__wiz_current" ]] && __wiz_input="$__wiz_current"
  printf -v "$__wiz_key" '%s' "$__wiz_input"
}

case "${OSTYPE:-}" in
darwin*) _WIZARD_LINE_MAX=1023 ;;
*) _WIZARD_LINE_MAX=4095 ;;
esac

# shellcheck disable=SC2310  # fatal exits the script directly; set -e suppression is moot
ask_secret() {
  local __wiz_key="$1" __wiz_prompt="$2" __wiz_current __wiz_input __wiz_path __wiz_bytes
  _valid_key "$__wiz_key"
  _assignable_key "$__wiz_key"
  _WIZARD_SECRET_KEYS+=("$__wiz_key")
  _check_env_target
  if ((_WIZARD_DRY_RUN)); then
    note "$__wiz_prompt (dry run: not asked)"
    printf -v "$__wiz_key" '%s' ""
    return 0
  fi
  __wiz_current=$(_existing "$__wiz_key" || true)
  _ask_prompt "$__wiz_prompt" "$__wiz_current"
  read -rs -u 3 __wiz_input || fatal "terminal closed while reading secret $__wiz_key, aborting"
  printf '\n'
  __wiz_bytes=$(LC_ALL=C && printf '%s' "${#__wiz_input}")
  if ((__wiz_bytes >= _WIZARD_LINE_MAX)); then
    warn "$__wiz_key is $__wiz_bytes bytes, the terminal's line limit: it was probably cut off"
    _ask_prompt "Path to a file holding the whole value (Enter keeps what was pasted):" ""
    read -r -e -u 3 __wiz_path || fatal "terminal closed while reading a file path for $__wiz_key, aborting"
    __wiz_path=${__wiz_path/#\~/$HOME}
    if [[ -n "$__wiz_path" ]]; then
      [[ -f "$__wiz_path" && -r "$__wiz_path" ]] || fatal "cannot read file $__wiz_path for $__wiz_key, aborting"
      __wiz_input=$(<"$__wiz_path")
      __wiz_input=${__wiz_input%$'\r'}
      [[ "$__wiz_input" != *[$'\n\r']* ]] ||
        fatal "file $__wiz_path holds more than one line; $__wiz_key must be one line (for a multi-line key such as a PEM file, store its path instead), aborting"
    fi
  fi
  [[ -z "$__wiz_input" && -n "$__wiz_current" ]] && __wiz_input="$__wiz_current"
  printf -v "$__wiz_key" '%s' "$__wiz_input"
}

_ENV_IGNORE_WARNED=0
_check_env_ignored() {
  ((_ENV_IGNORE_WARNED)) && return 0
  command -v git >/dev/null 2>&1 || return 0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  if ! git check-ignore -q -- "$ENV_FILE" 2>/dev/null; then
    _ENV_IGNORE_WARNED=1
    warn "$ENV_FILE is NOT gitignored: a secret written here can be committed"
    SKIPPED+=("gitignore $ENV_FILE (add it to .gitignore before any commit)")
  fi
}

# shellcheck disable=SC2310  # a failed _existing is the handled read-back mismatch
write_env() {
  local __wiz_key="$1" __wiz_value="$2" __wiz_escaped __wiz_tmp __wiz_back
  _valid_key "$__wiz_key"
  _assignable_key "$__wiz_key"
  _check_env_target
  _check_env_ignored
  if ((_WIZARD_DRY_RUN)); then
    printf -v "$__wiz_key" '%s' "$__wiz_value"
    WRITTEN_ENV+=("$__wiz_key")
    printf '  would write %s → %s\n' "$__wiz_key" "$ENV_FILE"
    return 0
  fi
  __wiz_tmp=$(mktemp "${ENV_FILE}.XXXXXX") || fatal "mktemp failed next to $ENV_FILE"
  _WIZARD_TMP="$__wiz_tmp"
  chmod 600 "$__wiz_tmp"
  __wiz_escaped=${__wiz_value//\'/\'\\\'\'}
  if [[ -f "$ENV_FILE" ]]; then grep -vE "^${__wiz_key}=" "$ENV_FILE" >"$__wiz_tmp" || true; fi
  printf "%s='%s'\n" "$__wiz_key" "$__wiz_escaped" >>"$__wiz_tmp"
  if [[ -L "$ENV_FILE" ]]; then
    (umask 077 && cat -- "$__wiz_tmp" >"$ENV_FILE") || fatal "couldn't write through the symlink $ENV_FILE"
    rm -f -- "$__wiz_tmp"
  else
    mv -- "$__wiz_tmp" "$ENV_FILE"
  fi
  _WIZARD_TMP=""
  printf -v "$__wiz_key" '%s' "$__wiz_value"
  WRITTEN_ENV+=("$__wiz_key")
  printf '  %s✓ wrote%s %s → %s\n' "$GREEN" "$RESET" "$__wiz_key" "$ENV_FILE"
  if __wiz_back=$(_existing "$__wiz_key") && [[ "$__wiz_back" == "$__wiz_value" ]]; then
    printf '  %s✓ read back%s %s from %s: present, %s characters\n' \
      "$GREEN" "$RESET" "$__wiz_key" "$ENV_FILE" "${#__wiz_value}"
  else
    _offer_fix "$__wiz_key did not read back from $ENV_FILE as written" \
      "Open $ENV_FILE in an editor and make its $__wiz_key= line hold the value, in single quotes"
  fi
}

# portability-ok: storing a secret or variable for GitHub Actions is inherently

_gh_ready() {
  command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1
}

GH_REPO=""
GH_REPO_DECLINED=0
# shellcheck disable=SC2310  # confirm's no-branch is the handled decline path; fatal exits directly
_resolve_repo() {
  [[ -n "$GH_REPO" ]] && return 0
  ((GH_REPO_DECLINED)) && return 1
  local repo
  if ! repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>&1); then
    GH_REPO_DECLINED=1
    warn "couldn't resolve the GitHub repo; CI writes will be skipped"
    SKIPPED+=("resolve GitHub repo (gh repo view failed: ${repo})")
    return 1
  fi
  say "GitHub CI values will be written to: ${BOLD}${repo}${RESET}"
  if ! confirm "Write CI secrets/variables to ${repo}?"; then
    GH_REPO_DECLINED=1
    warn "CI writes to ${repo} declined; set them manually"
    SKIPPED+=("GitHub CI writes (declined for ${repo})")
    return 1
  fi
  GH_REPO="$repo"
}

_gh_read_back() {
  local kind="$1" name="$2" value="$3" got nl=$'\n'
  if [[ "$kind" == secret ]]; then
    got=$(gh secret list --repo "$GH_REPO" --json name -q '.[].name' 2>/dev/null) || return 1
    [[ "$nl$got$nl" == *"$nl$name$nl"* ]]
  else
    got=$(gh variable get "$name" --repo "$GH_REPO" 2>/dev/null) || return 1
    [[ "$got" == "$value" ]]
  fi
}

# shellcheck disable=SC2310  # _gh_ready/_resolve_repo are status-returning gates; every false branch is handled
_gh_set() {
  local kind="$1" name="$2" value="$3" err
  _valid_key "$name"
  if ((_WIZARD_DRY_RUN)); then
    if [[ "$kind" == secret ]]; then WRITTEN_SECRET+=("$name"); else WRITTEN_VAR+=("$name"); fi
    printf '  would set GitHub %s %s\n' "$kind" "$name"
    return 0
  fi
  if [[ -z "$value" ]]; then
    warn "refusing to set GitHub $kind $name: empty value"
    SKIPPED+=("GitHub $kind $name (empty value; nothing was sent to gh)")
    return 0
  fi
  if ! _gh_ready; then
    warn "skipped GitHub $kind $name: gh is not installed or not signed in"
    SKIPPED+=("GitHub $kind $name (gh missing/unauthenticated: gh $kind set $name --repo <owner/repo>)")
    return 0
  fi
  if ! _resolve_repo; then
    SKIPPED+=("GitHub $kind $name (no confirmed target repo)")
    return 0
  fi
  if err=$(printf '%s' "$value" | gh "$kind" set "$name" --repo "$GH_REPO" 2>&1 >/dev/null); then
    if [[ "$kind" == secret ]]; then WRITTEN_SECRET+=("$name"); else WRITTEN_VAR+=("$name"); fi
    printf '  %s✓ set%s GitHub %s %s in %s\n' "$GREEN" "$RESET" "$kind" "$name" "$GH_REPO"
    if _gh_read_back "$kind" "$name" "$value"; then
      printf '  %s✓ read back%s GitHub %s %s: present\n' "$GREEN" "$RESET" "$kind" "$name"
    else
      warn "GitHub $kind $name did not read back from $GH_REPO"
      SKIPPED+=("GitHub $kind $name (read-back failed: gh $kind set $name --repo $GH_REPO)")
    fi
  else
    warn "couldn't set GitHub $kind $name; see the closing summary"
    SKIPPED+=("GitHub $kind $name (gh error: ${err})")
  fi
}

set_secret() { _gh_set secret "$1" "$2"; }

# shellcheck disable=SC2329  # library API; the example stage does not call it
set_var() { _gh_set variable "$1" "$2"; }

# shellcheck disable=SC2329  # library API; the example stage does not call it
record() {
  local k
  _valid_key "$1"
  for k in ${_WIZARD_SECRET_KEYS[@]+"${_WIZARD_SECRET_KEYS[@]}"}; do
    [[ "$k" != "$1" ]] || fatal "record: $1 was captured with ask_secret, and the summary never prints a secret"
  done
  _WIZARD_RECORDED+=("$1=$2")
  printf '  %s✓ recorded%s %s (shown in the closing summary)\n' "$GREEN" "$RESET" "$1"
}

# shellcheck disable=SC2329  # library API; the example stage does not call it
temporary() {
  _valid_key "$1"
  _WIZARD_TEMPORARY+=("$1: $2")
}

prove_credential() {
  local __wiz_key="$1" __wiz_fix="$2" __wiz_rc=0
  shift 2
  _valid_key "$__wiz_key"
  if ((_WIZARD_DRY_RUN)); then
    printf '  would check %s with %s\n' "$__wiz_key" "$1"
    return 0
  fi
  printf '%s' "${!__wiz_key-}" | "$@" >/dev/null 2>&1 || __wiz_rc=${PIPESTATUS[1]}
  if ((__wiz_rc == 0)); then
    printf '  %s✓ checked%s %s: %s accepted it\n' "$GREEN" "$RESET" "$__wiz_key" "$1"
  else
    _offer_fix "$__wiz_key was refused by $1 (exit $__wiz_rc)" "$__wiz_fix"
  fi
}

finish() {
  local title="${1:-Done}" mark="✓" color="$GREEN" s
  if ((_WIZARD_DRY_RUN)); then title="Dry run of $title: nothing was written"; fi
  if ((${#SKIPPED[@]})); then
    title="$title, with items left to do by hand"
    mark="⚠"
    color="$YELLOW"
  fi
  _clear
  printf '\n%s%s  %s %s%s\n' "$BOLD" "$color" "$mark" "$title" "$RESET"
  if ((_STAGE_INDEX != TOTAL_STAGES)); then
    warn "stage count mismatch: TOTAL_STAGES is $TOTAL_STAGES but $_STAGE_INDEX stage() calls ran; fix TOTAL_STAGES"
  fi
  if ((_WIZARD_DRY_RUN)); then
    ((${#WRITTEN_ENV[@]})) && note "$ENV_FILE keys that would be saved (${#WRITTEN_ENV[@]}): ${WRITTEN_ENV[*]}"
    ((${#WRITTEN_SECRET[@]})) && note "CI secrets that would be stored (${#WRITTEN_SECRET[@]}): ${WRITTEN_SECRET[*]}"
    ((${#WRITTEN_VAR[@]})) && note "CI variables that would be stored (${#WRITTEN_VAR[@]}): ${WRITTEN_VAR[*]}"
  else
    ((${#WRITTEN_ENV[@]})) && note "$ENV_FILE keys saved (${#WRITTEN_ENV[@]}): ${WRITTEN_ENV[*]}"
    ((${#WRITTEN_SECRET[@]})) && note "${GH_REPO} CI secrets stored (${#WRITTEN_SECRET[@]}): ${WRITTEN_SECRET[*]}"
    ((${#WRITTEN_VAR[@]})) && note "${GH_REPO} CI variables stored (${#WRITTEN_VAR[@]}): ${WRITTEN_VAR[*]}"
  fi
  if ((${#_WIZARD_RECORDED[@]})); then
    note "Recorded (${#_WIZARD_RECORDED[@]}):"
    for s in "${_WIZARD_RECORDED[@]}"; do note "  $s"; done
  fi
  if ((${#_WIZARD_FIXED[@]})); then
    note "Finished by hand (${#_WIZARD_FIXED[@]}):"
    for s in "${_WIZARD_FIXED[@]}"; do note "  - $s"; done
  fi
  if ((${#SKIPPED[@]})); then
    printf '\n'
    warn "still to do by hand:"
    for s in "${SKIPPED[@]}"; do note "  - $s"; done
  fi
  if ((${#_WIZARD_TEMPORARY[@]})); then
    printf '\n'
    warn "temporary credentials to delete when done:"
    for s in "${_WIZARD_TEMPORARY[@]}"; do note "  - $s"; done
  fi
  printf '\n'
}

# STAGES: the part you write. Delete the example stage below, add one stage()
# call per row of the confirmed stage plan, in plan order, and make
# TOTAL_STAGES equal the number of stage() calls. Pass banner intro lines and
# the finish title that fit what this wizard does; without intro lines the
# banner prints a neutral default, with no browser or saved-answers claim.
# Keep every stage inside run_wizard, ahead of its closing `finish` and `exit`,
# and keep the last line as is: bash then parses the whole file before the
# first prompt, so editing the script while it runs cannot re-run a step.

run_wizard() {
  TOTAL_STAGES=1

  banner "Mail provider setup" \
    "Keep a browser beside this terminal; pages for each stage open there." \
    "Ctrl-C quits. Answers saved in $ENV_FILE are pre-filled on a later run."

  # ── EXAMPLE STAGE (fictional provider at mail.example.com): delete it ───
  # shellcheck disable=SC2154  # ask/ask_secret assign the named variable via printf -v
  stage "Mail provider: sending domain and API token"
  say "This stage records the sending domain and a send-only API token."
  open_url "https://mail.example.com/settings/api"
  step "Under Sending domain, copy the domain shown as Verified."
  ask MAIL_FROM_DOMAIN "Sending domain:"
  step "Choose Create token, tick only the Send scope, and copy the new token."
  ask_secret MAIL_API_TOKEN "API token:"
  gate "Save these two values to $ENV_FILE?" "nothing was written to $ENV_FILE"
  # shellcheck disable=SC2154  # assigned by ask via printf -v
  write_env MAIL_FROM_DOMAIN "$MAIL_FROM_DOMAIN"
  # shellcheck disable=SC2154  # assigned by ask_secret via printf -v
  write_env MAIL_API_TOKEN "$MAIL_API_TOKEN"
  set_secret MAIL_API_TOKEN "$MAIL_API_TOKEN"
  # shellcheck disable=SC2329  # prove_credential calls it by name
  _check_mail_token() {
    local token=""
    IFS= read -r token || [[ -n "$token" ]]
    printf 'Authorization: Bearer %s\n' "$token" |
      curl -fsS -o /dev/null -H @- https://api.mail.example.com/v1/domains # prereq-ok: example stage the author deletes
  }
  prove_credential MAIL_API_TOKEN \
    "Create a new token with only the Send scope and save it as MAIL_API_TOKEN in $ENV_FILE and in the repository's CI secrets" \
    _check_mail_token

  finish "Mail provider setup complete"
  exit
}

run_wizard "$@"
