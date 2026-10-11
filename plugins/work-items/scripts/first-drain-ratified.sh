#!/usr/bin/env bash
# first-drain-ratified.sh — report whether an operator has ratified a work-loop's
# first drain, the state that lifts the first-drain C3 ratification gate.
#
# The gate must come from a source the lane cannot write. The lane's own telemetry
# comment is lane-writable, so the source is a label on the lane's telemetry
# issue, applied by a person. This script reads the label and who applied it.
#
# Usage:
#   first-drain-ratified.sh --repo <owner/name> --issue <n>
#
#   --repo    Target repository, owner/name.
#   --issue   The lane's telemetry issue number.
#   --help
#
# RATIFIED means the issue carries the label `loop-lane: first-drain-ratified`
# AND the most recent `labeled` or `unlabeled` event for it is a `labeled` event
# whose actor is of type `User` and was not acting through a GitHub App. A label
# a Bot or an App applied does not count, so a lane running under an App token
# cannot ratify itself. Any user token with triage access still counts: a lane
# sharing its operator's token, or other automation holding a user token, is
# indistinguishable from a person here, and only the lane's rule never to apply
# this label protects that setup.
#
# Exit codes. Only 0 lifts the gate; the caller treats every other code as
# "not ratified" (fail closed).
#
#   0   ratified
#   1   not ratified: the label is absent, its last event is not an
#       application, or a Bot or App applied it (the reason is on stderr)
#   2   usage: a missing, repeated, or unknown argument
#   6   --repo is not owner/name
#   7   --issue is not a positive integer
#   8   prerequisite missing: gh or jq is not on PATH
#   11  a read failed or returned unparsable JSON

set -uo pipefail

LABEL="loop-lane: first-drain-ratified"

err() { printf 'first-drain: %s\n' "$*" >&2; }
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

REPO=""
ISSUE=""
while (($#)); do
  case "$1" in
  --repo | --issue)
    (($# >= 2)) || {
      err "$1 requires a value"
      exit 2
    }
    if [[ "$1" == --repo ]]; then REPO="$2"; else ISSUE="$2"; fi
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

if [[ ! "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ || "/$REPO/" =~ /\.+/ ]]; then
  err "--repo must be owner/name (got: '$REPO')"
  exit 6
fi
if [[ ! "$ISSUE" =~ ^[0-9]+$ ]]; then
  err "--issue must be a positive integer (got: '$ISSUE')"
  exit 7
fi
for bin in gh jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    err "$bin not found (required)"
    exit 8
  }
done

issue="$(gh api "repos/$REPO/issues/$ISSUE" 2>/dev/null)" || {
  err "issue read failed; not ratified (fail closed)"
  exit 11
}
has="$(jq -r --arg l "$LABEL" '[.labels[]?.name] | index($l) != null' <<<"$issue" 2>/dev/null)" || {
  err "issue read was unparsable; not ratified (fail closed)"
  exit 11
}
if [[ "$has" != "true" ]]; then
  err "label '$LABEL' is absent; not ratified"
  exit 1
fi

# `--paginate` emits one array per page; `-s add` joins them so `last` is the
# most recent event across every page.
events="$(gh api --paginate "repos/$REPO/issues/$ISSUE/events?per_page=100" 2>/dev/null)" || {
  err "event read failed; not ratified (fail closed)"
  exit 11
}
# The last labeled-or-unlabeled event decides, so a label that reappears without
# a fresh application (a rename onto this name) never revives an old one.
last="$(jq -rs --arg l "$LABEL" \
  'add // [] | map(select((.event == "labeled" or .event == "unlabeled") and .label.name == $l)) | last // {}
   | "\(.event // "")|\(.actor.type // "")|\(if .performed_via_github_app == null then "" else "app" end)|\(.actor.login // "")"' \
  <<<"$events" 2>/dev/null)" || {
  err "event read was unparsable; not ratified (fail closed)"
  exit 11
}
# `|` cannot occur in any field and, unlike a tab, does not collapse empty fields.
IFS='|' read -r event type via login <<<"$last"
if [[ "$event" != "labeled" ]]; then
  err "label '$LABEL' has no applying event after its last removal; not ratified"
  exit 1
fi
if [[ "$type" != "User" || -n "$via" ]]; then
  err "label '$LABEL' was applied by '${login:-unknown}' (type '${type:-none}'${via:+, via a GitHub App}), not a person; not ratified"
  exit 1
fi

printf 'first-drain: ratified on %s#%s by %s\n' "$REPO" "$ISSUE" "$login"
exit 0
