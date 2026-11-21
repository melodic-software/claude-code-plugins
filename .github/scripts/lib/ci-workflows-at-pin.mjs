import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

import { CONTRACT_FILES, contractFiles, loadContract } from "../plugin-eval/eval-handoff.mjs";

const REMOTE = "https://github.com/melodic-software/ci-workflows.git";
const CACHE = join(tmpdir(), "ci-workflows-at-pin");
const ATTEMPTS = 3;
const PIN = /^[0-9a-f]{40}$/;

const git = (dir, ...args) =>
  execFileSync("git", ["-C", dir, ...args], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    env: { ...process.env, GIT_TERMINAL_PROMPT: "0" },
    stdio: ["ignore", "pipe", "pipe"],
  });

const pause = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

function pinned(pin) {
  if (!PIN.test(pin)) throw new Error(`ci-workflows pin is not a full commit sha: ${pin}`);
  const dir = join(CACHE, pin);
  if (existsSync(join(dir, "ready"))) return dir;
  mkdirSync(CACHE, { recursive: true });
  const work = mkdtempSync(join(CACHE, `${pin}-`));
  try {
    git(work, "init", "-q");
    for (let attempt = 1; ; attempt += 1) {
      try {
        git(work, "fetch", "-q", "--depth", "1", "--no-tags", REMOTE, pin);
        break;
      } catch (error) {
        if (attempt === ATTEMPTS) throw new Error(`git fetch of ci-workflows ${pin} failed: ${String(error.stderr || error.message).trim()}`);
        pause(2000 * attempt);
      }
    }
    writeFileSync(join(work, "ready"), "");
    try {
      renameSync(work, dir);
    } catch (error) {
      if (!existsSync(join(dir, "ready"))) throw error;
      rmSync(work, { recursive: true, force: true });
    }
    return dir;
  } catch (error) {
    rmSync(work, { recursive: true, force: true });
    throw error;
  }
}

export async function fetchAtPin(pin, path) {
  return git(pinned(pin), "show", `${pin}:${path}`);
}

export async function contractFilesAtPin(pin) {
  return contractFiles(await fetchAtPin(pin, CONTRACT_FILES));
}

export async function contractAtPin(pin) {
  const root = mkdtempSync(join(tmpdir(), "ci-workflows-at-pin-"));
  try {
    for (const path of [CONTRACT_FILES, ...(await contractFilesAtPin(pin))]) {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      writeFileSync(join(root, path), await fetchAtPin(pin, path));
    }
    return loadContract(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}
