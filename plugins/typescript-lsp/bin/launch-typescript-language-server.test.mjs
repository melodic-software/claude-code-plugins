#!/usr/bin/env node

import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, win32 } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import {
  cmdShimCommandLine,
  javascriptEntryFromCmd,
  planTypescriptLaunch,
  resolveTypescriptEntry,
} from "./launch-typescript-language-server.mjs";

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

const lspManifest = JSON.parse(readFileSync(join(pluginRoot, ".lsp.json"), "utf8"));
const server = lspManifest.typescript;
check("lsp command is node", server?.command === "node", server?.command);
check(
  "lsp args name the bundled launcher and --stdio",
  Array.isArray(server?.args) &&
    server.args[0] === "${CLAUDE_PLUGIN_ROOT}/bin/launch-typescript-language-server.mjs" &&
    server.args[1] === "--stdio",
  JSON.stringify(server?.args),
);
check(
  "lsp command is not the npm shim name",
  server?.command !== "typescript-language-server",
);

const spaced = String.raw`C:\Program Files\npm\typescript-language-server.cmd`;
check(
  "cmd /s command line keeps a spaced shim quoted",
  cmdShimCommandLine(spaced, ["--stdio"]) ===
    `"${String.raw`"C:\Program Files\npm\typescript-language-server.cmd"`} --stdio"`,
);

const cmdBody =
  '@ECHO off\r\n"%_prog%"  "%dp0%\\node_modules\\typescript-language-server\\lib\\cli.mjs" %*\r\n';
check(
  "cmd shim text yields the JavaScript entry",
  javascriptEntryFromCmd(String.raw`D:\npm\typescript-language-server.cmd`, cmdBody) ===
    String.raw`D:\npm\node_modules\typescript-language-server\lib\cli.mjs`,
);

const files = new Map();
function touch(filePath, body = "") {
  files.set(filePath, body);
}
const isFile = (filePath) => files.has(filePath);
const readFile = (filePath) => {
  if (!files.has(filePath)) throw new Error(`missing ${filePath}`);
  return files.get(filePath);
};

const cli = win32.join(
  "C:\\fnm\\aliases\\default",
  "node_modules",
  "typescript-language-server",
  "lib",
  "cli.mjs",
);
touch(cli, "");
const fromLayout = resolveTypescriptEntry({
  pathEnv: "C:\\fnm\\aliases\\default",
  pathDelimiter: ";",
  pathApi: win32,
  env: {},
  home: "",
  isFile,
  readFile,
});
check("path layout prefers cli.mjs over a shim", fromLayout?.kind === "javascript" && fromLayout.file === cli);

files.clear();
const parsedCli = String.raw`D:\tools\typescript-language-server\lib\cli.mjs`;
touch(
  "C:\\npm\\typescript-language-server.cmd",
  `@ECHO off\r\n"%_prog%"  "${parsedCli}" %*\r\n`,
);
touch(parsedCli, "");
const fromCmd = resolveTypescriptEntry({
  pathEnv: "C:\\npm",
  pathDelimiter: ";",
  pathApi: win32,
  env: {},
  home: "",
  isFile,
  readFile,
});
check("cmd shim text resolves cli.mjs", fromCmd?.source === "cmd-shim-text" && fromCmd.file === parsedCli);

files.clear();
const stable = win32.join(
  "C:\\fnm-data",
  "fnm",
  "aliases",
  "default",
  "node_modules",
  "typescript-language-server",
  "lib",
  "cli.mjs",
);
touch(stable, "");
touch("C:\\ephemeral\\typescript-language-server.cmd", "@ECHO off\r\n");
const fromAlias = resolveTypescriptEntry({
  pathEnv: "C:\\ephemeral",
  pathDelimiter: ";",
  pathApi: win32,
  env: { APPDATA: "C:\\fnm-data" },
  home: "C:\\home",
  isFile,
  readFile,
});
check("stable fnm alias wins over an unparsed cmd", fromAlias?.source === "fnm-alias" && fromAlias.file === stable);

files.clear();
touch("C:\\only\\typescript-language-server.cmd", "@ECHO off\r\n");
const cmdOnly = resolveTypescriptEntry({
  pathEnv: "C:\\only",
  pathDelimiter: ";",
  pathApi: win32,
  env: {},
  home: "",
  isFile,
  readFile,
});
const winPlan = planTypescriptLaunch(cmdOnly, {
  userArgs: ["--stdio"],
  execPath: String.raw`C:\node\node.exe`,
  platform: "win32",
  comSpec: String.raw`C:\Windows\System32\cmd.exe`,
});
check("windows cmd fallback uses cmd.exe", winPlan.file === String.raw`C:\Windows\System32\cmd.exe`);
check("windows cmd fallback does not use a shell", winPlan.shell === false);
check(
  "windows cmd fallback passes /d /s /c and --stdio",
  JSON.stringify(winPlan.args) ===
    JSON.stringify([
      "/d",
      "/s",
      "/c",
      cmdShimCommandLine(String.raw`C:\only\typescript-language-server.cmd`, ["--stdio"]),
    ]),
  JSON.stringify(winPlan.args),
);

const nodePlan = planTypescriptLaunch(
  { kind: "javascript", file: "/opt/cli.mjs", source: "path-layout" },
  { userArgs: ["--stdio"], execPath: "/usr/bin/node", platform: "linux" },
);
check(
  "javascript plan spawns node.exe with the entry and --stdio",
  nodePlan.file === "/usr/bin/node" &&
    nodePlan.shell === false &&
    nodePlan.args[0] === "/opt/cli.mjs" &&
    nodePlan.args[1] === "--stdio",
);

const root = mkdtempSync(join(tmpdir(), "ts-lsp-"));
try {
  const fake = join(root, "cli.mjs");
  writeFileSync(
    fake,
    [
      "import { createInterface } from 'node:readline';",
      "const input = createInterface({ input: process.stdin });",
      "let buf = '';",
      "process.stdin.on('data', (chunk) => {",
      "  buf += chunk.toString('utf8');",
      "  const sep = buf.indexOf('\\r\\n\\r\\n');",
      "  if (sep === -1) return;",
      "  const header = buf.slice(0, sep);",
      "  const match = header.match(/Content-Length:\\s*(\\d+)/i);",
      "  if (!match) return;",
      "  const start = sep + 4;",
      "  const length = Number(match[1]);",
      "  if (Buffer.byteLength(buf.slice(start)) < length) return;",
      "  const body = JSON.stringify({ jsonrpc: '2.0', id: 1, result: { capabilities: { hoverProvider: true } } });",
      "  process.stdout.write(`Content-Length: ${Buffer.byteLength(body)}\\r\\n\\r\\n${body}`);",
      "});",
      "process.stderr.write('SPAWNED_BY_NODE\\n');",
    ].join("\n"),
  );
  const child = spawn(process.execPath, [join(here, "launch-typescript-language-server.mjs"), "--stdio"], {
    env: {
      ...process.env,
      TYPESCRIPT_LANGUAGE_SERVER_ENTRY: fake,
    },
    stdio: ["pipe", "pipe", "pipe"],
  });
  const request = JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: { processId: process.pid, capabilities: {} },
  });
  let stdout = Buffer.alloc(0);
  let stderr = "";
  child.stdout.on("data", (chunk) => {
    stdout = Buffer.concat([stdout, chunk]);
  });
  child.stderr.on("data", (chunk) => {
    stderr += chunk.toString("utf8");
  });
  child.stdin.write(`Content-Length: ${Buffer.byteLength(request)}\r\n\r\n${request}`);
  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      child.kill();
      reject(new Error(`timeout stdout=${stdout.toString("utf8")} stderr=${stderr}`));
    }, 5000);
    child.on("error", reject);
    child.stdout.on("data", () => {
      const text = stdout.toString("utf8");
      if (!text.includes("hoverProvider")) return;
      clearTimeout(timer);
      child.kill();
      resolve(text);
    });
  });
  check("launcher spawn answers initialize", result.includes("hoverProvider"), result);
  check("launcher spawn is the node entry, not a shell shim", stderr.includes("SPAWNED_BY_NODE"), stderr);
} catch (error) {
  fail("launcher spawn answers initialize", error.message);
} finally {
  rmSync(root, { recursive: true, force: true });
}

if (failed > 0) {
  console.error(`${failed} failed, ${passed} passed`);
  process.exit(1);
}
console.log(`${passed} passed`);
