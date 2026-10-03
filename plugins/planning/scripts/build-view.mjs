#!/usr/bin/env node
// Build the plan or brainstorm view: a checked-in template plus the JSON data
// object on stdin, through the shared view builder (interactive profile).
// Writes the page to one deterministic path under the OS temp directory,
// never beside the record, and prints that path.
//
//   node build-view.mjs plan|brainstorm < data.json
//
// Exit 0 built, 1 the page fails its profile, 2 usage or environment.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { ViewBuildError, buildView } from "../lib/view-builder.mjs";

const TEMPLATES = {
  plan: "../skills/plan/templates/plan-view.html",
  brainstorm: "../skills/brainstorm/templates/brainstorm-view.html",
};

const kind = process.argv[2];
if (!Object.hasOwn(TEMPLATES, kind)) {
  console.error("usage: build-view.mjs plan|brainstorm < data.json");
  process.exit(2);
}

try {
  const page = buildView({
    profile: "interactive",
    template: readFileSync(fileURLToPath(new URL(TEMPLATES[kind], import.meta.url)), "utf8"),
    data: JSON.parse(readFileSync(0, "utf8")),
  });
  const dir = join(tmpdir(), "planning-views");
  mkdirSync(dir, { recursive: true });
  const out = join(dir, `${kind}.html`);
  writeFileSync(out, page);
  console.log(out);
} catch (err) {
  console.error(err instanceof SyntaxError ? "build-view: stdin is not JSON" : err.message);
  process.exit(err instanceof ViewBuildError ? 1 : 2);
}
