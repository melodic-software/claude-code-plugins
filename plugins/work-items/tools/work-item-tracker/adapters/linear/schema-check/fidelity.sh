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
V="$HERE/validate.mjs"
for e in "${LITERALS[@]}"; do
  f="${e%%|*}"
  lit="${e#*|}"
  # BOTH ends, not one. Checking only that the literal is in the adapter proves nothing about
  # what validate.mjs actually validated: it could hold a different — and still schema-valid —
  # query, and both scripts would stay green while the adapter's real request went unchecked.
  # The guarantee this script claims is "the thing validated IS the thing sent", which needs
  # the literal to appear on both sides.
  in_src=0
  in_val=0
  grep -qF -- "$lit" "$f" && in_src=1
  grep -qF -- "$lit" "$V" && in_val=1
  if ((in_src && in_val)); then
    ok=$((ok + 1))
    echo "VERBATIM  $(basename "$f"): ${lit:0:64}..."
  else
    bad=$((bad + 1))
    if ((!in_src)); then
      echo "MISMATCH  not in adapter source $(basename "$f"): $lit"
    fi
    if ((!in_val)); then
      echo "MISMATCH  not in validate.mjs (so it was never the operation validated): $lit"
    fi
  fi
done

# The multi-line operations. These are the ones an eyeball skips, so they are checked by
# whitespace-normalized containment rather than left to the printout above.
# The adapter builds these inside double-quoted shell strings, so its `$` sigils are written
# `\$` in the file while validate.mjs holds them bare. Strip that one escape before comparing,
# or every multi-line entry mismatches on punctuation rather than on substance.
unesc() { sed 's/\\\$/$/g'; }

declare -a MULTILINE=(
  "$A/common.sh|validate.mjs|issues(filter: { team: { key: { eq: \$team } }, number: { eq: \$num } }, first: 1)"
  "$A/list-items.sh|validate.mjs|issues(filter: { team: { key: { in: \$teams } } }, first: \$first, after: \$after)"
  "$A/list-sub-items.sh|validate.mjs|children(first: \$first, after: \$after)"
  "$A/create-item.sh|validate.mjs|issueLabels("
  "$A/create-item.sh|validate.mjs|filter: { or: [{ team: { id: { eq: \$team } } }, { team: { null: true } }] }"
)
for e in "${MULTILINE[@]}"; do
  f="${e%%|*}"
  rest="${e#*|}"
  lit="${rest#*|}"
  in_src=0
  in_val=0
  needle="$(printf '%s' "$lit" | unesc | norm)"
  unesc <"$f" | norm | grep -qF -- "$needle" && in_src=1
  unesc <"$V" | norm | grep -qF -- "$needle" && in_val=1
  if ((in_src && in_val)); then
    ok=$((ok + 1))
    echo "VERBATIM  $(basename "$f") [multi-line]: ${lit:0:56}..."
  else
    bad=$((bad + 1))
    ((in_src)) || echo "MISMATCH  not in adapter source $(basename "$f") [multi-line]: $lit"
    ((in_val)) || echo "MISMATCH  not in validate.mjs [multi-line]: $lit"
  fi
done

echo
echo "operations found verbatim on BOTH sides: $ok  mismatched: $bad"
# Exit status, not just a printed count — a fidelity check that reports MISMATCH and exits 0
# is read as success by every caller, which is the whole failure this script exists to catch.
((bad == 0)) || exit 1
