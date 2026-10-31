import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, describe, it } from "node:test";

import { computeStamp, installPackageDeps, runCli } from "./setup-deps.mjs";

const sandboxes = [];
after(() => {
  for (const dir of sandboxes) fs.rmSync(dir, { recursive: true, force: true });
});

function sandbox() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "node-launcher-setup-"));
  sandboxes.push(dir);
  return dir;
}

/** A package directory whose package.json carries `setupDeps`. */
function fixturePackage(setupDeps) {
  const dir = sandbox();
  fs.writeFileSync(path.join(dir, "package.json"), JSON.stringify({ name: "fixture", setupDeps }));
  return dir;
}

function streams() {
  const io = { out: "", err: "", calls: [] };
  io.stdout = { write: (text) => (io.out += text) };
  io.stderr = { write: (text) => (io.err += text) };
  io.spawnWith = (status) => (command, options) => {
    io.calls.push({ command, options });
    return { status };
  };
  return io;
}

/** What setup leaves behind once npm has installed the shared packages. */
function markInstalled(data) {
  fs.mkdirSync(path.join(data, "node_modules", "@melodic", "video-digestion"), { recursive: true });
}

describe("installPackageDeps", () => {
  it("installs the package into the data directory and records the stamp", () => {
    const pkg = fixturePackage({ stamp: ".fixture.stamp", label: "fixture extraction" });
    const data = path.join(sandbox(), "knowledge-test");
    const io = streams();
    const code = installPackageDeps({
      packageDir: pkg,
      dataDir: data,
      env: {},
      stdout: io.stdout,
      stderr: io.stderr,
      spawn: io.spawnWith(0),
    });
    assert.equal(code, 0);
    assert.equal(io.calls.length, 1);
    assert.match(io.calls[0].command, /^npm(\.cmd)? install --omit=dev --install-links /);
    assert.ok(io.calls[0].command.endsWith(JSON.stringify(pkg)));
    assert.equal(io.calls[0].options.cwd, data);
    assert.match(fs.readFileSync(path.join(data, ".fixture.stamp"), "utf8"), /^[0-9a-f]{64}$/);
    assert.equal(io.out, `fixture extraction deps installed to ${path.join(data, "node_modules")}.\n`);

    // The recorded stamp is what makes the next run skip npm.
    markInstalled(data);
    const rerun = streams();
    installPackageDeps({ packageDir: pkg, dataDir: data, env: {}, stdout: rerun.stdout, spawn: rerun.spawnWith(0) });
    assert.equal(rerun.calls.length, 0);
    assert.equal(rerun.out, "fixture extraction deps already current.\n");
  });

  it("skips npm when the stamp is current", () => {
    const pkg = fixturePackage({ stamp: ".fixture.stamp", label: "fixture extraction" });
    const data = sandbox();
    markInstalled(data);
    fs.writeFileSync(path.join(data, ".fixture.stamp"), computeStamp(pkg));
    const io = streams();
    const code = installPackageDeps({ packageDir: pkg, dataDir: data, env: {}, stdout: io.stdout, spawn: io.spawnWith(0) });
    assert.equal(code, 0);
    assert.equal(io.calls.length, 0);
    assert.equal(io.out, "fixture extraction deps already current.\n");
  });

  it("reinstalls when package.json changes the stamp", () => {
    const pkg = fixturePackage({ stamp: ".fixture.stamp", label: "fixture extraction" });
    const data = sandbox();
    markInstalled(data);
    fs.writeFileSync(path.join(data, ".fixture.stamp"), computeStamp(pkg));
    fs.writeFileSync(path.join(pkg, "package.json"), JSON.stringify({ name: "fixture", version: "2.0.0", setupDeps: { stamp: ".fixture.stamp", label: "fixture extraction" } }));
    const io = streams();
    installPackageDeps({ packageDir: pkg, dataDir: data, env: {}, stdout: io.stdout, spawn: io.spawnWith(0) });
    assert.equal(io.calls.length, 1);
  });

  it("reinstalls when a file under the vendor tree changes the stamp", () => {
    const pkg = fixturePackage({ stamp: ".fixture.stamp", label: "fixture extraction" });
    const vendorDir = sandbox();
    fs.mkdirSync(path.join(vendorDir, "shared", "lib"), { recursive: true });
    const vendored = path.join(vendorDir, "shared", "lib", "index.js");
    fs.writeFileSync(vendored, "export const v = 1;\n");
    const data = sandbox();
    markInstalled(data);
    fs.writeFileSync(path.join(data, ".fixture.stamp"), computeStamp(pkg, vendorDir));
    const unchanged = streams();
    installPackageDeps({ packageDir: pkg, dataDir: data, env: {}, stdout: unchanged.stdout, spawn: unchanged.spawnWith(0), vendorDir });
    assert.equal(unchanged.calls.length, 0);

    fs.writeFileSync(vendored, "export const v = 2;\n");
    const io = streams();
    installPackageDeps({ packageDir: pkg, dataDir: data, env: {}, stdout: io.stdout, spawn: io.spawnWith(0), vendorDir });
    assert.equal(io.calls.length, 1);
    assert.match(io.calls[0].command, /^npm(\.cmd)? install --omit=dev --install-links /);
  });

  it("reinstalls when the package's sentinel module is missing, though the stamp is current", () => {
    const pkg = fixturePackage({ stamp: ".fixture.stamp", label: "fixture extraction", sentinel: "@fixture/shared" });
    const data = sandbox();
    fs.writeFileSync(path.join(data, ".fixture.stamp"), computeStamp(pkg));
    fs.mkdirSync(path.join(data, "node_modules", "@melodic", "video-digestion"), { recursive: true });
    const missing = streams();
    installPackageDeps({ packageDir: pkg, dataDir: data, env: {}, stdout: missing.stdout, spawn: missing.spawnWith(0) });
    assert.equal(missing.calls.length, 1);

    fs.mkdirSync(path.join(data, "node_modules", "@fixture", "shared"), { recursive: true });
    const present = streams();
    installPackageDeps({ packageDir: pkg, dataDir: data, env: {}, stdout: present.stdout, spawn: present.spawnWith(0) });
    assert.equal(present.calls.length, 0);
    assert.equal(present.out, "fixture extraction deps already current.\n");
  });

  it("provisions Chromium for a package that asks for it, even when the stamp is current", () => {
    const pkg = fixturePackage({ stamp: ".fixture.stamp", label: "fixture extraction", chromium: true });
    const data = sandbox();
    markInstalled(data);
    fs.writeFileSync(path.join(data, ".fixture.stamp"), computeStamp(pkg));
    const io = streams();
    const code = installPackageDeps({ packageDir: pkg, dataDir: data, env: { KEEP: "1" }, stdout: io.stdout, spawn: io.spawnWith(0) });
    assert.equal(code, 0);
    assert.equal(io.calls.length, 1);
    assert.match(io.calls[0].command, /^npx(\.cmd)? playwright install chromium$/);
    const browsers = path.join(data, "ms-playwright");
    assert.deepEqual(io.calls[0].options.env, { KEEP: "1", PLAYWRIGHT_BROWSERS_PATH: browsers });
    assert.equal(io.out, `Chromium provisioned into ${browsers}.\n`);
  });

  it("reports deps and Chromium current together", () => {
    const pkg = fixturePackage({ stamp: ".fixture.stamp", label: "fixture extraction", chromium: true });
    const data = sandbox();
    markInstalled(data);
    fs.writeFileSync(path.join(data, ".fixture.stamp"), computeStamp(pkg));
    fs.mkdirSync(path.join(data, "ms-playwright", "chromium-1234"), { recursive: true });
    const io = streams();
    installPackageDeps({ packageDir: pkg, dataDir: data, env: {}, stdout: io.stdout, spawn: io.spawnWith(0) });
    assert.equal(io.calls.length, 0);
    assert.equal(io.out, "fixture extraction deps and Chromium already current.\n");
  });

  it("returns npm's failing status and writes no stamp", () => {
    const pkg = fixturePackage({ stamp: ".fixture.stamp", label: "fixture extraction" });
    const data = sandbox();
    const io = streams();
    const code = installPackageDeps({ packageDir: pkg, dataDir: data, env: {}, stdout: io.stdout, stderr: io.stderr, spawn: io.spawnWith(5) });
    assert.equal(code, 5);
    assert.equal(io.err, "npm install failed; see output above.\n");
    assert.equal(fs.existsSync(path.join(data, ".fixture.stamp")), false);
  });

  it("refuses an inherited data directory naming another plugin and writes nothing there", () => {
    const pkg = fixturePackage({ stamp: ".fixture.stamp", label: "fixture extraction" });
    const foreign = path.join(sandbox(), "codex-openai-codex");
    fs.mkdirSync(foreign);
    const io = streams();
    const code = installPackageDeps({
      packageDir: pkg,
      dataDir: undefined,
      env: { CLAUDE_PLUGIN_DATA: foreign },
      stderr: io.stderr,
      spawn: io.spawnWith(0),
    });
    assert.equal(code, 1);
    assert.match(io.err, /--data-dir "\$\{CLAUDE_PLUGIN_DATA\}"/);
    assert.deepEqual(fs.readdirSync(foreign), []);
    assert.equal(io.calls.length, 0);
  });
});

describe("runCli", () => {
  const extraction = path.resolve(import.meta.dirname, "..", "..", "skills", "video-digest", "extraction");

  for (const [name, argv, message] of [
    ["a missing --package", ["--data-dir", "/d/knowledge-x"], "`--package` is required"],
    ["an unknown argument", ["--package", extraction, "--work-root", "/p"], "unknown argument `--work-root`"],
    ["a flag with no value", ["--package"], "`--package` requires a directory value"],
    ["a package outside the plugin", ["--package", os.tmpdir()], "`--package` must name a directory inside the knowledge plugin"],
    ["a package with no setupDeps", ["--package", import.meta.dirname], "has no setupDeps { stamp, label }"],
    ["an unsubstituted --data-dir", ["--package", extraction, "--data-dir", "<plugin-data>"], "unsubstituted placeholder"],
  ]) {
    it(`rejects ${name} before installing anything`, () => {
      const io = streams();
      assert.equal(runCli(argv, io.stderr), 2);
      assert.ok(io.err.includes(message), io.err);
      assert.ok(io.err.endsWith("Usage: node setup-deps.mjs --data-dir <dir> --package <extraction-package-dir>\n"));
    });
  }
});
