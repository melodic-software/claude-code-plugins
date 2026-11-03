import assert from "node:assert/strict";
import { test } from "node:test";
import { branchOf, parseAreas, promptText, sortSweeps, staysInArea, sweepRecord, toOpen, validatePlan } from "./batch.mjs";

const BASE = "a".repeat(40);
const HEAD = "b".repeat(40);
const DATE = "2026-11-03";
const areas = [
  { area: "plugins/bugs", glob: "plugins/bugs/**", slug: "plugins-bugs", overdue: false },
  { area: "scripts", glob: "scripts/**", slug: "scripts", overdue: true },
];
const ctx = { areas, date: DATE, baseSha: BASE };
const prSweep = (over = {}) => ({
  slug: "plugins-bugs",
  outcome: "pr",
  branch: "chore/tidy-adhoc-plugins-bugs-2026-11-03",
  head_sha: HEAD,
  pr: { title: "refactor(bugs): name the lane reader", body: "No related issue: code-tidying upkeep sweep." },
  ...over,
});
const planText = (sweeps, over = {}) => JSON.stringify({ schema: "tidy-code-upkeep-plan/1", base_sha: BASE, sweeps, ...over });
const rawLine = (path, mode = "100644") => `:${mode} ${mode} ${"0".repeat(40)} ${"1".repeat(40)} M\t${path}`;

test("the branch is the shape tidy's ad hoc scope names", () => {
  assert.equal(branchOf("plugins-bugs", DATE), "chore/tidy-adhoc-plugins-bugs-2026-11-03");
});

test("the prompt names each area's branch and in-place arguments, and forbids pushing", () => {
  const text = promptText({ areas, date: DATE, baseSha: BASE });
  assert.match(text, /branch `chore\/tidy-adhoc-scripts-2026-11-03`, arguments `scripts\/\*\* in-place=commit`/);
  assert.match(text, /Push nothing, open no pull request and file no issue/);
});

test("parseAreas refuses a glob that could break out of the prompt", () => {
  assert.equal(parseAreas(JSON.stringify(areas)).length, 2);
  assert.throws(() => parseAreas(JSON.stringify([{ area: "x", glob: "x/**`; id", slug: "x" }])));
  assert.throws(() => parseAreas(JSON.stringify([{ area: "x", glob: "x/**", slug: "X Y" }])));
  assert.throws(() => parseAreas("[]"));
});

test("validatePlan accepts a clean and a pr sweep", () => {
  const sweeps = [prSweep(), { slug: "scripts", outcome: "clean" }];
  assert.deepEqual(validatePlan(planText(sweeps), ctx), sweeps);
});

test("validatePlan refuses each bad field, naming no value", () => {
  const bad = [
    [planText([], { schema: "other" }), /schema/],
    [planText([], { base_sha: HEAD }), /base_sha/],
    [planText([{ slug: "plugins-other", outcome: "clean" }]), /slug is not an area/],
    [planText([{ slug: "scripts", outcome: "clean" }, { slug: "scripts", outcome: "clean" }]), /repeats/],
    [planText([prSweep({ branch: "chore/tidy-adhoc-scripts-2026-11-03" })]), /branch/],
    [planText([prSweep({ head_sha: BASE })]), /head_sha/],
    [planText([prSweep({ pr: { title: "tidied things", body: "" } })]), /title/],
    [planText([prSweep({ pr: { title: "chore: x\ny", body: "" } })]), /title/],
    [planText([prSweep({ outcome: "merged" })]), /outcome/],
    ["not json secret-value", /not valid JSON/],
  ];
  for (const [text, why] of bad) {
    assert.throws(() => validatePlan(text, ctx), (error) => why.test(error.message) && !error.message.includes("secret-value"));
  }
});

test("a branch stays in its area, a plugin area may add its own fragment", () => {
  assert.equal(staysInArea(rawLine("plugins/bugs/a.sh"), "plugins/bugs"), true);
  assert.equal(staysInArea(`${rawLine("plugins/bugs/a.sh")}\n${rawLine(".changes/bugs/x.md")}`, "plugins/bugs"), true);
  assert.equal(staysInArea(rawLine(".changes/review/x.md"), "plugins/bugs"), false);
  assert.equal(staysInArea(rawLine("plugins/review/a.sh"), "plugins/bugs"), false);
  assert.equal(staysInArea(rawLine(".changes/bugs/x.md"), "scripts"), false);
  assert.equal(staysInArea(rawLine("plugins/bugs/link", "120000"), "plugins/bugs"), false);
  assert.equal(staysInArea("", "plugins/bugs"), false);
});

test("sortSweeps records a clean sweep and a refused one, and keeps a good branch", () => {
  const out = sortSweeps([prSweep(), { slug: "scripts", outcome: "clean" }], areas, { rawOf: () => rawLine("plugins/bugs/a.sh"), binary: () => false });
  assert.deepEqual(out.recorded, ["scripts"]);
  assert.deepEqual(out.kept.map((sweep) => sweep.slug), ["plugins-bugs"]);
  const outside = sortSweeps([prSweep()], areas, { rawOf: () => rawLine("scripts/a.sh"), binary: () => false });
  assert.deepEqual(outside, { kept: [], recorded: ["plugins-bugs"] });
  const binary = sortSweeps([prSweep()], areas, { rawOf: () => rawLine("plugins/bugs/a.png"), binary: () => true });
  assert.deepEqual(binary, { kept: [], recorded: ["plugins-bugs"] });
});

test("sortSweeps refuses a branch that changes a hold path", () => {
  const held = { ...areas[0], area: "plugins/source-control", slug: "plugins-source-control" };
  const sweep = prSweep({ slug: "plugins-source-control" });
  const raw = rawLine("plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py");
  assert.deepEqual(sortSweeps([sweep], [held], { rawOf: () => raw, binary: () => false }), { kept: [], recorded: ["plugins-source-control"] });
});

test("the sweep record holds git's committer time as a number, and the slugs", () => {
  assert.equal(sweepRecord(["scripts"], "1793000000"), '{"at":1793000000,"slugs":["scripts"]}');
});

test("toOpen opens only pushed branches, at most limit minus open", () => {
  const a = prSweep();
  const b = prSweep({ slug: "scripts", branch: "chore/tidy-adhoc-scripts-2026-11-03" });
  const heads = { [a.branch]: HEAD, [b.branch]: HEAD };
  assert.deepEqual(toOpen([a, b], heads, { open: 2, limit: 3, throttled: false }), [a]);
  assert.deepEqual(toOpen([a, b], heads, { open: 3, limit: 3, throttled: true }), []);
  assert.deepEqual(toOpen([a, b], { [b.branch]: HEAD }, { open: 0, limit: 3, throttled: false }), [b]);
});
