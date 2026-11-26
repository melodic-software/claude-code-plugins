export default {
  workflow: ".github/workflows/pr-run-plugin-evals.yml",
  key: "run-eval",
  legs: [
    {
      job: "run-eval-subscription",
      drop: ["Write the key's credit-stop marker", "Scan the key's credit-stop marker for credentials", "Upload the key's credit-stop marker", "Pick the next leg"],
      replace: [
        [
          `  run-eval:
    name: Run Eval
    needs: check-key-credit
    if: >-
      \${{ !cancelled() && needs.check-key-credit.result == 'success' && ((github.event_name == 'workflow_dispatch'
      && github.ref == format('refs/heads/{0}', github.event.repository.default_branch))
      || (github.event_name == 'workflow_run'
      && github.event.workflow_run.event == 'pull_request'
      && github.event.workflow_run.conclusion == 'success'
      && github.event.workflow_run.head_repository.full_name == github.repository)) }}
`,
          `  run-eval-subscription:
    name: Run Eval Subscription
    needs: run-eval
    if: >-
      \${{ !cancelled() && vars.CLAUDE_EVALS_DISABLED == 'false' && github.event_name == 'workflow_dispatch'
      && inputs.mode != 'compare' && needs.run-eval.result == 'success' && needs.run-eval.outputs.next-leg == 'subscription' }}
`,
          1,
        ],
        [
          `    permissions:
      contents: read # check out the repository; nothing in this job writes
      pull-requests: read # check-trusted-trigger reads the pull request
      issues: read # check-label-sender.sh reads https://docs.github.com/en/rest/issues/events
      actions: read # check-trusted-trigger reads this run's re-runner
    outputs:
      next-leg: \${{ steps.next.outputs.next-leg }}
      next-reason: \${{ steps.next.outputs.next-reason }}
`,
          `    permissions:
      contents: read
`,
          1,
        ],
        [
          `    steps:
      - name: Resolve main's tip
`,
          `    steps:
      - name: Refuse a run off the default branch or without a case filter
        env:
          REF: \${{ github.ref }}
          DEFAULT_BRANCH: \${{ github.event.repository.default_branch }}
          CASE: \${{ inputs.case }}
          CASES: \${{ inputs.cases }}
          TAGS: \${{ inputs.tag }}
        run: |
          if [ "$REF" != "refs/heads/$DEFAULT_BRANCH" ]; then
            echo "::error::the subscription token runs a suite only when dispatched on the default branch; no case runs"
            exit 1
          fi
          read -ra cases <<<"$CASES"
          read -ra tags <<<"$TAGS"
          if [ -z "\${CASE//[*?[:space:]]/}" ] && [ "\${#cases[@]}" -eq 0 ] && [ "\${#tags[@]}" -eq 0 ]; then
            echo "::error::a suite run on the subscription token must name case, cases or tag, never the whole suite; no case runs"
            exit 1
          fi

      - name: Resolve main's tip
`,
          1,
        ],
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
          "          REASON: ${{ steps.judge.outputs.handoff-reason || needs.check-key-credit.outputs.next-reason || 'no-key' }}\n          EVENT: ${{ github.event_name }}\n          NEXT: ${{ steps.next.outputs.next-leg }}\n          CASE: ${{ inputs.case }}\n          CASES: ${{ inputs.cases }}\n          TAGS: ${{ inputs.tag }}\n",
          "          REASON: ${{ steps.judge.outputs.handoff-reason || 'no-token' }}\n          KEY_REASON: ${{ needs.run-eval.outputs.next-reason }}\n",
          1,
        ],
        [
          `          if [ "$EVENT" != workflow_dispatch ]; then
            echo "::warning::EVALS_CLAUDE_API_KEY stopped ($REASON), so no case ran; a pull request run never moves to the subscription token (docs/review/evals.md)"
            exit 0
          fi
          read -ra cases <<<"$CASES"
          read -ra tags <<<"$TAGS"
          if [ "$NEXT" = subscription ] && [ -z "\${CASE//[*?[:space:]]/}" ] && [ "\${#cases[@]}" -eq 0 ] && [ "\${#tags[@]}" -eq 0 ]; then
            echo "::error::EVALS credentials not assigned or used up: EVALS_CLAUDE_API_KEY stopped ($REASON), and the EVALS subscription token runs only a suite that names case, cases or tag, so no case ran; name the cases, or reassign the EVALS key through the account rotation tool (docs/review/evals.md)"
            exit 1
          fi
          if [ "$NEXT" = subscription ]; then
            echo "::notice::EVALS_CLAUDE_API_KEY stopped ($REASON), so the subscription leg runs the suite"
            exit 0
          fi
          echo "::error::EVALS credentials not assigned or used up: EVALS_CLAUDE_API_KEY stopped ($REASON), so no case ran; reassign the EVALS role through the account rotation tool (docs/review/evals.md)"
`,
          `          echo "::error::EVALS credentials not assigned or used up: EVALS_CLAUDE_API_KEY stopped ($KEY_REASON) and EVALS_CLAUDE_CODE_OAUTH_TOKEN stopped ($REASON), so no case ran; no fallback leg runs, so reassign the EVALS role through the account rotation tool (docs/review/evals.md)"
`,
          1,
        ],
      ],
    },
  ],
};
