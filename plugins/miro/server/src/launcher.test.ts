import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, utimesSync } from "node:fs";
import { basename, join } from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import {
  appDir,
  ensureDependencies,
  ensureSource,
  installCommand,
  installDir,
} from "./launcher.ts";
import { LAUNCH, seedInstall, tempDataDir } from "./test-support/install.ts";

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
  });
});
