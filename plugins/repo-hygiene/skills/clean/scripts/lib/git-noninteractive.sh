# shellcheck shell=bash

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
