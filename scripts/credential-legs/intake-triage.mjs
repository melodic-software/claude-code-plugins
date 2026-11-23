const KEY_ONLY = ["Write the key's credit-stop marker", "Scan the key's credit-stop marker for credentials", "Upload the key's credit-stop marker"];
const HEADER = "  refine-issue:\n    name: Refine Issue\n    needs: [refine-select, refine-key-credit]\n";
const TRIGGER = "      && needs.refine-key-credit.outputs.next-leg != 'subscription' }}";
const CREDENTIAL_CALL = `          credential-set: \${{ secrets.INTAKE_CLAUDE_API_KEY != '' }}
          key-off: \${{ vars.CLAUDE_API_KEYS_DISABLED == 'true' }}`;
const API_KEY = "          api-key: ${{ secrets.INTAKE_CLAUDE_API_KEY }}\n";
const FAIL = "        if: always() && steps.prompt.outcome != 'skipped' && steps.upload.outcome != 'success' && steps.run.outputs.handoff != 'true'\n";
const shared = (leg) => [
  ["group: intake-refine-issue-${{", `group: intake-refine-issue-${leg}-\${{`, 1],
  ["          leg: key\n", `          leg: ${leg}\n`, 1],
  ['          fallback-reason: ""', "          fallback-reason: ${{ steps.credential.outputs.fallback-reason }}", 1],
];
const COMMENTS = { "Upload the sealed transcript": true, "Record the leg": true };

export default {
  workflow: ".github/workflows/intake-triage.yml",
  key: "refine-issue",
  legs: [
    {
      job: "refine-issue-subscription",
      drop: KEY_ONLY,
      comments: {
        ...COMMENTS,
        "Fail without a refinement": `A handoff hands the refinement on, and an empty token either hands it
to the fallback leg or, with no fallback token, ends with the
credential step's warning; any other run that passed the context
check and uploaded nothing fails here.`,
        "Pick the next leg": true,
      },
      replace: [
        [HEADER, "  refine-issue-subscription:\n    name: Refine Issue Subscription\n    needs: [refine-select, refine-key-credit, refine-issue]\n", 1],
        [TRIGGER, "      && (needs.refine-issue.outputs.next-leg == 'subscription' || needs.refine-key-credit.outputs.next-leg == 'subscription') }}", 1],
        ...shared("subscription"),
        [
          CREDENTIAL_CALL,
          `          credential-set: \${{ secrets.INTAKE_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          fallback-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ needs.refine-issue.outputs.next-reason || needs.refine-key-credit.outputs.next-reason }}`,
          1,
        ],
        [API_KEY, "          subscription-token: ${{ secrets.INTAKE_CLAUDE_CODE_OAUTH_TOKEN }}\n          fallback-ready: ${{ steps.credential.outputs.fallback-ready }}\n", 1],
        [
          `          LANE_CLASS: \${{ steps.run.outputs.lane-class }}
        run: |
          case "$LANE_CLASS" in
            auth) echo "::warning::the API refused the intake role's API key (INTAKE_CLAUDE_API_KEY), class auth; the owner must replace the secret" ;;
            *) echo "::warning::the intake role's API key (INTAKE_CLAUDE_API_KEY) hit a credit stop; rotate a spare key in" ;;
          esac
          echo "::notice::refine-issue-subscription refines on the subscription token"`,
          `          HANDOFF_REASON: \${{ steps.run.outputs.handoff-reason }}
        run: |
          case "$HANDOFF_REASON" in
            limit-stop) echo "::notice::the intake role's subscription (INTAKE_CLAUDE_CODE_OAUTH_TOKEN) is at its usage limit" ;;
            credit-stop) echo "::notice::the intake role's subscription (INTAKE_CLAUDE_CODE_OAUTH_TOKEN) is out of credit" ;;
            *) echo "::warning::the API refused the intake role's subscription token (INTAKE_CLAUDE_CODE_OAUTH_TOKEN), class auth; the owner must replace the secret" ;;
          esac
          echo "::notice::refine-issue-fallback refines on FALLBACK_CLAUDE_CODE_OAUTH_TOKEN"`,
          1,
        ],
        [
          FAIL,
          `        if: >-
          always() && steps.context.outcome == 'success' && steps.upload.outcome != 'success' && steps.run.outputs.handoff != 'true'
          && steps.credential.outputs.present != 'false'
`,
          1,
        ],
      ],
    },
    {
      job: "refine-issue-fallback",
      drop: [...KEY_ONLY, "Report a handoff", "Pick the next leg"],
      comments: {
        ...COMMENTS,
        "Fail without a refinement": "The last leg: any run that passed the context check and uploaded\nnothing fails here, an empty token included.",
      },
      replace: [
        [HEADER, "  refine-issue-fallback:\n    name: Refine Issue Fallback\n    needs: [refine-select, refine-issue-subscription]\n", 1],
        [TRIGGER, "      && needs.refine-issue-subscription.outputs.next-leg == 'fallback' }}", 1],
        ["      next-leg: ${{ steps.next.outputs.next-leg }}\n      next-reason: ${{ steps.next.outputs.next-reason }}\n", "", 1],
        ...shared("fallback"),
        [
          CREDENTIAL_CALL,
          `          credential-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ needs.refine-issue-subscription.outputs.next-reason }}`,
          1,
        ],
        [API_KEY, "          fallback-token: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}\n", 1],
        [FAIL, "        if: always() && steps.context.outcome == 'success' && steps.upload.outcome != 'success'\n", 1],
      ],
    },
  ],
};
