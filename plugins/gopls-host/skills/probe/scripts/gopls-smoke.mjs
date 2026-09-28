import { execFileSync, spawn } from "node:child_process";
import { closeSync, mkdtempSync, openSync, readSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

const SOURCE = "package p\n\nfunc Target() int { return 1 }\n\nfunc Use() int { return Target() }\n";

function pathApi(platform) {
  return platform === "win32" ? path.win32 : path.posix;
}

function splitPath(pathValue, platform) {
  const sep = platform === "win32" ? ";" : ":";
  return String(pathValue ?? "")
    .split(sep)
    .filter((part) => part.length > 0);
}

function nonEmpty(value) {
  return typeof value === "string" && value.length > 0;
}

export function classifyHead(buf) {
  if (!buf || buf.length < 2) return "unknown";
  if (buf[0] === 0x4d && buf[1] === 0x5a) return "pe";
  if (
    buf.length >= 4 &&
    buf[0] === 0x7f &&
    buf[1] === 0x45 &&
    buf[2] === 0x4c &&
    buf[3] === 0x46
  ) {
    return "elf";
  }
  if (buf.length >= 4) {
    const be = buf.readUInt32BE(0);
    const le = buf.readUInt32LE(0);
    const machos = new Set([0xfeedface, 0xfeedfacf, 0xcafebabe, 0xcafebabf]);
    if (machos.has(be) || machos.has(le)) return "macho";
  }
  if (buf[0] === 0x23 && buf[1] === 0x21) return "script";
  return "other";
}

function isNative(kind) {
  return kind === "pe" || kind === "elf" || kind === "macho";
}

function isCmdShimName(file, platform) {
  const ext = pathApi(platform).extname(file).toLowerCase();
  return ext === ".cmd" || ext === ".bat" || ext === ".ps1";
}

function defaultExists(file) {
  try {
    return statSync(file).isFile();
  } catch {
    return false;
  }
}

function defaultReadHead(file) {
  const fd = openSync(file, "r");
  try {
    const buf = Buffer.alloc(8);
    const n = readSync(fd, buf, 0, 8, 0);
    return buf.subarray(0, n);
  } finally {
    closeSync(fd);
  }
}

function sameDir(left, right, platform, api) {
  const a = api.normalize(left);
  const b = api.normalize(right);
  if (platform === "win32") return a.toLowerCase() === b.toLowerCase();
  return a === b;
}

export function resolveInstallDir(env, goEnv, platform) {
  const api = pathApi(platform);
  const gobin = nonEmpty(goEnv.GOBIN) ? goEnv.GOBIN : nonEmpty(env.GOBIN) ? env.GOBIN : "";
  if (gobin) return gobin;
  const gopathRaw = nonEmpty(goEnv.GOPATH) ? goEnv.GOPATH : nonEmpty(env.GOPATH) ? env.GOPATH : "";
  if (gopathRaw) {
    const sep = platform === "win32" ? ";" : ":";
    return api.join(gopathRaw.split(sep)[0], "bin");
  }
  const home = platform === "win32" ? env.USERPROFILE || env.HOME : env.HOME || env.USERPROFILE;
  if (!home) return null;
  return api.join(home, "go", "bin");
}

function consider(dir, names, platform, exists, readHead, api) {
  for (const name of names) {
    const candidate = api.join(dir, name);
    if (!exists(candidate) || isCmdShimName(candidate, platform)) continue;
    const kind = classifyHead(readHead(candidate));
    if (isNative(kind)) return { binary: candidate, kind };
  }
  return null;
}

export function planGopls({
  platform = process.platform,
  env = process.env,
  goEnv = {},
  exists = defaultExists,
  readHead = defaultReadHead,
} = {}) {
  const api = pathApi(platform);
  const names = platform === "win32" ? ["gopls.exe"] : ["gopls"];
  const shimNames = ["gopls.cmd", "gopls.bat", "gopls.ps1"];
  const dirs = splitPath(env.PATH, platform);
  const installDir = resolveInstallDir(env, goEnv, platform);
  const rejected = [];
  const noteShim = (dir) => {
    for (const shim of shimNames) {
      const candidate = api.join(dir, shim);
      if (exists(candidate)) rejected.push(candidate);
    }
  };
  let onPath = null;
  for (const dir of dirs) {
    noteShim(dir);
    if (!onPath) onPath = consider(dir, names, platform, exists, readHead, api);
  }
  let installed = null;
  if (installDir) {
    noteShim(installDir);
    installed = consider(installDir, names, platform, exists, readHead, api);
  }
  const installOnPath =
    installDir != null && dirs.some((dir) => sameDir(dir, installDir, platform, api));
  const binary = onPath?.binary ?? installed?.binary ?? null;
  const kind = onPath?.kind ?? installed?.kind ?? null;
  let reason = null;
  if (!onPath && installed) {
    reason =
      "gopls is a native executable in the go install directory, and that directory is not on PATH.";
  } else if (!onPath && rejected.length > 0) {
    reason = "gopls on PATH is not a native executable. A .cmd shim is not spawned.";
  } else if (!onPath) {
    reason =
      "gopls is not on PATH. Install with go install golang.org/x/tools/gopls@latest and put GOBIN or GOPATH/bin on PATH.";
  }
  return {
    status: onPath ? "ready" : "blocked",
    reason,
    command: onPath ? onPath.binary : null,
    args: onPath ? ["serve"] : [],
    shell: false,
    binary,
    kind,
    onPath: Boolean(onPath),
    installDir,
    installOnPath,
    gobin: nonEmpty(goEnv.GOBIN) ? goEnv.GOBIN : env.GOBIN || "",
    gopath: nonEmpty(goEnv.GOPATH) ? goEnv.GOPATH : env.GOPATH || "",
    rejected,
  };
}

function encode(message) {
  const body = Buffer.from(JSON.stringify(message));
  return Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`), body]);
}

function attach(child) {
  let buf = Buffer.alloc(0);
  const pending = new Map();
  child.stdout.on("data", (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      const headerEnd = buf.indexOf("\r\n\r\n");
      if (headerEnd < 0) return;
      const header = buf.slice(0, headerEnd).toString("utf8");
      const match = /Content-Length: (\d+)/i.exec(header);
      if (!match) throw new Error(`bad LSP header: ${header}`);
      const length = Number(match[1]);
      const start = headerEnd + 4;
      if (buf.length < start + length) return;
      const message = JSON.parse(buf.slice(start, start + length).toString("utf8"));
      buf = buf.slice(start + length);
      if (message.id != null && pending.has(message.id)) pending.get(message.id)(message);
    }
  });
  let id = 0;
  return {
    request(method, params, timeoutMs) {
      const mine = ++id;
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          pending.delete(mine);
          reject(new Error(`timeout ${method}`));
        }, timeoutMs);
        pending.set(mine, (message) => {
          clearTimeout(timer);
          pending.delete(mine);
          resolve(message);
        });
        child.stdin.write(encode({ jsonrpc: "2.0", id: mine, method, params }));
      });
    },
    notify(method, params) {
      const message = { jsonrpc: "2.0", method };
      if (params !== undefined) message.params = params;
      child.stdin.write(encode(message));
    },
  };
}

function hasHover(result) {
  return Boolean(result && result.contents != null);
}

function hasLocations(result, minimum) {
  if (Array.isArray(result)) return result.length >= minimum;
  if (result && (result.uri || result.targetUri)) return minimum <= 1;
  return false;
}

export async function runLspSmoke(binary, { settleMs = 0, timeoutMs = 20000 } = {}) {
  const root = mkdtempSync(path.join(tmpdir(), "gopls-smoke-"));
  writeFileSync(path.join(root, "go.mod"), "module example.com/p\n\ngo 1.22\n");
  writeFileSync(path.join(root, "p.go"), SOURCE);
  const child = spawn(binary, ["serve"], {
    cwd: root,
    shell: false,
    stdio: ["pipe", "pipe", "pipe"],
  });
  const killer = setTimeout(() => child.kill("SIGKILL"), timeoutMs);
  const outcome = {
    ok: false,
    hover: false,
    definition: false,
    references: false,
    error: null,
  };
  try {
    const rpc = attach(child);
    const uri = pathToFileURL(path.join(root, "p.go")).href;
    const rootUri = pathToFileURL(root).href;
    const init = await rpc.request(
      "initialize",
      {
        processId: process.pid,
        rootUri,
        capabilities: {},
        workspaceFolders: [{ uri: rootUri, name: "p" }],
      },
      timeoutMs,
    );
    if (!init.result) {
      outcome.error = "initialize failed";
      return outcome;
    }
    rpc.notify("initialized", {});
    rpc.notify("textDocument/didOpen", {
      textDocument: { uri, languageId: "go", version: 1, text: SOURCE },
    });
    if (settleMs > 0) await new Promise((resolve) => setTimeout(resolve, settleMs));
    const hover = await rpc.request(
      "textDocument/hover",
      { textDocument: { uri }, position: { line: 2, character: 5 } },
      timeoutMs,
    );
    const definition = await rpc.request(
      "textDocument/definition",
      { textDocument: { uri }, position: { line: 4, character: 24 } },
      timeoutMs,
    );
    const references = await rpc.request(
      "textDocument/references",
      {
        textDocument: { uri },
        position: { line: 2, character: 5 },
        context: { includeDeclaration: true },
      },
      timeoutMs,
    );
    outcome.hover = hasHover(hover.result);
    outcome.definition = hasLocations(definition.result, 1);
    outcome.references = hasLocations(references.result, 2);
    outcome.ok = outcome.hover && outcome.definition && outcome.references;
    await rpc.request("shutdown", null, timeoutMs);
    rpc.notify("exit");
    return outcome;
  } catch (error) {
    outcome.error = error instanceof Error ? error.message : String(error);
    return outcome;
  } finally {
    clearTimeout(killer);
    if (child.exitCode == null && child.signalCode == null) child.kill("SIGTERM");
  }
}

export function readGoEnv() {
  try {
    const out = execFileSync("go", ["env", "GOBIN", "GOPATH"], {
      encoding: "utf8",
      shell: false,
      timeout: 10000,
    });
    const lines = out.split(/\r?\n/);
    return { GOBIN: (lines[0] ?? "").trim(), GOPATH: (lines[1] ?? "").trim() };
  } catch {
    return { GOBIN: process.env.GOBIN || "", GOPATH: process.env.GOPATH || "" };
  }
}

function report(plan, lsp) {
  return {
    status: plan.status,
    reason: plan.reason,
    command: plan.command,
    args: plan.args,
    shell: plan.shell,
    binary: plan.binary,
    kind: plan.kind,
    onPath: plan.onPath,
    installDir: plan.installDir,
    installOnPath: plan.installOnPath,
    gobin: plan.gobin,
    gopath: plan.gopath,
    rejected: plan.rejected,
    lsp: lsp ?? null,
  };
}

function invokedDirectly() {
  const entry = process.argv[1];
  if (!entry) return false;
  try {
    return path.resolve(entry) === fileURLToPath(import.meta.url);
  } catch {
    return false;
  }
}

async function main() {
  const lsp = process.argv.includes("--lsp");
  const plan = planGopls({ goEnv: readGoEnv() });
  if (!lsp) {
    process.stdout.write(`${JSON.stringify(report(plan), null, 2)}\n`);
    process.exit(plan.status === "ready" ? 0 : 2);
  }
  if (!plan.binary) {
    process.stdout.write(`${JSON.stringify(report(plan), null, 2)}\n`);
    process.exit(2);
  }
  const smoked = await runLspSmoke(plan.binary, { settleMs: 1500, timeoutMs: 20000 });
  process.stdout.write(`${JSON.stringify(report(plan, smoked), null, 2)}\n`);
  process.exit(smoked.ok ? 0 : 1);
}

if (invokedDirectly()) {
  main().catch((error) => {
    process.stderr.write(`gopls-smoke: ${error instanceof Error ? error.message : String(error)}\n`);
    process.exit(1);
  });
}
