// Appends one rate-limit reading, from a response's x-ratelimit-* headers, to
// $RUNNER_TEMP/api-budget/<token> in api-budget.bash's line shape, for the
// job-end notice the log-api-budget action writes. `token` names the bucket
// (`github-token`, `lanes-app`); without it or RUNNER_TEMP nothing is written.
// Never throws.

import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

const VALUE = { limit: /^\d+$/, remaining: /^\d+$/, used: /^\d+$/, reset: /^\d+$/, resource: /^[a-z_]+$/ };

export function readingLine(status, headers) {
  const values = Object.entries(VALUE).map(([key, re]) => {
    const value = String(headers?.get?.(`x-ratelimit-${key}`) ?? "");
    return re.test(value) ? value : "na";
  });
  return `${status} ${values.join(" ")}\n`;
}

// Appends one content-creating write, as its epoch second, to
// $RUNNER_TEMP/api-budget/content-creation, which api-budget.bash's gh wrapper
// also appends to, for the job-end content-creation notice. Without
// RUNNER_TEMP nothing is written. Never throws.
export function recordContentWrite({ dir = process.env.RUNNER_TEMP, at }) {
  if (!dir || !Number.isSafeInteger(at)) {
    return;
  }
  try {
    mkdirSync(join(dir, "api-budget"), { recursive: true });
    appendFileSync(join(dir, "api-budget", "content-creation"), `${at}\n`);
  } catch {
    // A count is never worth failing the job.
  }
}

export function recordReading({ token = process.env.API_BUDGET_TOKEN, dir = process.env.RUNNER_TEMP, status, headers }) {
  if (!dir || !/^[a-z][a-z0-9-]{0,39}$/.test(token ?? "")) {
    return;
  }
  try {
    mkdirSync(join(dir, "api-budget"), { recursive: true });
    appendFileSync(join(dir, "api-budget", token), readingLine(status, headers));
  } catch {
    // A reading is never worth failing the job.
  }
}
