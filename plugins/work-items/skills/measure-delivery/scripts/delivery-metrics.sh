#!/usr/bin/env bash
# delivery-metrics.sh: the five DORA delivery metrics for one repository's
# default branch, as a team trend, read from git history alone.
#
# Deploy signal merge-to-default-branch: each commit on the branch's
# first-parent history (a merge commit, or a squash or rebase landing) is one
# deployment, at its committer date. A deployment that a later first-parent
# commit reverts is a failed deployment. A commit reverts a deployment when its
# message carries `This reverts commit <sha>` for the deployment or for a
# commit the deployment merged, or, with no such line, when its subject is
# `Revert "<subject>"` for an earlier deployment's subject. A merge's message
# includes the messages of the commits it merges, so a revert that lands
# through a merge commit is seen. Every deployment that reverts an earlier
# change is a rework deployment.
#
# Change lead time is from the earliest author date among the commits a
# deployment brings in to the deployment's committer date. Failed deployment
# recovery time is from a failed deployment to the first deployment that
# reverts it; reverts after --until still count. The output carries counts,
# medians and ratios only: no commit, subject, author or committer.
#
# Usage:
#   delivery-metrics.sh [--repo <dir>] [--branch <ref>] [--since <YYYY-MM-DD>]
#     [--until <YYYY-MM-DD>] [--bucket week|month]
#     [--deploy-signal merge-to-default-branch]
#
#   --repo           repository directory (default: the current directory)
#   --branch         the default branch ref (default: what origin/HEAD names)
#   --since          first UTC day of the window (default: the 84 days ending with --until)
#   --until          last UTC day of the window, inclusive (default: now)
#   --bucket         trend period: week (ISO weeks, Monday start) or month
#   --deploy-signal  what counts as a deployment; only merge-to-default-branch
#
# Output: one JSON document on stdout, with `totals` for the window and one
# `trend` row per period, empty periods included. Times are hours, rates are
# ratios from 0 to 1, and a metric with nothing to measure is null.
#
# Exit codes:
#   0   report written
#   2   usage: a missing, repeated or unknown argument, or a malformed value
#   3   a git read failed
#   8   prerequisite missing: git or jq is not on PATH

set -uo pipefail

err() { printf 'delivery-metrics: %s\n' "$*" >&2; }
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

REPO="." BRANCH="" SINCE="" UNTIL="" BUCKET="" SIGNAL="" SEEN=" "
while (($#)); do
  case "$1" in
    --repo | --branch | --since | --until | --bucket | --deploy-signal)
      (($# >= 2)) || {
        err "$1 requires a value"
        exit 2
      }
      [[ "$SEEN" != *" $1 "* ]] || {
        err "$1 given twice"
        exit 2
      }
      SEEN+="$1 "
      case "$1" in
        --repo) REPO="$2" ;;
        --branch) BRANCH="$2" ;;
        --since) SINCE="$2" ;;
        --until) UNTIL="$2" ;;
        --bucket) BUCKET="$2" ;;
        --deploy-signal) SIGNAL="$2" ;;
        *) ;;
      esac
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      err "unknown argument: $1"
      exit 2
      ;;
  esac
done

SIGNAL="${SIGNAL:-merge-to-default-branch}"
[[ "$SIGNAL" == merge-to-default-branch ]] || {
  err "--deploy-signal must be merge-to-default-branch"
  exit 2
}
BUCKET="${BUCKET:-week}"
[[ "$BUCKET" == week || "$BUCKET" == month ]] || {
  err "--bucket must be week or month"
  exit 2
}
for tool in git jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    err "$tool is not on PATH"
    exit 8
  }
done
[[ -d "$REPO" ]] || {
  err "--repo is not a directory: $REPO"
  exit 2
}

# day_epoch <YYYY-MM-DD>: the UTC midnight that starts the day, as epoch seconds.
day_epoch() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  jq -n --arg d "$1" '$d + "T00:00:00Z" | fromdateiso8601' 2>/dev/null
}
if [[ -n "$UNTIL" ]]; then
  until_start="$(day_epoch "$UNTIL")" || {
    err "--until must be a YYYY-MM-DD date"
    exit 2
  }
  UNTIL_EPOCH=$((until_start + 86400))
else
  UNTIL_EPOCH="$(date +%s)"
fi
if [[ -n "$SINCE" ]]; then
  SINCE_EPOCH="$(day_epoch "$SINCE")" || {
    err "--since must be a YYYY-MM-DD date"
    exit 2
  }
else
  SINCE_EPOCH=$(((UNTIL_EPOCH - 84 * 86400) / 86400 * 86400))
fi
((SINCE_EPOCH < UNTIL_EPOCH)) || {
  err "--since must come before --until"
  exit 2
}

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git -C "$REPO" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" || {
    err "origin/HEAD names no default branch; pass --branch"
    exit 2
  }
fi
[[ "$BRANCH" =~ ^[A-Za-z0-9._/-]+$ && "$BRANCH" != -* ]] || {
  err "--branch is not a usable ref name: $BRANCH"
  exit 2
}
git -C "$REPO" rev-parse --verify --quiet "$BRANCH^{commit}" >/dev/null || {
  err "--branch does not resolve to a commit: $BRANCH"
  exit 2
}

TMP="$(mktemp -d)" || exit 3
trap 'rm -rf "$TMP"' EXIT

# Every first-parent commit, newest first: sha, parents, author and committer
# epochs, subject, body. Fields end in US (0x1f), records in RS (0x1e).
git -C "$REPO" log --first-parent --format='%H%x1f%P%x1f%at%x1f%ct%x1f%s%x1f%b%x1e' \
  "$BRANCH" -- >"$TMP/deploys" || {
  err "git log failed on $BRANCH"
  exit 3
}

# The commits each merge in the window brought in: deploy sha, member sha,
# member author epoch, tab-separated; and each member's message, so a revert
# that lands through a merge commit is seen.
git -C "$REPO" log --first-parent --merges --format='%H %ct %P' "$BRANCH" -- >"$TMP/merges" || {
  err "git log failed listing the merges on $BRANCH"
  exit 3
}
: >"$TMP/members"
: >"$TMP/member_msgs"
while read -r sha ct first rest; do
  ((ct >= SINCE_EPOCH)) || continue
  read -r -a others <<<"$rest"
  if ! git -C "$REPO" log --format="$sha%x09%H%x09%at" "${others[@]}" "^$first" -- >>"$TMP/members" ||
    ! git -C "$REPO" log --format="$sha%x1f%B%x1e" "${others[@]}" "^$first" -- >>"$TMP/member_msgs"; then
    err "git log failed for the commits merged by $sha"
    exit 3
  fi
done <"$TMP/merges"

jq -n \
  --rawfile raw "$TMP/deploys" \
  --rawfile members "$TMP/members" \
  --rawfile member_msgs "$TMP/member_msgs" \
  --argjson since "$SINCE_EPOCH" \
  --argjson until "$UNTIL_EPOCH" \
  --arg bucket "$BUCKET" \
  --arg branch "$BRANCH" \
  --arg signal "$SIGNAL" '
def median: sort | length as $n
  | if $n == 0 then null
    elif $n % 2 == 1 then .[($n - 1) / 2]
    else (.[$n / 2 - 1] + .[$n / 2]) / 2 end;
def hours: if . == null then null else (. / 36 | round) / 100 end;
def ratio($part; $whole): if $whole == 0 then null else ($part / $whole * 10000 | round) / 10000 end;
def period:
  if $bucket == "week"
  then (345600 + (((. - 345600) / 604800) | floor) * 604800) | todate | .[0:10]
  else todate | .[0:7] end;
def stats: {
  deployments: length,
  change_lead_time_hours_median: (map(.lead) | median | hours),
  failed_deployments: (map(select(.failed)) | length),
  change_fail_rate: ratio(map(select(.failed)) | length; length),
  failed_deployment_recovery_time_hours_median:
    (map(select(.recovery != null) | .recovery) | median | hours),
  rework_deployments: (map(select(.rework)) | length),
  deployment_rework_rate: ratio(map(select(.rework)) | length; length)
};

($raw | split("\u001e") | map(ltrimstr("\n") | select(length > 0) | split("\u001f")
  | {sha: .[0], parents: (.[1] | split(" ") | map(select(length > 0))),
     at: (.[2] | tonumber), ct: (.[3] | tonumber), subject: (.[4] // ""), body: (.[5] // "")})
  | map(select(.ct >= $since))) as $scope
| ($members | split("\n") | map(select(length > 0) | split("\t")
  | {deploy: .[0], sha: .[1], at: (.[2] | tonumber)})) as $mem
| (reduce $scope[] as $d ({}; .[$d.sha] = $d.sha)
   | reduce $mem[] as $m (.; .[$m.sha] //= $m.deploy)) as $owner
| (reduce $mem[] as $m ({}; .[$m.deploy] += [$m.at])) as $member_at
| (reduce ($member_msgs | split("\u001e") | map(ltrimstr("\n") | select(length > 0) | split("\u001f")))[] as $m
    ({}; .[$m[0]] += "\n" + ($m[1] // ""))) as $member_text
| ($scope | map(. as $r
    | ([.body + "\n" + ($member_text[.sha] // "") | scan("This reverts (?:commit )?([0-9a-f]{40})") | .[0]]
       | unique | map(select(($owner[.] // "") != $r.sha))) as $named
    | ($named | map($owner[.] // empty) | unique) as $by_sha
    | ([.subject | capture("^Revert \"(?<s>.*)\"") | .s] | first) as $reverted_subject
    | (if ($named | length) > 0 then $by_sha
       elif $reverted_subject == null then []
       else [$scope | map(select(.subject == $reverted_subject and .ct <= $r.ct and .sha != $r.sha))
             | max_by(.ct) | .sha | select(. != null)]
       end) as $targets
    | . + {targets: $targets, rework: (($named | length) > 0 or $reverted_subject != null)})) as $graded
| ($graded | map(select(.ct < $until)) | map(. as $d
    | ([$graded[] | select(.ct >= $d.ct and any(.targets[]; . == $d.sha)) | .ct] | min) as $fixed_at
    | {ct,
       rework,
       lead: ([(([$d.at] + ($member_at[$d.sha] // [])) | min) as $start | $d.ct - $start, 0] | max),
       failed: ($fixed_at != null),
       recovery: (if $fixed_at == null then null else $fixed_at - $d.ct end),
       period: (.ct | period)})) as $reported
| (($until - $since) / 86400) as $days
| {
    deploy_signal: $signal,
    branch: $branch,
    bucket: $bucket,
    since: ($since | todate | .[0:10]),
    until: ($until - 1 | todate | .[0:10]),
    totals: ($reported | stats
      + {deployments_per_week: ((length * 7 / $days * 100 | round) / 100)}),
    trend: ([range($since; $until; 86400) | period] | unique
      | map(. as $p | {period: $p} + ($reported | map(select(.period == $p)) | stats)))
  }
' || {
  err "could not compute the report"
  exit 3
}
