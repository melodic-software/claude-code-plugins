#!/usr/bin/env bash
# Prove the operation strings fed to validate.mjs are the adapter's own text, not a
# paraphrase. Extracts each op from the SOURCE, whitespace-normalizes both sides, diffs.
set -uo pipefail
# Resolved from this script's own location so the check runs in any checkout, not just the
# one it was written in.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
A="$(cd "$HERE/.." && pwd)"
C="$(cd "$HERE/../../../conformance/bindings" && pwd)"

norm() { tr '\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//'; }

# Pull the real WIT_LINEAR_ISSUE_FIELDS out of common.sh by executing just that assignment.
FIELDS="$(sed -n "/^readonly WIT_LINEAR_ISSUE_FIELDS='/,/^'$/p" "$A/common.sh" |
  sed "s/^readonly WIT_LINEAR_ISSUE_FIELDS=//" | sed "1s/^'//; \$s/^'$//")"
echo "--- WIT_LINEAR_ISSUE_FIELDS as extracted from common.sh ---"
printf '%s\n' "$FIELDS"
echo "--- normalized ---"
printf '%s' "$FIELDS" | norm
echo
echo

# Every single-line operation literal must appear VERBATIM (fixed-string) in its source.
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
for e in "${LITERALS[@]}"; do
  f="${e%%|*}"
  lit="${e#*|}"
  if grep -qF -- "$lit" "$f"; then
    ok=$((ok + 1))
    echo "VERBATIM  $(basename "$f"): ${lit:0:64}..."
  else
    bad=$((bad + 1))
    echo "MISMATCH  $(basename "$f"): $lit"
  fi
done
echo
echo "single-line operations found verbatim in source: $ok  mismatched: $bad"
