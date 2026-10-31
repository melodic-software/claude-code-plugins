#!/usr/bin/env node
/**
 * Who can read what lands in a directory, or in a named GitHub repository, as a
 * CLI for skills and an export for node code. Skills use it to keep private and
 * paid sources out of public repositories.
 *
 *   node repo-visibility.mjs <dir>                     the repository holding <dir>
 *   node repo-visibility.mjs <dir> --commit <sha>      whether that commit of it is public
 *   node repo-visibility.mjs --repo <owner>/<repo>     a GitHub repository by name
 *
 * Prints one JSON line: {"visibility": ..., "repo": "<owner>/<repo>" | null,
 * "root": "<git top-level>" | null, "reason": "..."}. `visibility` is one of:
 *
 *   public | private | internal   what GitHub reports. A directory reads
 *             private or internal only when every URL it could fetch from or
 *             push to names a GitHub repository that GitHub reports as private
 *             or internal; any URL that reads public makes it public
 *   local     no `.git` in the directory or any ancestor, or a working tree with
 *             no remote: nothing can be published
 *   unknown   a `.git` that git cannot read (dubious ownership, a corrupt
 *             repository, git missing), or a remote URL whose visibility cannot
 *             be read (a host other than github.com, gh missing or not signed in,
 *             an API error, any other answer) when no URL reads public; callers
 *             treat it as public
 *
 * The verdicts are ordered private < internal < local < unknown < public, and a
 * directory takes the highest verdict among its URLs. Those URLs are every
 * remote's url and pushurl as configured, as the repository's own config
 * rewrites them, and as the user's global and system config rewrite them
 * (insteadOf and pushInsteadOf), plus any branch.<name>.remote,
 * branch.<name>.pushRemote or remote.pushDefault value that is a URL rather
 * than a configured remote name.
 *
 * With --commit, a directory that reads public reads public only when the commit
 * is in a remote-tracking ref of a remote whose fetch URLs, after insteadOf
 * rewriting, all read public; otherwise it reads private, since the commit was
 * never published.
 *
 * Git runs with -C and without the caller's GIT_* environment, so an inherited
 * GIT_DIR or an env-injected config entry (GIT_CONFIG_COUNT and the rest) changes
 * nothing. Reading the repository runs with global and system config pointed at
 * the null device; listing the remotes runs a second time with the user's own
 * global and system config files, and the URLs of both listings count.
 *
 * A directory that does not exist yet is judged by its nearest existing ancestor
 * directory, so a new directory inside a public repository reads as public.
 *
 * Exit: 0 printed a visibility (any of the five); 2 usage, or an invalid name.
 */
import { spawnSync } from "node:child_process";
import { lstatSync, realpathSync, statSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const NAME = /^[A-Za-z0-9._-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const VISIBLE = new Set(["public", "private", "internal"]);
const RANK = { private: 0, internal: 1, local: 2, unknown: 3, public: 4 };
const TIMEOUT_MS = 30_000;
const CONFIG_KEYS =
  "^(remote\\..+\\.(url|pushurl)|branch\\..+\\.(remote|pushremote)|remote\\.pushdefault|url\\..+\\.(insteadof|pushinsteadof))$";

/**
 * @typedef {{ status: number | null, stdout: string, error?: Error }} RunResult
 * @typedef {(args: string[]) => RunResult} Runner
 * @typedef {{ visibility: "public" | "private" | "internal" | "local" | "unknown", repo: string | null, root: string | null, reason: string }} Visibility
 * @typedef {{ fetch: Set<string>, push: Set<string>, configured: Set<string> }} RemoteUrls
 * @typedef {{ remote: string, url: string }} LabeledUrl
 */

/** @param {string} command @param {NodeJS.ProcessEnv} env @returns {Runner} */
function runner(command, env) {
  return (args) => {
    const r = spawnSync(command, args, { env, encoding: "utf8", timeout: TIMEOUT_MS, stdio: ["ignore", "pipe", "ignore"] });
    return { status: r.status, stdout: r.stdout ?? "", error: r.error };
  };
}

/**
 * `env` without any GIT_* variable.
 *
 * @param {NodeJS.ProcessEnv} env
 * @returns {NodeJS.ProcessEnv}
 */
function withoutGitVars(env) {
  return Object.fromEntries(Object.entries(env).filter(([name]) => !name.toUpperCase().startsWith("GIT_")));
}

/**
 * `env` without any GIT_* variable, with global and system git config pointed at
 * the null device.
 *
 * @param {NodeJS.ProcessEnv} env
 * @returns {NodeJS.ProcessEnv}
 */
export function isolatedGitEnv(env) {
  return { ...withoutGitVars(env), GIT_CONFIG_GLOBAL: os.devNull, GIT_CONFIG_SYSTEM: os.devNull, GIT_CONFIG_NOSYSTEM: "1" };
}

/**
 * A git runner isolated from `env` as isolatedGitEnv describes.
 *
 * @param {NodeJS.ProcessEnv} [env]
 * @returns {Runner}
 */
export function gitRunner(env = process.env) {
  return runner("git", isolatedGitEnv(env));
}

/**
 * A git runner without any GIT_* variable of `env`, so git reads the user's own
 * global and system config files (found from HOME and XDG_CONFIG_HOME) and no
 * env-injected config entry.
 *
 * @param {NodeJS.ProcessEnv} [env]
 * @returns {Runner}
 */
export function userGitRunner(env = process.env) {
  return runner("git", withoutGitVars(env));
}

/**
 * A GitHub owner or repository name that is safe to put in an API path.
 *
 * @param {string} name
 * @returns {boolean}
 */
export function isValidName(name) {
  return NAME.test(name) && name !== "." && name !== "..";
}

/**
 * The `<owner>/<repo>` a github.com remote URL names, or null for any other host
 * or form. Accepts https, ssh and git URLs and the scp-like `git@github.com:o/r`.
 *
 * @param {string} url
 * @returns {{ owner: string, repo: string } | null}
 */
export function parseGitHubRemote(url) {
  const m =
    /^(?:https?|ssh|git):\/\/(?:[^@/]+@)?github\.com(?::\d+)?\/([^/]+)\/([^/]+?)\/?$/i.exec(url.trim()) ??
    /^(?:[^@/]+@)?github\.com:([^/]+)\/([^/]+?)\/?$/i.exec(url.trim());
  if (!m) return null;
  const owner = m[1];
  const repo = m[2].replace(/\.git$/i, "");
  return isValidName(owner) && isValidName(repo) ? { owner, repo } : null;
}

/**
 * The visibility GitHub reports for `<owner>/<repo>`.
 *
 * @param {string} owner
 * @param {string} repo
 * @param {{ runGh?: Runner }} [options]
 * @returns {Visibility}
 */
export function githubVisibility(owner, repo, { runGh = runner("gh", process.env) } = {}) {
  const name = `${owner}/${repo}`;
  if (!isValidName(owner) || !isValidName(repo)) {
    return { visibility: "unknown", repo: null, root: null, reason: `not a valid GitHub name: ${name}` };
  }
  const r = runGh(["api", "--hostname", "github.com", `repos/${owner}/${repo}`, "--jq", ".visibility"]);
  const answer = r.stdout.trim();
  if (r.error || r.status !== 0) {
    return { visibility: "unknown", repo: name, root: null, reason: `gh could not read ${name}` };
  }
  if (!VISIBLE.has(answer)) {
    return { visibility: "unknown", repo: name, root: null, reason: `gh answered an unrecognized visibility for ${name}` };
  }
  return { visibility: /** @type {Visibility["visibility"]} */ (answer), repo: name, root: null, reason: "reported by GitHub" };
}

/**
 * Whether `p` is a directory, following symlinks; false when it cannot be read.
 *
 * @param {string} p
 * @returns {boolean}
 */
function isDirectory(p) {
  try {
    return statSync(p, { throwIfNoEntry: false })?.isDirectory() ?? false;
  } catch {
    return false;
  }
}

/**
 * The nearest existing ancestor directory of `dir`, itself included. A file or
 * device in the path (a sandbox masks paths with the null device) is skipped,
 * since git cannot run from it.
 *
 * @param {string} dir
 * @returns {string}
 */
function nearestExisting(dir) {
  let current = path.resolve(dir);
  while (!isDirectory(current)) {
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
  return current;
}

/**
 * Whether `dir` or any ancestor holds a `.git` entry of any kind. A `.git` that
 * cannot be checked counts as present.
 *
 * @param {string} dir
 * @returns {boolean}
 */
export function insideGitEntry(dir) {
  for (let current = dir; ; current = path.dirname(current)) {
    try {
      if (lstatSync(path.join(current, ".git"), { throwIfNoEntry: false })) return true;
    } catch (e) {
      if (e?.code !== "ENOTDIR") return true;
    }
    if (path.dirname(current) === current) return false;
  }
}

/**
 * Every remote's URLs, and the branch.<name>.remote, branch.<name>.pushRemote and
 * remote.pushDefault values that name no configured remote, or null when git
 * cannot list them. A remote's `fetch` and `push` are the URLs `git remote -v`
 * prints under the repository's own config and under the user's config;
 * `configured` are its url and pushurl values as written in either view. Pointer
 * keys are read in both views too. A pointer value of `.` names the repository
 * itself and publishes nothing; any other pointer value counts as written and as
 * each view rewrites it for fetch (insteadOf) and for push (pushInsteadOf, else
 * insteadOf), the longest matching prefix winning as in git.
 *
 * @param {string} cwd
 * @param {Runner} runGit
 * @param {Runner} runUserGit
 * @returns {{ remotes: Map<string, RemoteUrls>, pointers: LabeledUrl[] } | null}
 */
function remoteUrls(cwd, runGit, runUserGit) {
  const views = [runGit, runUserGit];
  const listings = views.map((run) => run(["-C", cwd, "remote", "-v"]));
  const configs = views.map((run) => run(["-C", cwd, "config", "-z", "--get-regexp", CONFIG_KEYS]));
  const failed = (r) => r.error || r.status !== 0;
  if (listings.some(failed) || configs.some((r) => r.error || (r.status !== 0 && r.status !== 1))) return null;
  /** @type {Map<string, RemoteUrls>} */
  const remotes = new Map();
  const remote = (name) => {
    if (!remotes.has(name)) remotes.set(name, { fetch: new Set(), push: new Set(), configured: new Set() });
    return /** @type {RemoteUrls} */ (remotes.get(name));
  };
  for (const listed of listings) {
    for (const line of listed.stdout.split("\n")) {
      const m = /^(\S+)\t(.+) \((fetch|push)\)$/.exec(line);
      if (m) remote(m[1])[/** @type {"fetch" | "push"} */ (m[3])].add(m[2]);
    }
  }
  /** @type {LabeledUrl[]} */
  const named = [];
  /** @type {{ insteadof: [string, string][], pushinsteadof: [string, string][] }[]} */
  const rules = [];
  for (const config of configs) {
    /** @type {{ insteadof: [string, string][], pushinsteadof: [string, string][] }} */
    const view = { insteadof: [], pushinsteadof: [] };
    rules.push(view);
    for (const item of config.stdout.split("\0")) {
      const cut = item.indexOf("\n");
      if (cut < 0) continue;
      const key = item.slice(0, cut);
      const value = item.slice(cut + 1);
      const url = /^remote\.(.+)\.(url|pushurl)$/i.exec(key);
      const rewrite = /^url\.(.+)\.(insteadof|pushinsteadof)$/i.exec(key);
      if (url) remote(url[1]).configured.add(value);
      else if (rewrite) view[/** @type {"insteadof" | "pushinsteadof"} */ (rewrite[2].toLowerCase())].push([value, rewrite[1]]);
      else named.push({ remote: key, url: value });
    }
  }
  /** @type {LabeledUrl[]} */
  const pointers = [];
  for (const { remote: key, url } of named) {
    if (url === "." || remotes.has(url)) continue;
    pointers.push({ remote: key, url });
    for (const view of rules) {
      pointers.push({ remote: key, url: rewritten(url, view.insteadof) });
      pointers.push({ remote: key, url: rewritten(url, view.pushinsteadof, view.insteadof) });
    }
  }
  return { remotes, pointers };
}

/**
 * `url` with its longest prefix matching a rule in `rules` replaced by that rule's
 * base, else by the longest match in `fallback`, else unchanged.
 *
 * @param {string} url
 * @param {[string, string][]} rules [prefix, base] pairs
 * @param {[string, string][]} [fallback]
 * @returns {string}
 */
function rewritten(url, rules, fallback = []) {
  for (const set of [rules, fallback]) {
    const match = set.filter(([prefix]) => url.startsWith(prefix)).sort(([a], [b]) => b.length - a.length)[0];
    if (match) return match[1] + url.slice(match[0].length);
  }
  return url;
}

/**
 * The visibility of a set of remote URLs, folded over the order private <
 * internal < local < unknown < public: the highest verdict by default, the
 * lowest with `lowest`. `repo` is the deciding repository, the first one read on
 * a tie. An empty set reads unknown.
 *
 * @param {LabeledUrl[]} urls
 * @param {(owner: string, repo: string) => Visibility} lookup
 * @param {{ lowest?: boolean }} [options]
 * @returns {Visibility}
 */
function urlsVisibility(urls, lookup, { lowest = false } = {}) {
  if (urls.length === 0) return { visibility: "unknown", repo: null, root: null, reason: "no remote URL to read" };
  /** @type {Visibility[]} */
  const results = urls.map(({ remote, url }) => {
    const parsed = parseGitHubRemote(url);
    if (!parsed) return { visibility: "unknown", repo: null, root: null, reason: `a URL of ${remote} is not a github.com repository` };
    const r = lookup(parsed.owner, parsed.repo);
    return { ...r, reason: `${remote}: ${r.reason}` };
  });
  const decided = results.reduce((a, b) => {
    const delta = RANK[b.visibility] - RANK[a.visibility];
    return (lowest ? delta < 0 : delta > 0) ? b : a;
  });
  return decided.visibility === "private" && !lowest ? { ...decided, reason: "every remote URL is private" } : decided;
}

/**
 * The visibility of the repository that holds `dir`. With `commit`, a public
 * repository reads public only when the commit is in a remote-tracking ref of a
 * remote whose every fetch URL reads public.
 *
 * @param {string} dir
 * @param {{ runGit?: Runner, runUserGit?: Runner, runGh?: Runner, commit?: string }} [options]
 * @returns {Visibility}
 */
export function directoryVisibility(
  dir,
  { runGit = gitRunner(), runUserGit = userGitRunner(), runGh = runner("gh", process.env), commit } = {},
) {
  const cwd = nearestExisting(dir);
  const top = runGit(["-C", cwd, "rev-parse", "--show-toplevel"]);
  if (top.error || top.status !== 0 || !top.stdout.trim()) {
    if (insideGitEntry(cwd)) return { visibility: "unknown", repo: null, root: null, reason: "git could not read the repository" };
    return { visibility: "local", repo: null, root: null, reason: "no .git in the directory or any ancestor" };
  }
  const root = path.resolve(top.stdout.trim());
  const listed = remoteUrls(cwd, runGit, runUserGit);
  if (!listed) return { visibility: "unknown", repo: null, root, reason: "git could not list the remotes" };
  const { remotes, pointers } = listed;
  if (remotes.size === 0 && pointers.length === 0) return { visibility: "local", repo: null, root, reason: "no remote" };

  /** @type {Map<string, Visibility>} */
  const seen = new Map();
  const lookup = (owner, repo) => {
    const key = `${owner}/${repo}`.toLowerCase();
    if (!seen.has(key)) seen.set(key, githubVisibility(owner, repo, { runGh }));
    return /** @type {Visibility} */ (seen.get(key));
  };
  const ordered = [...remotes].sort(([a], [b]) => (a === "origin" ? -1 : b === "origin" ? 1 : 0));
  const all = [
    ...ordered.flatMap(([name, { fetch, push, configured }]) =>
      [...new Set([...fetch, ...push, ...configured])].map((url) => ({ remote: `remote ${name}`, url })),
    ),
    ...pointers,
  ];
  const whole = { ...urlsVisibility(all, lookup), root };
  if (commit === undefined || whole.visibility !== "public") return whole;

  const first = all.map(({ url }) => parseGitHubRemote(url)).find(Boolean);
  /** @type {Visibility} */
  const notPublished = {
    visibility: "private",
    repo: first ? `${first.owner}/${first.repo}` : null,
    root,
    reason: `commit ${commit} is on no public remote`,
  };
  if (!SHA.test(commit)) return { ...notPublished, reason: "not a full commit id" };
  const refs = runGit(["-C", cwd, "for-each-ref", "--contains", commit, "--format=%(refname)", "refs/remotes/"]);
  if (refs.error || refs.status !== 0) return notPublished;
  const names = [...remotes.keys()].sort((a, b) => b.length - a.length);
  /** @type {string | null} */
  let holder = null;
  for (const ref of refs.stdout.split("\n").filter(Boolean)) {
    const remote = names.find((name) => ref.startsWith(`refs/remotes/${name}/`));
    if (!remote) continue;
    const fetched = [...(remotes.get(remote)?.fetch ?? [])].map((url) => ({ remote: `remote ${remote}`, url }));
    if (fetched.length === 0) continue;
    const r = urlsVisibility(fetched, lookup, { lowest: true });
    if (r.visibility === "public") return { ...r, root, reason: `commit ${commit} is in ${ref}, ${r.reason}` };
    holder ??= r.repo;
  }
  return { ...notPublished, repo: holder ?? notPublished.repo };
}

/**
 * @param {string[]} argv
 * @param {{ stdout?: { write: (s: string) => void }, stderr?: { write: (s: string) => void }, runGit?: Runner, runUserGit?: Runner, runGh?: Runner }} [io]
 * @returns {number}
 */
export function main(argv, { stdout = process.stdout, stderr = process.stderr, runGit, runUserGit, runGh } = {}) {
  const usage = "Usage: node repo-visibility.mjs <dir> [--commit <sha>] | --repo <owner>/<repo>\n";
  let result;
  if (argv.length === 2 && argv[0] === "--repo") {
    const [owner, repo, extra] = argv[1].split("/");
    if (extra !== undefined || !owner || !repo || !isValidName(owner) || !isValidName(repo.replace(/\.git$/i, ""))) {
      stderr.write(`not a valid <owner>/<repo>: ${argv[1]}\n${usage}`);
      return 2;
    }
    result = githubVisibility(owner, repo.replace(/\.git$/i, ""), runGh ? { runGh } : {});
  } else if ((argv.length === 1 || (argv.length === 3 && argv[1] === "--commit")) && !argv[0].startsWith("-")) {
    const commit = argv[2];
    if (commit !== undefined && !SHA.test(commit)) {
      stderr.write(`not a full 40-character lowercase commit id: ${commit}\n${usage}`);
      return 2;
    }
    result = directoryVisibility(argv[0], {
      ...(runGit && { runGit }),
      ...(runUserGit && { runUserGit }),
      ...(runGh && { runGh }),
      ...(commit && { commit }),
    });
  } else {
    stderr.write(usage);
    return 2;
  }
  stdout.write(`${JSON.stringify(result)}\n`);
  return 0;
}

/** @returns {boolean} whether this module is the script node was started with */
function isMain() {
  try {
    return Boolean(process.argv[1]) && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMain()) {
  process.exitCode = main(process.argv.slice(2));
}
