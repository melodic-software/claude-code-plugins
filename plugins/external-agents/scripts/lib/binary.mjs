import { accessSync, constants, statSync } from "node:fs";
import { delimiter, join, posix, win32 } from "node:path";

const isFile = (path) => {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
};

/** A file this user can run: Windows runs any file with a PATHEXT extension, POSIX needs the execute bit. */
const isRunnable = (path, windows) => {
  if (!isFile(path)) return false;
  if (windows) return true;
  try {
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
};

const expand = (template, env) => {
  let missing = false;
  const path = template.replace(/\{([A-Z_][A-Z0-9_]*)\}/g, (_, name) => {
    if (!env[name]) missing = true;
    return env[name] ?? "";
  });
  return missing ? null : path;
};

const found = (path, source, tried) => ({ path, source, tried, shell: /\.(cmd|bat)$/i.test(path) });

export function resolveBinary(record, { binaryPath, platform = process.platform, env = process.env } = {}) {
  const tried = [];
  if (binaryPath) {
    tried.push(binaryPath);
    return isFile(binaryPath) ? found(binaryPath, "binary_path", tried) : { path: null, source: null, tried, shell: false };
  }
  const windows = platform === "win32";
  const joinPath = windows ? win32.join : join;
  for (const template of record.binary.candidates?.[platform] ?? []) {
    const path = expand(template, env);
    if (!path) continue;
    const normalized = windows ? win32.normalize(path) : path;
    tried.push(normalized);
    if (isRunnable(normalized, windows)) return found(normalized, "candidate", tried);
  }
  const exts = windows ? (env.PATHEXT || ".EXE;.CMD;.BAT").split(";").filter(Boolean) : [""];
  const isAbsoluteDir = (windows ? win32 : posix).isAbsolute;
  for (const dir of (env.PATH ?? env.Path ?? "").split(windows ? ";" : delimiter).filter(isAbsoluteDir)) {
    for (const ext of exts) {
      const path = joinPath(dir, record.binary.name + ext.toLowerCase());
      if (isRunnable(path, windows)) return found(path, "PATH", [...tried, `PATH (${record.binary.name})`]);
    }
  }
  tried.push(`PATH (${record.binary.name})`);
  return { path: null, source: null, tried, shell: false };
}

export const unavailableMessage = (record, result) =>
  `${record.product}: unavailable: ${record.binary.name} not found (tried ${result.tried.join(", ")}). ` +
  `Install it, or set ${record.product}.binary_path, then run: external-agents update ${record.product}`;
