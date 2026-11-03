import assert from "node:assert/strict";
import { test } from "node:test";
import { refsIssue } from "../pr-merge/merge-holds.mjs";
import { branchOf, findExisting, openPulls, parseAreas, prBody, promptText, pushStep, sortSweeps, staysInArea, slotsLeft, sweepRecord, validatePlan } from "./batch.mjs";

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
  pr: { title: "refactor(bugs): name the lane reader", body: "## Summary\n\nNamed the lane reader." },
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
  // The opt-out line is what left pr-verify with no spec (#12828).
  assert.doesNotMatch(text, /No related issue/);
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

test("slotsLeft is limit minus open, and none while throttled or over the limit", () => {
  assert.equal(slotsLeft({ open: 2, limit: 3, throttled: false }), 1);
  assert.equal(slotsLeft({ open: 3, limit: 3, throttled: true }), 0);
  assert.equal(slotsLeft({ open: 5, limit: 3, throttled: false }), 0);
});

test("a re-run's reused branch uses a slot, so the run stays within the cap", () => {
  let slots = 2;
  const actions = [{ exists: true, head: HEAD }, { exists: false }, { exists: false }].map((existing) => {
    const step = pushStep(existing, slots);
    slots = step.slots;
    return step.action;
  });
  assert.deepEqual(actions, ["reuse", "push", "past-cap"]);
});

test("a branch that already has its pull request uses no slot", () => {
  assert.deepEqual(pushStep({ exists: true }, 1), { action: "done", slots: 1 });
});

const OTHER = "e".repeat(40);
const reader = (routes) => async (path) => {
  const hit = Object.keys(routes).find((prefix) => path.includes(prefix));
  return hit ? routes[hit] : null;
};

test("a re-run finds its branch at the planned tree and hands publish the tip", async () => {
  const read = reader({ "/git/ref/": { object: { sha: HEAD } }, "/git/commits/": { tree: { sha: "tree" } } });
  assert.deepEqual(await findExisting(read, "o/r", { branch: "b", tree: "tree", i: 0 }), { exists: true, head: HEAD });
});

test("no branch yet is not an existing one", async () => {
  assert.deepEqual(await findExisting(reader({}), "o/r", { branch: "b", tree: "tree", i: 0 }), { exists: false });
});

test("another tree with a pull request is done; with none it stops the run", async () => {
  const routes = { "/git/ref/": { object: { sha: HEAD } }, "/git/commits/": { tree: { sha: "other" } } };
  assert.deepEqual(await findExisting(reader({ ...routes, "/pulls?": [{ number: 1 }] }), "o/r", { branch: "b", tree: "tree", i: 0 }), { exists: true });
  await assert.rejects(findExisting(reader({ ...routes, "/pulls?": [] }), "o/r", { branch: "b", tree: "tree", i: 2 }), /sweeps\[2\]/);
});

test("openPulls opens only branches at their head with no pull request", async () => {
  const a = prSweep();
  const posted = [];
  const read = async (path, options = {}) => {
    if (options.method === "POST") return posted.push(options.body.head);
    if (path.includes("/git/ref/heads/moved")) return { object: { sha: OTHER } };
    if (path.includes("/git/ref/")) return { object: { sha: HEAD } };
    return path.includes("has-pr") ? [{ number: 1 }] : [];
  };
  const sweeps = [a, { ...a, branch: "has-pr" }, { ...a, branch: "moved" }, { ...a, branch: "not-pushed" }];
  const heads = { [a.branch]: HEAD, "has-pr": HEAD, moved: HEAD };
  assert.equal(await openPulls(read, "o/r", sweeps, heads, "12894"), 1);
  assert.deepEqual(posted, [a.branch]);
});

// The spec issue the team config names (docs/conventions/code-tidying.yaml upkeep_spec_issue).
const SPEC = "12894";
const pullReader = (posted) => async (path, options = {}) => {
  if (options.method === "POST") return posted.push(options.body.body);
  return path.includes("/git/ref/") ? { object: { sha: HEAD } } : [];
};

test("each pull request's body opens with Refs: to the configured spec issue, the link pr-verify reads", async () => {
  const posted = [];
  await openPulls(pullReader(posted), "o/r", [prSweep()], { [prSweep().branch]: HEAD }, SPEC);
  assert.equal(posted.length, 1);
  assert.equal(posted[0].split("\n")[0], "Refs: #12894");
  // refsIssue is the reader pr-verify (resolve-pr.mjs linkedIssues) and pr-merge share.
  assert.equal(refsIssue(posted[0]), 12894);
  assert.match(posted[0], /## Summary\n\nNamed the lane reader\.$/);
});

test("with no spec issue configured the batch opens no pull request and says why", async () => {
  for (const missing of ["", undefined, "0", "#12894", "12894 "]) {
    const posted = [];
    await assert.rejects(openPulls(pullReader(posted), "o/r", [prSweep()], { [prSweep().branch]: HEAD }, missing), /upkeep_spec_issue/);
    assert.deepEqual(posted, []);
    assert.throws(() => prBody("## Summary", missing), /upkeep_spec_issue/);
  }
});

test("a body that links another issue is refused: a second Refs line unlinks the spec, a closing keyword overrides it", () => {
  assert.equal(prBody("## Summary\n\nRefs: #12894", SPEC).split("\n")[0], "Refs: #12894");
  for (const body of ["Refs: #7585", "## Related\n\nRefs: #1, #2", "Closes #7585", "## Fix\n\nThis fixes #12.", "resolves melodic-software/other#3"]) {
    assert.throws(() => prBody(body, SPEC), /another issue/, body);
  }
});
