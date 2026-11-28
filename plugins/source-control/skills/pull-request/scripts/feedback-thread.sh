#!/usr/bin/env bash
# Exit: 0 done; 1 refused (nothing recorded); 2 usage or environment.
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

allowed() {
  local tracked=false mode
  mode=$(git_tree ls-tree HEAD -- "$1" 2>/dev/null | cut -d' ' -f1) || mode=""
  [[ $mode == 100644 || $mode == 100755 ]] && tracked=true
  [[ ! ${1,,} =~ ^\.github/workflows(/|$) && ! $1 =~ (^|/)\.{0,2}(/|$) ]] &&
    jq -e --arg p "$1" --argjson tracked "$tracked" '
      def dir: sub("[^/]*$"; "");
      def plugin: first(capture("^(?<c>plugins/[^/]+/)").c) // null;
      ($p | test("^[A-Za-z0-9_@+.-]+(/[A-Za-z0-9_@+.-]+)*$")) as $plain
      | ($p | test("(^|/)(\\.gitmodules|codeowners|settings[^/]*\\.json|package(-lock)?\\.json|requirements[^/]*\\.txt)$"; "i")) as $instruction
      | (if $instruction then null else $p | plugin end) as $plugin
      | ($p | sub("^.*/"; "") | test("^(test_[^/]*\\.py|[^/]*_test\\.py|[^/]*\\.(test|spec)\\.[^/]+)$")) as $test
      | ($tracked and any(.pr_paths[]?, .copy_paths[]?; . == $p)) as $pr
      | ($plugin != null and (($p | test("^plugins/[^/]+/(skills/[^/]+/)?evals/")) or any(.pr_paths[]?; startswith($plugin)))) as $wide
      | $plain and ($pr or $wide or any(.threads[], .verify_notes[]?; .path as $t
          | $t == $p
          or ($plugin != null and ($t | startswith($plugin)))
          or ($test and ($t | dir) == ($p | dir))
          or ($plugin != null and ($t | plugin) == $plugin and any(.named_paths[]?; . == $p))))' "$threads_file" >/dev/null
}

git_tree() {
  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.untrackedCache=false --no-optional-locks -C "$workspace" "$@"
}

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

cmd_comments() {
  jq '.pr_comments // []' "$threads_file"
}

cmd_notes() {
  jq '.verify_notes // []' "$threads_file"
}

cmd_issues() {
  jq '.closing_issues // []' "$threads_file"
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

scratch_file() {
  local scratch real
  scratch=$(realpath -e "$scratch_dir") || die 2 "no scratch directory"
  real=$(realpath -e -- "$1") || die 1 "no such file: $1"
  [[ $real == "$scratch"/* && -f $real && ! -L $1 ]] || die 1 "the file must be a file in $scratch"
  (($(wc -c <"$real") <= 16384)) || die 1 "the file is over 16 KiB"
  printf '%s\n' "$real"
}

replies_cap=49152

size_with() {
  local now=0
  [[ -f $log_file ]] && now=$(wc -c <"$log_file")
  echo $((now + $(printf '%s\n' "$1" | wc -c)))
}

append_reply() {
  local note=""
  if (($(size_with "$1") > replies_cap)) && [[ -f $log_file ]] && grep -q '^{"body_sections":' "$log_file"; then
    grep -v '^{"body_sections":' "$log_file" >"$log_file.next" || true
    mv -- "$log_file.next" "$log_file"
    note="; the body sections were dropped to make room for it"
  fi
  (($(size_with "$1") <= replies_cap)) || die 1 "the replies would pass their $replies_cap-byte cap; shorten the note and record again"
  printf '%s\n' "$1" >>"$log_file"
  printf '%s' "$note"
}

cmd_body() {
  jq '.body_view // []' "$threads_file"
}

cmd_sections() {
  jq '.body_sections // []' "$threads_file"
}

cmd_record_body() {
  (($# == 1)) || die 2 "usage: record-body <body-file>"
  jq -e '(.body_sections // []) | length > 0' "$threads_file" >/dev/null ||
    die 1 "this round offers no body section to refresh"
  if [[ -f $log_file ]] && jq -se 'any(.[]; has("body_sections"))' "$log_file" >/dev/null 2>&1; then
    die 1 "the body sections are already recorded"
  fi
  local real d
  real=$(scratch_file "$1")
  d=$(jq -ec --slurpfile t "$threads_file" '
    ([$t[0].body_sections[].heading]) as $offered
    | select(type == "object" and keys == ["sections"])
    | .sections
    | select(type == "array" and length > 0 and length <= 8)
    | select(all(.[]; type == "object" and keys == ["heading", "text"]
        and (.heading as $h | $offered | index($h) != null)
        and (.text | type == "string" and length > 0 and length <= 4000)
        and (.text | explode | all(. == 9 or . == 10 or (. >= 32 and . != 127
          and (. < 128 or . > 159) and (. < 8203 or . > 8207) and (. < 8234 or . > 8238)
          and (. < 8288 or . > 8297) and . != 65279)))
        and (.text | test("<!--|-->|gh[opsur]_[A-Za-z0-9]{20}|ghs_[0-9]+_|github_pat_") | not)))
    | select((map(.heading) | unique | length) == length)
    | {body_sections: map({heading, text})}' "$real") ||
    die 1 "the body file does not match the template: sections, 1-8 of them, each a heading sections lists once and text of 1-4000 characters with no control characters, HTML comments or tokens"
  d=$(jq -c . <<<"$d")
  (($(size_with "$d") <= replies_cap)) ||
    die 1 "the body sections would pass the replies' $replies_cap-byte cap; nothing is recorded"
  printf '%s\n' "$d" >>"$log_file"
  echo "recorded the body sections; the reply job puts them in place after this run when the fix lands, and a reply that needs their room drops them"
}

cmd_record() {
  (($# == 2)) || die 2 "usage: record <thread-id> <disposition-file>"
  local id=$1 file=$2 kinds
  if [[ $id =~ ^VNOTE_[1-9][0-9]{0,2}$ ]]; then
    jq -e --arg id "$id" 'any(.verify_notes[]?; .id == $id)' "$threads_file" >/dev/null ||
      die 1 "$id is not a pr-verify note of this round"
    kinds='["VALID", "already-addressed"]'
  elif [[ $id =~ ^PRC_[1-9][0-9]{0,19}$ ]]; then
    jq -e --arg id "$id" 'any(.pr_comments[]?; .id == $id)' "$threads_file" >/dev/null ||
      die 1 "$id is not a comment of this round"
    kinds='["answered"]'
  else
    [[ $id =~ ^PRRT_[A-Za-z0-9_-]{1,100}$ ]] || die 1 "not a review thread id"
    jq -e --arg id "$id" 'any(.threads[]; .id == $id)' "$threads_file" >/dev/null ||
      die 1 "$id is not a kept thread"
    kinds='["VALID", "INCORRECT", "UNCERTAIN", "VALID-defer"]'
    if jq -e --arg id "$id" 'any(.threads[]; .id == $id and .may_follow_up == true)' "$threads_file" >/dev/null; then
      kinds='["VALID", "INCORRECT", "UNCERTAIN", "VALID-defer", "follow-up"]'
    fi
  fi
  if [[ -f $log_file ]] && jq -se --arg id "$id" 'any(.[]; .thread == $id)' "$log_file" >/dev/null 2>&1; then
    die 1 "$id already has a reply recorded"
  fi

  local real
  real=$(scratch_file "$file")

  local d
  d=$(jq -ec --arg id "$id" --argjson kinds "$kinds" '
    def path_line: type == "string" and test("^[A-Za-z0-9_@+.-]+(/[A-Za-z0-9_@+.-]+)*:[1-9][0-9]{0,6}$")
      and (test("(^|/)\\.\\.?(/|:)") | not);
    select(type == "object")
    | select(keys - ["disposition", "evidence", "fix_sha", "note"] == [])
    | select(.disposition as $d | $kinds | index($d) != null)
    | select((.evidence // []) | type == "array" and length <= 10 and all(path_line))
    | select((.disposition | IN("VALID", "INCORRECT", "already-addressed") | not) or ((.evidence // []) | length > 0))
    | select(.note | type == "string" and length > 0 and length <= 2000)
    | select(.note | explode | all(. == 9 or . == 10 or (. >= 32 and . != 127
        and (. < 128 or . > 159) and (. < 8203 or . > 8207) and (. < 8234 or . > 8238)
        and (. < 8288 or . > 8297) and . != 65279)))
    | select(.note | test("<!--|-->|gh[opsur]_[A-Za-z0-9]{20}|ghs_[0-9]+_|github_pat_") | not)
    | select((.fix_sha // "") == "")
    | {thread: $id, disposition, evidence: (.evidence // []), fix_sha: (.fix_sha // ""), note}' "$real") ||
    die 1 "the disposition file does not match the template: disposition (VALID or already-addressed for a pr-verify note, answered for a comment), evidence path:line list (one or more for VALID, INCORRECT and already-addressed), an empty fix_sha, note of 1-2000 characters with no control characters, HTML comments or tokens"

  local disposition ev
  disposition=$(jq -r .disposition <<<"$d")
  while IFS= read -r ev; do
    [[ -f $workspace/${ev%:*} ]] || die 1 "evidence ${ev%:*} is not a file in the checkout"
  done < <(jq -r '.evidence[]' <<<"$d")

  if [[ $disposition == VALID ]]; then
    local -a paths untracked
    local path
    mapfile -d '' -t paths < <(git_tree diff --no-ext-diff --no-renames --name-only -z HEAD --)
    wait "$!" || die 1 "cannot read the working tree's changes"
    mapfile -d '' -t untracked < <(git_tree ls-files --others --exclude-standard -z)
    wait "$!" || die 1 "cannot read the working tree's untracked files"
    for path in "${untracked[@]}"; do
      [[ -L $workspace/$path || ! -c $workspace/$path ]] || continue
      is_stub "$path" || paths+=("$path")
    done
    ((${#paths[@]} < 300)) || die 1 "the working tree changes too many files to check"
    for path in "${paths[@]}"; do
      allowed "$path" || die 1 "the working tree changes $path, which is outside every kept thread's scope or under .github/workflows/; nothing is recorded"
    done
  fi

  local note
  note=$(append_reply "$(jq -c . <<<"$d")")
  echo "recorded $disposition for $id; the reply job posts it after this run$note"
}

case ${1:-} in
  list) cmd_list ;;
  comments) cmd_comments ;;
  notes) cmd_notes ;;
  issues) cmd_issues ;;
  check-paths) shift && cmd_check_paths "$@" ;;
  record) shift && cmd_record "$@" ;;
  body) cmd_body ;;
  sections) cmd_sections ;;
  record-body) shift && cmd_record_body "$@" ;;
  *) die 2 "usage: feedback-thread.sh list | comments | notes | issues | body | sections | check-paths <path>... | record <thread-id> <disposition-file> | record-body <body-file>" ;;
esac
