#!/usr/bin/env node

import { spawn } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, dirname, join, win32 } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import {
  planCsharpLaunch,
  resolveCsharpLs,
  resolveDotnetRoot,
} from "./launch-csharp-ls.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const pluginRoot = dirname(here);
let passed = 0;
let failed = 0;

function ok(name) {
  console.log(`ok: ${name}`);
  passed += 1;
}

function fail(name, detail) {
  console.error(`FAIL: ${name}${detail ? ` - ${detail}` : ""}`);
  failed += 1;
}

function check(name, condition, detail) {
  if (condition) ok(name);
  else fail(name, detail);
}

const lsp = JSON.parse(readFileSync(join(pluginRoot, ".lsp.json"), "utf8"));
const server = lsp["csharp-ls"];
check("lsp command is node", server?.command === "node", server?.command);
check(
  "lsp args name the bundled launcher",
  server?.args?.[0] === "${CLAUDE_PLUGIN_ROOT}/bin/launch-csharp-ls.mjs",
  JSON.stringify(server?.args),
);
check("lsp command is not csharp-ls itself", server?.command !== "csharp-ls");
check("lsp maps .cs to csharp", server?.extensionToLanguage?.[".cs"] === "csharp");

const files = new Map();
const isFile = (filePath) => files.has(filePath);
function touch(filePath) {
  files.set(filePath, true);
}

const exe = win32.join("C:\\home", ".dotnet", "tools", "csharp-ls.exe");
const cmd = win32.join("C:\\home", ".dotnet", "tools", "csharp-ls.cmd");
touch(exe);
touch(cmd);
const resolved = resolveCsharpLs({
  pathEnv: "",
  pathDelimiter: ";",
  pathApi: win32,
  env: { USERPROFILE: "C:\\home" },
  home: "C:\\home",
  isFile,
});
check("user tools dir resolves csharp-ls.exe", resolved.file === exe, resolved.file);
check("batch shim is not the resolved server", resolved.file !== cmd);

const dotnet = win32.join("C:\\sdk", "dotnet", "dotnet.exe");
touch(dotnet);
const root = resolveDotnetRoot({
  pathEnv: "C:\\sdk\\dotnet",
  pathDelimiter: ";",
  pathApi: win32,
  env: {},
  home: "C:\\home",
  isFile,
});
check(
  "DOTNET_ROOT is the directory containing dotnet.exe",
  root?.value === "C:\\sdk\\dotnet",
  root?.value,
);

const plan = planCsharpLaunch(resolved, root, {
  userArgs: [],
  env: { PATH: "C:\\Windows" },
  platform: "win32",
  arch: "x64",
});
check("plan spawns the apphost with no shell", plan.shell === false && plan.file === exe);
check("plan sets DOTNET_ROOT when unset", plan.env.DOTNET_ROOT === "C:\\sdk\\dotnet");
check("plan sets DOTNET_ROOT_X64 on win32 x64", plan.env.DOTNET_ROOT_X64 === "C:\\sdk\\dotnet");

const kept = planCsharpLaunch(resolved, { value: "D:\\sdk", source: "DOTNET_ROOT" }, {
  env: { DOTNET_ROOT: "D:\\sdk", DOTNET_ROOT_X64: "D:\\sdk64" },
  platform: "win32",
  arch: "x64",
});
check("existing DOTNET_ROOT is kept", kept.env.DOTNET_ROOT === "D:\\sdk" && kept.env.DOTNET_ROOT_X64 === "D:\\sdk64");

files.clear();
touch(win32.join("C:\\shim", "csharp-ls.cmd"));
const rejected = resolveCsharpLs({
  pathEnv: "C:\\shim",
  pathDelimiter: ";",
  pathApi: win32,
  env: {},
  home: "",
  isFile,
});
check("a cmd-only install is not a server", Boolean(rejected.error), rejected.file);

if (process.platform !== "win32") {
  const temp = mkdtempSync(join(tmpdir(), "csharp-lsp-"));
  try {
    const fake = join(temp, "csharp-ls");
    const dotnetDir = join(temp, "dotnet-host");
    writeFileSync(
      fake,
      [
        "#!/usr/bin/env node",
        "let buf = '';",
        "process.stderr.write('DOTNET_ROOT=' + (process.env.DOTNET_ROOT || '') + '\\n');",
        "process.stdin.on('data', (chunk) => {",
        "  buf += chunk.toString('utf8');",
        "  const sep = buf.indexOf('\\r\\n\\r\\n');",
        "  if (sep === -1) return;",
        "  const body = JSON.stringify({ jsonrpc: '2.0', id: 1, result: { capabilities: { definitionProvider: true } } });",
        "  process.stdout.write('Content-Length: ' + Buffer.byteLength(body) + '\\r\\n\\r\\n' + body);",
        "  process.exit(0);",
        "});",
        "",
      ].join("\n"),
    );
    chmodSync(fake, 0o755);
    mkdirSync(dotnetDir);
    writeFileSync(join(dotnetDir, "dotnet"), "");
    const childEnv = {
      ...process.env,
      PATH: `${dotnetDir}${delimiter}${process.env.PATH ?? ""}`,
      CSHARPLS_PATH: fake,
    };
    delete childEnv.DOTNET_ROOT;
    delete childEnv.DOTNET_ROOT_X64;
    const child = spawn(process.execPath, [join(here, "launch-csharp-ls.mjs")], {
      env: childEnv,
      stdio: ["pipe", "pipe", "pipe"],
    });
    const request = JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: { processId: process.pid, capabilities: {} },
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });
    // Clear inherited DOTNET_ROOT by passing a sentinel through the launcher.
    // The launcher sets DOTNET_ROOT only when unset. Force it unset in the child env.
    child.stdin.write(`Content-Length: ${Buffer.byteLength(request)}\r\n\r\n${request}`);
    const outcome = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        child.kill();
        reject(new Error(`timeout stdout=${stdout} stderr=${stderr}`));
      }, 5000);
      child.on("exit", () => {
        clearTimeout(timer);
        resolve({ stdout, stderr });
      });
      child.on("error", reject);
    });
    check(
      "launcher spawn answers initialize",
      outcome.stdout.includes("definitionProvider"),
      outcome.stdout,
    );
    check(
      "launcher sets DOTNET_ROOT to the dotnet host directory",
      outcome.stderr.includes(`DOTNET_ROOT=${dotnetDir}`),
      outcome.stderr,
    );
  } catch (error) {
    fail("launcher spawn answers initialize", error.message);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
}

if (failed > 0) {
  console.error(`${failed} failed, ${passed} passed`);
  process.exit(1);
}
console.log(`${passed} passed`);
