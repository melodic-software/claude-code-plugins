// Planning views on the view registries: each kind renders through render(laneId, kind, record),
// the shipped default is a private Artifact that the publish gate keeps local for a non-public
// repository or a credential-shaped record, and a medium added only to a registry delivers a plan
// view with no edit to the planning skills.
import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { parsePlan, render, validateView, VIEW_KINDS, ViewBuildError } from "../lib/view-builder.mjs";
import { MEDIUMS } from "../lib/view-registry.mjs";
import { resolveMedium } from "../lib/view-settings.mjs";
import { deliverView } from "./build-view.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, "build-view.mjs");
const dirs = [];
process.on("exit", () => dirs.forEach((dir) => rmSync(dir, { recursive: true, force: true })));
const tempDir = () => {
  const dir = mkdtempSync(join(tmpdir(), "deliver-view-"));
  dirs.push(dir);
  return dir;
};

const DESIGN_RECORD = [
  "# Plan: Cache query results",
  "",
  "## Brief",
  "",
  "Cache repeated reads.",
  "",
  "## Design",
  "",
  "Gate: PASS (design handoff).",
  "",
  "### Module layout",
  "",
  "| Module | Owns |",
  "|---|---|",
  "| Cache | entries |",
  "",
  "### Contracts",
  "",
  "```text",
  "get(key) -> value?",
  "## inside a fence, not a heading",
  "```",
  "",
  "## Plan",
  "",
  "### Phase 1: Cache layer",
  "",
].join("\n");

const PLAN_RECORD = readFileSync(join(HERE, "testdata", "plan-record.md"), "utf8");
const dataOf = (page) => JSON.parse(/<script type="application\/json" id="rv-data">([\s\S]*?)<\/script>/.exec(page)[1]);
const resolution = (medium, decidedBy, preferred = medium) => ({ preferred, medium, decidedBy, notices: [] });

/** A write step that keeps each page in memory and hands back a made-up path. */
const memory = () => {
  const pages = [];
  return { pages, write: (page, kind) => (pages.push(page), `/views/${kind}-${pages.length}.html`) };
};

describe("the design kind", () => {
  test("reads the record's ## Design section: the title, the lead text, and each subsection's lines", () => {
    assert.deepEqual(VIEW_KINDS.design.parse(DESIGN_RECORD), {
      title: "Plan: Cache query results",
      intro: "Gate: PASS (design handoff).",
      sections: [
        { name: "Module layout", lines: ["| Module | Owns |", "|---|---|", "| Cache | entries |"] },
        { name: "Contracts", lines: ["```text", "get(key) -> value?", "## inside a fence, not a heading", "```"] },
      ],
    });
  });

  test("a record with no ## Design section is refused as data", () => {
    assert.throws(() => VIEW_KINDS.design.parse("# Plan\n\n## Plan\n\n### Phase 1\n"), ViewBuildError);
  });

  test("renders a page that passes the interactive profile", () => {
    const page = render("planning", "design", DESIGN_RECORD);
    assert.equal(validateView(page).ok, true, validateView(page).failures?.join(", "));
    assert.deepEqual(dataOf(page).sections.map((s) => s.name), ["Module layout", "Contracts"]);
  });
});

describe("parsePlan", () => {
  test("reads the Brief, behaviors, criteria, decisions and phases of a PLAN.md", () => {
    assert.deepEqual(parsePlan(PLAN_RECORD), {
      title: "Plan: Add caching to query handlers",
      goal: "Cache repeated query results so a repeated lookup skips the database.",
      blast: "MEDIUM",
      brief: {
        problem: ["Repeated order lookups hit the database on every request.", "Peak latency is twice the target."],
        constraints: ["No new runtime dependency."],
        outOfScope: ["Cache invalidation across instances."],
      },
      behaviors: [
        { id: "B1", text: "A repeated order lookup returns without a database read.", cites: "AC1" },
        { id: "B2", text: "Each lookup logs whether it hit the cache.", cites: "AC2" },
      ],
      process: "AC3",
      criteria: [
        { id: "AC1", text: "A repeated lookup within the TTL reads from the cache." },
        { id: "AC2", text: "The hit rate is logged." },
        { id: "AC3", text: "The PR body links the issue it closes." },
      ],
      decisions: [
        { decision: "D1 In-process cache first", changes: "Phase 1 adds a map-backed cache", basis: "the handler runs in one process", source: "plan" },
        { decision: "D2 Log through the existing logger", changes: "Phase 2 reuses `log.info`", basis: "the logger module read this session", source: "plan" },
      ],
      phases: [
        {
          status: "DONE",
          name: "Phase 1: Cache layer",
          what: "Add the cache module and read through it in the order handler.",
          satisfies: "AC1",
          delivers: "B1",
          criteria: ["`pytest tests/test_cache.py` exits 0", '`grep -c "cache.get" src/orders/handler.py` prints 1'],
          shapes: [{ anchor: "src/orders/handler.py#get_order", body: "get_order\n+ cache.get\n  db.fetch_order" }],
        },
        {
          status: "TODO",
          name: "Phase 2: Wire the hit-rate log",
          what: "Log each lookup's hit or miss.\n\n```text\n## a heading inside a fence stays text\n```",
          satisfies: "AC2, AC3",
          delivers: "B2",
          criteria: ["`pytest tests/test_log.py` exits 0"],
          shapes: [],
        },
      ],
    });
  });

  test("a missing part is an empty list or empty text, and a No Brief plan takes its Goal line", () => {
    const plan = parsePlan("No Brief: a one-line fix.\nGoal: fix the typo; done when the page reads right.\n\n## Plan\n\n### Phase 1: Fix [TODO]\n");
    assert.equal(plan.goal, "fix the typo; done when the page reads right.");
    assert.deepEqual([plan.title, plan.blast, plan.process], ["", "", ""]);
    assert.deepEqual([plan.behaviors, plan.criteria, plan.decisions, plan.brief.problem], [[], [], [], []]);
    assert.deepEqual(plan.phases, [{ status: "TODO", name: "Phase 1: Fix", what: "", satisfies: "", delivers: "", criteria: [], shapes: [] }]);
  });

  test("a record with no ## Plan section is refused as data", () => {
    assert.throws(() => parsePlan("# Plan\n\n## Brief\n\n```\n## Plan\n```\n"), ViewBuildError);
    assert.throws(() => VIEW_KINDS.plan.parse({ phases: [] }), ViewBuildError);
  });
});

describe("render", () => {
  test("renders the plan kind from its PLAN.md record, the Brief lists as top-level keys", () => {
    const data = dataOf(render("planning", "plan", PLAN_RECORD));
    assert.equal(data.title, "Plan: Add caching to query handlers");
    assert.deepEqual(data["out-of-scope"], ["Cache invalidation across instances."]);
    assert.equal(data.brief, undefined);
  });

  test("a plan record that names no title shows Plan", () => {
    assert.equal(dataOf(render("planning", "plan", "## Plan\n\n### Phase 1: Fix [TODO]\n")).title, "Plan");
  });

  test("refuses a kind the lane does not register", () => {
    assert.throws(() => render("review:explain-change", "plan", PLAN_RECORD), /does not register/);
  });

  test("refuses an unknown lane", () => {
    assert.throws(() => render("nope", "plan", PLAN_RECORD), /unknown lane/);
  });
});

describe("deliverView", () => {
  test("a medium registered only in a fixture registry delivers a plan view", () => {
    const delivered = [];
    const fake = Object.freeze({
      id: "fake",
      publishes: false,
      reportName: "a fake medium",
      reachable: () => ({ ok: true }),
      deliver: (view) => (delivered.push(view), { location: `fake:${view.path}` }),
    });
    const { pages, write } = memory();
    const out = deliverView({ kind: "plan", record: PLAN_RECORD, resolution: resolution("fake", "argument"), mediums: { ...MEDIUMS, fake }, write });
    assert.equal(delivered.length, 1);
    assert.equal(delivered[0].path, "/views/plan-1.html");
    assert.equal(out.delivery.location, "fake:/views/plan-1.html");
    assert.equal(dataOf(pages[0]).title, "Add caching to query handlers");
    assert.equal(validateView(pages[0]).ok, true);
    assert.deepEqual(out.report, ["view: fake (argument)"]);
  });

  test("the shipped default publishes a public repository's clean record", () => {
    const { write } = memory();
    const out = deliverView({ kind: "plan", record: PLAN_RECORD, resolution: resolution("artifact", "plugin default"), visibility: "PUBLIC", write });
    assert.equal(out.delivery.publish, "/views/plan-1.html");
    assert.deepEqual(out.report, ["view: artifact (plugin default)"]);
  });

  test("the publish gate keeps the shipped default local for a private repository", () => {
    const { write } = memory();
    const out = deliverView({ kind: "plan", record: PLAN_RECORD, resolution: resolution("artifact", "plugin default"), visibility: "PRIVATE", write });
    assert.equal(out.delivery.publish, undefined);
    assert.equal(out.delivery.location, "/views/plan-1.html");
    assert.match(out.report[0], /^view: file \(publish gate: .*PRIVATE/);
    assert.equal(out.report.length, 2, "the gate's opt-in line follows the report line");
  });

  test("the publish gate keeps the shipped default local when the visibility is not given", () => {
    const out = deliverView({ kind: "plan", record: PLAN_RECORD, resolution: resolution("artifact", "plugin default"), write: memory().write });
    assert.equal(out.delivery.publish, undefined);
  });

  test("the publish gate keeps a credential-shaped record local in a public repository", () => {
    const record = PLAN_RECORD.replace("Cache repeated query results", `token ghp_${"a".repeat(36)}`);
    const out = deliverView({ kind: "plan", record, resolution: resolution("artifact", "plugin default"), visibility: "PUBLIC", write: memory().write });
    assert.equal(out.delivery.publish, undefined);
    assert.match(out.report[0], /^view: file \(publish gate: .*GitHub token/);
  });

  test("an artifact the reader chose in userConfig publishes from a private repository", () => {
    const out = deliverView({ kind: "plan", record: PLAN_RECORD, resolution: resolution("artifact", "userConfig"), visibility: "PRIVATE", write: memory().write });
    assert.equal(out.delivery.publish, "/views/plan-1.html");
  });

  test("the terminal builds no page", () => {
    const { pages, write } = memory();
    const out = deliverView({ kind: "design", record: "no design here", resolution: resolution("terminal", "userConfig"), write });
    assert.equal(pages.length, 0);
    assert.deepEqual(out.delivery, { location: "terminal" });
  });
});

describe("the planning lane", () => {
  test("ships a private Artifact as its default when no scope decides", () => {
    const home = tempDir();
    const got = resolveMedium({ lane: "planning", userConfig: "auto" }, { userHome: home, dataDir: null });
    assert.deepEqual([got.preferred, got.medium, got.decidedBy], ["artifact", "artifact", "plugin default"]);
  });
});

describe("the build-view CLI", () => {
  const env = (dir, extra = {}) => ({ ...process.env, HOME: dir, USERPROFILE: dir, CLAUDE_PROJECT_DIR: dir, TMPDIR: dir, TEMP: dir, TMP: dir, CI: "", ...extra });

  test("design --record writes one HTML page", () => {
    const dir = tempDir();
    const record = join(dir, "PLAN.md");
    writeFileSync(record, DESIGN_RECORD);
    const run = spawnSync("node", [CLI, "design", "--record", record], { encoding: "utf8", env: env(dir) });
    assert.equal(run.status, 0, run.stderr);
    const path = run.stdout.trim();
    assert.equal(path, join(dir, "planning-views", "design.html"));
    assert.deepEqual(readdirSync(join(dir, "planning-views")), ["design.html"]);
    assert.equal(validateView(readFileSync(path, "utf8")).ok, true);
  });

  test("--option resolves, gates and delivers, then prints the report line", () => {
    const dir = tempDir();
    const record = join(dir, "PLAN.md");
    writeFileSync(record, DESIGN_RECORD);
    const run = spawnSync("node", [CLI, "design", "--record", record, "--option", "auto"], { encoding: "utf8", env: env(dir) });
    assert.equal(run.status, 0, run.stderr);
    const [json, report] = run.stdout.trim().split("\n");
    const delivery = JSON.parse(json);
    assert.equal(delivery.page, join(dir, "planning-views", "design.html"));
    assert.equal(delivery.publish, undefined);
    assert.match(report, /^view: file \(publish gate: /);
  });

  test("a non-interactive run builds no page", () => {
    const dir = tempDir();
    const run = spawnSync("node", [CLI, "plan", "--option", "artifact"], { input: PLAN_RECORD, encoding: "utf8", env: env(dir, { CI: "true" }) });
    assert.equal(run.status, 0, run.stderr);
    const [json, report] = run.stdout.trim().split("\n");
    assert.deepEqual(JSON.parse(json), { location: "terminal" });
    assert.match(report, /^view: terminal \(fell back: /);
  });

  test("an empty --option is unset, as the resolver reads it", () => {
    const run = spawnSync("node", [CLI, "plan", "--option", ""], { input: PLAN_RECORD, encoding: "utf8", env: env(tempDir(), { CI: "true" }) });
    assert.equal(run.status, 0, run.stderr);
    assert.match(run.stdout.trim().split("\n")[1], /^view: terminal \(fell back: artifact unreachable/);
  });

  test("--argument naming no medium exits 2", () => {
    const run = spawnSync("node", [CLI, "plan", "--option", "auto", "--argument", "paper"], { input: PLAN_RECORD, encoding: "utf8", env: env(tempDir()) });
    assert.equal(run.status, 2);
  });

  test("--option with --connect exits 2", () => {
    const run = spawnSync("node", [CLI, "plan", "--option", "auto", "--connect", "http://127.0.0.1:8765", "--out", "/x/page.html"], { input: PLAN_RECORD, encoding: "utf8", env: env(tempDir()) });
    assert.equal(run.status, 2);
  });
});
