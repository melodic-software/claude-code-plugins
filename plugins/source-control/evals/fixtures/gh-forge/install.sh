#!/usr/bin/env bash
# Gives a scaffolded repository an offline forge: a bare `origin` holding the base and head branches,
# and a gh stand-in that serves one open draft pull request from them. Run it from a case's
# scaffold.sh in the workspace, after the base and head branches exist:
#   bash install.sh <number> <head-branch> <base-branch> <title> [--open] [--no-pr] [--failing-check <name>] [--thread <id>]...
#     [--outdated-bot-thread <id>]... [--thread-comment <path> <body>] [--extra-pr <number> <head-branch> <title>]...
#     [--dir <checkout>]
# --dir installs into that checkout instead of the current directory. Each --extra-pr serves one more
# open pull request from that head branch into the same base, with the first one's draft state and checks.
# The pull request is a draft unless --open is given. --no-pr serves no pull request until `gh pr create`
# opens one from <head-branch>. The head is always pushed here: a run whose root sits under /tmp has
# .git read-only, so its push must find nothing to send, which git reports as up to date with exit 0.
# Issues the stand-in serves are <git common dir>/eval-forge/issues/<n>.json, written by the scaffold. --failing-check adds one failing check with
# that name, which `pr checks` and the pull request's status rollup then report. Each --thread adds
# one unresolved review thread with that id, from a person on the current diff, to what
# `gh api graphql` serves; each --outdated-bot-thread adds one from a bot (author __typename Bot)
# that GitHub marks outdated (isOutdated true). Threads are served in the order given.
# --thread-comment sets every thread's file path and comment body (default path `f`, a placeholder body).
#
# origin's URL is https://github.com/eval-fixture/app.git, so push-branch.sh, which compares the
# push remote's URL with the PR's head repository, accepts it as eval-fixture/app on github.com.
# `remote.origin.vcs=evalforge` hands every fetch and push of origin to the git-remote-evalforge
# helper (copied into the stand-in's bin/), which serves them from the local bare repository, so
# nothing reaches github.com. git runs a helper as `git remote-evalforge`, so the
# `alias.remote-evalforge` this script sets finds the helper by its absolute path when the run's PATH
# lacks the stand-in's bin/, as in the no-plugin arm. Without either, git fails with
# "remote-evalforge is not a git command" and never falls back to https.
#
# The gh and git stand-ins land in <git common dir>/eval-forge/bin. A case puts them first on the run's Bash PATH by
# listing its own `gh-forge-path` plugin subdirectory in prompt.md `plugins:`: that plugin's
# SessionStart hook appends an export of the directory to $CLAUDE_ENV_FILE, which the run's shell
# applies whether it is bash or zsh. A case cannot set PATH (env keys are EVAL_* only), a plugin's
# bin/ is not put on an eval run's PATH, and a plugin a case ships must sit in a subdirectory of
# the case directory, so each case carries its own copy of that one-file plugin. The no-plugin arm
# loads no plugin, and a run reads no .claude/ directory a scaffold writes, so a bare `gh` there is
# the real one: a grader that reads the stand-in's call record is `arm: with-only`.
# Pointers: https://code.claude.com/docs/en/plugin-evals#case-yaml-fields,
# https://code.claude.com/docs/en/plugin-evals#how-runs-are-isolated and
# https://code.claude.com/docs/en/hooks#persist-environment-variables, as of 2026-10-31 (Claude
# Code 2.1.296 probe run for the hook). Recheck trigger: a Claude Code release that changes
# CLAUDE_ENV_FILE, plugin hooks or bin/ in eval runs, or adds a case-level PATH setting.
set -euo pipefail

number="$1" head="$2" base="$3" title="$4"
shift 4
draft=true failing="" threads=() thread_path=f thread_body="eval fixture review comment" no_pr=0 dir=. extra_prs=() extra_heads=()
while (($#)); do
  case "$1" in
    --open) draft=false ;;
    --no-pr) no_pr=1 ;;
    --dir)
      dir="${2:?--dir needs a checkout directory}"
      shift
      ;;
    --extra-pr)
      extra_prs+=("${2:?--extra-pr needs a number}"$'\t'"${3:?--extra-pr needs a head branch}"$'\t'"${4:?--extra-pr needs a title}")
      extra_heads+=("$3")
      shift 3
      ;;
    --thread)
      threads+=("user ${2:?--thread needs a thread id}")
      shift
      ;;
    --outdated-bot-thread)
      threads+=("bot ${2:?--outdated-bot-thread needs a thread id}")
      shift
      ;;
    --thread-comment)
      thread_path="${2:?--thread-comment needs a path}" thread_body="${3:?--thread-comment needs a body}"
      shift 2
      ;;
    --failing-check)
      failing="${2:?--failing-check needs a check name}"
      shift
      ;;
    *)
      echo "install.sh: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
  shift
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$dir"
forge="$(git rev-parse --path-format=absolute --git-common-dir)/eval-forge"
git remote add origin "https://github.com/eval-fixture/app.git"
git config remote.origin.vcs evalforge
git config alias.remote-evalforge "!\"$forge/bin/git-remote-evalforge\""

mkdir -p "$forge/bin" "$forge/issues"
cp "$here/gh" "$forge/bin/gh"
chmod +x "$forge/bin/gh"
cp "$here/git-remote-evalforge" "$forge/bin/git-remote-evalforge"
chmod +x "$forge/bin/git-remote-evalforge"
printf 'PR_NUMBER=%q\nPR_HEAD=%q\nPR_BASE=%q\nPR_TITLE=%q\n' "$number" "$head" "$base" "$title" >"$forge/state"
printf '%s\n' "${extra_prs[@]+"${extra_prs[@]}"}" | sed '/^$/d' >"$forge/extra-prs"
echo "$draft" >"$forge/draft"
((no_pr)) || : >"$forge/created"
if [[ -n "$failing" ]]; then
  jq -n --arg name "$failing" --arg url "https://github.com/eval-fixture/app/actions/runs/1" \
    '[{name: $name, state: "FAILURE", bucket: "fail", workflow: "ci", link: $url}]' >"$forge/checks"
else
  echo '[]' >"$forge/checks"
fi

printf '%s\n' "${threads[@]+"${threads[@]}"}" | jq -Rnc --arg path "$thread_path" --arg body "$thread_body" '[inputs | select(length > 0) | (.[:index(" ")] == "bot") as $bot | {
  id: .[index(" ") + 1:], isResolved: false, isOutdated: $bot, resolvedBy: null, originalStartLine: null, originalLine: 1,
  comments: {totalCount: 1, pageInfo: {hasNextPage: false}, nodes: [{
    author: (if $bot then {__typename: "Bot", login: "review-bot"} else {__typename: "User", login: "reviewer"} end),
    body: $body, path: $path,
    url: "https://github.com/eval-fixture/app/pull/1#discussion_r1", createdAt: "2026-01-01T00:00:00Z",
    updatedAt: "2026-01-01T00:00:00Z", databaseId: 1, diffHunk: "", originalCommit: {oid: "0"}}]}}]' >"$forge/threads"
: >"$forge/calls.jsonl"

git init -q --bare "$forge/eval-fixture/app.git"
git -C "$forge/eval-fixture/app.git" symbolic-ref HEAD "refs/heads/$base"
export PATH="$forge/bin:$PATH"
git push -q origin "$base" "$head" "${extra_heads[@]+"${extra_heads[@]}"}"
cp "$here/git" "$forge/bin/git"
chmod +x "$forge/bin/git"
for b in "$head" "${extra_heads[@]+"${extra_heads[@]}"}"; do
  git branch -q --set-upstream-to="origin/$b" "$b"
done
# A fetch opens FETCH_HEAD for writing before anything else, and on Linux nothing under a run root in
# /tmp is writable to the run's Bash (with TMPDIR outside /tmp the root is writable, as
# /evals:plugin-eval records), so the file points at the one writable path every run has.
ln -sf /dev/null "$(git rev-parse --path-format=absolute --git-path FETCH_HEAD)"
