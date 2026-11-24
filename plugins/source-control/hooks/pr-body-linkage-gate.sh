#!/usr/bin/env bash
# PreToolUse hook: block a bare `gh pr create` / `gh pr edit` whose PR BODY
# carries a negated closing reference. A command the shared reader cannot parse
# (lib/hook-utils.sh: shfmt missing, failing, too slow, or a syntax error such
# as an unterminated here-doc) is denied too, before any body is judged.
#
# WHY IT EXISTS — a negated closer (`does not close #N`) still closes the issue
# on merge, because GitHub's closing-keyword parser ignores the negation, and CI
# reports it only one round trip after the PR is already open. This hook covers
# the calls that never go through `/source-control:pull-request create`.
#
# WHAT IT ENFORCES — no negated closing reference anywhere in the body, judged
# as the PR-body contract step judges it in CI (https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/pr-body-convention/README.md), after stripping HTML comments
# (terminated ones, then an unterminated `<!--` swallowing the rest) and masking
# Markdown code. The rest of that contract (a closing line and non-empty
# `## Summary`, `## Fix`, `## Verification` and `## Related` sections) is
# advisory in CI, so a body missing any of it is allowed.
#
# SCOPE GUARD — enforcement is keyed to the repository's OWN policy: the gate
# runs only when one of the repo's `.github/workflows/*.yml` / `*.yaml` files
# matches `linkage_gate_uses_pattern` (https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/source-control/reference/config-resolution.md#yaml-keys-docsconventionssource-controlyaml); unset gates no repo. The first matching file, in sorted glob order, becomes GATE_FILE. A repo that does not
# run the step is never gated, so the hook cannot drift away from what its
# consumer actually enforces. This is deliberately NOT the
# `pr_body_required_sections` seam (docs/contracts/pr-body-convention/): that
# key is the repo's configurable section scaffold, whose portable default
# excludes `Related` on purpose. The authority for THIS gate is the workflow
# that wires the step in.
#
# WHICH DIRECTORY — the workflow scan and any relative `--body-file` resolve
# against the payload's `cwd`. A `cd`/`pushd`/`popd` earlier in the same command line
# moves the directory `gh` actually runs in, and the segment tokenizer discards
# that segment, so neither resolution would be knowable: the call goes OUT OF
# SCOPE from that point on, exactly as a `--repo`-targeted one does. Only the
# CURRENT shell's own relocation counts — `command cd`, `builtin cd`, and
# `eval cd` do move it; `sudo cd` and `env cd` are separate processes that fail
# on a builtin and move nothing.
#
# FAIL-OPEN ON EXTRACTION, FAIL-CLOSED ON A DETERMINABLE BAD BODY. The body is
# only judged when it can be read statically: a `--body`/`-b` literal, a
# `--body-file`/`-F <path>` that exists, or the sole heredoc when the command
# feeds stdin (`--body-file -`) or wraps one in a command substitution
# (`--body "$(cat <<'EOF' … EOF)"`). A value carrying an unexpanded `$` or
# backtick with no heredoc to resolve it, a body flag with no following word (a
# command `gh` itself rejects), an absent body flag (`--fill`, `--template`,
# `--editor`, `--web`, the interactive prompt), or an unreadable body file all
# ALLOW: guessing at a body this hook cannot see would block compliant calls.
# The exception is a command the reader cannot parse at all, which is denied
# (see the first paragraph).
# A stalled or unreadable hook payload allows too — unlike the sibling SECURITY
# guards, refusing an arbitrary Bash command because this POLICY gate could not
# read its own stdin is a worse failure than missing one body check.
#
# LOCALE — `[[:space:]]` stands in for JavaScript's `\s`, but its membership is
# locale-defined while `\s` is a fixed set, so the same body could be judged
# differently depending on ambient environment. Both halves are pinned instead:
# every non-ASCII character in the `\s` set is rewritten to a plain space by
# byte sequence (locale-independent), and matching then runs under `LC_ALL=C`,
# where `[[:space:]]` is exactly the six ASCII whitespace characters. The two
# together reproduce `\s` on any host.
#
# DECLARED BYPASS COVERAGE (out of scope, documented): the PowerShell tool —
# the Bash-faithful PowerShell command classifier is guardrails-owned and not
# vendored here; `gh api …/pulls` direct API calls; `gh pr edit` invocations
# that change no body (`--title`, `--add-label` alone) — the CI gate re-runs on
# `edited`, but such an edit leaves the body it already validated untouched; any
# invocation carrying `--repo`/`-R` or following a directory change; and four
# residuals, each a MISS or a contrivance, never a false block:
#   - the validator strips a comment span spanning a line break and JOINS what
#     surrounds it, so `does not <!--` then `-->close` on the next line is a
#     negated closer to CI and an un-negated one here. Reproducing it needs
#     whole-body rather than per-line stripping, and the shape does not occur
#     in a real body.
#   - `env -S` operands are re-parsed with the Bash tokenizer, not env's own
#     split-string grammar (which has its own escape and `${VAR}` rules). The
#     two agree on every ordinary command line; a contrived operand exploiting
#     the difference could be read wrong. Re-parsing is still strictly better
#     than the alternative it replaced, which was to ignore the operand and let
#     the call through unexamined. The operand is spliced with the wrapper's
#     remaining argv first, since env appends those to whatever it split.
#   - a directory change confined to a SUBSHELL (`(cd /tmp) && gh pr create …`)
#     does not survive into the `gh` call, but the tracking flag here is
#     process-wide, so the call is treated as out of scope. Fixing it needs
#     subshell nesting the segment tokenizer does not expose.
#   - a directory change that FAILS (`cd /nonexistent || gh pr create …`) leaves
#     `gh` in the original directory, where the call could have been judged.
#     Whether a `cd` succeeds is a runtime fact, so a static gate cannot know;
#     assuming failure would false-block every case where it succeeds, and
#     assuming success is this fail-open miss. The safe assumption is taken.
#
# Kill switch: pr_body_linkage_gate_enabled userConfig option.
#
# BLOCKING: exits 2 naming each negated closer plus the `Refs: #N` line to use.

set -uo pipefail

# Pinned for the whole process: see LOCALE above. Set before anything reads a
# character class, including the shared lib.
export LC_ALL=C

[[ "${CLAUDE_PLUGIN_OPTION_PR_BODY_LINKAGE_GATE_ENABLED:-true}" == "true" ]] || exit 0
# Parameter expansion, not `dirname`: a command substitution forks, which is a
# process on Windows Git Bash. A bare filename strips to itself, so it means `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || exit 0

hook::require jq "PreToolUse" "source-control" "$INPUT"

hook::jq_fields "$INPUT" '.tool_input.command' '.cwd' || exit 0
COMMAND="${HOOK_JQ_FIELDS[0]}"
HOOK_CWD="${HOOK_JQ_FIELDS[1]}"
# hook::jq_fields keeps trailing newlines, and a cwd ending in one fails `git -C`
# and every relative `--body-file` join. Inline because the validator, with its
# linkage::chomp_to, is sourced only past the pre-filter.
while [[ "$HOOK_CWD" == *$'\n' ]]; do HOOK_CWD="${HOOK_CWD%$'\n'}"; done
[[ -n "$COMMAND" ]] || exit 0
# Applicability pre-filter before any repo I/O or parsing. `gh` must appear as
# its own word (or a path's last segment) so `npm run lighthouse-prod` does not
# pay for the parse. `.` stays OUT of the trailing class so `gh.exe` still
# matches, and out of the leading one so `./gh` does; a quote on either side is
# a boundary too, since the command text is pre-tokenizer.
[[ "$COMMAND" =~ (^|[^[:alnum:]_.-])[Gg][Hh][^[:alnum:]_-] ]] || exit 0
[[ "$COMMAND" == *"pr"* ]] || exit 0

REPO_ROOT=""
hook::repo_root_to REPO_ROOT "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}" || :

# shellcheck source=pr-linkage-scope.sh
source "$HOOK_DIR/pr-linkage-scope.sh"
GATE_FILE=""
linkage::gate_file_to GATE_FILE "$REPO_ROOT" "pr-body-linkage-gate"
[[ -n "$GATE_FILE" ]] || exit 0

FORM=""
DIR_CHANGED=0

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  hook::json_str_object_to data outcome "$1" form "$FORM"
  hook::emit_telemetry "pr-body-linkage-gate" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# shellcheck source=pr-linkage-validator.sh
source "$HOOK_DIR/pr-linkage-validator.sh"

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
sole_heredoc_body_to() {
  local __pbl_dest="$1" text="$2" line delim="" in_hd=0 t out="" count=0 li=0
  local start_re='(^|[^<])<<-?[[:space:]]*([^[:space:]<>]+)'
  printf -v "$__pbl_dest" '%s' ""
  linkage::split_lines "$text"
  for ((li = 0; li < ${#LINKAGE_LINES[@]}; li++)); do
    line="${LINKAGE_LINES[li]}"
    if ((in_hd)); then
      t="${line%$'\r'}"
      t="${t#"${t%%[![:space:]]*}"}"
      t="${t%"${t##*[![:space:]]}"}"
      [[ "$t" == "$delim" ]] && {
        in_hd=0
        continue
      }
      out+="${line%$'\r'}"$'\n'
      continue
    fi
    if [[ "$line" =~ $start_re ]]; then
      ((count++))
      ((count > 1)) && return 1
      delim="${BASH_REMATCH[2]}"
      delim="${delim#\\}"
      delim="${delim#\'}"
      delim="${delim%\'}"
      delim="${delim#\"}"
      delim="${delim%\"}"
      in_hd=1
    fi
  done
  ((count == 1 && in_hd == 0)) || return 1
  linkage::chomp_to "$__pbl_dest" "$out"
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
is_dynamic() {
  [[ "$1" == *'$'* || "$1" == *'`'* ]]
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
validate_body() {
  # shellcheck disable=SC2310  # the return status IS the verdict
  linkage::blocking_problems "$1" && return 0
  linkage::block_message "${GATE_FILE#"$REPO_ROOT/"}"
  emit_tel "blocked"
  exit 2
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
takes_value() {
  case "$1" in
  --assignee | --base | --body | --body-file | --head | --label | --milestone | \
    --project | --reviewer | --template | --title | --repo | --recover | \
    --add-assignee | --add-label | --add-project | --add-reviewer | \
    --remove-assignee | --remove-label | --remove-project | --remove-reviewer)
    return 0
    ;;
  *) return 1 ;;
  esac
}

# pflag groups shorthands: `-db BODY`, `-dbBODY`, `-dF file`, `-dFfile` are all
# valid and all carry a body, which a plain `-b`/`-F` match misses entirely.
# Walks the cluster; the first value-taking shorthand ends it, taking the rest
# of the word as its value or, when that is empty, the next word.
# Sets SHORT_KIND (body|file|repo|other|unknown), SHORT_VAL, SHORT_ATE_NEXT.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
parse_short_cluster() {
  local word="$1" next="$2" have_next="$3"
  local rest="${word#-}" c
  SHORT_KIND="other"
  SHORT_VAL=""
  SHORT_ATE_NEXT=0
  while [[ -n "$rest" ]]; do
    c="${rest:0:1}"
    rest="${rest:1}"
    case "$c" in
    # Value-taking shorthands. gh's own set; `b`/`F` carry the body, `R`
    # retargets the repository, the rest merely consume their value.
    b | F | R | a | B | H | l | m | p | r | T | t)
      if [[ -n "$rest" ]]; then
        SHORT_VAL="$rest"
      elif ((have_next)); then
        SHORT_VAL="$next"
        SHORT_ATE_NEXT=1
      else
        SHORT_KIND="unknown"
        return 0
      fi
      case "$c" in
      b) SHORT_KIND="body" ;;
      F) SHORT_KIND="file" ;;
      R) SHORT_KIND="repo" ;;
      *) SHORT_KIND="other" ;;
      esac
      return 0
      ;;
    d | e | f | w) ;;
    *)
      SHORT_KIND="unknown"
      return 0
      ;;
    esac
  done
  return 0
}

# Classify ONE wrapper option word, so the loop knows what the flag does rather
# than blindly stepping over it. Three classifications matter:
#   chdir — `env -C DIR`, `sudo -D DIR`, `sudo -R DIR` move the working
#           directory or the root, so the call resolves elsewhere: the same
#           out-of-scope verdict a `cd` segment gets, not a value to skip.
#   split — `env -S 'gh …'` carries a whole command line in one operand.
#   value — an ordinary option value, which must be consumed WITH its flag or it
#           is left sitting where the command name is expected.
# A short word is a cluster, not a single flag (`sudo -Eu root` is valid), so its
# letters are walked and the first one that matters decides — mirroring how gh's
# own shorthand is read. Sets WRAP_KIND, WRAP_VAL, WRAP_ATE_NEXT.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
parse_wrapper_flag() {
  local wrapper="$1" word="$2" next="$3" have_next="$4"
  local rest c
  WRAP_KIND="none"
  WRAP_VAL=""
  WRAP_ATE_NEXT=0

  case "$word" in
  --*)
    case "$wrapper:${word%%=*}" in
    env:--chdir | sudo:--chdir | sudo:--chroot | sudo:--login)
      WRAP_KIND="chdir"
      return 0
      ;;
    env:--split-string) WRAP_KIND="split" ;;
    env:--unset | sudo:--user | sudo:--group | sudo:--host | sudo:--prompt | \
      sudo:--close-from | sudo:--command-timeout | sudo:--other-user | \
      sudo:--role | sudo:--type)
      WRAP_KIND="value"
      ;;
    env:--help | env:--version | sudo:--help | sudo:--version)
      WRAP_KIND="terminal"
      return 0
      ;;
    # Positively known booleans; the loop steps over these. env's list is
    # transcribed from `env --help` on a GNU coreutils host. Its three signal
    # options take an OPTIONAL argument, which GNU only accepts attached after
    # `=`, so they never consume the following word and belong here.
    env:--ignore-environment | env:--null | env:--debug | env:--list-signal-handling | \
      env:--block-signal | env:--default-signal | env:--ignore-signal | \
      sudo:--askpass | sudo:--background | sudo:--bell | sudo:--preserve-env | \
      sudo:--set-home | sudo:--remove-timestamp | sudo:--reset-timestamp | \
      sudo:--non-interactive | sudo:--preserve-groups | sudo:--stdin | \
      sudo:--shell | sudo:--validate)
      return 0
      ;;
    *)
      WRAP_KIND="unknown"
      return 0
      ;;
    esac
    case "$word" in
    *=*) WRAP_VAL="${word#*=}" ;;
    *)
      if ((have_next)); then
        WRAP_VAL="$next"
        WRAP_ATE_NEXT=1
      else
        WRAP_KIND="none"
      fi
      ;;
    esac
    return 0
    ;;
  *) ;;
  esac

  rest="${word#-}"
  while [[ -n "$rest" ]]; do
    c="${rest:0:1}"
    rest="${rest:1}"
    case "$wrapper:$c" in
    # `sudo -i` is login mode: it runs the command from the target user's home,
    # so it relocates the call exactly as an explicit `-D` does. `-s` (shell
    # mode) does NOT — it keeps the current directory — and stays a boolean.
    env:C | sudo:D | sudo:R | sudo:i)
      WRAP_KIND="chdir"
      return 0
      ;;
    env:S) WRAP_KIND="split" ;;
    env:u | sudo:u | sudo:g | sudo:h | sudo:p | sudo:C | sudo:T | sudo:U | sudo:r | sudo:t)
      WRAP_KIND="value"
      ;;
    sudo:V)
      WRAP_KIND="terminal"
      return 0
      ;;
    # A letter this hook positively knows to be boolean: the cluster continues
    # past it. Anything else is unrecognized, and the caller bails rather than
    # assume — see WRAP_KIND=unknown handling.
    # `command -p` uses the default PATH and still EXECUTES the command, so it is
    # a pass-through. `-v`/`-V` are deliberately absent: they make `command`
    # print a pathname instead of running anything, so no PR is created and
    # gating one would be a false block — they fall through to `unknown`, which
    # allows.
    command:p | \
      env:i | env:0 | env:v | sudo:A | sudo:B | sudo:b | sudo:E | sudo:H | sudo:K | \
      sudo:k | sudo:n | sudo:P | sudo:S | sudo:s | sudo:v)
      continue
      ;;
    *)
      WRAP_KIND="unknown"
      return 0
      ;;
    esac
    if [[ -n "$rest" ]]; then
      WRAP_VAL="$rest"
    elif ((have_next)); then
      WRAP_VAL="$next"
      WRAP_ATE_NEXT=1
    else
      WRAP_KIND="none"
    fi
    return 0
  done
  return 0
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=("$@")
  local n=$# i=0 d k word next have_next bin wrapper split_from reparse qword
  local body_flag="" body_val="" body=""

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  while ((i < n)) && [[ "${w[i]}" == *=* && "${w[i]}" != -* ]]; do ((i++)); done

  # Only the CURRENT shell can relocate later segments. `command`, `builtin`, and
  # `eval` dispatch a builtin INSIDE this shell, so `command cd /x` really does
  # move it; `sudo cd /x` and `env cd /x` are separate processes that FAIL,
  # because `cd` is a builtin and not an executable, so those must poison
  # nothing — which is why this test precedes wrapper removal and why neither
  # appears here. A wrapped `cd` falls through to the wrapper loop below, where
  # `cd` is simply not `gh`.
  # Only `-p` is stepped over here: it preserves execution. `command -v cd`
  # PRINTS a description instead of running the builtin, so nothing moves, and
  # skipping every flag shape would read that lookup as a relocation.
  d=$i
  while ((d < n)); do
    case "${w[d]}" in
    command | builtin | eval | -p) ((d++)) ;;
    *) break ;;
    esac
  done
  case "${w[d]:-}" in
  cd | pushd | popd)
    DIR_CHANGED=1
    return 0
    ;;
  *) ;;
  esac
  ((DIR_CHANGED)) && return 0

  while ((i < n)); do
    word="${w[i]}"
    if [[ "$word" == *=* && "$word" != -* ]]; then
      ((i++))
      continue
    fi
    case "${word##*/}" in
    env | command | sudo)
      wrapper="${word##*/}"
      ((i++))
      while ((i < n)); do
        case "${w[i]}" in
        --)
          ((i++))
          break
          ;;
        -*)
          parse_wrapper_flag "$wrapper" "${w[i]}" "${w[i + 1]:-}" "$((i + 1 < n))"
          case "$WRAP_KIND" in
          chdir | terminal) return 0 ;;
          split)
            # env appends its remaining operands to the split string, so
            # `env -S 'gh pr create' --body BAD` runs the two spliced together.
            # Re-parsing the operand alone would see a command with no body.
            split_from=$((i + 1))
            ((WRAP_ATE_NEXT)) && split_from=$((i + 2))
            reparse="$WRAP_VAL"
            for ((k = split_from; k < n; k++)); do
              printf -v qword '%q' "${w[k]}"
              reparse+=" $qword"
            done
            hook::bash_parse_segments "$reparse" check_segment
            return 0
            ;;
          value) ((WRAP_ATE_NEXT)) && ((i++)) ;;
          unknown) return 0 ;;
          *) ;;
          esac
          ((i++))
          ;;
        *=*) ((i++)) ;;
        *) break ;;
        esac
      done
      continue
      ;;
    *) break ;;
    esac
  done

  bin="${w[i]:-}"
  bin="${bin//\\//}"
  bin="${bin##*/}"
  bin="${bin,,}"
  bin="${bin%.exe}"
  [[ "$bin" == "gh" && "${w[i + 1]:-}" == "pr" ]] || return 0
  case "${w[i + 2]:-}" in
  create | new | edit) ;;
  *) return 0 ;;
  esac

  for ((i = i + 3; i < n; i++)); do
    word="${w[i]}"
    next=""
    have_next=0
    ((i + 1 < n)) && {
      next="${w[i + 1]}"
      have_next=1
    }
    case "$word" in
    --) break ;;
    --repo | --repo=*) return 0 ;;
    # A body flag with no following word is a malformed command gh rejects on
    # its own; there is no body to judge. An explicitly EMPTY value is a
    # different case — the word is present, and gh would open a PR with a blank
    # body — so it stays judged.
    --body)
      ((have_next)) || return 0
      body_flag="body"
      body_val="$next"
      ((i++))
      ;;
    --body=*)
      body_flag="body"
      body_val="${word#--body=}"
      ;;
    --body-file)
      ((have_next)) || return 0
      body_flag="file"
      body_val="$next"
      ((i++))
      ;;
    --body-file=*)
      body_flag="file"
      body_val="${word#--body-file=}"
      ;;
    --*)
      # shellcheck disable=SC2310  # takes_value is a pure classifier; a false return is the "no value" case
      if takes_value "$word"; then ((i++)); fi
      ;;
    -?*)
      parse_short_cluster "$word" "$next" "$have_next"
      case "$SHORT_KIND" in
      repo) return 0 ;;
      body | file)
        body_flag="$SHORT_KIND"
        body_val="$SHORT_VAL"
        ;;
      *) ;;
      esac
      ((SHORT_ATE_NEXT)) && ((i++))
      ;;
    *) ;;
    esac
  done

  [[ -n "$body_flag" ]] || return 0

  if [[ "$body_flag" == "file" ]]; then
    if [[ "$body_val" == "-" ]]; then
      sole_heredoc_body_to body "$COMMAND" || return 0
      FORM="stdin-heredoc"
    else
      local path="$body_val"
      [[ "$path" == /* || "$path" =~ ^[A-Za-z]:[\\/] ]] || path="${HOOK_CWD:-$REPO_ROOT}/$path"
      [[ -r "$path" && -f "$path" ]] || return 0
      # `$(<file)`, not `cat`: bash reads the file itself, with no fork or exec.
      body=$(<"$path") || return 0
      FORM="body-file"
    fi
  else
    # shellcheck disable=SC2310  # is_dynamic is a pure predicate; both branches are handled
    if is_dynamic "$body_val"; then
      sole_heredoc_body_to body "$body_val" || return 0
      FORM="body-substitution"
    else
      body="$body_val"
      FORM="body-literal"
    fi
  fi

  validate_body "$body"
  return 0
}

hook::bash_parse_segments "$COMMAND" check_segment

emit_tel "ok"
exit 0
