/**
 * Shallow clone of a repository URL: hardened for an untrusted repository by
 * default, or run in the user's own git environment when the caller asks.
 *
 * Node builtins only, so a skill can run `clone-cli.js` straight from the plugin
 * without installing anything.
 */

import { spawn, spawnSync } from "node:child_process";
import { rmSync } from "node:fs";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

export const CLONE_TIMEOUT_MS = 120_000;

/**
 * The command-line config of a hardened clone: no credential helper, https as
 * the only transport, and symbolic links checked out as plain files.
 */
const HARDENED_GIT_ARGS = [
  "-c",
  "credential.helper=",
  "-c",
  "protocol.allow=never",
  "-c",
  "protocol.https.allow=always",
  "-c",
  "core.symlinks=false",
];

/**
 * Shallow-clone an untrusted URL so that a private, renamed or LFS-heavy
 * repository fails fast instead of prompting or downloading, and so that the
 * clone reaches only an https remote and writes only inside `destDir`:
 *
 * - Every inherited variable whose name starts with `GIT_` (compared upper-cased,
 *   so Windows spellings count) is dropped: config passed through the
 *   environment (`GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT` and its pairs, where
 *   an `insteadOf` could point the clone elsewhere) and the variables that move
 *   the repository or weaken transport checks (`GIT_DIR`, `GIT_WORK_TREE`,
 *   `GIT_SSL_NO_VERIFY`, `GIT_SSH_COMMAND`).
 * - Then a fixed table is set: `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_SYSTEM` point
 *   at an empty file with `GIT_CONFIG_NOSYSTEM=1`, hiding the user's and the
 *   system's git config; an empty throwaway `HOME`, `USERPROFILE` and
 *   `XDG_CONFIG_HOME` hide `~/.netrc`, which git's HTTP transport reads
 *   regardless of the other settings; an empty `GIT_ASKPASS` and `SSH_ASKPASS`
 *   stop git falling back to `core.askPass` or `SSH_ASKPASS` before it consults
 *   `GIT_TERMINAL_PROMPT=0`, which stops the terminal prompt;
 *   `GIT_LFS_SKIP_SMUDGE=1` leaves LFS pointers in place; `GIT_ALLOW_PROTOCOL=https`
 *   and `GIT_PROTOCOL_FROM_USER=0` refuse every transport but https, `file://`,
 *   local paths and `ssh://` included.
 * - The command line adds `credential.helper=` (an empty helper list),
 *   `protocol.allow=never` with `protocol.https.allow=always`, and
 *   `core.symlinks=false`, so a symbolic link in the repository is checked out
 *   as a regular file holding its target path, never a link a later read follows.
 * - A clone that outlives the timeout is killed with its remote helpers and
 *   counted as failed.
 *
 * `inheritGitEnvironment: true` is for a repository the user is entitled to,
 * such as a private course repository: git runs as the user would run it, with
 * their home, git config, credential helper, prompts and LFS, in the parent's
 * process group, and a timeout sends git alone SIGTERM. `env`, in this mode
 * only, adds variables over the parent's environment (such as
 * `GIT_LFS_SKIP_SMUDGE`); a hardened clone ignores it. Depth, branch and
 * timeout are the same in both modes.
 *
 * `onStderr`, when given, receives git's stderr once the clone ends.
 *
 * @param {string} url
 * @param {string} destDir
 * @param {typeof spawn} [spawnFn]
 * @param {{ timeoutMs?: number, inheritGitEnvironment?: boolean, env?: Record<string, string>, onStderr?: (text: string) => void }} [options]
 * @returns {Promise<boolean>}
 */
export async function shallowCloneGitHubRepo(
  url,
  destDir,
  spawnFn = spawn,
  { timeoutMs = CLONE_TIMEOUT_MS, inheritGitEnvironment = false, env, onStderr } = {},
) {
  const run = { url, destDir, spawnFn, timeoutMs, onStderr };
  if (inheritGitEnvironment) {
    return runClone({ ...run, gitArgs: [], env: env ? { ...process.env, ...env } : process.env, ownGroup: false });
  }
  // Never throws: a home that cannot be made fails this clone (never one without
  // isolation), and one that cannot be removed leaves the clone's result standing.
  const isolatedHome = await fs
    .mkdtemp(path.join(os.tmpdir(), "harvest-clone-home-"))
    .catch(() => null);
  if (!isolatedHome) return false;
  liveHomes.add(isolatedHome);
  try {
    const emptyConfig = path.join(isolatedHome, "gitconfig");
    if (!(await fs.writeFile(emptyConfig, "").then(() => true, () => false))) return false;
    return await runClone({ ...run, gitArgs: HARDENED_GIT_ARGS, env: hardenedEnv(isolatedHome, emptyConfig), ownGroup: true });
  } finally {
    liveHomes.delete(isolatedHome);
    await fs.rm(isolatedHome, { recursive: true, force: true }).catch(() => {});
  }
}

/**
 * The parent's environment without any `GIT_*` variable or a variable the table
 * sets (names compared upper-cased), then the fixed hardening table.
 *
 * @param {string} isolatedHome
 * @param {string} emptyConfig
 * @returns {NodeJS.ProcessEnv}
 */
function hardenedEnv(isolatedHome, emptyConfig) {
  const table = {
    GIT_CONFIG_GLOBAL: emptyConfig,
    GIT_CONFIG_SYSTEM: emptyConfig,
    GIT_CONFIG_NOSYSTEM: "1",
    HOME: isolatedHome,
    USERPROFILE: isolatedHome,
    XDG_CONFIG_HOME: isolatedHome,
    GIT_ASKPASS: "",
    SSH_ASKPASS: "",
    GIT_TERMINAL_PROMPT: "0",
    GIT_LFS_SKIP_SMUDGE: "1",
    GIT_ALLOW_PROTOCOL: "https",
    GIT_PROTOCOL_FROM_USER: "0",
  };
  const kept = Object.entries(process.env).filter(([name]) => {
    const upper = name.toUpperCase();
    return !upper.startsWith("GIT_") && !Object.hasOwn(table, upper);
  });
  return { ...Object.fromEntries(kept), ...table };
}

/**
 * @param {{
 *   url: string,
 *   destDir: string,
 *   spawnFn: typeof spawn,
 *   timeoutMs: number,
 *   onStderr?: (text: string) => void,
 *   gitArgs: string[],
 *   env: NodeJS.ProcessEnv,
 *   ownGroup: boolean,
 * }} run
 * @returns {Promise<boolean>}
 */
function runClone({ url, destDir, spawnFn, timeoutMs, onStderr, gitArgs, env, ownGroup }) {
  return new Promise((resolve) => {
    const args = [...gitArgs, "clone", "--depth", "1", "--single-branch"];
    // Track before spawning: a signal between spawn and tracking would otherwise
    // take the default exit and leave the detached clone running.
    const tracker = ownGroup ? trackCloneGroup() : { add: () => {}, untrack: () => {} };
    /** @type {import("node:child_process").ChildProcess} */
    let child;
    try {
      child = spawnFn("git", [...args, "--", url, destDir], {
        stdio: ["ignore", "ignore", onStderr ? "pipe" : "ignore"],
        // Its own process group on POSIX, so a timeout can signal the remote helpers too.
        detached: ownGroup && process.platform !== "win32",
        env,
      });
    } catch (error) {
      tracker.untrack();
      throw error;
    }
    tracker.add(child);
    let stderr = "";
    child.stderr?.setEncoding("utf8");
    child.stderr?.on("data", (text) => {
      stderr += text;
    });
    const timer = setTimeout(() => (ownGroup ? killProcessTree(child) : child.kill()), timeoutMs);
    let finished = false;
    /** @param {boolean} ok */
    const finish = (ok) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      tracker.untrack();
      onStderr?.(stderr);
      resolve(ok);
    };
    child.on("close", (code) => finish(code === 0));
    child.on("error", () => finish(false));
  });
}

/** Live detached clone children, whose groups the parent kills if it dies first. */
const liveCloneGroups = new Set();

/** The signals whose default exit a listener would remove. */
const HANDLED_SIGNALS = /** @type {const} */ (["SIGHUP", "SIGINT", "SIGTERM"]);

/** Isolated homes of hardened clones in flight; an abnormal parent exit skips their `finally`. */
const liveHomes = new Set();

function killLiveCloneGroups() {
  for (const child of liveCloneGroups) killProcessTree(child);
  liveCloneGroups.clear();
  for (const home of liveHomes) {
    try {
      rmSync(home, { recursive: true, force: true });
    } catch {
      // A home that cannot be removed must not stop the exit.
    }
  }
  liveHomes.clear();
}

/** @param {NodeJS.Signals} signal */
function exitOnSignal(signal) {
  killLiveCloneGroups();
  // A signal listener removes Node's default exit, so drop ours and re-raise the
  // signal: the parent then dies the conventional way (128 + signal number).
  removeParentHandlers();
  process.kill(process.pid, signal);
}

/** @type {Array<[NodeJS.Signals, () => void]>} */
const signalListeners = HANDLED_SIGNALS.map((signal) => [signal, () => exitOnSignal(signal)]);

function installParentHandlers() {
  process.on("exit", killLiveCloneGroups);
  for (const [signal, listener] of signalListeners) process.on(signal, listener);
}

function removeParentHandlers() {
  process.off("exit", killLiveCloneGroups);
  for (const [signal, listener] of signalListeners) process.off(signal, listener);
}

/** Clones being spawned or live; the parent handlers exist while this is non-zero. */
let trackedClones = 0;

/**
 * Track a detached clone's process group so an abnormal parent exit (a signal or
 * `process.exit`) kills it instead of leaving it running. Call it before spawning:
 * the handlers are installed first, so a signal that arrives during the spawn is
 * handled on the event loop after `add` has run. Windows clones are not detached
 * and are left alone. The handlers exist only while a clone is tracked, so the
 * default signal behavior returns once the last one ends.
 *
 * @returns {{ add: (child: import("node:child_process").ChildProcess) => void, untrack: () => void }}
 */
function trackCloneGroup() {
  if (process.platform === "win32") return { add: () => {}, untrack: () => {} };
  if (trackedClones++ === 0) installParentHandlers();
  /** @type {import("node:child_process").ChildProcess | undefined} */
  let tracked;
  let done = false;
  return {
    add: (child) => {
      tracked = child;
      liveCloneGroups.add(child);
    },
    untrack: () => {
      if (done) return;
      done = true;
      if (tracked) liveCloneGroups.delete(tracked);
      if (--trackedClones === 0) removeParentHandlers();
    },
  };
}

/** @returns {number} How many clone process groups are currently tracked. */
export function liveCloneGroupCount() {
  return liveCloneGroups.size;
}

/**
 * Kill a child and its descendants (git's `git-remote-https` helpers): the
 * process group on POSIX, `taskkill /T` on Windows.
 *
 * @param {import("node:child_process").ChildProcess} child
 */
function killProcessTree(child) {
  if (child.pid === undefined) return;
  try {
    if (process.platform === "win32") {
      spawnSync("taskkill", ["/pid", String(child.pid), "/T", "/F"], { stdio: "ignore" });
    } else {
      process.kill(-child.pid, "SIGKILL");
    }
  } catch {
    child.kill("SIGKILL");
  }
}
