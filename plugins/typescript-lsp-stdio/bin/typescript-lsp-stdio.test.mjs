import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { planTypescriptLanguageServer } from "./typescript-lsp-stdio.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const spawnScript = path.join(here, "typescript-lsp-stdio.mjs");
const MZ = Buffer.from([0x4d, 0x5a, 0x90, 0x00]);
const nodeExe = "C:\\Program Files\\nodejs\\node.exe";

function winFs(entries) {
  const files = new Map();
  for (const [file, head] of entries) {
    files.set(path.win32.normalize(file).toLowerCase(), head);
  }
  return {
    exists(file) {
      return files.has(path.win32.normalize(file).toLowerCase());
    },
    readHead(file) {
      return files.get(path.win32.normalize(file).toLowerCase()) ?? Buffer.alloc(0);
    },
    readText(file) {
      const buf = files.get(path.win32.normalize(file).toLowerCase());
      return Buffer.isBuffer(buf) ? buf.toString("utf8") : "";
    },
  };
}

test("windows node plus cli.mjs is used when PATH has only a .cmd shim", () => {
  const prefix = "C:\\Users\\me\\AppData\\Roaming\\npm";
  const cli = path.win32.join(prefix, "node_modules", "typescript-language-server", "lib", "cli.mjs");
  const shim = path.win32.join(prefix, "typescript-language-server.cmd");
  const fs = winFs([
    [shim, Buffer.from("@echo off\r\n")],
    [cli, Buffer.from("")],
  ]);
  const plan = planTypescriptLanguageServer({
    platform: "win32",
    env: { PATH: prefix, APPDATA: "C:\\Users\\me\\AppData\\Roaming" },
    execPath: nodeExe,
    exists: fs.exists,
    readHead: fs.readHead,
    readText: fs.readText,
  });
  assert.equal(plan.status, "ready");
  assert.equal(plan.mode, "node-cli");
  assert.equal(plan.shell, false);
  assert.equal(plan.command, nodeExe);
  assert.deepEqual(plan.args, [cli, "--stdio"]);
  assert.ok(plan.rejected.some((file) => file.toLowerCase().endsWith(".cmd")));
  assert.ok(!String(plan.command).toLowerCase().endsWith(".cmd"));
});

test("windows parses cli.mjs out of the .cmd and still does not spawn it", () => {
  const prefix = "C:\\npm";
  const cli = "D:\\pkg\\typescript-language-server\\lib\\cli.mjs";
  const shim = path.win32.join(prefix, "typescript-language-server.cmd");
  const fs = winFs([
    [shim, Buffer.from(`"%_prog%" "${cli}" %*\r\n`)],
    [cli, Buffer.from("")],
  ]);
  const plan = planTypescriptLanguageServer({
    platform: "win32",
    env: { PATH: prefix },
    execPath: nodeExe,
    exists: fs.exists,
    readHead: fs.readHead,
    readText: fs.readText,
  });
  assert.equal(plan.mode, "node-cli");
  assert.equal(plan.shell, false);
  assert.equal(plan.args[0], cli);
  assert.equal(plan.args.at(-1), "--stdio");
});

test("a real typescript-language-server.exe wins over node plus cli.mjs", () => {
  const prefix = "C:\\npm";
  const exe = path.win32.join(prefix, "typescript-language-server.exe");
  const cli = path.win32.join(prefix, "node_modules", "typescript-language-server", "lib", "cli.mjs");
  const fs = winFs([
    [exe, MZ],
    [cli, Buffer.from("")],
    [path.win32.join(prefix, "typescript-language-server.cmd"), Buffer.from("@echo off\r\n")],
  ]);
  const plan = planTypescriptLanguageServer({
    platform: "win32",
    env: { PATH: prefix },
    execPath: nodeExe,
    exists: fs.exists,
    readHead: fs.readHead,
    readText: fs.readText,
  });
  assert.equal(plan.mode, "path-executable");
  assert.equal(plan.command, exe);
  assert.deepEqual(plan.args, ["--stdio"]);
  assert.equal(plan.shell, false);
  assert.equal(plan.kind, "pe");
});

test("windows blocks a .cmd shim when lib/cli.mjs is missing", () => {
  const prefix = "C:\\npm";
  const fs = winFs([
    [path.win32.join(prefix, "typescript-language-server.cmd"), Buffer.from("@echo off\r\n")],
  ]);
  const plan = planTypescriptLanguageServer({
    platform: "win32",
    env: { PATH: prefix },
    execPath: nodeExe,
    exists: fs.exists,
    readHead: fs.readHead,
    readText: fs.readText,
  });
  assert.equal(plan.status, "blocked");
  assert.equal(plan.command, null);
  assert.equal(plan.shell, false);
  assert.match(plan.reason, /\.cmd shim/);
});

test("linux spawn uses node and lib/cli.mjs --stdio and does not run the .cmd", () => {
  const root = mkdtempSync(path.join(tmpdir(), "ts-lsp-"));
  const prefix = path.join(root, "prefix");
  const cli = path.join(prefix, "node_modules", "typescript-language-server", "lib", "cli.mjs");
  mkdirSync(path.dirname(cli), { recursive: true });
  const marker = path.join(root, "marker");
  const shimRan = path.join(root, "shim-ran");
  writeFileSync(
    cli,
    `import { writeFileSync } from "node:fs";
writeFileSync(process.env.MARKER, JSON.stringify({ argv: process.argv.slice(1), execPath: process.execPath }));
`,
  );
  writeFileSync(path.join(prefix, "typescript-language-server.cmd"), `#!/bin/sh\nprintf shim > ${JSON.stringify(shimRan)}\n`);
  chmodSync(path.join(prefix, "typescript-language-server.cmd"), 0o755);
  const env = { ...process.env, PATH: prefix, MARKER: marker, APPDATA: "" };
  const probe = spawnSync(process.execPath, [spawnScript, "--probe"], { env, encoding: "utf8" });
  assert.equal(probe.status, 0, probe.stderr);
  const plan = JSON.parse(probe.stdout);
  assert.equal(plan.shell, false);
  assert.equal(plan.mode, "node-cli");
  assert.equal(plan.command, process.execPath);
  assert.deepEqual(plan.args, [cli, "--stdio"]);
  const run = spawnSync(process.execPath, [spawnScript], { env, encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  const seen = JSON.parse(readFileSync(marker, "utf8"));
  assert.deepEqual(seen.argv, [cli, "--stdio"]);
  assert.equal(seen.execPath, process.execPath);
  assert.throws(() => readFileSync(shimRan, "utf8"));
});
