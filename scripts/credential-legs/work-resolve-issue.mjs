import { readRunnerCalls } from "./read-runner-calls.mjs";

const ADMITTED = "${{ !cancelled() && needs.check-admission.outputs.proceed == 'true'\n      && needs.pick-slot.outputs.capped == 'false'";

export default readRunnerCalls({
  workflow: ".github/workflows/work-resolve-issue.yml",
  key: "resolve-issue",
  role: "ISSUE_LANE",
  upstream: ["check-admission", "pick-slot"],
  comments: 10,
  subscription: {
    if: `>-
      ${ADMITTED}
      && (needs.resolve-issue-handoff.outputs.handed-off == 'true' || needs.pick-slot.result == 'success' && needs.pick-slot.outputs.skip-key == 'true' && needs.resolve-issue.result == 'skipped') }}`,
    fallback: "${{ needs.resolve-issue.result == 'skipped' && (needs.pick-slot.outputs.key-off == 'true' && 'no-key' || 'credit-stop') || 'handoff' }}",
  },
  fallback: {
    if: `>-
      ${ADMITTED} && needs.resolve-issue-handoff.outputs.fallback-ready == 'true'
      && needs.resolve-issue-subscription-handoff.outputs.handed-off == 'true' }}`,
    replace: [["      start-gate: true\n", "", 1]],
  },
});
