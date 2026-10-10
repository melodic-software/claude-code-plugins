#!/usr/bin/env bash
#
# Interactive setup wizard written by /wizard:generate. A person runs it to get
# through setup work that needs them at a browser or console.
#
# Two parts: the shared library, which ends at the "STAGES" marker and is never
# edited by hand, and the stages after the marker, one per task the person does.
#
# Only a person starts this script, from a real terminal; the agent that wrote
# it does not. Without a controlling TTY the library exits at once, so no pipe
# or pasted block can answer its prompts.

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────
# Shared library: prompts, output and storage helpers. Same text in all wizards.
# ──────────────────────────────────────────────────────────────────────────

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  # `|| true`: a terminfo entry may lack a capability, and tput then exits
  # nonzero, which set -e would turn into a silent exit before any prompt.
  BOLD=$(tput bold || true)
  DIM=$(tput dim || true)
  RESET=$(tput sgr0 || true)
  BLUE=$(tput setaf 4 || true)
  GREEN=$(tput setaf 2 || true)
  YELLOW=$(tput setaf 3 || true)
  RED=$(tput setaf 1 || true)
else
  BOLD=""
  DIM=""
  RESET=""
  BLUE=""
  GREEN=""
  YELLOW=""
  RED=""
fi

fatal() {
  printf '%s✗ %s%s\n' "$RED" "$1" "$RESET" >&2
  exit 1
}

# Every prompt reads from the controlling terminal (fd 3 ← /dev/tty), never
# stdin. Fail closed when no TTY exists: a wizard driven by piped input would
# let a multi-line paste blow through its confirmation gates.
if ! { exec 3</dev/tty; } 2>/dev/null; then
  fatal "no interactive terminal (/dev/tty unavailable) — run this wizard from a real terminal, not a pipe or CI"
fi

# The stages section overrides this with its stage count.
TOTAL_STAGES=0

_STAGE_INDEX=0
ENV_FILE="${ENV_FILE:-.env}"
# Where ENV_FILE may resolve to without asking (_check_env_target).
_WIZARD_PROJECT_DIR="$(pwd -P)"
WRITTEN_ENV=()    # keys saved in ENV_FILE during this run
WRITTEN_SECRET=() # CI secret names stored during this run
WRITTEN_VAR=()    # CI variable names stored during this run
SKIPPED=()        # manual follow-ups: no gh, a gh failure, a declined repo

# Temp-file hygiene: write_env stages its rewrite in a mktemp file alongside
# ENV_FILE (same filesystem, so the final mv of a regular file is an atomic
# rename); the trap removes it if the wizard dies mid-write.
_WIZARD_TMP=""
# if-form, not `[[ ]] &&`: a false condition must not leave a nonzero status
# for the EXIT trap under set -e, which would turn a successful run into exit 1.
_cleanup() { if [[ -n "$_WIZARD_TMP" && -f "$_WIZARD_TMP" ]]; then rm -f -- "$_WIZARD_TMP"; fi; }
trap _cleanup EXIT

# _valid_key KEY — keys and secret/variable names must be valid identifiers.
# Anything else (spaces, '=', metacharacters) is an authoring bug: fail fast
# before it reaches the env file or a gh call.
_valid_key() {
  [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fatal "invalid key name: '$1' (must match ^[A-Za-z_][A-Za-z0-9_]*$)"
}

# _clear: blank the screen before a new stage. Skipped when stdout is not a
# terminal, which keeps a captured log free of escape codes. Best effort: a
# terminal without a clear capability (TERM=dumb, no terminfo) makes tput exit
# nonzero, and that must never stop the wizard.
_clear() {
  [[ -t 1 ]] || return 0
  if command -v tput >/dev/null 2>&1; then tput clear 2>/dev/null || true; else printf '\033[2J\033[3J\033[H'; fi
}

# banner "Title": the first screen, with the title and the stage count.
banner() {
  _clear
  printf '\n%s%s  %s%s\n' "$BOLD" "$BLUE" "$1" "$RESET"
  printf '%s  %s stages%s\n\n' "$DIM" "$TOTAL_STAGES" "$RESET"
  printf '%s  Keep a browser beside this terminal; pages for each stage open there.\n' "$DIM"
  printf '  Ctrl-C quits. Answers saved in %s are pre-filled on a later run.%s\n' "$ENV_FILE" "$RESET"
  pause "Ready to start?"
}

# stage "Name": new screen, then the stage header with its number and the total.
stage() {
  _clear
  _STAGE_INDEX=$((_STAGE_INDEX + 1))
  printf '\n%s%s▸ Stage %s/%s · %s%s\n' \
    "$BOLD" "$BLUE" "$_STAGE_INDEX" "$TOTAL_STAGES" "$1" "$RESET"
}

# say "...": an unmarked line of explanation.
say() { printf '  %s\n' "$1"; }
# step "...": a bulleted thing for the person to do; note is dim, warn is yellow.
step() { printf '  %s•%s %s\n' "$BLUE" "$RESET" "$1"; }
note() { printf '  %s%s%s\n' "$DIM" "$1" "$RESET"; }
warn() { printf '  %s⚠ %s%s\n' "$YELLOW" "$1" "$RESET"; }

# open_url URL: hand the page to the first opener found (wslview, explorer.exe,
# xdg-open, open). Only https:// is accepted; other schemes get a warning (this also
# keeps a crafted file:// or UNC path away from the explorer.exe branch on
# Windows, where it could trigger an SMB/NTLM credential leak). The full URL
# is printed BEFORE dispatch so the human sees exactly what is being opened.
# shellcheck disable=SC2310  # warn always succeeds; the || branch is the handled fallback
open_url() {
  local url="$1"
  if [[ "$url" != https://* ]]; then
    warn "refusing to open non-https URL: $url"
    return 0
  fi
  printf '  %s↗ opening%s %s\n' "$GREEN" "$RESET" "$url"
  # explorer.exe exits 1 even on success, so its status must not trip the
  # manual-fallback warning on the supported Git Bash path.
  {
    if command -v wslview >/dev/null 2>&1; then
      wslview "$url"
    elif command -v explorer.exe >/dev/null 2>&1; then
      explorer.exe "$url" || true
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$url"
    elif command -v open >/dev/null 2>&1; then
      open "$url"
    else warn "no browser opener found; open this address yourself: $url"; fi
  } >/dev/null 2>&1 || warn "the browser did not open; open this address yourself: $url"
}

# _drain_tty — discard tty input already buffered (a multi-line paste into an
# earlier prompt) so a gate only ever consumes a line the human typed at it.
# Without this, pasted `value\ny\n` would silently answer the next gate.
_drain_tty() {
  while read -r -t 0 -u 3; do
    IFS= read -r -u 3 _ || break
  done
}

# pause "msg": hold until the person presses Enter after the off-screen work.
# A read failure (terminal closed) is fatal, never silently skipped: a pause
# that falls through at EOF would fail open.
# shellcheck disable=SC2310  # fatal exits the script directly; set -e suppression is moot
pause() {
  _drain_tty
  printf '  %s%s%s ' "$DIM" "${1:-Done? Press Enter.}" "$RESET"
  read -r -u 3 _ || fatal "terminal closed at a pause gate — aborting"
}

# confirm "question": a yes/no gate whose default is no. Fail-closed: only an
# explicit y/Y answers yes, a read failure aborts the wizard, and buffered
# paste is drained first so a leftover line can never answer the gate.
# shellcheck disable=SC2310  # fatal exits the script directly; set -e suppression is moot
confirm() {
  local reply=""
  _drain_tty
  printf '  %s? %s [y/N]%s ' "$YELLOW" "$1" "$RESET"
  read -r -u 3 reply || fatal "terminal closed at a confirmation gate — aborting"
  [[ "$reply" =~ ^[Yy] ]]
}

# _existing KEY: the value ENV_FILE already holds for KEY (none: status 1), one matched
# pair of surrounding quotes stripped (write_env stores values single-quoted,
# so re-run defaults must offer the value back, not the quoting). For a
# single-quoted line, write_env's escaping ('\'' for an embedded ') is also
# reversed, so Enter-keeps-current never re-escapes an already-escaped value.
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
    \"*\") val="${val:1:${#val}-2}" ;;
    *) ;; # unquoted (hand-written line) — offer verbatim
    esac
  fi
  printf '%s' "$val"
}

# _ask_prompt "Prompt" CURRENT: the prompt line ask and ask_secret share. The
# "[Enter keeps current]" hint shows only when a stored value can be kept.
_ask_prompt() {
  if [[ -n "$2" ]]; then
    printf '  %s%s%s %s[Enter keeps current]%s ' "$BOLD" "$1" "$RESET" "$DIM" "$RESET"
  else
    printf '  %s%s%s ' "$BOLD" "$1" "$RESET"
  fi
}

# _resolve_link PATH — print PATH's final target, following every symlink hop,
# as an absolute physical path. Portable to older macOS: plain readlink (no
# -f) and `cd -P`/`pwd -P`, never realpath.
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

# _check_env_target — an ENV_FILE that resolves outside the project, through a
# symlinked file or a symlinked parent directory (a hostile repo can ship
# `.env -> ~/.bashrc` or `sub -> ~`), is written to only after the human sees
# the real destination and says yes; like open_url, the destination is printed
# before anything is dispatched. A target inside the project under any .git
# directory (`.env -> .git/config`, a nested repo's metadata) gets the same gate:
# a secret appended there sits in a world-readable file, and a key name of the
# repo's choosing is read as git configuration. Runs before any value is
# prompted for. The path is re-resolved on every call and the yes is remembered
# for that resolved target only, so a link repointed mid-run asks again. A
# decline or an unanswerable gate aborts with nothing written.
_ENV_TARGET_CONFIRMED=""
# shellcheck disable=SC2310  # every || branch is fatal, which exits the script directly
_check_env_target() {
  local target rel
  if ! target=$(_resolve_link "$ENV_FILE"); then
    [[ ! -L "$ENV_FILE" ]] || fatal "couldn't resolve where the symlink $ENV_FILE points — nothing written"
    return 0 # its directory does not exist, so nothing can be written there
  fi
  [[ "$target" != "$_ENV_TARGET_CONFIRMED" ]] || return 0
  # Lowercased: on a case-insensitive filesystem .GIT/config is the git config.
  rel=$(printf '/%s/' "${target#"$_WIZARD_PROJECT_DIR"/}" | LC_ALL=C tr '[:upper:]' '[:lower:]')
  if [[ "$target" != "$_WIZARD_PROJECT_DIR"/* ]]; then
    warn "$ENV_FILE resolves to a file outside this project: $target"
  elif [[ "$rel" == */.git/* ]]; then
    warn "$ENV_FILE resolves into git metadata: $target"
  else
    return 0
  fi
  confirm "Write values to $target?" || fatal "declined writing through $ENV_FILE to $target — nothing written"
  _ENV_TARGET_CONFIRMED="$target"
}

# _assignable_key KEY — ask, ask_secret and write_env assign $KEY in the
# library's own shell, so KEY must not name the library's state (ENV_FILE,
# SKIPPED, ...), a helper local (__wiz_*), or a variable the shell itself sets
# or reads (PATH, IFS, PS4, BASH_ENV, ...: the "Shell Variables" list in the
# bash manual), whose new value would change how the rest of the wizard runs.
# LD_* and DYLD_* are refused too: when already exported, the dynamic loader
# reads them in every command the wizard starts (gh, git, mktemp).
# A key the shell already exports (GH_TOKEN, BROWSER, GIT_SSH_COMMAND, ...) is
# refused: printf -v keeps the export flag, so the assigned value would reach
# gh, git and the browser opener.
# Gate KEY with _valid_key first.
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
  # declare -p prints the attribute flags first (declare -x, -rx, ...).
  __wiz_decl=$(declare -p -- "$1" 2>/dev/null) || return 0
  __wiz_decl=${__wiz_decl#declare -}
  if [[ "${__wiz_decl%% *}" == *x* ]]; then
    fatal "exported key name: '$1' (already exported, so a value the wizard assigns would reach gh, git and the browser opener; pick another name)"
  fi
}

# ask, ask_secret and write_env assign $KEY with printf -v, which writes the
# innermost variable of that name: a helper local spelled like the key would
# take the value instead of the caller. Their locals carry a __wiz_ prefix, a
# name _assignable_key refuses as a key.

# ask KEY "Prompt": store the typed answer in the shell variable named KEY.
# Input is shown on screen, for public values; readline (-e) gives arrow-key
# editing. A value already in .env is the default, and Enter accepts it.
# shellcheck disable=SC2310  # fatal exits the script directly; set -e suppression is moot
ask() {
  local __wiz_key="$1" __wiz_prompt="$2" __wiz_current __wiz_input
  _valid_key "$__wiz_key"
  _assignable_key "$__wiz_key"
  _check_env_target
  __wiz_current=$(_existing "$__wiz_key" || true)
  _ask_prompt "$__wiz_prompt" "$__wiz_current"
  read -r -e -u 3 __wiz_input || fatal "terminal closed while reading $__wiz_key — aborting"
  [[ -z "$__wiz_input" && -n "$__wiz_current" ]] && __wiz_input="$__wiz_current"
  printf -v "$__wiz_key" '%s' "$__wiz_input"
}

# ask_secret KEY "Prompt": the ask contract with nothing echoed. No readline
# here, because -e would echo and -s has to take effect.
# shellcheck disable=SC2310  # fatal exits the script directly; set -e suppression is moot
ask_secret() {
  local __wiz_key="$1" __wiz_prompt="$2" __wiz_current __wiz_input
  _valid_key "$__wiz_key"
  _assignable_key "$__wiz_key"
  _check_env_target
  __wiz_current=$(_existing "$__wiz_key" || true)
  _ask_prompt "$__wiz_prompt" "$__wiz_current"
  read -rs -u 3 __wiz_input || fatal "terminal closed while reading secret $__wiz_key — aborting"
  printf '\n'
  [[ -z "$__wiz_input" && -n "$__wiz_current" ]] && __wiz_input="$__wiz_current"
  printf -v "$__wiz_key" '%s' "$__wiz_input"
}

# _check_env_ignored — warn loudly (once) when ENV_FILE is not gitignored in a
# git repo: a captured secret must never be one `git add .` from a commit.
_ENV_IGNORE_WARNED=0
_check_env_ignored() {
  ((_ENV_IGNORE_WARNED)) && return 0
  command -v git >/dev/null 2>&1 || return 0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  if ! git check-ignore -q -- "$ENV_FILE" 2>/dev/null; then
    _ENV_IGNORE_WARNED=1
    warn "$ENV_FILE is NOT gitignored — a secret written here can be committed"
    SKIPPED+=("gitignore $ENV_FILE (add it to .gitignore before any commit)")
  fi
}

# write_env KEY VALUE: leave exactly one KEY='VALUE' line in ENV_FILE, creating
# the file when absent, and set $KEY in the shell, as ask does; running it twice
# changes nothing. Single quotes wrap the value, with embedded single quotes
# escaped, so shells and dotenv loaders read it back verbatim. A regular file is
# replaced by an atomic rename of a 0600 temp file. A symlinked ENV_FILE (a
# shared secret store) is written through instead, so the link survives, its
# target gets the key and keeps its own mode; that write is not atomic. A link
# pointing outside the project is written through only after _check_env_target's
# confirmation.
write_env() {
  local __wiz_key="$1" __wiz_value="$2" __wiz_escaped __wiz_tmp
  _valid_key "$__wiz_key"
  _assignable_key "$__wiz_key"
  _check_env_target
  _check_env_ignored # pre-flight: warn BEFORE the first value lands on disk
  __wiz_tmp=$(mktemp "${ENV_FILE}.XXXXXX") || fatal "mktemp failed next to $ENV_FILE"
  _WIZARD_TMP="$__wiz_tmp"
  chmod 600 "$__wiz_tmp"
  __wiz_escaped=${__wiz_value//\'/\'\\\'\'}
  if [[ -f "$ENV_FILE" ]]; then grep -vE "^${__wiz_key}=" "$ENV_FILE" >"$__wiz_tmp" || true; fi
  printf "%s='%s'\n" "$__wiz_key" "$__wiz_escaped" >>"$__wiz_tmp"
  if [[ -L "$ENV_FILE" ]]; then
    # umask 077: a dangling link's newly created target is owner-only too.
    (umask 077 && cat -- "$__wiz_tmp" >"$ENV_FILE") || fatal "couldn't write through the symlink $ENV_FILE"
    rm -f -- "$__wiz_tmp"
  else
    mv -- "$__wiz_tmp" "$ENV_FILE"
  fi
  _WIZARD_TMP=""
  printf -v "$__wiz_key" '%s' "$__wiz_value"
  WRITTEN_ENV+=("$__wiz_key")
  printf '  %s✓ wrote%s %s → %s\n' "$GREEN" "$RESET" "$__wiz_key" "$ENV_FILE"
}

# ── GitHub Actions helpers ────────────────────────────────────────────────
# portability-ok: storing a secret or variable for GitHub Actions is inherently
# a GitHub-forge capability — these helpers exist only for stages whose
# declared destination is GitHub CI, degrade to SKIPPED when gh is absent,
# and nothing else in this library touches a forge.

# _gh_ready — gh installed and authenticated.
_gh_ready() {
  command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1
}

# _resolve_repo — resolve the target repo ONCE, echo it, and get explicit
# confirmation before the first CI write. Every later gh call passes it via
# --repo so a write can never land in whatever repo the cwd happens to imply.
GH_REPO=""
GH_REPO_DECLINED=0
# shellcheck disable=SC2310  # confirm's no-branch is the handled decline path; fatal exits directly
_resolve_repo() {
  [[ -n "$GH_REPO" ]] && return 0
  ((GH_REPO_DECLINED)) && return 1
  local repo
  if ! repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>&1); then
    GH_REPO_DECLINED=1
    warn "couldn't resolve the GitHub repo — CI writes will be skipped"
    SKIPPED+=("resolve GitHub repo (gh repo view failed: ${repo})")
    return 1
  fi
  say "GitHub CI values will be written to: ${BOLD}${repo}${RESET}"
  if ! confirm "Write CI secrets/variables to ${repo}?"; then
    GH_REPO_DECLINED=1
    warn "CI writes to ${repo} declined — set them manually"
    SKIPPED+=("GitHub CI writes (declined for ${repo})")
    return 1
  fi
  GH_REPO="$repo"
}

# _gh_set KIND NAME VALUE: the shared body of set_secret/set_var. KIND is both
# the gh subcommand and the noun every message uses, so the two helpers cannot
# drift in their refusals or their remediation lines.
# shellcheck disable=SC2310  # _gh_ready/_resolve_repo are status-returning gates; every false branch is handled
_gh_set() {
  local kind="$1" name="$2" value="$3" err
  _valid_key "$name"
  if [[ -z "$value" ]]; then
    warn "refusing to set GitHub $kind $name — empty value"
    SKIPPED+=("GitHub $kind $name (empty value — nothing was sent to gh)")
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
  else
    warn "couldn't set GitHub $kind $name — see the closing summary"
    SKIPPED+=("GitHub $kind $name (gh error: ${err})")
  fi
}

# set_secret NAME VALUE: store a repository secret for GitHub Actions through gh,
# passing the value on stdin, never as an argument. Empty values are refused; gh errors surface into
# the closing summary instead of vanishing into /dev/null.
set_secret() { _gh_set secret "$1" "$2"; }

# set_var NAME VALUE: the same for a plain (non-secret) Actions variable, value
# on stdin (gh reads standard input when --body is omitted), never
# argv. Same refusals as set_secret.
set_var() { _gh_set variable "$1" "$2"; }

# finish: last screen. Lists what was saved and what is left to the person, by
# name; no value is ever printed.
finish() {
  _clear
  printf '\n%s%s  ✓ Setup complete%s\n' "$BOLD" "$GREEN" "$RESET"
  ((${#WRITTEN_ENV[@]})) && note "$ENV_FILE keys saved (${#WRITTEN_ENV[@]}): ${WRITTEN_ENV[*]}"
  ((${#WRITTEN_SECRET[@]})) && note "${GH_REPO} CI secrets stored (${#WRITTEN_SECRET[@]}): ${WRITTEN_SECRET[*]}"
  ((${#WRITTEN_VAR[@]})) && note "${GH_REPO} CI variables stored (${#WRITTEN_VAR[@]}): ${WRITTEN_VAR[*]}"
  if ((${#SKIPPED[@]})); then
    printf '\n'
    warn "still to do by hand:"
    for s in "${SKIPPED[@]}"; do note "  - $s"; done
  fi
  printf '\n'
}

# ──────────────────────────────────────────────────────────────────────────
# STAGES: the part you write. Delete the example stage below, add one stage()
# call per row of the confirmed stage plan, in plan order, and make
# TOTAL_STAGES equal the number of stage() calls.
# ──────────────────────────────────────────────────────────────────────────

TOTAL_STAGES=1

banner "Mail provider setup"

# ── EXAMPLE STAGE (fictional provider at mail.example.com): delete it ─────
# shellcheck disable=SC2154  # ask/ask_secret assign the named variable via printf -v
stage "Mail provider: sending domain and API token"
say "This stage records the sending domain and a send-only API token."
open_url "https://mail.example.com/settings/api"
step "Under Sending domain, copy the domain shown as Verified."
ask MAIL_FROM_DOMAIN "Sending domain:"
step "Choose Create token, tick only the Send scope, and copy the new token."
ask_secret MAIL_API_TOKEN "API token:"
# shellcheck disable=SC2154  # assigned by ask via printf -v
write_env MAIL_FROM_DOMAIN "$MAIL_FROM_DOMAIN"
# shellcheck disable=SC2154  # assigned by ask_secret via printf -v
write_env MAIL_API_TOKEN "$MAIL_API_TOKEN"
set_secret MAIL_API_TOKEN "$MAIL_API_TOKEN" # the deploy workflow reads secrets.MAIL_API_TOKEN
# ── END EXAMPLE STAGE ─────────────────────────────────────────────────────

finish
