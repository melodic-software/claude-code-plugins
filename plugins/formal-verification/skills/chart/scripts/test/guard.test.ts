import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import {
  capLine,
  colonsBeforeHash,
  escapeMarkdown,
  fence,
  moduleName,
  referencedModules,
  usesGeneratedName,
} from "../guard.ts";
import { checkSpecName, childEnv, freshOut, stageSpec } from "../stage.ts";

const ALLOWED = ["Naturals", "Integers", "Reals", "Sequences", "FiniteSets", "Bags", "TLC", "TLCExt"];

const folder = (t: { after: (fn: () => void) => void }, files: { [name: string]: string }) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "statechart-guard-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  for (const [name, text] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(dir, name)), { recursive: true });
    fs.writeFileSync(path.join(dir, name), text);
  }
  return dir;
};

const spec = (name: string, body: string) => `---- MODULE ${name} ----\n${body}\n====\n`;

test("fence is one backtick longer than the longest run in the text, and never under three", () => {
  assert.equal(fence("plain"), "```\nplain\n```");
  assert.equal(fence("a ``` b"), "````\na ``` b\n````");
  assert.equal(fence("x `````` y"), "```````\nx `````` y\n```````");
});

test("escapeMarkdown escapes Markdown and HTML", () => {
  assert.equal(escapeMarkdown("<img src=x>"), "&lt;img src=x&gt;");
  assert.equal(escapeMarkdown("[a](b) *c* `d`"), "\\[a\\]\\(b\\) \\*c\\* \\`d\\`");
  assert.equal(escapeMarkdown("a & b"), "a &amp; b");
  assert.equal(escapeMarkdown("go\r\n---"), "go ---");
});

test("capLine keeps a short line and cuts a long one with a count", () => {
  assert.equal(capLine("abc", 5), "abc");
  assert.equal(capLine("abcdefgh", 5), "abcde… (3 more characters)");
});

test("colonsBeforeHash finds a colon followed by a # before the next space", () => {
  assert.deepEqual(colonsBeforeHash("a:b#c"), [1]);
  assert.deepEqual(colonsBeforeHash("a: b#c"), []);
  assert.deepEqual(colonsBeforeHash("x::#"), [1, 2]);
  assert.deepEqual(colonsBeforeHash("no colon #"), []);
});

test("colonsBeforeHash takes linear time on a long run of colons", () => {
  const s = `${":".repeat(200_000)}#`;
  const start = performance.now();
  assert.equal(colonsBeforeHash(s).length, 200_000);
  assert.ok(performance.now() - start < 2000);
});

test("referencedModules reads EXTENDS and INSTANCE and skips comments", () => {
  const text = spec(
    "M",
    "EXTENDS Naturals, Sequences\n\\* EXTENDS Json\n(* INSTANCE IOUtils *)\nJ == INSTANCE Json\nLOCAL INSTANCE TLC",
  );
  assert.deepEqual(referencedModules(text).sort(), ["Json", "Naturals", "Sequences", "TLC"]);
  assert.equal(moduleName(text), "M");
});

test("referencedModules reads past a comment mark inside a string", () => {
  const text = spec(
    "M",
    'EXTENDS Naturals\nOpen == "(*"\nJ == INSTANCE Json\nClose == "*)"\nS == "\\\\*" K == INSTANCE IOUtils\nQ == "a\\"(*"',
  );
  assert.deepEqual(referencedModules(text).sort(), ["IOUtils", "Json", "Naturals"]);
  assert.equal(usesGeneratedName(spec("M", 'S == "\\\\*" ChartMark == TRUE')), "ChartMark");
  assert.equal(moduleName(`X == "(*"\n${spec("M", 'Y == "*)"')}`), "M");
});

test("usesGeneratedName finds a generated name only outside comments", () => {
  assert.equal(usesGeneratedName(spec("M", "ChartMark == TRUE")), "ChartMark");
  assert.equal(usesGeneratedName(spec("M", "\\* ChartMark is ours")), undefined);
});

test("checkSpecName wants a name ending in lower-case .tla", () => {
  checkSpecName("dir/Spec.tla");
  assert.throws(() => checkSpecName("Spec.TLA"), /ends in \.tla/);
  assert.throws(() => checkSpecName("Spec"), /ends in \.tla/);
});

test("stageSpec copies only the regular .tla files of the spec folder", (t) => {
  const dir = folder(t, {
    "Spec.tla": spec("Spec", "EXTENDS Naturals, Lib\nVARIABLE x"),
    "Lib.tla": spec("Lib", "EXTENDS Sequences"),
    "Spec.cfg": "INIT Init",
    "notes.txt": "x",
    "sub/Other.tla": spec("Other", ""),
  });
  fs.symlinkSync(path.join(dir, "Lib.tla"), path.join(dir, "Linked.tla"));
  const into = path.join(dir, "..", `${path.basename(dir)}-staged`);
  t.after(() => fs.rmSync(into, { recursive: true, force: true }));
  const staged = stageSpec(path.join(dir, "Spec.tla"), into, ALLOWED);
  assert.equal(staged, path.join(into, "Spec.tla"));
  assert.deepEqual(fs.readdirSync(into).sort(), ["Lib.tla", "Spec.tla"]);
});

for (const [what, files, message] of [
  ["a .class file", { "Spec.tla": spec("Spec", ""), "Spec.class": "" }, /Java code beside the spec/],
  ["a .jar in a subfolder", { "Spec.tla": spec("Spec", ""), "lib/x.jar": "" }, /Java code beside the spec/],
  ["a module that shadows TLC", { "Spec.tla": spec("Spec", ""), "TLC.tla": spec("TLC", "") }, /shadows a standard or generated module/],
  ["a module named _Hidden", { "Spec.tla": spec("Spec", ""), "_Hidden.tla": spec("_Hidden", "") }, /shadows/],
  ["a module named ChartRun", { "Spec.tla": spec("Spec", ""), "ChartRun.tla": spec("ChartRun", "") }, /shadows/],
  ["a generated operator name", { "Spec.tla": spec("Spec", "ChartBudget == 1") }, /uses the name ChartBudget/],
  ["a Json EXTENDS", { "Spec.tla": spec("Spec", "EXTENDS Json") }, /uses Json, which is not in the allowed modules.*read and write files/],
  ["an IOUtils INSTANCE", { "Spec.tla": spec("Spec", "I == INSTANCE IOUtils") }, /uses IOUtils/],
] as [string, { [name: string]: string }, RegExp][]) {
  test(`stageSpec refuses a spec folder with ${what}`, (t) => {
    const dir = folder(t, files);
    const into = path.join(dir, "..", `${path.basename(dir)}-staged`);
    t.after(() => fs.rmSync(into, { recursive: true, force: true }));
    assert.throws(() => stageSpec(path.join(dir, "Spec.tla"), into, ALLOWED), message);
  });
}

test("stageSpec refuses a spec that is a symbolic link", (t) => {
  const dir = folder(t, { "Real.tla": spec("Real", "") });
  fs.symlinkSync(path.join(dir, "Real.tla"), path.join(dir, "Spec.tla"));
  const into = path.join(dir, "..", `${path.basename(dir)}-staged`);
  t.after(() => fs.rmSync(into, { recursive: true, force: true }));
  assert.throws(() => stageSpec(path.join(dir, "Spec.tla"), into, ALLOWED), /not a regular file/);
});

test("childEnv keeps only PATH, LANG, LC_ALL and a fresh HOME and TMPDIR", () => {
  const saved = { ...process.env };
  try {
    process.env.GH_TOKEN = "secret";
    process.env.JAVA_TOOL_OPTIONS = "-javaagent:x";
    process.env._JAVA_OPTIONS = "-Dx";
    process.env.JDK_JAVA_OPTIONS = "-Dy";
    process.env.PATH = "/usr/bin";
    const env = childEnv("/tmp/home", { LC_ALL: "C.UTF-8" });
    assert.equal(env.HOME, "/tmp/home");
    assert.equal(env.TMPDIR, "/tmp/home");
    assert.equal(env.PATH, "/usr/bin");
    assert.equal(env.LC_ALL, "C.UTF-8");
    for (const name of ["GH_TOKEN", "JAVA_TOOL_OPTIONS", "_JAVA_OPTIONS", "JDK_JAVA_OPTIONS"])
      assert.equal(env[name], undefined, name);
  } finally {
    for (const name of Object.keys(process.env)) if (!(name in saved)) delete process.env[name];
    Object.assign(process.env, saved);
  }
});

test("freshOut refuses a symbolic link, a live one or a broken one", (t) => {
  const dir = folder(t, {});
  fs.mkdirSync(path.join(dir, "real"));
  fs.symlinkSync(path.join(dir, "real"), path.join(dir, "live"));
  fs.symlinkSync(path.join(dir, "gone"), path.join(dir, "broken"));
  assert.throws(() => freshOut(path.join(dir, "live")), /It is a symbolic link/);
  assert.throws(() => freshOut(path.join(dir, "broken")), /It is a broken link/);
  assert.equal(freshOut(path.join(dir, "real")), path.join(dir, "real"));
  assert.equal(freshOut(path.join(dir, "new")), path.join(dir, "new"));
});
