import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, describe, it } from "node:test";
import { pathToFileURL } from "node:url";

import { launch } from "./run.mjs";

const sandboxes = [];
after(() => {
  for (const dir of sandboxes) fs.rmSync(dir, { recursive: true, force: true });
});

function sandbox() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "node-launcher-"));
  sandboxes.push(dir);
  return dir;
}

/** A stderr double and a spawn double that records its call. */
function doubles(status = 0) {
  const io = { errors: "", calls: [] };
  io.stderr = { write: (text) => (io.errors += text) };
  io.spawn = (command, args, options) => {
    io.calls.push({ command, args, options });
    return { status };
  };
  return io;
}

const packageDir = path.join(os.tmpdir(), "pkg");
const knowledge = "/var/fixture/claude/plugins/data/knowledge-melodic-software";
const codex = "/var/fixture/claude/plugins/data/codex-openai-codex";
const usage = "usage line\n";

describe("launch", () => {
  it("runs the script under the package directory with the resolve hook and the --data-dir value", () => {
    const io = doubles(7);
    const code = launch({
      packageDir,
      argv: ["--data-dir", knowledge, "sub/script.js", "--flag", "x"],
      usage,
      env: { CLAUDE_PLUGIN_DATA: codex, KEEP: "1" },
      stderr: io.stderr,
      spawn: io.spawn,
    });
    assert.equal(code, 7);
    assert.equal(io.calls.length, 1);
    const [{ command, args, options }] = io.calls;
    assert.equal(command, process.execPath);
    assert.deepEqual(args, [
      "--import",
      pathToFileURL(path.join(import.meta.dirname, "register-hook.mjs")).href,
      path.join(packageDir, "sub", "script.js"),
      "--flag",
      "x",
    ]);
    assert.deepEqual(options.env, { KEEP: "1", CLAUDE_PLUGIN_DATA: knowledge });
  });

  it("drops an inherited data directory naming another plugin when no flag is given", () => {
    const io = doubles();
    launch({ packageDir, argv: ["a.js"], usage, env: { CLAUDE_PLUGIN_DATA: codex }, stderr: io.stderr, spawn: io.spawn });
    assert.deepEqual(io.calls[0].options.env, {});
  });

  it("refuses a script outside the package directory", () => {
    const io = doubles();
    const code = launch({ packageDir, argv: ["../escape.js"], usage, env: {}, stderr: io.stderr, spawn: io.spawn });
    assert.equal(code, 2);
    assert.equal(io.calls.length, 0);
    assert.equal(io.errors, "Refusing to run a script outside the extraction directory: ../escape.js\n");
  });

  it("prints the usage and runs nothing without a script", () => {
    const io = doubles();
    assert.equal(launch({ packageDir, argv: [], usage, env: {}, stderr: io.stderr, spawn: io.spawn }), 2);
    assert.equal(io.errors, usage);
    assert.equal(io.calls.length, 0);
  });

  it("reports an unsubstituted --data-dir placeholder as a usage error", () => {
    const io = doubles();
    const code = launch({
      packageDir,
      argv: ["--data-dir", "${CLAUDE_PLUGIN_DATA}", "a.js"],
      usage,
      env: {},
      stderr: io.stderr,
      spawn: io.spawn,
    });
    assert.equal(code, 2);
    assert.match(io.errors, /unsubstituted placeholder/);
    assert.ok(io.errors.endsWith(usage));
    assert.equal(io.calls.length, 0);
  });

  it("uses the caller's parser and child environment, and a throw from either is a usage error", () => {
    const io = doubles();
    launch({
      packageDir,
      argv: ["ignored"],
      usage,
      env: { CLAUDE_PLUGIN_DATA: knowledge },
      parse: () => ({ script: "b.js", rest: ["r"] }),
      childEnv: (inherited, parsed) => ({ ...inherited, SEEN: parsed.dataDir }),
      stderr: io.stderr,
      spawn: io.spawn,
    });
    assert.equal(io.calls[0].args[2], path.join(packageDir, "b.js"));
    assert.deepEqual(io.calls[0].options.env, { SEEN: knowledge });

    const failing = doubles();
    const code = launch({
      packageDir,
      argv: ["a.js"],
      usage,
      env: {},
      childEnv: () => {
        throw new Error("bad option");
      },
      stderr: failing.stderr,
      spawn: failing.spawn,
    });
    assert.equal(code, 2);
    assert.equal(failing.errors, `bad option\n${usage}`);
    assert.equal(failing.calls.length, 0);
  });

  it("exits 1 when the child reports no status", () => {
    const io = doubles(null);
    assert.equal(launch({ packageDir, argv: ["a.js"], usage, env: {}, stderr: io.stderr, spawn: io.spawn }), 1);
  });

  it("lets the child resolve a bare specifier from the data directory's node_modules", () => {
    const data = sandbox();
    const pkg = sandbox();
    const moduleDir = path.join(data, "node_modules", "fixture-dep");
    fs.mkdirSync(moduleDir, { recursive: true });
    fs.writeFileSync(path.join(moduleDir, "package.json"), JSON.stringify({ name: "fixture-dep", type: "module", exports: "./index.js" }));
    fs.writeFileSync(path.join(moduleDir, "index.js"), 'export const value = "from data dir";\n');
    const out = path.join(pkg, "out.txt");
    fs.writeFileSync(
      path.join(pkg, "script.mjs"),
      `import fs from "node:fs";\nimport { value } from "fixture-dep";\nfs.writeFileSync(${JSON.stringify(out)}, value);\n`,
    );
    const code = launch({
      packageDir: pkg,
      argv: ["--data-dir", data, "script.mjs"],
      usage,
      env: { PATH: process.env.PATH ?? "" },
      stderr: process.stderr,
    });
    assert.equal(code, 0);
    assert.equal(fs.readFileSync(out, "utf8"), "from data dir");
  });
});
