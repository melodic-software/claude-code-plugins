// post-merge-test-mutation.yml's report job: the audit's structured output is
// untrusted model text, read from the environment, checked against
// result.schema.json, and written to the job summary with the pushed range and
// the pull request that merged its head. When exactly one pull request merged
// it, the comment body for comment.mjs goes to COMMENT_PATH and its number to
// the `pull` step output. No model runs here.
//
// Env: STRUCTURED_OUTPUT, AUDIT_RESULT (the audit job's result), RESTORED
// (`true` or `false` from the audit job's own check of the checkout), BEFORE,
// AFTER, RANGE_MODE (`range`, or `commit` when the push had no usable
// previous head), REPOSITORY, GITHUB_TOKEN, GITHUB_STEP_SUMMARY, COMMENT_PATH,
// GITHUB_OUTPUT, GITHUB_RUN_ID.
// Exits 1 when the audit left no valid result or could not restore the tree;
// surviving mutants alone never fail it (the plugin gates on no score).
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { commitPulls, createGitHub, graphQLReader } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

// The first line of the lane's comment on a merged pull request.
export const MARKER = "<!-- post-merge-test-mutation -->";
export const SCHEMA = JSON.parse(readFileSync(new URL("./result.schema.json", import.meta.url), "utf8"));
const SHA = /^[0-9a-f]{40}$/;
const STATES = SCHEMA.properties.mutants.items.properties.state.enum;

// The subset of JSON Schema result.schema.json uses; a value it does not
// match is named by its path. A key the schema does not list is model text, so
// it is counted, never echoed.
export function violations(value, schema = SCHEMA, at = "$") {
  if (schema.enum) return schema.enum.includes(value) ? [] : [`${at}: not one of ${schema.enum.join(", ")}`];
  if (schema.type === "string") {
    if (typeof value !== "string") return [`${at}: not a string`];
    if (value.length > schema.maxLength) return [`${at}: longer than ${schema.maxLength}`];
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) return [`${at}: does not match ${schema.pattern}`];
    return [];
  }
  if (schema.type === "integer") {
    return Number.isSafeInteger(value) && value >= schema.minimum ? [] : [`${at}: not an integer of at least ${schema.minimum}`];
  }
  if (schema.type === "array") {
    if (!Array.isArray(value)) return [`${at}: not an array`];
    if (value.length > schema.maxItems) return [`${at}: more than ${schema.maxItems} items`];
    return value.flatMap((item, index) => violations(item, schema.items, `${at}[${index}]`));
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) return [`${at}: not an object`];
  return [
    ...schema.required.filter((key) => !Object.hasOwn(value, key)).map((key) => `${at}.${key}: missing`),
    ...(Object.keys(value).some((key) => !Object.hasOwn(schema.properties, key)) ? [`${at}: has a property the schema does not list`] : []),
    ...Object.entries(value)
      .filter(([key]) => Object.hasOwn(schema.properties, key))
      .flatMap(([key, item]) => violations(item, schema.properties[key], `${at}.${key}`)),
  ];
}

export function parseResult(text) {
  let value;
  try {
    value = JSON.parse(text ?? "");
  } catch {
    return { error: "the audit returned no JSON result" };
  }
  const bad = violations(value);
  // Structured output takes no lookaround, so the schema's pattern admits a
  // `.` or `..` segment; a repository-relative path has none.
  if (!bad.length) {
    value.mutants.forEach((m, index) => {
      if (m.path.split("/").some((part) => part === "." || part === "..")) bad.push(`$.mutants[${index}].path: has a . or .. segment`);
    });
  }
  return bad.length ? { error: `the audit's result does not match result.schema.json: ${bad.slice(0, 5).join("; ")}` } : { result: value };
}

// Stryker's aggregates, as the principles skill's metrics.md defines them.
export function scores(mutants) {
  const count = Object.fromEntries(STATES.map((state) => [state, mutants.filter((m) => m.state === state).length]));
  const detected = count.killed + count.timeout;
  const covered = detected + count.survived;
  const valid = covered + count["no-coverage"];
  const percent = (part, whole) => (whole ? `${Math.round((part / whole) * 100)}%` : "n/a");
  return { count, coveredScore: percent(detected, covered), mutationScore: percent(detected, valid) };
}

// The pull requests into main that the commit belongs to: after a merge, the
// one that merged it. A failed read is `null`, never an empty list.
export async function mergedPulls({ github, repository, sha }) {
  try {
    const pulls = await commitPulls({
      repository,
      sha,
      readRest: () => github("GET", `/repos/${repository}/commits/${sha}/pulls?per_page=100`),
      readGraphQL: graphQLReader(github),
    });
    return pulls.filter((pull) => pull?.base?.ref === "main" && pull.state === "closed" && Number.isSafeInteger(pull.number)).map((pull) => pull.number);
  } catch {
    return null;
  }
}

// A fence longer than any backtick run in the text, so model text cannot
// close it and render as markdown.
const fenced = (text) => {
  const fence = "`".repeat(Math.max(3, ...[...text.matchAll(/`+/g)].map((m) => m[0].length + 1)));
  return `${fence}text\n${text}\n${fence}`;
};

export function render({ result, error, before, after, mode, pulls, repository }) {
  const short = (sha) => (SHA.test(sha ?? "") ? sha.slice(0, 12) : "unknown");
  const range = mode === "range" ? `${short(before)}..${short(after)}` : `${short(after)} only (the push had no usable previous head)`;
  const merged =
    pulls === null
      ? "unknown (the lookup failed)"
      : pulls.length
        ? pulls.map((n) => `[#${n}](https://github.com/${repository}/pull/${n})`).join(", ")
        : "none (a direct push)";
  const lines = ["## Post-merge mutation testing", "", `- Range: ${range}`, `- Merged pull request: ${merged}`];
  if (error) return [...lines, `- Outcome: no result. ${error}`, ""].join("\n");
  const { count, coveredScore, mutationScore } = scores(result.mutants);
  lines.push(`- Outcome: ${result.outcome}`);
  if (result.detail) lines.push("", fenced(result.detail));
  if (!result.mutants.length) return [...lines, ""].join("\n");
  lines.push(
    "",
    `Killed ${count.killed}, survived ${count.survived}, timeout ${count.timeout}, no coverage ${count["no-coverage"]}, invalid ${count.invalid}, not run ${count["not-run"]}.`,
    `Covered-code score ${coveredScore}; mutation score ${mutationScore}.`,
    "",
    "| File | Killed | Survived | Timeout | No coverage | Invalid | Not run |",
    "|---|---|---|---|---|---|---|",
  );
  const files = [...new Set(result.mutants.map((m) => m.path))].sort();
  for (const file of files) {
    const { count: c } = scores(result.mutants.filter((m) => m.path === file));
    lines.push(`| \`${file}\` | ${c.killed} | ${c.survived} | ${c.timeout} | ${c["no-coverage"]} | ${c.invalid} | ${c["not-run"]} |`);
  }
  const survivors = result.mutants.filter((m) => m.state === "survived");
  if (survivors.length) {
    lines.push("", "### Surviving mutants", "", "| Location | Operator | Disposition | Cause |", "|---|---|---|---|");
    for (const m of survivors) lines.push(`| \`${m.path}:${m.line}\` | ${m.operator} | ${m.disposition} | ${m.cause} |`);
  }
  return [...lines, ""].join("\n");
}

// The pull request comment: render's report with no free model text. The
// detail is left out, and a failed result names no violation, since a
// violation names the model's values; the run's summary has both.
export function commentBody({ result, error, before, after, mode, pulls, repository, runId }) {
  const report = render({
    result: result && { ...result, detail: "" },
    error: error && "The run's summary says why.",
    before,
    after,
    mode,
    pulls,
    repository,
  });
  const run = /^[1-9][0-9]*$/.test(runId ?? "") ? `[The run's summary](https://github.com/${repository}/actions/runs/${runId}) has the full report.` : "The run's summary has the full report.";
  return `${MARKER}\n${report}\n${run}\n`;
}

function outcomeOf(env) {
  if (env.RESTORED === "false") return { error: "the checkout differs from the pushed head after the audit, so no result is reported" };
  if (env.AUDIT_RESULT !== "success") return { error: `the audit job ended ${env.AUDIT_RESULT || "without a result"}` };
  return parseResult(env.STRUCTURED_OUTPUT);
}

export async function main(env = process.env, { github } = {}) {
  const parsed = outcomeOf(env);
  const client = github ?? createGitHub({ token: env.GITHUB_TOKEN });
  const pulls = SHA.test(env.AFTER ?? "") ? await mergedPulls({ github: client, repository: env.REPOSITORY, sha: env.AFTER }) : null;
  const summary = render({ ...parsed, before: env.BEFORE, after: env.AFTER, mode: env.RANGE_MODE, pulls, repository: env.REPOSITORY });
  appendFileSync(env.GITHUB_STEP_SUMMARY, summary);
  // One pull request gets the comment; none, several or a failed lookup gets none.
  if (pulls?.length !== 1) {
    console.log(`::notice::no pull request comment: ${pulls === null ? "the merged pull request lookup failed" : `${pulls.length} pull requests merged the head`}`);
  } else if (env.COMMENT_PATH && env.GITHUB_OUTPUT) {
    writeFileSync(env.COMMENT_PATH, commentBody({ ...parsed, before: env.BEFORE, after: env.AFTER, mode: env.RANGE_MODE, pulls, repository: env.REPOSITORY, runId: env.GITHUB_RUN_ID }));
    appendFileSync(env.GITHUB_OUTPUT, `pull=${pulls[0]}\n`);
  }
  if (parsed.error) {
    console.log(`::error::${parsed.error}`);
    return 1;
  }
  if (parsed.result.outcome === "restore-failed") {
    console.log("::error::the audit could not restore the checkout after a mutant; its result describes an edited tree");
    return 1;
  }
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
