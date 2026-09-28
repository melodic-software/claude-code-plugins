import { spawn } from "node:child_process";
import { closeSync, openSync, readFileSync, readSync, statSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const CMD_EXT = new Set([".cmd", ".bat", ".ps1"]);

function pathApi(platform) {
  return platform === "win32" ? path.win32 : path.posix;
}

// Relative entries resolve against the workspace, which a cloned repository controls.
function splitPath(pathValue, platform) {
  const sep = platform === "win32" ? ";" : ":";
  return String(pathValue ?? "")
    .split(sep)
    .filter((part) => part.length > 0 && pathApi(platform).isAbsolute(part));
}

export function isCmdShimName(file, platform) {
  return CMD_EXT.has(pathApi(platform).extname(file).toLowerCase());
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

function defaultReadText(file) {
  return readFileSync(file, "utf8");
}

function wrapperNames(platform) {
  return platform === "win32" ? ["typescript-language-server.exe"] : ["typescript-language-server"];
}

function cliCandidates(dir, api) {
  const lib = ["typescript-language-server", "lib"];
  return [
    api.join(dir, "node_modules", ...lib, "cli.mjs"),
    api.join(dir, "node_modules", ...lib, "cli.js"),
    api.join(api.dirname(dir), "lib", "node_modules", ...lib, "cli.mjs"),
    api.join(api.dirname(dir), "lib", "node_modules", ...lib, "cli.js"),
  ];
}

function cliFromText(text, dir, api, exists) {
  if (!text) return null;
  const replaced = text.replaceAll("%~dp0", dir).replaceAll("%dp0%", dir);
  const matches = replaced.match(/[^\s"'<>|]+cli\.m?js/gi) || [];
  for (const raw of matches) {
    const candidate = api.isAbsolute(raw) ? raw : api.resolve(dir, raw);
    if (exists(candidate) && !isCmdShimName(candidate, api === path.win32 ? "win32" : "posix")) {
      return candidate;
    }
  }
  return null;
}

function acceptableWrapper(kind, platform) {
  if (platform === "win32") return kind === "pe";
  return kind === "elf" || kind === "macho" || kind === "pe" || kind === "script";
}

function withStdio(args) {
  return args.includes("--stdio") ? args : [...args, "--stdio"];
}

export function planTypescriptLanguageServer({
  platform = process.platform,
  env = process.env,
  execPath = process.execPath,
  exists = defaultExists,
  readHead = defaultReadHead,
  readText = defaultReadText,
  extraArgs = [],
} = {}) {
  const api = pathApi(platform);
  const dirs = splitPath(env.PATH, platform);
  if (platform === "win32" && env.APPDATA) dirs.push(api.join(env.APPDATA, "npm"));
  if (execPath) {
    const nodeDir = api.dirname(execPath);
    dirs.push(nodeDir);
    dirs.push(api.dirname(nodeDir));
  }
  const rejected = [];
  let wrapper = null;
  let cli = null;
  const shimNames = [
    "typescript-language-server.cmd",
    "typescript-language-server.bat",
    "typescript-language-server.ps1",
  ];
  for (const dir of dirs) {
    for (const shim of shimNames) {
      const candidate = api.join(dir, shim);
      if (!exists(candidate)) continue;
      rejected.push(candidate);
      if (!cli) cli = cliFromText(readText(candidate), dir, api, exists);
    }
    if (!cli) {
      for (const candidate of cliCandidates(dir, api)) {
        if (exists(candidate)) {
          cli = candidate;
          break;
        }
      }
    }
    if (!wrapper) {
      for (const name of wrapperNames(platform)) {
        const candidate = api.join(dir, name);
        if (!exists(candidate) || isCmdShimName(candidate, platform)) continue;
        const kind = classifyHead(readHead(candidate));
        if (acceptableWrapper(kind, platform)) {
          wrapper = { command: candidate, kind };
          break;
        }
        rejected.push(candidate);
      }
    }
  }
  if (wrapper) {
    return {
      status: "ready",
      reason: null,
      mode: "path-executable",
      command: wrapper.command,
      args: withStdio(extraArgs),
      shell: false,
      kind: wrapper.kind,
      cli: null,
      rejected,
    };
  }
  if (cli && execPath && !isCmdShimName(execPath, platform)) {
    return {
      status: "ready",
      reason: null,
      mode: "node-cli",
      command: execPath,
      args: withStdio([cli, ...extraArgs]),
      shell: false,
      kind: "node",
      cli,
      rejected,
    };
  }
  const reason =
    rejected.length > 0
      ? "typescript-language-server on PATH is only a .cmd shim and lib/cli.mjs was not found."
      : "typescript-language-server was not found. Install the npm package and use node plus lib/cli.mjs.";
  return {
    status: "blocked",
    reason,
    mode: null,
    command: null,
    args: [],
    shell: false,
    kind: null,
    cli: null,
    rejected,
  };
}

function report(plan) {
  return {
    status: plan.status,
    reason: plan.reason,
    mode: plan.mode,
    command: plan.command,
    args: plan.args,
    shell: plan.shell,
    kind: plan.kind,
    cli: plan.cli,
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
  const extraArgs = process.argv.slice(2).filter((arg) => arg !== "--probe");
  const plan = planTypescriptLanguageServer({ extraArgs: probe ? [] : extraArgs });
  if (probe) {
    process.stdout.write(`${JSON.stringify(report(plan), null, 2)}\n`);
    process.exit(plan.status === "ready" ? 0 : 2);
  }
  if (plan.status !== "ready" || plan.shell !== false || !plan.command) {
    process.stderr.write(`typescript-lsp-stdio: ${plan.reason}\n`);
    process.exit(1);
  }
  if (isCmdShimName(plan.command, process.platform)) {
    process.stderr.write("typescript-lsp-stdio: refusing to spawn a .cmd shim\n");
    process.exit(1);
  }
  const child = spawn(plan.command, plan.args, {
    shell: false,
    stdio: "inherit",
    windowsHide: true,
  });
  child.on("error", (error) => {
    process.stderr.write(`typescript-lsp-stdio: ${error.message}\n`);
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
