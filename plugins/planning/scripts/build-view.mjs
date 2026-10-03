#!/usr/bin/env node
// Build the plan or brainstorm view: a checked-in template plus the JSON data
// object on stdin, through the shared view builder (interactive profile).
// Writes the page to one deterministic path under the OS temp directory,
// never beside the record, and prints that path.
//
//   node build-view.mjs plan|brainstorm < data.json
//
// Exit 0 built, 1 the data or the page fails its checks, 2 usage or environment.

import { chmodSync, lstatSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
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

const kind = process.argv[2];
if (!Object.hasOwn(TEMPLATES, kind)) {
  console.error("usage: build-view.mjs plan|brainstorm < data.json");
  process.exit(2);
}

try {
  const data = JSON.parse(readFileSync(0, "utf8"));
  const failures = shapeFailures(SHAPES[kind], data);
  if (failures.length > 0) throw new ViewBuildError(failures);
  const page = buildView({
    profile: "interactive",
    template: readFileSync(fileURLToPath(new URL(TEMPLATES[kind], import.meta.url)), "utf8"),
    data,
  });
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
