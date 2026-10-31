// The tree a /toolchain:check or /toolchain:lint result was recorded for, and the store that
// holds it.
//
// "The tree" is the content git would commit if every change in the working tree were staged:
// tracked edits, deletions and untracked files that .gitignore does not exclude. Its hash is a git
// tree id, so the same content gives the same id whatever HEAD is, and any edit gives a new one.
// It is computed on a copy of the index, so the real index is never touched, and with
// `update-index --info-only`, so no file content is written to the object database; only the
// small tree objects `write-tree` makes are.
//
// The store sits under the repository's common git directory, shared by every worktree:
// toolchain-results/<tree>/<skill> holds the Overall line the skill printed for that tree, and
// toolchain-results/sessions/<session id> what the Stop hook saw at that session's last turn end.

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

function git(dir, args, env) {
  return execFileSync("git", ["-C", dir, ...args], {
    encoding: "utf8",
    env: { ...process.env, GIT_OPTIONAL_LOCKS: "0", ...env },
    stdio: ["pipe", "pipe", "ignore"],
    maxBuffer: 64 * 1024 * 1024,
  });
}

// The verdict word of an Overall line, or null when the line is not one.
export function verdictOf(line) {
  const match = typeof line === "string" ? OVERALL.exec(line) : null;
  return match ? match[1] : null;
}

// The repository at <dir>: {top, store, index}. Throws when <dir> is not in a work tree.
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

// True when the work tree has no change git would commit: nothing staged, modified, deleted or
// untracked outside .gitignore.
export function isClean(repo) {
  return git(repo.top, ["status", "--porcelain=v1", "-z", "--untracked-files=all"]) === "";
}

function updateIndex(top, flags, paths, env) {
  if (paths === "") return;
  execFileSync("git", ["-C", top, "update-index", ...flags, "-z", "--stdin"], {
    env: { ...process.env, GIT_OPTIONAL_LOCKS: "0", ...env },
    input: paths,
    stdio: ["pipe", "ignore", "ignore"],
  });
}

// The tree id of the working tree as described at the top of this file.
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
      updateIndex(repo.top, ["--force-remove"], [...removed].map((path) => `${path}\0`).join(""), env);
    }
    // --replace lets a tracked directory that is now a file drop the entries under it.
    updateIndex(
      repo.top,
      ["--add", "--remove", "--replace", "--info-only"],
      listed
        .filter((path) => !removed.has(path))
        .map((path) => `${path}\0`)
        .join(""),
      env,
    );
    return git(repo.top, ["write-tree", "--missing-ok"], env).trim();
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}

// <line> with each run of control characters replaced by one space, trimmed and capped at
// MAX_LINE characters. Applied on write and again on read, since a record file can be placed in
// the store by something other than record().
function sanitize(line) {
  return String(line).replace(/[\u0000-\u001f\u007f]+/g, " ").trim().slice(0, MAX_LINE);
}

// Stores <line> as <skill>'s result for <tree>. The line must be an Overall line.
export function record(repo, tree, skill, line) {
  if (!SKILLS.includes(skill)) throw new Error(`skill must be one of ${SKILLS.join(", ")}`);
  const clean = sanitize(line);
  if (verdictOf(clean) === null) throw new Error(`not an Overall line: ${clean}`);
  const dir = join(repo.store, tree);
  mkdirSync(dir, { recursive: true });
  const part = join(dir, `.${skill}.${process.pid}`);
  writeFileSync(part, `${clean}\n`);
  renameSync(part, join(dir, skill));
  return clean;
}

// What the hook saw at a session's previous turn end, so a turn that changed no file and recorded
// no result stays quiet: sessions/<session id> holds one line. Returns "" when nothing is stored or
// the id is not a plain token.
const SESSION_ID = /^[A-Za-z0-9._-]{1,128}$/;
export function lastSeen(repo, session) {
  if (!SESSION_ID.test(session ?? "")) return "";
  try {
    return readFileSync(join(repo.store, "sessions", session), "utf8").trim();
  } catch {
    return "";
  }
}

// Stores <seen> as what the hook saw at this turn end. Best effort: an unwritable store only
// means the next turn end reports again.
export function remember(repo, session, seen) {
  if (!SESSION_ID.test(session ?? "")) return;
  try {
    const dir = join(repo.store, "sessions");
    mkdirSync(dir, { recursive: true });
    const part = join(dir, `.${session}.${process.pid}`);
    writeFileSync(part, `${seen}\n`);
    renameSync(part, join(dir, session));
  } catch {
    // Reporting again next turn is the safe direction.
  }
}

// The results recorded for <tree>: [{skill, line, verdict}], verdict null when the file holds no
// Overall line. A skill with no file is left out.
export function results(repo, tree) {
  const found = [];
  for (const skill of SKILLS) {
    let text;
    try {
      text = readFileSync(join(repo.store, tree, skill), "utf8");
    } catch (error) {
      if (error.code === "ENOENT" || error.code === "ENOTDIR") continue;
      found.push({ skill, line: "", verdict: null });
      continue;
    }
    const line = sanitize(text.split("\n")[0]);
    found.push({ skill, line, verdict: verdictOf(line) });
  }
  return found;
}
