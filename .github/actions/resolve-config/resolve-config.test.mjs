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
  const github = fakeGitHub(
    pullRoutes({ changedFiles: 3000, files: fileList(3000) }),
  ).github;
  await assertFailsRed(t, env, /listed 3000 of 3000 changed files/, github);
});

test("pulls/{n}/files returning fewer files than changed_files fails red with no output file", async (t) => {
  const { env } = workspace();
  const github = fakeGitHub(
    pullRoutes({ changedFiles: 5, files: fileList(4) }),
  ).github;
  await assertFailsRed(t, env, /listed 4 of 5 changed files/, github);
});

test("a paths predicate with no PR number fails red", async (t) => {
  const { env } = workspace();
  await assertFailsRed(t, { ...env, PR_NUMBER: "" }, /no pr-number/);
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

test("a work-classes predicate fails red: no run supplies work classes yet", async (t) => {
  const { env } = workspace();
  withPredicate(env, { "work-classes": ["C2"] });
  await assertFailsRed(t, env, /needs workClasses/);
});
