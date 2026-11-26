const KEY_ONLY = ["Write the key's credit-stop marker", "Scan the key's credit-stop marker for credentials", "Upload the key's credit-stop marker"];
const HEADER = `  sweep-areas:
    name: Sweep Areas
    needs: select-areas
    if: needs.select-areas.outputs.proceed == 'true' && needs.select-areas.outputs.next-leg != 'subscription' && github.run_attempt == '1'
`;
const NEXT_OUTPUTS = "      next-leg: ${{ steps.next.outputs.next-leg }}\n      next-reason: ${{ steps.next.outputs.next-reason }}\n";
const CREDENTIAL_CALL = `          credential-set: \${{ secrets.AUTOMATIONS_CLAUDE_API_KEY != '' }}
          key-off: \${{ vars.CLAUDE_API_KEYS_DISABLED == 'true' }}`;
const API_KEY = "          api-key: ${{ secrets.AUTOMATIONS_CLAUDE_API_KEY }}\n";
const shared = (leg) => [
  ["          leg: key\n", `          leg: ${leg}\n`, 1],
  ['          fallback-reason: ""', "          fallback-reason: ${{ steps.credential.outputs.fallback-reason }}", 1],
  ["          JOB_ID: sweep-areas\n", `          JOB_ID: sweep-areas-${leg}\n`, 1],
];
const COMMENTS = {
  "Stage the plugin and the prompt": true,
  "Check out main with history": true,
  "Clear the trusted checkout path": true,
  "Record the leg": true,
  "Seal the plan and the branches": true,
};

export default {
  workflow: ".github/workflows/maintenance-tidy-code-upkeep.yml",
  key: "sweep-areas",
  legs: [
    {
      job: "sweep-areas-subscription",
      drop: KEY_ONLY,
      comments: {
        ...COMMENTS,
        "Pick the next leg": true,
      },
      replace: [
        [
          HEADER,
          `  sweep-areas-subscription:
    name: Sweep Areas Subscription
    needs: [select-areas, sweep-areas]
    if: >-
      \${{ !cancelled() && needs.select-areas.outputs.proceed == 'true' && github.run_attempt == '1'
      && (needs.sweep-areas.outputs.next-leg == 'subscription' || needs.select-areas.outputs.next-leg == 'subscription') }}
`,
          1,
        ],
        [
          NEXT_OUTPUTS,
          `${NEXT_OUTPUTS}      credential-present: \${{ steps.credential.outputs.present }}
`,
          1,
        ],
        ...shared("subscription"),
        [
          CREDENTIAL_CALL,
          `          credential-set: \${{ secrets.AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          fallback-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ needs.sweep-areas.outputs.next-reason || needs.select-areas.outputs.next-reason }}`,
          1,
        ],
        [API_KEY, "          subscription-token: ${{ secrets.AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN }}\n          fallback-ready: ${{ steps.credential.outputs.fallback-ready }}\n", 1],
        [
          `      - name: Report the key's handoff
        if: always() && steps.run.outputs.handoff == 'true'
        continue-on-error: true
        timeout-minutes: 1
        env:
          LANE_CLASS: \${{ steps.run.outputs.lane-class }}
        run: |
          case "$LANE_CLASS" in
            auth) line="the API refused AUTOMATIONS_CLAUDE_API_KEY (class auth); the owner must replace the secret, and sweep-areas-subscription sweeps on the subscription token" ;;
            *) line="AUTOMATIONS_CLAUDE_API_KEY hit a credit stop (class credit-stop); sweep-areas-subscription sweeps on the subscription token" ;;
          esac
          echo "::warning::$line"`,
          `      - name: Report the subscription's handoff
        if: always() && steps.run.outputs.handoff == 'true'
        continue-on-error: true
        timeout-minutes: 1
        env:
          HANDOFF_REASON: \${{ steps.run.outputs.handoff-reason }}
        run: |
          line="AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN handed off (\${HANDOFF_REASON:-unknown}); sweep-areas-fallback sweeps on FALLBACK_CLAUDE_CODE_OAUTH_TOKEN"
          echo "::notice::$line"`,
          1,
        ],
      ],
    },
    {
      job: "sweep-areas-fallback",
      drop: [...KEY_ONLY, "Report the key's handoff", "Pick the next leg"],
      comments: {
        ...COMMENTS,
      },
      replace: [
        [
          HEADER,
          `  sweep-areas-fallback:
    name: Sweep Areas Fallback
    needs: [select-areas, sweep-areas-subscription]
    if: >-
      \${{ !cancelled() && needs.select-areas.outputs.proceed == 'true' && github.run_attempt == '1'
      && (needs.sweep-areas-subscription.outputs.next-leg == 'fallback' || needs.sweep-areas-subscription.outputs.credential-present == 'false') }}
`,
          1,
        ],
        [NEXT_OUTPUTS, "", 1],
        ...shared("fallback"),
        [
          CREDENTIAL_CALL,
          `          credential-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ needs.sweep-areas-subscription.outputs.next-reason }}`,
          1,
        ],
        [API_KEY, "          fallback-token: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}\n", 1],
      ],
    },
  ],
};
