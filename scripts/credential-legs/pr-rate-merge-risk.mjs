const KEY_ONLY = [
  "Read the key's credit history",
  "Report the skipped key leg",
  "Write the key's credit-stop marker",
  "Scan the key's credit-stop marker for credentials",
  "Upload the key's credit-stop marker",
];
const MOVE = { "Check the credential": "Read the checker's model" };
const HEAD_REPO = "      && github.event.workflow_run.head_repository.full_name == github.repository\n";
const CREDENTIAL_CALL = `          credential-set: \${{ secrets.PR_VERIFY_CLAUDE_API_KEY != '' }}
          selected: \${{ steps.credit.outputs.next-leg }}
          key-off: \${{ vars.CLAUDE_API_KEYS_DISABLED == 'true' }}`;
const API_KEY = "          api-key: ${{ secrets.PR_VERIFY_CLAUDE_API_KEY }}\n";
const STANDARDS = "        uses: melodic-software/ci-workflows/.github/actions/download-standards@main\n";
const standardsFrom = (job) => [STANDARDS, `${STANDARDS}        with:\n          ref: \${{ needs.${job}.outputs.standards-sha }}\n`, 1];
const shared = (leg) => [
  ["    if: >-\n      github.ref", "    if: >-\n      !cancelled()\n      && github.ref", 1],
  ["if: steps.pr.outputs.proceed == 'true' && steps.credential.outputs.present == 'true'", "if: steps.pr.outputs.proceed == 'true'", 1],
  ["        id: credential\n        if: steps.pr.outputs.proceed == 'true'\n", "        id: credential\n        if: steps.checker.outcome == 'success'\n", 1],
  ["          leg: key\n", `          leg: ${leg}\n`, 1],
  ['          fallback-reason: ""', "          fallback-reason: ${{ steps.credential.outputs.fallback-reason }}", 1],
];

export default {
  workflow: ".github/workflows/pr-rate-merge-risk.yml",
  key: "rate-merge-risk",
  legs: [
    {
      job: "rate-merge-risk-subscription",
      drop: KEY_ONLY,
      move: MOVE,
      replace: [
        ["  rate-merge-risk:\n    name: Rate Merge Risk\n", "  rate-merge-risk-subscription:\n    name: Rate Merge Risk Subscription\n    needs: rate-merge-risk\n", 1],
        [HEAD_REPO, `${HEAD_REPO}      && needs.rate-merge-risk.result == 'success'\n      && needs.rate-merge-risk.outputs.next-leg == 'subscription'\n`, 1],
        ...shared("subscription"),
        standardsFrom("rate-merge-risk"),
        [
          CREDENTIAL_CALL,
          `          credential-set: \${{ secrets.PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          fallback-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ needs.rate-merge-risk.outputs.next-reason }}`,
          1,
        ],
        [API_KEY, "          subscription-token: ${{ secrets.PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN }}\n          fallback-ready: ${{ steps.credential.outputs.fallback-ready }}\n", 1],
      ],
    },
    {
      job: "rate-merge-risk-fallback",
      drop: [...KEY_ONLY, "Pick the next leg"],
      move: MOVE,
      replace: [
        ["  rate-merge-risk:\n    name: Rate Merge Risk\n", "  rate-merge-risk-fallback:\n    name: Rate Merge Risk Fallback\n    needs: rate-merge-risk-subscription\n", 1],
        [
          HEAD_REPO,
          `${HEAD_REPO}      && needs.rate-merge-risk-subscription.result == 'success'\n      && needs.rate-merge-risk-subscription.outputs.next-leg == 'fallback'\n`,
          1,
        ],
        ["    outputs:\n      next-leg: ${{ steps.next.outputs.next-leg }}\n      next-reason: ${{ steps.next.outputs.next-reason }}\n      standards-sha: ${{ steps.standards.outputs.sha }}\n", "", 1],
        ...shared("fallback"),
        standardsFrom("rate-merge-risk-subscription"),
        [
          CREDENTIAL_CALL,
          `          credential-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ needs.rate-merge-risk-subscription.outputs.next-reason }}`,
          1,
        ],
        [API_KEY, "          fallback-token: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}\n", 1],
      ],
    },
  ],
};
