#!/usr/bin/env node

// Spawn csharp-ls, the native dotnet-tool apphost, and set DOTNET_ROOT when
// the parent environment does not. Claude Code starts language servers with
// no shell and no profile, so a global tool can be missing from PATH and an
// apphost can exit before it writes any LSP bytes.

import { spawn } from "node:child_process";
import { statSync } from "node:fs";
import { delimiter, join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const TOOL_NAMES = ["csharp-ls.exe", "csharp-ls.EXE", "csharp-ls"];

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

function parentDir(filePath) {
  const index = Math.max(filePath.lastIndexOf("/"), filePath.lastIndexOf("\\"));
  if (index <= 0) return filePath;
  return filePath.slice(0, index);
}

function isBatch(filePath) {
  return /\.(cmd|bat)$/i.test(filePath);
}

export function dotnetToolDirs(env, home, pathApi) {
  const dirs = [];
  if (env.DOTNET_CLI_HOME) dirs.push(pathApi.join(env.DOTNET_CLI_HOME, "tools"));
  if (home) dirs.push(pathApi.join(home, ".dotnet", "tools"));
  if (env.USERPROFILE) dirs.push(pathApi.join(env.USERPROFILE, ".dotnet", "tools"));
  return dirs;
}

export function defaultDotnetHosts(env, home, pathApi) {
  const hosts = [];
  if (env.DOTNET_ROOT) hosts.push(pathApi.join(env.DOTNET_ROOT, "dotnet"));
  if (env.ProgramFiles) hosts.push(pathApi.join(env.ProgramFiles, "dotnet", "dotnet.exe"));
  if (env["ProgramFiles(x86)"]) {
    hosts.push(pathApi.join(env["ProgramFiles(x86)"], "dotnet", "dotnet.exe"));
  }
  hosts.push("/usr/share/dotnet/dotnet", "/usr/lib/dotnet/dotnet");
  if (home) hosts.push(pathApi.join(home, ".dotnet", "dotnet"));
  if (env.USERPROFILE) hosts.push(pathApi.join(env.USERPROFILE, ".dotnet", "dotnet.exe"));
  return hosts;
}

export function resolveCsharpLs(options) {
  const fileExists = options.isFile ?? isRegularFile;
  const pathApi = options.pathApi ?? { join };
  const env = options.env ?? {};
  const override = env.CSHARPLS_PATH;
  if (override) {
    if (!fileExists(override)) {
      return { error: `CSHARPLS_PATH does not exist: ${override}` };
    }
    if (isBatch(override)) {
      return { error: `CSHARPLS_PATH is a batch shim, not the csharp-ls apphost: ${override}` };
    }
    return { file: override, source: "CSHARPLS_PATH" };
  }

  const dirs = [
    ...pathDirs(options.pathEnv ?? "", options.pathDelimiter ?? delimiter),
    ...dotnetToolDirs(env, options.home ?? "", pathApi),
  ];
  for (const dir of dirs) {
    for (const name of TOOL_NAMES) {
      const candidate = pathApi.join(dir, name);
      if (!fileExists(candidate) || isBatch(candidate)) continue;
      return { file: candidate, source: "resolved" };
    }
  }
  return {
    error:
      "csharp-ls was not found. Install with: dotnet tool install --global csharp-ls",
  };
}

export function resolveDotnetRoot(options) {
  const fileExists = options.isFile ?? isRegularFile;
  const pathApi = options.pathApi ?? { join };
  const env = options.env ?? {};
  if (env.DOTNET_ROOT) return { value: env.DOTNET_ROOT, source: "DOTNET_ROOT" };

  const names = ["dotnet.exe", "dotnet.EXE", "dotnet"];
  for (const dir of pathDirs(options.pathEnv ?? "", options.pathDelimiter ?? delimiter)) {
    for (const name of names) {
      const candidate = pathApi.join(dir, name);
      if (fileExists(candidate)) return { value: parentDir(candidate), source: "dotnet-on-path" };
    }
  }
  for (const candidate of defaultDotnetHosts(env, options.home ?? "", pathApi)) {
    if (fileExists(candidate)) return { value: parentDir(candidate), source: "dotnet-default" };
  }
  return null;
}

export function planCsharpLaunch(resolved, dotnetRoot, options) {
  if (resolved.error) return { error: resolved.error };
  const env = { ...(options.env ?? {}) };
  if (dotnetRoot && !env.DOTNET_ROOT) env.DOTNET_ROOT = dotnetRoot.value;
  if (
    options.platform === "win32" &&
    options.arch === "x64" &&
    dotnetRoot &&
    !env.DOTNET_ROOT_X64
  ) {
    env.DOTNET_ROOT_X64 = dotnetRoot.value;
  }
  return {
    file: resolved.file,
    args: options.userArgs ?? [],
    env,
    shell: false,
    source: resolved.source,
    dotnetRootSource: dotnetRoot?.source ?? "unset",
  };
}

function isDirectRun() {
  const entry = process.argv[1];
  if (!entry) return false;
  return import.meta.url === pathToFileURL(entry).href;
}

if (isDirectRun()) {
  const home = process.env.HOME || process.env.USERPROFILE || "";
  const resolved = resolveCsharpLs({
    pathEnv: process.env.PATH,
    env: process.env,
    home,
  });
  const dotnetRoot = resolveDotnetRoot({
    pathEnv: process.env.PATH,
    env: process.env,
    home,
  });
  const plan = planCsharpLaunch(resolved, dotnetRoot, {
    userArgs: process.argv.slice(2),
    env: process.env,
    platform: process.platform,
    arch: process.arch,
  });
  if (plan.error) {
    console.error(plan.error);
    process.exit(1);
  }
  const child = spawn(plan.file, plan.args, {
    stdio: "inherit",
    env: plan.env,
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
