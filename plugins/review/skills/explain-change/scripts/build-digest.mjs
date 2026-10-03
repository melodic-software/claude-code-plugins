#!/usr/bin/env node
// Build the change digest page: the checked-in template plus the digest data as
// a JSON data block, through the shared view-builder's interactive profile.
// The data is K2 (it describes a pull request), so nothing here writes a data
// value into markup; view-builder puts it in the data block and the inlined
// runtime renders it as text.
//
//   build-digest.mjs < data.json      write the page into a fresh temp dir, print its path
//   build-digest.mjs --connect http://127.0.0.1:<port> --dir <data_dir> < data.json
//                                     write the Claude-interactive page to <data_dir>/page.html,
//                                     the view-bridge data dir that serves that origin
//   build-digest.mjs --check <file>   validate a page
// The caller never picks the output path, so a diff-steered caller cannot aim
// the page at a rules, shell, or settings file: --dir takes only a private
// view-bridge data dir outside any working tree, and the file name is fixed.
// Exit 0 ok, 1 the page fails its profile, 2 usage, input, or output path.

import { existsSync, lstatSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve, isAbsolute } from "node:path";
import { fileURLToPath } from "node:url";

import { buildView, validateView } from "../../../lib/view-builder.mjs";

const selfDir = dirname(fileURLToPath(import.meta.url));
export const TEMPLATE_PATH = join(selfDir, "../templates/digest.html");

const text = (value) =>
  typeof value === "string" ? value : typeof value === "number" ? String(value) : "";
const list = (value) => (Array.isArray(value) ? value.filter((row) => row && typeof row === "object") : []);
const texts = (value) => (Array.isArray(value) ? value : []).map(text).filter((item) => item !== "");

/** What the fresh-context check said about a risk row. Anything else reads as unchecked. */
export const CHECKS = Object.freeze(["agreed", "disputed", "added", "unchecked"]);

/**
 * Keep only the fields the template binds, each as a string. Anything else in
 * the input never reaches the page. The quiz and the recording become lists of
 * zero or one section, so the page omits a section the input does not carry.
 */
export function shapeDigest(input) {
  const src = input && typeof input === "object" ? input : {};
  const questions = list(src.quiz)
    .map((q) => ({ question: text(q.question), choices: texts(q.choices), answer: text(q.answer) }))
    .filter((q) => q.question !== "");
  const recording = src.recording && typeof src.recording === "object" ? src.recording : {};
  // Repo-relative only: an absolute or home path would show the reader's username.
  const recordingPath = /^(?:[/\\~]|[A-Za-z]:)/.test(text(recording.path)) ? "" : text(recording.path);
  return {
    title: text(src.title) || "Change digest",
    change: text(src.change),
    why: text(src.why),
    before: text(src.before),
    after: text(src.after),
    risks: list(src.risks).map((r) => ({
      area: text(r.area),
      level: text(r.level),
      why: text(r.why),
      check: CHECKS.includes(r.check) ? r.check : "unchecked",
      checker: text(r.checker),
    })),
    focus: texts(src.focus),
    recording: recordingPath ? [{ path: recordingPath, head: text(recording.head) }] : [],
    files: list(src.files).map((f) => ({
      path: text(f.path),
      status: text(f.status),
      note: text(f.note),
      hunks: list(f.hunks).map((h) => ({ at: text(h.at), code: text(h.code), note: text(h.note) })),
    })),
    quiz: questions.length ? [{ questions }] : [],
  };
}

export function buildDigest(input, connect = null) {
  return buildView({
    profile: "interactive",
    template: readFileSync(TEMPLATE_PATH, "utf8"),
    data: shapeDigest(input),
    connect,
  });
}

/**
 * Why dir cannot take a connected page for origin, or null when it can: it must be
 * a plain directory owned by this user with mode 0700, outside any working tree,
 * holding the session file view-bridge ensure-running wrote for that origin's port.
 */
export function bridgeDirProblem(dir, origin) {
  let st;
  try {
    st = lstatSync(dir);
  } catch {
    return `${dir} does not exist`;
  }
  if (!st.isDirectory()) return `${dir} is not a plain directory`;
  if (process.platform !== "win32" && (st.uid !== process.getuid() || st.mode & 0o077)) {
    return `${dir} must be owned by you with mode 0700`;
  }
  const root = repoRoot(realpathSync(dir));
  if (root) return `${dir} is inside the working tree ${root}`;
  let session;
  try {
    session = JSON.parse(readFileSync(join(dir, ".view-session.json"), "utf8"));
  } catch {
    return `${dir} holds no view-bridge session; run view-bridge.sh ensure-running first`;
  }
  const port = /^http:\/\/127\.0\.0\.1:([0-9]{1,5})$/.exec(origin)?.[1];
  if (!port || Number(port) !== session?.port) return `${origin} is not the origin this data dir serves`;
  return null;
}

/** The working tree holding dir, found by walking up to a .git entry. */
export function repoRoot(dir) {
  let at = resolve(dir);
  for (;;) {
    if (existsSync(join(at, ".git"))) return at;
    const up = dirname(at);
    if (up === at) return null;
    at = up;
  }
}

const inside = (child, parent) => {
  const rel = relative(parent, child);
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
};

function fail(message, code) {
  process.stderr.write(`build-digest: ${message}\n`);
  process.exit(code);
}

function main(args) {
  if (args[0] === "--check") {
    if (!args[1]) fail("usage: build-digest.mjs --check <file>", 2);
    let html;
    try {
      html = readFileSync(args[1], "utf8");
    } catch (error) {
      fail(error.message, 2);
    }
    const verdict = validateView(html);
    if (!verdict.ok) fail(verdict.failures.join(","), 1);
    process.stdout.write("ok\n");
    return;
  }
  const usage = "usage: build-digest.mjs [--connect <origin> --dir <view-bridge data dir>] < data.json | --check <file>";
  const flags = {};
  for (let i = 0; i < args.length; i += 2) flags[args[i]] = args[i + 1];
  const connected = args.length === 4 && typeof flags["--connect"] === "string" && typeof flags["--dir"] === "string";
  if (args.length > 0 && !connected) fail(usage, 2);
  if (connected) {
    const problem = bridgeDirProblem(flags["--dir"], flags["--connect"]);
    if (problem) fail(`refused: ${problem}`, 2);
  }
  // A view never sits beside the record: refuse a temp dir inside a working tree.
  const temp = realpathSync(tmpdir());
  const root = repoRoot(temp);
  if (!connected && root && inside(temp, realpathSync(root))) {
    fail(`refused: the temp dir ${temp} is inside the working tree ${root}; write the view outside it`, 2);
  }
  let input;
  try {
    input = JSON.parse(readFileSync(0, "utf8"));
  } catch (error) {
    fail(`invalid JSON (${error.message})`, 2);
  }
  if (!input || typeof input !== "object" || Array.isArray(input)) fail("JSON root must be an object", 2);
  let page;
  try {
    page = buildDigest(input, connected ? flags["--connect"] : null);
  } catch (error) {
    fail(error.message, 1);
  }
  if (connected) {
    // Never write through a link a K2-steered run might have planted.
    const out = join(realpathSync(flags["--dir"]), "page.html");
    rmSync(out, { force: true });
    writeFileSync(out, page, { flag: "wx", mode: 0o600 });
    process.stdout.write(`${out}\n`);
    return;
  }
  const out = join(mkdtempSync(join(temp, "explain-change-")), "digest.html");
  writeFileSync(out, page, { flag: "wx" });
  process.stdout.write(`${out}\n`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2));
}
