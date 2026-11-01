// Every workflow job that calls the GitHub API leaves api-budget readings and
// logs them at its end, so the lane record's githubCalls covers the job: the
// job (or the calling step) sets API_BUDGET_TOKEN, and a final always() step
// runs this action. A job calls GitHub when a step:
//   - runs `gh api|issue|pr|run|workflow|release|label|search|repo`, or
//     handoff-evidence.sh or dispatcher-current.sh;
//   - runs a repository script (scripts/ or .github/scripts/, .sh or .bash)
//     whose own text does any of those;
//   - uses resolve-config or check-trusted-trigger.
// It does not see GitHub calls made from Node or Python (an api-budget.mjs
// caller, babysit_gh.py), through a script a script runs or a scripts/lib file
// a script sources, or through other gh subcommands.
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path/posix";
import { test } from "node:test";

import { parse } from "yaml";

const ROOT = new URL("../../../", import.meta.url);
const WORKFLOWS = new URL(".github/workflows/", ROOT);

// Jobs that call GitHub and are not yet covered, each with the exact gap the
// detector reports for it, so a gap that grows, shrinks or closes fails.
const RESOLVE = "resolve-config without API_BUDGET_TOKEN";
const NO_CHECKOUT = "no job-end log-api-budget step; no API_BUDGET_TOKEN";
const LANE_JOB =
  "no job-end log-api-budget step; check-trusted-trigger without API_BUDGET_TOKEN; resolve-config without API_BUDGET_TOKEN";
const DECIDE_REBUILD =
  "no API_BUDGET_TOKEN; .github/scripts/release-publish-plugins/decide-rebuild.sh does not wrap its gh calls";
const REPORT_ESCALATION =
  ".github/scripts/pr-unblock/report-escalation.sh does not wrap its gh calls";
const ALLOWED = new Map([
  // The lane jobs.
  ["pr-run-activity-read.yml:run", LANE_JOB],
  ["pr-run-activity-write.yml:run", LANE_JOB],
  // No checkout to load the log-api-budget action from.
  ["intake-triage.yml:redispatch-refined", NO_CHECKOUT],
  ["intake-triage.yml:triage-split-children", NO_CHECKOUT],
  ["pr-review-main.yml:record", NO_CHECKOUT],
  // The step's own gh pr and gh api calls.
  ["dependabot-fragments.yml:write", "no API_BUDGET_TOKEN"],
  // The detector judges selection-audit.sh by the whole file; trace, the mode
  // this job runs, makes none of its gh calls (red-replay does).
  [
    "maintenance-audit-test-selection.yml:audit-test-selection",
    "no job-end log-api-budget step",
  ],
  ["release-publish-plugins.yml:build", DECIDE_REBUILD],
  ["release-publish-plugins.yml:merge", DECIDE_REBUILD],
  // report-escalation.sh runs as its own process.
  ["pr-require-checks.yml:ci-status", REPORT_ESCALATION],
  ["pr-unblock.yml:report-stop-status", REPORT_ESCALATION],
  // resolve-config and check-trusted-trigger read readings into
  // API_BUDGET_TOKEN's bucket only when the job or step sets it.
  ["intake-triage.yml:apply-refinement", RESOLVE],
  ["pr-merge.yml:merge", RESOLVE],
  ["pr-merge.yml:enable-auto-merge", RESOLVE],
  ["pr-review-main.yml:review", RESOLVE],
  ["pr-review-main.yml:review-subscription", RESOLVE],
  ["pr-review-main.yml:review-fallback", RESOLVE],
  ["pr-unblock.yml:adjudicate-feedback", RESOLVE],
  ["pr-verify.yml:check-intent", RESOLVE],
  ["pr-verify.yml:check-intent-subscription", RESOLVE],
  ["pr-verify.yml:check-intent-fallback", RESOLVE],
  ["work-unblock.yml:label-unblocked", RESOLVE],
  [
    "pr-unblock-dispatch.yml:dispatch",
    "check-trusted-trigger without API_BUDGET_TOKEN",
  ],
]);

const GH_CALL =
  /(?:^|[\s;&|({`$])gh (?:api|issue|pr|run|workflow|release|label|search|repo)\b|handoff-evidence\.sh|dispatcher-current\.sh/m;
const GH_ACTION = /\/actions\/(?:resolve-config|check-trusted-trigger)$/;
const SCRIPT =
  /(?:^|[\s"'])(?:\.base\/)?((?:\.github\/)?scripts\/[\w./-]+\.(?:sh|bash))\b/g;
const WRAP = /\bapi_budget_wrap_gh\b/;
// The self-wrap line: source the wrapper by a path relative to the script,
// then call api_budget_wrap_gh <token>.
const SELF_WRAP =
  /\.\s+"\$\{BASH_SOURCE\[0\]%\/\*\}\/([\w./-]*api-budget\.bash)"[^\n]*\bapi_budget_wrap_gh [a-z]/;

const repoFs = {
  read: (path) => {
    const file = new URL(path, ROOT);
    return existsSync(file) ? readFileSync(file, "utf8") : "";
  },
  exists: (path) => existsSync(new URL(path, ROOT)),
};

// The detector over a file system of repository-relative paths.
const detector = ({ read, exists }) => {
  const actionOf = (step) =>
    step.uses
      ?.split("@")[0]
      .split(" ")[0]
      .match(GH_ACTION)?.[0]
      .slice("/actions/".length);
  const scriptsOf = (step) =>
    [...(step.run ?? "").matchAll(SCRIPT)]
      .map(([, path]) => path)
      .filter((path) => GH_CALL.test(read(path)));
  // A script run as its own process gets no gh() a step defines: it wraps its
  // own calls by sourcing a wrapper file that exists and defines
  // api_budget_wrap_gh.
  const scriptWraps = (path) => {
    const rel = read(path).match(SELF_WRAP)?.[1];
    if (!rel) return false;
    const wrapper = join(dirname(path), rel);
    return exists(wrapper) && /\bapi_budget_wrap_gh\(\)/.test(read(wrapper));
  };
  const stepCallsGitHub = (step) =>
    Boolean(actionOf(step)) ||
    GH_CALL.test(step.run ?? "") ||
    scriptsOf(step).length > 0;

  // A job logs its budget through this action under always(), or through the
  // shell library's api_budget_emit, as ci-status does with no checkout.
  const covered = (job) => {
    const { steps } = job;
    const logs = steps.some(
      (s) =>
        (s.uses?.split(" ")[0].endsWith("/actions/log-api-budget") &&
          /always\(\)/.test(s.if ?? "")) ||
        /\bapi_budget_emit\b/.test(s.run ?? ""),
    );
    // A sourced script runs in the step's shell, under the gh() it defines.
    const sourcedUnderWrap = (path) =>
      steps.some(
        (s) =>
          WRAP.test(s.run ?? "") &&
          new RegExp(
            `(?:^|[\\s;{(])(?:\\.|source) ["']?(?:\\.base/)?${path.replaceAll(".", "\\.")}`,
            "m",
          ).test(s.run),
      );
    const scripts = steps.flatMap(scriptsOf);
    const unwrapped = scripts.filter(
      (path) => !scriptWraps(path) && !sourcedUnderWrap(path),
    );
    // The actions read API_BUDGET_TOKEN from their own environment; a script's
    // self-wrap does not reach them.
    const actionGaps = steps
      .filter(
        (s) =>
          actionOf(s) && !job.env?.API_BUDGET_TOKEN && !s.env?.API_BUDGET_TOKEN,
      )
      .map((s) => `${actionOf(s)} without API_BUDGET_TOKEN`);
    const shellCalls = steps.some(
      (s) => GH_CALL.test(s.run ?? "") || scriptsOf(s).length > 0,
    );
    const token =
      !shellCalls ||
      job.env?.API_BUDGET_TOKEN ||
      steps.some((s) => s.env?.API_BUDGET_TOKEN || WRAP.test(s.run ?? "")) ||
      (scripts.length > 0 && unwrapped.length === 0);
    return [
      logs ? null : "no job-end log-api-budget step",
      token ? null : "no API_BUDGET_TOKEN",
      ...new Set(actionGaps),
      ...[...new Set(unwrapped)].map(
        (path) => `${path} does not wrap its gh calls`,
      ),
    ].filter(Boolean);
  };

  // Every gap in { file: parsed workflow }, as `file:job: what is missing`.
  const gaps = (workflows) =>
    Object.entries(workflows).flatMap(([file, wf]) =>
      Object.entries(wf?.jobs ?? {})
        .filter(([, job]) => job.steps?.some(stepCallsGitHub))
        .map(([id, job]) => [`${file}:${id}`, covered(job)])
        .filter(([, missing]) => missing.length)
        .map(([key, missing]) => `${key}: ${missing.join("; ")}`),
    );
  return { stepCallsGitHub, covered, gaps };
};

const repo = detector(repoFs);
const repoWorkflows = () =>
  Object.fromEntries(
    readdirSync(WORKFLOWS)
      .filter((f) => /\.ya?ml$/.test(f))
      .sort()
      .map((f) => [f, parse(readFileSync(new URL(f, WORKFLOWS), "utf8"))]),
  );

// The repository's gaps are exactly the allowlist's: a job outside it with a
// gap fails, and so does an allowlisted job whose gap grew, shrank or closed.
test("every job that calls the GitHub API logs its api budget", () => {
  assert.deepEqual(
    repo.gaps(repoWorkflows()).sort(),
    [...ALLOWED].map(([key, missing]) => `${key}: ${missing}`).sort(),
  );
});

test("the detector sees each kind of GitHub call", () => {
  const { stepCallsGitHub } = repo;
  assert.equal(
    stepCallsGitHub({ run: 'sha=$(gh api "repos/x/pulls/1")' }),
    true,
  );
  assert.equal(stepCallsGitHub({ run: "gh issue create --title t" }), true);
  for (const sub of ["run", "workflow", "release", "label", "search", "repo"]) {
    assert.equal(stepCallsGitHub({ run: `gh ${sub} list` }), true, `gh ${sub}`);
  }
  assert.equal(
    stepCallsGitHub({
      run: "bash .base/.github/scripts/lib/handoff-evidence.sh posted",
    }),
    true,
  );
  assert.equal(
    stepCallsGitHub({
      uses: "./.base/.github/actions/resolve-config # zizmor: ignore[self-repository]",
    }),
    true,
  );
  assert.equal(
    stepCallsGitHub({ uses: "./.github/actions/check-trusted-trigger" }),
    true,
  );
  assert.equal(
    stepCallsGitHub({ run: "bash scripts/claude-code-release-issues.sh" }),
    true,
  );
  assert.equal(stepCallsGitHub({ run: "gh auth status" }), false);
  assert.equal(stepCallsGitHub({ run: "npm test" }), false);
  assert.equal(stepCallsGitHub({ uses: "actions/checkout@v7" }), false);
});

// Fixtures: a wrapper, a script that wraps through it, one whose source path
// misses it, and one with no wrap at all.
const WRAPPER = ".github/actions/log-api-budget/api-budget.bash";
const files = {
  [WRAPPER]: "api_budget_wrap_gh() {\n  :\n}\n",
  "scripts/wraps.sh": `[[ -z "\${RUNNER_TEMP:-}" ]] || ! . "\${BASH_SOURCE[0]%/*}/../${WRAPPER}" 2>/dev/null || api_budget_wrap_gh github-token\ngh api x\n`,
  "scripts/wrong-path.sh": `[[ -z "\${RUNNER_TEMP:-}" ]] || ! . "\${BASH_SOURCE[0]%/*}/../../${WRAPPER}" 2>/dev/null || api_budget_wrap_gh github-token\ngh api x\n`,
  "scripts/bare.sh": "gh issue list\n",
  "scripts/names-only.sh":
    "# api_budget_wrap_gh is defined elsewhere\ngh pr view 1\n",
};
const fixture = detector({
  read: (path) => files[path] ?? "",
  exists: (path) => path in files,
});
const LOG = { uses: "./.base/.github/actions/log-api-budget", if: "always()" };
const env = { API_BUDGET_TOKEN: "github-token" };

test("covered() names each missing piece", () => {
  const { covered } = fixture;
  assert.deepEqual(
    covered({ env, steps: [{ run: "bash scripts/wraps.sh" }, LOG] }),
    [],
  );
  assert.deepEqual(covered({ env, steps: [{ run: "gh api x" }] }), [
    "no job-end log-api-budget step",
  ]);
  assert.deepEqual(
    covered({ env, steps: [{ run: "gh api x" }, { ...LOG, if: "success()" }] }),
    ["no job-end log-api-budget step"],
  );
  assert.deepEqual(covered({ steps: [{ run: "gh api x" }, LOG] }), [
    "no API_BUDGET_TOKEN",
  ]);
  assert.deepEqual(
    covered({ env, steps: [{ run: "bash scripts/bare.sh" }, LOG] }),
    ["scripts/bare.sh does not wrap its gh calls"],
  );
  assert.deepEqual(
    covered({ env, steps: [{ run: "bash scripts/names-only.sh" }, LOG] }),
    ["scripts/names-only.sh does not wrap its gh calls"],
  );
  assert.deepEqual(
    covered({ steps: [{ run: "bash scripts/wrong-path.sh" }, LOG] }),
    ["no API_BUDGET_TOKEN", "scripts/wrong-path.sh does not wrap its gh calls"],
  );
  // A self-wrapping script gives the job no token for the actions.
  assert.deepEqual(
    covered({
      steps: [
        { uses: "./.github/actions/resolve-config" },
        { run: "bash scripts/wraps.sh" },
        LOG,
      ],
    }),
    ["resolve-config without API_BUDGET_TOKEN"],
  );
  assert.deepEqual(
    covered({
      steps: [{ uses: "./.github/actions/check-trusted-trigger", env }, LOG],
    }),
    [],
  );
});

test("gaps() reports each uncovered job by file and id", () => {
  const workflows = {
    "a.yml": {
      jobs: {
        ok: { env, steps: [{ run: "gh api x" }, LOG] },
        nolog: { env, steps: [{ run: "gh api x" }] },
        quiet: { steps: [{ run: "npm test" }] },
      },
    },
    "b.yml": {
      jobs: { script: { steps: [{ run: "bash .base/scripts/bare.sh" }, LOG] } },
    },
  };
  assert.deepEqual(fixture.gaps(workflows), [
    "a.yml:nolog: no job-end log-api-budget step",
    "b.yml:script: no API_BUDGET_TOKEN; scripts/bare.sh does not wrap its gh calls",
  ]);
});
