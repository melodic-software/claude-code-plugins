export default {
  workflow: ".github/workflows/maintenance-measure-skill-edit-pass.yml",
  key: "run-eval",
  legs: [
    {
      job: "run-eval-subscription",
      drop: ["Write the key's credit-stop marker", "Scan the key's credit-stop marker for credentials", "Upload the key's credit-stop marker", "Pick the next leg"],
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
    needs: run-eval
    if: >-
      \${{ !cancelled() && vars.CLAUDE_EVALS_DISABLED == 'false' && inputs.allow-subscription
      && needs.run-eval.result == 'success' && needs.run-eval.outputs.next-leg == 'subscription' }}
`,
          1,
        ],
        ["      next-leg: ${{ steps.next.outputs.next-leg }}\n      next-reason: ${{ steps.next.outputs.next-reason }}\n", "", 1],
        [
          `          leg: key
          role: evals
          credential-set: \${{ secrets.EVALS_CLAUDE_API_KEY != '' }}
          selected: \${{ needs.check-key-credit.outputs.next-leg }}
          key-off: \${{ vars.CLAUDE_API_KEYS_DISABLED == 'true' }}
`,
          `          leg: subscription
          role: evals
          credential-set: \${{ secrets.EVALS_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ needs.run-eval.outputs.next-reason }}
`,
          1,
        ],
        ["          LANE_API_KEY: ${{ secrets.EVALS_CLAUDE_API_KEY }}\n", "          CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.EVALS_CLAUDE_CODE_OAUTH_TOKEN }}\n", 2],
        ["          LEG: key\n          FALLBACK_READY: ${{ steps.credential.outputs.fallback-ready }}\n", '          LEG: subscription\n          FALLBACK_READY: "true"\n', 2],
        ["          credential: EVALS_CLAUDE_API_KEY\n", "          credential: EVALS_CLAUDE_CODE_OAUTH_TOKEN\n", 1],
        ['          fallback-reason: ""\n', "          fallback-reason: ${{ steps.credential.outputs.fallback-reason }}\n", 1],
        ["      - name: Stop at the key's stop\n", "      - name: Stop at the token's stop\n", 1],
        [
          "          REASON: ${{ steps.judge.outputs.handoff-reason || needs.check-key-credit.outputs.next-reason || 'no-key' }}\n          NEXT: ${{ inputs.allow-subscription && steps.next.outputs.next-leg || '' }}\n",
          "          REASON: ${{ steps.judge.outputs.handoff-reason || 'no-token' }}\n          KEY_REASON: ${{ needs.run-eval.outputs.next-reason }}\n",
          1,
        ],
        [
          `          if [ "$NEXT" = subscription ]; then
            echo "::notice::EVALS_CLAUDE_API_KEY stopped ($REASON), so the subscription leg runs the pass"
            exit 0
          fi
          echo "::error::EVALS credentials not assigned or used up: EVALS_CLAUDE_API_KEY stopped ($REASON) and this pass may not move to the subscription token, so it ran no case; reassign the EVALS role through the account rotation tool (docs/review/evals.md)"
`,
          `          echo "::error::EVALS credentials not assigned or used up: EVALS_CLAUDE_API_KEY stopped ($KEY_REASON) and EVALS_CLAUDE_CODE_OAUTH_TOKEN stopped ($REASON), so the pass uploads no result; no fallback leg runs, so reassign the EVALS role through the account rotation tool (docs/review/evals.md)"
`,
          1,
        ],
      ],
    },
  ],
};
