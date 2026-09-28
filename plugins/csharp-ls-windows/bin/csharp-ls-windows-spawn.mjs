import { spawn } from "node:child_process";
import { closeSync, openSync, readSync, statSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const CMD_EXT = new Set([".cmd", ".bat", ".ps1"]);

function pathApi(platform) {
  return platform === "win32" ? path.win32 : path.posix;
}

function splitPath(pathValue, platform) {
  const sep = platform === "win32" ? ";" : ":";
  return String(pathValue ?? "")
    .split(sep)
    .filter((part) => part.length > 0);
}

function extensionOf(file, platform) {
  return pathApi(platform).extname(file).toLowerCase();
}

export function isCmdShimName(file, platform) {
  return CMD_EXT.has(extensionOf(file, platform));
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

function nativeKind(kind, platform) {
  if (platform === "win32") return kind === "pe";
  return kind === "elf" || kind === "macho" || kind === "pe" || kind === "script";
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

function defaultToolsDir(env, platform, api) {
  const home = platform === "win32" ? env.USERPROFILE || env.HOME : env.HOME || env.USERPROFILE;
  if (!home) return null;
  return api.join(home, ".dotnet", "tools");
}

function nonEmpty(value) {
  return typeof value === "string" && value.length > 0;
}

function resolveDotnetRoot({ platform, env, dirs, exists, readHead, api }) {
  if (nonEmpty(env.DOTNET_ROOT)) return { value: env.DOTNET_ROOT, source: "env" };
  const names = platform === "win32" ? ["dotnet.exe"] : ["dotnet"];
  for (const dir of dirs) {
    for (const name of names) {
      const candidate = api.join(dir, name);
      if (!exists(candidate) || isCmdShimName(candidate, platform)) continue;
      const kind = classifyHead(readHead(candidate));
      if (!nativeKind(kind, platform)) continue;
      return { value: api.dirname(candidate), source: "dotnet-host" };
    }
  }
  return { value: null, source: "unset" };
}

export function planCsharpLs({
  platform = process.platform,
  env = process.env,
  exists = defaultExists,
  readHead = defaultReadHead,
} = {}) {
  const api = pathApi(platform);
  const dirs = splitPath(env.PATH, platform);
  const toolsDir = defaultToolsDir(env, platform, api);
  const toolsDirOnPath =
    toolsDir != null && dirs.some((dir) => sameDir(dir, toolsDir, platform, api));
  const rejected = [];
  let selected = null;
  const names = platform === "win32" ? ["csharp-ls.exe"] : ["csharp-ls"];
  const shimNames = ["csharp-ls.cmd", "csharp-ls.bat", "csharp-ls.ps1"];
  for (const dir of dirs) {
    for (const shim of shimNames) {
      const candidate = api.join(dir, shim);
      if (exists(candidate)) rejected.push(candidate);
    }
    if (selected) continue;
    for (const name of names) {
      const candidate = api.join(dir, name);
      if (!exists(candidate) || isCmdShimName(candidate, platform)) continue;
      const kind = classifyHead(readHead(candidate));
      if (nativeKind(kind, platform)) {
        selected = { binary: candidate, kind };
        break;
      }
      rejected.push(candidate);
    }
  }
  const dotnet = resolveDotnetRoot({ platform, env, dirs, exists, readHead, api });
  const childEnv = { ...env };
  if (!nonEmpty(childEnv.DOTNET_ROOT) && dotnet.source === "dotnet-host" && dotnet.value) {
    childEnv.DOTNET_ROOT = dotnet.value;
  }
  const dotnetRoot = nonEmpty(childEnv.DOTNET_ROOT) ? childEnv.DOTNET_ROOT : null;
  const dotnetRootSource = nonEmpty(env.DOTNET_ROOT)
    ? "env"
    : dotnet.source === "dotnet-host"
      ? "dotnet-host"
      : "unset";
  if (!selected) {
    const reason =
      rejected.length > 0
        ? "csharp-ls on PATH is not a native executable. A .cmd shim is not spawned."
        : "csharp-ls is not on PATH. Add the dotnet global tools directory to PATH.";
    return {
      status: "blocked",
      reason,
      command: null,
      args: [],
      shell: false,
      kind: null,
      binary: null,
      toolsDir,
      toolsDirOnPath,
      dotnetRoot,
      dotnetRootSource,
      env: childEnv,
      rejected,
    };
  }
  return {
    status: "ready",
    reason: null,
    command: selected.binary,
    args: [],
    shell: false,
    kind: selected.kind,
    binary: selected.binary,
    toolsDir,
    toolsDirOnPath,
    dotnetRoot,
    dotnetRootSource,
    env: childEnv,
    rejected,
  };
}

function report(plan) {
  return {
    status: plan.status,
    reason: plan.reason,
    command: plan.command,
    args: plan.args,
    shell: plan.shell,
    kind: plan.kind,
    binary: plan.binary,
    toolsDir: plan.toolsDir,
    toolsDirOnPath: plan.toolsDirOnPath,
    dotnetRoot: plan.dotnetRoot,
    dotnetRootSource: plan.dotnetRootSource,
    rejected: plan.rejected,
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

function main() {
  const probe = process.argv.includes("--probe");
  const plan = planCsharpLs();
  if (probe) {
    process.stdout.write(`${JSON.stringify(report(plan), null, 2)}\n`);
    process.exit(plan.status === "ready" ? 0 : 2);
  }
  if (plan.status !== "ready" || plan.shell !== false || !plan.command) {
    process.stderr.write(`csharp-ls-windows: ${plan.reason}\n`);
    process.exit(1);
  }
  if (isCmdShimName(plan.command, process.platform)) {
    process.stderr.write("csharp-ls-windows: refusing to spawn a .cmd shim\n");
    process.exit(1);
  }
  const child = spawn(plan.command, plan.args, {
    env: plan.env,
    shell: false,
    stdio: "inherit",
    windowsHide: true,
  });
  child.on("error", (error) => {
    process.stderr.write(`csharp-ls-windows: ${error.message}\n`);
    process.exit(1);
  });
  child.on("exit", (code, signal) => {
    if (signal) {
      process.kill(process.pid, signal);
      return;
    }
    process.exit(code ?? 1);
  });
}

if (invokedDirectly()) main();
