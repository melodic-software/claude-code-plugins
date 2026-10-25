// Appends one rate-limit reading, from a response's x-ratelimit-* headers, to
// $RUNNER_TEMP/api-budget/<token> in api-budget.bash's line shape, for the
// job-end notice the log-api-budget action writes. `token` names the bucket
// (`github-token`, `lanes-app`); without it or RUNNER_TEMP nothing is written.
// Never throws. The rate guard keeps each guarded call's reading with it, so
// it lives in rate-guard.mjs.

export { readingLine, recordReading } from "./rate-guard.mjs";
