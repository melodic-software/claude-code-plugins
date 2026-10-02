// What src/launch.ts, the entry point Claude Code starts, runs. Installs the server's npm
// dependencies from the committed lockfile into ${CLAUDE_PLUGIN_DATA} on first launch, then
// runs the TypeScript source with Node's type stripping.
// Rules: docs/conventions/on-demand-dependencies/README.md.
//
// Layout under the data directory:
//   mcp-server/<lock hash>/node_modules   runtime dependencies, from `npm ci --omit=dev`
//   mcp-server/<lock hash>/app-<hash>     a copy of src/ plus the current package.json, keyed
//                                         by both; Node resolves its imports from the
//                                         node_modules above it
// Both are built in a `.partial-<pid>` sibling and renamed into place, so an interrupted run
// leaves nothing that looks complete and concurrent first launches end with one good copy.
// Nothing here writes to stdout: it is the MCP stdio channel.

import { type SpawnSyncOptionsWithStringEncoding, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, relative } from "node:path";
import { pathToFileURL } from "node:url";

const SRC_DIR = import.meta.dirname;
const SERVER_DIR = dirname(SRC_DIR);
const MANIFESTS = ["package.json", "package-lock.json"] as const;
const NPM_CI_ARGS = ["ci", "--omit=dev", "--ignore-scripts", "--no-audit", "--no-fund"];
const NPM_TIMEOUT_MS = 600_000;
const STALE_PARTIAL_MS = 2 * NPM_TIMEOUT_MS;
const LINE_BREAK = /\r?\n/;

export class LaunchBroken extends Error {
  readonly command: string | undefined;

  constructor(reason: string, command?: string) {
    super(command ? `${reason}\nRepair with: ${command}` : reason);
    this.command = command;
  }
}

const digest = (parts: readonly (string | Buffer)[]): string => {
  const hash = createHash("sha256");
  for (const part of parts) hash.update(part);
  return hash.digest("hex").slice(0, 12);
};

const isRuntimeSource = (path: string): boolean =>
  !path.endsWith(".test.ts") && !relative(SRC_DIR, path).startsWith("test-support");

function runtimeSources(dir = SRC_DIR): string[] {
  return readdirSync(dir, { withFileTypes: true })
    .flatMap((entry) => {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) return runtimeSources(path);
      return entry.name.endsWith(".ts") && isRuntimeSource(path) ? [path] : [];
    })
    .sort();
}

export function installDir(dataDir: string): string {
  return join(dataDir, "mcp-server", digest([readFileSync(join(SERVER_DIR, "package-lock.json"))]));
}

const currentManifest = (): Buffer => readFileSync(join(SERVER_DIR, "package.json"));

// The source copy carries its own package.json, so Node reads the package scope (`type`,
// `imports`, `exports`) from the current manifest even when an unchanged lockfile reuses an
// install made from an older one. Dependencies still resolve from the node_modules above it.
export function appDir(target: string, manifest = currentManifest()): string {
  const parts = runtimeSources().flatMap((path) => [relative(SRC_DIR, path), readFileSync(path)]);
  return join(target, `app-${digest(["package.json", manifest, ...parts])}`);
}

export function installCommand(target: string, platform = process.platform): string {
  const sources = MANIFESTS.map((name) => join(SERVER_DIR, name));
  const [ci, ...flags] = NPM_CI_ARGS;
  if (platform === "win32") {
    // Windows PowerShell 5.1 has no `&&`; Stop turns each cmdlet failure into a halt.
    const q = (path: string) => `'${path.replaceAll("'", "''")}'`;
    return (
      `$ErrorActionPreference = 'Stop'; ` +
      `Remove-Item -LiteralPath ${q(target)} -Recurse -Force -ErrorAction SilentlyContinue; ` +
      `New-Item -ItemType Directory -Force -Path ${q(target)} | Out-Null; ` +
      `Copy-Item -LiteralPath ${sources.map(q).join(", ")} -Destination ${q(target)}; ` +
      `npm ${ci} --prefix ${q(target)} ${flags.join(" ")}`
    );
  }
  const q = (path: string) => `'${path.replaceAll("\\", "/").replaceAll("'", `'\\''`)}'`;
  return (
    `rm -rf ${q(target)} && mkdir -p ${q(target)} && cp ${sources.map(q).join(" ")} ${q(target)}/ ` +
    `&& npm ${ci} --prefix ${q(target)} ${flags.join(" ")}`
  );
}

function installed(dir: string): boolean {
  const manifest = JSON.parse(readFileSync(join(SERVER_DIR, "package.json"), "utf8")) as {
    dependencies?: Record<string, string>;
  };
  return Object.keys(manifest.dependencies ?? {}).every((name) =>
    existsSync(join(dir, "node_modules", name, "package.json")),
  );
}

// A `.partial-*` sibling untouched for longer than any live `npm ci` runs was left by a
// killed launch; a younger one may belong to a concurrent launch, so it stays.
function removeStalePartials(target: string): void {
  const parent = dirname(target);
  if (!existsSync(parent)) return;
  const cutoff = Date.now() - STALE_PARTIAL_MS;
  for (const name of readdirSync(parent)) {
    if (!name.startsWith(`${basename(target)}.partial-`)) continue;
    const path = join(parent, name);
    try {
      if (statSync(path).mtimeMs < cutoff) rmSync(path, { recursive: true, force: true });
    } catch {
      // Another launch removed or renamed it first.
    }
  }
}

// Builds `target` through `build(partial)`, then renames it into place. A failed rename is
// fine when a concurrent launch won it and its copy satisfies `ready`.
function buildAtomically(
  target: string,
  ready: (dir: string) => boolean,
  build: (partial: string) => void,
  command?: string,
): void {
  removeStalePartials(target);
  const partial = `${target}.partial-${process.pid}`;
  rmSync(partial, { recursive: true, force: true });
  try {
    mkdirSync(partial, { recursive: true });
    build(partial);
    renameSync(partial, target);
  } catch (error) {
    rmSync(partial, { recursive: true, force: true });
    if (error instanceof LaunchBroken) throw error;
    if (!ready(target)) throw new LaunchBroken(`cannot create ${target}: ${error}`, command);
  }
}

export function ensureDependencies(target: string): boolean {
  if (installed(target)) return false;
  const command = installCommand(target);
  buildAtomically(
    target,
    installed,
    (partial) => {
      for (const name of MANIFESTS) cpSync(join(SERVER_DIR, name), join(partial, name));
      const { MIRO_API_TOKEN: _token, ...env } = process.env;
      const options: SpawnSyncOptionsWithStringEncoding = {
        cwd: partial,
        env,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
        timeout: NPM_TIMEOUT_MS,
        windowsHide: true,
      };
      // npm is a .cmd shim on Windows, which Node spawns only through a shell. The command is
      // fixed flags and the paths travel in `cwd`, so the shell parses nothing variable.
      const run =
        process.platform === "win32"
          ? spawnSync(`npm ${NPM_CI_ARGS.join(" ")}`, { ...options, shell: true })
          : spawnSync("npm", NPM_CI_ARGS, options);
      if (run.error) {
        const missing = (run.error as NodeJS.ErrnoException).code === "ENOENT";
        throw new LaunchBroken(
          missing
            ? "npm is not on PATH, so the server's dependencies cannot be installed (install Node.js, which ships npm)"
            : `npm ci could not run: ${run.error.message}`,
          command,
        );
      }
      if (run.status !== 0 || !installed(partial)) {
        const tail = `${run.stderr}\n${run.stdout}`
          .split(LINE_BREAK)
          .filter((line) => line.trim() && !line.includes("npm notice"))
          .slice(-3);
        throw new LaunchBroken(`npm ci failed (exit ${run.status}): ${tail.join(" | ")}`, command);
      }
    },
    command,
  );
  return true;
}

export function ensureSource(target: string, manifest = currentManifest()): string {
  const app = appDir(target, manifest);
  const ready = (dir: string) =>
    existsSync(join(dir, "index.ts")) && existsSync(join(dir, "package.json"));
  if (!ready(app)) {
    buildAtomically(app, ready, (partial) => {
      cpSync(SRC_DIR, partial, { recursive: true, filter: isRuntimeSource });
      writeFileSync(join(partial, "package.json"), manifest);
    });
  }
  return app;
}

export async function launch(dataDir = process.env["CLAUDE_PLUGIN_DATA"]): Promise<void> {
  if (!dataDir) {
    throw new LaunchBroken(
      "CLAUDE_PLUGIN_DATA is not set. Claude Code exports it to plugin MCP servers; when running " +
        "the server by hand, set it to a directory the dependencies can be installed into.",
    );
  }
  const target = installDir(dataDir);
  ensureDependencies(target);
  const app = ensureSource(target);
  try {
    await import(pathToFileURL(join(app, "index.ts")).href);
  } catch (error) {
    throw new LaunchBroken(`the installed server failed to load: ${error}`, installCommand(target));
  }
}
