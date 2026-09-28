#!/usr/bin/env node

// Spawn typescript-language-server without asking the parent to execute an
// npm .cmd shim. Claude Code starts the LSP `command` with no shell. On
// Windows that command is `node`, which CreateProcess resolves as node.exe.
// This process then finds lib/cli.mjs and re-spawns it with process.execPath.

import { spawn } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { delimiter, join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const ENTRY_SEGMENTS = [
  "node_modules",
  "typescript-language-server",
  "lib",
  "cli.mjs",
];

const SHIM_NAMES = [
  "typescript-language-server.cmd",
  "typescript-language-server.CMD",
  "typescript-language-server",
];

export function pathDirs(pathEnv, pathDelimiter = delimiter) {
  return String(pathEnv ?? "")
    .split(pathDelimiter)
    .map((part) => part.trim().replace(/^"(.*)"$/, "$1"))
    .filter(Boolean);
}

export function isRegularFile(filePath) {
  try {
    return statSync(filePath).isFile();
  } catch {
    return false;
  }
}

export function quoteForCmd(value) {
  const text = String(value);
  if (text.length === 0) return '""';
  if (!/[\s"&<>()@^|]/.test(text)) return text;
  return `"${text.replaceAll('"', '""')}"`;
}

// cmd.exe /s strips one outer quote pair. The extra pair keeps a path that
// contains spaces quoted after that strip. CreateProcessW documents that a
// batch file runs only when lpApplicationName is cmd.exe and lpCommandLine
// starts with /c plus the batch name.
export function cmdShimCommandLine(cmdPath, userArgs) {
  const parts = [quoteForCmd(cmdPath), ...userArgs.map(quoteForCmd)];
  return `"${parts.join(" ")}"`;
}

function parentDir(filePath) {
  const index = Math.max(filePath.lastIndexOf("/"), filePath.lastIndexOf("\\"));
  if (index <= 0) return filePath;
  return filePath.slice(0, index);
}

export function javascriptEntryFromCmd(cmdPath, text) {
  const cmdDir = parentDir(cmdPath);
  const expanded = String(text)
    .replaceAll(/%~dp0%/gi, cmdDir)
    .replaceAll(/%dp0%/gi, cmdDir);
  const quoted = [...expanded.matchAll(/"([^"]+\.(?:mjs|cjs|js))"/gi)].map(
    (match) => match[1],
  );
  const bare = [
    ...expanded.matchAll(/(?:^|[\s=])([^\s"]+\.(?:mjs|cjs|js))/gi),
  ].map((match) => match[1]);
  for (const candidate of [...quoted, ...bare]) {
    if (candidate.toLowerCase().includes("typescript-language-server")) {
      return candidate;
    }
  }
  return null;
}

export function stableAliasEntries(env, home, pathApi = { join }) {
  const roots = [];
  if (env.APPDATA) roots.push(pathApi.join(env.APPDATA, "fnm", "aliases", "default"));
  if (env.XDG_DATA_HOME) {
    roots.push(pathApi.join(env.XDG_DATA_HOME, "fnm", "aliases", "default"));
  }
  if (home) {
    roots.push(pathApi.join(home, ".local", "share", "fnm", "aliases", "default"));
    roots.push(
      pathApi.join(home, "Library", "Application Support", "fnm", "aliases", "default"),
    );
    roots.push(pathApi.join(home, "AppData", "Roaming", "fnm", "aliases", "default"));
  }
  return roots.map((root) => pathApi.join(root, ...ENTRY_SEGMENTS));
}

export function entryCandidatesForDir(dir, pathApi = { join }) {
  return [
    pathApi.join(dir, ...ENTRY_SEGMENTS),
    pathApi.join(dir, "..", "lib", ...ENTRY_SEGMENTS),
    pathApi.join(dir, "..", ...ENTRY_SEGMENTS),
  ];
}

export function resolveTypescriptEntry(options) {
  const fileExists = options.isFile ?? isRegularFile;
  const readFile = options.readFile ?? ((filePath) => readFileSync(filePath, "utf8"));
  const env = options.env ?? {};
  const override = env.TYPESCRIPT_LANGUAGE_SERVER_ENTRY;
  if (override && fileExists(override)) {
    return {
      kind: "javascript",
      file: override,
      source: "TYPESCRIPT_LANGUAGE_SERVER_ENTRY",
    };
  }

  const pathApi = options.pathApi ?? { join };
  const dirs = pathDirs(options.pathEnv ?? "", options.pathDelimiter ?? delimiter);
  for (const dir of dirs) {
    for (const candidate of entryCandidatesForDir(dir, pathApi)) {
      if (fileExists(candidate)) {
        return { kind: "javascript", file: candidate, source: "path-layout" };
      }
    }
  }

  let cmdFallback = null;
  for (const dir of dirs) {
    for (const name of SHIM_NAMES) {
      const shim = pathApi.join(dir, name);
      if (!fileExists(shim)) continue;
      const sibling = pathApi.join(dir, ...ENTRY_SEGMENTS);
      if (fileExists(sibling)) {
        return { kind: "javascript", file: sibling, source: "shim-sibling" };
      }
      if (!name.toLowerCase().endsWith(".cmd")) continue;
      let text = "";
      try {
        text = readFile(shim);
      } catch {
        text = "";
      }
      const parsed = text ? javascriptEntryFromCmd(shim, text) : null;
      if (parsed && fileExists(parsed)) {
        return { kind: "javascript", file: parsed, source: "cmd-shim-text" };
      }
      if (cmdFallback === null) cmdFallback = shim;
    }
  }

  for (const candidate of stableAliasEntries(env, options.home ?? "", pathApi)) {
    if (fileExists(candidate)) {
      return { kind: "javascript", file: candidate, source: "fnm-alias" };
    }
  }

  if (cmdFallback) return { kind: "cmd", file: cmdFallback, source: "cmd-fallback" };
  return null;
}

export function planTypescriptLaunch(resolved, options) {
  const userArgs = options.userArgs ?? [];
  if (!resolved) {
    return {
      error:
        "typescript-language-server entry not found. Install with: npm install -g typescript-language-server typescript",
    };
  }
  if (resolved.kind === "javascript") {
    return {
      file: options.execPath,
      args: [resolved.file, ...userArgs],
      shell: false,
      source: resolved.source,
    };
  }
  if (resolved.kind === "cmd" && options.platform === "win32") {
    return {
      file: options.comSpec || "cmd.exe",
      args: ["/d", "/s", "/c", cmdShimCommandLine(resolved.file, userArgs)],
      shell: false,
      source: resolved.source,
    };
  }
  return {
    error: `cannot spawn ${resolved.file} without a shell on ${options.platform}`,
  };
}

function isDirectRun() {
  const entry = process.argv[1];
  if (!entry) return false;
  return import.meta.url === pathToFileURL(entry).href;
}

function installHint() {
  return "Install with: npm install -g typescript-language-server typescript";
}

if (isDirectRun()) {
  const resolved = resolveTypescriptEntry({
    pathEnv: process.env.PATH,
    env: process.env,
    home: process.env.HOME || process.env.USERPROFILE || "",
  });
  const plan = planTypescriptLaunch(resolved, {
    userArgs: process.argv.slice(2),
    execPath: process.execPath,
    platform: process.platform,
    comSpec: process.env.ComSpec,
  });
  if (plan.error) {
    console.error(plan.error);
    console.error(installHint());
    process.exit(1);
  }
  const child = spawn(plan.file, plan.args, {
    stdio: "inherit",
    shell: false,
    windowsHide: true,
  });
  child.on("error", (error) => {
    console.error(error.message);
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

