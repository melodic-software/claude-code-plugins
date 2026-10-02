import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join } from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import {
  appDir,
  buildAtomically,
  ensureDependencies,
  ensureSource,
  installCommand,
  installDir,
  LaunchBroken,
} from "./launcher.ts";
import { LAUNCH, SERVER_DIR, seedInstall, tempDataDir } from "./test-support/install.ts";

const temps: (() => void)[] = [];
afterEach(() => {
  for (const cleanup of temps.splice(0)) cleanup();
});

function dataDir(): string {
  const temp = tempDataDir();
  temps.push(temp.cleanup);
  return temp.dataDir;
}

function launch(env: Record<string, string>) {
  return spawnSync(process.execPath, [LAUNCH], { env, encoding: "utf8", timeout: 20_000 });
}

describe("first launch that cannot install", () => {
  it("fails closed with the exact repair command and leaves no partial install", () => {
    const data = dataDir();
    const target = installDir(data);
    const emptyPath = join(data, "empty-path");
    mkdirSync(emptyPath);
    const stale = `${target}.partial-1`;
    const fresh = `${target}.partial-2`;
    mkdirSync(stale, { recursive: true });
    mkdirSync(fresh);
    utimesSync(stale, new Date(0), new Date(0));

    const run = launch({ PATH: emptyPath, CLAUDE_PLUGIN_DATA: data });

    expect(run.status).toBe(1);
    expect(run.stdout).toBe("");
    expect(run.stderr).toContain("npm is not on PATH");
    expect(run.stderr).toContain(installCommand(target));
    expect(readdirSync(join(data, "mcp-server"))).toEqual([basename(fresh)]);
  });

  it("fails closed when CLAUDE_PLUGIN_DATA is missing", () => {
    const run = launch({ PATH: process.env["PATH"] ?? "" });
    expect(run.status).toBe(1);
    expect(run.stderr).toContain("CLAUDE_PLUGIN_DATA is not set");
  });

  it("delivers a diagnostic longer than a pipe buffer whole, then exits 1", () => {
    // A data path too long to create makes the diagnostic repeat it several times.
    const longData = join(dataDir(), "a/".repeat(20_000));
    const run = launch({ PATH: process.env["PATH"] ?? "", CLAUDE_PLUGIN_DATA: longData });
    expect(run.status).toBe(1);
    expect(run.stderr.length).toBeGreaterThan(65_536);
    expect(run.stderr.startsWith("miro MCP server cannot start: cannot create ")).toBe(true);
    expect(run.stderr.endsWith("--no-audit --no-fund\n")).toBe(true);
  });
});

describe("a launch racing another", () => {
  const ok = (dir: string) => existsSync(join(dir, "ok"));

  it("accepts the other launch's finished copy when its own build fails", () => {
    const target = join(dataDir(), "target");
    expect(() =>
      buildAtomically(target, ok, () => {
        mkdirSync(target);
        writeFileSync(join(target, "ok"), "");
        throw new LaunchBroken("npm ci failed (exit 1)", "repair");
      }),
    ).not.toThrow();
    expect(readdirSync(dirname(target))).toEqual(["target"]);
  });

  it("reports its own failure when no finished copy exists", () => {
    const target = join(dataDir(), "target");
    expect(() =>
      buildAtomically(target, ok, () => {
        throw new LaunchBroken("npm ci failed (exit 1)", "repair");
      }),
    ).toThrow("npm ci failed (exit 1)");
    expect(readdirSync(dirname(target))).toEqual([]);
  });
});

describe("later launches", () => {
  it("reuse the install and the source copy", () => {
    const target = seedInstall(dataDir());

    expect(ensureDependencies(target)).toBe(false);
    const app = ensureSource(target);
    expect(ensureSource(target)).toBe(app);
    expect(app).toBe(appDir(target));
    expect(existsSync(join(app, "index.ts"))).toBe(true);
    expect(existsSync(join(app, "launcher.test.ts"))).toBe(false);
    expect(existsSync(join(app, "test-support"))).toBe(false);
    expect(readFileSync(join(app, "package.json"), "utf8")).toBe(
      readFileSync(join(SERVER_DIR, "package.json"), "utf8"),
    );
  });

  it("put a changed package.json beside the source, with the same lockfile", () => {
    const target = seedInstall(dataDir());
    const manifest = JSON.parse(readFileSync(join(SERVER_DIR, "package.json"), "utf8"));
    const changed = `${JSON.stringify({ ...manifest, imports: { "#probe": "zod" } }, null, 2)}\n`;

    const app = ensureSource(target, Buffer.from(changed));

    expect(app).not.toBe(ensureSource(target));
    expect(readFileSync(join(app, "package.json"), "utf8")).toBe(changed);
    // The source copy's own manifest scopes `imports`, and a bare dependency still resolves
    // from the install's node_modules above it.
    writeFileSync(
      join(app, "probe.ts"),
      'import { z } from "zod";\nimport * as viaImports from "#probe";\nprocess.stdout.write(String(z === viaImports.z));\n',
    );
    const run = spawnSync(process.execPath, [join(app, "probe.ts")], { encoding: "utf8" });
    expect(run.stderr).toBe("");
    expect(run.stdout).toBe("true");
  });
});

describe("repair command", () => {
  const target = "/data/it's a dir/mcp-server/abc";

  it("is a POSIX shell line off Windows, quoting a space and a single quote", () => {
    const command = installCommand(target, "linux");
    expect(command).toContain(`rm -rf '/data/it'\\''s a dir/mcp-server/abc'`);
    expect(command).toContain("npm ci --prefix '/data/it'\\''s a dir/mcp-server/abc' --omit=dev");
    expect(spawnSync("bash", ["-n", "-c", command]).status).toBe(0);
  });

  it("is a Windows PowerShell 5.1 line on Windows, with no &&", () => {
    const winTarget = "C:\\Users\\O'Brien Dev\\data\\mcp-server\\abc";
    const command = installCommand(winTarget, "win32");
    const quoted = "'C:\\Users\\O''Brien Dev\\data\\mcp-server\\abc'";
    expect(command).not.toContain("&&");
    expect(command.startsWith("$ErrorActionPreference = 'Stop'; ")).toBe(true);
    expect(command).toContain(`Remove-Item -LiteralPath ${quoted} -Recurse -Force`);
    expect(command).toContain(`New-Item -ItemType Directory -Force -Path ${quoted}`);
    expect(command).toContain(`-Destination ${quoted};`);
    expect(command).toContain(`npm ci --prefix ${quoted} --omit=dev --ignore-scripts`);
  });
});
