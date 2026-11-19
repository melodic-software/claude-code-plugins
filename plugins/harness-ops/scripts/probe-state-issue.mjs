#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { resolve } from "../lib/config-cascade.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const KEY = "probe_state_issue";

let opts;
try {
  ({ values: opts } = parseArgs({ options: { project: { type: "string" }, "user-value": { type: "string" } } }));
} catch {
  process.stderr.write("usage: probe-state-issue.mjs [--project DIR] [--user-value VALUE]\n  prints {probe_state_issue, layer, errors}: the option, then <home>/harness-ops.yaml, then harness-ops.local.yaml\n");
  process.exit(2);
}

const run = (cmd, args) => spawnSync(cmd, args, { cwd: ROOT, encoding: "utf8", timeout: 15_000 });
const start = resolvePath(opts.project ?? process.cwd());
const top = run("git", ["-C", start, "rev-parse", "--show-toplevel"]);
const project = top.status === 0 ? top.stdout.trim() : start;
const pointer = run("bash", [join(ROOT, "lib/resolve-convention-home.sh"), "--root", project]);
const home = pointer.status === 0 ? pointer.stdout.trim() : pointer.status === 1 ? "docs/conventions" : null;

const schema = JSON.parse(readFileSync(join(ROOT, "schemas/harness-ops.schema.json"), "utf8"));
const scratch = mkdtempSync(join(tmpdir(), "harness-ops-probe-state-issue-"));
let out;
try {
  const userConfig = opts["user-value"] === undefined ? undefined : { [KEY]: opts["user-value"] };
  out = resolve({ plugin: "harness-ops", projectRoot: project, home: home ?? scratch, schema, userConfig, userHome: scratch });
} finally {
  rmSync(scratch, { recursive: true, force: true });
}
const errors = out.layers.flatMap((l) => l.errors.filter((_, i) => [KEY, null].includes(l.error_keys[i])));
const value = out.values[KEY] ?? null;
console.log(JSON.stringify({ [KEY]: value, layer: value === null ? "default" : out.provenance[KEY], errors }));
