#!/usr/bin/env bash
# PreToolUse hook, the merge guard: refuse a pull-request merge the PR's own
# state does not allow (#6463, https://github.com/melodic-software/claude-code-plugins/issues/18822).
#
# WHY. An agent marked a PR ready, which made a bot reviewer post a thread,
# then merged without reading it, and when the merge came back blocked it
# asked the operator for `--admin`. Instructions did not stop that; a guard in
# a plugin that ships everywhere does.
#
# OWNERSHIP. What makes a PR ready is decided once, in merge-readiness.sh
# (lib/merge-readiness.sh, copied here and into the source-control
# pull-request skill): hold labels, unresolved review threads, changes-requested
# reviews, failed and pending checks, the workflow-file exemption and the
# pr-verify verdict with its 30-minute no-verdict wait. Its header lists each.
# This guard finds the merge in a command, resolves its target, and turns the
# verdict into a refusal that points at `/source-control:pull-request merge`.
# The skill owns judgment and process; GitHub rulesets are the server-side
# backstop (https://github.com/melodic-software/claude-code-plugins/issues/18822).
#
# MATCHED MERGE PATHS (each at a command position, never inside a quoted
# argument; hook-precision rule 2):
#   gh CLI      `gh pr merge` with any flags (`--auto`, `--admin`, `--merge`,
#               `--squash`, `--rebase`). `--disable-auto` is not a merge and
#               passes.
#   REST        `gh api` or `curl` with method PUT on
#               `repos/{owner}/{repo}/pulls/{n}/merge`, and on the Claude Code
#               cloud auto-merge route `repos/{owner}/{repo}/pulls/{n}/ccr/auto_merge`.
#   GraphQL     `gh api graphql` or `curl .../graphql` whose arguments name the
#               `mergePullRequest`, `enablePullRequestAutoMerge` or
#               `enqueuePullRequest` mutation. The PR is read from a `PR_...`
#               node id in the arguments.
#   MCP         any server's `merge_pull_request` or `enable_pr_auto_merge`
#               tool (the GitHub MCP server's names), from its owner, repo and
#               pullNumber inputs. hooks.json registers that row.
#
# `--admin` is held to the same rule: a bypass flag does not exempt a merge
# from unread feedback. A pending check blocks an immediate merge only: an
# auto-merge or merge-queue request (`--auto`, `enablePullRequestAutoMerge`,
# `enqueuePullRequest`, `enable_pr_auto_merge`, the cloud auto-merge route)
# waits for checks by design.
# FAILS OPEN, VISIBLY. When gh is missing or unauthenticated, a read fails, or
# the time budget runs out, the merge runs and both the user and the model are
# told it will run unchecked. This guard sees every merge on every machine, a
# person's own included, so a GitHub outage or a missing login must not wedge
# them; the org ruleset that requires conversation resolution is the
# server-side backstop. The skill reads the same verdict and holds instead,
# since it decides to merge on that evidence alone (https://github.com/melodic-software/claude-code-plugins/issues/18822).
# AN UNRESOLVABLE TARGET FAILS CLOSED (#8598): a `gh pr merge` or REST merge
# whose repo or PR number comes from a shell variable, `$(...)` or backticks,
# a `gh pr merge` with no selector whose current branch cannot be read or has
# no open PR, or one whose `-R` value is missing, is blocked with the literal
# form to use (`gh pr merge <number> -R owner/repo`); otherwise any `$R` or
# `$n` would skip the check. On the Bash tool, a command whose text is merge-
# shaped (`pr merge` or `pr -R x merge` after a word that is gh or cannot be
# read, a `pulls/.../merge` or `auto_merge` route, a merge mutation name; prose
# such as "Gated PR Merge" is not) and holds a backtick is blocked whatever the
# parse found: the
# tokenizer splits a backtick substitution off, so the target it reads need not
# be the one the shell runs (`5`echo 0`` reads #5, merges #50), and a merge
# written inside the backticks would be hidden. The pre-filter tracks no quotes
# itself (a comment or heredoc apostrophe would fool a quote tracker), so a
# backtick in a quoted --body is refused too; pass such a body with --body-file.
# Likewise a
# `pr merge` or REST merge route continued with a backslash-newline is blocked:
# bash joins a continuation except in a comment, a quoted heredoc or after an
# escaped backslash, so the command is never rewritten, and only the pre-filter
# reads a joined copy. Both tests read the command with the body of each quoted
# heredoc (`<<'EOF'`, `<<"EOF"`, `<<\EOF`, `<<-'EOF'`) cut out, as the shared
# parser bounds it: bash expands nothing there, so merge text in it is stdin
# for the program, as in `python3 - <<'EOF'` or `git commit -F - <<'MSG'`. A
# body stays in when the body may run as commands (a word of the command names
# a shell, `sudo`, `su`, `ssh` or `at`, or the command word is `eval`, `source`,
# `.`, a `.sh` script, or cannot be read); when it names a GraphQL merge
# mutation, which `gh api graphql -F query=@-` would send; when it holds a
# backslash-newline; when its delimiter is not a plain word or does not end it,
# since the parser then bounded it differently from bash; and, with every body
# after it, when a backtick, `$(`, `${`, `$[`, `((` or `[[` comes before it,
# since its opener may sit where bash reads no heredoc. An unquoted heredoc's
# body always stays in: bash runs its backticks. A command holding
# more than one merge is blocked as well, so each merge runs, and is checked,
# as its own command. ALSO FAILS CLOSED: a GraphQL merge,
# auto-merge or merge-queue mutation whose PR cannot be resolved (an id from a
# variable or `$(...)`, an unreadable node) is blocked, because a
# scripted mutation almost always takes its id that way. A literal `PR_...` id
# with gh missing or unauthenticated fails open with the notice (#7376, the
# owner's decision on #6463); a non-literal id is blocked whether or not gh is
# there. In a Claude Code
# cloud session GraphQL is refused (HTTP 403, not an auth failure) and no cloud
# route resolves a node id, so every GraphQL merge mutation is blocked there
# when gh answers, literal id or not; merge with
# `gh pr merge <number>` or the REST route, which the guard can check.
#
# TARGET RESOLUTION (#8657). The pre-filter also reads a copy with quotes and
# backslashes dropped, so `gh pr mer"ge" 5` is parsed. A `gh pr` subcommand or a
# `-X`/`--method` value from an expansion (`gh pr $VERB`, `-X "$M"` on a merge
# route) is blocked as unresolvable, since either may be the merge. A `gh pr
# merge` with no -R and no URL is blocked when the command also changes directory
# (`cd`, `pushd`, `popd`, PowerShell's `Set-Location`, `Push-Location`,
# `Pop-Location`, `sl`) or names GH_REPO or GH_HOST (quotes dropped, so
# `export GH_RE""PO=x` counts), because the repository it merges in is then not
# the session's. A repo written `HOST/OWNER/REPO` is read without the
# host, passing a host other than github.com as `--hostname`. A 404 on the PR or
# its branch lookup, for a repo the command wrote, is blocked rather than run
# unchecked; a repo taken from the working directory still fails open. The branch
# in the pulls `head=` query is percent-encoded.
#
# COMMAND POSITION. Leading assignments, a reserved word the tokenizer leaves
# at a segment head (`then`, `do`, `{`, `if`, ...), and the `command`, `time`,
# `exec` and `nohup` prefixes are stepped over; `gh pr -R o/r merge` is read
# with its repo. `gh pr merge --help` / `-h` and `--disable-auto` are not merges.
#
# KNOWN GAPS (stated, not chased): a merge from a script (Python, Node), a
# quoted heredoc body included, or the web UI; a merge command whose command word comes from expansion
# (`$GH pr merge`), `eval`, a wrapper such as
# `sudo`, `env`, `nice`, `timeout` or `xargs`, a child shell (`bash -c '...'`),
# a gh alias, brace expansion (`{gh,} pr merge`), a glob (`g? pr merge`) or
# `gh.cmd`; a GraphQL mutation read from a file (`--input`), whose name
# never appears in the command; past 100 reviews or check runs the rest are
# not read; past 2,000 review threads (https://github.com/melodic-software/claude-code-plugins/issues/18822) the merge runs unchecked; the backtick refusal keys on merge-shaped text, so
# an obfuscated spelling of `pr merge` itself (`pr mer"ge"`) with a backtick is
# parsed as usual (#8657); a merge verb built from pieces (`V=mer; gh pr ${V}ge`);
# a cancelled run `<name>` is cleared by a newer successful `<name> (...)` run
# of the same app in another check suite even when that run belongs to an unrelated
# workflow, which the check-runs payload cannot tell apart from a matrix leg;
# an ignored check (merge_guard_ignored_checks) is matched by app slug and
# name only, so every GitHub Actions job named `Merge` or `merge` is ignored by the
# default, not just the pr-merge lane's, because a check run does not name its
# workflow; the workflow exemption reads only the first 100 changed files and
# matches a required check by name alone, and an `action.yml` outside
# MG_WORKFLOW_PREFIXES (merge-readiness.sh) does not count as an action definition file, so in
# those cases a failed check blocks; a run does not list the actions it used,
# so for an action change the exemption confirms only that the check loaded a
# workflow of this repository from the base branch, not that the workflow used
# the changed action; it reads at most MG_EXEMPT_MAX_RUNS runs, and a failed
# check past them blocks; the rules read returns ruleset rules only
# (first 100), so a check that only classic branch protection requires counts
# as not required on a PR that changes a workflow or action file.
#
# THE CLOUD ROUTES. Basis: the HTTP 403 body GitHub GraphQL returns inside a
# Claude Code cloud session names `GET pulls/{n}/ccr/review_threads` (an array
# of {resolved, outdated, path, line, comment_ids}) and `PUT pulls/{n}/ccr/auto_merge`
# as the replacements. As of: 2026-10-11, gh 2.98.0. Recheck: that refusal
# text changes, or the review_threads route stops answering.
#
# COST. A command that names neither `merge` nor `enqueue` leaves after one
# string test. A merge command pays five calls in sequence (PR, reviews, check
# runs, statuses, threads; up to seven with a branch or node lookup and the
# thread fallback, one more per further 100 review threads (https://docs.github.com/graphql/guides/using-pagination-in-the-graphql-api), and one more per failed check run, three at most, to read
# its annotations, and when a check failed, one for the PR's changed files and,
# if a workflow or action file changed, one for the base branch's rules and one
# per Actions run behind a failed check the rules do not require, five at most), all
# inside one 35 s budget that keeps the row under its
# 60 s timeout (TIME BUDGET in merge-readiness.sh), about once per PR: measured
# 3.0 to 3.6 s end to end against live PRs in a Claude Code cloud session on
# 2026-10-11.
#
# Escape: the `merge_guard_enabled` userConfig option (true or
# false; any other value keeps the guard on and says so). userConfig resolves
# at plugin-enable time, so an inline env prefix on the command cannot change it.
# `merge_guard_ignored_checks` (comma list of `<app slug>:<check name>`,
# default `github-actions:Merge,github-actions:merge`, the pr-merge lane's own
# job under its display name, then as a head tested before the rename or a
# repository whose job has no display name shows it) names check runs the guard
# never judges; set it empty to judge every check. It is the only way a failed
# check stops blocking: no failure is judged informational.
# A saved value of the former `block_unresolved_pr_merge_enabled` key is not
# read, so a saved `false` there leaves this guard on (https://github.com/melodic-software/claude-code-plugins/issues/18822).
#
# BLOCKING: exits 2 with the list of what is unresolved.

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_MERGE_GUARD_ENABLED:-true}" == "false" ]] && exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
# Could-not-run posture: fail-open with a dual-channel "guard did not run"
# notice; 0 (allow) and 2 (block) pass through.
guard::abort_boundary merge-guard PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

_bupm_enabled="${CLAUDE_PLUGIN_OPTION_MERGE_GUARD_ENABLED:-true}"
start=${EPOCHREALTIME:-}

# This guard fails open on every input it cannot read.
hook::buffer_stdin_to INPUT || exit 0
[[ "$_bupm_enabled" == true ]] ||
  guard::bad_switch_notice merge_guard_enabled "$_bupm_enabled" "$INPUT"

hook::require jq PreToolUse guardrails "$INPUT"

hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || exit 0
COMMAND="${HOOK_JQ_FIELDS[0]}"
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
BUPM_CWD="${HOOK_JQ_FIELDS[2]}"

# What the command (or MCP call) asks for. Globals, set by the merge path
# found; a command with more than one is refused, so the last one wins.
BUPM_FORM=""  # gh-pr-merge | rest-merge | ccr-auto-merge | graphql | mcp | backtick
BUPM_AUTO=0   # 1: the request waits for checks (auto-merge or merge queue)
BUPM_REPO=""  # owner/repo, may hold gh's {owner}/{repo} placeholders
BUPM_NUM=""
BUPM_SEL=""   # gh pr merge selector: number, URL or branch; empty = current branch
BUPM_NODE=""  # GraphQL PullRequest node id
# Why the merge target is not a literal value; set means refuse.
BUPM_UNRESOLVED=""
BUPM_MERGES=0
BUPM_BT=0
BUPM_CONT=0
BUPM_CD=0     # 1: a segment changes directory (cd, pushd, popd, Set-Location)
BUPM_GHREPO=0 # 1: the command text names GH_REPO or GH_HOST
BUPM_HOST=""  # a host other than github.com that qualified the repo
BUPM_SHELL=0
BUPM_UNLABEL=0
BUPM_UNLABEL_VAR=0
BUPM_UNLABEL_IDS=""
BUPM_UNLABEL_GQL=0

# _bupm_literal <word>: true when the word holds no expansion the guard
# cannot evaluate (a parameter, `$(...)` or a backtick substitution).
# shellcheck disable=SC2329  # reached from the recorders below
_bupm_literal() { [[ "$1" != *'$'* && "$1" != *'`'* ]]; }

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  hook::json_str_object_to data tool "$TOOL_NAME" form "$2"
  hook::emit_telemetry "merge-guard" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

_bupm_mutation_re='(mergePullRequest|enablePullRequestAutoMerge|enqueuePullRequest)'

# shellcheck disable=SC2329  # reached from the recorders below
_bupm_unlabel_value() {
  if ! _bupm_literal "$1"; then
    BUPM_UNLABEL_VAR=1
  elif [[ ",${1,,}," =~ ,[[:space:]]*pr-verify-failed[[:space:]]*, ]]; then
    BUPM_UNLABEL=1
  fi
}

# shellcheck disable=SC2329
_bupm_label_edit() {
  local a
  while (($#)); do
    a="$1"
    shift
    case "$a" in
    --remove-label)
      _bupm_unlabel_value "${1-}"
      (($#)) && shift
      ;;
    --remove-label=*) _bupm_unlabel_value "${a#*=}" ;;
    *) ;;
    esac
  done
  return 1
}

# The five recorders below are reached from the hook::bash_parse_segments
# callback, which shellcheck cannot follow.

# _bupm_rest_path <path> <method>: record a REST merge or cloud auto-merge PUT.
# shellcheck disable=SC2329
_bupm_rest_path() {
  local p="$1" m="${2^^}" route_re='^repos/.+/pulls/[^/]+/(merge|ccr/auto_merge)$'
  p="${p#https://api.github.com}"
  p="${p#http://api.github.com}"
  p="${p#/}"
  p="${p%%\?*}"
  p="${p%/}"
  if [[ "$p" =~ ^repos/[^/]+/[^/]+/issues/[^/]+/labels/(.+)$ ]] && { [[ "$m" == DELETE ]] || ! _bupm_literal "$m"; }; then
    local label="${BASH_REMATCH[1]}"
    _bupm_literal "$label" && printf -v label '%b' "${label//%/\\x}"
    _bupm_unlabel_value "$label"
    return 1
  fi
  if [[ "$m" != PUT ]]; then
    # A method from a variable (`-X "$M"`) may be PUT: refuse a merge route
    # called that way, since the method cannot be read.
    _bupm_literal "$m" && return 1
    [[ "$p" =~ $route_re ]] || return 1
    BUPM_FORM="rest-merge"
    BUPM_UNRESOLVED="the method $2 is not literal"
    return 0
  fi
  if [[ "$p" =~ $route_re ]] && ! _bupm_literal "$p"; then
    BUPM_FORM="rest-merge"
    BUPM_UNRESOLVED="the route $p is not literal"
    return 0
  fi
  [[ "$p" =~ ^repos/([^/]+/[^/]+)/pulls/([0-9]+)/(merge|ccr/auto_merge)$ ]] || return 1
  BUPM_REPO="${BASH_REMATCH[1]}"
  BUPM_NUM="${BASH_REMATCH[2]}"
  if [[ "${BASH_REMATCH[3]}" == merge ]]; then
    BUPM_FORM="rest-merge"
  else
    BUPM_FORM="ccr-auto-merge"
    BUPM_AUTO=1
  fi
}

# _bupm_graphql <arg>...: record a merge mutation named anywhere in the args.
# shellcheck disable=SC2329
_bupm_graphql() {
  local a hit="" unlabel=0 ids=" " lid
  for a in "$@"; do
    [[ "$a" =~ $_bupm_mutation_re ]] && hit="${BASH_REMATCH[1]}"
    [[ "$a" == *removeLabelsFromLabelable* ]] && unlabel=1
  done
  if ((unlabel)); then
    for a in "$@"; do
      while [[ "$a" =~ (LA_[A-Za-z0-9_-]+) ]]; do
        lid="${BASH_REMATCH[1]}"
        [[ "$ids" == *" $lid "* ]] || ids+="$lid "
        a="${a#*"$lid"}"
      done
    done
    read -r BUPM_UNLABEL_IDS <<<"$ids"
    [[ -n "$BUPM_UNLABEL_IDS" ]] || BUPM_UNLABEL_GQL=1
  fi
  [[ -n "$hit" ]] || return 1
  BUPM_FORM=graphql
  [[ "$hit" == mergePullRequest ]] || BUPM_AUTO=1
  # The node id is the one bound to `pullRequestId`, never the first `PR_...`
  # anywhere in the command: a decoy in another field would point the check
  # at a different PR. A binding is a literal (`pullRequestId:"PR_x"`, JSON-
  # escaped too) or a GraphQL variable (`pullRequestId:$id`) whose literal
  # value is a `-f id=PR_x` argument or a JSON `"id":"PR_x"` entry; a value from
  # a shell variable or `$(...)` is not a literal. Every binding must resolve
  # to one and the same id, or BUPM_NODE stays empty and the mutation fails
  # closed below.
  # shellcheck disable=SC2016  # regexes, `$` is a literal character
  local bind_re='pullRequestId[[:space:]]*:[[:space:]]*(\\?"(PR_[A-Za-z0-9_-]+)|\$([A-Za-z_][A-Za-z0-9_]*))'
  local text rest id var val node="" vals
  printf -v text '%s\n' "$@"
  rest="$text"
  while [[ "$rest" =~ $bind_re ]]; do
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    id="${BASH_REMATCH[2]}"
    var="${BASH_REMATCH[3]}"
    if [[ -n "$var" ]]; then
      vals=""
      for a in "$@"; do
        [[ "$a" =~ ^${var}=(PR_[A-Za-z0-9_-]+)$ ]] && vals+="${BASH_REMATCH[1]} "
      done
      val="$text"
      while [[ "$val" =~ \\?\"${var}\\?\"[[:space:]]*:[[:space:]]*\\?\"(PR_[A-Za-z0-9_-]+) ]]; do
        vals+="${BASH_REMATCH[1]} "
        val="${val#*"${BASH_REMATCH[0]}"}"
      done
      read -r id _ <<<"$vals"
      [[ -n "$id" ]] || return 0
      for val in $vals; do [[ "$val" == "$id" ]] || return 0; done
    fi
    [[ -z "$node" || "$node" == "$id" ]] || return 0
    node="$id"
  done
  BUPM_NODE="$node"
}

# gh pr merge <args>
# shellcheck disable=SC2329
_bupm_gh_pr_merge() {
  local a sel="" repo="" auto=0 flags=1 why=""
  while (($#)); do
    a="$1"
    shift
    if ((flags)); then
      case "$a" in
      --) flags=0 && continue ;;
      # Not a merge: gh prints help, or switches auto-merge off.
      --disable-auto | --help | -h) return 1 ;;
      --auto) auto=1 && continue ;;
      -R | --repo)
        (($#)) || why="the -R value is missing"
        repo="${1-}" && shift && continue
        ;;
      --repo=*) repo="${a#--repo=}" && continue ;;
      -R?*) repo="${a#-R}" && continue ;;
      -A | --author-email | -b | --body | -F | --body-file | --match-head-commit | -t | --subject)
        shift
        continue
        ;;
      -*) continue ;;
      *) ;;
      esac
    fi
    [[ -z "$sel" ]] && sel="$a"
  done
  BUPM_FORM=gh-pr-merge
  BUPM_AUTO=$auto
  BUPM_REPO="$repo"
  BUPM_SEL="$sel"
  _bupm_literal "$repo" || why="the repository $repo is not literal"
  _bupm_literal "$sel" || why="the pull request $sel is not literal"
  BUPM_UNRESOLVED="$why"
}

# gh api <args>
# shellcheck disable=SC2329
_bupm_gh_api() {
  local -a all=("$@")
  local a method="" endpoint=""
  while (($#)); do
    a="$1"
    shift
    case "$a" in
    -X | --method) method="${1-}" && shift && continue ;;
    --method=*) method="${a#--method=}" && continue ;;
    -X?*) method="${a#-X}" && continue ;;
    -f | --raw-field | -F | --field | -H | --header | --input | -q | --jq | -t | --template | --hostname | --cache | -p | --preview)
      shift
      continue
      ;;
    -*) continue ;;
    *) ;;
    esac
    [[ -z "$endpoint" ]] && endpoint="$a"
  done
  if [[ "$endpoint" == graphql || "$endpoint" == /graphql ]]; then
    _bupm_graphql "${all[@]}"
    return
  fi
  _bupm_rest_path "$endpoint" "$method"
}

# curl <args>
# shellcheck disable=SC2329
_bupm_curl() {
  local -a all=("$@")
  local a method="" url="" upload=0
  while (($#)); do
    a="$1"
    shift
    case "$a" in
    -X | --request) method="${1-}" && shift && continue ;;
    --request=*) method="${a#--request=}" && continue ;;
    -X?*) method="${a#-X}" && continue ;;
    # An upload is a PUT over HTTP(S) unless -X names another method.
    -T | --upload-file) upload=1 && shift && continue ;;
    --upload-file=* | -T?*) upload=1 && continue ;;
    *) ;;
    esac
    [[ "$a" == *api.github.com/* && -z "$url" ]] && url="$a"
  done
  [[ -z "$method" ]] && ((upload)) && method=PUT
  [[ -n "$url" ]] || return 1
  if [[ "${url%%\?*}" =~ api\.github\.com/graphql/?$ ]]; then
    _bupm_graphql "${all[@]}"
    return
  fi
  _bupm_rest_path "${url#*api.github.com}" "$method"
}

# _bupm_is_cd <argv>...: true when the segment changes directory, past the
# reserved words and prefixes _bupm_command also steps over.
# shellcheck disable=SC2329  # reached from _bupm_segment
_bupm_is_cd() {
  while (($#)); do
    case "$1" in
    '{' | '}' | '!' | then | do | else | elif | if | while | until | command | builtin | time | exec | nohup | -p | --) shift ;;
    *) break ;;
    esac
  done
  # PowerShell's cmdlets and their `sl` alias too, which it matches in any case.
  local w="${1-}"
  case "${w,,}" in cd | pushd | popd | chdir | set-location | push-location | pop-location | sl) return 0 ;; *) return 1 ;; esac
}

# hook::bash_parse_segments callback: one segment's argv words. Counts the
# merge paths found; a recorder returns 0 only when it recorded one.
# shellcheck disable=SC2329  # invoked through hook::bash_parse_segments
_bupm_segment() {
  # A directory change before a merge with no -R moves the repository gh reads
  # from the session's to another. Same prefixes stepped over as in _bupm_command.
  ((BUPM_MERGES == 0)) && _bupm_is_cd "$@" && BUPM_CD=1
  _bupm_runs_shell "$@" && BUPM_SHELL=1
  _bupm_command "$@" && ((++BUPM_MERGES))
  return 0
}

# _bupm_runs_shell <argv>...: true when the segment may run a heredoc body as
# commands: a word names a shell or a program that hands stdin to one (`bash`,
# `xargs -0 sh`, `sudo -s`, `ssh host`), or the command word, past the prefixes
# _bupm_command steps over, is `eval`, `source`, `.` or a `.sh` script, or
# cannot be read (an expansion or a glob).
# shellcheck disable=SC2329  # reached from _bupm_segment
_bupm_runs_shell() {
  local w lead=1
  for w in "$@"; do
    if ((lead)); then
      case "$w" in
      '{' | '}' | '!' | then | do | else | elif | if | while | until | command | builtin | time | exec | nohup | -p | --) continue ;;
      *) ;;
      esac
      [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && continue
      lead=0
      _bupm_literal "$w" || return 0
      [[ "$w" != '[' && "$w" != '[[' && "$w" == *[\*\?\[]* ]] && return 0
      case "${w,,}" in eval | source | . | *.sh) return 0 ;; *) ;; esac
    fi
    w="${w##*/}"
    w="${w##*\\}"
    w="${w,,}"
    case "${w%.exe}" in
    bash | sh | zsh | dash | ksh | mksh | ash | yash | csh | tcsh | fish | busybox | pwsh | powershell | sudo | doas | su | ssh | at | batch) return 0 ;;
    *) ;;
    esac
  done
  return 1
}

# shellcheck disable=SC2329  # reached from _bupm_segment
_bupm_command() {
  # Step over what stands before the command word: NAME=value assignments; a
  # reserved word the tokenizer leaves at the head of a segment (`then gh ...`,
  # `do gh ...`, `{ gh ...`), as block-root-delete-target.sh does; and the
  # prefixes that run the next word as the command (`command`, `time`,
  # `exec`, `nohup`) with their own flags.
  while (($#)); do
    case "$1" in
    '{' | '}' | '!' | then | do | else | elif | if | while | until | command | time | exec | nohup | -p | --) shift ;;
    *)
      [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || break
      shift
      ;;
    esac
  done
  (($#)) || return 1
  local cmd="${1##*/}"
  cmd="${cmd##*\\}"
  cmd="${cmd,,}"
  cmd="${cmd%.exe}"
  shift
  case "$cmd" in
  gh)
    if [[ "${1-}" == pr ]]; then
      # `gh pr -R o/r merge`: the repo flag may sit before the subcommand.
      local pre_repo=""
      shift
      while (($#)); do
        case "$1" in
        -R | --repo) pre_repo="${2-}" && shift 2 ;;
        --repo=*) pre_repo="${1#--repo=}" && shift ;;
        -R?*) pre_repo="${1#-R}" && shift ;;
        *) break ;;
        esac
      done
      # `VERB=merge; gh pr $VERB 5`: a subcommand from an expansion may be merge.
      if [[ "${1-}" == *[\$\`]* ]]; then
        BUPM_FORM=gh-pr-merge
        BUPM_UNRESOLVED="the gh pr subcommand $1 is not literal"
        return 0
      fi
      [[ "${1-}" == edit ]] && _bupm_label_edit "${@:2}"
      [[ "${1-}" == merge ]] || return 1
      shift
      _bupm_gh_pr_merge ${pre_repo:+-R "$pre_repo"} "$@"
    elif [[ "${1-}" == label && ("${2-}" == delete || "${2-}" == edit) ]]; then
      local w
      set -- "${@:3}"
      while (($#)); do
        w="$1"
        shift
        case "$w" in
        -R | --repo | -n | --name | -d | --description | -c | --color) (($#)) && shift ;;
        -*) ;;
        *)
          _bupm_unlabel_value "$w"
          break
          ;;
        esac
      done
      return 1
    elif [[ "${1-}" == issue ]]; then
      _bupm_label_edit "${@:2}"
    elif [[ "${1-}" == api ]]; then
      _bupm_gh_api "${@:2}"
    else
      return 1
    fi
    ;;
  curl) _bupm_curl "$@" ;;
  *) return 1 ;;
  esac
}

if [[ "$TOOL_NAME" =~ ^mcp__.+__(merge_pull_request|enable_pr_auto_merge)$ ]]; then
  BUPM_FORM=mcp
  [[ "${BASH_REMATCH[1]}" == enable_pr_auto_merge ]] && BUPM_AUTO=1
  hook::jq_fields "$INPUT" '.tool_input.owner' '.tool_input.repo' '.tool_input.pullNumber' || exit 0
  BUPM_REPO="${HOOK_JQ_FIELDS[0]}/${HOOK_JQ_FIELDS[1]}"
  BUPM_NUM="${HOOK_JQ_FIELDS[2]%.0}"
else
  [[ -n "$COMMAND" ]] || exit 0
  ((${#COMMAND} > 16384)) && exit 0
  # Cheap pre-filter: every matched path names `merge` or `enqueue`. It reads a
  # copy with every backslash-newline joined, so `mer\<newline>ge` still matches;
  # the command itself is never rewritten, because bash does not join inside a
  # comment, a quoted heredoc or after an escaped backslash.
  _bupm_lc="${COMMAND,,}"
  _bupm_joined="${_bupm_lc//$'\\\n'/}"
  # A second copy with quotes and backslashes dropped, as the tokenizer drops
  # them, reads `mer"ge"` and `en\queue` as the words they spell.
  _bupm_bare="${_bupm_joined//[\"\'\\]/}"
  _bupm_pre_re='merge|enqueue|pr-verify-failed|removelabelsfromlabelable|labels/[^[:space:]]*%'
  [[ "$_bupm_joined" =~ $_bupm_pre_re || "$_bupm_bare" =~ $_bupm_pre_re ]] || exit 0
  # The bare copy too: `export GH_RE""PO=x` sets GH_REPO.
  [[ "$_bupm_lc" == *gh_repo* || "$_bupm_bare" == *gh_repo* ||
    "$_bupm_lc" == *gh_host* || "$_bupm_bare" == *gh_host* ]] && BUPM_GHREPO=1
  # A backtick or a line continuation in merge-shaped text is refused below
  # whatever the parse found; in PowerShell a backtick is the escape character,
  # not a substitution, and a backslash is not a continuation.
  # shellcheck disable=SC2016  # the backticks are literal regex text
  _bupm_rest_re='pulls/([^/[:space:]`]|`[^`]*`)+/(ccr/auto_)?merge'
  _bupm_pr_re='(^|[^a-z0-9_-])pr[[:space:]]+((-r|--repo)[=[:space:]]*[^[:space:]]+[[:space:]]+)*merge'
  _bupm_cli_re="$_bupm_pr_re|$_bupm_rest_re"
  _bupm_gql_re='mergepullrequest|enqueuepullrequest|enablepullrequestautomerge'
  # _bupm_gh_pr_shaped: true when a `pr ... merge` in the joined text may run as
  # `gh pr merge`. The word before `pr` decides: gh once quotes and backslashes
  # are dropped (`g""h`, `/usr/bin/gh`, `gh.exe`), or a `$` or backtick in it,
  # so the command word cannot be read (`$GH`, `gh${IFS}pr`). Prose such as
  # "Gated PR Merge" is not (#8657).
  _bupm_gh_pr_shaped() {
    local text="$_bupm_joined" seen="" m lead before word w1 w2 w3 t i toks
    local redir_re='^[0-9]*&?[<>]+&?[^[:space:]]+$' redir_op_re='^[0-9]*&?[<>]+&?$'
    while [[ "$text" =~ $_bupm_pr_re ]]; do
      m="${BASH_REMATCH[0]}"
      lead="${BASH_REMATCH[1]}"
      before="${text%%"$m"*}"
      text="${text#*"$m"}"
      [[ -n "$lead" ]] || {
        seen+="$m"
        continue
      }
      word="$seen$before"
      seen+="$before$m"
      [[ "$lead" =~ [[:space:]] ]] || word+="$lead"
      toks=()
      read -rd '' -a toks <<<"$word"
      i=$((${#toks[@]} - 1))
      ((i >= 0)) && [[ "${toks[i]}" == *[\$\`]* ]] && return 0
      # `pr` glued to an operator is its own command word, never gh's.
      [[ "$lead" == [';|&(){}<>!'] ]] && continue
      # A lone opening quote: `pr ...` is a quoted argument of the word before.
      ((i >= 0)) && [[ "${toks[i]}" == [\"\'] ]] && continue
      # Step back over what bash drops before argv: empty quotes and a bare
      # backslash (`''pr`, `\pr`) and redirections (`2>&1`, `> /dev/null`).
      while ((i >= 0)); do
        t="${toks[i]}"
        [[ "$t" == *[\$\`]* ]] && return 0
        if [[ "$t" =~ ^[\"\'\\]+$ || "$t" =~ $redir_re ]]; then
          ((i -= 1))
        elif ((i > 0)) && [[ "${toks[i - 1]}" =~ $redir_op_re ]]; then
          ((i -= 2))
        else
          break
        fi
      done
      ((i >= 0)) || continue
      word="${toks[i]}"
      w1="${word//[\"\']/}"
      w1="${w1##*[/;|&()\{\}<>=!]}"
      w1="${w1##*\\}"
      w2="${word//[\"\'\\]/}"
      w2="${w2##*[/;|&()\{\}<>=!]}"
      # A redirect glued to the word ends it: `gh</dev/null` runs gh.
      w3="${word//[\"\'\\]/}"
      w3="${w3%%[<>]*}"
      w3="${w3##*[/;|&()\{\}=!]}"
      [[ "${w1%.exe}" == gh || "${w2%.exe}" == gh || "${w3%.exe}" == gh ]] && return 0
    done
    return 1
  }
  # _bupm_strip_bodies: set _bupm_text to the command with each quoted heredoc
  # body cut out (header, the backtick refusal), from the byte offsets the parse
  # left in HOOK_HEREDOC_BODIES, so it runs under C.
  # shellcheck disable=SC2329  # invoked through hook::_c_locale
  _bupm_strip_bodies() {
    local e s t q c d pre body at=0 out=""
    _bupm_text="$COMMAND"
    ((BUPM_SHELL)) && return 0
    for e in ${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"}; do
      s="${e%% *}"
      e="${e#* }"
      t="${e%% *}"
      e="${e#* }"
      q="${e%% *}"
      e="${e#* }"
      c="${e%% *}"
      d="${e#* }"
      pre="${COMMAND:at:s-at}"
      # An opener after one of these may sit where bash reads no heredoc
      # (`${x:-<<'E' }`, `((1 <<'E' ))`), which the parser does not model.
      # shellcheck disable=SC2016  # literal shell syntax
      [[ "$out$pre" == *'`'* || "$out$pre" == *'$('* || "$out$pre" == *'${'* ||
        "$out$pre" == *'$['* || "$out$pre" == *'(('* || "$out$pre" == *'[['* ]] && break
      body="${COMMAND:s:t-s}"
      out+="$pre"
      at=$t
      # The body is cut only when its delimiter line closed it and that
      # delimiter is a plain word, so the parser bounded it as bash does.
      [[ "$q" == 1 && "$c" == 1 && "$d" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ &&
        "$body" != *$'\\\n'* && ! "${body,,}" =~ $_bupm_gql_re ]] && continue
      out+="$body"
    done
    _bupm_text="$out${COMMAND:at}"
  }
  # PowerShell's escape character is the backtick, which Bash would read as an
  # unclosed substitution and the reader refuses. PowerShell passes the escaped
  # character on, so the PowerShell text is parsed with every backtick dropped,
  # and with the `&` call operator and empty `;` statements that open a
  # PowerShell statement and no bash one dropped as the git guards' reduction
  # drops them (ps::_bash_ready_to).
  if [[ "$TOOL_NAME" == PowerShell ]]; then
    declare -F guard::require_libs >/dev/null || source "$_HOOK_SELF/guard-requires.sh"
    guard::require_libs
    _bupm_ps=""
    ps::_bash_ready_to _bupm_ps "${COMMAND//\`/}"
    hook::bash_parse_segments "$_bupm_ps" _bupm_segment
  else
    hook::bash_parse_segments "$COMMAND" _bupm_segment
  fi
  _bupm_text="$COMMAND"
  hook::_c_locale _bupm_strip_bodies
  _bupm_joined="${_bupm_text,,}"
  _bupm_joined="${_bupm_joined//$'\\\n'/}"
  if [[ "$TOOL_NAME" != PowerShell && "$_bupm_text" == *'`'* ]] &&
    { [[ "$_bupm_joined" =~ $_bupm_rest_re|$_bupm_gql_re ]] || _bupm_gh_pr_shaped; }; then
    BUPM_BT=1
    BUPM_FORM=backtick
  elif [[ "$TOOL_NAME" != PowerShell && "$_bupm_text" == *$'\\\n'* && "$_bupm_joined" =~ $_bupm_cli_re ]]; then
    BUPM_CONT=1
    BUPM_FORM=continuation
  else
    [[ -n "$BUPM_FORM$BUPM_UNLABEL_IDS" ]] || ((BUPM_UNLABEL || BUPM_UNLABEL_VAR || BUPM_UNLABEL_GQL)) || exit 0
  fi
fi

# shellcheck source=merge-readiness.sh
source "$_HOOK_SELF/merge-readiness.sh" || exit 70

BUPM_OUT=""
BUPM_ERR=""
_bupm_api() {
  local rc=0
  MG_CWD="$BUPM_CWD" MG_HOST="$BUPM_HOST"
  _mg_api "$@" || rc=$?
  BUPM_OUT="$MG_OUT" BUPM_ERR="$MG_ERR"
  return "$rc"
}
_bupm_urlencode() { _mg_urlencode "$@"; }

# _bupm_unchecked <reason>: fail open, telling both channels.
_bupm_unchecked() {
  local what="this pull request"
  [[ -n "$BUPM_NUM" ]] && what="${BUPM_REPO}#${BUPM_NUM}"
  local subject="${2:-unresolved review threads, change requests or failing checks}" read="the PR's review threads and checks"
  [[ -n "${2-}" ]] && read="$2"
  local msg="guardrails merge-guard: could not check $what for $subject ($1), so this merge will run unchecked. Read $read yourself before relying on it."
  hook::emit_channels PreToolUse "$msg" "$msg"
  emit_tel "unchecked" "$BUPM_FORM"
  exit 0
}

# _bupm_block <telemetry form> [line]...: print each line and the turn-off note
# to stderr, record the block, and exit 2.
_bupm_block() {
  local form="$1"
  shift
  printf '%s\n' "$@" 'Only the user can turn this guard off (merge_guard_enabled).' >&2
  emit_tel "blocked" "$form"
  exit 2
}

# _bupm_refuse <reason>: fail closed, for a GraphQL merge mutation whose PR
# cannot be resolved.
_bupm_refuse() {
  _bupm_block graphql-unresolvable \
    "BLOCKED: this GraphQL merge mutation could not be checked for unresolved review threads, change requests or failing checks ($1)." \
    'Fix: pass the pull request id as a literal (-f id=PR_...), or merge with gh pr merge <number>, so the PR can be checked.'
}

# _bupm_refuse_target <reason>: fail closed, for a gh pr merge or REST merge
# whose repo or PR number is not a literal value.
_bupm_refuse_target() {
  # shellcheck disable=SC2016  # $(...) is literal text in the message
  _bupm_block "$BUPM_FORM-unresolvable" \
    "BLOCKED: guardrails could not tell which pull request this merge targets ($1), so it could not check it for unresolved review threads, change requests or failing checks." \
    'Fix: write the repository and PR number literally: gh pr merge <number> -R owner/repo (or PUT repos/owner/repo/pulls/<number>/merge). A shell variable, $(...) or backticks hide the target; in a loop, write each merge as its own literal command.'
}
if [[ -n "$BUPM_UNLABEL_IDS" ]]; then
  _bupm_ids=()
  for _bupm_id in $BUPM_UNLABEL_IDS; do _bupm_ids+=(-f "ids[]=$_bupm_id"); done
  # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
  if command -v gh >/dev/null 2>&1 &&
    _bupm_api graphql -f query='query($ids:[ID!]!){nodes(ids:$ids){... on Label{name}}}' "${_bupm_ids[@]}" \
      --jq '[.data.nodes[]? | .name? // empty | ascii_downcase] | index("pr-verify-failed") != null'; then
    [[ "$BUPM_OUT" == true ]] && BUPM_UNLABEL=1
  else
    _bupm_msg="guardrails merge-guard: could not read which labels this removeLabelsFromLabelable removes (${BUPM_ERR:-gh is not on PATH}), so it runs unchecked. Never remove pr-verify-failed: only a PASS verdict at a newer head clears it."
    hook::emit_channels PreToolUse "$_bupm_msg" "$_bupm_msg"
  fi
fi
((BUPM_UNLABEL_GQL)) &&
  _bupm_block pr-verify-label-removal-unresolvable \
    'BLOCKED: this removeLabelsFromLabelable names no literal LA_ label id, so guardrails cannot tell whether it removes the pr-verify-failed label.' \
    'Fix: pass each label id as a literal LA_... id, or use gh pr edit <number> --remove-label <name>.'
if ((BUPM_UNLABEL)) || { ((BUPM_UNLABEL_VAR)) && [[ "${_bupm_bare-}" == *pr-verify-failed* ]]; }; then
  _bupm_block pr-verify-label-removal \
    'BLOCKED: this command removes the pr-verify-failed label, which is pr-verify'"'"'s FAIL hold on the pull request.' \
    'Only a PASS verdict at a newer head clears it, and pr-verify'"'"'s own workflow removes it then. Fix what the FAIL comment names, push, and let pr-verify judge the new head.'
fi
[[ -n "$BUPM_FORM" ]] || exit 0

((BUPM_BT)) &&
  _bupm_refuse_target "the command holds a backtick, and a backtick substitution can change or hide the target; remove every backtick, and pass a body that holds one with --body-file"
((BUPM_CONT)) &&
  _bupm_refuse_target "the command continues a line with a backslash, which can join or split the merge differently from how the guard reads it; write the merge on one line"
((BUPM_MERGES > 1)) &&
  _bupm_refuse_target "this command holds $BUPM_MERGES merges and only one can be checked; run each merge as its own command"
[[ -z "$BUPM_UNRESOLVED" ]] || _bupm_refuse_target "$BUPM_UNRESOLVED"
# A merge with no -R and no URL reads its repository from the working directory
# and the environment, which `cd other &&` and `GH_REPO=x/y` change: the PR the
# guard would check is then the session repo's, not the one gh merges.
if [[ "$BUPM_FORM" == gh-pr-merge && -z "$BUPM_REPO" && ! "$BUPM_SEL" =~ ^https?:// ]]; then
  ((BUPM_CD)) &&
    _bupm_refuse_target "the command changes directory before the merge and names no -R repository, so the merge may not run in the session's repository"
  ((BUPM_GHREPO)) &&
    _bupm_refuse_target "the command names GH_REPO or GH_HOST and no -R repository, so the merge may not run in the session's repository"
fi

# A GraphQL mutation must name its PR by a literal node id the guard can
# resolve; see the fail-closed note below.
if [[ "$BUPM_FORM" == graphql ]]; then
  [[ -n "$BUPM_NODE" ]] || _bupm_refuse "the mutation's pull request id is not a literal PR_ node id in the command"
fi
command -v gh >/dev/null 2>&1 || _bupm_unchecked "gh is not on PATH"

[[ -n "$BUPM_REPO" ]] || BUPM_REPO="{owner}/{repo}"

# gh takes -R as [HOST/]OWNER/REPO; the REST path takes OWNER/REPO. A host other
# than github.com goes to gh api as --hostname.
if [[ "$BUPM_REPO" =~ ^([^/]+)/([^/]+/[^/]+)$ ]]; then
  BUPM_REPO="${BASH_REMATCH[2]}"
  [[ "${BASH_REMATCH[1],,}" == github.com ]] || BUPM_HOST="${BASH_REMATCH[1]}"
fi

# _bupm_pr_unreadable: a read of the PR or its branch lookup failed. A 404 on a
# repository the command wrote literally means the guard is not looking where gh
# will merge, which is refused; any other failure fails open.
_bupm_pr_unreadable() {
  if [[ "$BUPM_ERR" == *"HTTP 404"* && "$BUPM_REPO" != *'{'* ]]; then
    _bupm_refuse_target "GitHub answered HTTP 404 for ${BUPM_REPO}${BUPM_NUM:+#$BUPM_NUM}, so the guard cannot tell which pull request this merge targets"
  fi
  _bupm_unchecked "$BUPM_ERR"
}

# A GraphQL mutation names its PR by node id. Unlike every other path, one
# whose PR cannot be resolved FAILS CLOSED: the id usually arrives through a
# variable or a substitution (`-F id="$(jq -r .id <<<"$PR")"`), so failing
# open there would leave the commonest scripted shape unguarded.
if [[ "$BUPM_FORM" == graphql ]]; then
  # shellcheck disable=SC2016  # GraphQL variables, not shell expansions
  _bupm_api graphql -f query='query($id:ID!){node(id:$id){... on PullRequest{number repository{nameWithOwner}}}}' \
    -f id="$BUPM_NODE" --jq '.data.node | "\(.repository.nameWithOwner) \(.number)"' || {
    # A literal id with gh unauthenticated fails open like the other paths (#7376);
    # any other failed read of the node still fails closed. Only gh's own
    # not-logged-in phrasings match: a 403 that merely mentions authentication
    # (SSO, SAML, a proxy) is not a missing login.
    [[ "$BUPM_ERR" =~ (Bad\ credentials|HTTP\ 401|gh\ auth\ login|not\ logged\ in) ]] &&
      _bupm_unchecked "node $BUPM_NODE: $BUPM_ERR"
    _bupm_refuse "node $BUPM_NODE could not be read: $BUPM_ERR"
  }
  read -r BUPM_REPO BUPM_NUM <<<"$BUPM_OUT"
  [[ "$BUPM_NUM" =~ ^[0-9]+$ ]] || _bupm_refuse "node $BUPM_NODE is not a pull request"
fi

# gh pr merge: a number, a URL, a branch, or the current branch.
if [[ "$BUPM_FORM" == gh-pr-merge ]]; then
  _bupm_branch=""
  if [[ "$BUPM_SEL" =~ ^#?([0-9]+)$ ]]; then
    BUPM_NUM="${BASH_REMATCH[1]}"
  elif [[ "$BUPM_SEL" =~ ^https?://([^/]+)/([^/]+/[^/]+)/pull/([0-9]+) ]]; then
    BUPM_REPO="${BASH_REMATCH[2]}"
    BUPM_NUM="${BASH_REMATCH[3]}"
    BUPM_HOST=""
    [[ "${BASH_REMATCH[1],,}" == github.com ]] || BUPM_HOST="${BASH_REMATCH[1]}"
  elif [[ -n "$BUPM_SEL" ]]; then
    _bupm_branch="$BUPM_SEL"
  else
    _bupm_branch=$(hook::git_untrusted -C "${BUPM_CWD:-.}" branch --show-current 2>/dev/null) || _bupm_branch=""
    [[ -n "$_bupm_branch" ]] || _bupm_refuse_target "no PR was named and the current branch could not be read"
  fi
  if [[ -z "$BUPM_NUM" ]]; then
    # The branch is encoded: a name holding `&`, `#` or `%` would otherwise add a
    # query parameter or cut the query short and list a different PR.
    _bupm_urlencode _bupm_head "$_bupm_branch"
    [[ "$_bupm_branch" == *:* ]] || _bupm_head="${BUPM_REPO%%/*}:$_bupm_head"
    _bupm_api "repos/$BUPM_REPO/pulls?state=open&head=$_bupm_head" --jq '.[0].number // empty' ||
      _bupm_pr_unreadable
    BUPM_NUM="$BUPM_OUT"
    # A bare branch is looked up under the base repo's owner; a fork's branch needs owner:branch or the number.
    [[ "$BUPM_NUM" =~ ^[0-9]+$ ]] || _bupm_refuse_target "no open pull request found for branch $_bupm_head; for a fork's branch write <fork-owner>:<branch> or the PR number"
  fi
fi

[[ "$BUPM_NUM" =~ ^[0-9]+$ ]] || _bupm_unchecked "the pull request number could not be read"

_mg_unchecked() {
  BUPM_REPO="$MG_REPO"
  _bupm_unchecked "$@"
}
_mg_pr_unreadable() {
  BUPM_ERR="$MG_ERR"
  _bupm_pr_unreadable
}
_mg_refuse_merge() {
  local kind="$1"
  shift
  [[ "$kind" == closed ]] && exit 0
  [[ "$kind" == not-ready ]] && kind=""
  _bupm_block "$BUPM_FORM${kind:+-$kind}" "$@" \
    'Merge through /source-control:pull-request merge, which runs this same readiness check and waits for what is pending.'
}
_mg_allow() {
  if (($#)); then
    _bupm_msg="guardrails merge-guard: ${MG_REPO}#${MG_NUM} is allowed to merge. $*"
    hook::emit_channels PreToolUse "$_bupm_msg" "$_bupm_msg"
    emit_tel "warned" "$BUPM_FORM"
  else
    emit_tel "ok" "$BUPM_FORM"
  fi
  exit 0
}

MG_REPO="$BUPM_REPO" MG_NUM="$BUPM_NUM" MG_HOST="$BUPM_HOST" MG_CWD="$BUPM_CWD" MG_AUTO="$BUPM_AUTO" MG_HEAD=""
merge_readiness::check
