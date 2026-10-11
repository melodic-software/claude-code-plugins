import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  analyzeHarvestedRepos,
  filterGitHubUrls,
  sanitizePathSegment,
  shallowCloneGitHubRepo,
} from "./analyze-harvested-repos.js";

describe("filterGitHubUrls", () => {
  it("should keep unique GitHub URLs only", () => {
    const links = [
      { url: "https://github.com/org/repo" },
      { url: "https://example.com/spec" },
      { url: "https://github.com/org/repo.git" },
    ];
    expect(filterGitHubUrls(links)).toEqual([
      "https://github.com/org/repo",
      "https://github.com/org/repo.git",
    ]);
  });
});

describe("sanitizePathSegment", () => {
  it("replaces Windows-reserved and path-breaking chars with underscores", () => {
    expect(sanitizePathSegment('a:b*c?d"e<f>g|h')).toBe("a_b_c_d_e_f_g_h");
  });

  it("preserves word chars, dots, and hyphens", () => {
    expect(sanitizePathSegment("Org-Name.v2")).toBe("Org-Name.v2");
  });
});

describe("shallowCloneGitHubRepo", () => {
  it("terminates git option parsing before repository and destination arguments", async () => {
    let capturedArgs;
    const spawnFn = (_command, args) => {
      capturedArgs = args;
      return {
        on(event, callback) {
          if (event === "close") callback(0);
        },
      };
    };

    await expect(
      shallowCloneGitHubRepo("https://github.com/owner/repo", "-destination", spawnFn),
    ).resolves.toBe(true);
    expect(capturedArgs).toEqual([
      "-c",
      "credential.helper=",
      "clone",
      "--depth",
      "1",
      "--single-branch",
      "--",
      "https://github.com/owner/repo",
      "-destination",
    ]);
  });
});

describe("shallowCloneGitHubRepo hardening", () => {
  it("disables credential prompts and LFS smudge for the clone", async () => {
    let capturedArgs;
    let capturedOptions;
    const spawnFn = (_command, args, options) => {
      capturedArgs = args;
      capturedOptions = options;
      return {
        on(event, callback) {
          if (event === "close") callback(0);
        },
      };
    };

    await shallowCloneGitHubRepo("https://github.com/owner/repo", "dest", spawnFn);

    expect(capturedArgs.slice(0, 3)).toEqual(["-c", "credential.helper=", "clone"]);
    expect(capturedOptions.env.GIT_ASKPASS).toBe("");
    expect(capturedOptions.env.SSH_ASKPASS).toBe("");
    expect(capturedOptions.env.GIT_TERMINAL_PROMPT).toBe("0");
    expect(capturedOptions.env.GIT_LFS_SKIP_SMUDGE).toBe("1");
  });

  it("kills a clone that outlives the timeout and reports it as failed", async () => {
    const hangingSpawn = (_command, _args, options) =>
      spawn(process.execPath, ["-e", "setTimeout(() => {}, 30000)"], options);

    const started = Date.now();
    await expect(
      shallowCloneGitHubRepo("https://github.com/owner/repo", "dest", hangingSpawn, {
        timeoutMs: 200,
      }),
    ).resolves.toBe(false);
    expect(Date.now() - started).toBeLessThan(4000);
  });

  it("kills the clone's descendants on timeout, as git's remote helpers would be", async () => {
    const pidDir = fs.mkdtempSync(path.join(os.tmpdir(), "clone-tree-"));
    const pidFile = path.join(pidDir, "descendant.pid");
    const forkingChild = [
      'const { spawn } = require("node:child_process");',
      'const g = spawn(process.execPath, ["-e", "setTimeout(() => {}, 30000)"], { stdio: "ignore" });',
      'require("node:fs").writeFileSync(process.argv[1], String(g.pid));',
      "setTimeout(() => {}, 30000);",
    ].join("\n");
    const forkingSpawn = (_command, _args, options) =>
      spawn(process.execPath, ["-e", forkingChild, pidFile], options);
    const isAlive = (/** @type {number} */ pid) => {
      try {
        process.kill(pid, 0);
        return true;
      } catch {
        return false;
      }
    };

    let descendant = 0;
    try {
      await expect(
        shallowCloneGitHubRepo("https://github.com/owner/repo", "dest", forkingSpawn, {
          timeoutMs: 1500,
        }),
      ).resolves.toBe(false);
      descendant = Number(fs.readFileSync(pidFile, "utf8"));
      const deadline = Date.now() + 3000;
      while (isAlive(descendant) && Date.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
      expect(isAlive(descendant)).toBe(false);
    } finally {
      if (descendant && isAlive(descendant)) process.kill(descendant);
      fs.rmSync(pidDir, { recursive: true, force: true });
    }
  });
});

describe("analyzeHarvestedRepos clone target", () => {
  /** @type {string} */
  let sliceDir;

  beforeEach(() => {
    sliceDir = fs.mkdtempSync(path.join(os.tmpdir(), "harvested-repos-test-"));
    fs.mkdirSync(path.join(sliceDir, "source"), { recursive: true });
  });

  afterEach(() => {
    fs.rmSync(sliceDir, { recursive: true, force: true });
  });

  it("clones the canonical repo URL built from parsed parts, not the harvested deep link", async () => {
    fs.writeFileSync(
      path.join(sliceDir, "source", "harvested-links.json"),
      JSON.stringify([
        {
          url: "https://github.com/melodic-software/medley/blob/main/README.md",
        },
      ]),
    );

    /** @type {string[]} */
    const clonedUrls = [];
    await analyzeHarvestedRepos(sliceDir, {
      clone: async (url) => {
        clonedUrls.push(url);
        return false; // skip structure detection; only the clone target matters here
      },
    });

    expect(clonedUrls).toEqual(["https://github.com/melodic-software/medley"]);
  });
});

describe("CLI exit handling", () => {
  it("sets process.exitCode instead of calling process.exit after the stdout write", () => {
    const src = fs.readFileSync(new URL("./analyze-harvested-repos.js", import.meta.url), "utf8");
    expect(src).not.toMatch(/process\.exit\(/);
    expect(src).toMatch(/process\.exitCode = code/);
  });
});
