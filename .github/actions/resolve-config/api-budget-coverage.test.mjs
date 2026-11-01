// Every workflow job that calls the GitHub API leaves api-budget readings and
// logs them at its end, so the lane record's githubCalls covers the job: the
// job (or the calling step) sets API_BUDGET_TOKEN, and a final always() step
// runs this action. A job calls GitHub when a step runs handoff-evidence.sh,
// dispatcher-current.sh, or `gh api`/`gh issue`/`gh pr`, runs a repository
// script that does, or uses resolve-config or check-trusted-trigger.
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { test } from "node:test";

import { parse } from "yaml";

const ROOT = new URL("../../../", import.meta.url);
const WORKFLOWS = new URL(".github/workflows/", ROOT);

// Jobs that call GitHub and are not yet covered, each with its reason.
const ALLOWED = new Map([
  // The lane jobs of the two run-activity reusables: a later change covers them.
  ...["pr-run-activity-read.yml", "pr-run-activity-write.yml"].map((file) => [file, "*"]),
  // No checkout to load the action from; adding one is a later change.
  ["intake-triage.yml", ["redispatch-refined", "triage-split-children"]],
  ["pr-review-main.yml", ["record"]],
  // Not yet inventoried for this check: a later change covers them.
  ["dependabot-fragments.yml", ["write"]],
  ["maintenance-audit-test-selection.yml", ["audit-test-selection"]],
  ["release-publish-plugins.yml", ["build", "merge"]],
  // report-escalation.sh runs as its own process and does not wrap its gh calls yet.
  ["pr-require-checks.yml", ["ci-status"]],
  ["pr-unblock.yml", ["report-stop-status"]],
]);

const GH_CALL = /(?:^|[\s;&|({`$])gh (?:api|issue|pr)\b|handoff-evidence\.sh|dispatcher-current\.sh/m;
const GH_ACTION = /\/actions\/(?:resolve-config|check-trusted-trigger)$/;
const SCRIPT = /(?:^|[\s"'])(?:\.base\/)?((?:\.github\/)?scripts\/[\w./-]+\.(?:sh|bash))\b/g;

const text = (path) => {
  const file = new URL(path, ROOT);
  return existsSync(file) ? readFileSync(file, "utf8") : "";
};
const scriptCallsGitHub = (path) => GH_CALL.test(text(path));
// A script run as its own process gets no gh() a step defines: it wraps its
// own calls, itself or through a scripts/lib file it sources.
const WRAP = /\bapi_budget_wrap_gh\b/;
const scriptWraps = (path) => {
  const body = text(path);
  return WRAP.test(body) || [...body.matchAll(/\blib\/([\w.-]+\.(?:sh|bash))\b/g)].some(([, lib]) => WRAP.test(text(`scripts/lib/${lib}`)));
};
const scriptsOf = (step) => [...(step.run ?? "").matchAll(SCRIPT)].map(([, path]) => path).filter(scriptCallsGitHub);

const stepCallsGitHub = (step) => {
  if (step.uses && GH_ACTION.test(step.uses.split("@")[0].split(" ")[0])) return true;
  return GH_CALL.test(step.run ?? "") || scriptsOf(step).length > 0;
};

// A job logs its budget through this action under always(), or through the
// shell library's api_budget_emit, as ci-status does with no checkout.
const covered = (job) => {
  const { steps } = job;
  const logs = steps.some(
    (s) => (s.uses?.split(" ")[0].endsWith("/actions/log-api-budget") && /always\(\)/.test(s.if ?? "")) || /\bapi_budget_emit\b/.test(s.run ?? ""),
  );
  // A sourced script runs in the step's shell, under the gh() it defines.
  const sourcedUnderWrap = (path) =>
    steps.some((s) => WRAP.test(s.run ?? "") && new RegExp(`(?:^|[\\s;{(])(?:\\.|source) ["']?(?:\\.base/)?${path.replaceAll(".", "\\.")}`, "m").test(s.run));
  const unwrapped = steps.flatMap(scriptsOf).filter((path) => !scriptWraps(path) && !sourcedUnderWrap(path));
  const scripts = steps.flatMap(scriptsOf);
  const token =
    job.env?.API_BUDGET_TOKEN || steps.some((s) => s.env?.API_BUDGET_TOKEN || WRAP.test(s.run ?? "")) || (scripts.length > 0 && unwrapped.length === 0);
  return [
    logs ? null : "no job-end log-api-budget step",
    token ? null : "no API_BUDGET_TOKEN",
    ...[...new Set(unwrapped)].map((path) => `${path} does not wrap its gh calls`),
  ].filter(Boolean);
};

const gaps = () => {
  const found = [];
  for (const file of readdirSync(WORKFLOWS).filter((f) => /\.ya?ml$/.test(f)).sort()) {
    const { jobs = {} } = parse(readFileSync(new URL(file, WORKFLOWS), "utf8")) ?? {};
    for (const [id, job] of Object.entries(jobs)) {
      if (!job.steps?.some(stepCallsGitHub)) continue;
      const allowed = ALLOWED.get(file);
      if (allowed === "*" || allowed?.includes?.(id)) continue;
      const missing = covered(job);
      if (missing.length) found.push(`${file}:${id}: ${missing.join("; ")}`);
    }
  }
  return found;
};

test("every job that calls the GitHub API logs its api budget", () => {
  assert.deepEqual(gaps(), []);
});

test("the detector sees each kind of GitHub call", () => {
  assert.equal(stepCallsGitHub({ run: 'sha=$(gh api "repos/x/pulls/1")' }), true);
  assert.equal(stepCallsGitHub({ run: "gh issue create --title t" }), true);
  assert.equal(stepCallsGitHub({ run: "bash .base/.github/scripts/lib/handoff-evidence.sh posted" }), true);
  assert.equal(stepCallsGitHub({ uses: "./.base/.github/actions/resolve-config # zizmor: ignore[self-repository]" }), true);
  assert.equal(stepCallsGitHub({ uses: "./.github/actions/check-trusted-trigger" }), true);
  assert.equal(stepCallsGitHub({ run: "bash scripts/claude-code-release-issues.sh" }), true);
  assert.equal(stepCallsGitHub({ run: "npm test" }), false);
  assert.equal(stepCallsGitHub({ uses: "actions/checkout@v7" }), false);
});
