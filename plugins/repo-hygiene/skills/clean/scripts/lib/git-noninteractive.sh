# shellcheck shell=bash
# Networked git for the clean scripts. Sourceable; not invoked directly.
#
# The child git has prompts off: GIT_TERMINAL_PROMPT=0, stdin from /dev/null,
# GCM_INTERACTIVE=0, and -c credential.interactive=false, so a helper that would
# open a dialog fails instead. The ssh command is core.sshCommand (default ssh),
# or GIT_SSH_COMMAND when that is already set, with BatchMode and a connect
# timeout appended. The child GIT_SSH_COMMAND is that resolved command, never a
# fixed `ssh -o BatchMode=yes`, because the variable overrides core.sshCommand.
# Global and system git config stay in place, and nothing here writes config.

# clean_git_noninteractive [git args...] — one git command, prompts off.
# Exit status is git's. stdout and stderr pass through.
clean_git_noninteractive() {
  local ssh_base="" repo=""
  if [[ "${1:-}" == "-C" && -n "${2:-}" ]]; then
    repo="$2"
  fi
  if [[ -n "${GIT_SSH_COMMAND:-}" ]]; then
    ssh_base="$GIT_SSH_COMMAND"
  elif [[ -n "$repo" ]]; then
    ssh_base="$(git -C "$repo" config --get core.sshCommand 2>/dev/null || true)"
  else
    ssh_base="$(git config --get core.sshCommand 2>/dev/null || true)"
  fi
  ssh_base="${ssh_base//$'\r'/}"
  [[ -n "$ssh_base" ]] || ssh_base="ssh"
  ssh_base="$ssh_base -o BatchMode=yes -o ConnectTimeout=5"
  GIT_TERMINAL_PROMPT=0 \
    GCM_INTERACTIVE=0 \
    GIT_SSH_COMMAND="$ssh_base" \
    git -c credential.interactive=false "$@" </dev/null
}
