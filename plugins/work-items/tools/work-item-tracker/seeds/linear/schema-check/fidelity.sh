#!/usr/bin/env bash
# Prove the operation strings fed to validate.mjs are the adapter's own text, not a
# paraphrase. Extracts each op from the SOURCE, whitespace-normalizes both sides, diffs.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
A="$(cd "$HERE/.." && pwd)"
C="$(cd "$HERE/../../../conformance/bindings" && pwd)"

norm() { tr '\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//'; }

FIELDS="$(sed -n "/^readonly WIT_LINEAR_ISSUE_FIELDS='/,/^'$/p" "$A/common.sh" |
  sed "1s/^readonly WIT_LINEAR_ISSUE_FIELDS='//; \$s/^'$//")"
echo "--- WIT_LINEAR_ISSUE_FIELDS as extracted from common.sh ---"
printf '%s\n' "$FIELDS"
echo

declare -a LITERALS=(
  "$A/common.sh|query { viewer { id displayName email } }"
  "$A/common.sh|mutation(\$input: CommentCreateInput!) { commentCreate(input: \$input) { success comment { id createdAt } } }"
  "$A/common.sh|mutation(\$id: String!, \$input: CommentUpdateInput!) { commentUpdate(id: \$id, input: \$input) { success } }"
  "$A/common.sh|mutation(\$id: String!, \$input: IssueUpdateInput!) { issueUpdate(id: \$id, input: \$input) { success } }"
  "$A/create-item.sh|query(\$key: String!) { teams(filter: { key: { eq: \$key } }, first: 1) { nodes { id } } }"
  "$A/create-item.sh|mutation(\$input: IssueCreateInput!) { issueCreate(input: \$input) { success issue { id number team { key } } } }"
  "$A/create-item.sh|mutation(\$input: IssueRelationCreateInput!) { issueRelationCreate(input: \$input) { success } }"
  "$A/add-sub-item.sh|mutation(\$id: String!, \$input: IssueUpdateInput!) { issueUpdate(id: \$id, input: \$input) { success } }"
  "$A/link-blocks.sh|mutation(\$input: IssueRelationCreateInput!) { issueRelationCreate(input: \$input) { success } }"
  "$C/linear.sh|query(\$t: String!, \$a: String) { issues(filter: { team: { key: { eq: \$t } } }, first: 50, after: \$a) { nodes { id } pageInfo { hasNextPage endCursor } } }"
  "$C/linear.sh|mutation(\$id: String!) { issueArchive(id: \$id) { success } }"
)
ok=0
bad=0
V="$HERE/validate.mjs"
for e in "${LITERALS[@]}"; do
  f="${e%%|*}"
  lit="${e#*|}"
  in_src=0
  in_val=0
  grep -qF -- "$lit" "$f" && in_src=1
  grep -qF -- "$lit" "$V" && in_val=1
  if ((in_src && in_val)); then
    ok=$((ok + 1))
    echo "VERBATIM  $(basename "$f"): ${lit:0:64}..."
  else
    bad=$((bad + 1))
    ((in_src)) || echo "MISMATCH  not in adapter source $(basename "$f"): $lit"
    ((in_val)) || echo "MISMATCH  not in validate.mjs (so it was never the operation validated): $lit"
  fi
done

unesc() { sed 's/\\\$/$/g'; }
V_NORM="$(unesc <"$V" | norm)"

declare -a MULTILINE=(
  "$A/common.sh|issues(filter: { team: { key: { eq: \$team } }, number: { eq: \$num } }, first: 1)"
  "$A/list-items.sh|query(\$filter: IssueFilter!, \$first: Int!, \$after: String) { issues(filter: \$filter, first: \$first, after: \$after)"
  "$A/list-sub-items.sh|children(first: \$first, after: \$after)"
  "$A/create-item.sh|issueLabels("
  "$A/create-item.sh|filter: { or: [{ team: { id: { eq: \$team } } }, { team: { null: true } }] }"
)
for e in "${MULTILINE[@]}"; do
  f="${e%%|*}"
  lit="${e#*|}"
  in_src=0
  in_val=0
  needle="$(printf '%s' "$lit" | unesc | norm)"
  grep -qF -- "$needle" < <(unesc <"$f" | norm) && in_src=1
  grep -qF -- "$needle" <<<"$V_NORM" && in_val=1
  if ((in_src && in_val)); then
    ok=$((ok + 1))
    echo "VERBATIM  $(basename "$f") [multi-line]: ${lit:0:56}..."
  else
    bad=$((bad + 1))
    ((in_src)) || echo "MISMATCH  not in adapter source $(basename "$f") [multi-line]: $lit"
    ((in_val)) || echo "MISMATCH  not in validate.mjs [multi-line]: $lit"
  fi
done

fields_needle="$(printf '%s' "$FIELDS" | unesc | norm)"
if [[ -z "$fields_needle" ]]; then
  bad=$((bad + 1))
  echo "MISMATCH  WIT_LINEAR_ISSUE_FIELDS could not be extracted from common.sh"
elif grep -qF -- "$fields_needle" <<<"$V_NORM"; then
  ok=$((ok + 1))
  echo "VERBATIM  WIT_LINEAR_ISSUE_FIELDS [shared field selection]: ${fields_needle:0:56}..."
else
  bad=$((bad + 1))
  echo "MISMATCH  WIT_LINEAR_ISSUE_FIELDS differs between common.sh and validate.mjs's F"
fi

echo
echo "operations found verbatim on BOTH sides: $ok  mismatched: $bad"
((bad == 0)) || exit 1
