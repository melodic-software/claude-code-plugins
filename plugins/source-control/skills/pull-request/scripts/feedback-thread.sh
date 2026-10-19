#!/usr/bin/env bash
# feedback-thread.sh: the review-thread tool of `comments --ci`
# (reference/comments-ci.md). The write runner stages a read-only copy behind a
# wrapper that fixes the environment below, and the skill's Bash may run only
# that wrapper. Every finding body is untrusted data: it is printed, never run.
# The tool posts nothing: it records each reply in the replies file, which the
# runner uploads and a later job with no model validates and posts.
#
#   list                              the kept threads, as JSON
#   check-paths <path>...             exit 0 when every path is in a kept
#                                     thread's scope (allowed below)
#   record <thread-id> <disposition>  check the disposition against the
#                                     template and append it to the replies
#
# The disposition file is JSON in the scratch directory:
#   {"disposition": "VALID" | "INCORRECT" | "UNCERTAIN" | "VALID-defer",
#    "evidence": ["path:line", ...], "fix_sha": "<sha, VALID only>",
#    "note": "<prose>"}
#
# Environment:
#   FEEDBACK_THREADS    the runner's thread file (repository, pr, head_sha,
#                       lane_branch, threads[])
#   FEEDBACK_LOG        the replies file, one JSON object per line
#   FEEDBACK_SCRATCH    the only directory a disposition file may sit in
#   FEEDBACK_WORKSPACE  the checkout evidence paths are checked against
#   GH_TOKEN            the lane token (or GITHUB_TOKEN), for the compare read
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
repo=$(jq -er '.repository | select(test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"))' "$threads_file") ||
  die 2 "the thread file names no repository"

# Not under .github/ in any letter case, with no empty, . or .. segment, and
# in a kept thread's scope: its path, a file in the plugins/<p>/ directory
# it sits in that is no instruction path (CLAUDE.md, AGENTS.md, .mcp.json,
# .gitmodules, CODEOWNERS, a .claude/ or .claude-plugin/ directory, a
# plugin's hooks/) and not a .sh, .py, .mjs, .js or .ts file, a test file in
# its directory, or a path in its named_paths (the files a write-access fix
# request named) in that same plugins/<p>/ directory, of plain ASCII
# segments and no instruction path. The same rule as
# .github/scripts/pr-unblock/thread-scope.mjs, which the promote step and
# the reply job apply.
allowed() {
  [[ ! ${1,,} =~ ^\.github(/|$) && ! $1 =~ (^|/)\.{0,2}(/|$) ]] &&
    jq -e --arg p "$1" '
      def dir: sub("[^/]*$"; "");
      def plugin: first(capture("^(?<c>plugins/[^/]+/)").c) // null;
      ($p | test("(^|/)((claude|agents)\\.md|\\.mcp\\.json|\\.gitmodules|codeowners)$|(^|/)\\.claude(-plugin)?/|(^|/)plugins/[^/]+/hooks/"; "i")) as $instruction
      | (if $instruction or ($p | test("\\.(sh|py|mjs|js|ts)$"; "i"))
         then null else $p | plugin end) as $plugin
      | ($p | sub("^.*/"; "") | test("^(test_[^/]*\\.py|[^/]*_test\\.py|[^/]*\\.(test|spec)\\.[^/]+)$")) as $test
      | (if ($p | test("^[A-Za-z0-9_@+.-]+(/[A-Za-z0-9_@+.-]+)*$")) and ($instruction | not)
         then $p | plugin else null end) as $named
      | any(.threads[]; .path as $t
          | $t == $p
          or ($plugin != null and ($t | startswith($plugin)))
          or ($test and ($t | dir) == ($p | dir))
          or ($named != null and ($t | plugin) == $named and any(.named_paths[]?; . == $p)))' "$threads_file" >/dev/null
}

cmd_list() {
  jq '.threads' "$threads_file"
}

cmd_check_paths() {
  (($#)) || die 2 "usage: check-paths <path>..."
  local refused=0 path
  for path in "$@"; do
    if ! allowed "$path"; then
      printf "refused: %s is outside every kept thread's scope, or is under .github/\n" "$path" >&2
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
  # character, no HTML comment, and nothing shaped like a GitHub token.
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
    | select(.note | test("<!--|-->|gh[opsur]_[A-Za-z0-9]{20}|github_pat_") | not)
    | select(if .disposition == "VALID" then (.fix_sha | type == "string" and test("^[0-9a-f]{40}$"))
             else (.fix_sha // "") == "" end)
    | {thread: $id, disposition, evidence: (.evidence // []), fix_sha: (.fix_sha // ""), note}' "$real") ||
    die 1 "the disposition file does not match the template: disposition, evidence path:line list (one or more for VALID and INCORRECT), fix_sha for VALID only, note of 1-2000 characters with no control characters, HTML comments or tokens"

  local disposition fix_sha ev
  disposition=$(jq -r .disposition <<<"$d")
  fix_sha=$(jq -r .fix_sha <<<"$d")
  while IFS= read -r ev; do
    [[ -f $workspace/${ev%:*} ]] || die 1 "evidence ${ev%:*} is not a file in the checkout"
  done < <(jq -r '.evidence[]' <<<"$d")

  # A VALID reply names a fix commit on the lane branch, and every file the
  # lane branch changed since the gated head is in a kept thread's scope.
  if [[ $disposition == VALID ]]; then
    local head lane cmp path
    head=$(jq -er '.head_sha | select(test("^[0-9a-f]{40}$"))' "$threads_file") || die 2 "the thread file names no head"
    lane=$(jq -er '.lane_branch | select(test("^[A-Za-z0-9._/-]+$"))' "$threads_file") || die 2 "the thread file names no lane branch"
    cmp=$(gh api "repos/$repo/compare/$head...$lane") || die 1 "cannot compare the lane branch with the gated head"
    jq -e --arg sha "$fix_sha" 'any(.commits[]; .sha == $sha)' <<<"$cmp" >/dev/null ||
      die 1 "the fix $fix_sha is not a commit on the lane branch"
    (($(jq '.files | length' <<<"$cmp") < 300)) || die 1 "the lane branch changes too many files to check"
    while IFS= read -r path; do
      allowed "$path" || die 1 "the lane branch changes $path, which is outside every kept thread's scope or under .github/; nothing is recorded"
    done < <(jq -r '.files[] | .filename, (.previous_filename // empty)' <<<"$cmp")
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
