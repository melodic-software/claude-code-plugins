import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import { fileURLToPath } from "node:url";
import { javaMajor } from "./toolchain.mjs";

const here = fileURLToPath(new URL(".", import.meta.url));
const toolchain = join(here, "toolchain.mjs");
const settings = join(here, "settings.mjs");
const fresh = (name) => mkdtempSync(join(tmpdir(), `fv-${name}-`));

const run = (script, args) => spawnSync(process.execPath, [script, ...args], { encoding: "utf8" });
const runAsync = (script, args) =>
  new Promise((resolve) => {
    const child = spawn(process.execPath, [script, ...args]);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d));
    child.stderr.on("data", (d) => (stderr += d));
    child.on("close", (status) => resolve({ status, stdout, stderr }));
  });

const project = (yaml) => {
  const dir = fresh("project");
  if (yaml) {
    mkdirSync(join(dir, "docs", "conventions"), { recursive: true });
    writeFileSync(join(dir, "docs", "conventions", "formal-verification.yaml"), yaml);
  }
  return dir;
};

const fakeJava = (banner) => {
  const bin = fresh("bin");
  const java = join(bin, "java");
  writeFileSync(java, `#!/bin/sh\necho '${banner}' >&2\n`);
  chmodSync(java, 0o755);
  return java;
};

const JAR = Buffer.from("not a real jar, a stand-in served by this test\n");
const JAR_SHA = createHash("sha256").update(JAR).digest("hex");
let server;
let base;
before(async () => {
  server = createServer((req, res) => {
    if (req.url === "/tla2tools.jar") return res.end(JAR);
    res.statusCode = 404;
    res.end();
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(() => server.close());

test("settings gives the shipped bounds when the project has no convention file", () => {
  const r = run(settings, ["--project-dir", project()]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout).bounds, { chart_states: 500, rerun_states: 100000 });
});

test("a key in docs/conventions/formal-verification.yaml overrides only that key", () => {
  const r = run(settings, ["--project-dir", project("bounds:\n  chart_states: 40\n")]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout).bounds, { chart_states: 40, rerun_states: 100000 });
});

test("an invalid convention value is reported and the shipped value stands", () => {
  const r = run(settings, ["--project-dir", project("bounds:\n  chart_states: 0\n")]);
  assert.equal(r.status, 0);
  assert.match(r.stderr, /chart_states/);
  assert.equal(JSON.parse(r.stdout).bounds.chart_states, 500);
});

test("resolve with no jar and no java reports blocked: toolchain missing and writes nothing", () => {
  const data = join(fresh("data"), "absent");
  const r = run(toolchain, ["resolve", "--data-dir", data, "--java", join(fresh("nojava"), "java"), "--project-dir", project()]);
  assert.equal(r.status, 3);
  assert.equal(r.stderr.trim(), "blocked: toolchain missing: java, model-checker");
  assert.equal(existsSync(data), false);
});

test("an unrendered user_config token counts as unset", () => {
  const r = run(toolchain, ["resolve", "--data-dir", fresh("data"), "--jar", "${user_config.model_checker_jar}", "--java", fakeJava('openjdk version "25.0.1" 2025-10-21'), "--project-dir", project()]);
  assert.equal(r.status, 3);
  assert.equal(r.stderr.trim(), "blocked: toolchain missing: model-checker");
});

test("resolve prints the named jar, java and the bounds when both are present", () => {
  const jar = join(fresh("jar"), "tla2tools.jar");
  writeFileSync(jar, JAR);
  const java = fakeJava('openjdk version "11.0.2" 2019-01-15');
  const r = run(toolchain, ["resolve", "--data-dir", fresh("data"), "--jar", jar, "--java", java, "--project-dir", project("bounds:\n  rerun_states: 7\n")]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { jar, java, runtime: null, bounds: { chart_states: 500, rerun_states: 7 } });
});

test("check fails a Java below the floor and passes the jar it is given", () => {
  const jar = join(fresh("jar"), "tla2tools.jar");
  writeFileSync(jar, JAR);
  const r = run(toolchain, ["check", "--data-dir", fresh("data"), "--jar", jar, "--java", fakeJava('java version "1.8.0_402"'), "--project-dir", project()]);
  assert.equal(r.status, 1);
  assert.match(r.stdout, /^FAIL\tjava\t.* is Java 8; Java 11 or later is needed\.$/m);
  assert.match(r.stdout, new RegExp(`^PASS\\tmodel-checker\\t${jar}$`, "m"));
});

test("javaMajor reads both version schemes", () => {
  assert.equal(javaMajor('openjdk version "25" 2025-09-16'), 25);
  assert.equal(javaMajor('java version "1.8.0_402"'), 8);
  assert.equal(javaMajor("no version here"), null);
});

test("install model-checker keeps a download whose sha256 matches the pin", async () => {
  const data = fresh("data");
  const yaml = `model_checker:\n  version: "9.9.9"\n  url: "${base}/tla2tools.jar"\n  sha256: "${JAR_SHA}"\n`;
  const r = await runAsync(toolchain, ["install", "model-checker", "--data-dir", data, "--project-dir", project(yaml)]);
  assert.equal(r.status, 0, r.stderr);
  const dest = join(data, "toolchain", "tla2tools-9.9.9.jar");
  assert.equal(r.stdout.trim(), dest);
  assert.deepEqual(readFileSync(dest), JAR);
  const again = await runAsync(toolchain, ["install", "model-checker", "--data-dir", data, "--project-dir", project(yaml)]);
  assert.equal(again.stdout.trim(), `${dest} (already present)`);
});

test("install model-checker discards a download whose sha256 does not match", async () => {
  const data = fresh("data");
  const yaml = `model_checker:\n  version: "9.9.9"\n  url: "${base}/tla2tools.jar"\n  sha256: "${"0".repeat(64)}"\n`;
  const r = await runAsync(toolchain, ["install", "model-checker", "--data-dir", data, "--project-dir", project(yaml)]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /does not match the pinned checksum; nothing was kept/);
  assert.deepEqual(readdirSync(join(data, "toolchain")), []);
});
