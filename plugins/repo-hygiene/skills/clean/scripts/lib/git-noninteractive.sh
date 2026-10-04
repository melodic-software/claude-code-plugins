# shellcheck shell=bash
# Networked git for the clean scripts. Sourceable; not invoked directly.
#
# The child git has prompts off: GIT_TERMINAL_PROMPT=0, stdin from /dev/null,
# GCM_INTERACTIVE=0, and -c credential.interactive=false, so a helper that would
# open a dialog fails instead. The ssh command is the one git would run
# (GIT_SSH_COMMAND, else core.sshCommand, else GIT_SSH, else ssh), handed back as
# the child GIT_SSH_COMMAND with batch options for its ssh variant, never a fixed
# `ssh -o BatchMode=yes`, because that variable overrides the configured command.
# Global and system git config stay in place, and nothing here writes config.
#
# The variant is resolved the way git resolves it: GIT_SSH_VARIANT, else
# ssh.variant, else the basename of the command's first word, else the -G probe.
# Source: https://git-scm.com/docs/git-config#Documentation/git-config.txt-sshvariant
# and determine_ssh_variant in git's connect.c; as of 2026-10-04 (git v2.56);
# recheck when git adds a variant or changes the probe. ssh takes
# `-o BatchMode=yes -o ConnectTimeout=5` right after the program word, ahead of
# any configured -o, since OpenSSH keeps the first value it obtains for an option
# (https://man.openbsd.org/ssh_config). plink and putty take Plink's -batch.
# tortoiseplink already gets -batch from git, and simple takes no options. An
# explicit ssh variant is trusted as git trusts it; an unrecognized basename gets
# the ssh options only when the command with them passes the same -G probe.

# _clean_ssh_first_word <command> — sets the caller's ssh_word (the first word
# as git's split_cmdline reads it) and ssh_word_end (its length in <command>).
# Returns 1 on an unclosed quote or a trailing backslash, which git rejects too.
_clean_ssh_first_word() {
  local cmd="$1" i=0 n=${#1} c quoted="" ended=0
  ssh_word=""
  ssh_word_end=$n
  while ((i < n)); do
    c="${cmd:i:1}"
    if [[ -z "$quoted" && "$c" == [[:space:]] ]]; then
      if ((!ended)); then
        ssh_word_end=$i
        ended=1
      fi
    elif [[ -z "$quoted" && ("$c" == "'" || "$c" == '"') ]]; then
      quoted="$c"
    elif [[ -n "$quoted" && "$c" == "$quoted" ]]; then
      quoted=""
    else
      if [[ "$c" == "\\" && "$quoted" != "'" ]]; then
        i=$((i + 1))
        ((i < n)) || return 1
        c="${cmd:i:1}"
      fi
      ((ended)) || ssh_word+="$c"
    fi
    i=$((i + 1))
  done
  [[ -z "$quoted" ]]
}

# _clean_ssh_command [repo] — prints the batch-mode ssh command for git's child.
_clean_ssh_command() {
  local repo="${1:-}" cmd="" variant="" explicit=0 base="" candidate ssh_word ssh_word_end
  local sq="'" q="'\\''"
  local -a cfg=(git)
  [[ -n "$repo" ]] && cfg=(git -C "$repo")
  if [[ -n "${GIT_SSH_COMMAND:-}" ]]; then
    cmd="$GIT_SSH_COMMAND"
  else
    cmd="$("${cfg[@]}" config --get core.sshCommand 2>/dev/null || true)"
    cmd="${cmd//$'\r'/}"
    if [[ -z "$cmd" && -n "${GIT_SSH:-}" ]]; then
      cmd="'${GIT_SSH//$sq/$q}'"
    fi
  fi
  [[ -n "$cmd" ]] || cmd="ssh"

  if [[ -n "${GIT_SSH_VARIANT+set}" ]]; then
    variant="$GIT_SSH_VARIANT"
  elif variant="$("${cfg[@]}" config --get ssh.variant 2>/dev/null)"; then
    variant="${variant//$'\r'/}"
  else
    variant="auto"
  fi
  case "$variant" in
  auto | plink | putty | tortoiseplink | simple) ;;
  *) variant="ssh" ;;
  esac
  [[ "$variant" == auto ]] || explicit=1

  if ! _clean_ssh_first_word "$cmd"; then
    printf '%s' "$cmd"
    return 0
  fi
  base="${ssh_word%"${ssh_word##*[!/\\]}"}"
  base="${base##*[/\\]}"
  base="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  if [[ "$variant" == auto ]]; then
    case "$base" in
    ssh | ssh.exe) variant="ssh" ;;
    plink | plink.exe) variant="plink" ;;
    tortoiseplink | tortoiseplink.exe) variant="tortoiseplink" ;;
    *) ;;
    esac
  fi

  case "$variant" in
  plink | putty)
    printf '%s -batch%s' "${cmd:0:ssh_word_end}" "${cmd:ssh_word_end}"
    ;;
  tortoiseplink | simple)
    printf '%s' "$cmd"
    ;;
  *)
    candidate="${cmd:0:ssh_word_end} -o BatchMode=yes -o ConnectTimeout=5${cmd:ssh_word_end}"
    if ((explicit)) || [[ "$base" == ssh || "$base" == ssh.exe ]] ||
      sh -c "$candidate"' "$@"' "$candidate" -G git-noninteractive.invalid \
        </dev/null >/dev/null 2>&1; then
      printf '%s' "$candidate"
    else
      printf '%s' "$cmd"
    fi
    ;;
  esac
}

# clean_git_noninteractive [git args...] — one git command, prompts off.
# Exit status is git's. stdout and stderr pass through.
clean_git_noninteractive() {
  local repo=""
  if [[ "${1:-}" == "-C" && -n "${2:-}" ]]; then
    repo="$2"
  fi
  GIT_TERMINAL_PROMPT=0 \
    GCM_INTERACTIVE=0 \
    GIT_SSH_COMMAND="$(_clean_ssh_command "$repo")" \
    git -c credential.interactive=false "$@" </dev/null
}
