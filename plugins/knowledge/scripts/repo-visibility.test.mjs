// Run: node --test plugins/knowledge/scripts/repo-visibility.test.mjs
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { after, before, describe, it } from "node:test";

import { directoryVisibility, githubVisibility, gitRunner, main, parseGitHubRemote, userGitRunner } from "./repo-visibility.mjs";

const base = realpathSync(mkdtempSync(path.join(os.tmpdir(), "repo-visibility-test-")));
const gitConfig = path.join(base, "gitconfig");
const inherited = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith("GIT_")));
const env = { ...inherited, GIT_CONFIG_GLOBAL: gitConfig, GIT_CONFIG_NOSYSTEM: "1", GIT_CEILING_DIRECTORIES: base };

/** Real git through the script's isolated runner. */
const runGit = gitRunner(env);

/** Real git with the caller's environment passed through, as the script ran it before isolation. */
const leakyGit = (extra) => (args) => {
  const r = spawnSync("git", args, { env: { ...env, ...extra }, encoding: "utf8" });
  return { status: r.status, stdout: r.stdout ?? "", error: r.error };
};

/**
 * A gh stand-in answering as `gh api ... --jq .visibility` does, recording its
 * arguments: one answer for every repository, or one per `<owner>/<repo>`, a
 * repository missing from the map failing as gh does on a 404.
 */
function fakeGh(answers, status = 0) {
  const calls = [];
  const runGh = (args) => {
    calls.push(args);
    if (typeof answers === "string") return { status, stdout: answers };
    const answer = answers[args[3].replace(/^repos\//, "")];
    return answer === undefined ? { status: 1, stdout: "" } : { status, stdout: `${answer}\n` };
  };
  return { runGh, calls };
}

const SECRET = "https://github.com/acme/secret";
const OPEN = "https://github.com/acme/open";
const split = { "acme/secret": "private", "acme/open": "public" };

const loose = path.join(base, "loose");
const noRemote = path.join(base, "no-remote");
const onGitHub = path.join(base, "on-github");
const elsewhere = path.join(base, "elsewhere");
const upstreamOnly = path.join(base, "upstream-only");
const brokenGit = path.join(base, "broken-git");
const secretOnly = path.join(base, "secret-only");
const openOnly = path.join(base, "open-only");
const secondPublicRemote = path.join(base, "second-public-remote");
const publicPushUrl = path.join(base, "public-push-url");
const localPushRewrite = path.join(base, "local-push-rewrite");
const pinned = path.join(base, "pinned");

function git(cwd, ...args) {
  return execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false", ...args], {
    cwd,
    env,
    encoding: "utf8",
  }).trim();
}

function repo(dir, remotes) {
  mkdirSync(dir, { recursive: true });
  git(dir, "init", "-q");
  for (const [name, url] of remotes) git(dir, "remote", "add", name, url);
}

/** Commits pushed to a public origin and to a private remote, and one commit pushed nowhere. */
const commits = {};

before(() => {
  writeFileSync(gitConfig, "");
  mkdirSync(loose);
  repo(noRemote, []);
  repo(onGitHub, [["origin", "git@github.com:acme/corpus.git"]]);
  repo(elsewhere, [["origin", "https://gitlab.com/acme/corpus.git"]]);
  repo(upstreamOnly, [["upstream", "https://github.com/acme/corpus"]]);
  mkdirSync(path.join(brokenGit, "nested"), { recursive: true });
  writeFileSync(path.join(brokenGit, ".git"), "gitdir: missing\n");
  repo(secretOnly, [["origin", SECRET]]);
  repo(openOnly, [["origin", OPEN]]);
  repo(secondPublicRemote, [["origin", SECRET], ["pub", OPEN]]);
  repo(publicPushUrl, [["origin", SECRET]]);
  git(publicPushUrl, "remote", "set-url", "--push", "origin", OPEN);
  repo(localPushRewrite, [["origin", SECRET]]);
  git(localPushRewrite, "config", `url.${OPEN}.pushInsteadOf`, SECRET);

  repo(pinned, [["origin", OPEN], ["mirror", SECRET]]);
  git(pinned, "commit", "-q", "--allow-empty", "-m", "published");
  commits.published = git(pinned, "rev-parse", "HEAD");
  git(pinned, "update-ref", "refs/remotes/origin/main", "HEAD");
  git(pinned, "commit", "-q", "--allow-empty", "-m", "mirrored");
  commits.mirrored = git(pinned, "rev-parse", "HEAD");
  git(pinned, "update-ref", "refs/remotes/mirror/main", "HEAD");
  git(pinned, "commit", "-q", "--allow-empty", "-m", "unpushed");
  commits.unpushed = git(pinned, "rev-parse", "HEAD");
});

after(() => rmSync(base, { recursive: true, force: true }));

/** Sets `vars` on process.env for one call, restoring it after. */
function withEnv(vars, fn) {
  const saved = Object.fromEntries(Object.keys(vars).map((k) => [k, process.env[k]]));
  Object.assign(process.env, vars);
  try {
    return fn();
  } finally {
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  }
}

describe("parseGitHubRemote", () => {
  for (const url of [
    "https://github.com/acme/corpus",
    "https://github.com/acme/corpus.git",
    "https://github.com/acme/corpus/",
    "https://token@github.com/acme/corpus.git",
    "ssh://git@github.com/acme/corpus.git",
    "git@github.com:acme/corpus.git",
    "git://github.com/acme/corpus",
  ]) {
    it(`reads acme/corpus from ${url}`, () => {
      assert.deepEqual(parseGitHubRemote(url), { owner: "acme", repo: "corpus" });
    });
  }

  for (const url of [
    "https://gitlab.com/acme/corpus",
    "https://github.com.evil.example/acme/corpus",
    "https://github.com/acme",
    "https://github.com/acme/corpus/tree/main",
    "https://github.com/acme/cor;pus",
    "https://github.com/../corpus",
    "/srv/git/corpus.git",
  ]) {
    it(`reads nothing from ${url}`, () => {
      assert.equal(parseGitHubRemote(url), null);
    });
  }
});

describe("directoryVisibility", () => {
  it("is local outside git", () => {
    assert.equal(directoryVisibility(loose, { runGit, runGh: fakeGh("public").runGh }).visibility, "local");
  });

  it("is unknown when git fails where a .git exists, in the directory or an ancestor", () => {
    const dubious = () => ({ status: 128, stdout: "" });
    const missing = () => ({ status: null, stdout: "", error: new Error("spawnSync git ENOENT") });
    for (const [dir, git] of [
      [brokenGit, dubious],
      [path.join(brokenGit, "nested"), dubious],
      [path.join(brokenGit, "nested", "not-yet"), dubious],
      [noRemote, dubious],
      [noRemote, missing],
      [brokenGit, runGit],
    ]) {
      assert.equal(directoryVisibility(dir, { runGit: git, runGh: fakeGh("public").runGh }).visibility, "unknown", dir);
    }
  });

  it("is local when git fails and no .git exists in the directory or any ancestor", () => {
    const dubious = () => ({ status: 128, stdout: "" });
    assert.equal(directoryVisibility(loose, { runGit: dubious, runGh: fakeGh("public").runGh }).visibility, "local");
  });

  it("is local in a repository with no remote", () => {
    const r = directoryVisibility(noRemote, { runGit, runGh: fakeGh("public").runGh });
    assert.equal(r.visibility, "local");
    assert.equal(r.root, noRemote);
  });

  for (const answer of ["public", "private", "internal"]) {
    it(`reports ${answer} as GitHub answers it for the only remote, asking gh once`, () => {
      const gh = fakeGh(`${answer}\n`);
      const r = directoryVisibility(onGitHub, { runGit, runGh: gh.runGh });
      assert.deepEqual([r.visibility, r.repo, r.root], [answer, "acme/corpus", onGitHub]);
      assert.deepEqual(gh.calls, [["api", "--hostname", "github.com", "repos/acme/corpus", "--jq", ".visibility"]]);
    });
  }

  it("judges a directory that does not exist yet by the repository it would land in", () => {
    const r = directoryVisibility(path.join(onGitHub, "docs", "upstream"), { runGit, runGh: fakeGh("public").runGh });
    assert.equal(r.visibility, "public");
    assert.equal(r.root, onGitHub);
  });

  it("is unknown when gh fails, is missing, or gives any other answer", () => {
    const missing = () => ({ status: null, stdout: "", error: new Error("spawnSync gh ENOENT") });
    for (const runGh of [fakeGh("", 1).runGh, fakeGh("null\n").runGh, fakeGh("").runGh, fakeGh("Public\n").runGh, missing]) {
      assert.equal(directoryVisibility(onGitHub, { runGit, runGh }).visibility, "unknown");
    }
  });

  it("is unknown for a remote on another host, without asking gh", () => {
    const gh = fakeGh("private");
    assert.equal(directoryVisibility(elsewhere, { runGit, runGh: gh.runGh }).visibility, "unknown");
    assert.deepEqual(gh.calls, []);
  });

  it("reads a remote not named origin like any other", () => {
    const r = directoryVisibility(upstreamOnly, { runGit, runGh: fakeGh({ "acme/corpus": "private" }).runGh });
    assert.deepEqual([r.visibility, r.repo], ["private", "acme/corpus"]);
  });

  it("is private when its only remote is private", () => {
    const r = directoryVisibility(secretOnly, { runGit, runGh: fakeGh(split).runGh });
    assert.deepEqual([r.visibility, r.repo], ["private", "acme/secret"]);
  });

  it("is public when a second remote is public, though origin is private", () => {
    const r = directoryVisibility(secondPublicRemote, { runGit, runGh: fakeGh(split).runGh });
    assert.deepEqual([r.visibility, r.repo], ["public", "acme/open"]);
  });

  it("is public when origin's push URL is public, though its fetch URL is private", () => {
    const r = directoryVisibility(publicPushUrl, { runGit, runGh: fakeGh(split).runGh });
    assert.deepEqual([r.visibility, r.repo], ["public", "acme/open"]);
  });

  it("is public when the repository's own pushInsteadOf rewrites a private URL to a public one", () => {
    const r = directoryVisibility(localPushRewrite, { runGit, runGh: fakeGh(split).runGh });
    assert.deepEqual([r.visibility, r.repo], ["public", "acme/open"]);
  });

  it("is unknown when one remote cannot be proven and none reads public", () => {
    const gh = { "acme/secret": "private" };
    assert.equal(directoryVisibility(secondPublicRemote, { runGit, runGh: fakeGh(gh).runGh }).visibility, "unknown");
  });

  it("ignores a GIT_DIR in the caller's environment that names a private repository", () => {
    const hostile = { GIT_DIR: path.join(secretOnly, ".git") };
    const runGh = fakeGh(split).runGh;
    assert.equal(directoryVisibility(openOnly, { runGit: leakyGit(hostile), runUserGit: leakyGit(hostile), runGh }).visibility, "private");
    const r = withEnv(hostile, () => directoryVisibility(openOnly, { runGh }));
    assert.deepEqual([r.visibility, r.repo, r.root], ["public", "acme/open", openOnly]);
  });

  it("ignores an insteadOf rule in the caller's environment that rewrites a public URL to a private one", () => {
    const hostile = { GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: `url.${SECRET}.insteadOf`, GIT_CONFIG_VALUE_0: OPEN };
    const getUrl = ["-C", openOnly, "remote", "get-url", "origin"];
    assert.equal(leakyGit(hostile)(getUrl).stdout.trim(), SECRET);
    assert.equal(withEnv(hostile, () => gitRunner()(getUrl)).stdout.trim(), OPEN);
    const r = withEnv(hostile, () => directoryVisibility(openOnly, { runGh: fakeGh(split).runGh }));
    assert.deepEqual([r.visibility, r.repo], ["public", "acme/open"]);
  });

  describe("with a commit", () => {
    it("is public when a public remote's tracking ref holds the commit", () => {
      const r = directoryVisibility(pinned, { runGit, runGh: fakeGh(split).runGh, commit: commits.published });
      assert.deepEqual([r.visibility, r.repo], ["public", "acme/open"]);
    });

    it("is private, naming that remote's repository, when only a private remote's tracking ref holds the commit", () => {
      const r = directoryVisibility(pinned, { runGit, runGh: fakeGh(split).runGh, commit: commits.mirrored });
      assert.deepEqual([r.visibility, r.repo], ["private", "acme/secret"]);
    });

    it("is private for a local commit pushed nowhere, though origin is public", () => {
      const r = directoryVisibility(pinned, { runGit, runGh: fakeGh(split).runGh, commit: commits.unpushed });
      assert.equal(r.visibility, "private");
    });

    it("keeps a non-public reading as it is", () => {
      const r = directoryVisibility(secretOnly, { runGit, runGh: fakeGh(split).runGh, commit: commits.published });
      assert.equal(r.visibility, "private");
    });
  });
});

describe("the user's config and branch pointers", () => {
  const home = path.join(base, "home");
  const userEnv = { ...inherited, HOME: home, XDG_CONFIG_HOME: path.join(home, ".config") };
  /** Real git reading `home`'s .gitconfig as the user's global config. */
  const runUserGit = userGitRunner(userEnv);
  /** The same git with no user config at all. */
  const noUserConfig = gitRunner(env);
  const globalPushRewrite = path.join(base, "global-push-rewrite");
  const globalFetchRewrite = path.join(base, "global-fetch-rewrite");
  const pushRemoteUrl = path.join(base, "push-remote-url");
  const pointersOnly = path.join(base, "pointers-only");
  const localTracking = path.join(base, "local-tracking");
  const namedPushDefault = path.join(base, "named-push-default");
  let fetchedCommit;

  before(() => {
    mkdirSync(home);
    const SECRET2 = "https://github.com/acme/secret2";
    writeFileSync(
      path.join(home, ".gitconfig"),
      `[url "${OPEN}"]\n\tpushInsteadOf = ${SECRET}\n[url "${SECRET}"]\n\tinsteadOf = ${SECRET2}\n`,
    );
    repo(globalPushRewrite, [["origin", SECRET]]);
    repo(globalFetchRewrite, [["origin", OPEN]]);
    git(globalFetchRewrite, "config", "remote.origin.url", SECRET2);
    git(globalFetchRewrite, "config", "--add", "remote.origin.pushurl", OPEN);
    git(globalFetchRewrite, "commit", "-q", "--allow-empty", "-m", "fetched");
    fetchedCommit = git(globalFetchRewrite, "rev-parse", "HEAD");
    git(globalFetchRewrite, "update-ref", "refs/remotes/origin/main", "HEAD");
    repo(pushRemoteUrl, [["origin", SECRET]]);
    git(pushRemoteUrl, "config", "branch.main.pushRemote", OPEN);
    repo(pointersOnly, []);
    git(pointersOnly, "config", "branch.main.remote", OPEN);
    repo(localTracking, [["origin", SECRET]]);
    git(localTracking, "config", "branch.feature.remote", ".");
    repo(namedPushDefault, [["origin", SECRET]]);
    git(namedPushDefault, "config", "remote.pushDefault", "origin");
  });

  it("is public when the user's global pushInsteadOf rewrites a private push URL to a public one", () => {
    const r = directoryVisibility(globalPushRewrite, { runGit, runUserGit, runGh: fakeGh(split).runGh });
    assert.deepEqual([r.visibility, r.repo], ["public", "acme/open"]);
    const without = directoryVisibility(globalPushRewrite, { runGit, runUserGit: noUserConfig, runGh: fakeGh(split).runGh });
    assert.deepEqual([without.visibility, without.repo], ["private", "acme/secret"]);
  });

  it("ignores the user's config injected through GIT_CONFIG_* variables", () => {
    const injected = { ...env, GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: `url.${OPEN}.pushInsteadOf`, GIT_CONFIG_VALUE_0: SECRET };
    const r = directoryVisibility(secretOnly, { runGit, runUserGit: userGitRunner(injected), runGh: fakeGh(split).runGh });
    assert.deepEqual([r.visibility, r.repo], ["private", "acme/secret"]);
  });

  it("with a commit, is private when one fetch URL of the remote holding it reads private after the user's insteadOf", () => {
    const gh = { "acme/secret": "private", "acme/secret2": "public", "acme/open": "public" };
    const r = directoryVisibility(globalFetchRewrite, { runGit, runUserGit, runGh: fakeGh(gh).runGh, commit: fetchedCommit });
    assert.deepEqual([r.visibility, r.repo], ["private", "acme/secret"]);
    const without = directoryVisibility(globalFetchRewrite, { runGit, runUserGit: noUserConfig, runGh: fakeGh(gh).runGh, commit: fetchedCommit });
    assert.deepEqual([without.visibility, without.repo], ["public", "acme/secret2"]);
  });

  it("is public when a branch's pushRemote is a public URL rather than a remote name", () => {
    const r = directoryVisibility(pushRemoteUrl, { runGit, runUserGit: noUserConfig, runGh: fakeGh(split).runGh });
    assert.deepEqual([r.visibility, r.repo], ["public", "acme/open"]);
  });

  it("reads a branch remote URL in a repository with no remote, rather than local", () => {
    const r = directoryVisibility(pointersOnly, { runGit, runUserGit: noUserConfig, runGh: fakeGh(split).runGh });
    assert.deepEqual([r.visibility, r.repo], ["public", "acme/open"]);
  });

  describe("pointer URLs under push semantics", () => {
    const STAGING = "https://github.com/acme/staging";
    const gh = { ...split, "acme/staging": "private" };
    const pushDefaultHome = path.join(base, "push-default-home");
    const runPushDefaultGit = userGitRunner({ ...inherited, HOME: pushDefaultHome, XDG_CONFIG_HOME: path.join(pushDefaultHome, ".config") });
    const pushRewritten = path.join(base, "pointer-push-rewritten");
    const pushPlain = path.join(base, "pointer-push-plain");
    const fetchRewritten = path.join(base, "pointer-fetch-rewritten");

    before(() => {
      mkdirSync(pushDefaultHome);
      writeFileSync(path.join(pushDefaultHome, ".gitconfig"), `[remote]\n\tpushDefault = ${OPEN}\n`);
      for (const dir of [pushRewritten, pushPlain, fetchRewritten]) {
        repo(dir, [["origin", SECRET]]);
        git(dir, "config", "branch.main.pushRemote", STAGING);
      }
      git(pushRewritten, "config", `url.${OPEN}.pushInsteadOf`, STAGING);
      git(fetchRewritten, "config", `url.${OPEN}.insteadOf`, "https://github.com/acme/stag");
      git(fetchRewritten, "config", `url.${SECRET}.insteadOf`, STAGING);
    });

    it("is public when the user's global remote.pushDefault is a public URL", () => {
      const r = directoryVisibility(secretOnly, { runGit, runUserGit: runPushDefaultGit, runGh: fakeGh(gh).runGh });
      assert.deepEqual([r.visibility, r.repo], ["public", "acme/open"]);
      const without = directoryVisibility(secretOnly, { runGit, runUserGit: noUserConfig, runGh: fakeGh(gh).runGh });
      assert.deepEqual([without.visibility, without.repo], ["private", "acme/secret"]);
    });

    it("is public when pushInsteadOf rewrites a private pushRemote URL to a public one", () => {
      const r = directoryVisibility(pushRewritten, { runGit, runUserGit: noUserConfig, runGh: fakeGh(gh).runGh });
      assert.deepEqual([r.visibility, r.repo], ["public", "acme/open"]);
      const without = directoryVisibility(pushPlain, { runGit, runUserGit: noUserConfig, runGh: fakeGh(gh).runGh });
      assert.deepEqual([without.visibility, without.repo], ["private", "acme/secret"]);
    });

    it("takes the longest insteadOf prefix for a pointer URL, as git does", () => {
      const r = directoryVisibility(fetchRewritten, { runGit, runUserGit: noUserConfig, runGh: fakeGh(gh).runGh });
      assert.deepEqual([r.visibility, r.repo], ["private", "acme/secret"]);
    });
  });

  it("keeps a branch remote of '.' and a pushDefault naming a remote out of the URL set", () => {
    for (const dir of [localTracking, namedPushDefault]) {
      const r = directoryVisibility(dir, { runGit, runUserGit: noUserConfig, runGh: fakeGh(split).runGh });
      assert.deepEqual([r.visibility, r.repo], ["private", "acme/secret"], dir);
    }
  });
});

describe("githubVisibility", () => {
  it("refuses a name that is not a plain GitHub name before calling gh", () => {
    const gh = fakeGh("private");
    for (const [owner, repo] of [["..", "x"], ["acme", "a b"], ["acme", "--jq=."]]) {
      assert.equal(githubVisibility(owner, repo, { runGh: gh.runGh }).visibility, "unknown");
    }
    assert.deepEqual(gh.calls, []);
  });
});

describe("CLI", () => {
  const capture = () => {
    const io = { out: "", err: "" };
    io.stdout = { write: (s) => (io.out += s) };
    io.stderr = { write: (s) => (io.err += s) };
    return io;
  };

  it("prints one JSON line for a directory", () => {
    const io = capture();
    assert.equal(main([loose], { ...io, runGit }), 0);
    assert.equal(JSON.parse(io.out).visibility, "local");
    assert.equal(io.out.split("\n").length, 2);
  });

  it("reads a commit named with --commit", () => {
    const io = capture();
    assert.equal(main([pinned, "--commit", commits.unpushed], { ...io, runGit, runGh: fakeGh(split).runGh }), 0);
    assert.equal(JSON.parse(io.out).visibility, "private");
  });

  it("reads a repository named with --repo, dropping a .git suffix", () => {
    const io = capture();
    const gh = fakeGh("private\n");
    assert.equal(main(["--repo", "acme/corpus.git"], { ...io, runGh: gh.runGh }), 0);
    assert.deepEqual(JSON.parse(io.out), { visibility: "private", repo: "acme/corpus", root: null, reason: "reported by GitHub" });
  });

  it("exits 2 on usage errors and invalid names, printing nothing", () => {
    for (const argv of [
      [],
      ["a", "b"],
      ["--repo"],
      ["--repo", "acme"],
      ["--repo", "acme/x/y"],
      ["--repo", "../x"],
      ["--nope"],
      ["a", "--commit"],
      ["a", "--commit", "HEAD"],
      ["a", "--commit", "abc123"],
    ]) {
      const io = capture();
      assert.equal(main(argv, { ...io, runGh: fakeGh("public").runGh }), 2, argv.join(" "));
      assert.equal(io.out, "");
    }
  });

  it("runs as a script", () => {
    const r = spawnSync(process.execPath, [path.join(import.meta.dirname, "repo-visibility.mjs"), loose], { env, encoding: "utf8" });
    assert.equal(r.status, 0, r.stderr);
    assert.equal(JSON.parse(r.stdout).visibility, "local");
  });
});
