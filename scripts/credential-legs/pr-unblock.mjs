import { readRunnerCalls } from "./read-runner-calls.mjs";

const call = (key, select, comments, gate = "") =>
  readRunnerCalls({
    workflow: ".github/workflows/pr-unblock.yml",
    key,
    role: "PR_UNBLOCK",
    upstream: [select],
    comments,
    subscription: {
      if: `>-
      \${{ !cancelled() && needs.${select}.outputs.proceed == 'true'
${gate}      && needs.${key}-handoff.outputs.posted != 'true' }}`,
    },
  });

export default [
  call("resolve-conflicts", "resolve-conflicts-select", 2),
  call("address-feedback", "address-feedback-select", 1),
  call("review-dependency", "review-dependency-select", 1),
  call("fix-ci", "fix-ci-context", 1),
  call("fix-ci-rung-up", "fix-ci-context", 0, "      && needs.fix-ci-rung-up.result != 'skipped'\n"),
];
