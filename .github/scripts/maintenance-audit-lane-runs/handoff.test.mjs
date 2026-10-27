// The judge's handoff markers: a leg hands its unit on only with a collector
// unit id and a reason from its leg's closed set, a leg with a permission
// denial hands nothing on, and the route job turns only well-formed markers
// into the next leg's matrix.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { denials, marker, route } from "./handoff.mjs";

const SCRIPT = fileURLToPath(new URL("./handoff.mjs", import.meta.url));

test("a marker takes a collector unit and its leg's handoff reasons only", () => {
  assert.deepEqual(marker("key", "a1", "credit-stop"), { unit: "a1", reason: "credit-stop" });
  assert.deepEqual(marker("key", "d8", "no-key"), { unit: "d8", reason: "no-key" });
  assert.deepEqual(marker("subscription", "c2", "limit-stop"), { unit: "c2", reason: "limit-stop" });
  assert.throws(() => marker("key", "a1", "limit-stop"), /not a key handoff reason/);
  assert.throws(() => marker("subscription", "a1", "no-key"), /not a subscription handoff reason/);
  assert.throws(() => marker("key", "a9", "auth"), /not a collector id/);
  assert.throws(() => marker("key", "a1\n", "auth"), /not a collector id/);
  assert.throws(() => marker("fallback", "a1", "auth"), /not key or subscription/);
});

test("the leg check counts every denial in the launcher's log", () => {
  assert.equal(denials(""), 0);
  assert.equal(denials(`${JSON.stringify({ denials: { count: 0 } })}\n`), 0);
  assert.equal(denials(`${JSON.stringify({ denials: { count: 2 } })}\n${JSON.stringify({})}\n`), 2);
});

test("the route builds the next leg's matrix from the downloaded markers", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "handoff-route-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(dir, { recursive: true });
  const put = (name, body) => writeFileSync(join(dir, name), JSON.stringify(body));
  assert.deepEqual(route("key", join(dir, "missing")), { include: [] });
  put("judge-handoff-c1.json", { unit: "c1", reason: "auth" });
  put("judge-handoff-a2.json", { unit: "a2", reason: "no-key" });
  assert.deepEqual(route("key", dir), {
    include: [
      { unit: "a2", reason: "no-key" },
      { unit: "c1", reason: "auth" },
    ],
  });
  // A marker under another unit's name, another leg's name or with an unknown reason fails the route.
  put("judge-handoff-d1.json", { unit: "d2", reason: "auth" });
  assert.throws(() => route("key", dir), /holds unit 'd2'/);
  rmSync(join(dir, "judge-handoff-d1.json"));
  put("judge-subscription-handoff-a1.json", { unit: "a1", reason: "auth" });
  assert.throws(() => route("key", dir), /not a key handoff marker/);
  rmSync(join(dir, "judge-subscription-handoff-a1.json"));
  put("judge-handoff-a1", { unit: "a1", reason: "auth" });
  assert.throws(() => route("key", dir), /not a key handoff marker/);
  rmSync(join(dir, "judge-handoff-a1"));
  put("judge-handoff-d1.json", { unit: "d1", reason: "rm -rf" });
  assert.throws(() => route("key", dir), /not a key handoff reason/);
});

test("the commands write the marker, the leg check and the route outputs", (t) => {
  const dir = mkdtempSync(join(tmpdir(), "handoff-cli-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const run = (command, env) => spawnSync(process.execPath, [SCRIPT, command], { env: { PATH: process.env.PATH, ...env }, encoding: "utf8" });
  const output = join(dir, "output");
  writeFileSync(output, "");

  const marked = join(dir, "markers");
  assert.equal(run("record", { LEG: "subscription", UNIT: "a3", REASON: "limit-stop", HANDOFF_DIR: marked }).status, 0);
  assert.deepEqual(JSON.parse(readFileSync(join(marked, "judge-subscription-handoff-a3.json"), "utf8")), { unit: "a3", reason: "limit-stop" });
  const refused = run("record", { LEG: "subscription", UNIT: "a3", REASON: "", HANDOFF_DIR: join(dir, "x") });
  assert.equal(refused.status, 1);
  assert.match(refused.stdout, /::error::reason '' is not a subscription handoff reason/);

  const log = join(dir, "log.jsonl");
  writeFileSync(log, `${JSON.stringify({ denials: { count: 0 } })}\n`);
  assert.equal(run("check-leg", { LOG_FILE: log, GITHUB_OUTPUT: output }).status, 0);
  assert.equal(readFileSync(output, "utf8"), "clean=true\n");
  writeFileSync(log, `${JSON.stringify({ denials: { count: 1 } })}\n`);
  writeFileSync(output, "");
  assert.equal(run("check-leg", { LOG_FILE: log, GITHUB_OUTPUT: output }).status, 1);
  assert.equal(run("check-leg", { LOG_FILE: join(dir, "none"), GITHUB_OUTPUT: output }).status, 1);
  assert.equal(readFileSync(output, "utf8"), "", "a denied or unreadable leg is never clean");

  assert.equal(run("route", { LEG: "subscription", HANDOFF_DIR: join(dir, "markers"), GITHUB_OUTPUT: output }).status, 0);
  assert.equal(readFileSync(output, "utf8"), `matrix=${JSON.stringify({ include: [{ unit: "a3", reason: "limit-stop" }] })}\ncount=1\n`);
});
