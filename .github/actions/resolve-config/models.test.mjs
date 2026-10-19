// The `models` block: schema, cross-checks, resolution, the arguments and
// settings a profile becomes, and what the live config gives every model run.
// The live expectations are the values each run got before the block existed,
// written by hand from the runners: no --model and 75 turns for every skill
// activity (pr-run-activity-read.yml and pr-run-activity-write.yml inputs
// default-model '' and default-max-turns 75, which no caller overrode), and
// --model opus with --max-turns 60 for pr-verify.yml (merge.verifier-model
// opus, its hard-coded --max-turns 60). No run passed --effort or a settings
// env.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

import { parse, stringify } from "yaml";

import { main } from "./resolve-config.mjs";
import { modelArgs, modelSettings, Rejection, resolve, resolveRoute } from "./resolve.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "../../..");
const read = (relative) => readFileSync(join(ROOT, relative), "utf8");
const json = (relative) => JSON.parse(read(relative));
const CONFIG_PATH = "docs/conventions/pr-pipeline.yaml";
const SCHEMA_PATH = "docs/conventions/pr-pipeline/pr-pipeline.schema.json";
const VOCABULARY_PATH = ".github/standards/github-actions-conventions/vocabulary.json";
const OWN = {
  schema: json(SCHEMA_PATH),
  laneRules: json(".github/actions/resolve-config/lane-rules.json"),
  effectGrants: json(".github/actions/resolve-config/effect-grants.json"),
  activityRules: json(".github/actions/resolve-config/activity-rules.json"),
};
const LIVE = { ...OWN, config: read(CONFIG_PATH), vocabulary: json(VOCABULARY_PATH) };
const FIXTURE = {
  ...OWN,
  config: read(".github/actions/resolve-config/fixtures/valid.yaml"),
  vocabulary: json(".github/actions/resolve-config/fixtures/vocabulary.json"),
};

const assertRejected = (fn, code) =>
  assert.throws(fn, (error) => {
    assert.ok(error instanceof Rejection, `expected a Rejection, got ${error}`);
    assert.equal(error.code, code, error.message);
    return true;
  });

// Facts under which every live skill activity's predicate applies.
const LIVE_FACTS = {
  event: "labeled",
  changedPaths: ["docs/guide.md"],
  changedTargets: ["docs/guide.md"],
  // resolve-issue applies only while its issue carries agent-ready.
  labels: ["agent-ready"],
  workClasses: [],
  mergeable: "conflicting",
  draft: false,
  labeledAt: "2026-10-16T00:00:00Z",
};
const liveSlot = (lane, activity) =>
  resolve(LIVE, { lane, activity, configPath: CONFIG_PATH, basePath: ".base", facts: LIVE_FACTS })
    .selected;

const DEFAULT_RUN = {
  model: "default",
  effort: null,
  "subagent-model": "inherit",
  "max-turns": 75,
};

for (const [lane, activity] of [
  ["pr-refine", "fix-docs"],
  ["pr-unblock", "resolve-conflicts"],
  ["pr-unblock", "address-feedback"],
  ["pr-unblock", "review-dependency"],
  ["work-resolve-issue", "resolve-issue"],
]) {
  test(`live config: ${lane} / ${activity} keeps no --model and 75 turns`, () => {
    const slot = liveSlot(lane, activity);
    assert.deepEqual(slot.models, { profile: "standard", ...DEFAULT_RUN });
    assert.equal(modelArgs(slot.models), "--max-turns 75");
    assert.equal(modelSettings(slot.models), "");
  });
}

test("live config: a script activity resolves no models", () => {
  assert.equal(liveSlot("pr-unblock", "report-escalation").models, null);
});

test("live config: verify-pr keeps --model opus and 60 turns", () => {
  const models = resolveRoute(LIVE, { route: "verify-pr", configPath: CONFIG_PATH });
  assert.deepEqual(models, {
    profile: "review",
    model: "opus",
    effort: null,
    "subagent-model": "inherit",
    "max-turns": 60,
  });
  assert.equal(modelArgs(models), "--model opus --max-turns 60");
  assert.equal(modelSettings(models), "");
});

// The review and triage routes have no caller yet. Their values are owner
// decisions: both review lanes keep the Sonnet, effort high, 75 turns the
// ci-workflows review callers pass today; triage moves to Sonnet at effort
// medium with 30 turns.
for (const [route, profile, args] of [
  ["review-code", "pr-review", "--model sonnet --max-turns 75 --effort high"],
  ["review-security", "pr-review", "--model sonnet --max-turns 75 --effort high"],
  ["triage-issue", "triage", "--model sonnet --max-turns 30 --effort medium"],
  // Owner decision: the reuse summary is a short read-only pass at a low turn budget.
  ["summarize-reuse", "summary", "--model sonnet --max-turns 10 --effort medium"],
]) {
  test(`live config: ${route} resolves ${args}`, () => {
    const models = resolveRoute(LIVE, { route, configPath: CONFIG_PATH });
    assert.equal(models.profile, profile);
    assert.equal(modelArgs(models), args);
    assert.equal(modelSettings(models), "");
  });
}

// A fixture config with a models block, or `null` to leave the block out.
const withModels = (models) => {
  const doc = parse(FIXTURE.config);
  if (models !== null) {
    doc.models = models;
  }
  return { ...FIXTURE, config: stringify(doc) };
};
const fixtureSlot = (files, lane = "pr-refine", activity = "fix-docs") =>
  resolve(files, { lane, activity, configPath: CONFIG_PATH, basePath: ".base", facts: { event: "synchronize", changedPaths: ["src/app.js"] } })
    .selected;
const PROFILES = {
  light: { model: "sonnet", effort: "medium", "max-turns": 40 },
  wide: { model: "opus", "subagent-model": "sonnet", "max-turns": 120 },
};

test("a route picks its profile, and every other skill activity takes default-profile", () => {
  const files = withModels({ profiles: PROFILES, "default-profile": "wide", routes: { "fix-docs": "light" } });
  assert.deepEqual(fixtureSlot(files).models, {
    profile: "light",
    model: "sonnet",
    effort: "medium",
    "subagent-model": "inherit",
    "max-turns": 40,
  });
  assert.equal(fixtureSlot(files, "pr-run-checks", "measure-coverage").models.profile, "wide");
});

test("a models block with no routes sends every skill activity to default-profile", () => {
  const files = withModels({ profiles: PROFILES, "default-profile": "light" });
  assert.equal(fixtureSlot(files).models.profile, "light");
  assert.equal(fixtureSlot(files, "pr-run-checks", "measure-coverage").models.profile, "light");
});

test("a config with no models block takes the built-in standard profile: no --model, 75 turns", () => {
  const { models } = fixtureSlot(withModels(null));
  assert.deepEqual(models, { profile: "standard", ...DEFAULT_RUN });
  assert.equal(modelArgs(models), "--max-turns 75");
});

test("a profile becomes --model, --max-turns and --effort, and its subagent model becomes settings env", () => {
  const files = withModels({ profiles: PROFILES, "default-profile": "wide", routes: { "fix-docs": "light" } });
  assert.equal(modelArgs(fixtureSlot(files).models), "--model sonnet --max-turns 40 --effort medium");
  const wide = fixtureSlot(files, "pr-run-checks", "measure-coverage").models;
  assert.equal(modelArgs(wide), "--model opus --max-turns 120");
  assert.equal(modelSettings(wide), '{"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"sonnet"}}');
});

for (const [why, models] of [
  ["a full model ID", { profiles: { p: { model: "claude-opus-5-5", "max-turns": 5 } }, "default-profile": "p" }],
  ["an unknown effort", { profiles: { p: { model: "opus", effort: "huge", "max-turns": 5 } }, "default-profile": "p" }],
  ["a profile with no max-turns", { profiles: { p: { model: "opus" } }, "default-profile": "p" }],
  ["a zero max-turns", { profiles: { p: { model: "opus", "max-turns": 0 } }, "default-profile": "p" }],
  ["a subagent model ID", { profiles: { p: { model: "opus", "subagent-model": "claude-sonnet-5", "max-turns": 5 } }, "default-profile": "p" }],
  ["an unknown profile key", { profiles: { p: { model: "opus", "max-turns": 5, advisor: "fable" } }, "default-profile": "p" }],
  ["no default-profile", { profiles: { p: { model: "opus", "max-turns": 5 } } }],
  ["no profiles", { profiles: {}, "default-profile": "p" }],
  ["an unknown models key", { profiles: { p: { model: "opus", "max-turns": 5 } }, "default-profile": "p", sizes: ["S"] }],
]) {
  test(`the schema rejects ${why}`, () => {
    assertRejected(() => fixtureSlot(withModels(models)), "invalid-config");
  });
}

test("the schema rejects the removed activity model and max-turns keys and merge.verifier-model", () => {
  for (const extra of [{ model: "opus" }, { "max-turns": 30 }]) {
    const doc = parse(FIXTURE.config);
    Object.assign(doc.activities["fix-docs"], extra);
    assertRejected(() => fixtureSlot({ ...FIXTURE, config: stringify(doc) }), "invalid-config");
  }
  const doc = parse(FIXTURE.config);
  doc.merge = { "verifier-model": "opus" };
  assertRejected(() => fixtureSlot({ ...FIXTURE, config: stringify(doc) }), "invalid-config");
});

test("the schema rejects a version 1 config, the contract before models", () => {
  const doc = parse(FIXTURE.config);
  doc.version = 1;
  assertRejected(() => fixtureSlot({ ...FIXTURE, config: stringify(doc) }), "invalid-config");
});

test("a default-profile or route naming no profile is undefined-profile", () => {
  const profiles = { p: { model: "opus", "max-turns": 5 } };
  assertRejected(() => fixtureSlot(withModels({ profiles, "default-profile": "q" })), "undefined-profile");
  assertRejected(
    () => fixtureSlot(withModels({ profiles, "default-profile": "p", routes: { "fix-docs": "q" } })),
    "undefined-profile",
  );
});

test("a route naming a script activity or nothing known is undefined-route", () => {
  const profiles = { p: { model: "opus", "max-turns": 5 } };
  for (const route of ["run-tests", "fix-doc"]) {
    assertRejected(
      () => fixtureSlot(withModels({ profiles, "default-profile": "p", routes: { [route]: "p" } })),
      "undefined-route",
    );
  }
  assertRejected(() => resolveRoute(LIVE, { route: "fix-docs", configPath: CONFIG_PATH }), "undefined-route");
});

test("a run route that is not one of the five is undefined-route, as a model-route and as a config route", () => {
  assertRejected(() => resolveRoute(LIVE, { route: "review-docs", configPath: CONFIG_PATH }), "undefined-route");
  const profiles = { p: { model: "opus", "max-turns": 5 } };
  assertRejected(
    () => fixtureSlot(withModels({ profiles, "default-profile": "p", routes: { "review-docs": "p" } })),
    "undefined-route",
  );
});

// main() with model-route against a base holding the live config.
const scratch = mkdtempSync(join(tmpdir(), "resolve-models-"));
after(() => rmSync(scratch, { recursive: true, force: true }));

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

function routeEnv(extra = {}) {
  const base = mkdtempSync(join(scratch, "base-"));
  for (const relative of [CONFIG_PATH, SCHEMA_PATH, VOCABULARY_PATH]) {
    mkdirSync(dirname(join(base, relative)), { recursive: true });
    writeFileSync(join(base, relative), read(relative));
  }
  const output = join(base, "github-output.txt");
  writeFileSync(output, "");
  return {
    BASE_PATH: base,
    MODEL_ROUTE: "verify-pr",
    OUTPUT_PATH: join(base, "resolved.json"),
    GITHUB_OUTPUT: output,
    ...extra,
  };
}

test("main with model-route verify-pr writes the verifier's outputs and file", async () => {
  const env = routeEnv();
  assert.equal(await main({ env }), 0);
  assert.deepEqual(readOutputs(env.GITHUB_OUTPUT), {
    profile: "review",
    "claude-args": "--model opus --max-turns 60",
    "settings-json": "",
    "max-turns": "60",
    model: "opus",
    effort: "",
  });
  assert.equal(JSON.parse(readFileSync(env.OUTPUT_PATH, "utf8")).models.profile, "review");
});

test("main with model-route triage-issue writes the triage profile's outputs", async () => {
  const env = routeEnv({ MODEL_ROUTE: "triage-issue" });
  assert.equal(await main({ env }), 0);
  assert.deepEqual(readOutputs(env.GITHUB_OUTPUT), {
    profile: "triage",
    "claude-args": "--model sonnet --max-turns 30 --effort medium",
    "settings-json": "",
    "max-turns": "30",
    model: "sonnet",
    effort: "medium",
  });
});

// A launcher caller (run-claude-cli) takes model and effort as inputs. A
// `default` model passes no --model, which the launcher cannot express, so its
// model output is empty and the caller fails on it.
test("main gives a default model and an unset effort as empty model and effort outputs", async () => {
  const env = routeEnv();
  const doc = parse(readFileSync(join(env.BASE_PATH, CONFIG_PATH), "utf8"));
  doc.models.profiles.review.model = "default";
  writeFileSync(join(env.BASE_PATH, CONFIG_PATH), stringify(doc));
  assert.equal(await main({ env }), 0);
  const outputs = readOutputs(env.GITHUB_OUTPUT);
  assert.equal(outputs.model, "");
  assert.equal(outputs.effort, "");
  assert.equal(outputs["claude-args"], "--max-turns 60");
});

test("main refuses an unknown model-route, and writes no file", async () => {
  const env = routeEnv({ MODEL_ROUTE: "review-docs" });
  assert.equal(await main({ env }), 1);
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), "");
  assert.throws(() => readFileSync(env.OUTPUT_PATH));
});

test("main refuses model-route beside a lane, and writes no file", async () => {
  const env = routeEnv({ LANE: "pr-refine" });
  assert.equal(await main({ env }), 1);
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), "");
  assert.throws(() => readFileSync(env.OUTPUT_PATH));
});
