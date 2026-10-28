#!/usr/bin/env node
// The leak scan on a lane branch an earlier run left with commits and no
// report. Its commits were scanned when their run made them, against that
// day's patterns, or not at all when the branch predates issue-mode scanning,
// so run-checks scans them again before report-outcome opens their PR: the
// diff from the branch's merge base with the base tip, and every file that
// diff makes, by name and bytes, through the read runner's own scan
// (lib/publish-gate.mjs scanLeak).
//
//   scan-reuse.mjs <repository> <base-tip> <tip>
// Prints one word: clean; found, for a credential format, an assignment
// hidden by markup or escapes, or a plain password or secret assignment;
// failed, when the scan did not finish. Never the match. Exit 0 unless the
// arguments are wrong.

import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { changedBytes, scanLeak } from "../../../lib/publish-gate.mjs";

const SHA = /^[0-9a-f]{40}$/;

// {result, label}: the first source that does not pass, else clean. `git`
// runs plumbing in the branch's repository and returns stdout as a Buffer.
export function scanBranch(git, base, tip) {
  const mergeBase = git(["merge-base", base, tip]).toString("latin1").trim();
  if (!SHA.test(mergeBase)) throw new Error("no merge base");
  const sources = [
    [git(["diff", "--binary", "--no-renames", "--no-ext-diff", "--no-textconv", mergeBase, tip]), true],
    ...[...changedBytes(git, mergeBase, tip)].map((bytes) => [bytes, false]),
  ];
  for (const [bytes, diff] of sources) {
    const { block, warn } = scanLeak(bytes, { diff });
    if (block) return { result: "found", label: block };
    if (warn) return { result: "found", label: "password or secret assignment" };
  }
  return { result: "clean", label: "" };
}

// git with no global or system config and no hooks, reading the repository's
// objects only.
export function plumbing(repository, scratch) {
  writeFileSync(join(scratch, "config"), "");
  const env = { PATH: "/usr/bin:/bin", HOME: scratch, XDG_CONFIG_HOME: scratch, GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: join(scratch, "config"), GIT_NO_REPLACE_OBJECTS: "1" };
  return (args) =>
    execFileSync("git", ["-C", repository, "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", ...args], {
      env,
      maxBuffer: 1 << 30,
      stdio: ["ignore", "pipe", "ignore"],
    });
}

export function main(argv = process.argv.slice(2)) {
  const [repository, base, tip] = argv;
  if (argv.length !== 3 || !repository || !SHA.test(base ?? "") || !SHA.test(tip ?? "")) {
    process.stderr.write("usage: scan-reuse.mjs <repository> <base-tip> <tip>\n");
    return 2;
  }
  const scratch = mkdtempSync(join(tmpdir(), "scan-reuse-"));
  let outcome;
  try {
    outcome = scanBranch(plumbing(repository, scratch), base, tip);
  } catch (error) {
    outcome = { result: "failed", label: `no finished scan (${error.name})` };
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
  if (outcome.label) process.stderr.write(`scan-reuse: ${outcome.label}\n`);
  process.stdout.write(`${outcome.result}\n`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = main();
}
