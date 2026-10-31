import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

import { resolveWorkRoot } from "./work-root.js";

describe("resolveWorkRoot", () => {
  let base;
  let repo;
  let loose;

  beforeAll(() => {
    base = realpathSync(mkdtempSync(path.join(os.tmpdir(), "video-work-root-")));
    repo = path.join(base, "consumer");
    loose = path.join(base, "loose");
    mkdirSync(path.join(repo, "sub"), { recursive: true });
    mkdirSync(loose);
    const gitConfig = path.join(base, "gitconfig");
    writeFileSync(gitConfig, "");
    const inherited = Object.fromEntries(
      Object.entries(process.env).filter(
        ([name]) => name !== "GIT_DIR" && name !== "GIT_WORK_TREE" && !name.startsWith("GIT_CONFIG"),
      ),
    );
    execFileSync("git", ["init", "-q"], {
      cwd: repo,
      env: { ...inherited, GIT_CONFIG_GLOBAL: gitConfig, GIT_CONFIG_SYSTEM: gitConfig },
    });
  });

  afterAll(() => rmSync(base, { recursive: true, force: true }));

  beforeEach(() => {
    vi.stubEnv("VIDEO_DIGEST_WORK_ROOT", "");
    vi.stubEnv("YOUTUBE_WORK_ROOT", "");
    vi.stubEnv("GIT_DIR", undefined);
    vi.stubEnv("GIT_WORK_TREE", undefined);
    vi.stubEnv("GIT_CEILING_DIRECTORIES", base);
    vi.stubEnv("CLAUDE_PROJECT_DIR", loose);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    vi.restoreAllMocks();
  });

  it("returns the root the launcher passed", () => {
    vi.stubEnv("VIDEO_DIGEST_WORK_ROOT", "/data/corpus");
    expect(resolveWorkRoot()).toBe("/data/corpus");
  });

  it("falls back to the git top-level of the working directory, not CLAUDE_PROJECT_DIR", () => {
    vi.spyOn(process, "cwd").mockReturnValue(path.join(repo, "sub"));
    expect(resolveWorkRoot()).toBe(repo);
  });

  it("falls back to the working directory itself outside git", () => {
    vi.stubEnv("CLAUDE_PROJECT_DIR", repo);
    vi.spyOn(process, "cwd").mockReturnValue(loose);
    expect(resolveWorkRoot()).toBe(loose);
  });
});
