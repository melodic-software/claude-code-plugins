#!/usr/bin/env node
// Build the plan or brainstorm view: a checked-in template plus the JSON data
// object on stdin, through the shared view builder (interactive profile).
// Writes the page to one deterministic path under the OS temp directory,
// never beside the record, and prints that path.
//
//   node build-view.mjs plan|brainstorm < data.json
//   node build-view.mjs plan|brainstorm --connect http://127.0.0.1:<port> --out <data_dir>/page.html < data.json
//     the Claude-interactive page that view-bridge (../view-bridge/) serves; <data_dir> must be
//     a private view-bridge data dir outside any working tree, or the build is refused (exit 2)
//
// Exit 0 built, 1 the data or the page fails its checks, 2 usage or environment.

import { chmodSync, existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { buildView, ViewBuildError } from "../lib/view-builder.mjs";

const TEMPLATES = {
  plan: "../skills/plan/templates/plan-view.html",
  brainstorm: "../skills/brainstorm/templates/brainstorm-view.html",
};

// Data shapes from reference/rendered-view.md: top-level text fields, then one
// list of rows whose fields are text, plus `criteria` (a list of text) for plan.
const SHAPES = {
  plan: {
    text: ["title", "goal", "blast"],
    list: "phases",
    row: ["status", "name", "what", "needs"],
    rowList: "criteria",
  },
  brainstorm: {
    text: ["title", "problem"],
    list: "candidates",
    row: ["effort", "name", "what", "where", "impact"],
  },
};

const isText = (value) => typeof value === "string";
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

const shapeFailures = (shape, data) => {
  if (!isObject(data)) return ["data is not an object"];
  const failures = shape.text.filter((key) => !isText(data[key])).map((key) => `${key} must be text`);
  if (!Array.isArray(data[shape.list])) return [...failures, `${shape.list} must be a list`];
  for (const [index, row] of data[shape.list].entries()) {
    const at = `${shape.list}[${index}]`;
    if (!isObject(row)) {
      failures.push(`${at} must be an object`);
      continue;
    }
    for (const key of shape.row) if (!isText(row[key])) failures.push(`${at}.${key} must be text`);
    if (shape.rowList && !(Array.isArray(row[shape.rowList]) && row[shape.rowList].every(isText))) {
      failures.push(`${at}.${shape.rowList} must be a list of text`);
    }
  }
  return failures;
};

const insideWorkingTree = (dir) => {
  for (let at = dir; ; at = dirname(at)) {
    if (existsSync(join(at, ".git"))) return at;
    if (dirname(at) === at) return null;
  }
};

/** Why out cannot take a connected page for origin, or null: it must be page.html in a private view-bridge data dir. */
const bridgeOutProblem = (out, origin) => {
  const dir = dirname(resolve(out));
  if (basename(out) !== "page.html") return `${out} must be named page.html`;
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
  if (realpathSync(dir) !== dir) return `${dir} is not a plain directory path (a link is in it)`;
  const root = insideWorkingTree(dir);
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
};

const [kind, ...rest] = process.argv.slice(2);
const flags = {};
for (let i = 0; i < rest.length; i += 2) flags[rest[i]] = rest[i + 1];
const flagsOk =
  Object.keys(flags).every((key) => ["--connect", "--out"].includes(key)) &&
  ("--connect" in flags) === ("--out" in flags) &&
  Object.values(flags).every((value) => typeof value === "string" && value !== "");
if (!Object.hasOwn(TEMPLATES, kind) || !flagsOk) {
  console.error("usage: build-view.mjs plan|brainstorm [--connect <session-bridge origin> --out <data_dir>/page.html] < data.json");
  process.exit(2);
}

if (flags["--out"]) {
  const problem = bridgeOutProblem(flags["--out"], flags["--connect"]);
  if (problem) {
    console.error(`build-view: refused: ${problem}`);
    process.exit(2);
  }
}

try {
  const data = JSON.parse(readFileSync(0, "utf8"));
  const failures = shapeFailures(SHAPES[kind], data);
  if (failures.length > 0) throw new ViewBuildError(failures);
  const page = buildView({
    profile: "interactive",
    template: readFileSync(fileURLToPath(new URL(TEMPLATES[kind], import.meta.url)), "utf8"),
    data,
    connect: flags["--connect"] ?? null,
  });
  if (flags["--out"]) {
    // Replace a planted link or file rather than write through it.
    if (existsSync(flags["--out"]) && lstatSync(flags["--out"]).isDirectory()) {
      throw new Error(`build-view: refused: ${flags["--out"]} is a directory`);
    }
    rmSync(flags["--out"], { force: true });
    writeFileSync(flags["--out"], page, { flag: "wx", mode: 0o600 });
    console.log(flags["--out"]);
    process.exit(0);
  }
  // The temp root is shared: keep the directory private and never write through a link.
  const dir = join(tmpdir(), "planning-views");
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  if (!lstatSync(dir).isDirectory())
    throw new Error("build-view: refusing a symlinked or non-directory output path");
  chmodSync(dir, 0o700);
  const out = join(dir, `${kind}.html`);
  rmSync(out, { force: true });
  writeFileSync(out, page, { mode: 0o600 });
  console.log(out);
} catch (err) {
  console.error(err instanceof SyntaxError ? "build-view: stdin is not JSON" : err.message);
  process.exit(err instanceof ViewBuildError ? 1 : 2);
}
