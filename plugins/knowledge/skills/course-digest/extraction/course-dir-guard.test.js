import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { afterAll, beforeAll, describe, expect, it } from "vitest";

const dir = path.dirname(fileURLToPath(import.meta.url));
const base = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "course-dir-guard-")));
const home = path.join(base, "home");
const bin = path.join(base, "bin");
const gitConfig = path.join(base, "gitconfig");
const withoutGit = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.toUpperCase().startsWith("GIT_")));
const gitEnv = { ...withoutGit, GIT_CONFIG_GLOBAL: gitConfig, GIT_CONFIG_NOSYSTEM: "1" };

const loose = path.join(base, "loose");
const noRemote = path.join(base, "no-remote");
const elsewhere = path.join(base, "elsewhere");
const onGitHub = path.join(base, "on-github");

const REFUSED = "Refusing to write course material to";
const CHILD_RAN = "course.json not found";

function repo(at, remote) {
  fs.mkdirSync(at, { recursive: true });
  execFileSync("git", ["init", "-q"], { cwd: at, env: gitEnv });
  if (remote) execFileSync("git", ["remote", "add", "origin", remote], { cwd: at, env: gitEnv });
}

/** run.mjs launching validate-extraction.js, which fails on the empty course directory only if it runs. */
function run(args, ghAnswer = "") {
  const result = spawnSync(process.execPath, [path.join(dir, "run.mjs"), "validate-extraction.js", ...args], {
    encoding: "utf8",
    timeout: 20000,
    env: { ...withoutGit, HOME: home, XDG_CONFIG_HOME: path.join(home, ".config"), PATH: `${bin}${path.delimiter}${process.env.PATH}`, FAKE_GH_ANSWER: ghAnswer },
  });
  return { status: result.status, output: `${result.stdout}${result.stderr}` };
}

beforeAll(() => {
  fs.writeFileSync(gitConfig, "");
  fs.mkdirSync(home);
  fs.mkdirSync(loose);
  fs.mkdirSync(bin);
  // A gh stand-in answering `gh api ... --jq .visibility` with FAKE_GH_ANSWER.
  fs.writeFileSync(path.join(bin, "gh"), '#!/bin/sh\nprintf "%s\\n" "$FAKE_GH_ANSWER"\n', { mode: 0o755 });
  repo(noRemote);
  repo(elsewhere, "https://gitlab.com/acme/corpus.git");
  repo(onGitHub, "https://github.com/acme/corpus");
});

afterAll(() => fs.rmSync(base, { recursive: true, force: true }));

describe("run.mjs course directory guard", () => {
  it("refuses a --course-dir whose repository reads unknown, naming the verdict and the redirect, and launches nothing", () => {
    const { status, output } = run(["--course-dir", elsewhere]);
    expect(status).toBe(1);
    expect(output).toContain(`${REFUSED} ${elsewhere}: it reads unknown`);
    expect(output).toContain("library_dir");
    expect(output).not.toContain(CHILD_RAN);
  });

  it("refuses the --flag=<dir> form and a course directory not created yet", () => {
    const target = path.join(elsewhere, "courses", "dometrain", "new-course");
    const { status, output } = run([`--course-dir=${target}`]);
    expect(status).toBe(1);
    expect(output).toContain(`${REFUSED} ${target}: it reads unknown`);
  });

  it.skipIf(process.platform === "win32")("refuses an --output-dir in a repository GitHub reports public", () => {
    const { status, output } = run(["--output-dir", onGitHub], "public");
    expect(status).toBe(1);
    expect(output).toContain(`${REFUSED} ${onGitHub}: it reads public`);
    expect(output).not.toContain(CHILD_RAN);
  });

  it.skipIf(process.platform === "win32")("launches the script for a repository GitHub reports private", () => {
    const { status, output } = run(["--course-dir", onGitHub], "private");
    expect(output).not.toContain(REFUSED);
    expect(output).toContain(CHILD_RAN);
    expect(status).toBe(1);
  });

  it("launches the script outside git and in a repository with no remote", () => {
    for (const target of [loose, noRemote]) {
      const { output } = run(["--course-dir", target]);
      expect(output).not.toContain(REFUSED);
      expect(output).toContain(`${CHILD_RAN} at: ${path.join(target, "course.json")}`);
    }
  });

  it.skipIf(process.platform === "win32")("refuses when any one of several course directories reads public", () => {
    const { status, output } = run(["--course-dir", loose, "--output-dir", onGitHub], "public");
    expect(status).toBe(1);
    expect(output).toContain(`${REFUSED} ${onGitHub}`);
  });
});
