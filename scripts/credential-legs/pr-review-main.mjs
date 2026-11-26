const COMMENTED = [
  "Record the main commit",
  "Check upstream status",
  "Check the trigger",
  "Select a lane-source pull request",
  "Note the hold",
  "Take the gate's result",
  "Write the diff",
  "Download the shared trusted PR text",
  "Copy the review criteria",
  "Check the credential",
  "Apply the Claude managed settings",
  "Write the prompt and schema",
  "Review chunk 1",
  "Pick the next leg",
  "Hand the lane on",
  "Write the verdict",
  "Record a failed chunk",
  "Keep the lane hold marker",
  "Fail without a verdict",
];
const KEY_CALL = `          leg: key
          role: reviews
          credential-set: \${{ secrets.REVIEWS_CLAUDE_API_KEY != '' }}
          key-off: \${{ vars.CLAUDE_API_KEYS_DISABLED == 'true' }}`;
const API_KEY = "          api-key: ${{ secrets.REVIEWS_CLAUDE_API_KEY }}";
const HANDOFF = /^ {10}handoff: \$\{\{ steps\.review-(?:1|chunks)\.outputs\.handoff \}\}$/gm;
const FALLBACK_REASON = "          fallback-reason: ${{ steps.credential.outputs.fallback-reason }}";

const leg = (suffix, route, { drop = [], comments = {}, replace }) => ({
  job: `review-${suffix.toLowerCase()}`,
  drop: ["Resolve main's tip", ...drop],
  comments: { ...Object.fromEntries(COMMENTED.map((name) => [name, true])), ...comments },
  replace: [
    [
      "  review:\n    name: Review\n    needs: [check-trigger, review-handoffs-credit, collect-trusted-text]\n",
      `  review-${suffix.toLowerCase()}:\n    name: Review ${suffix}\n    needs: [collect-trusted-text, ${route}]\n`,
      1,
    ],
    [
      "      needs.review-handoffs-credit.outputs.next-leg != 'subscription'\n      && !cancelled()\n      && needs.check-trigger.result == 'success'\n",
      `      !cancelled()\n      && needs.${route}.result == 'success'\n`,
      1,
    ],
    [
      "      && (needs.check-trigger.outputs.run-attempt != github.run_attempt\n      || needs.check-trigger.outputs.review != 'false' && needs.check-trigger.outputs.judged != 'true' && needs.check-trigger.outputs.held != 'true')\n",
      "",
      1,
    ],
    [/^ {6}matrix:\n {8}include:\n(?: {10}.*\n)+/gm, `      matrix: \${{ fromJSON(needs.${route}.outputs.matrix) }}\n`, 1],
    [
      "          ref: ${{ steps.tip.outputs.sha }}\n",
      "          ref: ${{ matrix.base }}\n",
      1,
    ],
    [" && needs.check-trigger.outputs.run-attempt != github.run_attempt\n", "\n", 1],
    ["ref: ${{ needs.check-trigger.outputs.standards-sha }}", "ref: ${{ needs.collect-trusted-text.outputs.standards-sha }}", 1],
    [/^ {10}CARRIED: .*\n(?: {10}CARRIED_\w+: .*\n)+/gm, '          CARRIED: "false"\n', 1],
    ...replace,
  ],
});

export default {
  workflow: ".github/workflows/pr-review-main.yml",
  key: "review",
  legs: [
    leg("Subscription", "review-handoffs", {
      replace: [
        [
          KEY_CALL,
          `          leg: subscription
          role: reviews
          credential-set: \${{ secrets.REVIEWS_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          fallback-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ matrix.reason }}`,
          1,
        ],
        [API_KEY, "          subscription-token: ${{ secrets.REVIEWS_CLAUDE_CODE_OAUTH_TOKEN }}", 2],
        ['          leg-timeout-minutes: "15"', '          fallback-ready: ${{ steps.credential.outputs.fallback-ready }}\n          leg-timeout-minutes: "15"', 2],
        [HANDOFF, `$&\n${FALLBACK_REASON}`, 2],
      ],
    }),
    leg("Fallback", "collect-subscription-handoffs", {
      drop: ["Pick the next leg", "Hand the lane on"],
      replace: [
        [
          "    outputs:\n" +
            "      claude-review: ${{ steps.handoff.outputs.claude-review }}\n      claude-security-review: ${{ steps.handoff.outputs.claude-security-review }}\n" +
            "      claude-review-base-sha: ${{ steps.base.outputs.claude-review-base-sha }}\n      claude-security-review-base-sha: ${{ steps.base.outputs.claude-security-review-base-sha }}\n",
          "    outputs:\n",
          1,
        ],
        [
          KEY_CALL,
          `          leg: fallback
          role: reviews
          credential-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ matrix.reason }}`,
          1,
        ],
        [
          "\n      - name: Isolate the runner\n",
          `\n      - name: Warn that the fallback token reviews
        if: steps.credential.outputs.present == 'true'
        env:
          LANE: \${{ matrix.lane }}
          REASON: \${{ steps.credential.outputs.fallback-reason }}
        run: echo "::warning title=pr-review-main fallback::lane=$LANE reviews on FALLBACK_CLAUDE_CODE_OAUTH_TOKEN (reason=\${REASON:-unread}); the subscription leg handed it on"

      - name: Isolate the runner\n`,
          1,
        ],
        [API_KEY, "          fallback-token: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}", 2],
        [HANDOFF, FALLBACK_REASON, 2],
        [" && steps.handoff.outcome != 'success'", "", 1],
      ],
    }),
  ],
};
