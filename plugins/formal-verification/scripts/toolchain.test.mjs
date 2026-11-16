import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { download, install, javaMajor, release, within } from "./toolchain.mjs";

const here = fileURLToPath(new URL(".", import.meta.url));
const toolchain = join(here, "toolchain.mjs");
const settings = join(here, "settings.mjs");
const temps = [];
const fresh = (name) => {
  const dir = mkdtempSync(join(tmpdir(), `fv-${name}-`));
  temps.push(dir);
  return dir;
};
test.after(() => {
  for (const dir of temps) rmSync(dir, { recursive: true, force: true });
});

const run = (script, args) => spawnSync(process.execPath, [script, ...args], { encoding: "utf8" });

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

const JAR = Buffer.from("not a real jar, a stand-in for this test\n");
const JAR_SHA = createHash("sha256").update(JAR).digest("hex");
const URL_ = "https://example.invalid/tla2tools.jar";
const releases = (sha256 = JAR_SHA, url = URL_) => ({ model_checker: { "9.9.9": { url, sha256 } }, renderer: {} });
const pinned = { model_checker: { version: "9.9.9" }, renderer: { package: "pele", version: "1.9.0" } };
const served = (body, headers = {}) => async () => new Response(body, { status: 200, headers });

test("settings gives the shipped bounds when the project has no convention file", () => {
  const r = run(settings, ["--project-dir", project()]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout).bounds, {
    chart_states: 500,
    rerun_states: 100000,
    timeout_seconds: 1800,
    heap: "4g",
    output_bytes: 1073741824,
    interval_max: 10000,
  });
});

test("a key in docs/conventions/formal-verification.yaml overrides only that key", () => {
  const r = run(settings, ["--project-dir", project("bounds:\n  chart_states: 40\n")]);
  assert.equal(r.status, 0, r.stderr);
  const { bounds } = JSON.parse(r.stdout);
  assert.equal(bounds.chart_states, 40);
  assert.equal(bounds.rerun_states, 100000);
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

test("resolve prints the named jar, java, the bounds and the allowed modules", () => {
  const jar = join(fresh("jar"), "tla2tools.jar");
  writeFileSync(jar, JAR);
  const java = fakeJava('openjdk version "11.0.2" 2019-01-15');
  const r = run(toolchain, ["resolve", "--data-dir", fresh("data"), "--jar", jar, "--java", java, "--project-dir", project("bounds:\n  rerun_states: 7\n")]);
  assert.equal(r.status, 0, r.stderr);
  const out = JSON.parse(r.stdout);
  assert.equal(out.jar, jar);
  assert.equal(out.java, java);
  assert.equal(out.bounds.rerun_states, 7);
  assert.ok(!out.allowed_modules.includes("Json"));
});

test("check fails a Java below the floor and passes the jar it is given", () => {
  const jar = join(fresh("jar"), "tla2tools.jar");
  writeFileSync(jar, JAR);
  const r = run(toolchain, ["check", "--data-dir", fresh("data"), "--jar", jar, "--java", fakeJava('java version "1.8.0_402"'), "--project-dir", project()]);
  assert.equal(r.status, 1);
  assert.match(r.stdout, /^FAIL\tjava\t.* is Java 8; Java 11 or later is needed\.$/m);
  assert.match(r.stdout, new RegExp(`^PASS\\tmodel-checker\\t${jar}$`, "m"));
});

test("a java.min_version that is not a whole number is refused", () => {
  const jar = join(fresh("jar"), "tla2tools.jar");
  writeFileSync(jar, JAR);
  const r = run(toolchain, ["check", "--jar", jar, "--java", fakeJava('openjdk version "25" 2025-09-16'), "--project-dir", project("java:\n  min_version: eleven\n")]);
  assert.equal(r.status, 1);
  assert.equal(r.stderr.trim(), 'java.min_version "eleven" is not a Java major version.');
});

test("a timeout_seconds past what a timer can hold is reported and the shipped value stands", () => {
  const r = run(settings, ["--project-dir", project("bounds:\n  timeout_seconds: 3000000\n")]);
  assert.equal(r.status, 0);
  assert.match(r.stderr, /timeout_seconds/);
  assert.equal(JSON.parse(r.stdout).bounds.timeout_seconds, 1800);
});

const fakeRuntime = (name, version) => {
  const file = join(fresh("bin"), name);
  writeFileSync(file, `#!/bin/sh\necho '${version}'\n`);
  chmodSync(file, 0o755);
  return file;
};

for (const [name, version, blocked] of [
  ["node", "v20.11.0", true],
  ["node", "v23.5.0", true],
  ["node", "v22.18.0", false],
  ["node", "v23.6.0", false],
  ["bun", "1.1.4", true],
  ["bun", "1.1.5", false],
  ["deno", "deno 1.46.3 (stable, release, x86_64-unknown-linux-gnu)", true],
  ["deno", "deno 2.0.0 (stable, release, x86_64-unknown-linux-gnu)", false],
]) {
  test(`resolve ${blocked ? "blocks" : "takes"} a --runtime ${name} that prints ${version}`, () => {
    const jar = join(fresh("jar"), "tla2tools.jar");
    writeFileSync(jar, JAR);
    const java = fakeJava('openjdk version "25" 2025-09-16');
    const r = run(toolchain, ["resolve", "--jar", jar, "--java", java, "--runtime", fakeRuntime(name, version), "--project-dir", project()]);
    assert.equal(r.status, blocked ? 3 : 0, r.stderr);
    if (blocked) assert.equal(r.stderr.trim(), "blocked: toolchain missing: script-runtime");
  });
}

test("both scripts run when reached through a symlink", () => {
  const links = fresh("links");
  symlinkSync(settings, join(links, "settings.mjs"));
  symlinkSync(toolchain, join(links, "toolchain.mjs"));
  const s = run(join(links, "settings.mjs"), ["--project-dir", project()]);
  assert.equal(s.status, 0, s.stderr);
  assert.equal(JSON.parse(s.stdout).bounds.chart_states, 500);
  const t = run(join(links, "toolchain.mjs"), []);
  assert.equal(t.status, 2);
  assert.match(t.stderr, /^usage: toolchain\.mjs/);
});

test("javaMajor reads both version schemes", () => {
  assert.equal(javaMajor('openjdk version "25" 2025-09-16'), 25);
  assert.equal(javaMajor('java version "1.8.0_402"'), 8);
  assert.equal(javaMajor("no version here"), null);
});

for (const [key, yaml] of [
  ["model_checker.url", "model_checker:\n  url: https://evil.example/x.jar\n"],
  ["model_checker.sha256", `model_checker:\n  sha256: "${"0".repeat(64)}"\n`],
  ["renderer.integrity", "renderer:\n  integrity: sha512-AAAA\n"],
]) {
  test(`a repository convention file that sets ${key} is refused`, () => {
    const data = fresh("data");
    const r = run(toolchain, ["install", "model-checker", "--data-dir", data, "--project-dir", project(yaml)]);
    assert.equal(r.status, 1);
    assert.match(r.stderr, new RegExp(`sets ${key.replace(".", "\\.")}\\. Download sources and checksums come only from the plugin's releases\\.json`));
    assert.deepEqual(readdirSync(data), []);
  });
}

test("a repository version with no pinned checksum is refused before any download", () => {
  const data = fresh("data");
  const r = run(toolchain, ["install", "model-checker", "--data-dir", data, "--project-dir", project('model_checker:\n  version: "1.8.0"\n')]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /^No pinned checksum for model-checker 1\.8\.0\. The plugin's releases\.json pins: 1\.7\.4\.$/m);
  assert.deepEqual(readdirSync(data), []);
});

test("a version or package that would leave the data folder is refused", () => {
  assert.throws(() => release("model-checker", { model_checker: { version: "../../x" } }), /is not a version/);
  assert.throws(
    () => release("renderer", { renderer: { package: "../../evil", version: "1.0.0" } }),
    /is not an npm package name/,
  );
  const data = fresh("data");
  assert.throws(() => within(data, join(data, "..", "outside")), /is outside/);
  assert.throws(() => within(data, data), /is outside/);
  assert.equal(within(data, join(data, "toolchain", "a.jar")), join(data, "toolchain", "a.jar"));
});

test("install keeps a download whose sha256 matches the shipped pin and skips it the second time", async () => {
  const data = fresh("data");
  const dest = await install("model-checker", { dataDir: data, settings: pinned, releases: releases(), fetchImpl: served(JAR) });
  assert.equal(dest, join(data, "toolchain", "tla2tools-9.9.9.jar"));
  assert.deepEqual(readFileSync(dest), JAR);
  const again = await install("model-checker", { dataDir: data, settings: pinned, releases: releases(), fetchImpl: served(JAR) });
  assert.equal(again, `${dest} (already present)`);
});

test("install discards a download whose sha256 does not match", async () => {
  const data = fresh("data");
  await assert.rejects(
    install("model-checker", { dataDir: data, settings: pinned, releases: releases("0".repeat(64)), fetchImpl: served(JAR) }),
    /does not match the pinned checksum; nothing was kept/,
  );
  assert.deepEqual(readdirSync(join(data, "toolchain")), []);
});

test("download refuses a URL that is not https", async () => {
  const dir = fresh("dl");
  await assert.rejects(
    download("http://example.invalid/x", join(dir, "x"), () => true, "test", { fetchImpl: served(JAR) }),
    /is not an https URL; nothing was downloaded/,
  );
  assert.deepEqual(readdirSync(dir), []);
});

test("download refuses a body over the size cap, by header and by bytes read", async () => {
  const dir = fresh("dl");
  await assert.rejects(
    download(URL_, join(dir, "x"), () => true, "test", { fetchImpl: served(JAR, { "content-length": "9999" }), maxBytes: 10 }),
    /is larger than 10 bytes; nothing was kept/,
  );
  await assert.rejects(
    download(URL_, join(dir, "y"), () => true, "test", { fetchImpl: served(JAR), maxBytes: 10 }),
    /is larger than 10 bytes; nothing was kept/,
  );
  assert.deepEqual(readdirSync(dir), []);
});

test("download stops at its timeout", async () => {
  const dir = fresh("dl");
  const hang = (url, { signal }) =>
    new Promise((_, reject) => signal.addEventListener("abort", () => reject(signal.reason)));
  await assert.rejects(download(URL_, join(dir, "x"), () => true, "test", { fetchImpl: hang, timeoutMs: 50 }), /timed out|aborted/i);
  assert.deepEqual(readdirSync(dir), []);
});
