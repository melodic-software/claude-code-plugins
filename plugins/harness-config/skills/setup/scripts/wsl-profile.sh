#!/usr/bin/env bash
# wsl-profile.sh — the opt-in WSL hardening profile for Claude Code settings.
#
#   wsl-profile.sh detect             exit 0 on a WSL host, 1 otherwise
#   wsl-profile.sh print              print the settings block for this host (WSL only)
#   wsl-profile.sh lint <file>        fail on any Write(path) rule or non-`//` Read/Edit path rule
#
# Print-only: nothing is written. Paths come from $HOME and the Windows user
# directories visible under $WSL_PROFILE_MNT_ROOT (default /mnt); nothing
# machine-specific is baked in. Exit: 0 ok, 1 not WSL (detect/print) or a rule
# failed lint, 2 usage or missing prerequisite.
set -uo pipefail

MNT_ROOT="${WSL_PROFILE_MNT_ROOT:-/mnt}"
PROC_VERSION="${WSL_PROFILE_PROC_VERSION:-/proc/version}"

is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" ]] && return 0
  [[ -r "$PROC_VERSION" ]] && grep -qi -E 'microsoft|wsl' "$PROC_VERSION"
}

need_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "wsl-profile: jq is required" >&2
    exit 2
  }
}

# Windows user directories as WSL sees them: <mnt>/<drive>/Users/<user>.
windows_homes() {
  local d
  for d in "$MNT_ROOT"/?/Users/*/; do
    d="${d%/}"
    case "${d##*/}" in Public | Default | "Default User" | "All Users" | desktop.ini) continue ;; *) ;; esac
    [[ -d "$d" ]] && printf '%s\n' "$d"
  done
}

print_profile() {
  need_jq
  [[ -n "${HOME:-}" && "$HOME" == /* ]] || {
    echo "wsl-profile: HOME is not an absolute path" >&2
    exit 2
  }
  local home="$HOME" win_homes=() line
  while IFS= read -r line; do win_homes+=("$line"); done < <(windows_homes)
  if ((${#win_homes[@]} == 0)); then
    echo "wsl-profile: no Windows user directory under $MNT_ROOT/<drive>/Users; the Edit rules use placeholders" >&2
    win_homes=("$MNT_ROOT/<drive>/Users/<windows-user>")
  elif ((${#win_homes[@]} > 1)); then
    echo "wsl-profile: ${#win_homes[@]} Windows user directories found; rules emitted for each, delete the ones that are not yours" >&2
  fi

  # `//` plus the path without its leading slash is the absolute form.
  local rules=() w
  rules+=("Read(/$home/.ssh/id_*)")
  rules+=("Read(/$home/.azure/msal_token_cache*)")
  rules+=("Read(/$home/.config/gh/hosts.yml)")
  rules+=("Read(/$home/.gnupg/**)")
  rules+=("Read(/$home/.microsoft/usersecrets/**)")
  for w in "${win_homes[@]}"; do
    rules+=("Edit(/$w/.claude/**)")
    rules+=("Edit(/$w/.claude.json)")
  done

  jq -n --arg tmp "${WSL_PROFILE_TMPDIR:-/tmp}" \
    '{permissions: {deny: $ARGS.positional}, env: {TMPDIR: $tmp}}' \
    --args "${rules[@]}"
}

lint_file() {
  need_jq
  local f="$1" bad
  [[ -f "$f" ]] || {
    echo "wsl-profile: $f is not a file" >&2
    exit 2
  }
  bad="$(jq -r '
    [(.permissions // {}) | (.allow // [], .deny // [], .ask // []) | .[]
     | select(type == "string")
     | select(test("^Write\\(.+\\)$")
              or (test("^(Read|Edit)\\(.+\\)$") and (test("^(Read|Edit)\\(//") | not)))]
    | .[]' "$f")" || {
    echo "wsl-profile: $f is not valid JSON" >&2
    exit 2
  }
  if [[ -n "$bad" ]]; then
    printf 'FAIL: Write(path) rule, or Read/Edit rule without a // prefix: %s\n' "$bad" >&2
    exit 1
  fi
  echo "PASS: every path rule is Read(//...) or Edit(//...)"
}

case "${1:-}" in
  detect) is_wsl ;;
  print)
    if ! is_wsl; then
      echo "wsl-profile: this is not a WSL host; the profile does not apply" >&2
      exit 1
    fi
    print_profile
    ;;
  lint)
    [[ $# -eq 2 ]] || {
      echo "usage: wsl-profile.sh lint <file>" >&2
      exit 2
    }
    lint_file "$2"
    ;;
  *)
    echo "usage: wsl-profile.sh detect | print | lint <file>" >&2
    exit 2
    ;;
esac
