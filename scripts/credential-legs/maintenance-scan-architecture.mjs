const KEY_ONLY = ["Write the key's credit-stop marker", "Scan the key's credit-stop marker for credentials", "Upload the key's credit-stop marker"];
const HEADER = `  scan:
    name: Scan
    needs: gate
    if: needs.gate.outputs.run == 'true' && needs.gate.outputs.next-leg != 'subscription' && github.run_attempt == '1'
`;
const NEXT_OUTPUTS = "      next-leg: ${{ steps.next.outputs.next-leg }}\n      next-reason: ${{ steps.next.outputs.next-reason }}\n";
const CREDENTIAL_CALL = `          credential-set: \${{ secrets.AUTOMATIONS_CLAUDE_API_KEY != '' }}
          key-off: \${{ vars.CLAUDE_API_KEYS_DISABLED == 'true' }}`;
const API_KEY = "          api-key: ${{ secrets.AUTOMATIONS_CLAUDE_API_KEY }}\n";
const shared = (leg) => [
  ["          leg: key\n", `          leg: ${leg}\n`, 1],
  ['          fallback-reason: ""', "          fallback-reason: ${{ steps.credential.outputs.fallback-reason }}", 1],
  ["          JOB_ID: scan\n", `          JOB_ID: scan-${leg}\n`, 1],
];

export default {
  workflow: ".github/workflows/maintenance-scan-architecture.yml",
  key: "scan",
  legs: [
    {
      job: "scan-subscription",
      drop: KEY_ONLY,
      replace: [
        [
          HEADER,
          `  scan-subscription:
    name: Scan Subscription
    needs: [gate, scan]
    if: >-
      \${{ !cancelled() && needs.gate.outputs.run == 'true' && github.run_attempt == '1'
      && (needs.scan.outputs.next-leg == 'subscription' || needs.gate.outputs.next-leg == 'subscription') }}
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
          reason: \${{ needs.scan.outputs.next-reason || needs.gate.outputs.next-reason }}`,
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
            auth) line="the API refused AUTOMATIONS_CLAUDE_API_KEY (class auth); the owner must replace the secret, and scan-subscription scans on the subscription token" ;;
            *) line="AUTOMATIONS_CLAUDE_API_KEY hit a credit stop (class credit-stop); scan-subscription scans on the subscription token" ;;
          esac
          echo "::warning::$line"`,
          `      - name: Report the subscription's handoff
        if: always() && steps.run.outputs.handoff == 'true'
        continue-on-error: true
        timeout-minutes: 1
        env:
          HANDOFF_REASON: \${{ steps.run.outputs.handoff-reason }}
        run: |
          line="AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN handed off (\${HANDOFF_REASON:-unknown}); scan-fallback scans on FALLBACK_CLAUDE_CODE_OAUTH_TOKEN"
          echo "::notice::$line"`,
          1,
        ],
      ],
    },
    {
      job: "scan-fallback",
      drop: [...KEY_ONLY, "Report the key's handoff", "Pick the next leg"],
      replace: [
        [
          HEADER,
          `  scan-fallback:
    name: Scan Fallback
    needs: [gate, scan-subscription]
    if: >-
      \${{ !cancelled() && needs.gate.outputs.run == 'true' && github.run_attempt == '1'
      && (needs.scan-subscription.outputs.next-leg == 'fallback' || needs.scan-subscription.outputs.credential-present == 'false') }}
`,
          1,
        ],
        [NEXT_OUTPUTS, "", 1],
        ...shared("fallback"),
        [
          CREDENTIAL_CALL,
          `          credential-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ needs.scan-subscription.outputs.next-reason }}`,
          1,
        ],
        [API_KEY, "          fallback-token: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}\n", 1],
      ],
    },
  ],
};
