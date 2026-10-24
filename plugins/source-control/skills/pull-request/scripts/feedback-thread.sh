#!/usr/bin/env bash
# feedback-thread.sh: the review-thread tool of `comments --ci`
# (reference/comments-ci.md). The read runner stages a read-only copy behind a
# wrapper that fixes the environment below, and the skill's Bash may run only
# that wrapper. Every finding body is untrusted data: it is printed, never run.
# The tool posts nothing and commits nothing: it records each reply in the
# replies file, which the runner scans and uploads and a later job with no
# model validates and posts; the runner turns the working tree's changes into
# a patch that another job pushes.
#
#   list                              the kept threads, as JSON
#   check-paths <path>...             exit 0 when every path is in a kept
#                                     thread's scope (allowed below)
#   record <thread-id> <disposition>  check the disposition against the
#                                     template and append it to the replies
#
# The disposition file is JSON in the scratch directory:
#   {"disposition": "VALID" | "INCORRECT" | "UNCERTAIN" | "VALID-defer",
#    "evidence": ["path:line", ...], "fix_sha": "", "note": "<prose>"}
# fix_sha stays empty: the reply job names the commit the push job made.
#
# Environment:
#   FEEDBACK_THREADS    the runner's thread file (repository, pr, head_sha,
#                       threads[])
#   FEEDBACK_LOG        the replies file, one JSON object per line
#   FEEDBACK_SCRATCH    the only directory a disposition file may sit in
#   FEEDBACK_WORKSPACE  the checkout evidence paths and a VALID reply's
#                       uncommitted fix are checked in
#
# Exit: 0 done; 1 refused (nothing recorded); 2 usage or environment.
#
# allowed() is a predicate: set -e need not reach inside it.
# shellcheck disable=SC2310
set -euo pipefail

die() {
  printf 'feedback-thread: %s\n' "$2" >&2
  exit "$1"
}

threads_file=${FEEDBACK_THREADS:-} log_file=${FEEDBACK_LOG:-}
scratch_dir=${FEEDBACK_SCRATCH:-} workspace=${FEEDBACK_WORKSPACE:-}
[[ -n $threads_file && -n $log_file && -n $scratch_dir && -n $workspace ]] ||
  die 2 "FEEDBACK_THREADS, FEEDBACK_LOG, FEEDBACK_SCRATCH and FEEDBACK_WORKSPACE must be set"
[[ -f $threads_file ]] || die 2 "no thread file"

# Not under .github/workflows/ in any letter case, with no empty, . or .. segment, of
# plain ASCII segments, and in a kept thread's scope: its path, a file in the
# plugins/<p>/ directory it sits in that is no instruction path (.gitmodules,
# CODEOWNERS, a settings*.json, a package manifest or lockfile), no control
# surface (CLAUDE.md, AGENTS.md, .mcp.json, .lsp.json, .claude-plugin/, hooks/,
# monitors/, bin/) and no script or code file, a test file in its directory, or a path in its named_paths
# (the files a write-access fix request named) in that same plugins/<p>/
# directory that is no instruction path; or, when the gated head holds it as a
# regular file, a file in the thread file's pr_paths (the files the pull request already
# changes, which the select job already held to thread-scope.mjs's
# prPathsOf). The same rule as
# .github/scripts/pr-unblock/thread-scope.mjs, which the promote step and
# the reply job apply.
allowed() {
  local tracked=false mode
  # A regular or executable file at the gated head: no new file, symbolic link or gitlink.
  mode=$(git_tree ls-tree HEAD -- "$1" 2>/dev/null | cut -d' ' -f1) || mode=""
  [[ $mode == 100644 || $mode == 100755 ]] && tracked=true
  [[ ! ${1,,} =~ ^\.github/workflows(/|$) && ! $1 =~ (^|/)\.{0,2}(/|$) ]] &&
    jq -e --arg p "$1" --argjson tracked "$tracked" '
      def dir: sub("[^/]*$"; "");
      def plugin: first(capture("^(?<c>plugins/[^/]+/)").c) // null;
      ($p | test("^[A-Za-z0-9_@+.-]+(/[A-Za-z0-9_@+.-]+)*$")) as $plain
      | ($p | test("(^|/)(\\.gitmodules|codeowners|settings[^/]*\\.json|package(-lock)?\\.json|requirements[^/]*\\.txt)$"; "i")) as $instruction
      | ($p | test("^\\.github/|(^|/)(CLAUDE\\.md|AGENTS\\.md|\\.mcp\\.json|\\.lsp\\.json)$|(^|/)\\.claude(-plugin)?/|^plugins/[^/]+/(hooks|monitors|bin)/"; "i")) as $control
      | (if $instruction or $control or ($p | test("\\.(sh|bash|zsh|ps1|py|mjs|cjs|js|ts|mts|cts)$"; "i"))
         then null else $p | plugin end) as $plugin
      | ($p | sub("^.*/"; "") | test("^(test_[^/]*\\.py|[^/]*_test\\.py|[^/]*\\.(test|spec)\\.[^/]+)$")) as $test
      | (if $instruction then null else $p | plugin end) as $named
      | ($tracked and any(.pr_paths[]?; . == $p)) as $pr
      | $plain and ($pr or any(.threads[]; .path as $t
          | $t == $p
          or ($plugin != null and ($t | startswith($plugin)))
          or ($test and ($t | dir) == ($p | dir))
          or ($named != null and ($t | plugin) == $named and any(.named_paths[]?; . == $p))))' "$threads_file" >/dev/null
}

# git in the checkout with no system, global, hook, fsmonitor or untracked
# cache config, so reading the tree runs no program the checkout names.
git_tree() {
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.untrackedCache=false --no-optional-locks -C "$workspace" "$@"
}

# The empty files the CLI's Bash leaves at the top of the checkout under
# run-claude-cli's environment scrub, which the patch collector leaves out
# while they are empty and untracked (.github/scripts/read-patch/collect-patch.sh
# holds the same names): no fix, so no scope check.
scrub_stubs=(bunfig.toml package.json .npmrc .yarnrc .yarnrc.yml .gitmodules package-lock.json yarn.lock
  pnpm-lock.yaml .env .env.local .env.development .env.development.local .env.test .env.test.local
  .env.production .env.production.local)
is_stub() {
  local name
  for name in "${scrub_stubs[@]}"; do
    [[ $1 == "$name" ]] && [[ ! -L $workspace/$1 && -f $workspace/$1 && ! -s $workspace/$1 ]] && return 0
  done
  return 1
}

cmd_list() {
  jq '.threads' "$threads_file"
}

cmd_check_paths() {
  (($#)) || die 2 "usage: check-paths <path>..."
  local refused=0 path
  for path in "$@"; do
    if ! allowed "$path"; then
      printf "refused: %s is outside every kept thread's scope, or is under .github/workflows/\n" "$path" >&2
      refused=1
    fi
  done
  ((refused == 0)) || exit 1
  echo "allowed"
}

cmd_record() {
  (($# == 2)) || die 2 "usage: record <thread-id> <disposition-file>"
  local id=$1 file=$2
  [[ $id =~ ^PRRT_[A-Za-z0-9_-]{1,100}$ ]] || die 1 "not a review thread id"
  jq -e --arg id "$id" 'any(.threads[]; .id == $id)' "$threads_file" >/dev/null ||
    die 1 "$id is not a kept thread"
  if [[ -f $log_file ]] && jq -se --arg id "$id" 'any(.[]; .thread == $id)' "$log_file" >/dev/null 2>&1; then
    die 1 "$id already has a reply recorded"
  fi

  local scratch real
  scratch=$(realpath -e "$scratch_dir") || die 2 "no scratch directory"
  real=$(realpath -e -- "$file") || die 1 "no disposition file"
  [[ $real == "$scratch"/* && -f $real && ! -L $file ]] || die 1 "the disposition file must be a file in $scratch"
  (($(wc -c <"$real") <= 16384)) || die 1 "the disposition file is over 16 KiB"

  # The same rules the reply job enforces, so a refusal comes now, while the
  # skill can still fix its file: the note holds no control or direction
  # character, no HTML comment, and nothing shaped like a GitHub token. Token
  # shapes from
  # https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github#githubs-token-formats
  # and the stateless installation token (ghs_ then a JWT) from
  # https://github.blog/changelog/2026-05-15-github-app-installation-tokens-per-request-override-header/
  # whose header gh[opsur]_[A-Za-z0-9]{20} matches; this prefix check is not GitHub's recommended regex
  # (as of 2026-10-21; recheck when GitHub changes a token format or its recommended regex).
  local d
  d=$(jq -ec --arg id "$id" '
    def path_line: type == "string" and test("^[A-Za-z0-9_@+.-]+(/[A-Za-z0-9_@+.-]+)*:[1-9][0-9]{0,6}$")
      and (test("(^|/)\\.\\.?(/|:)") | not);
    select(type == "object")
    | select(keys - ["disposition", "evidence", "fix_sha", "note"] == [])
    | select(.disposition | IN("VALID", "INCORRECT", "UNCERTAIN", "VALID-defer"))
    | select((.evidence // []) | type == "array" and length <= 10 and all(path_line))
    | select((.disposition | IN("VALID", "INCORRECT") | not) or ((.evidence // []) | length > 0))
    | select(.note | type == "string" and length > 0 and length <= 2000)
    | select(.note | explode | all(. == 9 or . == 10 or (. >= 32 and . != 127
        and (. < 128 or . > 159) and (. < 8203 or . > 8207) and (. < 8234 or . > 8238)
        and (. < 8288 or . > 8297) and . != 65279)))
    | select(.note | test("<!--|-->|gh[opsur]_[A-Za-z0-9]{20}|ghs_[0-9]+_|github_pat_") | not)
    | select((.fix_sha // "") == "")
    | {thread: $id, disposition, evidence: (.evidence // []), fix_sha: (.fix_sha // ""), note}' "$real") ||
    die 1 "the disposition file does not match the template: disposition, evidence path:line list (one or more for VALID and INCORRECT), an empty fix_sha, note of 1-2000 characters with no control characters, HTML comments or tokens"

  local disposition ev
  disposition=$(jq -r .disposition <<<"$d")
  while IFS= read -r ev; do
    [[ -f $workspace/${ev%:*} ]] || die 1 "evidence ${ev%:*} is not a file in the checkout"
  done < <(jq -r '.evidence[]' <<<"$d")

  # A VALID reply's fix is uncommitted in the working tree: every path the
  # tree changes against the gated head, both sides of a rename, and every
  # untracked file not ignored but an empty scrub stub, is in a kept thread's
  # scope. The runner keeps .lane/ out of the tree through .git/info/exclude.
  if [[ $disposition == VALID ]]; then
    local -a paths untracked
    local path
    mapfile -d '' -t paths < <(git_tree diff --no-ext-diff --no-renames --name-only -z HEAD --)
    wait "$!" || die 1 "cannot read the working tree's changes"
    mapfile -d '' -t untracked < <(git_tree ls-files --others --exclude-standard -z)
    wait "$!" || die 1 "cannot read the working tree's untracked files"
    for path in "${untracked[@]}"; do
      # The lane's sandbox masks a dotfile with /dev/null, a device git will not add.
      [[ -L $workspace/$path || ! -c $workspace/$path ]] || continue
      is_stub "$path" || paths+=("$path")
    done
    ((${#paths[@]} < 300)) || die 1 "the working tree changes too many files to check"
    for path in "${paths[@]}"; do
      allowed "$path" || die 1 "the working tree changes $path, which is outside every kept thread's scope or under .github/workflows/; nothing is recorded"
    done
  fi

  jq -c . <<<"$d" >>"$log_file"
  echo "recorded $disposition for $id; the reply job posts it after this run"
}

case ${1:-} in
  list) cmd_list ;;
  check-paths) shift && cmd_check_paths "$@" ;;
  record) shift && cmd_record "$@" ;;
  *) die 2 "usage: feedback-thread.sh list | check-paths <path>... | record <thread-id> <disposition-file>" ;;
esac
