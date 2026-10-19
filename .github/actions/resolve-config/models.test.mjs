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
import { modelArgs, modelSettings, neededFacts, Rejection, resolve, resolveRoute } from "./resolve.mjs";

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
const TRUSTED_ACTORS_PATH = ".github/standards/trusted-actors/trusted-actors.json";
const LIVE = { ...OWN, config: read(CONFIG_PATH), vocabulary: json(VOCABULARY_PATH), trustedActors: json(TRUSTED_ACTORS_PATH) };
// A listed human in the live trusted-actor list, and an account not on it.
const LISTED = 153232337;
const UNLISTED = 42;
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
  // A listed human set the issue Small, Low and Known (the org's option ids).
  fieldValues: [
    { field: 15462270, option: 27053568 },
    { field: 48625720, option: 85127651 },
    { field: 48625721, option: 85127654 },
  ],
  fieldSetters: { 15462270: LISTED, 48625720: LISTED, 48625721: LISTED },
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
]) {
  test(`live config: ${lane} / ${activity} keeps no --model and 75 turns`, () => {
    const slot = liveSlot(lane, activity);
    assert.deepEqual(slot.models, { profile: "standard", ...DEFAULT_RUN });
    assert.equal(modelArgs(slot.models), "--max-turns 75");
    assert.equal(modelSettings(slot.models), "");
  });
}

// models.issue-dimensions: the live config's field and option ids (the org's,
// 2026-10-18) with fixture budgets in place of its tuning, so a tuning PR is a
// config-only edit. Turn cap = ceil(base-turns x complexity factor); the
// timeout is the size's; a skip takes the shortest size timeout.
const TUNING = {
  sizes: { small: { "base-turns": 11, "timeout-minutes": 7 }, medium: { "base-turns": 20, "timeout-minutes": 9 }, large: "split" },
  complexity: { low: 1, medium: 1.5, high: 2.5 },
  uncertainty: { known: "run", knowable: "research-first", unknown: "probe-first" },
};
const tunedConfig = () => {
  const doc = parse(LIVE.config);
  doc.models["issue-dimensions"] = { fields: doc.models["issue-dimensions"].fields, ...TUNING };
  return stringify(doc);
};
const TUNED = { ...LIVE, config: tunedConfig() };
const SIZE = { small: 27053568, medium: 27053567, large: 27053566 };
const COMPLEXITY = { low: 85127651, medium: 85127652, high: 85127653 };
const UNCERTAINTY = { known: 85127654, knowable: 85127655, unknown: 85127656 };
const fieldFacts = ({ size, complexity, uncertainty }, setter = LISTED) => {
  const rows = [
    [15462270, SIZE[size]],
    [48625720, COMPLEXITY[complexity]],
    [48625721, UNCERTAINTY[uncertainty]],
  ].filter(([, option]) => option !== undefined);
  return {
    fieldValues: rows.map(([field, option]) => ({ field, option })),
    fieldSetters: Object.fromEntries(rows.map(([field]) => [field, setter])),
  };
};
const issueSlot = (dims, { setter, labels = [], pinnedDimensions } = {}) =>
  resolve(TUNED, {
    lane: "work-resolve-issue",
    activity: "resolve-issue",
    configPath: CONFIG_PATH,
    basePath: ".base",
    facts: { ...LIVE_FACTS, labels: ["agent-ready", ...labels], ...fieldFacts(dims, setter) },
    pinnedDimensions,
  }).selected;

for (const [size, complexity, turns, minutes] of [
  ["small", "low", 11, 7],
  ["small", "medium", 17, 7],
  ["small", "high", 28, 7],
  ["medium", "low", 20, 9],
  ["medium", "high", 50, 9],
]) {
  test(`live config: a known ${size} ${complexity} issue runs at ${turns} turns for ${minutes} minutes`, () => {
    const slot = issueSlot({ size, complexity, uncertainty: "known" });
    assert.equal(slot.applies, true);
    assert.equal(slot["issue-dimensions"], `${size}/${complexity}/known`);
    assert.equal(slot["timeout-minutes"], minutes);
    assert.equal(modelArgs(slot.models), `--max-turns ${turns}`);
  });
}

for (const [why, dims, options, reason] of [
  ["an issue with no Complexity", { size: "small", uncertainty: "known" }, {}, "not-assessed"],
  ["an issue with no fields", {}, {}, "not-assessed"],
  ["fields an unlisted account set", { size: "small", complexity: "low", uncertainty: "known" }, { setter: UNLISTED }, "not-assessed"],
  ["a large issue", { size: "large", complexity: "low", uncertainty: "known" }, {}, "split-required"],
  ["a knowable issue", { size: "small", complexity: "low", uncertainty: "knowable" }, {}, "research-first"],
  ["an unknown issue", { size: "small", complexity: "low", uncertainty: "unknown" }, {}, "probe-first"],
]) {
  test(`live config: ${why} is refused with ${reason} before any model turn`, () => {
    const slot = issueSlot(dims, options);
    assert.equal(slot.applies, false);
    assert.equal(slot["skip-reason"], reason);
    assert.equal(slot["timeout-minutes"], 7);
  });
}

test("live config: a held large issue keeps its hold reason", () => {
  const slot = issueSlot({ size: "large", complexity: "low", uncertainty: "known" }, { labels: ["needs-human"] });
  assert.equal(slot["skip-reason"], "awaiting-human");
});

test("live config: an option id the config does not map fails the resolve", () => {
  const facts = { ...LIVE_FACTS, ...fieldFacts({ size: "small", complexity: "low", uncertainty: "known" }) };
  facts.fieldValues = facts.fieldValues.map((row) => (row.field === 48625720 ? { ...row, option: 1 } : row));
  assertRejected(
    () => resolve(TUNED, { lane: "work-resolve-issue", activity: "resolve-issue", configPath: CONFIG_PATH, basePath: ".base", facts }),
    "unmapped-dimension",
  );
});

// The run job takes what pick-slot read, whose timeout is already fixed: a
// field changed while the run waited for its slot cannot give it more turns.
test("live config: pinned dimensions win over fields changed since", () => {
  const slot = issueSlot({ size: "medium", complexity: "high", uncertainty: "known" }, { pinnedDimensions: "small/low/known" });
  assert.equal(slot["issue-dimensions"], "small/low/known");
  assert.equal(slot["timeout-minutes"], 7);
  assert.equal(modelArgs(slot.models), "--max-turns 11");
});

test("live config: a pinned not-assessed still refuses the run", () => {
  const slot = issueSlot({ size: "small", complexity: "low", uncertainty: "known" }, { pinnedDimensions: "not-assessed" });
  assert.equal(slot["skip-reason"], "not-assessed");
});

test("live config: pinned dimensions naming no entry are rejected", () => {
  assertRejected(() => issueSlot({}, { pinnedDimensions: "huge/low/known" }), "undefined-dimension");
});

test("live config: pinned dimensions read no fields", () => {
  const request = { lane: "work-resolve-issue", activity: "resolve-issue", configPath: CONFIG_PATH };
  assert.ok(neededFacts(LIVE, request).includes("fieldValues"));
  assert.ok(neededFacts(LIVE, request).includes("fieldSetters"));
  assert.ok(!neededFacts(LIVE, { ...request, pinnedDimensions: "small/low/known" }).includes("fieldValues"));
});

test("live config: no size label is read", () => {
  const request = { lane: "work-resolve-issue", activity: "resolve-issue", configPath: CONFIG_PATH };
  assert.ok(!neededFacts(LIVE, request).includes("labelers"));
});

test("live config: resolve-issue keeps the standard profile's model, its turns from its dimensions", () => {
  const slot = issueSlot({ size: "small", complexity: "low", uncertainty: "known" });
  assert.deepEqual(slot.models, { profile: "standard", ...DEFAULT_RUN, "max-turns": 11 });
  assert.equal(modelSettings(slot.models), "");
});

// The live tuning is checked for shape only: it loads, every org option is
// mapped, and an assessed, known issue of a size that runs applies.
test("live config: the live issue-dimensions maps every org option and runs a known small issue", () => {
  const live = resolve(LIVE, {
    lane: "work-resolve-issue",
    activity: "resolve-issue",
    configPath: CONFIG_PATH,
    basePath: ".base",
    facts: { ...LIVE_FACTS, ...fieldFacts({ size: "small", complexity: "low", uncertainty: "known" }) },
  }).selected;
  assert.equal(live.applies, true);
  const { fields } = parse(LIVE.config).models["issue-dimensions"];
  for (const [name, ids] of [["size", SIZE], ["complexity", COMPLEXITY], ["uncertainty", UNCERTAINTY]]) {
    assert.deepEqual(Object.keys(fields[name].options).sort(), Object.values(ids).map(String).sort(), name);
  }
});

test("live config: an activity with no issue input takes no dimensions", () => {
  const slot = liveSlot("pr-refine", "fix-docs");
  assert.equal(slot["issue-dimensions"], undefined);
  assert.equal(slot["timeout-minutes"], undefined);
});

const DIMS = {
  fields: {
    size: { "field-id": 1, options: { 11: "small", 12: "large" } },
    complexity: { "field-id": 2, options: { 21: "low" } },
    uncertainty: { "field-id": 3, options: { 31: "known" } },
  },
  sizes: { small: { "base-turns": 10, "timeout-minutes": 5 }, large: "split" },
  complexity: { low: 1 },
  uncertainty: { known: "run" },
};
for (const [why, dims, code] of [
  ["an option mapped to no size", { ...DIMS, fields: { ...DIMS.fields, size: { "field-id": 1, options: { 11: "huge" } } } }, "undefined-dimension"],
  ["one field id for two dimensions", { ...DIMS, fields: { ...DIMS.fields, complexity: { "field-id": 1, options: { 21: "low" } } } }, "undefined-dimension"],
  ["no size that runs", { ...DIMS, sizes: { large: "split" } }, "undefined-dimension"],
  ["a size with no timeout", { ...DIMS, sizes: { small: { "base-turns": 10 } } }, "invalid-config"],
  ["a size value other than split", { ...DIMS, sizes: { ...DIMS.sizes, large: "skip" } }, "invalid-config"],
  ["a complexity factor of 0", { ...DIMS, complexity: { low: 0 } }, "invalid-config"],
  ["an uncertainty mode outside the enum", { ...DIMS, uncertainty: { known: "maybe" } }, "invalid-config"],
  ["a non-numeric option id", { ...DIMS, fields: { ...DIMS.fields, size: { "field-id": 1, options: { small: "small" } } } }, "invalid-config"],
]) {
  test(`issue-dimensions: ${why} is rejected`, () => {
    const profiles = { p: { model: "opus", "max-turns": 5 } };
    assertRejected(() => fixtureSlot(withModels({ profiles, "default-profile": "p", "issue-dimensions": dims })), code);
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
  for (const relative of [CONFIG_PATH, SCHEMA_PATH, VOCABULARY_PATH, TRUSTED_ACTORS_PATH]) {
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

// Canned answers in the shapes recorded live on pr-pipeline-sandbox#167
// (REST issue-field-values and the GraphQL field events, 2026-10-18).
const fieldRow = (field, option) => ({
  issue_field_id: field,
  data_type: "single_select",
  value: option,
  single_select_option: { id: option, name: "x", color: "red" },
});
const fieldEvent = (type, field, actor) => ({
  __typename: type,
  actor: { databaseId: actor },
  issueField: { fullDatabaseId: String(field) },
});
async function mainOnIssue(events) {
  const env = routeEnv({
    MODEL_ROUTE: "",
    LANE: "work-resolve-issue",
    ACTIVITY: "resolve-issue",
    EVENT_NAME: "issues",
    REPOSITORY: "o/r",
  });
  writeFileSync(join(env.BASE_PATH, CONFIG_PATH), TUNED.config);
  const issue = { number: 7, updated_at: "2026-10-18T00:00:00Z", labels: [] };
  const calls = [];
  const github = async (method, path, body, headers) => {
    calls.push({ method, path, headers });
    if (path === "/repos/o/r/issues/7/issue-field-values") {
      return [fieldRow(15462270, 27053567), fieldRow(48625720, 85127653), fieldRow(48625721, 85127654)];
    }
    if (path === "/graphql") {
      assert.deepEqual(body.variables, { owner: "o", name: "r", number: 7 });
      return { data: { repository: { issue: { timelineItems: { nodes: events } } } } };
    }
    assert.equal(`${method} ${path}`, "GET /repos/o/r/issues/7");
    return { labels: [{ name: "agent-ready" }] };
  };
  writeFileSync(join(env.BASE_PATH, "event.json"), JSON.stringify({ action: "labeled", issue }));
  const code = await main({ env: { ...env, EVENT_PATH: join(env.BASE_PATH, "event.json") }, github });
  return { code, outputs: readOutputs(env.GITHUB_OUTPUT), calls };
}

test("main on an issue set Medium, High, Known writes its turn cap, dimensions and timeout", async () => {
  const { code, outputs, calls } = await mainOnIssue([
    fieldEvent("IssueFieldAddedEvent", 15462270, LISTED),
    fieldEvent("IssueFieldAddedEvent", 48625720, LISTED),
    fieldEvent("IssueFieldAddedEvent", 48625721, LISTED),
  ]);
  assert.equal(code, 0);
  assert.equal(outputs["claude-args"], "--max-turns 50");
  assert.equal(outputs["issue-dimensions"], "medium/high/known");
  assert.equal(outputs["timeout-minutes"], "9");
  const read = calls.find((call) => call.path.endsWith("/issue-field-values"));
  assert.equal(read.headers["X-GitHub-Api-Version"], "2026-03-10");
});

test("main refuses an issue whose latest Size setter is unlisted", async () => {
  const { code, outputs } = await mainOnIssue([
    fieldEvent("IssueFieldAddedEvent", 15462270, LISTED),
    fieldEvent("IssueFieldAddedEvent", 48625720, LISTED),
    fieldEvent("IssueFieldAddedEvent", 48625721, LISTED),
    fieldEvent("IssueFieldChangedEvent", 15462270, UNLISTED),
  ]);
  assert.equal(code, 0);
  assert.equal(outputs.applies, "false");
  assert.equal(outputs["skip-reason"], "not-assessed");
  assert.equal(outputs["issue-dimensions"], "not-assessed");
});

test("main fails when the field events answer with GraphQL errors", async () => {
  const { fieldSetters } = await import("./resolve-config.mjs");
  const github = async () => ({ errors: [{ message: "Resource not accessible by integration" }] });
  await assert.rejects(() => fieldSetters(github, "o/r", 7), /field events could not be read: Resource not accessible/);
});

test("main refuses an issue whose field was removed after it was set", async () => {
  const { outputs } = await mainOnIssue([
    fieldEvent("IssueFieldAddedEvent", 15462270, LISTED),
    fieldEvent("IssueFieldAddedEvent", 48625720, LISTED),
    fieldEvent("IssueFieldAddedEvent", 48625721, LISTED),
    fieldEvent("IssueFieldRemovedEvent", 48625721, LISTED),
  ]);
  assert.equal(outputs["skip-reason"], "not-assessed");
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
