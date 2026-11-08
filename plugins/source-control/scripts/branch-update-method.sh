#!/usr/bin/env bash
# Decides how one pull request branch takes its base: none, merge, rebase,
# delegate or hold. Pure: signals JSON on stdin, decision JSON on stdout, no
# network, no git. The rows below own every condition and their order; the
# reasoning for each is in ../reference/branch-update-criteria.md.
#
#   branch-update-method.sh <signals.json   print one decision
#   branch-update-method.sh --rows          print the row ids, in order
#
# Rows are evaluated top to bottom, first match. A row needing a signal that
# reads `unknown` does not match, except where a row tests for `unknown` itself.
#
# setting.applied is true exactly when `setting` is merge or rebase and the
# matched row is forceable: the method came from the setting, whether it changed
# the row's method or agreed with it. On every other row the setting has no
# effect and applied is false.
#
# Exit: 0 a decision was printed; 2 malformed input, usage error or jq missing,
# with nothing on stdout. A consumer treats exit 2 as `hold`.
set -uo pipefail

# shellcheck disable=SC2016 # False positive: each $name is a jq variable.
readonly PROGRAM='
def tri: ["yes", "no", "unknown"];

def domains: {
  setting: ["auto", "merge", "rebase"],
  behind: tri,
  conflict: tri,
  up_to_date_required: tri,
  base_change_needed: tri,
  native_stack: tri,
  managed_head: tri,
  rewrite: ["allowed", "blocked"],
  other_authors: tri,
  dependents: tri,
  base_merged: tri,
  human_review: tri,
  landing: ["squash", "keeps-commits", "unknown"]
};

def row($id; matches; $method; $forceable; $reason):
  {id: $id, matches: matches, method: $method, forceable: $forceable, reason: $reason};

def rows: [
  row("no-update-needed";
    .behind == "no" or (.conflict == "no" and .up_to_date_required == "no"
      and .base_change_needed == "no" and .native_stack == "no");
    "none"; false; "Nothing calls for updating this branch"),
  row("safety-unknown"; .managed_head == "unknown" or .native_stack == "unknown";
    "hold"; false; "Who owns the head or whether it is a stack member could not be read"),
  row("managed-head"; .managed_head == "yes";
    "delegate"; false; "A dependency manager owns this head"),
  row("native-stack"; .native_stack == "yes" and .rewrite == "allowed" and .other_authors == "no";
    "rebase"; false; "A native stack member updates by rebase"),
  row("native-stack-blocked"; .native_stack == "yes";
    "hold"; false; "A native stack member cannot be rewritten here"),
  row("shared-history"; [.other_authors, .dependents] | any(. == "yes" or . == "unknown");
    "merge"; false; "Others may have built on this head, or that could not be read"),
  row("no-rewrite"; .rewrite == "blocked";
    "merge"; false; "This head cannot be rewritten"),
  row("base-merged"; .base_merged == "yes" or .base_merged == "unknown";
    "merge"; false; "The head already holds a merge of the base, or that could not be read"),
  row("human-reviewed"; .human_review == "yes";
    "merge"; true; "A person reviewed the current commits"),
  row("squash-landing"; .landing == "squash";
    "merge"; true; "A squash landing keeps no branch shape on the base"),
  row("keeps-commits";
    .landing == "keeps-commits" and .other_authors == "no" and .dependents == "no" and .human_review == "no";
    "rebase"; true; "The landing keeps these commits and nobody else depends on them"),
  row("default-merge"; true;
    "merge"; true; "No row calls for a rewrite")
];

def fail($message): "branch-update-method.sh: \($message)\n" | halt_error(2);

def validated:
  if length != 1 or (.[0] | type) != "object" then fail("stdin must hold one JSON object") else .[0] end
  | . as $in
  | (domains | to_entries[]
      | select(.key as $key | .value | any(. == $in[$key]) | not)
      | fail("signal \(.key) must be one of \(.value | join(", ")), got \($in[.key] | tojson)")),
    (("head_sha", "setting_level")
      | select($in[.] | type != "string" or length == 0)
      | fail("signal \(.) must be a non-empty string")),
    $in;

def decide:
  first(rows[] | select(.matches)) as $row
  | (.setting != "auto" and $row.forceable) as $applied
  | . as $in
  | {
      method: (if $applied then .setting else $row.method end),
      rule: $row.id,
      reason: "\($row.reason)\(if $applied then "; pr_update_method forces \(.setting)" else "" end).",
      head_sha: .head_sha,
      setting: {value: .setting, level: .setting_level, applied: $applied},
      human_review: .human_review,
      unknown: [domains | keys_unsorted[] | select($in[.] == "unknown")]
    };

if $list then rows[].id else validated | decide end
'

command -v jq >/dev/null 2>&1 || {
  echo "branch-update-method.sh: jq not found on PATH" >&2
  exit 2
}

case "$*" in
  '') decision=$(jq -c -s --argjson list false "$PROGRAM") || exit 2 ;;
  --rows) decision=$(jq -r -n --argjson list true "$PROGRAM") || exit 2 ;;
  *)
    echo "usage: branch-update-method.sh [--rows] <signals.json" >&2
    exit 2
    ;;
esac
printf '%s\n' "$decision"
