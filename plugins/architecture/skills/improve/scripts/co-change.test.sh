#!/usr/bin/env bash
# Behavioral tests for co-change.mjs: builds fixture repositories with known
# histories and asserts the hand-computed pair counts, degrees, citing commits,
# clusters, spread, focus and mixed folders; each filter; the too-little-history
# report; the settings files through the config cascade; and that two runs give
# the same bytes.
#
#   bash plugins/architecture/skills/improve/scripts/co-change.test.sh
#
# Exit 0 clean, 1 findings, 2 environment (node or git missing).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

for tool in node git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "co-change: $tool not found on PATH" >&2
    exit 2
  fi
done

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

node --input-type=module - "$SCRIPT_DIR" "$work" <<'NODE'
import { appendFileSync, mkdirSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";

const [dir, work] = process.argv.slice(2);
const env = {
  ...process.env,
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_CEILING_DIRECTORIES: work,
  GIT_AUTHOR_EMAIL: "author@example.com",
  GIT_COMMITTER_NAME: "fixture",
  GIT_COMMITTER_EMAIL: "fixture@example.com",
};

let failed = 0;
const check = (name, cond, detail) => {
  if (cond) {
    console.log(`ok: ${name}`);
  } else {
    console.error(`FAIL: ${name}${detail ? ` - ${detail}` : ""}`);
    failed += 1;
  }
};
const same = (x, y) => JSON.stringify(x) === JSON.stringify(y);

const git = (repo, args, extra = {}) => {
  const run = spawnSync("git", ["-C", repo, ...args], { encoding: "utf8", env: { ...env, ...extra } });
  if (run.status !== 0) throw new Error(`git ${args.join(" ")}: ${run.stderr}`);
  return run.stdout;
};
let serial = 0;
const commit = (repo, author, files) => {
  for (const file of files) {
    mkdirSync(dirname(join(repo, file)), { recursive: true });
    serial += 1;
    appendFileSync(join(repo, file), `${serial}\n`);
  }
  git(repo, ["add", "--", ...files]);
  git(repo, ["-c", "commit.gpgsign=false", "commit", "-q", "-m", `change ${serial}`], { GIT_AUTHOR_NAME: author });
  return git(repo, ["rev-parse", "HEAD"]).trim();
};
const newRepo = (name) => {
  const repo = join(work, name);
  mkdirSync(repo, { recursive: true });
  git(repo, ["init", "-q"]);
  return repo;
};
const run = (repo, ...args) => spawnSync("node", [`${dir}/co-change.mjs`, "--repo", repo, ...args], { encoding: "utf8", env });
const report = (repo, ...args) => {
  const result = run(repo, ...args);
  if (result.status !== 0) throw new Error(`co-change ${args.join(" ")} exited ${result.status}: ${result.stderr}`);
  return JSON.parse(result.stdout);
};
const pair = (r, a, b) => r.pairs.find((p) => p.a === a && p.b === b);

// The fixture history, oldest first.
const A = "src/orders/a.js";
const B = "src/orders/b.js";
const C = "src/shared/c.js";
const X = "src/billing/x.js";
const Y = "src/billing/y.js";
const Z = "src/shared/z.js";
const Q = "src/misc/q.js";
const M = "src/misc/m.js";
const N = "src/misc/n.js";
const U = "src/ui/u.js";
const V = "src/ui/v.js";
const BIG = ["big/s1.txt", "big/s2.txt", "big/s3.txt", "big/s4.txt", "big/s5.txt"];
const repo = newRepo("main");
const h = [null];
h.push(commit(repo, "alice", [A, B, C])); // 1
h.push(commit(repo, "alice", [A, B, C])); // 2
h.push(commit(repo, "bob", [A, B, C])); // 3
h.push(commit(repo, "carol", [X, Y, Z])); // 4
h.push(commit(repo, "carol", [X, Y, Z])); // 5
h.push(commit(repo, "alice", BIG)); // 6: five files, over a change-set limit of 4
h.push(commit(repo, "alice", BIG)); // 7
h.push(commit(repo, "release[bot]", ["docs/p.md", "docs/r.md"])); // 8: a bot author
h.push(commit(repo, "release[bot]", ["docs/p.md", "docs/r.md"])); // 9
h.push(commit(repo, "alice", ["lone.txt"])); // 10: one commit, below a minimum of 2
h.push(commit(repo, "dave", [X, Q])); // 11: x and q share one commit
h.push(commit(repo, "dave", [Q])); // 12
h.push(commit(repo, "erin", [M, N])); // 13: m and n share two commits
h.push(commit(repo, "erin", [M, N])); // 14
for (let i = 15; i <= 18; i += 1) h.push(commit(repo, "erin", [M])); // 15-18: m reaches 6
h.push(commit(repo, "erin", [N])); // 19: n reaches 3, degree floor(200*2/9) = 44
for (let i = 20; i <= 25; i += 1) h.push(commit(repo, "frank", [U, V])); // 20-25: six shared

const base = ["--no-config", "--history-commits", "100", "--min-revs", "2", "--min-shared-revs", "2", "--min-coupling", "50", "--max-coupling", "100", "--max-changeset-size", "4", "--min-cluster-size", "3"];
const r = report(repo, ...base);

check("the window counts read, kept and dropped commits", same(r.window, { history_commits: 100, read: 25, kept: 21, dropped: { excluded_authors: 2, oversized: 2, no_files: 0 } }), JSON.stringify(r.window));
check("the history is enough", r.history === "enough", r.history);
check("the files reaching the commit minimum, with their counts", same(r.files.map((f) => [f.path, f.revs]), [[X, 3], [Y, 2], [M, 6], [N, 3], [Q, 2], [A, 3], [B, 3], [C, 3], [Z, 2], [U, 6], [V, 6]]), JSON.stringify(r.files));
check("seven pairs pass, sorted", same(r.pairs.map((p) => [p.a, p.b]), [[X, Y], [X, Z], [Y, Z], [A, B], [A, C], [B, C], [U, V]]), JSON.stringify(r.pairs.map((p) => [p.a, p.b])));
check("x-y: 2 shared of 3 and 2 commits is degree 80", same(pair(r, X, Y), { a: X, b: Y, shared: 2, revs_a: 3, revs_b: 2, degree: 80, commits: [h[5], h[4]], cluster: "c1" }), JSON.stringify(pair(r, X, Y)));
check("y-z: 2 shared of 2 and 2 commits is degree 100", pair(r, Y, Z).degree === 100 && pair(r, Y, Z).shared === 2);
check("a-b cites its three commits newest first", same(pair(r, A, B).commits, [h[3], h[2], h[1]]) && pair(r, A, B).degree === 100);
check("u-v cites five of its six commits, newest first", same(pair(r, U, V).commits, [h[25], h[24], h[23], h[22], h[21]]) && pair(r, U, V).shared === 6);
check("a pair in no cluster carries cluster null", pair(r, U, V).cluster === null);
check("two clusters of three files", same(r.clusters.map((c) => [c.id, c.files]), [["c1", [X, Y, Z]], ["c2", [A, B, C]]]), JSON.stringify(r.clusters.map((c) => c.files)));
check("c1 spans two folders with their file counts", same(r.clusters[0].folders, [{ folder: "src/billing", cluster_files: 2, folder_files: 2 }, { folder: "src/shared", cluster_files: 1, folder_files: 2 }]), JSON.stringify(r.clusters[0].folders));
check("c1 spread 2, focus 0.83, unclassified", r.clusters[0].spread === 2 && r.clusters[0].focus === 0.83 && r.clusters[0].pattern === "unclassified", JSON.stringify(r.clusters[0]));
check("c2 spread 2, focus 0.83", r.clusters[1].spread === 2 && r.clusters[1].focus === 0.83);
check("src/shared is a mixed folder of both clusters", same(r.mixed_folders, [{ folder: "src/shared", clusters: ["c1", "c2"] }]) && same(r.clusters[0].mixed_folders, ["src/shared"]), JSON.stringify(r.mixed_folders));
check("two runs give identical output", run(repo, ...base).stdout === run(repo, ...base).stdout);

const depth = report(repo, ...base, "--folder-depth", "1");
check("folder_depth 1 groups each cluster into src", same(depth.clusters[0].folders, [{ folder: "src", cluster_files: 3, folder_files: 11 }]), JSON.stringify(depth.clusters[0].folders));
check("one folder at focus 0.27 is well-confined", depth.clusters[0].spread === 1 && depth.clusters[0].focus === 0.27 && depth.clusters[0].pattern === "well-confined", JSON.stringify(depth.clusters[0]));
check("a lower encapsulated cutoff names it well-encapsulated", report(repo, ...base, "--folder-depth", "1", "--encapsulated-min-focus", "0.2").clusters[0].pattern === "well-encapsulated");

// Each filter: left out under the base settings, back in when that setting is loosened.
const hasBig = (x) => x.pairs.some((p) => p.a.startsWith("big/"));
const loose = report(repo, ...base, "--max-changeset-size", "5");
check("an oversized change set is left out", !hasBig(r) && r.window.dropped.oversized === 2);
check("the oversized change set returns under a larger limit", hasBig(loose) && loose.clusters.some((c) => same(c.files, BIG)));
check("an excluded author is left out by the default [bot] rule", !pair(r, "docs/p.md", "docs/r.md") && r.settings.values.exclude_authors[0] === "[bot]");
check("the excluded author's pair returns with --all-authors", pair(report(repo, ...base, "--all-authors"), "docs/p.md", "docs/r.md")?.shared === 2);
check("a file below the commit minimum is left out", !r.files.some((f) => f.path === "lone.txt"));
check("that file returns at --min-revs 1", report(repo, ...base, "--min-revs", "1").files.some((f) => f.path === "lone.txt" && f.revs === 1));
check("a pair below the shared-commit minimum is left out", !pair(r, X, Q) && !pair(report(repo, ...base, "--min-coupling", "0"), X, Q));
check("that pair returns at --min-shared-revs 1", pair(report(repo, ...base, "--min-shared-revs", "1", "--min-coupling", "0"), X, Q)?.degree === 40);
check("a pair below the coupling range is left out", !pair(r, M, N));
check("that pair returns at --min-coupling 40, degree 44", pair(report(repo, ...base, "--min-coupling", "40"), M, N)?.degree === 44);
const capped = report(repo, ...base, "--max-coupling", "90");
check("a pair above the coupling range is left out", !pair(capped, A, B) && pair(capped, X, Y)?.degree === 80);

// Too little history: two commits cannot reach the default minimums.
const small = newRepo("small");
commit(small, "alice", ["a.txt", "b.txt"]);
commit(small, "alice", ["a.txt", "b.txt"]);
const thin = report(small, "--no-config");
check("too little history is reported with the window and the surviving count", thin.history === "too-little" && thin.message.includes("too little history") && thin.message.includes("2 of 2 commits") && thin.message.includes("window 500"), thin.message);
check("too little history shows no candidate", thin.pairs.length === 0 && thin.clusters.length === 0);
check("the defaults come from the schema", same(thin.settings.values, { history_commits: 500, min_revs: 5, min_shared_revs: 5, min_coupling: 30, max_coupling: 100, max_changeset_size: 30, exclude_authors: ["[bot]"], folder_depth: 0, min_cluster_size: 4, encapsulated_min_focus: 0.8, crosscutting_min_spread: 4, crosscutting_max_focus: 0.3 }), JSON.stringify(thin.settings.values));

// A repository with no commits is too little history, not an error.
const empty = newRepo("empty");
const none = report(empty, "--no-config");
check("a repository with no commits reports too little history", none.history === "too-little" && none.window.read === 0, JSON.stringify(none.window));

// A path git quotes is counted as the path on disk, and a ./ scope matches.
const quoted = newRepo("quoted");
for (let i = 0; i < 2; i += 1) commit(quoted, "alice", ['src/say "hi".txt', "src/plain.txt"]);
const quotedReport = report(quoted, "--no-config", "--min-revs", "2", "--min-shared-revs", "2", "--path", "./src");
check("a quoted path is unquoted and a ./ scope matches", same(quotedReport.files.map((f) => f.path), ["src/plain.txt", 'src/say "hi".txt']), JSON.stringify(quotedReport.files));

// The team file, through the config cascade.
mkdirSync(join(small, "docs/conventions"), { recursive: true });
const teamFile = join(small, "docs/conventions/architecture.yaml");
writeFileSync(teamFile, 'layout:\n  min_revs: 2\n  exclude_authors:\n    - "melodic-release[bot]"\n');
const valid = report(small);
check("a valid team file sets its keys", valid.settings.values.min_revs === 2 && same(valid.settings.values.exclude_authors, ["melodic-release[bot]"]) && valid.settings.source.min_revs === "team" && valid.settings.errors.length === 0, JSON.stringify(valid.settings));
check("an argument beats the team file", report(small, "--min-revs", "3").settings.values.min_revs === 3);
writeFileSync(teamFile, "layout:\n  min_revs: 2\n  bogus: 1\n");
const unknown = report(small);
check("an unknown layout key is an error", unknown.settings.errors.some((e) => e.includes("bogus") && e.includes("unknown key")), JSON.stringify(unknown.settings.errors));
writeFileSync(teamFile, "layout:\n  min_revs: 0\n");
const invalid = report(small);
check("a value the schema rejects is an error and falls back to the default", invalid.settings.errors.length === 1 && invalid.settings.values.min_revs === 5, JSON.stringify(invalid.settings));

// Usage and environment.
check("an unknown flag exits 2", run(repo, "--bogus").status === 2);
check("a value below its minimum exits 2", run(repo, "--min-revs", "0").status === 2);
check("a fractional integer exits 2", run(repo, "--min-revs", "1.5").status === 2);
check("min_coupling above max_coupling exits 2", run(repo, "--no-config", "--min-coupling", "60", "--max-coupling", "50").status === 2);
const plain = join(work, "plain");
mkdirSync(plain);
check("a directory outside any git work tree exits 2", run(plain, "--no-config").status === 2);

process.exit(failed ? 1 : 0);
NODE
