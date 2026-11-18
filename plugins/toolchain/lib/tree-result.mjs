import { execFileSync } from "node:child_process";
import {
  copyFileSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  rmSync,
  statSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export const SKILLS = ["check", "lint"];
export const VERDICTS = ["PASS", "FAIL", "INCOMPLETE", "STOPPED"];
const OVERALL = /^Overall: (PASS|FAIL|INCOMPLETE|STOPPED)(?![A-Za-z])/;
const MAX_LINE = 2000;

function git(dir, args, env, input) {
  return execFileSync("git", ["-C", dir, ...args], {
    encoding: "utf8",
    env: { ...process.env, GIT_OPTIONAL_LOCKS: "0", ...env },
    input,
    stdio: ["pipe", "pipe", "ignore"],
    maxBuffer: 64 * 1024 * 1024,
  });
}

export function verdictOf(line) {
  const match = typeof line === "string" ? OVERALL.exec(line) : null;
  return match ? match[1] : null;
}

export function repository(dir) {
  const [top, common, index] = git(dir, [
    "rev-parse",
    "--path-format=absolute",
    "--show-toplevel",
    "--git-common-dir",
    "--git-path",
    "index",
  ])
    .split("\n")
    .map((line) => line.replace(/\r$/, ""));
  if (!top || !common || !index) throw new Error(`not a git work tree: ${dir}`);
  return { top, store: join(common, "toolchain-results"), index };
}

export function isClean(repo) {
  return git(repo.top, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]) === "";
}

function updateIndex(top, flags, paths, env) {
  if (paths.length === 0) return;
  git(top, ["update-index", ...flags, "-z", "--stdin"], env, paths.map((path) => `${path}\0`).join(""));
}

export function treeHash(repo) {
  const scratch = mkdtempSync(join(tmpdir(), "toolchain-tree-"));
  try {
    const index = join(scratch, "index");
    try {
      copyFileSync(repo.index, index);
      // The copy keeps the original's mtime, which git compares entry times against to find
      // racily clean entries; a fresh mtime would hide a same-size edit made in that second.
      const { atime, mtime } = statSync(repo.index);
      utimesSync(index, atime, mtime);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
    const env = { GIT_INDEX_FILE: index };
    // An untracked nested repository is listed as `dir/`, which update-index refuses; the tree
    // leaves it out.
    const listed = git(repo.top, ["ls-files", "-z", "--modified", "--deleted", "--others", "--exclude-standard"], env)
      .split("\0")
      .filter((path) => path !== "" && !path.endsWith("/"));
    // A tracked file that is now a directory is listed by its old path, which update-index refuses
    // even with --replace; its entry is removed first. A submodule entry is a directory by design.
    const nowDirs = listed.filter((path) => {
      try {
        return lstatSync(join(repo.top, path)).isDirectory();
      } catch {
        return false;
      }
    });
    const removed = new Set();
    if (nowDirs.length > 0) {
      const dirSet = new Set(nowDirs);
      for (const line of git(repo.top, ["ls-files", "-z", "--stage", "--", ...nowDirs], {
        ...env,
        GIT_LITERAL_PATHSPECS: "1",
      }).split("\0")) {
        const match = /^(\d+) \S+ \d+\t(.*)$/s.exec(line);
        if (match && match[1] !== "160000" && dirSet.has(match[2])) removed.add(match[2]);
      }
      updateIndex(repo.top, ["--force-remove"], [...removed], env);
    }
    // --replace lets a tracked directory that is now a file drop the entries under it.
    updateIndex(
      repo.top,
      ["--add", "--remove", "--replace", "--info-only"],
      listed.filter((path) => !removed.has(path)),
      env,
    );
    return git(repo.top, ["write-tree", "--missing-ok"], env).trim();
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

function sanitize(line) {
  return String(line).replace(/[\u0000-\u001f\u007f]+/g, " ").trim().slice(0, MAX_LINE);
}

function writeAtomically(dir, name, text) {
  mkdirSync(dir, { recursive: true });
  const part = join(dir, `.${name}.${process.pid}`);
  writeFileSync(part, text);
  renameSync(part, join(dir, name));
}

export function record(repo, tree, skill, line) {
  if (!SKILLS.includes(skill)) throw new Error(`skill must be one of ${SKILLS.join(", ")}`);
  const clean = sanitize(line);
  if (verdictOf(clean) === null) throw new Error(`not an Overall line: ${clean}`);
  writeAtomically(join(repo.store, tree), skill, `${clean}\n`);
  return clean;
}

const SESSION_ID = /^[A-Za-z0-9._-]{1,128}$/;
export function lastSeen(repo, session) {
  if (!SESSION_ID.test(session ?? "")) return "";
  try {
    return readFileSync(join(repo.store, "sessions", session), "utf8").trim();
  } catch {
    return "";
  }
}

export function remember(repo, session, seen) {
  if (!SESSION_ID.test(session ?? "")) return;
  try {
    writeAtomically(join(repo.store, "sessions"), session, `${seen}\n`);
  } catch {
    // Reporting again next turn is the safe direction.
  }
}

export function results(repo, tree) {
  const found = [];
  for (const skill of SKILLS) {
    let text;
    try {
      text = readFileSync(join(repo.store, tree, skill), "utf8");
    } catch (error) {
      if (error.code !== "ENOENT" && error.code !== "ENOTDIR") found.push({ skill, line: "", verdict: null });
      continue;
    }
    const line = sanitize(text.split("\n")[0]);
    found.push({ skill, line, verdict: verdictOf(line) });
  }
  return found;
}
