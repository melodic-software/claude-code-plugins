export function readRunnerCalls({ workflow, key, role, upstream, comments, subscription, fallback = {} }) {
  const leg = (suffix, needs, { if: gate, replace = [] }, keyCredit, token) => ({
    job: `${key}-${suffix.toLowerCase()}`,
    replace: [
      [
        new RegExp(`^ {2}${key}:\\n {4}name: (.*)\\n {4}needs: .*\\n {4}if: .*\\n(?: {6}.*\\n)*`, "gm"),
        `  ${key}-${suffix.toLowerCase()}:\n    name: $1 ${suffix}\n    needs: [${[...upstream, key, ...needs].join(", ")}]\n    if: ${gate}\n`,
        1,
      ],
      [/^ {4,}#.*\n/gm, "", comments],
      [`      key-credit-job: ${key}\n`, keyCredit, 1],
      [`      claude-api-key: \${{ secrets.${role}_CLAUDE_API_KEY }}`, token, 1],
      ...replace,
    ],
  });
  return {
    workflow,
    key,
    legs: [
      leg(
        "Subscription",
        [`${key}-handoff`],
        subscription,
        `      fallback: ${subscription.fallback ?? "handoff"}\n      fallback-ready: \${{ needs.${key}-handoff.outputs.fallback-ready }}\n`,
        `      claude-code-oauth-token: \${{ secrets.${role}_CLAUDE_CODE_OAUTH_TOKEN }}`,
      ),
      leg(
        "Fallback",
        [`${key}-handoff`, `${key}-subscription`, `${key}-subscription-handoff`],
        {
          if: `\${{ !cancelled() && needs.${key}-handoff.outputs.fallback-ready == 'true' && needs.${key}-subscription-handoff.outputs.handed-off == 'true' }}`,
          ...fallback,
        },
        "      fallback: fallback\n",
        "      fallback-claude-code-oauth-token: ${{ secrets.FALLBACK_CLAUDE_CODE_OAUTH_TOKEN }}",
      ),
    ],
  };
}
