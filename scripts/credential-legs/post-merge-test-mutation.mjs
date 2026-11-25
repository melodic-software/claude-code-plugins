const KEY_ONLY = ["Write the key's credit-stop marker", "Scan the key's credit-stop marker for credentials", "Upload the key's credit-stop marker"];
const SAME_REPO = "      && github.event.workflow_run.head_repository.full_name == github.repository";
const API_KEY = "          api-key: ${{ secrets.AUTOMATIONS_CLAUDE_API_KEY }}\n";
const NO_TOKEN = (condition, message) => `
      - name: Fail when no token is set
        id: no-token
        if: ${condition}
        run: |
          echo "::error::${message}"
          exit 1
`;

const chain = (stage, needs) => {
  const title = stage[0].toUpperCase() + stage.slice(1);
  const header = (job, name, last) => [`  ${stage}:\n    name: ${title}\n    needs: [${needs}]\n`, `  ${job}:\n    name: ${name}\n    needs: [${needs}, ${last}]\n`, 1];
  const credential = `          credential-set: \${{ secrets.AUTOMATIONS_CLAUDE_API_KEY != '' }}
          selected: \${{ needs.check-key-credit.outputs.${stage}-next-leg }}
          key-off: \${{ vars.CLAUDE_API_KEYS_DISABLED == 'true' }}
`;
  const shared = (leg) => [
    ["          leg: key\n", `          leg: ${leg}\n`, 1],
    ['          fallback-reason: ""', "          fallback-reason: ${{ steps.credential.outputs.fallback-reason }}", 1],
  ];
  return {
    workflow: ".github/workflows/post-merge-test-mutation.yml",
    key: stage,
    legs: [
      {
        job: `${stage}-subscription`,
        drop: KEY_ONLY,
        replace: [
          header(`${stage}-subscription`, `${title} Subscription`, stage),
          [
            `${SAME_REPO} }}`,
            `${SAME_REPO}\n      && (needs.${stage}.outputs.next-leg == 'subscription' || needs.check-key-credit.outputs.${stage}-next-leg == 'subscription') }}`,
            1,
          ],
          ...shared("subscription"),
          [
            credential,
            `          credential-set: \${{ secrets.AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          fallback-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ needs.${stage}.outputs.next-reason || needs.check-key-credit.outputs.${stage}-next-reason }}
${NO_TOKEN(
  "steps.credential.outputs.present != 'true' && steps.credential.outputs.fallback-ready != 'true'",
  "AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN and FALLBACK_CLAUDE_CODE_OAUTH_TOKEN are both empty, so nothing is audited",
)}`,
            1,
          ],
          [API_KEY, "          subscription-token: ${{ secrets.AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN }}\n          fallback-ready: ${{ steps.credential.outputs.fallback-ready }}\n", 1],
        ],
      },
      {
        job: `${stage}-fallback`,
        drop: [...KEY_ONLY, "Pick the next leg"],
        replace: [
          header(`${stage}-fallback`, `${title} Fallback`, `${stage}-subscription`),
          [`${SAME_REPO} }}`, `${SAME_REPO}\n      && needs.${stage}-subscription.outputs.next-leg == 'fallback' }}`, 1],
          ["      next-leg: ${{ steps.next.outputs.next-leg }}\n      next-reason: ${{ steps.next.outputs.next-reason }}\n", "", 1],
          ...shared("fallback"),
          [
            credential,
            `          credential-set: \${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN != '' }}
          reason: \${{ needs.${stage}-subscription.outputs.next-reason }}
${NO_TOKEN("steps.credential.outputs.present != 'true'", "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN is empty, so nothing is audited")}`,
            1,
          ],
          [API_KEY, "          fallback-token: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}\n", 1],
        ],
      },
    ],
  };
};

export default [chain("generate", "check-range, check-key-credit"), chain("triage", "check-range, check-key-credit, run-mutants")];
