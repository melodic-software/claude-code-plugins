// test-scope: .github/workflows/*.yml .github/actions/*/action.yml .github/actions/resolve-config/package.json
// ADR 0085, "Lane model steps hold no write token": every job that runs a
// model holds no write scope, no write credential and no dependency cache, so
// a model steered by the text it reads can neither write nor plant an entry a
// later trusted job restores. No exception list: such a job needs a new ADR.
import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";

const { parse } = createRequire(new URL("../../actions/resolve-config/package.json", import.meta.url))("yaml");
const ROOT = new URL("../../../", import.meta.url);

const LAUNCHER = /^(melodic-software\/ci-workflows\/\.github\/actions\/run-claude-cli|anthropics\/claude-code-action)@/;
const runsModel = (step) => LAUNCHER.test(String(step.uses ?? "")) || /\bclaude\s+(-p|--print|plugin eval)\b/.test(String(step.run ?? ""));
const MODEL_SECRET = /claude[-_](api[-_]key|code[-_]oauth[-_]token)$/i;
const OFF = [undefined, "", false, "false"];

export function modelJobViolations(workflow, expand = (step) => [step]) {
  const found = [];
  for (const [id, job] of Object.entries(workflow.jobs ?? {})) {
    const steps = (job.steps ?? []).flatMap(expand);
    if (!steps.some(runsModel)) continue;
    const bad = (rule, what) => found.push(`${id}: ${rule}: ${what}`);
    const permissions = job.permissions ?? workflow.permissions ?? "the repository default";
    if (typeof permissions === "string") {
      if (permissions !== "read-all") bad("write scope", permissions);
    } else {
      for (const [scope, level] of Object.entries(permissions)) if (level === "write") bad("write scope", `${scope}: write`);
    }
    const text = JSON.stringify({ env: workflow.env, job });
    if (/toJSON\(\s*secrets\s*\)/.test(text)) bad("write credential", "toJSON(secrets)");
    for (const [, dotted, bracketed] of text.matchAll(/secrets(?:\.([\w-]+)|\[\s*'([^']+)'\s*\])/g)) {
      const name = dotted ?? bracketed;
      if (!MODEL_SECRET.test(name) && name !== "GITHUB_TOKEN") bad("write credential", `secrets.${name}`);
    }
    for (const step of steps) {
      const uses = String(step.uses ?? "");
      const input = step.with ?? {};
      if (/create-github-app-token/.test(uses)) bad("write credential", uses);
      if (/\/request-lane-token$/.test(uses.split("@")[0]) && input.mode !== "check") bad("write credential", `request-lane-token mode ${input.mode ?? "mint"}`);
      if (runsModel(step) && ("github_token" in input || "github-token" in input)) bad("write credential", "a GitHub token input to the model");
      if (/^actions\/cache(\/(restore|save))?@/.test(uses)) bad("dependency cache", uses);
      if (/\/setup-[\w-]+(@|$)/.test(uses) && !OFF.includes(input.cache)) bad("dependency cache", `${uses} cache: ${input.cache}`);
      // setup-node turns package-manager-cache on by default.
      if (/^actions\/setup-node@/.test(uses) && String(input["package-manager-cache"]) !== "false") bad("dependency cache", `${uses} package-manager-cache on`);
    }
  }
  return found;
}

const LAUNCH = { uses: "melodic-software/ci-workflows/.github/actions/run-claude-cli@abc", with: { "api-key": "${{ secrets.X_CLAUDE_API_KEY }}" } };
const NODE = { uses: "actions/setup-node@abc", with: { "package-manager-cache": false } };
const flow = (job = {}, top = {}) => ({ permissions: { contents: "read" }, ...top, jobs: { j: { steps: [NODE, LAUNCH], ...job } } });
const withStep = (step, model = LAUNCH) => flow({ steps: [step, model] });

const CASES = {
  "a read-only model job": [flow(), []],
  "a write job that runs no model": [flow({ permissions: { contents: "write" }, steps: [NODE] }), []],
  "a job read-all overriding workflow write-all": [flow({ permissions: "read-all" }, { permissions: "write-all" }), []],
  "a broker check": [withStep({ uses: "./.base/.github/actions/request-lane-token", with: { mode: "check" } }), []],
  "a quoted package-manager-cache false": [withStep({ uses: "actions/setup-node@abc", with: { "package-manager-cache": "false" } }), []],
  "a job write scope": [flow({ permissions: { contents: "read", "pull-requests": "write" } }), ["write scope"]],
  "a claude -p step with a write scope": [flow({ permissions: { issues: "write" }, steps: [{ run: "claude -p hi" }] }), ["write scope"]],
  "a claude-code-action step with a write scope": [flow({ permissions: { contents: "write" }, steps: [{ uses: "anthropics/claude-code-action@abc" }] }), ["write scope"]],
  "workflow write-all": [flow({}, { permissions: "write-all" }), ["write scope"]],
  "no permissions anywhere": [flow({}, { permissions: undefined }), ["write scope"]],
  "an App token step": [withStep({ uses: "actions/create-github-app-token@abc" }), ["write credential"]],
  "a lane-token mint": [withStep({ uses: "./.base/.github/actions/request-lane-token", with: { lane: "x" } }), ["write credential"]],
  "a PAT in step env": [withStep({ run: "true", env: { GH_TOKEN: "${{ secrets.LANE_PAT }}" } }), ["write credential"]],
  "a PAT in workflow env": [flow({}, { env: { GH_TOKEN: "${{ secrets['LANE_PAT'] }}" } }), ["write credential"]],
  "every secret at once": [withStep({ run: "true", env: { ALL: "${{ toJSON(secrets) }}" } }), ["write credential"]],
  "a github_token input to the model": [flow({ steps: [{ ...LAUNCH, with: { github_token: "${{ github.token }}" } }] }), ["write credential"]],
  "a github-token input to the model": [flow({ steps: [{ ...LAUNCH, with: { "github-token": "${{ github.token }}" } }] }), ["write credential"]],
  "actions/cache": [withStep({ uses: "actions/cache@abc" }), ["dependency cache"]],
  "actions/cache/restore": [withStep({ uses: "actions/cache/restore@abc" }), ["dependency cache"]],
  "actions/cache/save": [withStep({ uses: "actions/cache/save@abc" }), ["dependency cache"]],
  "a setup action with cache set": [withStep({ uses: "actions/setup-python@abc", with: { cache: "pip" } }), ["dependency cache"]],
  "setup-node with its default cache": [flow({ steps: [{ uses: "actions/setup-node@abc" }, LAUNCH] }), ["dependency cache"]],
  "a cache inside a composite": [flow({ steps: [{ uses: "./x" }, LAUNCH] }), ["dependency cache"], (s) => (s.uses === "./x" ? [s, { uses: "actions/cache@abc" }] : [s])],
};

for (const [name, [workflow, rules, expand]] of Object.entries(CASES)) {
  test(`model job rules: ${name}`, () => {
    assert.deepEqual(modelJobViolations(workflow, expand).map((v) => v.split(": ")[1]), rules);
  });
}

const expand = (step) => {
  const local = /^\.\/(?:\.base\/)?(\.github\/actions\/[\w-]+)$/.exec(String(step.uses ?? ""));
  const file = local && new URL(`${local[1]}/action.yml`, ROOT);
  if (!file || !existsSync(file)) return [step];
  return [step, ...(parse(readFileSync(file, "utf8")).runs?.steps ?? []).flatMap(expand)];
};

test("every model job in this repository's workflows holds no write scope, credential or cache", (t) => {
  const dir = new URL(".github/workflows/", ROOT);
  let jobs = 0;
  const files = new Set();
  const violations = [];
  for (const file of readdirSync(dir).filter((name) => /\.ya?ml$/.test(name))) {
    const workflow = parse(readFileSync(new URL(file, dir), "utf8"));
    for (const job of Object.values(workflow.jobs ?? {})) {
      if (!(job.steps ?? []).flatMap(expand).some(runsModel)) continue;
      jobs++;
      files.add(file);
    }
    violations.push(...modelJobViolations(workflow, expand).map((v) => `${file}#${v}`));
  }
  t.diagnostic(`${jobs} model jobs in ${files.size} workflow files`);
  assert.deepEqual(violations, []);
  assert.ok(jobs >= 36 && files.size >= 13, `only ${jobs} model jobs in ${files.size} files: the detector lost them`);
});
