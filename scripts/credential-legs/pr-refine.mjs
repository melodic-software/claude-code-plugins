import { readRunnerCalls } from "./read-runner-calls.mjs";

export default readRunnerCalls({
  workflow: ".github/workflows/pr-refine.yml",
  key: "fix-docs",
  role: "PR_UNBLOCK",
  upstream: ["select-passes"],
  comments: 0,
  subscription: {
    if: `>-
      \${{ !cancelled() && needs.fix-docs.result != 'skipped'
      && needs.fix-docs-handoff.outputs.posted != 'true'
      && needs.fix-docs-handoff.outputs.allowed == 'true'
      && needs.fix-docs-handoff.outputs.handed-off == 'true' }}`,
  },
});
