import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

import { main } from "./resolve-config.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, "resolve-config.mjs");
const FIXTURES = join(HERE, "fixtures");
const LIVE_SCHEMA = join(
  HERE,
  "../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json",
);
const CONFIG_PATH = "docs/conventions/pr-pipeline.yaml";
const SCHEMA_PATH = "docs/conventions/pr-pipeline/pr-pipeline.schema.json";
const VOCABULARY_PATH =
  ".github/standards/github-actions-conventions/vocabulary.json";

const scratch = mkdtempSync(join(tmpdir(), "resolve-config-"));
after(() => rmSync(scratch, { recursive: true, force: true }));
let counter = 0;

function place(root, relative, source) {
  mkdirSync(dirname(join(root, relative)), { recursive: true });
  copyFileSync(source, join(root, relative));
}

// A workspace whose `.base/` holds the config, the live schema and the fixture
// vocabulary. `head` puts a config at the workspace root, where the PR head
// would be checked out.
function workspace({
  config = "valid.yaml",
  configPath = CONFIG_PATH,
  head,
  vocabulary = true,
} = {}) {
  counter += 1;
  const root = join(scratch, `ws-${counter}`);
  const base = join(root, ".base");
  mkdirSync(base, { recursive: true });
  if (config !== null) {
    place(base, configPath, join(FIXTURES, config));
  }
  place(base, SCHEMA_PATH, LIVE_SCHEMA);
  if (vocabulary) {
    place(base, VOCABULARY_PATH, join(FIXTURES, "vocabulary.json"));
  }
  if (head) {
    place(root, configPath, join(FIXTURES, head));
  }
  const event = join(root, "event.json");
  writeFileSync(
    event,
    JSON.stringify({
      action: "synchronize",
      pull_request: { number: 42, labels: [] },
    }),
  );
  const output = join(root, "github-output.txt");
  writeFileSync(output, "");
  return {
    root,
    base,
    env: {
      LANE: "pr-run-checks",
      ACTIVITY: "run-tests",
      BASE_PATH: base,
      CONFIG_PATH: configPath,
      OUTPUT_PATH: join(root, "resolved.json"),
      EVENT_NAME: "pull_request",
      EVENT_PATH: event,
      PR_NUMBER: "42",
      REPOSITORY: "melodic-software/claude-code-plugins",
      GITHUB_OUTPUT: output,
    },
  };
}

// Reads the delimited GITHUB_OUTPUT form back into an object.
function readOutputs(path) {
  const outputs = {};
  const lines = readFileSync(path, "utf8").split("\n");
  for (let index = 0; index < lines.length; index += 1) {
    const match = /^([^<]+)<<(.+)$/.exec(lines[index]);
    if (match) {
      const end = lines.indexOf(match[2], index + 1);
      outputs[match[1]] = lines.slice(index + 1, end).join("\n");
      index = end;
    }
  }
  return outputs;
}

// A fake API: each route is a path prefix and its response; every call is logged.
function fakeGitHub(routes) {
  const calls = [];
  const github = async (method, path) => {
    calls.push(`${method} ${path}`);
    for (const [prefix, respond] of Object.entries(routes)) {
      if (path.startsWith(prefix)) {
        return respond(path);
      }
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { github, calls };
}

const noApi = fakeGitHub({}).github;

const fileList = (count, prefix = "src/f") =>
  Array.from({ length: count }, (_, index) => ({
    filename: `${prefix}${index}.js`,
  }));

// Serves `files` 100 to a page, as pulls/{n}/files does.
function pullRoutes({ changedFiles, files, labels = [] }) {
  return {
    "/repos/melodic-software/claude-code-plugins/pulls/42/files": (path) => {
      const page = Number(new URL(path, "https://x").searchParams.get("page"));
      return files.slice((page - 1) * 100, page * 100);
    },
    "/repos/melodic-software/claude-code-plugins/pulls/42": () => ({
      number: 42,
      changed_files: changedFiles,
      labels: labels.map((name) => ({ name })),
    }),
  };
}

// valid.yaml's pr-run-checks lane has a paths predicate, so it reads the PR.
const srcChanged = () =>
  fakeGitHub(pullRoutes({ changedFiles: 1, files: [{ filename: "src/a.js" }] }))
    .github;

// Exit 1, no file, no outputs, and an error annotation naming the cause.
async function assertFailsRed(t, env, cause, github = noApi) {
  const log = t.mock.method(console, "log", () => {});
  const code = await main({ env, github });
  const messages = log.mock.calls.map((call) => String(call.arguments[0]));
  log.mock.restore();
  assert.equal(code, 1);
  assert.equal(
    existsSync(env.OUTPUT_PATH),
    false,
    "no ResolvedConfig is written on a rejection",
  );
  assert.deepEqual(
    readOutputs(env.GITHUB_OUTPUT),
    {},
    "no step output is written on a rejection",
  );
  assert.ok(
    messages.some(
      (message) => message.startsWith("::error") && cause.test(message),
    ),
    `expected an error matching ${cause}, got ${messages.join(" | ")}`,
  );
}

// A valid run

test("a valid config writes ResolvedConfig and the selected activity's outputs", async () => {
  const { env } = workspace();
  assert.equal(await main({ env, github: srcChanged() }), 0);
  const resolved = JSON.parse(readFileSync(env.OUTPUT_PATH, "utf8"));
  assert.equal(resolved.selected.name, "run-tests");
  assert.deepEqual(resolved.source, {
    "base-path": env.BASE_PATH,
    "config-path": CONFIG_PATH,
  });
  assert.deepEqual(readOutputs(env.GITHUB_OUTPUT), {
    enabled: "true",
    slots: '["run-tests","measure-coverage"]',
    kind: "script",
    effect: "read",
    gating: "gate",
    skill: "",
    script: "scripts/run-tests.sh",
    model: "",
    "max-turns": "",
    "reads-untrusted": "false",
    applies: "true",
    "skip-reason": "",
    contents: "read",
    "pull-requests": "read",
    issues: "read",
    "can-commit": "false",
  });
});

test("a mutate-branch activity can commit; args stay in the file only", async () => {
  const { env } = workspace();
  env.LANE = "pr-refine";
  env.ACTIVITY = "fix-docs";
  assert.equal(await main({ env, github: noApi }), 0);
  const outputs = readOutputs(env.GITHUB_OUTPUT);
  assert.deepEqual(
    [outputs.contents, outputs["can-commit"], outputs.skill, outputs.gating],
    ["write", "true", "ai-slop:audit", "advisory"],
  );
  assert.equal(Object.hasOwn(outputs, "args"), false);
});

test("without an activity only enabled and slots are output", async () => {
  const { env } = workspace();
  env.ACTIVITY = "";
  assert.equal(await main({ env, github: srcChanged() }), 0);
  assert.deepEqual(readOutputs(env.GITHUB_OUTPUT), {
    enabled: "true",
    slots: '["run-tests","measure-coverage"]',
  });
  assert.equal(
    JSON.parse(readFileSync(env.OUTPUT_PATH, "utf8")).selected,
    null,
  );
});

// Base vs head

function runCli(root, env) {
  const result = spawnSync(process.execPath, [CLI], {
    cwd: root,
    env: { PATH: process.env.PATH, ...env, BASE_PATH: "" },
    encoding: "utf8",
  });
  return result;
}

test("base vs head: a head config that disables the activity is ignored; the base enables it", () => {
  const { root, env } = workspace({
    config: "base/head-disables.yaml",
    head: "head/head-disables.yaml",
  });
  const result = runCli(root, env);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const selected = JSON.parse(readFileSync(env.OUTPUT_PATH, "utf8")).selected;
  assert.deepEqual([selected.enabled, selected["skip-reason"]], [true, null]);
});

test("base vs head: a head config that enables the activity is ignored; the base disables it", () => {
  const { root, env } = workspace({
    config: "base/head-enables.yaml",
    head: "head/head-enables.yaml",
  });
  const result = runCli(root, env);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  const resolved = JSON.parse(readFileSync(env.OUTPUT_PATH, "utf8"));
  assert.deepEqual(
    [resolved.selected.enabled, resolved.selected["skip-reason"]],
    [false, "disabled-by-config"],
  );
  assert.equal(resolved.source["base-path"], ".base");
});

test("base vs head: with no base config, the head config is never read", async (t) => {
  const { env } = workspace({ config: null, head: "valid.yaml" });
  await assertFailsRed(t, env, /no config file/);
});

test("a config symlink that leaves base-path fails red", async (t) => {
  const { root, base, env } = workspace({ config: null, head: "valid.yaml" });
  mkdirSync(dirname(join(base, CONFIG_PATH)), { recursive: true });
  symlinkSync(join(root, CONFIG_PATH), join(base, CONFIG_PATH));
  await assertFailsRed(t, env, /outside base-path/);
});

// Every rejection fails red with no file

const REJECTIONS = [
  [
    "rejection 1: a schema-invalid config",
    /fails the schema/,
    { config: "schema-invalid.yaml" },
  ],
  [
    "rejection 1: no config file under base-path",
    /no config file/,
    { config: null },
  ],
  ["rejection 2: extends with a value", /extends/, { config: "extends.yaml" }],
  [
    "rejection 3: an effect the lane forbids",
    /may not run/,
    { config: "forbidden-effect.yaml" },
  ],
  [
    "rejection 3: a gate in pr-explain",
    /may not run/,
    { config: "forbidden-gating.yaml" },
    { LANE: "pr-explain", ACTIVITY: "explain" },
  ],
  [
    "rejection 4: a stage that differs from lane-rules.json",
    /lane-rules.json says/,
    { config: "stage-mismatch.yaml" },
  ],
  [
    "rejection 4: a lane with no lane-rules.json row",
    /no row in lane-rules.json/,
    { config: "unknown-lane.yaml" },
    { LANE: "pr-review-docs" },
  ],
  [
    "rejection 5: a needs entry outside the lane",
    /not in the lane/,
    { config: "needs-outside-lane.yaml" },
  ],
  [
    "rejection 6: an activity name the vocabulary refuses",
    /accepted verb/,
    { config: "activity-not-in-vocabulary.yaml" },
  ],
  [
    "rejection 6: no vocabulary under base-path",
    /vocabulary is missing/,
    { vocabulary: false },
  ],
  [
    "rejection 7: a slot naming an undefined activity",
    /not defined/,
    { config: "undefined-activity.yaml" },
  ],
  [
    "rejection 7: a requested activity absent from the lane",
    /0 slots for activity/,
    {},
    { ACTIVITY: "fix-docs" },
  ],
  [
    "rejection 7: a requested lane absent from the config",
    /no lane `pr-review`/,
    {},
    { LANE: "pr-review" },
  ],
  [
    "rejection 8: a config-path with ..",
    /contains `\.\.`/,
    { configPath: "docs/pr-pipeline.yaml" },
    { CONFIG_PATH: "docs/conventions/../pr-pipeline.yaml" },
  ],
  [
    "rejection 8: a config-path whose basename is not pr-pipeline.yaml",
    /basename other than pr-pipeline.yaml/,
    { configPath: "docs/conventions/valid.yaml" },
  ],
  [
    "rejection 8: a config-path under .github/actions",
    /under \.github\/actions/,
    { configPath: ".github/actions/resolve-config/fixtures/pr-pipeline.yaml" },
  ],
  [
    "rejection 9: an activity named run",
    /pr-run-activity job name/,
    { config: "reserved-run.yaml" },
    { ACTIVITY: "run" },
  ],
  [
    "rejection 9: an activity named report",
    /pr-run-activity job name/,
    { config: "reserved-report.yaml" },
    { ACTIVITY: "report" },
  ],
];

for (const [name, cause, tree, envOverrides = {}] of REJECTIONS) {
  test(`${name} fails red with no output file`, async (t) => {
    const { env } = workspace(tree);
    await assertFailsRed(t, { ...env, ...envOverrides }, cause);
  });
}

test("rejection 8: an absolute config-path fails red with no output file", async (t) => {
  const { base, env } = workspace();
  await assertFailsRed(
    t,
    { ...env, CONFIG_PATH: join(base, CONFIG_PATH) },
    /is absolute/,
  );
});

test("a stale output file is removed before a rejection, so it never reads as valid", async (t) => {
  const { env } = workspace({ config: "extends.yaml" });
  writeFileSync(env.OUTPUT_PATH, "{}");
  await assertFailsRed(t, env, /extends/);
});

test("no output-path fails red", async (t) => {
  const { env } = workspace();
  t.mock.method(console, "log", () => {});
  const code = await main({ env: { ...env, OUTPUT_PATH: "" }, github: noApi });
  assert.equal(code, 1);
  assert.deepEqual(readOutputs(env.GITHUB_OUTPUT), {});
});

test("an error message cannot start a second workflow command", async (t) => {
  const { env } = workspace();
  await assertFailsRed(
    t,
    { ...env, LANE: "x\n::set-output name=a::b" },
    /no lane `x%0A::set-output/,
  );
});

// Changed paths from pulls/{n}/files

test("a paths predicate reads the PR's changed files through the API", async () => {
  const { env } = workspace();
  env.ACTIVITY = "measure-coverage";
  const { github, calls } = fakeGitHub(
    pullRoutes({
      changedFiles: 2,
      files: [{ filename: "src/a.js" }, { filename: "docs/b.md" }],
    }),
  );
  assert.equal(await main({ env, github }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "true");
  assert.ok(
    calls.some((call) =>
      call.startsWith(
        "GET /repos/melodic-software/claude-code-plugins/pulls/42/files",
      ),
    ),
  );
});

test("a renamed file's previous path counts as changed", async () => {
  const { env } = workspace();
  env.ACTIVITY = "measure-coverage";
  const files = [{ filename: "lib/a.js", previous_filename: "src/a.js" }];
  assert.equal(
    await main({
      env,
      github: fakeGitHub(pullRoutes({ changedFiles: 1, files })).github,
    }),
    0,
  );
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "true");
});

test("changed-paths holds the head's changed files minus removed ones and the base CODEOWNERS paths", async () => {
  const { env } = workspace();
  const config = join(env.BASE_PATH, CONFIG_PATH);
  writeFileSync(
    config,
    readFileSync(config, "utf8").replace(
      "    effect: mutate-branch\n",
      "    effect: mutate-branch\n    inputs: [changed-paths]\n",
    ),
  );
  mkdirSync(join(env.BASE_PATH, ".github"), { recursive: true });
  writeFileSync(
    join(env.BASE_PATH, ".github/CODEOWNERS"),
    "/plugins/ai-slop/** @owner\n",
  );
  env.LANE = "pr-refine";
  env.ACTIVITY = "fix-docs";
  const files = [
    { filename: "docs/kept.md", status: "modified" },
    { filename: "docs/gone.md", status: "removed" },
    {
      filename: "docs/new.md",
      previous_filename: "docs/old.md",
      status: "renamed",
    },
    { filename: "plugins/ai-slop/README.md", status: "modified" },
  ];
  const { github } = fakeGitHub(pullRoutes({ changedFiles: 4, files }));
  assert.equal(await main({ env, github }), 0);
  const resolved = JSON.parse(readFileSync(env.OUTPUT_PATH, "utf8"));
  assert.deepEqual(resolved.selected["changed-paths"], [
    "docs/kept.md",
    "docs/new.md",
  ]);
  assert.equal(
    Object.hasOwn(readOutputs(env.GITHUB_OUTPUT), "changed-paths"),
    false,
  );
});

test("a paths miss outputs not-applicable-paths", async () => {
  const { env } = workspace();
  env.ACTIVITY = "measure-coverage";
  const routes = pullRoutes({
    changedFiles: 1,
    files: [{ filename: "docs/b.md" }],
  });
  assert.equal(await main({ env, github: fakeGitHub(routes).github }), 0);
  const outputs = readOutputs(env.GITHUB_OUTPUT);
  assert.deepEqual(
    [outputs.applies, outputs["skip-reason"]],
    ["false", "not-applicable-paths"],
  );
});

test("pulls/{n}/files returning 3000 files fails red with no output file", async (t) => {
  const { env } = workspace();
  env.ACTIVITY = "measure-coverage";
  const github = fakeGitHub(
    pullRoutes({ changedFiles: 3000, files: fileList(3000) }),
  ).github;
  await assertFailsRed(t, env, /listed 3000 of 3000 changed files/, github);
});

test("pulls/{n}/files returning fewer files than changed_files fails red with no output file", async (t) => {
  const { env } = workspace();
  env.ACTIVITY = "measure-coverage";
  const github = fakeGitHub(
    pullRoutes({ changedFiles: 5, files: fileList(4) }),
  ).github;
  await assertFailsRed(t, env, /listed 4 of 5 changed files/, github);
});

test("a paths predicate with no PR number fails red", async (t) => {
  const { env } = workspace();
  await assertFailsRed(
    t,
    { ...env, ACTIVITY: "measure-coverage", PR_NUMBER: "" },
    /no pr-number/,
  );
});

test("another slot's paths predicate makes no API call for the selected activity", async () => {
  const { env } = workspace();
  const { github, calls } = fakeGitHub({});
  assert.equal(await main({ env: { ...env, PR_NUMBER: "" }, github }), 0);
  assert.deepEqual(calls, []);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "true");
});

test("a config with no predicate makes no API call", async () => {
  const { env } = workspace();
  const config = join(env.BASE_PATH, CONFIG_PATH);
  writeFileSync(
    config,
    readFileSync(config, "utf8").replace(
      / {4}applies-when:\n {6}paths: \["src\/\*\*"\]\n/,
      "",
    ),
  );
  const { github, calls } = fakeGitHub({});
  assert.equal(await main({ env, github }), 0);
  assert.deepEqual(calls, []);
});

// Labels, events and work classes

// Gives valid.yaml's fix-docs activity (lane pr-refine) a predicate.
function withPredicate(env, predicate) {
  const config = join(env.BASE_PATH, CONFIG_PATH);
  writeFileSync(
    config,
    readFileSync(config, "utf8").replace(
      "    effect: mutate-branch\n",
      `    effect: mutate-branch\n    applies-when: ${JSON.stringify(predicate)}\n`,
    ),
  );
  env.LANE = "pr-refine";
  env.ACTIVITY = "fix-docs";
}

test("labels come from the pull_request payload without an API call", async () => {
  const { env } = workspace();
  writeFileSync(
    env.EVENT_PATH,
    JSON.stringify({
      action: "labeled",
      pull_request: { labels: [{ name: "docs" }] },
    }),
  );
  withPredicate(env, { labels: ["docs"], events: ["labeled"] });
  const { github, calls } = fakeGitHub({});
  assert.equal(await main({ env, github }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "true");
  assert.deepEqual(calls, []);
});

test("on workflow_dispatch, labels come from the PR and the event maps to dispatch", async () => {
  const { env } = workspace();
  writeFileSync(env.EVENT_PATH, JSON.stringify({ inputs: {} }));
  env.EVENT_NAME = "workflow_dispatch";
  withPredicate(env, { labels: ["docs"], events: ["dispatch"] });
  const { github } = fakeGitHub(
    pullRoutes({ changedFiles: 0, files: [], labels: ["docs"] }),
  );
  assert.equal(await main({ env, github }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "true");
});

// An issues lane: the event payload is the issue, and there is no PR.
function issueEvent(env, issue) {
  writeFileSync(env.EVENT_PATH, JSON.stringify({ action: "labeled", issue }));
  env.EVENT_NAME = "issues";
  env.PR_NUMBER = "";
}

test("on an issues event, labels come from the issue payload and the event maps to labeled", async () => {
  const { env } = workspace();
  issueEvent(env, { number: 7, labels: [{ name: "work-class: read-only" }], updated_at: "2026-10-20T00:00:00Z" });
  withPredicate(env, { labels: ["work-class: read-only"], events: ["labeled"] });
  const { github, calls } = fakeGitHub({});
  assert.equal(await main({ env, github }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "true");
  assert.deepEqual(calls, []);
});

test("on an issues event, a missing label skips with not-applicable", async () => {
  const { env } = workspace();
  issueEvent(env, { number: 7, labels: [{ name: "work-class: scoped" }], updated_at: "2026-10-20T00:00:00Z" });
  withPredicate(env, { labels: ["work-class: read-only"] });
  assert.equal(await main({ env, github: noApi }), 0);
  const outputs = readOutputs(env.GITHUB_OUTPUT);
  assert.equal(outputs.applies, "false");
  assert.equal(outputs["skip-reason"], "not-applicable");
});

test("labeled-after applies to an issue labeled after the cutover", async () => {
  const { env } = workspace();
  issueEvent(env, { number: 7, labels: [], updated_at: "2026-10-20T00:00:01Z" });
  withPredicate(env, { "labeled-after": "2026-10-20T00:00:00Z" });
  assert.equal(await main({ env, github: noApi }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "true");
});

test("labeled-after skips an issue labeled before the cutover with not-applicable", async () => {
  const { env } = workspace();
  issueEvent(env, { number: 7, labels: [], updated_at: "2026-10-19T23:59:59Z" });
  withPredicate(env, { "labeled-after": "2026-10-20T00:00:00Z" });
  assert.equal(await main({ env, github: noApi }), 0);
  const outputs = readOutputs(env.GITHUB_OUTPUT);
  assert.equal(outputs.applies, "false");
  assert.equal(outputs["skip-reason"], "not-applicable");
});

test("labeled-after fails red off an issues event, which carries no label time", async (t) => {
  const { env } = workspace();
  withPredicate(env, { "labeled-after": "2026-10-20T00:00:00Z" });
  await assertFailsRed(t, env, /needs labeledAt/);
});

test("on an issues event, labels-absent reads the issue's labels now", async () => {
  const { env } = workspace();
  issueEvent(env, { number: 7, labels: [], updated_at: "2026-10-20T00:00:00Z" });
  withPredicate(env, { "labels-absent": ["needs-human"] });
  const { github, calls } = fakeGitHub({
    "/repos/melodic-software/claude-code-plugins/issues/7": () => ({ number: 7, labels: [{ name: "needs-human" }] }),
  });
  assert.equal(await main({ env, github }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT)["skip-reason"], "awaiting-human");
  assert.deepEqual(calls, ["GET /repos/melodic-software/claude-code-plugins/issues/7"]);
});

// The owner's batch-ratification marker, as kyle-sexton (a listed human in the
// fixture list) posted it on #7597.
const MARKER = "<!-- admission: admitted when unblocked, owner batch ratification 2026-10-16 -->\n";
const OWNER = { id: 153232337, login: "kyle-sexton" };
const LANES_APP = { id: 337595936, login: "melodic-automation-lanes[bot]" };

// An agent-ready issue with no work class under an admission predicate that
// takes ratification, its comments served by the fake API.
function ratifiedIssue(comments) {
  const { env, base } = workspace();
  place(base, ".github/standards/trusted-actors/trusted-actors.json", join(HERE, "../check-trusted-trigger/fixtures/trusted-actors.json"));
  issueEvent(env, { number: 7, labels: [{ name: "agent-ready" }], updated_at: "2026-10-20T00:00:00Z" });
  withPredicate(env, { events: ["labeled"], admission: { classes: ["work-class: read-only"], ratified: true } });
  const { github, calls } = fakeGitHub({
    "/repos/melodic-software/claude-code-plugins/issues/7/comments": (path) =>
      new URL(path, "https://x").searchParams.get("page") === "1" ? comments : [],
  });
  return { env, github, calls };
}

const comment = (user, body = MARKER, app = null) => ({ user, body, performed_via_github_app: app });

test("an issue the owner ratified with the admission marker is admitted with no work class", async () => {
  const { env, github, calls } = ratifiedIssue([comment(OWNER)]);
  assert.equal(await main({ env, github }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "true");
  assert.deepEqual(calls, ["GET /repos/melodic-software/claude-code-plugins/issues/7/comments?per_page=100&page=1"]);
});

// D33: a lane never admits work on its own, so the lanes App cannot ratify.
test("an admission marker authored by the lanes App does not admit", async () => {
  const { env, github } = ratifiedIssue([comment(LANES_APP, MARKER, { slug: "melodic-automation-lanes" })]);
  assert.equal(await main({ env, github }), 0);
  const outputs = readOutputs(env.GITHUB_OUTPUT);
  assert.equal(outputs.applies, "false");
  assert.equal(outputs["skip-reason"], "not-applicable");
});

test("an admission marker from anyone but a listed human admits nothing", async () => {
  const cases = [
    comment({ id: 1234, login: "someone-else" }),
    // A listed bot.
    comment({ id: 209825114, login: "claude[bot]" }),
    // The owner's account, through a GitHub App.
    comment(OWNER, MARKER, { slug: "some-app" }),
  ];
  for (const marker of cases) {
    const { env, github } = ratifiedIssue([marker]);
    assert.equal(await main({ env, github }), 0);
    const outputs = readOutputs(env.GITHUB_OUTPUT);
    assert.equal(outputs.applies, "false", JSON.stringify(marker));
    assert.equal(outputs["skip-reason"], "not-applicable");
  }
});

test("an owner comment that only quotes or misstates the marker admits nothing", async () => {
  for (const body of [
    `> ${MARKER}`,
    "<!-- admission: admitted when unblocked, owner batch ratification -->",
    "We will add `<!-- admission: admitted when unblocked, owner batch ratification 2026-10-16 -->` later.",
  ]) {
    const { env, github } = ratifiedIssue([comment(OWNER, body)]);
    assert.equal(await main({ env, github }), 0);
    assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "false", body);
  }
});

test("an admission predicate that takes ratification fails red off an issues event", async (t) => {
  const { env } = workspace();
  withPredicate(env, { admission: { classes: ["work-class: read-only"], ratified: true } });
  await assertFailsRed(t, env, /needs ratified/);
});

test("a work-classes predicate fails red: no run supplies work classes yet", async (t) => {
  const { env } = workspace();
  withPredicate(env, { "work-classes": ["C2"] });
  await assertFailsRed(t, env, /needs workClasses/);
});

// valid.yaml's fix-docs (lane pr-refine) with prepare: merge-base and `extra`.
function withPrepare(env, extra = "") {
  const config = join(env.BASE_PATH, CONFIG_PATH);
  writeFileSync(
    config,
    readFileSync(config, "utf8").replace(
      "    effect: mutate-branch\n",
      `    effect: mutate-branch\n    prepare: merge-base\n${extra}`,
    ),
  );
  env.LANE = "pr-refine";
  env.ACTIVITY = "fix-docs";
}

test("a leaf's prepare mode is a step output, set only when the leaf declares one", async () => {
  const { env } = workspace();
  withPrepare(env);
  env.PREPARE_SUPPORTED = "true";
  assert.equal(await main({ env, github: noApi }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).prepare, "merge-base");
});

test("an applying leaf with prepare fails red unless the runner declares prepare support", async (t) => {
  for (const supported of [undefined, "", "false", "TRUE"]) {
    const { env } = workspace();
    withPrepare(env);
    if (supported === undefined) {
      delete env.PREPARE_SUPPORTED;
    } else {
      env.PREPARE_SUPPORTED = supported;
    }
    await assertFailsRed(t, env, /prepare-supported/);
  }
});

test("a leaf with prepare that does not apply resolves without prepare support", async () => {
  const { env } = workspace();
  withPrepare(env, "    applies-when:\n      labels: [never-set]\n");
  assert.equal(await main({ env, github: noApi }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "false");
});

// mergeable, labels-absent and draft, from GET /pulls/{n}

const GATED_HEAD = "a".repeat(40);
const OTHER_HEAD = "b".repeat(40);

// Serves GET /pulls/42 from `reads` in turn, repeating the last one.
function pullReads(reads) {
  let index = 0;
  return fakeGitHub({
    "/repos/melodic-software/claude-code-plugins/pulls/42": () => {
      const read = reads[Math.min(index, reads.length - 1)];
      index += 1;
      return {
        number: 42,
        draft: false,
        labels: [],
        ...read,
        head: { sha: read.headSha ?? GATED_HEAD },
      };
    },
  });
}
const PULL = "GET /repos/melodic-software/claude-code-plugins/pulls/42";
const noSleep = async () => {};

function dispatchWithPredicate(env, predicate) {
  writeFileSync(env.EVENT_PATH, JSON.stringify({ inputs: {} }));
  env.EVENT_NAME = "workflow_dispatch";
  env.HEAD_SHA = GATED_HEAD;
  withPredicate(env, predicate);
}

test("mergeable false at the gated head reads as conflicting", async () => {
  const { env } = workspace();
  dispatchWithPredicate(env, { mergeable: ["conflicting"] });
  const { github, calls } = pullReads([{ mergeable: false }]);
  assert.equal(await main({ env, github, sleep: noSleep }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "true");
  assert.deepEqual(calls, [PULL]);
});

test("mergeable true reads as clean and misses a conflicting predicate", async () => {
  const { env } = workspace();
  dispatchWithPredicate(env, { mergeable: ["conflicting"] });
  const { github } = pullReads([{ mergeable: true }]);
  assert.equal(await main({ env, github, sleep: noSleep }), 0);
  assert.deepEqual(
    [
      readOutputs(env.GITHUB_OUTPUT).applies,
      readOutputs(env.GITHUB_OUTPUT)["skip-reason"],
    ],
    ["false", "not-applicable"],
  );
});

test("a null mergeable is re-read a bounded number of times, then skips with prerequisite-missing", async () => {
  const { env } = workspace();
  dispatchWithPredicate(env, { mergeable: ["conflicting"] });
  const { github, calls } = pullReads([{ mergeable: null }]);
  const sleeps = [];
  const sleep = async (ms) => {
    sleeps.push(ms);
  };
  assert.equal(await main({ env, github, sleep }), 0);
  const outputs = readOutputs(env.GITHUB_OUTPUT);
  assert.deepEqual(
    [outputs.applies, outputs["skip-reason"]],
    ["false", "prerequisite-missing"],
  );
  assert.equal(calls.length, 3);
  assert.equal(sleeps.length, 2);
});

test("a null mergeable that settles within the bound is used", async () => {
  const { env } = workspace();
  dispatchWithPredicate(env, { mergeable: ["conflicting"] });
  const { github, calls } = pullReads([
    { mergeable: null },
    { mergeable: false },
  ]);
  assert.equal(await main({ env, github, sleep: noSleep }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "true");
  assert.equal(calls.length, 2);
});

test("a mergeable read whose head.sha is not the gated head-sha is re-read, then skips with prerequisite-missing", async () => {
  const { env } = workspace();
  dispatchWithPredicate(env, { mergeable: ["conflicting"] });
  const { github, calls } = pullReads([
    { mergeable: false, headSha: OTHER_HEAD },
  ]);
  assert.equal(await main({ env, github, sleep: noSleep }), 0);
  assert.equal(
    readOutputs(env.GITHUB_OUTPUT)["skip-reason"],
    "prerequisite-missing",
  );
  assert.equal(calls.length, 3);
});

test("a mergeable read at another head that reaches the gated head within the bound is used", async () => {
  const { env } = workspace();
  dispatchWithPredicate(env, { mergeable: ["conflicting"] });
  const { github } = pullReads([
    { mergeable: true, headSha: OTHER_HEAD },
    { mergeable: false },
  ]);
  assert.equal(await main({ env, github, sleep: noSleep }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "true");
});

test("a mergeable predicate with no head-sha fails red", async (t) => {
  const { env } = workspace();
  dispatchWithPredicate(env, { mergeable: ["conflicting"] });
  delete env.HEAD_SHA;
  await assertFailsRed(
    t,
    env,
    /head-sha/,
    pullReads([{ mergeable: false }]).github,
  );
});

test("mergeable never comes from the event payload", async () => {
  const { env } = workspace();
  writeFileSync(
    env.EVENT_PATH,
    JSON.stringify({
      action: "synchronize",
      pull_request: { number: 42, labels: [], draft: false, mergeable: false },
    }),
  );
  env.HEAD_SHA = GATED_HEAD;
  withPredicate(env, { mergeable: ["conflicting"] });
  const { github, calls } = pullReads([{ mergeable: true }]);
  assert.equal(await main({ env, github, sleep: noSleep }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "false");
  assert.deepEqual(calls, [PULL]);
});

test("on workflow_dispatch, labels, draft and mergeable come from one GET /pulls/{n}", async () => {
  const { env } = workspace();
  dispatchWithPredicate(env, {
    mergeable: ["conflicting"],
    "labels-absent": ["do-not-merge", "needs-human"],
    draft: [false],
  });
  const { github, calls } = pullReads([
    { mergeable: false, draft: false, labels: [{ name: "C2" }] },
  ]);
  assert.equal(await main({ env, github, sleep: noSleep }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT).applies, "true");
  assert.deepEqual(calls, [PULL]);
});

test("a needs-human label skips with awaiting-human", async () => {
  const { env } = workspace();
  dispatchWithPredicate(env, {
    mergeable: ["conflicting"],
    "labels-absent": ["do-not-merge", "needs-human"],
  });
  const { github } = pullReads([
    { mergeable: false, labels: [{ name: "needs-human" }] },
  ]);
  assert.equal(await main({ env, github, sleep: noSleep }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT)["skip-reason"], "awaiting-human");
});

test("labels-absent reads labels from GET /pulls/{n}, not the event payload", async () => {
  const { env } = workspace();
  writeFileSync(
    env.EVENT_PATH,
    JSON.stringify({
      action: "synchronize",
      pull_request: { number: 42, labels: [], draft: false },
    }),
  );
  withPredicate(env, { "labels-absent": ["needs-human"] });
  const { github, calls } = pullReads([
    { labels: [{ name: "needs-human" }] },
  ]);
  assert.equal(await main({ env, github, sleep: noSleep }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT)["skip-reason"], "awaiting-human");
  assert.deepEqual(calls, [PULL]);
});

test("a draft PR misses draft: [false] with not-applicable", async () => {
  const { env } = workspace();
  dispatchWithPredicate(env, { draft: [false] });
  const { github } = pullReads([{ draft: true }]);
  assert.equal(await main({ env, github, sleep: noSleep }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT)["skip-reason"], "not-applicable");
});

test("on a pull_request event, draft comes from the payload without an API call", async () => {
  const { env } = workspace();
  writeFileSync(
    env.EVENT_PATH,
    JSON.stringify({
      action: "synchronize",
      pull_request: { number: 42, labels: [], draft: true },
    }),
  );
  withPredicate(env, { draft: [false] });
  const { github, calls } = fakeGitHub({});
  assert.equal(await main({ env, github, sleep: noSleep }), 0);
  assert.equal(readOutputs(env.GITHUB_OUTPUT)["skip-reason"], "not-applicable");
  assert.deepEqual(calls, []);
});
