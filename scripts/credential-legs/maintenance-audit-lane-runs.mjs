const HEADER = `  assess-units:
    name: Assess Units
    needs: collect
    # A key the credit gate skipped runs nothing here; collect-key-handoffs routes
    # every unit to assess-units-subscription.
    if: needs.collect.outputs.units != '' && needs.collect.outputs.units != '[]' && needs.collect.outputs.next-leg != 'subscription'
`;
const header = (job, name, collector) => `  ${job}:
    name: ${name}
    needs: ${collector}
    if: \${{ !cancelled() && needs.${collector}.result == 'success' && needs.${collector}.outputs.count != '' && needs.${collector}.outputs.count != '0' }}
`;
const MATRIX = "      matrix:\n        unit: ${{ fromJson(needs.collect.outputs.units) }}\n";
const matrix = (collector) => `      matrix: \${{ fromJson(needs.${collector}.outputs.matrix) }}\n`;
const API_KEY = "          api-key: ${{ secrets.AUTOMATIONS_CLAUDE_API_KEY }}\n";
const HANDOFF = "          handoff: ${{ steps.judge.outputs.handoff == 'true' && steps.key-leg.outcome != 'failure' }}\n";
const FALLBACK_REASON = "          # Why this leg ran, for its lane record.\n          fallback-reason: ${{ steps.credential.outputs.fallback-reason }}\n";
const JUDGE_LIMITS = `One leg of leg-timeout-minutes and the CLI install fit in
timeout-minutes, which the outcome step repeats, and that fits in the
job's 30. The launcher's --restricted keeps the file tools inside the
working directory, which holds the data and the checkout; the allow
rules name those two, and under dontAsk nothing else is readable. The
deny rules keep the process environment, the home directory's dot
files (the workspace is under home, so not all of it) and the runner's
temp files out if the tools or the working directory change
(code.claude.com/docs/en/permissions, "Read and Edit").`;
const CREDENTIAL_REASON = "matrix.reason is checked there against the closed list of fallback\nreasons.";
const COMMENTS = {
  "Resolve the model": true,
  "Apply the Claude managed settings": true,
  "Write the prompt and schema": true,
  "Upload the sealed transcript": true,
  "Write the findings": true,
};
const shared = (leg) => [
  ["          leg: key\n", `          leg: ${leg}\n`, 1],
  ["          key-off: ${{ vars.CLAUDE_API_KEYS_DISABLED == 'true' }}", "          reason: ${{ matrix.reason }}", 1],
];

export default {
  workflow: ".github/workflows/maintenance-audit-lane-runs.yml",
  key: "assess-units",
  legs: [
    {
      job: "assess-units-subscription",
      comments: {
        ...COMMENTS,
        "Check the credential": `Only whether each secret is set reaches the action, never its value.\n${CREDENTIAL_REASON}`,
        "Judge the unit": `continue-on-error keeps a launcher failure, which run-claude-cli
reports by failing this step, from ending the job before the outcome
step; "Fail without findings" carries the red. With the fallback
token set, a limit stop, a credit stop or a 401 or 402 hands off, which
skips the findings steps; the outcome step records the leg as handed
off, and assess-units-fallback judges the unit.
${JUDGE_LIMITS}`,
        "Check the key leg": true,
        "Pick the next leg": true,
        "Record the handoff": true,
      },
      replace: [
        [HEADER, header("assess-units-subscription", "Assess Units Subscription", "collect-key-handoffs"), 1],
        [MATRIX, matrix("collect-key-handoffs"), 1],
        ...shared("subscription"),
        ["          credential-set: ${{ secrets.AUTOMATIONS_CLAUDE_API_KEY != '' }}\n", "          credential-set: ${{ secrets.AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN != '' }}\n          fallback-set: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}\n", 1],
        [API_KEY, "          subscription-token: ${{ secrets.AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN }}\n", 1],
        [
          "          json-schema-file: ${{ runner.temp }}/lane-sweep-schema.json\n",
          "          json-schema-file: ${{ runner.temp }}/lane-sweep-schema.json\n          fallback-ready: ${{ steps.credential.outputs.fallback-ready }}\n",
          1,
        ],
        [
          `      - name: Check the key leg
        id: key-leg
        if: steps.judge.outputs.handoff == 'true'
        continue-on-error: true
        env:
          LOG_FILE: \${{ steps.judge.outputs.log-file }}
          LANE_CLASS: \${{ steps.judge.outputs.lane-class }}
        run: |
          case "$LANE_CLASS" in
            auth) echo "::warning::the API refused the automations role's API key (AUTOMATIONS_CLAUDE_API_KEY), class auth; the owner must replace the secret" ;;
            *) echo "::warning::the automations role's API key (AUTOMATIONS_CLAUDE_API_KEY) hit a credit stop; rotate a spare key in" ;;
          esac
          node .base/.github/scripts/maintenance-audit-lane-runs/handoff.mjs check-leg
`,
          `      - name: Check the subscription leg
        id: sub-leg
        if: steps.judge.outputs.handoff == 'true'
        continue-on-error: true
        env:
          LOG_FILE: \${{ steps.judge.outputs.log-file }}
          HANDOFF_REASON: \${{ steps.judge.outputs.handoff-reason }}
        run: |
          node .base/.github/scripts/maintenance-audit-lane-runs/handoff.mjs check-leg
          echo "::notice::the subscription leg handed off (\${HANDOFF_REASON}); assess-units-fallback judges on the fallback token"
`,
          1,
        ],
        ["steps.key-leg.", "steps.sub-leg.", 2],
        ["if: steps.next.outputs.next-leg == 'subscription'", "if: steps.next.outputs.next-leg == 'fallback'", 1],
        ["          LEG: key\n", "          LEG: subscription\n", 1],
        ["judge-handoff-", "judge-subscription-handoff-", 3],
        [HANDOFF.replace("key-leg", "sub-leg"), `${HANDOFF.replace("key-leg", "sub-leg")}${FALLBACK_REASON}`, 1],
      ],
    },
    {
      job: "assess-units-fallback",
      drop: ["Check the key leg", "Pick the next leg", "Record the handoff", "#scan-handoff", "Upload the handoff"],
      comments: {
        ...COMMENTS,
        "Check the credential": `Only whether the secret is set reaches the action, never its value.\n${CREDENTIAL_REASON}`,
        "Judge the unit": `continue-on-error keeps a launcher failure, which run-claude-cli
reports by failing this step, from ending the job before the outcome
step; "Fail without findings" carries the red. The fallback leg
never hands off.
${JUDGE_LIMITS}`,
      },
      replace: [
        [HEADER, header("assess-units-fallback", "Assess Units Fallback", "collect-subscription-handoffs"), 1],
        [MATRIX, matrix("collect-subscription-handoffs"), 1],
        ...shared("fallback"),
        ["          credential-set: ${{ secrets.AUTOMATIONS_CLAUDE_API_KEY != '' }}\n", "          credential-set: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}\n", 1],
        [API_KEY, "          fallback-token: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}\n", 1],
        [HANDOFF, FALLBACK_REASON, 1],
        [" && steps.handoff.outcome != 'success'", "", 1],
      ],
    },
  ],
};
