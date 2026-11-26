const HEADER = /^[\s\S]*?\n(?= {4}runs-on: )/g;
const KEY_CREDENTIAL = "          credential-set: ${{ secrets.ISSUE_LANE_CLAUDE_API_KEY != '' }}\n          key-off: ${{ vars.CLAUDE_API_KEYS_DISABLED == 'true' }}\n";
const API_KEY = "          api-key: ${{ secrets.ISSUE_LANE_CLAUDE_API_KEY }}\n";
const NEXT_OUTPUTS = "      next-leg: ${{ steps.next.outputs.next-leg }}\n      next-reason: ${{ steps.next.outputs.next-reason }}\n";
const IF = "    if: >-\n      ${{ !cancelled() && needs.select-release.outputs.proceed == 'true' && github.run_attempt == '1'\n";

const subscription = (key, name) => ({
  header: `  ${key}-subscription:
    name: ${name} Subscription
    needs: [select-release, ${key}]
${IF}      && (needs.${key}.outputs.next-leg == 'subscription' || needs.select-release.outputs.next-leg == 'subscription') }}
`,
  replace: [
    ["          leg: key\n", "          leg: subscription\n", 1],
    [
      KEY_CREDENTIAL,
      `          credential-set: \${{ secrets.ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          fallback-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ needs.${key}.outputs.next-reason || needs.select-release.outputs.next-reason }}
`,
      1,
    ],
    [API_KEY, "          subscription-token: ${{ secrets.ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN }}\n          fallback-ready: ${{ steps.credential.outputs.fallback-ready }}\n", 1],
  ],
});
const fallback = (key, name) => ({
  header: `  ${key}-fallback:
    name: ${name} Fallback
    needs: [select-release, ${key}-subscription]
${IF}      && needs.${key}-subscription.outputs.next-leg == 'fallback' }}
`,
  replace: [
    ["          leg: key\n", "          leg: fallback\n", 1],
    [KEY_CREDENTIAL, `          credential-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}\n          reason: \${{ needs.${key}-subscription.outputs.next-reason }}\n`, 1],
    [API_KEY, "          fallback-token: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}\n", 1],
  ],
});
const leg = (job, { header, replace }, more) => ({ job, ...more, replace: [[HEADER, header, 1], ...replace, ...more.replace] });

const APPLY_COMMENTS = {
  "Resolve the model": true,
  "Check the credential": true,
  "Stage the base plugins": true,
  "Check out main with history": true,
  "Clear the trusted checkout path": true,
  "Record the leg": true,
  "Seal the plan and the branches": true,
  "Log the API budget at the end": true,
};
const CREDIT_MARKER = ["Write the key's credit-stop marker", "Scan the key's credit-stop marker for credentials", "Upload the key's credit-stop marker"];
const APPLY_SHARED = [
  ['          fallback-reason: ""', "          fallback-reason: ${{ steps.credential.outputs.fallback-reason }}", 1],
];
const KEY_HANDOFF = `          LANE_CLASS: \${{ steps.run.outputs.lane-class }}
        run: |
          case "$LANE_CLASS" in
            auth) line="the API refused ISSUE_LANE_CLAUDE_API_KEY (class auth); the owner must replace the secret, and apply-changelog-subscription runs release $RELEASE on the subscription token" ;;
            *) line="ISSUE_LANE_CLAUDE_API_KEY hit a credit stop (class credit-stop); apply-changelog-subscription runs release $RELEASE on the subscription token" ;;
          esac
          echo "::warning::$line"`;

const applyChangelog = {
  workflow: ".github/workflows/upstream-apply-changelog.yml",
  key: "apply-changelog",
  legs: [
    leg(
      "apply-changelog-subscription",
      subscription("apply-changelog", "Apply Changelog"),
      {
        drop: CREDIT_MARKER,
        comments: {
          ...APPLY_COMMENTS,
          "Pick the next leg": true,
        },
        replace: [
          ...APPLY_SHARED,
          ["      - name: Report the key's handoff\n", "      - name: Report the subscription's handoff\n", 1],
          [
            KEY_HANDOFF,
            `          HANDOFF_REASON: \${{ steps.run.outputs.handoff-reason }}
        run: |
          line="ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN handed off (\${HANDOFF_REASON:-unknown}); apply-changelog-fallback runs release $RELEASE on FALLBACK_CLAUDE_CODE_OAUTH_TOKEN"
          echo "::notice::$line"`,
            1,
          ],
          ["          JOB_ID: apply-changelog\n", "          JOB_ID: apply-changelog-subscription\n", 1],
        ],
      },
    ),
    leg(
      "apply-changelog-fallback",
      fallback("apply-changelog", "Apply Changelog"),
      {
        drop: [...CREDIT_MARKER, "Report the key's handoff", "Pick the next leg"],
        comments: {
          ...APPLY_COMMENTS,
        },
        replace: [
          [NEXT_OUTPUTS, "", 1],
          ...APPLY_SHARED,
          [" && steps.run.outputs.handoff != 'true' && steps.credential.outputs.present != 'false'", " && steps.credential.outputs.present != 'false'", 1],
          ["          JOB_ID: apply-changelog\n", "          JOB_ID: apply-changelog-fallback\n", 1],
        ],
      },
    ),
  ],
};

const SCRUB_COMMENTS = { "Check the credential": true, "Record the probe leg": true, "Check the probe": true };
const scrubNames = (token) => [": ISSUE_LANE_CLAUDE_API_KEY\n", `: ${token}\n`, 2];

const verifyEnvScrub = {
  workflow: ".github/workflows/upstream-apply-changelog.yml",
  key: "verify-env-scrub",
  legs: [
    leg("verify-env-scrub-subscription", subscription("verify-env-scrub", "Verify Env Scrub"), {
      comments: {
        ...SCRUB_COMMENTS,
        "Pick the next leg": true,
      },
      replace: [scrubNames("ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN")],
    }),
    leg("verify-env-scrub-fallback", fallback("verify-env-scrub", "Verify Env Scrub"), {
      drop: ["Pick the next leg"],
      comments: {
        ...SCRUB_COMMENTS,
      },
      replace: [[`    outputs:\n${NEXT_OUTPUTS}`, "", 1], scrubNames("FALLBACK_CLAUDE_CODE_OAUTH_TOKEN")],
    }),
  ],
};

export default [applyChangelog, verifyEnvScrub];
