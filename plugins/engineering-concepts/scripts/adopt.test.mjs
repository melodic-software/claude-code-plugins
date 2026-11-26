import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { main } from "./adopt.mjs";
import { main as lookup } from "./lookup.mjs";

process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const FIXTURES = join(fileURLToPath(new URL(".", import.meta.url)), "fixtures", "data");
const scratch = mkdtempSync(join(tmpdir(), "ec-adopt-"));
after(() => rmSync(scratch, { recursive: true, force: true }));
let count = 0;

const WORKED_EXAMPLE = join(fileURLToPath(new URL(".", import.meta.url)), "..", "..", "..", "docs", "contracts", "standards", "examples", "worked-index.md");
const INDEX = readFileSync(WORKED_EXAMPLE, "utf8").match(/```markdown\n([\s\S]*?)```/u)[1];

function tree(files = {}) {
  const dir = join(scratch, `tree-${++count}`);
  mkdirSync(dir);
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  return dir;
}

function repo(files = {}) {
  const dir = tree(files);
  assert.equal(spawnSync("git", ["init", "-q", dir]).status, 0);
  return dir;
}

async function run(args, { home = tree(), project = repo() } = {}) {
  const out = [];
  const err = [];
  const code = await main(["--data-dir", FIXTURES, "--home", home, "--project", project, ...args], {
    out: (line) => out.push(line),
    err: (line) => err.push(line),
  });
  return { code, out: out.join("\n"), errors: err.map((line) => JSON.parse(line)) };
}

const personalHome = () => tree({ ".claude/standards/README.md": INDEX });
const personal = (home, name) => join(home, ".claude", "standards", name);
const rowsFor = (index, file) => index.split("\n").filter((line) => line.startsWith("|") && line.split(/(?<!\\)\|/u)[3]?.trim() === file);

test("without --yes it shows what it would write, exits 3 and writes nothing", async () => {
  const home = personalHome();
  const { code, out } = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size"], { home });
  assert.equal(code, 3);
  assert.match(out, /- Example Small Steps \(`example-small-steps`\): https:\/\/example\.com\/small-steps/u);
  assert.match(out, /\| change-size \| change-size \| change-size\.md \|/u);
  assert.equal(existsSync(personal(home, "change-size.md")), false);
  assert.equal(readFileSync(personal(home, "README.md"), "utf8"), INDEX);
});

test("the preview of a new file holds the whole text --yes then writes, header included, and the index row", async () => {
  const home = personalHome();
  const args = ["example-small-steps", "--layer", "personal", "--surface", "change-size"];
  const preview = await run(args, { home });
  assert.equal((await run([...args, "--yes"], { home })).code, 0);
  const written = readFileSync(personal(home, "change-size.md"), "utf8");
  assert.ok(written.startsWith("# "), "a new file starts with its heading");
  assert.ok(preview.out.includes(`Would create ${personal(home, "change-size.md")}:\n${written}`), preview.out);
  assert.ok(preview.out.includes(`Would add this row to ${personal(home, "README.md")}:\n| change-size | change-size | change-size.md |`), preview.out);
});

test("the preview of an existing file shows exactly the lines --yes then appends", async () => {
  const home = personalHome();
  const adopt = (extra, ...ids) => run([...ids, "--layer", "personal", "--surface", "change-size", ...extra], { home });
  assert.equal((await adopt(["--yes"], "example-small-steps")).code, 0);
  const before = readFileSync(personal(home, "change-size.md"), "utf8");
  const preview = await adopt([], "example-review-gate");
  assert.equal((await adopt(["--yes"], "example-review-gate")).code, 0);
  const after = readFileSync(personal(home, "change-size.md"), "utf8");
  assert.ok(after.startsWith(before), "the existing text is kept as it was");
  assert.equal(after.slice(before.length), "- Example Review Gate (`example-review-gate`): https://example.com/review-gate\n");
  assert.ok(preview.out.includes(`Would append to ${personal(home, "change-size.md")}:\n${after.slice(before.length)}`), preview.out);
  assert.doesNotMatch(preview.out, /Would add this row/u, "the row already exists");
});

test("with --yes it writes a file with no frontmatter and no counterweight lines, and one index row; the lookup prints the counterweights and conflicts of the ids the file cites", async () => {
  const home = personalHome();
  const { code } = await run(["example-big-design", "--layer", "personal", "--surface", "change-size", "--yes"], { home });
  assert.equal(code, 0);
  const text = readFileSync(personal(home, "change-size.md"), "utf8");
  assert.doesNotMatch(text, /^---$/mu, "a standards file carries no frontmatter anywhere");
  const entries = text.split("\n").filter((line) => line.startsWith("- ") || line.startsWith("  "));
  assert.deepEqual(entries, ["- Example Big Design Up Front (`example-big-design`): https://example.com/big-design"]);
  assert.doesNotMatch(text, /Counterweight|Conflicts with|example-small-steps|example-review-gate/u, "counterweights come from the lookup, not the file");
  const index = readFileSync(personal(home, "README.md"), "utf8");
  assert.deepEqual(rowsFor(index, "change-size.md"), ["| change-size | change-size | change-size.md |"]);
  assert.deepEqual(rowsFor(index, "testing.md").length, 1, "the existing row stays");

  const cited = [...text.matchAll(/^- .*\(`([a-z0-9-]+)`\)/gmu)].map((m) => m[1]);
  const lines = [];
  const lookupCode = await lookup(["--data-dir", FIXTURES, "--home", home, "--project", repo(), "--counterweights-of", cited.join(",")], {
    out: (line) => lines.push(JSON.parse(line)),
    err: () => {},
  });
  assert.equal(lookupCode, 0);
  const big = { id: "example-big-design", name: "Example Big Design Up Front" };
  assert.deepEqual(lines, [
    { of: big, relation: "counterweight", concept: { id: "example-small-steps", name: "Example Small Steps" } },
    { of: big, relation: "conflict", concept: { id: "example-review-gate", name: "Example Review Gate" } },
  ]);
});

test("adopting again appends only the new concepts and keeps one index row; adopting nothing new writes nothing", async () => {
  const home = personalHome();
  const adopt = (...ids) => run([...ids, "--layer", "personal", "--surface", "change-size", "--yes"], { home });
  assert.equal((await adopt("example-small-steps")).code, 0);
  assert.equal((await adopt("tiny-steps", "example-review-gate")).code, 0);
  const text = readFileSync(personal(home, "change-size.md"), "utf8");
  const entries = text.split("\n").filter((line) => line.startsWith("- "));
  assert.deepEqual(entries, [
    "- Example Small Steps (`example-small-steps`): https://example.com/small-steps",
    "- Example Review Gate (`example-review-gate`): https://example.com/review-gate",
  ]);
  assert.equal(rowsFor(readFileSync(personal(home, "README.md"), "utf8"), "change-size.md").length, 1);
  const again = await adopt("example-small-steps");
  assert.equal(again.code, 0);
  assert.match(again.out, /already adopted/u);
  assert.equal(readFileSync(personal(home, "change-size.md"), "utf8"), text);
});

test("a term that names no shipped concept is reported, exits 1 and nothing is written", async () => {
  const home = personalHome();
  const { code, errors } = await run(["example-small-steps", "no-such-concept", "--layer", "personal", "--surface", "change-size", "--yes"], { home });
  assert.equal(code, 1);
  assert.deepEqual(errors.map((e) => [e.event, e.term]), [["concept not found", "no-such-concept"]]);
  assert.equal(existsSync(personal(home, "change-size.md")), false);
  assert.equal(readFileSync(personal(home, "README.md"), "utf8"), INDEX);
});

test("the team layer writes under the standards root the repository's .claude/standards.yaml names", async () => {
  const project = repo({ ".claude/standards.yaml": "standards_dir: handbook/standards\n", "handbook/standards/README.md": INDEX });
  const { code } = await run(["example-small-steps", "--layer", "team", "--surface", "change-size", "--yes"], { project });
  assert.equal(code, 0);
  const root = join(project, "handbook", "standards");
  assert.match(readFileSync(join(root, "change-size.md"), "utf8"), /^- Example Small Steps \(`example-small-steps`\)/mu);
  assert.deepEqual(rowsFor(readFileSync(join(root, "README.md"), "utf8"), "change-size.md"), ["| change-size | change-size | change-size.md |"]);
});

test("a team standards root with no index is refused with exit 1, and its hand-written README is left alone", async () => {
  const handWritten = "# Our standards\n\nSee testing.md.\n";
  const project = repo({ "docs/standards/README.md": handWritten });
  const { code, errors } = await run(["example-small-steps", "--layer", "team", "--surface", "change-size", "--yes"], { project });
  assert.equal(code, 1);
  assert.deepEqual(errors.map((e) => e.event), ["no team index"]);
  assert.equal(existsSync(join(project, "docs", "standards", "change-size.md")), false);
  assert.equal(readFileSync(join(project, "docs", "standards", "README.md"), "utf8"), handWritten);
});

test("a personal layer with no index gets the file and no index, and the output says the folder is read file by file", async () => {
  const home = tree();
  const { code, out } = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home });
  assert.equal(code, 0);
  assert.match(readFileSync(personal(home, "change-size.md"), "utf8"), /^- Example Small Steps \(`example-small-steps`\)/mu);
  assert.equal(existsSync(personal(home, "README.md")), false);
  assert.match(out, /read file by file/u);
});

test("a missing or unknown layer, a surface that is not a kebab-case name, or an unknown option exits 2 and writes nothing", async () => {
  const cases = [
    [["example-small-steps", "--surface", "change-size"], "layer"],
    [["example-small-steps", "--layer", "org", "--surface", "change-size"], "layer"],
    [["example-small-steps", "--layer", "personal", "--surface", "../escape"], "surface"],
    [["example-small-steps", "--layer", "personal", "--surface", "Change Size"], "surface"],
    [["example-small-steps", "--layer", "personal", "--surface", "readme"], "surface"],
    [["example-small-steps", "--layer", "personal", "--surface", "README"], "surface"],
    [["example-small-steps", "--layer", "personal", "--surface", "change-size", "--applies-when", "a \\| b"], "applies-when"],
    [["example-small-steps", "--layer", "personal", "--surface", "change-size", "--force"], null],
    [["--layer", "personal", "--surface", "change-size"], "concepts"],
  ];
  for (const [args, option] of cases) {
    const home = personalHome();
    const { code, errors } = await run([...args, "--yes"], { home });
    assert.equal(code, 2, args.join(" "));
    assert.deepEqual(errors.map((e) => [e.event, e.option]), [["invalid option", option]], args.join(" "));
    assert.equal(readFileSync(personal(home, "README.md"), "utf8"), INDEX);
  }
});

test("a standards_dir that resolves outside the repository is refused with exit 1", async () => {
  const outside = tree({ "README.md": INDEX });
  const project = repo({ ".claude/standards.yaml": `standards_dir: ../${outside.split("/").pop()}\n` });
  const { code, errors } = await run(["example-small-steps", "--layer", "team", "--surface", "change-size", "--yes"], { project });
  assert.equal(code, 1);
  assert.deepEqual(errors.map((e) => e.event), ["standards root outside the repository"]);
  assert.equal(existsSync(join(outside, "change-size.md")), false);
});

test("a | in --applies-when is escaped so the index row keeps three columns", async () => {
  const home = personalHome();
  await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--applies-when", "sizing a change | splitting work", "--yes"], { home });
  const [row] = rowsFor(readFileSync(personal(home, "README.md"), "utf8"), "change-size.md");
  assert.equal(row, "| change-size | sizing a change \\| splitting work | change-size.md |");
});

test("a newline in --applies-when becomes a space, and a | inside backticks is escaped too, so the row stays on one line with three columns", async () => {
  const home = personalHome();
  await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--applies-when", "sizing a change\nsplitting `a|b` work", "--yes"], { home });
  const [row] = rowsFor(readFileSync(personal(home, "README.md"), "utf8"), "change-size.md");
  assert.equal(row, "| change-size | sizing a change splitting `a\\|b` work | change-size.md |");
});

test("a backslash in --applies-when is refused with exit 2 and a reason, since no escape keeps it right both in and out of backticks", async () => {
  const home = personalHome();
  const { code, errors } = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--applies-when", "a \\| b", "--yes"], { home });
  assert.equal(code, 2);
  assert.match(errors[0].reason, /backslash/u);
  assert.equal(existsSync(personal(home, "change-size.md")), false);
});

const longFile = (lines) => `# Long\n${Array.from({ length: lines - 1 }, (_, i) => `- line ${i}`).join("\n")}\n`;

test("a write that takes the file past the contract's 200-line budget warns and still writes; one that reaches 200 does not", async () => {
  for (const [existing, warns] of [[200, true], [199, false]]) {
    const home = tree({ ".claude/standards/README.md": INDEX, ".claude/standards/change-size.md": longFile(existing) });
    const { code, errors } = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home });
    assert.equal(code, 0, `${existing} lines`);
    assert.equal(readFileSync(personal(home, "change-size.md"), "utf8").split("\n").length - 1, existing + 1);
    assert.deepEqual(
      errors.map((e) => [e.level, e.event, e.lines]),
      warns ? [["warn", "standards file over budget", existing + 1]] : [],
      `${existing} lines`,
    );
    if (warns) assert.match(errors[0].contract, /soft budget of roughly 200 lines per file/u);
  }
});

test("run as a command, it previews with exit 3", () => {
  const script = fileURLToPath(new URL("./adopt.mjs", import.meta.url));
  const home = personalHome();
  const r = spawnSync(process.execPath, [script, "tiny-steps", "--layer", "personal", "--surface", "change-size", "--data-dir", FIXTURES, "--home", home], { encoding: "utf8" });
  assert.equal(r.status, 3, r.stderr);
  assert.match(r.stdout, /Re-run with --yes to write\./u);
});

test("a malformed .claude/standards.yaml is reported with its path and exits 1", async () => {
  const project = repo({ ".claude/standards.yaml": "standards_dir: [docs\n", "docs/standards/README.md": INDEX });
  const { code, errors } = await run(["example-small-steps", "--layer", "team", "--surface", "change-size", "--yes"], { project });
  assert.equal(code, 1);
  assert.deepEqual(errors.map((e) => [e.event, e.file]), [["standards config unreadable", join(project, ".claude", "standards.yaml")]]);
  assert.equal(existsSync(join(project, "docs", "standards", "change-size.md")), false);
});
