import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { planCsharpLs } from "./csharp-ls-windows-spawn.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const spawnScript = path.join(here, "csharp-ls-windows-spawn.mjs");
const MZ = Buffer.from([0x4d, 0x5a, 0x90, 0x00]);

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
      return files.get(path.win32.normalize(file).toLowerCase());
    },
  };
}

test("windows PATH resolves csharp-ls.exe and skips a sibling .cmd", () => {
  const tools = "C:\\Users\\me\\.dotnet\\tools";
  const fs = winFs([
    [path.win32.join(tools, "csharp-ls.exe"), MZ],
    [path.win32.join(tools, "csharp-ls.cmd"), Buffer.from("@echo off\r\n")],
    ["C:\\Program Files\\dotnet\\dotnet.exe", MZ],
  ]);
  const plan = planCsharpLs({
    platform: "win32",
    env: {
      PATH: `${tools};C:\\Program Files\\dotnet`,
      USERPROFILE: "C:\\Users\\me",
    },
    exists: fs.exists,
    readHead: fs.readHead,
  });
  assert.equal(plan.status, "ready");
  assert.equal(plan.shell, false);
  assert.equal(plan.command, path.win32.join(tools, "csharp-ls.exe"));
  assert.deepEqual(plan.args, []);
  assert.equal(plan.kind, "pe");
  assert.equal(plan.toolsDirOnPath, true);
  assert.equal(plan.dotnetRoot, "C:\\Program Files\\dotnet");
  assert.equal(plan.dotnetRootSource, "dotnet-host");
  assert.equal(plan.env.DOTNET_ROOT, "C:\\Program Files\\dotnet");
  assert.ok(plan.rejected.some((file) => file.toLowerCase().endsWith(".cmd")));
  assert.ok(!String(plan.command).toLowerCase().endsWith(".cmd"));
});

test("windows blocks when PATH has only a csharp-ls.cmd shim", () => {
  const tools = "C:\\Users\\me\\.dotnet\\tools";
  const fs = winFs([[path.win32.join(tools, "csharp-ls.cmd"), Buffer.from("@echo off\r\n")]]);
  const plan = planCsharpLs({
    platform: "win32",
    env: { PATH: tools, USERPROFILE: "C:\\Users\\me", DOTNET_ROOT: "D:\\dotnet" },
    exists: fs.exists,
    readHead: fs.readHead,
  });
  assert.equal(plan.status, "blocked");
  assert.equal(plan.shell, false);
  assert.equal(plan.command, null);
  assert.equal(plan.dotnetRootSource, "env");
  assert.equal(plan.dotnetRoot, "D:\\dotnet");
  assert.match(plan.reason, /not a native executable/);
});

test("windows reports the tools directory when it is absent from PATH", () => {
  const fs = winFs([]);
  const plan = planCsharpLs({
    platform: "win32",
    env: { PATH: "C:\\Windows\\System32", USERPROFILE: "C:\\Users\\me" },
    exists: fs.exists,
    readHead: fs.readHead,
  });
  assert.equal(plan.status, "blocked");
  assert.equal(plan.toolsDirOnPath, false);
  assert.equal(plan.toolsDir, "C:\\Users\\me\\.dotnet\\tools");
  assert.match(plan.reason, /not on PATH/);
});

test("an existing DOTNET_ROOT is kept", () => {
  const tools = "C:\\Users\\me\\.dotnet\\tools";
  const fs = winFs([
    [path.win32.join(tools, "csharp-ls.exe"), MZ],
    ["C:\\Program Files\\dotnet\\dotnet.exe", MZ],
  ]);
  const plan = planCsharpLs({
    platform: "win32",
    env: {
      PATH: `${tools};C:\\Program Files\\dotnet`,
      USERPROFILE: "C:\\Users\\me",
      DOTNET_ROOT: "E:\\sdk",
    },
    exists: fs.exists,
    readHead: fs.readHead,
  });
  assert.equal(plan.dotnetRoot, "E:\\sdk");
  assert.equal(plan.dotnetRootSource, "env");
  assert.equal(plan.env.DOTNET_ROOT, "E:\\sdk");
});

test("linux spawn runs the native binary with shell false and a derived DOTNET_ROOT", () => {
  const root = mkdtempSync(path.join(tmpdir(), "csharp-ls-spawn-"));
  const bin = path.join(root, "bin");
  const runtime = path.join(root, "dotnet");
  mkdirSync(bin);
  mkdirSync(runtime);
  const marker = path.join(root, "marker");
  const server = path.join(bin, "csharp-ls");
  const shim = path.join(bin, "csharp-ls.cmd");
  writeFileSync(
    server,
    `#!/bin/sh\nprintf '%s\\n' "$DOTNET_ROOT" > ${JSON.stringify(marker)}\nprintf '%s\\n' "$0" >> ${JSON.stringify(marker)}\n`,
  );
  writeFileSync(shim, "#!/bin/sh\nprintf shim > " + JSON.stringify(path.join(root, "shim-ran")) + "\n");
  writeFileSync(path.join(runtime, "dotnet"), "#!/bin/sh\nexit 0\n");
  chmodSync(server, 0o755);
  chmodSync(shim, 0o755);
  chmodSync(path.join(runtime, "dotnet"), 0o755);
  const env = { ...process.env, PATH: `${bin}:${runtime}`, DOTNET_ROOT: "" };
  const probe = spawnSync(process.execPath, [spawnScript, "--probe"], { env, encoding: "utf8" });
  assert.equal(probe.status, 0, probe.stderr);
  const plan = JSON.parse(probe.stdout);
  assert.equal(plan.shell, false);
  assert.equal(plan.status, "ready");
  assert.equal(plan.kind, "script");
  assert.equal(plan.dotnetRootSource, "dotnet-host");
  assert.equal(plan.command, server);
  assert.ok(plan.rejected.some((file) => file.endsWith(".cmd")));
  const run = spawnSync(process.execPath, [spawnScript], { env, encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  const lines = readFileSync(marker, "utf8").trim().split("\n");
  assert.equal(lines[0], runtime);
  assert.equal(lines[1], server);
  assert.throws(() => readFileSync(path.join(root, "shim-ran"), "utf8"));
});
