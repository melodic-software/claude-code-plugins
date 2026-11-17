import { readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { realPath } from "./record.mjs";

const LOCAL = [".claude", "settings.local.json"];

/** The repository of a folder whose .git is a file: a linked worktree's main checkout, else a submodule's own folder. */
function fromGitFile(dir) {
  const gitdir = /^gitdir:\s*(.+?)\s*$/m.exec(readFileSync(join(dir, ".git"), "utf8"));
  if (!gitdir) return null;
  const gitDir = resolve(dir, gitdir[1]);
  let common;
  try {
    common = resolve(gitDir, readFileSync(join(gitDir, "commondir"), "utf8").trim());
  } catch {
    return { root: dir, commonDir: gitDir };
  }
  return { root: basename(common) === ".git" ? dirname(common) : dir, commonDir: common };
}

const statOf = (path) => statSync(path, { throwIfNoEntry: false });

/** {root, commonDir} of the nearest .git at or above dir, read from the files git writes without running git; null outside git. */
export function gitRepository(dir) {
  for (let at = realPath(dir); ; at = dirname(at)) {
    const entry = statOf(join(at, ".git"));
    if (entry?.isDirectory()) return { root: at, commonDir: join(at, ".git") };
    if (entry?.isFile()) {
      try {
        return fromGitFile(at);
      } catch {
        return null;
      }
    }
    if (dirname(at) === at) return null;
  }
}

const defaultHome = () => process.env.HOME || process.env.USERPROFILE || homedir();

/**
 * The settings.local.json Claude Code reads for a folder, per https://code.claude.com/docs/en/settings#where-claude-code-keeps-the-local-file-in-a-git-repository:
 * the repository root's, or the folder's own on Windows, outside git, at the home folder, or where the root, .git or .claude is not the user's.
 */
export function folderLevel(projectDir, { platform = process.platform, home = defaultHome(), uid = process.getuid?.() } = {}) {
  const own = { file: join(projectDir, ...LOCAL), root: null, commonDir: null, shared: false };
  if (platform === "win32") return own;
  const repo = gitRepository(projectDir);
  if (!repo) return own;
  const kept = { ...own, ...repo };
  if (realPath(repo.root) === realPath(home)) return kept;
  if (uid !== undefined && [repo.root, join(repo.root, ".git"), join(repo.root, ".claude")].some((p) => (statOf(p)?.uid ?? uid) !== uid)) return kept;
  return { file: join(repo.root, ...LOCAL), ...repo, shared: true };
}
