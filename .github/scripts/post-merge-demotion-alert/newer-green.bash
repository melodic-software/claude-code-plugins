# shellcheck shell=bash
# newer_green_of REPO WORKFLOW_ID RUN_ID RUN_CREATED RUN_SHA prints, as
# <id>\t<sha>, the newest full run of WORKFLOW_ID on REPO's main, newer than
# run RUN_ID, whose attempt 1 passed (a listed run shows its latest
# attempt), or nothing when there is none. It counts only when its head descends from RUN_SHA and is on main's history (a ref named main, a
# tag included, can sit anywhere): compare RUN_SHA...newer and newer...<main's
# tip, read by heads/main> must each read ahead or identical. A failed listing
# returns 1; any other failed read or status prints nothing. At most four
# reads: one listing (newest ten), two compares and the ref.
# post-merge-demotion-alert.yml sources it, so a red run main already
# recovered from is neither re-run nor waited on; babysit_postmerge.py's
# `_Context.superseded` holds the same rule for what pr-merge re-runs.
newer_green_of() {
  local found newer_id newer_sha ancestry main_tip on_main
  found="$(NG_REPO="$1" NG_RUN_ID="$3" NG_CREATED="$4" gh api \
    "repos/$1/actions/workflows/$2/runs?branch=main&status=success&per_page=10" \
    --jq '[.workflow_runs[] | select(.conclusion == "success" and .run_attempt == 1 and .head_branch == "main"
      and (.event | IN("schedule", "workflow_dispatch"))
      and (.head_repository.full_name // "") == env.NG_REPO
      and (.id > (env.NG_RUN_ID | tonumber) or .created_at > env.NG_CREATED))]
      | max_by(.created_at) // empty | [.id, .head_sha] | @tsv')" || return 1
  [[ -n "$found" ]] || return 0
  IFS=$'\t' read -r newer_id newer_sha <<<"$found"
  [[ "$newer_id" =~ ^[0-9]+$ && "$newer_sha" =~ ^[0-9a-f]{40}$ && "$5" =~ ^[0-9a-f]{40}$ ]] || return 0
  ancestry="$(gh api "repos/$1/compare/$5...$newer_sha" --jq '.status')" || return 0
  [[ "$ancestry" == ahead || "$ancestry" == identical ]] || return 0
  main_tip="$(gh api "repos/$1/git/ref/heads/main" --jq '.object.sha')" || return 0
  [[ "$main_tip" =~ ^[0-9a-f]{40}$ ]] || return 0
  on_main="$(gh api "repos/$1/compare/$newer_sha...$main_tip" --jq '.status')" || return 0
  if [[ "$on_main" == ahead || "$on_main" == identical ]]; then
    printf '%s\n' "$found"
  fi
}
