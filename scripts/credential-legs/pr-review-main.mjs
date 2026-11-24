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
const HANDOFF = /^ {10}handoff: \$\{\{ steps\.review-\d\.outputs\.handoff \}\}$/gm;
const FALLBACK_REASON = "          # Why this leg ran, for its lane record.\n          fallback-reason: ${{ steps.credential.outputs.fallback-reason }}";

const leg = (suffix, route, { drop = [], comments = {}, replace }) => ({
  job: `review-${suffix.toLowerCase()}`,
  drop: ["Resolve main's tip", ...drop],
  comments: { ...Object.fromEntries(COMMENTED.map((name) => [name, true])), ...comments },
  replace: [
    [
      "  review:\n    name: Review\n    needs: [check-trigger, review-handoffs-credit, collect-trusted-text]\n",
      `  review-${suffix.toLowerCase()}:\n    name: Review ${suffix}\n    needs: [collect-trusted-text, ${route}]\n    # !cancelled(): the implicit success() also needs every ancestor, so one\n    # lane's failed leg would skip the other lane's next leg.\n`,
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
      "          # The tip when the run starts, never an older commit a re-run of an\n          # old run would bring back; later legs check out the commit this\n          # leg recorded.\n          ref: ${{ steps.tip.outputs.sha }}\n",
      "          # The main commit this lane's key leg checked out, passed on by the\n          # route job only as 40 hex characters.\n          ref: ${{ matrix.base }}\n",
      1,
    ],
    [" && needs.check-trigger.outputs.run-attempt != github.run_attempt\n", "\n", 1],
    ["ref: ${{ needs.check-trigger.outputs.standards-sha }}", "ref: ${{ needs.collect-trusted-text.outputs.standards-sha }}", 1],
    [/^ {10}# The check-trigger job's result, only from this run attempt\.\n {10}CARRIED: .*\n(?: {10}CARRIED_\w+: .*\n)+/gm, '          CARRIED: "false"\n', 1],
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
        [API_KEY, "          subscription-token: ${{ secrets.REVIEWS_CLAUDE_CODE_OAUTH_TOKEN }}", 4],
        ['          leg-timeout-minutes: "15"', '          fallback-ready: ${{ steps.credential.outputs.fallback-ready }}\n          leg-timeout-minutes: "15"', 4],
        [HANDOFF, `$&\n${FALLBACK_REASON}`, 4],
      ],
    }),
    leg("Fallback", "collect-subscription-handoffs", {
      drop: ["Pick the next leg", "Hand the lane on"],
      comments: {
        "Record the main commit": "The main commit this leg checked out, under the lane's own output\nname, as the earlier legs record it; no later leg reads it here.",
        "Fail without a verdict": "A reviewed pull request that left no verdict fails here, so the run\nshows it; the lane stays unbound either way.",
      },
      replace: [
        [
          "    # One output per lane, since a matrix job's outputs merge: why the lane\n    # was handed to the next leg (empty when it was not), the main commit\n    # this leg checked out, and the designed stop with the head it names.\n    outputs:\n" +
            "      claude-review: ${{ steps.handoff.outputs.claude-review }}\n      claude-security-review: ${{ steps.handoff.outputs.claude-security-review }}\n" +
            "      claude-review-base-sha: ${{ steps.base.outputs.claude-review-base-sha }}\n      claude-security-review-base-sha: ${{ steps.base.outputs.claude-security-review-base-sha }}\n",
          "    # One output per lane, since a matrix job's outputs merge: the designed\n    # stop that left the lane without a verdict, and the head it names.\n    outputs:\n",
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
        [API_KEY, "          fallback-token: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}", 4],
        [HANDOFF, FALLBACK_REASON, 4],
        [" && steps.handoff.outcome != 'success'", "", 1],
      ],
    }),
  ],
};
