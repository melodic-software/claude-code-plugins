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
  npmEnv,
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

describe("the npm environment", () => {
  it("carries no token alias and no exported plugin option", () => {
    const env = npmEnv({
      PATH: "/bin",
      MIRO_API_TOKEN: "t",
      CLAUDE_PLUGIN_OPTION_MIRO_API_TOKEN: "t",
      CLAUDE_PLUGIN_OPTION_OTHER: "x",
      CLAUDE_PLUGIN_DATA: "/data",
    });
    expect(env).toEqual({ PATH: "/bin", CLAUDE_PLUGIN_DATA: "/data" });
  });
});

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

  it("quotes a POSIX path verbatim, keeping a backslash a legal filename character", () => {
    const odd = "/srv/o'brien\\data dir/mcp-server/abc";
    const command = installCommand(odd, "linux");
    const quoted = command.slice("rm -rf ".length, command.indexOf(" && mkdir"));
    const printed = spawnSync("bash", ["-c", `printf %s ${quoted}`], { encoding: "utf8" });
    expect(printed.stdout).toBe(odd);
    expect(spawnSync("bash", ["-n", "-c", command]).status).toBe(0);
  });

  const winTarget = "D:\\O'Brien Data\\mcp-server\\abc";

  it("is a Windows PowerShell 5.1 line on Windows, with no &&", () => {
    const command = installCommand(winTarget, "win32");
    const quoted = "'D:\\O''Brien Data\\mcp-server\\abc'";
    expect(command).not.toContain("&&");
    expect(command.startsWith("& { $ErrorActionPreference = 'Stop'; ")).toBe(true);
    expect(command).toContain(`Remove-Item -LiteralPath ${quoted} -Recurse -Force`);
    expect(command).toContain(`New-Item -ItemType Directory -Force -Path ${quoted}`);
    expect(command).toContain(`-Destination ${quoted};`);
    const npm = `; npm.cmd ci --prefix ${quoted} --omit=dev --ignore-scripts --no-audit --no-fund }`;
    expect(command.endsWith(npm)).toBe(true);
  });

  const pwsh = spawnSync("pwsh", ["-NoProfile", "-Command", "exit 0"]).status === 0;

  // One top-level `& { ... }` statement keeps `$ErrorActionPreference = 'Stop'` out of the user's
  // session; a bare assignment would be a second top-level statement that persists.
  it.skipIf(!pwsh)("parses as one child script block, so Stop does not leak", () => {
    const probe =
      "$e = $null; $s = [System.Management.Automation.Language.Parser]::ParseInput(" +
      "$env:REPAIR_LINE, [ref]$null, [ref]$e).EndBlock.Statements; $c = $s[0].PipelineElements[0]; " +
      '"$($e.Count) $($s.Count) $($c.InvocationOperator) $($c.CommandElements[0].GetType().Name)"';
    const run = spawnSync("pwsh", ["-NoProfile", "-NonInteractive", "-Command", probe], {
      encoding: "utf8",
      env: { ...process.env, REPAIR_LINE: installCommand(winTarget, "win32") },
    });
    expect(run.stdout.trim()).toBe("0 1 Ampersand ScriptBlockExpressionAst");
  });

  // PowerShell's tokenizer treats U+2018, U+2019, U+201A and U+201B as single-quote characters
  // (language specification 2.3.5.2); doubling the same character escapes each one.
  const curlyTarget = "D:\\it\u2018s \u2019 \u201A \u201B data\\mcp-server\\abc";

  it("doubles every PowerShell single-quote character, not only the ASCII one", () => {
    const command = installCommand(curlyTarget, "win32");
    expect(command).toContain(
      "-LiteralPath 'D:\\it\u2018\u2018s \u2019\u2019 \u201A\u201A \u201B\u201B data\\mcp-server\\abc'",
    );
  });

  it.skipIf(!pwsh)("keeps a path with curly single quotes one argument in each use", () => {
    const probe =
      "$e = $null; $a = [System.Management.Automation.Language.Parser]::ParseInput(" +
      "$env:REPAIR_LINE, [ref]$null, [ref]$e); $h = $a.FindAll({ param($n) " +
      "$n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and " +
      '$n.Value -ceq $env:EXPECTED_PATH }, $true); "$($e.Count) $($h.Count)"';
    const run = spawnSync("pwsh", ["-NoProfile", "-NonInteractive", "-Command", probe], {
      encoding: "utf8",
      env: {
        ...process.env,
        REPAIR_LINE: installCommand(curlyTarget, "win32"),
        EXPECTED_PATH: curlyTarget,
      },
    });
    // Remove-Item, New-Item, Copy-Item -Destination and npm --prefix each carry the path once.
    expect(run.stdout.trim()).toBe("0 4");
  });
});
