#!/usr/bin/env bash
# delivery-metrics.sh: the five DORA delivery metrics for one repository's
# default branch, as a team trend, read from git history alone.
#
# Deploy signal merge-to-default-branch: each commit on the branch's
# first-parent history is one deployment, at its committer date: a merge commit
# or a squash landing is one, and a rebase landing is one per commit it lands.
# A deployment that a later first-parent
# commit reverts is a failed deployment. A commit reverts a deployment when its
# message carries `This reverts commit <sha>` for the deployment or for a
# commit the deployment merged. With no such line, a commit whose subject is a
# revert (`Revert "<subject>"`, `revert:` or `revert(<scope>):`) reverts the
# deployment a `Reverts [<owner>/<repo>]#<n>` body line or a `(#<n>` subject
# group names by its pull request number, else the one its quoted or remaining
# subject matches. A merge's message includes the messages of the commits it
# merges, so a revert that lands through a merge commit is seen. Every
# deployment that reverts an earlier change is a rework deployment; a revert
# subject that names no deployment is also counted in unresolved_reverts.
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

# Each `This reverts commit <sha>` a deployment's message (or a commit it merged)
# names, kept only when the deployment's first parent reaches that sha: a
# squash body that names a commit which only ever existed on its branch
# reverts nothing on the default branch. Only deployments in the window are read.
jq -rn --rawfile raw "$TMP/deploys" --rawfile member_msgs "$TMP/member_msgs" \
  --argjson since "$SINCE_EPOCH" '
  def records: split("\u001e") | map(ltrimstr("\n") | select(length > 0) | split("\u001f"));
  (($raw | records | map(select((.[3] | tonumber) >= $since) | [.[0], (.[5] // "")]))
   + ($member_msgs | records | map([.[0], (.[1] // "")])))[]
  | .[0] as $d | .[1] | scan("This reverts (?:commit )?([0-9a-f]{40})") | "\($d)\t\(.[0])"
' >"$TMP/named" || {
  err "could not read the revert lines"
  exit 3
}
: >"$TMP/reachable"
while IFS=$'\t' read -r deploy named; do
  if git -C "$REPO" merge-base --is-ancestor "$named" "$deploy^1" 2>/dev/null; then
    printf '%s\t%s\n' "$deploy" "$named" >>"$TMP/reachable"
  fi
done < <(sort -u "$TMP/named")

jq -n \
  --rawfile raw "$TMP/deploys" \
  --rawfile members "$TMP/members" \
  --rawfile member_msgs "$TMP/member_msgs" \
  --rawfile reachable "$TMP/reachable" \
  --argjson since "$SINCE_EPOCH" \
  --argjson until "$UNTIL_EPOCH" \
  --arg bucket "$BUCKET" \
  --arg branch "$BRANCH" \
  --arg signal "$SIGNAL" '
# The US/RS-delimited git log records, each split into its fields.
def records: split("\u001e") | map(ltrimstr("\n") | select(length > 0) | split("\u001f"));
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
  deployment_rework_rate: ratio(map(select(.rework)) | length; length),
  unresolved_reverts: (map(select(.unresolved)) | length)
};
# A revert subject: `Revert "<subject>"` as git writes it, or Conventional Commits `revert:` / `revert(<scope>):`.
def revert_form: test("^Revert \"") or test("^revert(\\([^)]*\\))?!?: ");
# A squash subject without its trailing own pull request number.
def strip_own_ref: sub(" *\\(#[0-9]+\\)$"; "");

($raw | records | map({sha: .[0], parents: (.[1] | split(" ") | map(select(length > 0))),
     at: (.[2] | tonumber), ct: (.[3] | tonumber), subject: (.[4] // ""), body: (.[5] // "")})) as $all
| ($all | map(select(.ct >= $since))) as $scope
# Each squash landing by the pull request number that ends its subject.
| (reduce ($all[] | {n: (.subject | capture("\\(#(?<n>[0-9]+)\\)$").n), sha, ct}) as $p ({}; .[$p.n] = $p)) as $by_pr
| ($members | split("\n") | map(select(length > 0) | split("\t")
  | {deploy: .[0], sha: .[1], at: (.[2] | tonumber)})) as $mem
| (reduce $all[] as $d ({}; .[$d.sha] = $d.sha)
   | reduce $mem[] as $m (.; .[$m.sha] //= $m.deploy)) as $owner
| (reduce $mem[] as $m ({}; .[$m.deploy] += [$m.at])) as $member_at
| ($member_msgs | records) as $msgs
| (reduce $msgs[] as $m ({}; .[$m[0]] += "\n" + ($m[1] // ""))) as $member_text
| (reduce $msgs[] as $m ({}; .[$m[0]] += [($m[1] // "") | split("\n")[0]])) as $member_subjects
| (reduce ($reachable | split("\n") | map(select(length > 0)))[] as $p ({}; .[$p] = true)) as $reach
| ($scope | map(. as $r
    # The latest earlier deployment, not this one, whose subject, with or
    # without its trailing pull request number, is $s.
    | def subject_target($s): $all
        | map(select((.subject == $s or (.subject | strip_own_ref) == $s) and .ct <= $r.ct and .sha != $r.sha))
        | max_by(.ct) | .sha | select(. != null);
    # The deployments a revert subject names: the quoted subject of `Revert "<s>"`
    # or `revert(<scope>): ... "<s>"`, or the text after `revert(<scope>): `.
    def subject_targets($s): [$s
        | (capture("^Revert \"(?<s>.*)\"").s,
           (select(test("^revert(\\([^)]*\\))?!?: "))
            | sub("^revert(\\([^)]*\\))?!?: *"; "")
            | (capture("\"(?<s>.*)\"").s, ., strip_own_ref)))
        | subject_target(.)] | unique;
    ([.body + "\n" + ($member_text[.sha] // "") | scan("This reverts (?:commit )?([0-9a-f]{40})") | .[0]]
       | unique | map(select(($owner[.] // "") != $r.sha and $reach[$r.sha + "\t" + .] == true))) as $named
    | ($named | map($owner[.] // empty) | unique) as $by_sha
    | (.subject | revert_form) as $own_revert
    # Pull requests a revert names: `Reverts [owner/repo]#<n>` in its body, or a
    # `(#<n>` group in its subject other than its own trailing number.
    | ([(.body | scan("(?i)(?:^|[^A-Za-z0-9_])reverts[ \t]+(?:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#([0-9]+)") | .[0]),
        (.subject | strip_own_ref | scan("\\(#([0-9]+)") | .[0])]
       | unique | map($by_pr[.] // empty | select(.ct <= $r.ct and .sha != $r.sha) | .sha) | unique) as $pr_targets
    # A merged commit titled as a revert counts when it names an earlier deployment.
    | ([($member_subjects[.sha] // [])[] | select(revert_form) | subject_targets(.)[]] | unique) as $member_targets
    | (if ($by_sha | length) > 0 then $by_sha
       elif $own_revert and ($pr_targets | length) > 0 then $pr_targets
       elif $own_revert then subject_targets(.subject)
       else $member_targets
       end) as $targets
    | . + {targets: $targets,
           rework: (($named | length) > 0 or $own_revert or ($member_targets | length) > 0),
           unresolved: ($own_revert and ($targets | length) == 0)})) as $graded
| ($graded | map(select(.ct < $until)) | map(. as $d
    | ([$graded[] | select(.ct >= $d.ct and any(.targets[]; . == $d.sha)) | .ct] | min) as $fixed_at
    | {ct,
       rework,
       unresolved,
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
