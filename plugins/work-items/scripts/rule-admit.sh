#!/usr/bin/env bash
# rule-admit.sh — evaluate the owner's C1/C2 admission rules for GitHub issues.
# No model runs here and nothing is written: the script reads each issue, its
# comments and its body edit time, and reports admit or refuse.
#
# The rules live in the security binding's `admission.rule_admission[]`; the
# autonomy plugin's admission-policy leaf ("Rule admission") owns their
# meaning, and this script implements it. Precedence, first hit decides:
# needs-human, trust-surface hit, an existing work-class label, then a rule
# match on the shared predicate. Issue text can only refuse.
#
# Usage:
#   rule-admit.sh --repo <owner/name> --binding <path> --issue <n> [--issue <n> ...]
#
#   --repo     Target repository, owner/name.
#   --binding  The resolved security binding document (agent-unwritable).
#   --issue    An issue number; repeat for more.
#   --help
#
# Output: one JSON object per issue, one per line:
#   {"issue": n, "verdict": "admit"|"refuse", "rule": "R1"|null,
#    "work_class": "C2"|null, "constraint": "human-merge"|null,
#    "proposed_class": string|null, "binding_sha": "<12 hex>", "reason": string}
# A failed read for one issue is a refuse row for it, never an admit. Only C2
# admits: a C1 rule refuses until a mechanical no-push exists.
#
# Exit codes. The caller admits only on an "admit" row from an exit-0 run.
#   0   every issue evaluated (rows printed)
#   2   usage: a missing, repeated, or unknown argument, or a malformed value
#   4   the binding is unreadable, its rule_admission is absent or malformed, its
#       dispatch_posture is not autonomous-enabled, or its decision table does not
#       make every rule's class autonomous-eligible
#   8   prerequisite missing: gh, jq or a SHA-256 tool is not on PATH

# portability-scope: the GitHub implementation of rule admission; every read is a gh call.
set -uo pipefail

MARKER="<!-- claude-lane intake-triage -->"

err() { printf 'rule-admit: %s\n' "$*" >&2; }
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

REPO="" BINDING=""
ISSUES=()
while (($#)); do
  case "$1" in
    --repo | --binding | --issue)
      (($# >= 2)) || {
        err "$1 requires a value"
        exit 2
      }
      case "$1" in
        --repo)
          [[ -z "$REPO" ]] || {
            err "--repo given twice"
            exit 2
          }
          REPO="$2"
          ;;
        --binding)
          [[ -z "$BINDING" ]] || {
            err "--binding given twice"
            exit 2
          }
          BINDING="$2"
          ;;
        *) ISSUES+=("$2") ;;
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

if [[ ! "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ || "/$REPO/" =~ /\.+/ ]]; then
  err "--repo must be owner/name (got: '$REPO')"
  exit 2
fi
[[ -n "$BINDING" ]] || {
  err "--binding is required"
  exit 2
}
((${#ISSUES[@]} > 0)) || {
  err "at least one --issue is required"
  exit 2
}
for n in "${ISSUES[@]}"; do
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || {
    err "--issue must be a positive integer (got: '$n')"
    exit 2
  }
done

for bin in gh jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    err "$bin not found (required)"
    exit 8
  }
done
if command -v sha256sum >/dev/null 2>&1; then
  sha_of() { sha256sum "$1"; }
elif command -v shasum >/dev/null 2>&1; then
  sha_of() { shasum -a 256 "$1"; }
else
  err "no SHA-256 tool found (sha256sum or shasum)"
  exit 8
fi

# The rules, re-checked here so a malformed binding admits nothing even when
# its validator never ran.
RULES="$(jq -ce '
  .admission.rule_admission
  | if type == "array" and length > 0
       and all(.[]; type == "object"
         and (keys - ["id", "proposed_class", "work_class"] | length == 0)
         and (.id | type == "string" and test("^R[1-9][0-9]*$"))
         and (.work_class == "C1" or .work_class == "C2")
         and (.proposed_class | type == "string" and test("^work-class: [a-z0-9-]+$")))
       and ([.[].id] | unique | length) == length
       and ([.[].proposed_class] | unique | length) == length
    then . else error("malformed") end' "$BINDING" 2>/dev/null)" || {
  err "binding '$BINDING' is unreadable, or its admission.rule_admission is absent or malformed; nothing is admitted by rule"
  exit 4
}

# A rule never admits past the binding's own gates: the dispatch posture must be
# autonomous-enabled, and the decision table must make each rule's class
# autonomous-eligible for an issue (tracker-vcs-event) under every provenance,
# since an agent files issues under the operator's token. Most specific rule
# wins; no match is human-gated; a tie with different dispositions is not eligible.
# shellcheck disable=SC2016 # jq program, not shell expansion
GATE="$(jq -r '. as $b
  | def spec: [.signal_class, .provenance, .work_class | select(. != "*")] | length;
    def disp($p; $w): [$b.admission.rules[] | select(type == "object"
        and (.signal_class == "*" or .signal_class == "tracker-vcs-event")
        and (.provenance == "*" or .provenance == $p) and (.work_class == "*" or .work_class == $w))]
      | if length == 0 then "human-gated"
        else (map(spec) | max) as $m | [.[] | select(spec == $m) | .disposition] | unique
          | if length == 1 then .[0] else "ambiguous" end end;
  if (.dispatch_posture // "autonomous-enabled") != "autonomous-enabled" then "dispatch_posture is \(.dispatch_posture)"
  elif (.admission.rules | type) != "array" then "admission.rules is absent or malformed"
  else [.admission.rule_admission[] as $r | ("human", "agent", "system") as $p
        | disp($p; $r.work_class) as $d | select($d != "autonomous-eligible")
        | "\($r.id) (\($r.work_class)) is \($d) in admission.rules for provenance \($p)"] | first // "" end' "$BINDING" 2>/dev/null)" ||
  GATE="the decision table could not be evaluated"
[[ -z "$GATE" ]] || {
  err "binding '$BINDING' does not allow rule admission: $GATE; nothing is admitted by rule"
  exit 4
}
SHA="$(sha_of "$BINDING" | cut -c1-12)"

# The evaluation. Inputs: $issue (REST issue), $comments (REST comments),
# $edited (GraphQL lastEditedAt, "" when never edited), $rules, $sha, $n.
# shellcheck disable=SC2016 # jq program, not shell expansion
EVAL='
def deny: "(\\.github|\\b(hooks?|guard(rail)?s?|permissions?|(allow|deny)[- ]?lists?|workflows?|rulesets?|codeowners|secrets?|tokens?|credentials?|pins?|pinned|pinning|sha(s|1|256)?|checksums?|admission|work-class(es)?|label-provenance|autonomy|security|merg(e|es|ed|ing)|sandbox(es|ed|ing)?|auto[- ]mode|bindings?|trust(ed|s|ing)?|ci)\\b)";
def cost: "\\b(billing|billed|spending[- ]limits?|subscriptions?|skus?|retention|(larger|hosted|self-hosted)[- ]runners?|macos minutes)\\b";
def row($verdict; $rule; $proposed; $reason):
  {issue: $n, verdict: $verdict, rule: ($rule.id // null), work_class: ($rule.work_class // null),
   constraint: (if $rule == null then null else "human-merge" end),
   proposed_class: (if $proposed == "" then null else $proposed end), binding_sha: $sha, reason: $reason};
def refuse($reason): row("refuse"; null; ""; $reason);
def trusted: . == "OWNER" or . == "MEMBER";
([$issue.labels[]? | .name // empty]) as $labels
| ([$comments[] | select(.user.login == "github-actions[bot]" and ((.body // "") | startswith($marker)))]) as $lane
| (if ($lane | length) == 1 then $lane[0] else null end) as $lc
| ((($lc.body // "") | split("\n") | .[1] // "") as $line
   | ($line | capture("^Proposed work class: (?<c>work-class: [a-z0-9-]+)$").c? // "")) as $proposed
| ((($issue.title // "") + "\n" + ($issue.body // "")) | [match(deny; "gi").string | ascii_downcase] | unique) as $hits
| ((($issue.title // "") + "\n" + ($issue.body // "")) | [match(cost; "gi").string | ascii_downcase] | unique) as $cost_hits
| ([$labels[] | select(. == "provenance: signal" or . == "area: security" or . == "do-not-merge" or . == "work-map"
     or startswith("status:") or startswith("wayfind:"))]) as $owner_step
| if $issue.pull_request != null then refuse("not an issue")
  elif $issue.state != "open" then refuse("issue is not open")
  elif ($labels | index("needs-human")) then refuse("needs-human present")
  elif ($labels | index("area: security")) then refuse("trust-surface hit: area: security label")
  elif ($hits | length) > 0 then refuse("trust-surface hit in title or body: " + ($hits | join(", ")))
  elif ($cost_hits | length) > 0 then refuse("cost hit in title or body: " + ($cost_hits | join(", ")) + "; a charge needs an owner decision")
  elif any($labels[]; startswith("work-class:")) then refuse("a work-class label is already present; left untouched")
  elif ($issue.author_association | trusted | not) then refuse("issue author association is " + ($issue.author_association // "unknown"))
  elif any($comments[]; ((.author_association // "") | trusted | not)
         and ((.user.login == "github-actions[bot]" and ((.body // "") | startswith($marker))) | not))
    then refuse("a comment is from an author who is neither OWNER nor MEMBER, nor the lane")
  elif ($lane | length) == 0 then refuse("no intake-triage lane comment")
  elif ($lane | length) > 1 then refuse("more than one intake-triage lane comment")
  elif ($lc.body | contains("Automated triage handed this issue to a maintainer.")) then refuse("the lane run escalated")
  elif $edited != "" and $edited > ($lc.updated_at // "") then refuse("issue body edited after the lane comment")
  elif ($owner_step | length) > 0 then refuse("an owner step remains: " + ($owner_step | join(", ")))
  elif $proposed == "" then refuse("the lane proposed no work class")
  else ([$rules[] | select(.proposed_class == $proposed)] | first) as $rule
    | if $rule == null then row("refuse"; null; $proposed; "no rule admits " + $proposed)
      elif $rule.work_class != "C2" then
        row("refuse"; null; $proposed; "C1 rule admission is not enabled (" + $rule.id + "): no mechanical no-push exists")
      else row("admit"; $rule; $proposed; "admitted-by-rule: " + $rule.id + "@" + $sha) end
  end'

refuse_row() { # $1 issue, $2 reason
  jq -nc --argjson n "$1" --arg sha "$SHA" --arg r "$2" \
    '{issue: $n, verdict: "refuse", rule: null, work_class: null, constraint: null, proposed_class: null, binding_sha: $sha, reason: $r}'
}

# Issue data goes through files: a long body or comment thread can exceed the
# argument-length limit.
TMP="$(mktemp -d)" || {
  err "mktemp failed"
  exit 8
}
trap 'rm -rf "$TMP"' EXIT

OWNER="${REPO%%/*}" NAME="${REPO#*/}"
for n in "${ISSUES[@]}"; do
  gh api "repos/$REPO/issues/$n" >"$TMP/issue.json" 2>/dev/null || {
    refuse_row "$n" "issue read failed"
    continue
  }
  { gh api --paginate "repos/$REPO/issues/$n/comments?per_page=100" 2>/dev/null || echo FAILED; } >"$TMP/pages.json"
  if grep -qx FAILED "$TMP/pages.json" || ! jq -cs 'add // []' "$TMP/pages.json" >"$TMP/comments.json" 2>/dev/null; then
    refuse_row "$n" "comment read failed"
    continue
  fi
  # shellcheck disable=SC2016 # GraphQL variables, not shell expansion
  edited="$(gh api graphql -F owner="$OWNER" -F name="$NAME" -F number="$n" \
    -f query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){issue(number:$number){lastEditedAt}}}' 2>/dev/null |
    jq -er '.data.repository.issue | if type == "object" then (.lastEditedAt // "") else error end' 2>/dev/null)" || {
    refuse_row "$n" "body edit-time read failed"
    continue
  }
  jq -nc --slurpfile i "$TMP/issue.json" --slurpfile c "$TMP/comments.json" --arg edited "$edited" \
    --argjson rules "$RULES" --arg sha "$SHA" --argjson n "$n" --arg marker "$MARKER" \
    '$i[0] as $issue | $c[0] as $comments | '"$EVAL" 2>/dev/null ||
    refuse_row "$n" "issue data was unparsable"
done
exit 0
