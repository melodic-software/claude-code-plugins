#!/usr/bin/env bash
# portability-scope: the GitHub implementation of the ready flip's hold check; every read is a gh call.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRUSTED_ACTORS_PATH=".github/standards/trusted-actors/trusted-actors.json"
TEAM_YAML="docs/conventions/source-control.yaml"
STANDARDS_TRUSTED_ACTORS="components/trusted-actors/trusted-actors.json"
PARSER="$SCRIPT_DIR/../../../lib/parse-concern-value.sh"

usage() {
  cat <<'EOF'
check-ready-holds.sh: refuse the ready flip for a held or superseded pull request.

Usage:
  check-ready-holds.sh <pr> [--repo <owner/repo>] [--unattended]

  --repo        the pull request's repository
  --unattended  also hold on a body line starting "Draft:"

Exit codes:
  0  no hold: the flip may go on
  1  invalid argument
  2  a gh call failed; the flip stops, since no hold was ruled out
  3  held or superseded: one reason per line on stdout
  5  prerequisite missing (gh, jq)
EOF
  exit 0
}

die() {
  printf 'check-ready-holds: %s\n' "$2" >&2
  exit "$1"
}

PR="" REPO="" UNATTENDED=false
while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --unattended)
    UNATTENDED=true
    shift
    ;;
  --repo)
    (($# >= 2)) || die 1 "--repo needs a value"
    REPO="$2"
    shift 2
    ;;
  -*) die 1 "unknown flag $(printf '%q' "$1") (use --help)" ;;
  *)
    [[ -z "$PR" ]] || die 1 "unexpected argument $(printf '%q' "$1")"
    PR="$1"
    shift
    ;;
  esac
done
[[ "$PR" =~ ^[0-9]+$ ]] || die 1 "a pull request number is required (use --help)"

command -v gh >/dev/null 2>&1 || die 5 "gh not found on PATH"
command -v jq >/dev/null 2>&1 || die 5 "jq not found on PATH"

repo_args=()
[[ -n "$REPO" ]] && repo_args=(--repo "$REPO")

facts=$(gh pr view "$PR" ${repo_args[@]+"${repo_args[@]}"} --json title,body,labels,closingIssuesReferences,url) ||
  die 2 "gh pr view $PR failed"

lanes_app_login_from_settings() {
  local shown
  shown=$(
    # shellcheck source=../../babysit-prs/scripts/babysit-python.sh
    . "$SCRIPT_DIR/../../babysit-prs/scripts/babysit-python.sh"
    babysit_python "$SCRIPT_DIR/../../babysit-prs/scripts/babysit_merge_settings.py" show 2>/dev/null
  ) || return 0
  jq -r '.issue_status_app_login // "" | strings' <<<"$shown" 2>/dev/null | tr -d '\r' || true
}

trusted_list() {
  local host=$1 path=$2 err team found src std sha
  err=$(mktemp) || return 1
  team=$(gh api --hostname "$host" -H "Accept: application/vnd.github.raw+json" "repos/$path/contents/$TEAM_YAML" 2>"$err")
  found=$?
  if ((found != 0)) && ! grep -q 'HTTP 404' "$err"; then
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  src=""
  if ((found == 0)); then
    src=$(printf '%s\n' "$team" | bash "$PARSER" --strict - trusted_actors_source) || return 1
    src=${src//$'\r'/}
    [[ -n "$src" ]] || ! grep -Eq '^trusted_actors_source[[:blank:]]*:' <<<"$team" || return 1
  fi
  case "$src" in
  "" | repository)
    gh api --hostname "$host" -H "Accept: application/vnd.github.raw+json" "repos/$path/contents/$TRUSTED_ACTORS_PATH"
    ;;
  standards)
    std=$(printf '%s\n' "$team" | bash "$PARSER" --strict - standards_repository) || return 1
    std=${std//$'\r'/}
    [[ "$std" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
    sha=$(gh api --hostname "$host" "repos/$std/git/ref/heads/main" --jq .object.sha) || return 1
    sha=${sha//$'\r'/}
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1
    gh api --hostname "$host" -H "Accept: application/vnd.github.raw+json" "repos/$std/contents/$STANDARDS_TRUSTED_ACTORS?ref=$sha"
    ;;
  *) return 1 ;;
  esac
}

eval_only_hold() {
  local where host path comments events trusted verdict
  where=$(jq -r '.url // "" | capture("^https?://(?<h>[^/]+)/(?<p>[^/]+/[^/]+)/pull/[0-9]+") | [.h, .p] | @tsv' <<<"$facts" 2>/dev/null)
  where=${where//$'\r'/}
  IFS=$'\t' read -r host path <<<"$where"
  [[ -n "$host" && -n "$path" ]] || {
    echo "the pull request URL could not be read"
    return 1
  }
  events=$(gh api --hostname "$host" --paginate "repos/$path/issues/$PR/events?per_page=100" \
    --jq '.[] | select(.event == "labeled") | {created_at, name: .label.name}' | jq -s .) || {
    echo "its label events could not be read"
    return 1
  }
  comments=$(gh api --hostname "$host" --paginate "repos/$path/issues/$PR/comments?per_page=100" \
    --jq '.[] | {created_at, body, type: .user.type, id: .user.id, login: .user.login, app: (.performed_via_github_app != null)}' | jq -s .) || {
    echo "its comments could not be read"
    return 1
  }
  trusted=$(trusted_list "$host" "$path") || {
    echo "the trusted-actors list could not be read"
    return 1
  }
  verdict=$(jq -rn --argjson events "$events" --argjson comments "$comments" --argjson trusted "$trusted" --arg app "$(lanes_app_login_from_settings)" '
    def ownlines:
      reduce (splits("\r\n|\r|\n")) as $l ({fence: "", out: []};
        ($l | capture("^ {0,3}(?<m>`{3,}|~{3,})(?<rest>.*)$") // null) as $m
        | if .fence != "" then
            (if $m != null and ($m.m[0:1] == .fence[0:1]) and ($m.m | length) >= (.fence | length) and ($m.rest | test("^\\s*$")) then .fence = "" else . end)
          elif $m != null then .fence = $m.m
          elif ($l | test("^ {0,3}>")) then .
          else .out += [$l] end)
      | .out[];
    if ($trusted.version != 1 or ($trusted.actors | type) != "array") then "the trusted-actors list does not match its schema"
    else
      ([$trusted.actors[] | select(.kind == "human" and (.id | type) == "number") | .id]) as $humans
      | ([$trusted.actors[] | .login | strings]) as $listed
      | ([$events[] | select((.name // "" | ascii_downcase) == "do-not-merge") | .created_at | strings] | sort | last) as $since
      | if $since == null then "no do-not-merge label event"
        else
          [$comments[] | select((.created_at // "") >= $since) | . as $c | ($c.body // "" | ownlines | select(test("^\\s*<!-- pr-hold"))) | {c: $c, line: .}] as $holds
          | if ($holds | length) == 0 then "no pr-hold reason line since the label was added"
            else
              first($holds[] | (.line | capture("^<!-- pr-hold reason=(?<r>[a-z0-9][a-z0-9-]{0,63}) -->$").r // null) as $r
                | if $r == null then "a pr-hold line with an unreadable reason"
                  elif $r != "eval" then "pr-hold reason=\($r)"
                  elif (.c as $c | ($c.type == "User" and ($c.app | not) and any($humans[]; . == $c.id))
                    or ($app != "" and $c.type == "Bot" and $c.login == $app and any($listed[]; . == $app))) | not
                  then "an eval hold line from an account that is not a listed human or the lanes App"
                  else empty end) // "eval"
            end
        end
    end') || {
    echo "its hold reason could not be parsed"
    return 1
  }
  verdict=${verdict//$'\r'/}
  [[ "$verdict" == eval ]] && return 0
  printf '%s\n' "${verdict//[[:cntrl:]]/}"
  return 1
}

reasons=$(jq -r --argjson unattended "$UNATTENDED" '
  (if $unattended then (.body // "" | [scan("(?mi)^[ \\t>]*Draft:[ \\t]*[^\\r\\n]*")] | first // empty | "draft: a person asked for this draft (\(gsub("[[:cntrl:]]"; ""))); only a person flips it") else empty end),
  (.body // "" | gsub("(?mi)^[ \\t>]*Hold:[^\\r\\n]*"; "") | if test("\\bdo(?:n['"'"'\u2019]?t| not)\\s+merge\\b"; "i") then "body: it says do not merge" else empty end),
  (.title // "" | if test("^\\s*(?:[a-z]+(?:\\([^)]*\\))?!?:\\s*)?wip\\b|[\\[(]wip[\\])]"; "i") then "title: a WIP marker in \"\(gsub("[[:cntrl:]]"; ""))\"" else empty end)
' <<<"$facts") || die 2 "cannot parse the pull request facts"

labeled=$(jq -r '[.labels[]?.name | strings | select(ascii_downcase == "do-not-merge")] | length' <<<"$facts") ||
  die 2 "cannot parse the pull request labels"
if [[ "${labeled//$'\r'/}" != 0 ]]; then
  if why=$(eval_only_hold); then
    printf 'check-ready-holds: do-not-merge is an eval hold, which holds the merge only, not the flip\n' >&2
  else
    reasons="label: the pull request carries do-not-merge (not an eval-only hold: ${why})${reasons:+$'\n'}${reasons}"
  fi
fi

refs=$(jq -r '.closingIssuesReferences[]? | [(.url | capture("^https?://(?<h>[^/]+)/").h), "\(.repository.owner.login)/\(.repository.name)", (.number | tostring)] | @tsv' <<<"$facts") ||
  die 2 "cannot parse the closing issue references"
refs=${refs//$'\r'/}

while IFS=$'\t' read -r host path num; do
  [[ -n "$num" ]] || continue
  state=$(gh api --hostname "$host" "repos/$path/issues/$num" --jq .state | tr -d '\r') ||
    die 2 "cannot read the state of $path#$num"
  [[ "$state" == closed ]] && reasons+="${reasons:+$'\n'}superseded: it closes $path#$num, which is already closed"
done <<<"$refs"

[[ -z "$reasons" ]] && exit 0
printf '%s\n' "$reasons"
exit 3
