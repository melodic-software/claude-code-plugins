import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

import { CONTRACT_FILES, contractFiles, loadContract } from "../plugin-eval/eval-handoff.mjs";

const REMOTE = "https://github.com/melodic-software/ci-workflows.git";
const CACHE = join(tmpdir(), "ci-workflows-at-pin");
const ATTEMPTS = 3;
const PIN = /^[0-9a-f]{40}$/;
let mainTip;

const LOCAL = new Set(execFileSync("git", ["rev-parse", "--local-env-vars"], { encoding: "utf8" }).split("\n").filter(Boolean));
const ENV = { ...Object.fromEntries(Object.entries(process.env).filter(([name]) => !LOCAL.has(name))), GIT_TERMINAL_PROMPT: "0" };

const git = (dir, ...args) =>
  execFileSync("git", ["-C", dir, ...args], {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    env: ENV,
    stdio: ["ignore", "pipe", "pipe"],
  });

const pause = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);

function commitOf(ref) {
  if (PIN.test(ref)) return ref;
  if (ref !== "main") throw new Error(`ci-workflows ref is neither main nor a full commit sha: ${ref}`);
  for (let attempt = 1; !mainTip; attempt += 1) {
    try {
      const sha = execFileSync("git", ["ls-remote", REMOTE, "refs/heads/main"], { encoding: "utf8", env: ENV, stdio: ["ignore", "pipe", "pipe"] }).split("\t")[0];
      if (!PIN.test(sha)) throw new Error(`no main tip in: ${sha}`);
      mainTip = sha;
    } catch (error) {
      if (attempt === ATTEMPTS) throw new Error(`git ls-remote of ci-workflows main failed: ${String(error.stderr || error.message).trim()}`);
      pause(2000 * attempt);
    }
  }
  return mainTip;
}

function pinned(pin) {
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

export async function fetchAtPin(ref, path) {
  const sha = commitOf(ref);
  return git(pinned(sha), "show", `${sha}:${path}`);
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
