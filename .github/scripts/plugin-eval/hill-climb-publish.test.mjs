// hill-climb-publish.mjs holds the owner's grant (AL-Q11, #12035) the broker cannot see: the one
// branch is chore/hill-climb-<plugin>-<skill>-<run id>, the pull request opens as a draft, the
// pushed diff is the skill's markdown and one fixed fragment, and the body quotes run text only
// inside a fence.
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import process from "node:process";
import { test } from "node:test";

import { netRawDiff } from "../upstream-apply-changelog/upstream-apply-changelog.mjs";
import { BRANCH_PREFIX, bodyOf, branchOf, diffRefusal, existingHead, fragmentOf, frontmatterOf, frontmatterRefusal, openDraft, SPEC_ISSUE, titleOf } from "./hill-climb-publish.mjs";

const SHA_A = "a".repeat(40);
const SHA_B = "b".repeat(40);
const TREE = "c".repeat(40);
const noHold = () => false;

test("the branch is the one chore/hill-climb-* name the inputs fill, and nothing else", () => {
  assert.equal(branchOf("testing", "write", "19000000001"), "chore/hill-climb-testing-write-19000000001");
  assert.ok(branchOf("a", "b", 1).startsWith(BRANCH_PREFIX));
  assert.equal(BRANCH_PREFIX, "chore/hill-climb-");
  for (const [plugin, skill, run] of [
    ["Testing", "write", "1"],
    ["testing", "write.v2", "1"],
    ["testing", "write_x", "1"],
    ["testing", "../main", "1"],
    ["testing", "a/b", "1"],
    ["testing", "", "1"],
    ["testing", "-write", "1"],
    ["testing", "write", "0"],
    ["testing", "write", "12a"],
    ["testing", "write", ""],
    [undefined, "write", "1"],
  ]) {
    assert.throws(() => branchOf(plugin, skill, run), /lowercase kebab-case/, `${plugin} ${skill} ${run}`);
  }
});

test("the title is a Conventional Commits line scoped to the plugin", () => {
  assert.match(titleOf("testing", "write"), /^chore\(testing\): [^\r\n]+$/);
});

test("the fragment is named as new-changelog-fragment.sh names one, and the same patch gives the same fragment", () => {
  const branch = branchOf("testing", "write", "7");
  const one = fragmentOf("testing", "write", branch, Buffer.from("diff one\n"));
  assert.match(one.path, /^\.changes\/testing\/chore-hill-climb-testing-write-7-[0-9a-f]{8}\.md$/);
  // check-changelog-fragments.sh's name rule (scripts/lib/changelog-fragments.sh).
  assert.match(one.path.split("/").pop(), /^[a-z0-9][a-z0-9._-]*-[0-9a-f]{8}\.md$/);
  assert.deepEqual(fragmentOf("testing", "write", branch, Buffer.from("diff one\n")), one);
  assert.notEqual(fragmentOf("testing", "write", branch, Buffer.from("diff two\n")).path, one.path);
  assert.match(one.text, /^---\nbump: patch\n---\n\n### Changed\n\n- the `write` skill /);
});

const ctx = { plugin: "testing", skill: "write", fragment: ".changes/testing/f-12345678.md" };
const edit = (path) => `:100644 100644 ${SHA_A} ${SHA_B} M\t${path}`;
const added = (path, mode = "100644") => `:000000 ${mode} ${"0".repeat(40)} ${SHA_B} A\t${path}`;

test("frontmatterOf takes the block between the opening --- lines, and nothing from a file without one", () => {
  assert.equal(frontmatterOf("---\nname: write\nallowed-tools: Read\n---\n\n# Write\n"), "---\nname: write\nallowed-tools: Read\n---\n");
  assert.equal(frontmatterOf("# Write\n\n---\n\nbody\n"), "");
  assert.equal(frontmatterOf(""), "");
});

test("an edit that changes a skill file's frontmatter is refused; a body-only edit passes", () => {
  const files = {
    "base:SKILL.md": "---\nname: write\nallowed-tools: Read\n---\n\nOld body.\n",
    "body:SKILL.md": "---\nname: write\nallowed-tools: Read\n---\n\nNew body.\n",
    "tools:SKILL.md": "---\nname: write\nallowed-tools: Read, Bash\n---\n\nOld body.\n",
    "hook:SKILL.md": "---\nname: write\nallowed-tools: Read\nhooks:\n  PreToolUse: [{ command: \"curl x\" }]\n---\n\nOld body.\n",
    "base:ref.md": "No frontmatter here.\n",
    "added:ref.md": "---\nhooks: x\n---\nNo frontmatter here.\n",
  };
  const show = (ref, path) => files[`${ref}:${path}`];
  assert.equal(frontmatterRefusal(["SKILL.md"], show, "base", "body"), null);
  assert.equal(frontmatterRefusal(["SKILL.md"], show, "base", "tools"), "a frontmatter change in SKILL.md");
  assert.equal(frontmatterRefusal(["SKILL.md"], show, "base", "hook"), "a frontmatter change in SKILL.md");
  assert.equal(frontmatterRefusal(["ref.md"], show, "base", "added"), "a frontmatter change in ref.md");
});

test("the draft body says the frontmatter is unchanged", () => {
  const body = bodyOf({ plugin: "testing", skill: "write", runUrl: "https://example.invalid/run", winTest: "w", summaryA: "a", summaryB: "b", fragment: ctx.fragment });
  assert.match(body, /markdown body only; its frontmatter is unchanged/);
});

test("the pushed diff may hold only edits to the skill's markdown and the one new fragment", () => {
  assert.equal(diffRefusal([edit("plugins/testing/skills/write/SKILL.md"), added(ctx.fragment)].join("\n"), ctx, noHold), null);
  assert.equal(diffRefusal([edit("plugins/testing/skills/write/reference/a.md"), edit("plugins/testing/skills/write/SKILL.md"), added(ctx.fragment)].join("\n"), ctx, noHold), null);
  for (const [why, raw, reason] of [
    ["no fragment", [edit("plugins/testing/skills/write/SKILL.md")], /^no changelog fragment$/],
    ["no skill edit", [added(ctx.fragment)], /^no edit to the skill$/],
    ["another skill", [edit("plugins/testing/skills/other/SKILL.md"), added(ctx.fragment)], /outside plugins\/testing\/skills\/write\//],
    ["a workflow", [edit(".github/workflows/maintenance-measure-skill-edit.yml"), added(ctx.fragment)], /outside/],
    ["an eval case", [edit("plugins/testing/skills/write/evals/a.md"), added(ctx.fragment)], /under an evals\/ directory/],
    ["a script in the skill", [edit("plugins/testing/skills/write/scripts/run.sh"), added(ctx.fragment)], /not a markdown file/],
    ["a new skill file", [added("plugins/testing/skills/write/NEW.md"), added(ctx.fragment)], /not an edit to a regular file/],
    ["a deleted skill file", [`:100644 000000 ${SHA_A} ${"0".repeat(40)} D\tplugins/testing/skills/write/SKILL.md`, added(ctx.fragment)], /not an edit to a regular file/],
    ["an executable bit", [`:100644 100755 ${SHA_A} ${SHA_B} M\tplugins/testing/skills/write/SKILL.md`, added(ctx.fragment)], /not an edit to a regular file/],
    ["a symbolic link", [`:100644 120000 ${SHA_A} ${SHA_B} T\tplugins/testing/skills/write/SKILL.md`, added(ctx.fragment)], /not an edit to a regular file/],
    ["an executable fragment", [edit("plugins/testing/skills/write/SKILL.md"), added(ctx.fragment, "100755")], /fragment is not one new regular file/],
    ["a second fragment", [edit("plugins/testing/skills/write/SKILL.md"), added(ctx.fragment), added(".changes/testing/g-12345678.md")], /not an edit to a regular file/],
    ["a rename", [`:100644 100644 ${SHA_A} ${SHA_B} R100\tplugins/testing/skills/write/a.md\tplugins/testing/skills/write/b.md`, added(ctx.fragment)], /rename or copy/],
  ]) {
    assert.match(diffRefusal(raw.join("\n"), ctx, noHold) ?? "", reason, why);
  }
  assert.equal(diffRefusal([edit("plugins/testing/skills/write/SKILL.md"), added(ctx.fragment)].join("\n"), ctx, () => true), "a hold path");
});

test("a real patch to a skill file plus its fragment passes, read through git's own raw diff", () => {
  const repo = mkdtempSync(join(tmpdir(), "hill-climb-publish-"));
  const git = (...args) => execFileSync("git", ["-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", ...args], { encoding: "utf8" }).trim();
  try {
    git("init", "--quiet");
    execFileSync("mkdir", ["-p", join(repo, "plugins/testing/skills/write")]);
    writeFileSync(join(repo, "plugins/testing/skills/write/SKILL.md"), "one\n");
    git("add", "--all");
    git("commit", "--quiet", "-m", "base");
    const base = git("rev-parse", "HEAD");
    writeFileSync(join(repo, "plugins/testing/skills/write/SKILL.md"), "two\n");
    const fragment = fragmentOf("testing", "write", branchOf("testing", "write", "7"), Buffer.from("p"));
    execFileSync("mkdir", ["-p", join(repo, ".changes/testing")]);
    writeFileSync(join(repo, fragment.path), fragment.text);
    git("add", "--all");
    git("commit", "--quiet", "-m", "edit");
    const raw = netRawDiff(repo, base, git("rev-parse", "HEAD"));
    assert.equal(diffRefusal(raw, { plugin: "testing", skill: "write", fragment: fragment.path }, noHold), null);
    assert.equal(diffRefusal(raw, { plugin: "testing", skill: "write", fragment: ".changes/testing/other-12345678.md" }, noHold), "a change that is not an edit to a regular file");
  } finally {
    rmSync(repo, { recursive: true, force: true });
  }
});

test("the body opens with the spec link and quotes run text only inside a fence it cannot close", () => {
  const body = bodyOf({
    plugin: "testing",
    skill: "write",
    runUrl: "https://github.com/melodic-software/claude-code-plugins/actions/runs/7",
    winTest: "win: the edit gained 0.10\n",
    summaryA: "| case | 0.5 |\n- a: error @kyle-sexton ```` closes #1 [x](https://example.com)\n",
    summaryB: "| case | 0.9 |\n",
    fragment: ".changes/testing/f-12345678.md",
  });
  assert.equal(body.split("\n")[0], `Refs: #${SPEC_ISSUE}`);
  for (const heading of ["## Summary", "## Fix", "## Verification", "## Related"]) assert.ok(body.includes(`\n${heading}\n`), heading);
  // The summary's four backticks sit inside a five-backtick fence.
  const at = body.indexOf("@kyle-sexton");
  const open = body.lastIndexOf("`````text\n", at);
  assert.ok(open > 0 && body.indexOf("\n`````", at) > at, "the mention is inside a fence");
  assert.equal([...body.matchAll(/^Refs: #/gm)].length, 1);
});

test("a long summary is cut, so the body stays under GitHub's limit", () => {
  const body = bodyOf({ plugin: "p", skill: "s", runUrl: "u", winTest: "w", summaryA: "x".repeat(100000), summaryB: "y".repeat(100000), fragment: "f" });
  assert.ok(body.length < 65536, String(body.length));
  assert.match(body, /cut at 24000 characters/);
});

const keptOf = (summary) => {
  const body = bodyOf({ plugin: "p", skill: "s", runUrl: "u", winTest: "w", summaryA: summary, summaryB: "b", fragment: "f" });
  const start = body.indexOf("```text\n", body.indexOf("Pass a,")) + "```text\n".length;
  return body.slice(start, body.indexOf("\n(cut at 24000 characters", start));
};

test("a long summary is cut at a word, never inside one", () => {
  const kept = keptOf("abcdef ".repeat(4000));
  assert.ok(kept.length <= 24000, `kept ${kept.length} characters`);
  assert.ok(kept === "abcdef ".repeat(3428).trimEnd(), `the cut keeps 3428 whole words and no part of the next; it ends ${JSON.stringify(kept.slice(-12))}`);
});

test("a single token past the cap is cut hard, never inside a surrogate pair", () => {
  const kept = keptOf(`${"a".repeat(23999)}\u{1F600}tail`);
  assert.ok(!/[\uD800-\uDBFF](?![\uDC00-\uDFFF])/.test(kept), "no unpaired high surrogate is left");
  assert.ok(kept === "a".repeat(23999), `the emoji straddling the cap is dropped whole; it ends ${JSON.stringify(kept.slice(-4))}`);
});

// A recording stand-in for upstream-apply-changelog.mjs's api().
function fake(routes) {
  const calls = [];
  const read = async (path, options = {}) => {
    calls.push({ path, ...options });
    for (const [pattern, answer] of routes) if (pattern.test(path) && (options.method ?? "GET") === (answer.method ?? "GET")) return typeof answer.value === "function" ? answer.value() : answer.value;
    throw new Error(`unrouted ${options.method ?? "GET"} ${path}`);
  };
  return { read, calls };
}

const BRANCH = "chore/hill-climb-testing-write-7";

test("the pull request opens as a draft into main, once", async () => {
  const { read, calls } = fake([
    [/\/git\/ref\/heads\//, { value: { object: { sha: SHA_A } } }],
    [/\/pulls\?state=all/, { value: [] }],
    [/\/pulls$/, { method: "POST", value: { number: 1 } }],
  ]);
  assert.equal(await openDraft(read, "o/r", { branch: BRANCH, head: SHA_A, title: "t", body: "b" }), true);
  const post = calls.find((call) => call.method === "POST");
  assert.deepEqual(post.body, { title: "t", body: "b", head: BRANCH, base: "main", draft: true });
});

test("no pull request opens for a branch that has one, is not at the pushed head, or is outside chore/hill-climb-*", async () => {
  const has = fake([
    [/\/git\/ref\/heads\//, { value: { object: { sha: SHA_A } } }],
    [/\/pulls\?state=all/, { value: [{ number: 3 }] }],
  ]);
  assert.equal(await openDraft(has.read, "o/r", { branch: BRANCH, head: SHA_A, title: "t", body: "b" }), false);
  assert.ok(!has.calls.some((call) => call.method === "POST"));
  const moved = fake([[/\/git\/ref\/heads\//, { value: { object: { sha: SHA_B } } }]]);
  await assert.rejects(openDraft(moved.read, "o/r", { branch: BRANCH, head: SHA_A, title: "t", body: "b" }), /not at the head the push job left/);
  const other = fake([]);
  await assert.rejects(openDraft(other.read, "o/r", { branch: "main", head: SHA_A, title: "t", body: "b" }), /malformed/);
  await assert.rejects(openDraft(other.read, "o/r", { branch: "chore/tidy-adhoc-x", head: SHA_A, title: "t", body: "b" }), /malformed/);
  assert.deepEqual(other.calls, []);
});

test("a refused command names its stop in the job summary, as every gate before it does", () => {
  const dir = mkdtempSync(join(tmpdir(), "hill-climb-publish-summary-"));
  try {
    const summary = join(dir, "summary.md");
    writeFileSync(summary, "");
    const script = new URL("./hill-climb-publish.mjs", import.meta.url).pathname;
    const proc = spawnSync(process.execPath, [script, "push"], { env: { PATH: process.env.PATH, PLUGIN: "Bad", SKILL: "write", RUN_ID: "7", GITHUB_STEP_SUMMARY: summary }, encoding: "utf8" });
    assert.equal(proc.status, 1);
    assert.match(proc.stdout, /^::error::the plugin, the skill or the run id is not/m);
    assert.equal(readFileSync(summary, "utf8"), "gate: push: the plugin, the skill or the run id is not a lowercase kebab-case name and a run id\n");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a re-run reuses a branch at the built tree and stops on one holding another", async () => {
  const none = fake([[/\/git\/ref\/heads\//, { value: null }]]);
  assert.equal(await existingHead(none.read, "o/r", BRANCH, TREE), null);
  const same = fake([
    [/\/git\/ref\/heads\//, { value: { object: { sha: SHA_A } } }],
    [/\/git\/commits\//, { value: { tree: { sha: TREE } } }],
  ]);
  assert.equal(await existingHead(same.read, "o/r", BRANCH, TREE), SHA_A);
  const other = fake([
    [/\/git\/ref\/heads\//, { value: { object: { sha: SHA_A } } }],
    [/\/git\/commits\//, { value: { tree: { sha: SHA_B } } }],
  ]);
  await assert.rejects(existingHead(other.read, "o/r", BRANCH, TREE), /already exists with another tree/);
});
