const KEY_ONLY = [
  "Read the defer override from the base config",
  "Check the token budget",
  "Note the deferral",
  "Hand the reads on",
  "Read the key's credit history",
  "Report the skipped key leg",
  "Write the key's probing marker",
  "Scan the key's probing marker for credentials",
  "Upload the key's probing marker",
  "Write the key's credit-stop marker",
  "Scan the key's credit-stop marker for credentials",
  "Upload the key's credit-stop marker",
];
const LEG_CHECKS = ["", ", later chunks", ", whole spec"].map((s) => `Check the key leg${s}`);
const CREDENTIAL_CALL = `          credential-set: \${{ secrets.PR_VERIFY_CLAUDE_API_KEY != '' }}
          selected: \${{ steps.credit.outputs.next-leg }}
          key-off: \${{ vars.CLAUDE_API_KEYS_DISABLED == 'true' }}`;
const LEG_CHECK_RUN = `          case "$LANE_CLASS" in
            auth) echo "::warning::the API refused the pr-verify role's API key (PR_VERIFY_CLAUDE_API_KEY), class auth; the owner must replace the secret" ;;
            *) echo "::warning::the pr-verify role's API key (PR_VERIFY_CLAUDE_API_KEY) hit a credit stop; rotate a spare key in" ;;
          esac
          node .base/.github/scripts/pr-verify/write-verdict.mjs check-key-leg
          echo "::notice::check-intent-subscription judges on the subscription token"`;
const TRIGGER = `    if: >-
      github.ref == 'refs/heads/main'
`;
const TRUSTED_ACTORS =
  "          TRUSTED_ACTORS_PATH: ${{ steps.standards.outputs.path }}/components/trusted-actors/trusted-actors.json\n          STANDARDS_DIR: ${{ steps.standards.outputs.path }}\n";
const STANDARDS = "        uses: melodic-software/ci-workflows/.github/actions/download-standards@main\n";
const SHARED = [
  [STANDARDS, `${STANDARDS}        with:\n          ref: \${{ needs.check-intent.outputs.standards-sha }}\n`, 1],
  ["      standards-sha: ${{ steps.standards.outputs.sha }}\n", "", 1],
  [`      reads: \${{ steps.carry.outputs.reads }}\n`, "", 1],
  [
    `${TRUSTED_ACTORS}        run: |`,
    `${TRUSTED_ACTORS}          CONTEXT_FILE: \${{ github.workspace }}/pr-verify-data/context.json\n          CARRIED: \${{ needs.check-intent.outputs.reads }}\n        run: |`,
    1,
  ],
  [" && steps.defer.outputs.cause != 'defer'", "", 1],
  [
    "      - name: Select the trusted PR text\n        if: steps.agree.outcome == 'success'\n",
    "      - name: Select the trusted PR text\n        if: steps.agree.outcome == 'success' && steps.pr.outputs.carried != 'true'\n",
    1,
  ],
  [" && steps.credential.outputs.key-skipped != 'true'", "", 5],
];
const fallbackReady = ['          leg-timeout-minutes: "15"', `          fallback-ready: \${{ steps.credential.outputs.fallback-ready }}\n          leg-timeout-minutes: "15"`, 3];
const FALLBACK_REASON = `          fallback-reason: \${{ steps.credential.outputs.fallback-reason }}`;

export default {
  workflow: ".github/workflows/pr-verify.yml",
  key: "check-intent",
  legs: [
    {
      job: "check-intent-subscription",
      drop: KEY_ONLY,
      move: { "Check the credential": "Resolve the verifier's model" },
      comments: { "Write the prompt and schema": true },
      replace: [
        ["  check-intent:\n    name: Check Intent\n", "  check-intent-subscription:\n    name: Check Intent Subscription\n    needs: check-intent\n", 1],
        [TRIGGER, `    if: >-\n      !cancelled()\n      && github.ref == 'refs/heads/main'\n`, 1],
        [
          "      && vars.CLAUDE_API_KEYS_DISABLED != 'true'\n",
          "      && (needs.check-intent.result == 'skipped'\n      || (needs.check-intent.result == 'success'\n      && needs.check-intent.outputs.next-leg == 'subscription'))\n",
          1,
        ],
        ...SHARED,
        ["          leg: key\n", "          leg: subscription\n", 1],
        [
          CREDENTIAL_CALL,
          `          credential-set: \${{ secrets.PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          fallback-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ needs.check-intent.result == 'skipped' && 'no-key' || needs.check-intent.outputs.next-reason }}`,
          1,
        ],
        ["          api-key: ${{ secrets.PR_VERIFY_CLAUDE_API_KEY }}", "          subscription-token: ${{ secrets.PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN }}", 3],
        fallbackReady,
        ["- name: Check the key leg", "- name: Check the subscription leg", 3],
        [/^( {10})LANE_CLASS: \$\{\{ steps\.(judge[\w-]*)\.outputs\.lane-class \}\}$/gm, "$1HANDOFF_REASON: ${{ steps.$2.outputs.handoff-reason }}", 3],
        [
          LEG_CHECK_RUN,
          `          node .base/.github/scripts/pr-verify/write-verdict.mjs check-key-leg
          echo "::notice::the subscription leg handed off (\${HANDOFF_REASON}); check-intent-fallback judges on the fallback token"`,
          3,
        ],
        [/(?<!check-)key-leg/g, "sub-leg", 12],
        [
          " && steps.credential.outputs.present != 'false' && steps.",
          " && !(steps.credential.outputs.present == 'false' && steps.credential.outputs.fallback-ready == 'true') && steps.",
          1,
        ],
        [
          "steps.judge.outputs.handoff == 'true' && steps.sub-leg.outcome != 'failure' }}\n",
          `steps.judge.outputs.handoff == 'true' && steps.sub-leg.outcome != 'failure' }}\n${FALLBACK_REASON}\n`,
          1,
        ],
        [/^( {10}handoff: \$\{\{ steps\.judge-[\w]+\.outputs\.handoff == 'true'(?: && steps\.later-fail\.outputs\.fail != 'true')? && steps\.sub-leg-\w+\.outcome != 'failure' \}\})$/gm, `$1\n${FALLBACK_REASON}`, 2],
      ],
    },
    {
      job: "check-intent-fallback",
      drop: [...KEY_ONLY, ...LEG_CHECKS, "Pick the next leg"],
      move: { "Check the credential": "Resolve the verifier's model" },
      comments: { "Write the prompt and schema": true },
      replace: [
        ["  check-intent:\n    name: Check Intent\n", "  check-intent-fallback:\n    name: Check Intent Fallback\n    needs: [check-intent, check-intent-subscription]\n", 1],
        [TRIGGER, `    if: >-\n      !cancelled()\n      && needs.check-intent-subscription.result == 'success'\n      && github.ref == 'refs/heads/main'\n`, 1],
        ["      && vars.CLAUDE_API_KEYS_DISABLED != 'true'\n", "      && needs.check-intent-subscription.outputs.next-leg == 'fallback'\n", 1],
        [`      next-leg: \${{ steps.next.outputs.next-leg }}\n      next-reason: \${{ steps.next.outputs.next-reason }}\n`, "", 1],
        ...SHARED,
        ["          leg: key\n", "          leg: fallback\n", 1],
        [
          CREDENTIAL_CALL,
          `          credential-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          fallback-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ needs.check-intent-subscription.outputs.next-reason }}`,
          1,
        ],
        ["          api-key: ${{ secrets.PR_VERIFY_CLAUDE_API_KEY }}", "          fallback-token: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}", 3],
        fallbackReady,
        [
          "          handoff: ${{ steps.judge.outputs.handoff == 'true' && steps.key-leg.outcome != 'failure' }}",
          FALLBACK_REASON,
          1,
        ],
        [/^ {10}handoff: \$\{\{ steps\.judge-\w+\.outputs\.handoff == 'true'(?: && steps\.later-fail\.outputs\.fail != 'true')? && steps\.key-leg-\w+\.outcome != 'failure' \}\}$/gm, FALLBACK_REASON, 2],
        [/ && steps\.credential\.outputs\.present != 'false'(?: && steps\.key-leg[\w-]*\.outcome != 'success')+$/gm, "", 1],
      ],
    },
  ],
};
