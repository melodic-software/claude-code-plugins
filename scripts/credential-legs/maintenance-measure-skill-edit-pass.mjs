export default {
  workflow: ".github/workflows/maintenance-measure-skill-edit-pass.yml",
  key: "run-eval",
  legs: [
    {
      job: "run-eval-subscription",
      drop: ["Write the key's credit-stop marker", "Scan the key's credit-stop marker for credentials", "Upload the key's credit-stop marker"],
      replace: [
        ["      contents: read # check out the default branch; nothing in this job writes\n", "      contents: read\n", 1],
        [
          `  run-eval:
    name: Run Eval
    needs: check-key-credit
    if: \${{ !cancelled() && needs.check-key-credit.result == 'success' }}
`,
          `  run-eval-subscription:
    name: Run Eval Subscription
    if: vars.CLAUDE_EVALS_DISABLED == 'false' && inputs.credential == 'subscription'
`,
          1,
        ],
        [
          `          leg: key
          role: maintenance
          credential-set: \${{ secrets.MAINTENANCE_CLAUDE_API_KEY != '' }}
          selected: \${{ needs.check-key-credit.outputs.next-leg }}
          key-off: \${{ vars.CLAUDE_API_KEYS_DISABLED == 'true' }}
`,
          `          leg: subscription
          role: maintenance
          credential-set: \${{ secrets.MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN != '' }}
`,
          1,
        ],
        ["          LANE_API_KEY: ${{ secrets.MAINTENANCE_CLAUDE_API_KEY }}\n", "          CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN }}\n", 2],
        ["          LEG: key\n          FALLBACK_READY: ${{ steps.credential.outputs.fallback-ready }}\n", '          LEG: subscription\n          FALLBACK_READY: "true"\n', 2],
        ["          credential: MAINTENANCE_CLAUDE_API_KEY\n", "          credential: MAINTENANCE_CLAUDE_CODE_OAUTH_TOKEN\n", 1],
        ["      - name: Stop at the key's stop\n", "      - name: Stop at the token's stop\n", 1],
        [
          "          REASON: ${{ steps.judge.outputs.handoff-reason || needs.check-key-credit.outputs.next-reason || 'no-key' }}\n",
          "          REASON: ${{ steps.judge.outputs.handoff-reason || 'no-token' }}\n",
          1,
        ],
        [
          `          echo "::error::The API key stopped ($REASON), so the pass ran no case; evals never fall back to subscription tokens (docs/review/evals.md)"\n`,
          `          echo "::error::The subscription token stopped ($REASON), so the pass uploads no result; no fallback leg runs (docs/review/evals.md)"\n`,
          1,
        ],
      ],
    },
  ],
};
