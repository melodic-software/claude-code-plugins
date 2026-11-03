import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { gzipSync } from "node:zlib";

const HERE = import.meta.dirname;
const SCRIPT = path.join(HERE, "scan-upload.mjs");
// Built at run time, so no tracked file holds a credential shape: a GitHub
// token prefix and 36 letters spelling FAKE, never a live token.
const PLANTED = ["gh", "p_", "FAKE".repeat(9)].join("");

function workDir(t) {
  const dir = mkdtempSync(path.join(tmpdir(), "scan-upload-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function run(dir, paths) {
  const output = path.join(dir, "github-output");
  const summary = path.join(dir, "step-summary");
  writeFileSync(output, "");
  writeFileSync(summary, "");
  const result = spawnSync(process.execPath, [SCRIPT], {
    env: { PATH: process.env.PATH, SCAN_PATHS: paths, GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: summary },
    encoding: "utf8",
  });
  return { ...result, outputs: readFileSync(output, "utf8"), summary: readFileSync(summary, "utf8") };
}

// No character of the token reaches the summary: not its fixed `ghp_` prefix, nor any after it.
function noneOfTheMatch(summary) {
  assert.ok(!summary.includes("ghp_") && !summary.includes("FAKE"), "no character of the match");
}

function withheld(result, label) {
  assert.equal(result.status, 1, result.stdout + result.stderr);
  assert.equal(result.outputs, "", "a withheld upload sets no clean output");
  assert.match(result.stdout, new RegExp(`::error::scan-upload: ${label}`));
  assert.ok(!result.stdout.includes(PLANTED) && !result.stderr.includes(PLANTED), "the matched value is never printed");
}

test("clean files pass and set clean=true", (t) => {
  const dir = workDir(t);
  mkdirSync(path.join(dir, "out", "nested"), { recursive: true });
  writeFileSync(path.join(dir, "out", "reply.txt"), "a clean reply\n");
  writeFileSync(path.join(dir, "out", "nested", "verdict.json"), '{"verdict":"merge"}\n');
  const result = run(dir, `${path.join(dir, "out")}\n${path.join(dir, "absent.json")}\n`);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.equal(result.outputs, "clean=true\n");
  assert.match(result.stdout, /2 file\(s\) clean/);
  assert.equal(result.summary, "", "a clean scan writes no summary");
});

test("a planted credential withholds the upload and asks for rotation, never printing the value", (t) => {
  const dir = workDir(t);
  mkdirSync(path.join(dir, "out"));
  writeFileSync(path.join(dir, "out", "clean.txt"), "nothing here\n");
  writeFileSync(path.join(dir, "out", "handoff.json"), `{"review":"token ${PLANTED} in the text"}\n`);
  const result = run(dir, path.join(dir, "out"));
  withheld(result, "GitHub token; nothing is uploaded");
  assert.match(result.stdout, /Rotate this credential/);
});

test("a block writes only the hit's rule, path and line to the summary, no character of the match", (t) => {
  const dir = workDir(t);
  mkdirSync(path.join(dir, "out", "nested"), { recursive: true });
  writeFileSync(path.join(dir, "out", "nested", "handoff.json"), `{\n  "review": "token ${PLANTED} in the text"\n}\n`);
  const result = run(dir, path.join(dir, "out"));
  withheld(result, "GitHub token");
  assert.equal(result.summary, "### scan-upload withheld the upload\n\n- rule `GitHub token`, path `nested/handoff.json`, line 2\n\n");
  noneOfTheMatch(result.summary);
});

test("a path's backtick and markup are escaped, so it cannot leave its code span", (t) => {
  const dir = workDir(t);
  writeFileSync(path.join(dir, "a`<b>.json"), `${PLANTED}\n`);
  const result = run(dir, path.join(dir, "a`<b>.json"));
  withheld(result, "GitHub token");
  assert.match(result.summary, /path `a\\u0060\\u003cb\\u003e\.json`, line 1\n/);
});

test("a path's bidi, line-separator, C1 and zero-width characters are escaped, so it cannot reorder or split the line", (t) => {
  const dir = workDir(t);
  const name = "a\u202Egnp.json";
  writeFileSync(path.join(dir, name), `${PLANTED}\n`);
  const result = run(dir, path.join(dir, name));
  withheld(result, "GitHub token");
  assert.equal(result.summary, "### scan-upload withheld the upload\n\n- rule `GitHub token`, path `a\\u202egnp.json`, line 1\n\n");
  assert.ok(!result.summary.includes("\u202E"), "no raw right-to-left override");
  writeFileSync(path.join(dir, "b\u2028\u0085\u200Bc.json"), `${PLANTED}\n`);
  const split = run(dir, path.join(dir, "b\u2028\u0085\u200Bc.json"));
  withheld(split, "GitHub token");
  assert.match(split.summary, /path `b\\u2028\\u0085\\u200bc\.json`, line 1\n/);
  assert.doesNotMatch(split.summary, /[^\x20-\x7e\n]/, "only printable ASCII and line breaks");
});

test("a zero-width match writes the rule, path and line and none of the line", (t) => {
  const dir = workDir(t);
  // A 32-hex and a 64-hex word on one line: the R2 key pair rule, whose match is the empty lookahead.
  const short = "a".repeat(32);
  writeFileSync(path.join(dir, "digests.txt"), `first line\n${short} ${"b".repeat(64)}\n`);
  const result = run(dir, path.join(dir, "digests.txt"));
  withheld(result, "R2 key pair");
  assert.equal(result.summary, "### scan-upload withheld the upload\n\n- rule `R2 key pair`, path `digests.txt`, line 2\n\n");
  assert.ok(!result.summary.includes("aaaaaa") && !result.summary.includes("bbbbbb"), "no character of the match");
});

test("a hit found only after escaped breaks decode names the file's own line", (t) => {
  const dir = workDir(t);
  // One physical line: the token follows a `\n` escape, so only the decoded view separates it.
  writeFileSync(path.join(dir, "work-outcome.json"), `{"a": 1}\n${JSON.stringify({ summary: `first\nsecond\n${PLANTED}` })}\n`);
  const result = run(dir, path.join(dir, "work-outcome.json"));
  withheld(result, "GitHub token");
  assert.equal(result.summary, "### scan-upload withheld the upload\n\n- rule `GitHub token`, path `work-outcome.json`, line 2\n\n");
});

test("a base64-wrapped credential withholds the upload, and neither form reaches the output", (t) => {
  const dir = workDir(t);
  const wrapped = Buffer.from(`Authorization: token ${PLANTED}`).toString("base64");
  writeFileSync(path.join(dir, "eval.json"), `{"a": 1}\n{"header": "${wrapped}"}\n`);
  const result = run(dir, path.join(dir, "eval.json"));
  withheld(result, "GitHub token");
  assert.equal(result.summary, "### scan-upload withheld the upload\n\n- rule `GitHub token`, path `eval.json`, line 2\n\n");
  assert.ok(!`${result.stdout}${result.stderr}${result.summary}`.includes(wrapped.slice(0, 12)), "the encoded value is never printed");
});

test("a credential in a file name withholds the upload and the summary never shows the name", (t) => {
  const dir = workDir(t);
  mkdirSync(path.join(dir, "out"));
  writeFileSync(path.join(dir, "out", `${PLANTED}.txt`), "clean bytes\n");
  const result = run(dir, path.join(dir, "out"));
  withheld(result, "GitHub token");
  assert.equal(result.summary, "### scan-upload withheld the upload\n\n- rule `GitHub token`, path `a file name`, line 1\n\n");
  noneOfTheMatch(result.summary);
});

test("a link, a compressed file and a glob each withhold the upload", (t) => {
  const dir = workDir(t);
  writeFileSync(path.join(dir, "target.txt"), "clean\n");
  symlinkSync(path.join(dir, "target.txt"), path.join(dir, "link.txt"));
  withheld(run(dir, path.join(dir, "link.txt")), "a link");
  writeFileSync(path.join(dir, "trace.gz"), gzipSync(Buffer.from(PLANTED)));
  withheld(run(dir, path.join(dir, "trace.gz")), "a compressed file");
  withheld(run(dir, path.join(dir, "*.txt")), "a glob or exclude pattern");
  withheld(run(dir, `!${path.join(dir, "target.txt")}`), "a glob or exclude pattern");
});

test("the broad assignment label only warns", (t) => {
  const dir = workDir(t);
  // Joined at run time, so no tracked line reads as a password assignment.
  writeFileSync(path.join(dir, "fixture.txt"), `${["pass", "word"].join("")} = "not-a-real-one"\n`);
  const result = run(dir, path.join(dir, "fixture.txt"));
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.equal(result.outputs, "clean=true\n");
  assert.match(result.stdout, /::warning::scan-upload: password or secret assignment/);
  assert.equal(result.summary, "", "a warning is no block and writes no summary");
});

test("the lane transcript is scanned as plaintext before it is sealed", () => {
  const action = readFileSync(path.join(HERE, "..", "upload-lane-transcript", "action.yml"), "utf8");
  const scan = action.indexOf("id: scan\n");
  const seal = action.indexOf("id: seal\n");
  assert.ok(scan > 0 && scan < seal, "the scan step comes before the seal step");
  assert.match(action, /SCAN_PATHS: \$\{\{ inputs\.execution-file \}\}\n\s+run: node "\$GITHUB_ACTION_PATH\/\.\.\/scan-upload\/scan-upload\.mjs"/);
  assert.match(action, /id: seal\n\s+if: steps\.scan\.outputs\.clean == 'true'\n/);
});
