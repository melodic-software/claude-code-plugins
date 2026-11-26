import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
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

test("an index with no table yet: the preview shows the blank line, table header, separator and row the write adds", async () => {
  const noTable = INDEX.slice(0, INDEX.indexOf("| Surface")).replace(/\n+$/u, "\n");
  const home = tree({ ".claude/standards/README.md": noTable });
  const args = ["example-small-steps", "--layer", "personal", "--surface", "change-size"];
  const preview = await run(args, { home });
  assert.equal(preview.code, 3);
  assert.equal((await run([...args, "--yes"], { home })).code, 0);
  const after = readFileSync(personal(home, "README.md"), "utf8");
  assert.ok(after.startsWith(noTable), "the existing index text is kept as it was");
  const added = after.slice(noTable.length);
  assert.equal(added, "\n| Surface | Applies when | File |\n|---|---|---|\n| change-size | change-size | change-size.md |\n");
  assert.ok(preview.out.includes(`${personal(home, "README.md")}:\n${added}`), preview.out);
});

test("with --yes it writes a file with no frontmatter and no counterweight lines, and one index row; the lookup option the file's header names prints the counterweights and conflicts of the ids the file cites", async () => {
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

  const header = text.slice(0, text.indexOf("\n- "));
  assert.match(header, /engineering-concepts plugin's\s+lookup/u, "the header names the command in plain words");
  const option = header.match(/`(--[a-z-]+)`/u)?.[1];
  assert.ok(option, "the header names the lookup option that lists counterweights");
  const cited = [...text.matchAll(/^- .*\(`([a-z0-9-]+)`\)/gmu)].map((m) => m[1]);
  const lines = [];
  const lookupCode = await lookup(["--data-dir", FIXTURES, "--home", home, "--project", repo(), option, cited.join(",")], {
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
    [["example-small-steps", "--layer", "personal", "--surface", "change-size", "--applies-when", ""], "applies-when"],
    [["example-small-steps", "--layer", "personal", "--surface", "change-size", "--applies-when", " \n "], "applies-when"],
    [["example-small-steps", "--layer", "personal", "--surface", "change-size", "--force"], "force"],
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

test("an empty --applies-when is refused with exit 2 and a reason", async () => {
  const home = personalHome();
  const { code, errors } = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--applies-when", "", "--yes"], { home });
  assert.equal(code, 2);
  assert.match(errors[0].reason, /empty/u);
  assert.equal(existsSync(personal(home, "change-size.md")), false);
});

test("a surface file or index that is a symbolic link is refused with exit 1 and a reason, and the link and its target are left as they were", async () => {
  for (const name of ["change-size.md", "README.md"]) {
    const home = personalHome();
    const target = join(tree({ "target.md": "# Elsewhere\n" }), "target.md");
    if (name === "README.md") writeFileSync(target, INDEX);
    rmSync(personal(home, name), { force: true });
    symlinkSync(target, personal(home, name));
    const before = readFileSync(target, "utf8");
    const { code, errors } = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home });
    assert.equal(code, 1, name);
    assert.deepEqual(errors.map((e) => [e.event, e.path]), [["symbolic link refused", personal(home, name)]], name);
    assert.match(errors[0].reason, /symbolic link/u, name);
    assert.ok(lstatSync(personal(home, name)).isSymbolicLink(), `${name} is still a link`);
    assert.equal(readFileSync(target, "utf8"), before, name);
  }
});

const TEAM_SETTINGS = "docs/conventions/engineering-concepts.yaml";

test("a concept the exclude setting drops is refused when named by id, alias or topic, with exit 1 and the setting and layer that drop it; nothing is written", async () => {
  for (const [term, listed] of [["example-small-steps", "example-small-steps"], ["tiny-steps", "example-small-steps"], ["example-review-gate", "beta"]]) {
    const project = repo({ [TEAM_SETTINGS]: `exclude:\n  - ${listed}\n` });
    const home = personalHome();
    const { code, errors } = await run([term, "--layer", "personal", "--surface", "change-size", "--yes"], { home, project });
    assert.equal(code, 1, term);
    assert.deepEqual(
      errors.map((e) => [e.event, e.term, e.setting, e.value, e.layer, e.path]),
      [["concept excluded", term, "exclude", listed, "team", join(project, TEAM_SETTINGS)]],
      term,
    );
    assert.equal(existsSync(personal(home, "change-size.md")), false, term);
    assert.equal(readFileSync(personal(home, "README.md"), "utf8"), INDEX, term);
  }
});

test("the user's exclude option refuses a concept with its layer named, and a concept it does not list is adopted", async () => {
  const home = personalHome();
  const userConfig = join(tree({ "user-config.json": JSON.stringify({ exclude: "example-big-design" }) }), "user-config.json");
  const refused = await run(["example-big-design", "--layer", "personal", "--surface", "change-size", "--user-config", userConfig, "--yes"], { home });
  assert.equal(refused.code, 1);
  assert.deepEqual(refused.errors.map((e) => [e.event, e.setting, e.value, e.layer]), [["concept excluded", "exclude", "example-big-design", "userConfig"]]);
  const adopted = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--user-config", userConfig, "--yes"], { home });
  assert.equal(adopted.code, 0);
  assert.match(readFileSync(personal(home, "change-size.md"), "utf8"), /^- Example Small Steps \(`example-small-steps`\)/mu);
});

test("source_bar official-plus-confirming refuses a concept with no confirming source, naming the setting and its layer, and adopts one that has one", async () => {
  const project = repo({ [TEAM_SETTINGS]: "source_bar: official-plus-confirming\n" });
  const home = personalHome();
  const refused = await run(["example-big-design", "--layer", "personal", "--surface", "change-size", "--yes"], { home, project });
  assert.equal(refused.code, 1);
  assert.deepEqual(
    refused.errors.map((e) => [e.event, e.setting, e.value, e.layer, e.path]),
    [["concept excluded", "source_bar", "official-plus-confirming", "team", join(project, TEAM_SETTINGS)]],
  );
  assert.equal(existsSync(personal(home, "change-size.md")), false);
  assert.equal((await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home, project })).code, 0);
});

const lineBreakNote = (path) => `A line break will also be added at the end of ${path}, which does not end with one.`;

test("the preview says so when the index or the surface file lacks a final line break, and says nothing when both have one", async () => {
  const cases = [
    [{ ".claude/standards/README.md": INDEX.replace(/\n+$/u, "") }, "README.md"],
    [{ ".claude/standards/README.md": INDEX, ".claude/standards/change-size.md": "# Mine" }, "change-size.md"],
    [{ ".claude/standards/README.md": INDEX, ".claude/standards/change-size.md": "# Mine\n" }, null],
  ];
  for (const [files, lacking] of cases) {
    const home = tree(files);
    const preview = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size"], { home });
    assert.equal(preview.code, 3);
    const notes = preview.out.split("\n").filter((line) => line.startsWith("A line break will also be added"));
    assert.deepEqual(notes, lacking ? [lineBreakNote(personal(home, lacking))] : [], String(lacking));
    if (!lacking) continue;
    assert.equal((await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home })).code, 0);
    const written = readFileSync(personal(home, lacking), "utf8");
    assert.ok(written.startsWith(`${files[`.claude/standards/${lacking}`]}\n`), `${lacking} gained the line break the preview named`);
  }
});

test("a --user-config file that does not exist is refused with the plain reason 'could not be read: file not found'", async () => {
  const { code, errors } = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--user-config", join(tree(), "missing.json")]);
  assert.equal(code, 2);
  assert.deepEqual(errors.map((e) => [e.event, e.option, e.reason]), [["invalid option", "user-config", "could not be read: file not found"]]);
});

test("a .claude/standards.yaml the parser rejects is reported as not valid, with a plain lead-in before the parser's detail", async () => {
  const project = repo({ ".claude/standards.yaml": "standards_dir: [docs\n", "docs/standards/README.md": INDEX });
  const { errors } = await run(["example-small-steps", "--layer", "team", "--surface", "change-size"], { project });
  assert.match(errors[0].reason, /^the settings file is not valid: .*line 1/u);
});

test("a concept refused by a setting names the layer in plain words, keeping the layer key", async () => {
  const userConfig = join(tree({ "user-config.json": JSON.stringify({ exclude: "example-small-steps" }) }), "user-config.json");
  const cases = [
    [{}, ["--user-config", userConfig], "userConfig", "your saved plugin options"],
    [{ [TEAM_SETTINGS]: "exclude:\n  - example-small-steps\n" }, [], "team", "the repository's settings file"],
    [{ "docs/conventions/engineering-concepts.local.yaml": "exclude:\n  - example-small-steps\n" }, [], "local", "your personal settings file for this repository"],
  ];
  for (const [files, extra, layer, plain] of cases) {
    const { code, errors } = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", ...extra], { project: repo(files) });
    assert.equal(code, 1, layer);
    assert.equal(errors.at(-1).layer, layer);
    assert.ok(errors.at(-1).reason.includes(plain), errors.at(-1).reason);
    assert.doesNotMatch(errors.at(-1).reason, /userConfig|\blocal layer|\bteam layer/u);
  }
});

test("a write the file system refuses names the target file and the reason in plain words, keeping the code as a key", { skip: process.getuid?.() === 0 && "root ignores directory permissions" }, async () => {
  const home = personalHome();
  const dir = join(home, ".claude", "standards");
  chmodSync(dir, 0o500);
  try {
    const { code, errors } = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home });
    assert.equal(code, 1);
    const target = personal(home, "change-size.md");
    const index = personal(home, "README.md");
    assert.deepEqual(errors.map((e) => [e.event, e.path, e.code]), [["write refused", target, "EACCES"], ["write refused", index, "EACCES"]]);
    assert.equal(errors[0].message, `${target} could not be written: permission denied`);
    assert.equal(readFileSync(index, "utf8"), INDEX);
  } finally {
    chmodSync(dir, 0o700);
  }
});

test("a --user-config that is a folder is refused with the plain reason 'could not be read: it is a folder, not a file'", async () => {
  const { code, errors } = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--user-config", tree()]);
  assert.equal(code, 2);
  assert.deepEqual(errors.map((e) => [e.event, e.option, e.reason]), [["invalid option", "user-config", "could not be read: it is a folder, not a file"]]);
});

test("a settings value the schema rejects stops adopt, so an exclude written as a string is never silently ignored", async () => {
  for (const text of ["exclude: example-small-steps\n", "exclude: [example-small-steps, 5]\n"]) {
    const project = repo({ [TEAM_SETTINGS]: text });
    const home = personalHome();
    const { code, errors } = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home, project });
    assert.equal(code, 1, text);
    assert.deepEqual(errors.map((e) => [e.level, e.event, e.layer]), [["error", "settings file invalid", "team"]], text);
    assert.ok(errors[0].reason.startsWith("the repository's settings file, "), errors[0].reason);
    assert.equal(existsSync(personal(home, "change-size.md")), false, text);
  }
});

test("a surface file that is not a regular file (a named pipe) is refused instead of hanging", async () => {
  const home = personalHome();
  const fifo = personal(home, "change-size.md");
  if (spawnSync("mkfifo", [fifo]).status !== 0) return;
  const { code, errors } = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home });
  assert.equal(code, 1);
  assert.deepEqual(errors.map((e) => [e.event, e.reason]), [["file unreadable", `${fifo} could not be read: it is not a regular file`]]);
  assert.equal(readFileSync(personal(home, "README.md"), "utf8"), INDEX);
});

test("a malformed plugin settings file stops adopt as not valid, in a plain sentence naming the file and its layer, while the lookup only warns", async () => {
  const cases = [
    [TEAM_SETTINGS, "team", "the repository's settings file"],
    ["docs/conventions/engineering-concepts.local.yaml", "local", "your personal settings file for this repository"],
  ];
  for (const [file, layer, plain] of cases) {
    const project = repo({ [file]: "exclude: [example-small-steps\n" });
    const home = personalHome();
    const path = join(project, file);
    const { code, errors } = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home, project });
    assert.equal(code, 1, layer);
    assert.deepEqual(errors.map((e) => [e.level, e.event, e.layer, e.path]), [["error", "settings file invalid", layer, path]], layer);
    assert.ok(errors[0].reason.startsWith(`${plain}, ${path}, is not valid, so nothing is adopted until it is fixed: `), errors[0].reason);
    assert.match(errors[0].reason, /line 1/u, "the parser's line stays in the reason");
    assert.ok(!errors[0].reason.includes(`${layer} (`), errors[0].reason);
    assert.equal(existsSync(personal(home, "change-size.md")), false, layer);
    assert.equal(readFileSync(personal(home, "README.md"), "utf8"), INDEX, layer);

    const warnings = [];
    const lookupCode = await lookup(["--data-dir", FIXTURES, "--home", home, "--project", project, "example-small-steps"], { out: () => {}, err: (line) => warnings.push(JSON.parse(line)) });
    assert.equal(lookupCode, 0, layer);
    assert.deepEqual(warnings.map((w) => [w.level, w.event]), [["warn", "setting rejected"]], layer);
  }
});

test("when every concept named is already cited in another file, the existing surface file gets no index row in the preview or the write", async () => {
  const cited = "# Testing\n\n- Example Small Steps (`example-small-steps`): https://example.com/small-steps\n";
  const home = tree({ ".claude/standards/README.md": INDEX, ".claude/standards/testing.md": cited, ".claude/standards/change-size.md": "" });
  const args = ["example-small-steps", "--layer", "personal", "--surface", "change-size"];
  const preview = await run(args, { home });
  assert.equal(preview.code, 0);
  assert.doesNotMatch(preview.out, /Would add/u);
  const write = await run([...args, "--yes"], { home });
  assert.equal(write.code, 0);
  assert.match(write.out, /Nothing to write/u);
  assert.doesNotMatch(write.out, /Adopted 0/u);
  assert.equal(readFileSync(personal(home, "README.md"), "utf8"), INDEX);
  assert.equal(readFileSync(personal(home, "change-size.md"), "utf8"), "");
});

test("a surface file holding only whitespace gets the header a new file gets", async () => {
  const home = tree({ ".claude/standards/README.md": INDEX, ".claude/standards/change-size.md": "  \n\n\t\n" });
  const fresh = personalHome();
  const args = ["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"];
  assert.equal((await run(args, { home })).code, 0);
  assert.equal((await run(args, { home: fresh })).code, 0);
  assert.equal(readFileSync(personal(home, "change-size.md"), "utf8"), readFileSync(personal(fresh, "change-size.md"), "utf8"));
});

const lfOnly = (text) => text.replace(/\r\n/gu, "").includes("\n");

test("a CRLF index and a CRLF surface file keep CRLF on every line adopt adds", async () => {
  const noTable = INDEX.slice(0, INDEX.indexOf("| Surface")).replace(/\n+$/u, "\n");
  for (const index of [INDEX, noTable]) {
    const crlf = index.replace(/\n/gu, "\r\n");
    const home = tree({ ".claude/standards/README.md": crlf, ".claude/standards/change-size.md": "# Mine\r\n" });
    assert.equal((await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home })).code, 0);
    const written = readFileSync(personal(home, "README.md"), "utf8");
    assert.ok(written.startsWith(crlf), "the existing index text is kept as it was");
    assert.ok(written.includes("| change-size | change-size | change-size.md |\r\n"), written);
    assert.equal(lfOnly(written), false, JSON.stringify(written));
    const surface = readFileSync(personal(home, "change-size.md"), "utf8");
    assert.equal(surface, "# Mine\r\n- Example Small Steps (`example-small-steps`): https://example.com/small-steps\r\n");
  }
});

test("a concept cited in a standards file in a subfolder of the layer is not added again, and one cited only through a symbolic link is", async () => {
  const cited = "# Testing\n\n- Example Small Steps (`example-small-steps`): https://example.com/small-steps\n";
  const nested = tree({ ".claude/standards/README.md": INDEX, ".claude/standards/topics/testing.md": cited });
  const found = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home: nested });
  assert.equal(found.code, 0);
  assert.ok(found.out.includes(personal(nested, join("topics", "testing.md"))), found.out);
  assert.equal(existsSync(personal(nested, "change-size.md")), false);

  const outside = tree({ "elsewhere/testing.md": cited });
  const linked = personalHome();
  symlinkSync(join(outside, "elsewhere", "testing.md"), personal(linked, "linked.md"));
  symlinkSync(join(outside, "elsewhere"), personal(linked, "linked-dir"));
  const adopted = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home: linked });
  assert.equal(adopted.code, 0);
  assert.doesNotMatch(adopted.out, /already adopted/u);
  assert.match(readFileSync(personal(linked, "change-size.md"), "utf8"), /^- Example Small Steps \(`example-small-steps`\)/mu);
});

test("a surface file that exists but is empty gets the header a new file gets, naming the --counterweights-of lookup", async () => {
  const home = tree({ ".claude/standards/README.md": INDEX, ".claude/standards/change-size.md": "" });
  const fresh = personalHome();
  const args = ["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"];
  assert.equal((await run(args, { home })).code, 0);
  assert.equal((await run(args, { home: fresh })).code, 0);
  const written = readFileSync(personal(home, "change-size.md"), "utf8");
  assert.match(written, /`--counterweights-of`/u);
  assert.equal(written, readFileSync(personal(fresh, "change-size.md"), "utf8"));
});

test("no concept named is refused with a plain reason", async () => {
  const { code, errors } = await run(["--layer", "personal", "--surface", "change-size"]);
  assert.equal(code, 2);
  assert.match(errors[0].reason, /name at least one concept/u);
});

test("a concept another standards file of the layer already cites is reported with that file and not added again", async () => {
  const cited = "# Testing\n\n- Example Small Steps (`example-small-steps`): https://example.com/small-steps\n";
  const home = tree({ ".claude/standards/README.md": INDEX, ".claude/standards/testing.md": cited });
  const mixed = await run(["example-small-steps", "example-review-gate", "--layer", "personal", "--surface", "change-size", "--yes"], { home });
  assert.equal(mixed.code, 0);
  assert.ok(mixed.out.includes(personal(home, "testing.md")), mixed.out);
  const entries = readFileSync(personal(home, "change-size.md"), "utf8").split("\n").filter((line) => line.startsWith("- "));
  assert.deepEqual(entries, ["- Example Review Gate (`example-review-gate`): https://example.com/review-gate"]);

  const only = tree({ ".claude/standards/README.md": INDEX, ".claude/standards/testing.md": cited });
  const none = await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home: only });
  assert.equal(none.code, 0);
  assert.match(none.out, /already adopted/u);
  assert.ok(none.out.includes(personal(only, "testing.md")), none.out);
  assert.equal(existsSync(personal(only, "change-size.md")), false);
  assert.equal(readFileSync(personal(only, "README.md"), "utf8"), INDEX);
});

test("a symbolic link planted where the old temporary file name went is not followed by the write", async () => {
  const home = personalHome();
  const target = join(tree({ "target.md": "untouched\n" }), "target.md");
  const planted = `${personal(home, "change-size.md")}.${process.pid}.tmp`;
  symlinkSync(target, planted);
  assert.equal((await run(["example-small-steps", "--layer", "personal", "--surface", "change-size", "--yes"], { home })).code, 0);
  assert.equal(readFileSync(target, "utf8"), "untouched\n");
  assert.ok(lstatSync(planted).isSymbolicLink(), "the planted link is left in place");
  assert.equal(lstatSync(personal(home, "change-size.md")).isFile(), true);
  assert.match(readFileSync(personal(home, "change-size.md"), "utf8"), /^- Example Small Steps/mu);
});

const asRoot = process.getuid?.() === 0 && "root ignores file permissions";
const modeOf = (path) => statSync(path).mode & 0o777;
const ADOPT = ["example-small-steps", "--layer", "personal", "--surface", "change-size"];

test("replacing the surface file and the index keeps each file's mode, and a new file gets the mode the umask gives", async () => {
  const home = tree({ ".claude/standards/README.md": INDEX, ".claude/standards/change-size.md": "# Mine\n" });
  chmodSync(personal(home, "README.md"), 0o640);
  chmodSync(personal(home, "change-size.md"), 0o600);
  assert.equal((await run([...ADOPT, "--yes"], { home })).code, 0);
  assert.equal(modeOf(personal(home, "README.md")), 0o640, "the index keeps 0640");
  assert.equal(modeOf(personal(home, "change-size.md")), 0o600, "the surface file keeps 0600");
  assert.match(readFileSync(personal(home, "change-size.md"), "utf8"), /^- Example Small Steps/mu);

  const fresh = personalHome();
  assert.equal((await run([...ADOPT, "--yes"], { home: fresh })).code, 0);
  assert.equal(modeOf(personal(fresh, "change-size.md")), 0o666 & ~process.umask(), "a new file gets 0666 less the umask");
});

test("a surface file or index the person cannot write is refused with a plain reason, and neither file is replaced", { skip: asRoot }, async () => {
  for (const name of ["change-size.md", "README.md"]) {
    const home = tree({ ".claude/standards/README.md": INDEX, ".claude/standards/change-size.md": "# Mine\n" });
    chmodSync(personal(home, name), 0o444);
    for (const extra of [[], ["--yes"]]) {
      const { code, errors } = await run([...ADOPT, ...extra], { home });
      assert.equal(code, 1, `${name} ${extra}`);
      assert.deepEqual(errors.map((e) => [e.event, e.path, e.code]), [["write refused", personal(home, name), "EACCES"]], name);
      assert.equal(errors[0].message, `${personal(home, name)} is not replaced: you have no write permission for it`, name);
    }
    assert.equal(modeOf(personal(home, name)), 0o444, `${name} keeps its mode`);
    assert.equal(readFileSync(personal(home, "change-size.md"), "utf8"), "# Mine\n", name);
    assert.equal(readFileSync(personal(home, "README.md"), "utf8"), INDEX, name);
  }
});

test("a surface file that already cites every concept named but has no index row gets the row, in the preview and the write", async () => {
  const cited = "# Mine\n\n- Example Small Steps (`example-small-steps`): https://example.com/small-steps\n";
  const home = tree({ ".claude/standards/README.md": INDEX, ".claude/standards/change-size.md": cited });
  const preview = await run(ADOPT, { home });
  assert.equal(preview.code, 3);
  assert.ok(preview.out.includes(`Would add this row to ${personal(home, "README.md")}:\n| change-size | change-size | change-size.md |`), preview.out);
  assert.doesNotMatch(preview.out, /Would (create|append|fill)/u);
  assert.equal((await run([...ADOPT, "--yes"], { home })).code, 0);
  assert.deepEqual(rowsFor(readFileSync(personal(home, "README.md"), "utf8"), "change-size.md"), ["| change-size | change-size | change-size.md |"]);
  assert.equal(readFileSync(personal(home, "change-size.md"), "utf8"), cited);
  const again = await run([...ADOPT, "--yes"], { home });
  assert.equal(again.code, 0);
  assert.match(again.out, /Nothing to write/u);
});

test("for the team layer a concept cited only in a personal *.local.md file is still adopted into the team file", async () => {
  const cited = "# Testing\n\n- Example Small Steps (`example-small-steps`): https://example.com/small-steps\n";
  const project = repo({ "docs/standards/README.md": INDEX, "docs/standards/testing.local.md": cited });
  const { code, out } = await run(["example-small-steps", "--layer", "team", "--surface", "change-size", "--yes"], { project });
  assert.equal(code, 0);
  assert.doesNotMatch(out, /already adopted/u);
  assert.match(readFileSync(join(project, "docs", "standards", "change-size.md"), "utf8"), /^- Example Small Steps \(`example-small-steps`\)/mu);

  const home = tree({ ".claude/standards/README.md": INDEX, ".claude/standards/testing.local.md": cited });
  const mine = await run([...ADOPT, "--yes"], { home });
  assert.equal(mine.code, 0);
  assert.ok(mine.out.includes(personal(home, "testing.local.md")), "every file of the personal layer is personal");
  assert.equal(existsSync(personal(home, "change-size.md")), false);
});

test("the already-adopted walk skips .git and node_modules", async () => {
  const cited = "- Example Small Steps (`example-small-steps`): https://example.com/small-steps\n";
  for (const folder of [".git", "node_modules"]) {
    const home = tree({ ".claude/standards/README.md": INDEX, [`.claude/standards/${folder}/notes.md`]: cited });
    const { code, out } = await run([...ADOPT, "--yes"], { home });
    assert.equal(code, 0, folder);
    assert.doesNotMatch(out, /already adopted/u, folder);
    assert.match(readFileSync(personal(home, "change-size.md"), "utf8"), /^- Example Small Steps/mu, folder);
  }
});

test("an index mixing CRLF and LF lines gets the row in its existing table, not a second table", async () => {
  const lines = INDEX.split("\n");
  const mixed = `${lines.slice(0, 3).join("\r\n")}\r\n${lines.slice(3).join("\n")}`;
  const home = tree({ ".claude/standards/README.md": mixed });
  assert.equal((await run([...ADOPT, "--yes"], { home })).code, 0);
  const written = readFileSync(personal(home, "README.md"), "utf8");
  assert.equal(written.match(/^\| Surface \|/gmu).length, 1, written);
  assert.ok(written.includes("| paved-path | adding a service endpoint, a schema migration, or a queue consumer | paved-paths.md |\n| change-size | change-size | change-size.md |"), written);
});

test("an unknown option or an option missing its value is named, with what is wrong in plain words", async () => {
  const cases = [
    [["--force"], "force", /--force is not an option/u],
    [["-x"], "x", /-x is not an option/u],
    [["--applies-when"], "applies-when", /--applies-when needs a value/u],
    [["--yes=no"], "yes", /--yes takes no value/u],
  ];
  for (const [extra, option, reason] of cases) {
    const { code, errors } = await run([...ADOPT, ...extra]);
    assert.equal(code, 2, extra.join(" "));
    assert.deepEqual(errors.map((e) => [e.event, e.option]), [["invalid option", option]], extra.join(" "));
    assert.match(errors[0].reason, reason);
  }
});

test("a --user-config holding JSON null, or anything but an object, is refused as not valid; the lookup reads null as no options", async () => {
  for (const text of ["null", "[]", "\"x\""]) {
    const userConfig = join(tree({ "user-config.json": text }), "user-config.json");
    const { code, errors } = await run([...ADOPT, "--user-config", userConfig]);
    assert.equal(code, 2, text);
    assert.deepEqual(errors.map((e) => [e.event, e.option]), [["invalid option", "user-config"]], text);
    assert.match(errors[0].reason, /^is not valid: /u, text);
  }
  const nullConfig = join(tree({ "user-config.json": "null" }), "user-config.json");
  const lookupCode = await lookup(["--data-dir", FIXTURES, "--home", tree(), "--project", repo(), "--user-config", nullConfig, "example-small-steps"], { out: () => {}, err: () => {} });
  assert.equal(lookupCode, 0);
});

test("a plugin settings file that exists but cannot be read stops adopt with 'could not be read' and the plain reason, not the system text", { skip: asRoot }, async () => {
  const project = repo({ [TEAM_SETTINGS]: "exclude: []\n" });
  chmodSync(join(project, TEAM_SETTINGS), 0o000);
  const { code, errors } = await run(ADOPT, { project });
  assert.equal(code, 1);
  assert.deepEqual(errors.map((e) => [e.event, e.layer]), [["settings file unreadable", "team"]]);
  assert.equal(errors[0].reason, `the repository's settings file, ${join(project, TEAM_SETTINGS)}, could not be read, so nothing is adopted until it is fixed: permission denied`);
});

test("a layer file that cannot be read is refused with exit 1 and a plain reason naming it", { skip: asRoot }, async () => {
  const unreadable = (home, name) => {
    chmodSync(personal(home, name), 0o000);
    return personal(home, name);
  };
  const cases = [
    (home) => unreadable(home, "README.md"),
    (home) => unreadable(home, "change-size.md"),
    (home) => {
      writeFileSync(personal(home, "testing.md"), "# Testing\n");
      return unreadable(home, "testing.md");
    },
  ];
  for (const make of cases) {
    const home = tree({ ".claude/standards/README.md": INDEX, ".claude/standards/change-size.md": "# Mine\n" });
    const path = make(home);
    const { code, errors } = await run([...ADOPT, "--yes"], { home });
    assert.equal(code, 1, path);
    assert.deepEqual(errors.map((e) => [e.event, e.path, e.code]), [["file unreadable", path, "EACCES"]], path);
    assert.equal(errors[0].reason, `${path} could not be read: permission denied`);
  }
});

test("a folder named like the surface file or the index is refused with exit 1 and a plain reason", async () => {
  for (const name of ["change-size.md", "README.md"]) {
    const home = tree({ ".claude/standards/README.md": INDEX });
    rmSync(personal(home, name), { force: true });
    mkdirSync(personal(home, name));
    const { code, errors } = await run([...ADOPT, "--yes"], { home });
    assert.equal(code, 1, name);
    assert.deepEqual(errors.map((e) => [e.event, e.path, e.code]), [["file unreadable", personal(home, name), "EISDIR"]], name);
    assert.equal(errors[0].reason, `${personal(home, name)} could not be read: it is a folder, not a file`);
  }
});

/** A folder on a read-only mount, or null when the machine has none this user can reach. */
function readOnlyFolder() {
  let info;
  try {
    info = readFileSync("/proc/self/mountinfo", "utf8");
  } catch {
    return null;
  }
  for (const line of info.split("\n")) {
    const [, , , , target, options] = line.split(" ");
    if (!options?.split(",").includes("ro")) continue;
    try {
      if (statSync(target).isDirectory() && !existsSync(join(target, ".claude"))) {
        readdirSync(target);
        return target;
      }
    } catch {}
  }
  return null;
}

test("a write on a read-only file system says the file system is read-only", { skip: !readOnlyFolder() && "no read-only mount on this machine" }, async () => {
  const home = readOnlyFolder();
  const { code, errors } = await run([...ADOPT, "--yes"], { home });
  assert.equal(code, 1);
  const target = personal(home, "change-size.md");
  assert.deepEqual(errors.map((e) => [e.event, e.path, e.code]), [["write refused", target, "EROFS"]]);
  assert.equal(errors[0].message, `${target} could not be written: the file system is read-only`);
});
