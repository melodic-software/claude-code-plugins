// Every workflow job that calls the GitHub API leaves api-budget readings and
// logs them at its end, so the lane record's githubCalls covers the job: each
// step that runs gh itself wraps it with api_budget_wrap_gh (or sources
// api-budget.bash and records each response with api_budget_read), each script that
// runs as its own process wraps its own calls, the job (or the step) sets
// API_BUDGET_TOKEN for the actions below, and a final always() step runs this
// action. A job calls GitHub when a step:
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
const NO_LOG = "no job-end log-api-budget step";
const DECIDE_REBUILD =
  ".github/scripts/release-publish-plugins/decide-rebuild.sh does not wrap its gh calls";
const ALLOWED = new Map([
  // The lane jobs run PR head code, after which no step loads an action or
  // library from a checkout; logging here needs a trusted copy of the library.
  ["pr-run-activity-read.yml:run", NO_LOG],
  ["pr-run-activity-write.yml:run", NO_LOG],
  // No checkout to load the log-api-budget action from, and no contents: read
  // to check one out with.
  [
    "intake-triage.yml:redispatch-refined",
    `${NO_LOG}; step "Triage the refined issue again" calls gh without api_budget_wrap_gh`,
  ],
  [
    "intake-triage.yml:triage-split-children",
    `${NO_LOG}; step "Triage each sub-issue" calls gh without api_budget_wrap_gh`,
  ],
  [
    "pr-review-main.yml:record",
    `${NO_LOG}; step "Record the stops" calls gh without api_budget_wrap_gh; step "Record the counts" calls gh without api_budget_wrap_gh`,
  ],
  // Steps whose own gh calls run unwrapped, on the plugin release App's
  // token, which has no api-budget token name yet.
  [
    "dependabot-fragments.yml:write",
    'step "Write the fragments and open the pull request" calls gh without api_budget_wrap_gh',
  ],
  [
    "release-publish-plugins.yml:build",
    `step "Write the release commit" calls gh without api_budget_wrap_gh; step "Open or update the release pull request" calls gh without api_budget_wrap_gh; step "Name the skipped plugins on the open release pull request" calls gh without api_budget_wrap_gh; ${DECIDE_REBUILD}`,
  ],
  [
    "release-publish-plugins.yml:merge",
    `step "Queue the checked head" calls gh without api_budget_wrap_gh; ${DECIDE_REBUILD}`,
  ],
]);

const GH_CALL =
  /(?:^|[\s;&|({`$])gh (?:api|issue|pr|run|workflow|release|label|search|repo)\b|handoff-evidence\.sh|dispatcher-current\.sh/m;
const GH_ACTION = /\/actions\/(?:resolve-config|check-trusted-trigger)$/;
const SCRIPT =
  /(?:^|[\s"'])(?:\.base\/)?((?:\.github\/)?scripts\/[\w./-]+\.(?:sh|bash))\b/g;
const WRAP = /\bapi_budget_wrap_gh\b/;
// Sourcing api-budget.bash by a literal path, or by "$NAME" from the step env.
const LIB_SOURCE =
  /(?:^|[\s;{(])(?:\.|source) +(?:["']?((?:\.base\/)?[\w./-]*api-budget\.bash)\b|"\$\{?([A-Z_][A-Z0-9_]*)\}?")/gm;
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
  const sources = (run, path) =>
    new RegExp(
      `(?:^|[\\s;{(])(?:\\.|source) ["']?(?:\\.base/)?${path.replaceAll(".", "\\.")}`,
      "m",
    ).test(run);
  // A step's own gh calls go through the gh() its own shell defines, by
  // api_budget_wrap_gh or by sourcing a self-wrapping script; a wrap in
  // another step, or API_BUDGET_TOKEN, which only the Node clients read, does
  // not reach them. Script paths are left to the script rules.
  // A step that records its own readings sources the library, by its path or
  // by a step env variable holding it, and calls api_budget_read.
  const recordsOwn = ({ run = "", env = {} }) =>
    /\bapi_budget_read\b/.test(run) &&
    [...run.matchAll(LIB_SOURCE)].some(
      ([, path, name]) => path || /api-budget\.bash$/.test(env[name] ?? ""),
    );
  const ownCallsUnwrapped = (step) => {
    const run = step.run ?? "";
    return (
      GH_CALL.test(run.replaceAll(SCRIPT, " ")) &&
      !WRAP.test(run) &&
      !recordsOwn(step) &&
      ![...run.matchAll(SCRIPT)].some(
        ([, path]) => sources(run, path) && scriptWraps(path),
      )
    );
  };

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
      steps.some((s) => WRAP.test(s.run ?? "") && sources(s.run, path));
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
    // Named by the step's name, else its 0-based index in the job's steps.
    const stepGaps = steps
      .map((s, i) => [s, i])
      .filter(([s]) => ownCallsUnwrapped(s))
      .map(
        ([s, i]) => `step "${s.name ?? i}" calls gh without api_budget_wrap_gh`,
      );
    return [
      logs ? null : "no job-end log-api-budget step",
      ...new Set(actionGaps),
      ...stepGaps,
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
const WRAPPED = {
  name: "Wrapped",
  run: `. .base/${WRAPPER}\napi_budget_wrap_gh github-token\ngh api x`,
};
const BARE = { name: "Bare", run: "gh api x" };

test("covered() names each missing piece", () => {
  const { covered } = fixture;
  assert.deepEqual(
    covered({ steps: [{ run: "bash scripts/wraps.sh" }, LOG] }),
    [],
  );
  assert.deepEqual(covered({ steps: [WRAPPED, LOG] }), []);
  assert.deepEqual(covered({ steps: [WRAPPED] }), [
    "no job-end log-api-budget step",
  ]);
  assert.deepEqual(
    covered({ steps: [WRAPPED, { ...LOG, if: "success()" }] }),
    ["no job-end log-api-budget step"],
  );
  // API_BUDGET_TOKEN reaches the Node clients only, never a step's bare gh.
  assert.deepEqual(covered({ env, steps: [BARE, LOG] }), [
    'step "Bare" calls gh without api_budget_wrap_gh',
  ]);
  assert.deepEqual(covered({ steps: [{ run: "gh pr view 1" }, LOG] }), [
    'step "0" calls gh without api_budget_wrap_gh',
  ]);
  // A wrap in one step leaves another step's gh unwrapped.
  assert.deepEqual(covered({ env, steps: [WRAPPED, BARE, LOG] }), [
    'step "Bare" calls gh without api_budget_wrap_gh',
  ]);
  // A step that sources the library and records its own readings is covered,
  // by a literal path or a step env variable holding it; either half alone
  // is not.
  const READ = 'out=$(gh api -i x)\napi_budget_read github-token /dev/stdin <<<"$out"';
  assert.deepEqual(
    covered({ steps: [{ run: `. .base/${WRAPPER} || true\n${READ}` }, LOG] }),
    [],
  );
  assert.deepEqual(
    covered({
      steps: [
        { env: { LIB: `.base/${WRAPPER}` }, run: `. "$LIB" || true\n${READ}` },
        LOG,
      ],
    }),
    [],
  );
  assert.deepEqual(
    covered({ steps: [{ name: "Read", run: READ }, LOG] }),
    ['step "Read" calls gh without api_budget_wrap_gh'],
  );
  assert.deepEqual(
    covered({
      steps: [{ name: "Src", run: `. .base/${WRAPPER} || true\ngh api x` }, LOG],
    }),
    ['step "Src" calls gh without api_budget_wrap_gh'],
  );
  assert.deepEqual(
    covered({
      steps: [
        { name: "Env", env: { LIB: "other.sh" }, run: `. "$LIB"\n${READ}` },
        LOG,
      ],
    }),
    ['step "Env" calls gh without api_budget_wrap_gh'],
  );
  // Sourcing a self-wrapping script defines gh() in the step's shell.
  assert.deepEqual(
    covered({ steps: [{ run: ". scripts/wraps.sh\ngh api y" }, LOG] }),
    [],
  );
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
    ["scripts/wrong-path.sh does not wrap its gh calls"],
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
        ok: { steps: [WRAPPED, LOG] },
        bare: { env, steps: [BARE, LOG] },
        split: { steps: [WRAPPED, BARE, LOG] },
        nolog: { steps: [WRAPPED] },
        quiet: { steps: [{ run: "npm test" }] },
      },
    },
    "b.yml": {
      jobs: { script: { steps: [{ run: "bash .base/scripts/bare.sh" }, LOG] } },
    },
  };
  assert.deepEqual(fixture.gaps(workflows), [
    'a.yml:bare: step "Bare" calls gh without api_budget_wrap_gh',
    'a.yml:split: step "Bare" calls gh without api_budget_wrap_gh',
    "a.yml:nolog: no job-end log-api-budget step",
    "b.yml:script: scripts/bare.sh does not wrap its gh calls",
  ]);
});
