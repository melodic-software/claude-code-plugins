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
  BOLD=$(tput bold)
  DIM=$(tput dim)
  RESET=$(tput sgr0)
  BLUE=$(tput setaf 4)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  RED=$(tput setaf 1)
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
WRITTEN_ENV=()    # keys saved in ENV_FILE during this run
WRITTEN_SECRET=() # CI secret names stored during this run
WRITTEN_VAR=()    # CI variable names stored during this run
SKIPPED=()        # manual follow-ups: no gh, a gh failure, a declined repo

# Temp-file hygiene: write_env stages its rewrite in a mktemp file alongside
# ENV_FILE (same filesystem, so the final mv is an atomic rename); the trap
# removes it if the wizard dies mid-write.
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
# terminal, which keeps a captured log free of escape codes.
_clear() {
  [[ -t 1 ]] || return 0
  if command -v tput >/dev/null 2>&1; then tput clear; else printf '\033[2J\033[3J\033[H'; fi
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

# ask KEY "Prompt": store the typed answer in the shell variable named KEY.
# Input is shown on screen, for public values; readline (-e) gives arrow-key
# editing. A value already in .env is the default, and Enter accepts it.
# shellcheck disable=SC2310  # fatal exits the script directly; set -e suppression is moot
ask() {
  local key="$1" prompt="$2" current input
  _valid_key "$key"
  current=$(_existing "$key" || true)
  _ask_prompt "$prompt" "$current"
  read -r -e -u 3 input || fatal "terminal closed while reading $key — aborting"
  [[ -z "$input" && -n "$current" ]] && input="$current"
  printf -v "$key" '%s' "$input"
}

# ask_secret KEY "Prompt": the ask contract with nothing echoed. No readline
# here, because -e would echo and -s has to take effect.
# shellcheck disable=SC2310  # fatal exits the script directly; set -e suppression is moot
ask_secret() {
  local key="$1" prompt="$2" current input
  _valid_key "$key"
  current=$(_existing "$key" || true)
  _ask_prompt "$prompt" "$current"
  read -rs -u 3 input || fatal "terminal closed while reading secret $key — aborting"
  printf '\n'
  [[ -z "$input" && -n "$current" ]] && input="$current"
  printf -v "$key" '%s' "$input"
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
# the file when absent; running it twice changes nothing. Single quotes wrap the value, with
# embedded single quotes escaped, so shells and dotenv loaders read it back
# verbatim; the file is chmod 600 after every write.
write_env() {
  local key="$1" value="$2" escaped tmp
  _valid_key "$key"
  _check_env_ignored # pre-flight: warn BEFORE the first value lands on disk
  touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  tmp=$(mktemp "${ENV_FILE}.XXXXXX") || fatal "mktemp failed next to $ENV_FILE"
  _WIZARD_TMP="$tmp"
  chmod 600 "$tmp"
  escaped=${value//\'/\'\\\'\'}
  grep -vE "^${key}=" "$ENV_FILE" >"$tmp" || true
  printf "%s='%s'\n" "$key" "$escaped" >>"$tmp"
  mv -- "$tmp" "$ENV_FILE"
  _WIZARD_TMP=""
  chmod 600 "$ENV_FILE"
  WRITTEN_ENV+=("$key")
  printf '  %s✓ wrote%s %s → %s\n' "$GREEN" "$RESET" "$key" "$ENV_FILE"
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
