// Tests for council-plan.mjs. Expected values come from the council keys' schema
// (plugins/review/schemas/review.schema.json), the adapter records under ../adapters, the
// flagship pointer file, and the selection rules ADR 0097 states (first match wins, every term
// must match, a member that cannot run as written is skipped and never replaced).
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { DEFAULTS, globToRegExp, resolveConfig, selectPanel } from "./council-plan.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const SCRIPT = join(HERE, "council-plan.mjs");
const TMP = mkdtempSync(join(tmpdir(), "council-plan-"));
after(() => rmSync(TMP, { recursive: true, force: true }));

let n = 0;
function repo(yaml) {
  const root = join(TMP, `r${n++}`);
  mkdirSync(join(root, "docs", "conventions"), { recursive: true });
  if (yaml !== undefined) writeFileSync(join(root, "docs", "conventions", "review.yaml"), yaml);
  return root;
}
function userFile(obj) {
  const f = join(TMP, `u${n++}.json`);
  writeFileSync(f, JSON.stringify(obj));
  return f;
}
const git = (root, ...args) =>
  spawnSync("git", ["-C", root, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false", ...args], { encoding: "utf8" });

const base = { changed: ["src/a.js"], tier: "medium", tierReason: "4 files", risk: "unrated", riskReason: "no PR", round: 1, dirty: false, claudeVersion: "2.1.319" };
const configWith = (members, extra = {}) => ({
  lanes: { value: "off", layer: "default" },
  max_rounds: { value: 1, layer: "default" },
  scores: { value: "off", layer: "default" },
  members: { value: members, layer: "test" },
  panel: { value: extra.panel ?? null, layer: "test" },
  rules: { value: extra.rules ?? [], layer: "test" },
});
const statusOf = (out, id) => out.members.find((m) => m.id === id).status;

describe("config", () => {
  test("no config at all: three opus members, one round, scores off, lanes off", () => {
    const out = resolveConfig({ root: repo() });
    assert.deepEqual(out.members, { value: DEFAULTS.council_members, layer: "default" });
    assert.deepEqual(Object.keys(out.members.value), ["correctness", "design", "adversarial"]);
    assert.ok(Object.values(out.members.value).every((m) => m.provider === "claude" && m.model === "opus"));
    assert.equal(out.max_rounds.value, 1);
    assert.equal(out.scores.value, "off");
    assert.equal(out.lanes.value, "off");
    assert.equal(out.panel.value, null);
    assert.deepEqual(out.rules.value, []);
    assert.equal(out.needs_risk, false);
    assert.deepEqual(out.problems, []);
  });

  test("the repository file wins over the user option per key", () => {
    const root = repo("council_max_rounds: 3\n");
    const out = resolveConfig({ root, userFile: userFile({ council_max_rounds: 2, council_scores: "on" }) });
    assert.deepEqual(out.max_rounds, { value: 3, layer: "docs/conventions/review.yaml" });
    assert.deepEqual(out.scores, { value: "on", layer: "userConfig" });
  });

  test("a flow map in review.yaml is refused and the repository layer dropped", () => {
    const out = resolveConfig({ root: repo("council_members: {a: {provider: claude}}\n") });
    assert.equal(out.members.layer, "default");
    assert.match(out.problems.join("\n"), /flow mapping/);
  });

  test("invalid user JSON is dropped for its key only", () => {
    const out = resolveConfig({ root: repo(), userFile: userFile({ council_members: "{not json", council_scores: "on" }) });
    assert.equal(out.members.layer, "default");
    assert.equal(out.scores.value, "on");
    assert.match(out.problems.join("\n"), /council_members: not JSON/);
  });

  test("user JSON holding quotes and backticks in a glob survives", () => {
    const rules = [{ name: "odd", when: { paths: ['docs/"q"/`b`/**'] }, members: ["correctness"] }];
    const out = resolveConfig({ root: repo(), userFile: userFile({ council_rules: JSON.stringify(rules) }) });
    assert.deepEqual(out.rules.value, rules);
    assert.equal(out.rules.layer, "userConfig");
  });

  test("a user council_lanes is ignored: the switch is repository-only", () => {
    const out = resolveConfig({ root: repo(), userFile: userFile({ council_lanes: "on" }) });
    assert.equal(out.lanes.value, "off");
    assert.match(out.problems.join("\n"), /repository-only/);
  });

  test("a schema-invalid value drops that layer for that key and keeps the others", () => {
    const out = resolveConfig({ root: repo("council_scores: maybe\ncouncil_max_rounds: 2\n") });
    assert.equal(out.scores.layer, "default");
    assert.equal(out.max_rounds.value, 2);
  });

  test("an unknown catalog id in a rule drops the rules for that layer", () => {
    const yaml = "council_rules:\n  - name: r\n    when:\n      size: [large]\n    members: [ghost]\n";
    const out = resolveConfig({ root: repo(yaml) });
    assert.deepEqual(out.rules.value, []);
    assert.match(out.problems.join("\n"), /ghost/);
  });

  test("a rule with a risk term sets needs_risk", () => {
    const yaml = "council_rules:\n  - name: r\n    when:\n      risk: HIGH\n    members: [correctness]\n";
    assert.equal(resolveConfig({ root: repo(yaml) }).needs_risk, true);
  });

  test("ref read: council keys come from the ref's committed copy, not the working tree", () => {
    const root = repo("council_max_rounds: 2\n");
    git(root, "init", "-q");
    git(root, "add", "-A");
    git(root, "commit", "-q", "-m", "base");
    writeFileSync(join(root, "docs", "conventions", "review.yaml"), "council_max_rounds: 5\ncouncil_lanes: on\n");
    const out = resolveConfig({ root, ref: "HEAD" });
    assert.equal(out.max_rounds.value, 2);
    assert.equal(out.lanes.value, "off");
    assert.match(out.read_at, /^HEAD \([0-9a-f]{40}\)$/);
  });

  test("a missing ref reads no repository layer and says why", () => {
    const root = repo("council_max_rounds: 2\n");
    git(root, "init", "-q");
    const out = resolveConfig({ root, ref: "origin/main" });
    assert.equal(out.max_rounds.layer, "default");
    assert.match(out.read_at, /does not exist/);
  });

  test("a ref with characters outside the allowed set is refused", () => {
    const out = resolveConfig({ root: repo("council_max_rounds: 2\n"), ref: "a..b" });
    assert.equal(out.max_rounds.layer, "default");
  });
});

describe("select", () => {
  const two = { correctness: { provider: "claude", model: "opus", brief: "correctness" }, design: { provider: "claude", model: "opus", brief: "design" } };

  test("no rule matching: the panel runs", () => {
    const out = selectPanel({ ...base, config: configWith(two, { panel: ["design"] }) });
    assert.equal(out.rule, "fallback");
    assert.deepEqual(out.members.map((m) => m.id), ["design"]);
  });

  test("no rule and no panel: every catalog member runs", () => {
    const out = selectPanel({ ...base, config: configWith(two) });
    assert.deepEqual(out.members.map((m) => m.id), ["correctness", "design"]);
    assert.equal(out.planned, 2);
  });

  test("the first matching rule wins", () => {
    const rules = [
      { name: "first", when: { paths: ["src/**"] }, members: ["correctness"] },
      { name: "second", when: { paths: ["src/**"] }, members: ["design"] },
    ];
    const out = selectPanel({ ...base, config: configWith(two, { rules }) });
    assert.equal(out.rule, "first");
    assert.deepEqual(out.members.map((m) => m.id), ["correctness"]);
  });

  test("every term must match", () => {
    const rules = [{ name: "both", when: { paths: ["src/**"], size: ["large"] }, members: ["correctness"] }];
    assert.equal(selectPanel({ ...base, config: configWith(two, { rules }) }).rule, "fallback");
    assert.equal(selectPanel({ ...base, tier: "large", config: configWith(two, { rules }) }).rule, "both");
  });

  test("a risk rule never matches an unrated head, and the report says why", () => {
    const rules = [{ name: "risky", when: { risk: "LOW" }, members: ["correctness"] }];
    const out = selectPanel({ ...base, config: configWith(two, { rules }) });
    assert.equal(out.rule, "fallback");
    assert.equal(out.risk, "unrated (no PR)");
    assert.equal(selectPanel({ ...base, risk: "HIGH", config: configWith(two, { rules }) }).rule, "risky");
    assert.equal(selectPanel({ ...base, risk: "HIGH", config: configWith(two, { rules: [{ ...rules[0], when: { risk: "CRITICAL" } }] }) }).rule, "fallback");
  });

  test("globs: ** crosses directories, * stays in one segment", () => {
    assert.ok(globToRegExp("plugins/*/hooks/**").test("plugins/a/hooks/x/y.sh"));
    assert.ok(!globToRegExp("plugins/*/hooks/**").test("plugins/a/b/hooks/x.sh"));
    assert.ok(globToRegExp("**/*.md").test("README.md"));
    assert.ok(!globToRegExp("src/*.js").test("src/a/b.js"));
  });

  test("inherit and a full claude model id are skipped, never replaced", () => {
    const out = selectPanel({ ...base, config: configWith({ a: { provider: "claude", model: "inherit" }, b: { provider: "claude", model: "claude-opus-5-5" } }) });
    assert.match(statusOf(out, "a"), /^skipped \(claude members take a model alias/);
    assert.match(statusOf(out, "b"), /^skipped \(claude members take a model alias/);
    assert.equal(out.planned, 0);
  });

  test("claude/flagship resolves to fable and is frontier", () => {
    const out = selectPanel({ ...base, config: configWith({ top: { provider: "claude", model: "claude/flagship", brief: "correctness" } }) });
    assert.equal(out.members[0].model, "fable");
    assert.equal(out.members[0].frontier, true);
    assert.equal(out.members[0].status, "planned");
  });

  test("the fan-out guard: every non-fable claude member carries a named non-frontier model", () => {
    const out = selectPanel({ ...base, config: configWith({ a: { provider: "claude" }, b: { provider: "claude", model: "sonnet" }, c: { provider: "claude", model: "fable" } }) });
    for (const m of out.members.filter((x) => x.id !== "c")) {
      assert.ok(["opus", "sonnet", "haiku"].includes(m.model), `${m.id} runs on ${m.model}`);
      assert.equal(m.frontier, false);
    }
    assert.equal(out.members.find((m) => m.id === "a").model_from, "adapter default");
    assert.equal(out.members.find((m) => m.id === "c").frontier, true);
  });

  test("codex/flagship is skipped until it resolves", () => {
    const out = selectPanel({ ...base, config: configWith({ x: { provider: "codex", model: "codex/flagship" } }) });
    assert.equal(statusOf(out, "x"), "skipped (codex/flagship cannot be resolved yet)");
  });

  test("codex routes: no brief runs review, a brief runs adversarial-review", () => {
    const out = selectPanel({ ...base, config: configWith({ plain: { provider: "codex" }, adv: { provider: "codex", brief: "correctness", model: "gpt-x" } }) });
    assert.equal(out.members[0].route, "review");
    assert.equal(out.members[0].model, "provider setting");
    assert.equal(out.members[0].effort, "provider setting");
    assert.equal(out.members[1].route, "adversarial-review");
    assert.equal(out.members[1].model, "gpt-x");
    assert.equal(out.planned, 2);
  });

  test("a codex member naming an effort is skipped", () => {
    const out = selectPanel({ ...base, config: configWith({ x: { provider: "codex", effort: "high" } }) });
    assert.equal(statusOf(out, "x"), "skipped (effort cannot be set on codex)");
  });

  test("codex sits out a dirty tree and every later round", () => {
    const cfg = configWith({ x: { provider: "codex" }, c: { provider: "claude", model: "opus" } });
    assert.equal(statusOf(selectPanel({ ...base, dirty: true, config: cfg }), "x"), "skipped (reviews committed changes only; the tree has uncommitted changes)");
    const r2 = selectPanel({ ...base, round: 2, config: cfg });
    assert.equal(statusOf(r2, "x"), "skipped (cannot be limited to the fix's changes)");
    assert.equal(statusOf(r2, "c"), "planned");
  });

  test("skips come from the adapter record, not the provider name", () => {
    const dir = join(TMP, "adapters");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "other.yaml"), "kind: script\nrun: scripts/other.sh\nsets: [model]\nsees: committed\nbriefs: any\nmodels: any\nmodel_default: provider\neffort_default: provider\nfrontier: []\n");
    const cfg = configWith({ o: { provider: "other" }, e: { provider: "other", effort: "high" } });
    assert.equal(statusOf(selectPanel({ ...base, adaptersDir: dir, config: cfg }), "o"), "planned");
    assert.equal(statusOf(selectPanel({ ...base, adaptersDir: dir, dirty: true, config: cfg }), "o"), "skipped (reviews committed changes only; the tree has uncommitted changes)");
    assert.equal(statusOf(selectPanel({ ...base, adaptersDir: dir, round: 2, config: cfg }), "o"), "skipped (cannot be limited to the fix's changes)");
    assert.equal(statusOf(selectPanel({ ...base, adaptersDir: dir, config: cfg }), "e"), "skipped (effort cannot be set on other)");
  });

  test("an unknown provider is skipped with no adapter", () => {
    const out = selectPanel({ ...base, config: configWith({ g: { provider: "gemini" } }) });
    assert.equal(statusOf(out, "g"), "skipped (no adapter for provider gemini)");
  });

  test("an unshipped brief is skipped", () => {
    const out = selectPanel({ ...base, config: configWith({ a: { provider: "claude", brief: "perf" } }) });
    assert.equal(statusOf(out, "a"), "skipped (no shipped brief named perf)");
  });

  test("pilot above four planned members", () => {
    const five = Object.fromEntries(["a", "b", "c", "d", "e"].map((id) => [id, { provider: "claude", model: "opus" }]));
    assert.equal(selectPanel({ ...base, config: configWith(five) }).pilot, true);
    const four = Object.fromEntries(["a", "b", "c", "d"].map((id) => [id, { provider: "claude", model: "opus" }]));
    assert.equal(selectPanel({ ...base, config: configWith(four) }).pilot, false);
  });

  test("an effort other than the default is skipped on a Claude Code before the effort parameter", () => {
    const cfg = configWith({ a: { provider: "claude", model: "opus", effort: "low" }, b: { provider: "claude", model: "opus", effort: "high" } });
    const old = selectPanel({ ...base, claudeVersion: "2.1.291", config: cfg });
    assert.match(statusOf(old, "a"), /^skipped \(effort cannot be set on this Claude Code version/);
    assert.equal(statusOf(old, "b"), "planned");
    assert.equal(statusOf(selectPanel({ ...base, claudeVersion: "2.1.292", config: cfg }), "a"), "planned");
  });

  test("claude effort defaults to high", () => {
    assert.equal(selectPanel({ ...base, config: configWith(two) }).members[0].effort, "high");
  });
});

describe("cli", () => {
  test("config prints JSON; a bad verb exits 2", () => {
    const ok = spawnSync("node", [SCRIPT, "config", "--root", repo()], { encoding: "utf8" });
    assert.equal(ok.status, 0);
    assert.equal(JSON.parse(ok.stdout).max_rounds.value, 1);
    assert.equal(spawnSync("node", [SCRIPT, "nope"], { encoding: "utf8" }).status, 2);
  });

  test("select reads its config and changed-paths files", () => {
    const cfg = join(TMP, "cfg.json");
    writeFileSync(cfg, JSON.stringify(configWith({ a: { provider: "claude", model: "opus" } })));
    const changed = join(TMP, "changed.txt");
    writeFileSync(changed, "src/a.js\n");
    const out = spawnSync("node", [SCRIPT, "select", "--config", cfg, "--changed", changed, "--tier", "small", "--tier-reason", "1 file", "--risk", "unrated", "--risk-reason", "no PR", "--round", "1", "--dirty", "false"], { encoding: "utf8" });
    assert.equal(out.status, 0, out.stderr);
    assert.equal(JSON.parse(out.stdout).members[0].status, "planned");
  });
});
