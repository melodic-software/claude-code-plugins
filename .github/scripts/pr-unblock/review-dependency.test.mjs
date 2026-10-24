import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { ciStatusOf, countRounds, main, readConfig, readPolicy, roundLine, rounds, select as selectLive } from "./review-dependency.mjs";

// No registry reads in tests: the provenance gate finds nothing unless a test
// passes its own, and the policy lists nothing unless a test passes its own.
const select = (args) => selectLive({ provenance: async () => [], policy: { autoMerge: { reviewOnly: [] } }, ...args });

const HEAD = "a".repeat(40);
const OTHER = "b".repeat(40);
const APP = 337595936;
const DEPENDABOT = 49699333;

// GitHub verified and committed it, as it does Dependabot's commits.
const SIGNED = { committer: { email: "noreply@github.com" }, verification: { verified: true, reason: "valid" } };
const dependabotCommit = (sha, message = "bump") => ({
  sha,
  commit: { message, author: { name: "dependabot[bot]", email: "49699333+dependabot[bot]@users.noreply.github.com" }, ...SIGNED },
});

function fakeApi({ pull = {}, comments = [], ciRuns = [], files = [], modelRuns = {}, commits = null, commitFiles = {} } = {}) {
  const listed = commits ?? [HEAD, ...Object.keys(modelRuns).filter((sha) => sha !== HEAD)].map((sha) => dependabotCommit(sha));
  return {
    getCommit: async (sha) => ({ sha, files: (commitFiles[sha] ?? []).map((filename) => ({ filename })) }),
    getPull: async () => ({
      number: 7,
      user: { id: DEPENDABOT, login: "dependabot[bot]" },
      head: { ref: "dependabot/npm_and_yarn/x-2.0.0", sha: HEAD },
      title: "build(deps): bump x from 1.4.0 to 2.0.0",
      body: "Bumps x from 1.4.0 to 2.0.0.",
      labels: [{ name: "dependencies" }],
      changed_files: files.length,
      commits: listed.length,
      ...pull,
    }),
    listIssueComments: async () => comments,
    listPullFiles: async () => files,
    listPullCommits: async () => listed,
    listCheckRuns: async (sha, name) => (name === "ci-status" ? ciRuns : (modelRuns[sha] ?? [])),
  };
}

const marker = (head, verdict, id = APP) => ({ user: { id }, body: `${roundLine({ head, verdict, run: "1-1" })}\nbody` });

test("the round line round-trips and only the lanes App's copies count", () => {
  const comments = [marker(HEAD, "fix"), marker(OTHER, "merge", 1), { user: { id: APP }, body: "no marker" }];
  assert.deepEqual(rounds(comments, APP), [{ head: HEAD, verdict: "fix", run: "1-1" }]);
  assert.equal(countRounds(comments, APP, [HEAD]), 1);
});

test("ci-status is the newest GitHub Actions run's conclusion, or pending", () => {
  assert.equal(ciStatusOf([]), "pending");
  assert.equal(
    ciStatusOf([
      { id: 1, app: { slug: "github-actions" }, status: "completed", conclusion: "failure" },
      { id: 2, app: { slug: "github-actions" }, status: "in_progress", conclusion: null },
      { id: 3, app: { slug: "someone-else" }, status: "completed", conclusion: "success" },
    ]),
    "pending",
  );
  assert.equal(ciStatusOf([{ id: 4, app: { slug: "github-actions" }, status: "completed", conclusion: "failure" }]), "failure");
});

test("select skips a pull request Dependabot did not open", async () => {
  const result = await select({
    api: fakeApi({ pull: { user: { id: 5, login: "someone" } } }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [],
  });
  assert.equal(result.decision, "skip");
  assert.equal(result.skipReason, "not-applicable");
});

test("select skips a pull request whose head moved since the gate", async () => {
  const args = { pr: 7, appId: APP, dependabotId: DEPENDABOT, config: [] };
  const result = await select({ api: fakeApi({ pull: { head: { ref: "dependabot/npm_and_yarn/x-2.0.0", sha: OTHER } } }), headSha: HEAD, ...args });
  assert.deepEqual([result.decision, result.skipReason, result.file], ["skip", "superseded-sha", undefined]);
});

test("select marks a files listing at the REST cap as truncated", async () => {
  const files = Array.from({ length: 3000 }, (_, i) => ({ filename: `f${i}`, status: "modified", additions: 1, deletions: 0, patch: "" }));
  const args = { pr: 7, headSha: HEAD, appId: APP, dependabotId: DEPENDABOT, config: [] };
  assert.equal((await select({ api: fakeApi({ files }), ...args })).file.files_truncated, true);
  assert.equal((await select({ api: fakeApi({ files: files.slice(0, 2999) }), ...args })).file.files_truncated, false);
});

test("select skips an auto-tier bump, which pr-merge owns", async () => {
  const result = await select({
    api: fakeApi({ pull: { title: "bump x from 1.4.0 to 1.5.0" }, ciRuns: [] }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [],
  });
  assert.equal(result.decision, "skip");
  assert.equal(result.skipReason, "not-applicable");
});

test("select proceeds on a major bump and writes the context file", async () => {
  const result = await select({
    api: fakeApi({ files: [{ filename: "package.json", status: "modified", additions: 1, deletions: 1, patch: "@@ -1 +1 @@" }] }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [["npm", "/"]],
    repository: "o/r",
  });
  assert.equal(result.decision, "proceed");
  assert.equal(result.file.head_sha, HEAD);
  assert.equal(result.file.classification.tier, "review");
  assert.deepEqual(result.file.classification.reasons, ["major:x"]);
  assert.equal(result.file.files[0].patch, "@@ -1 +1 @@");
  assert.equal(result.file.rounds, 0);
});

test("select reviews a red ci-status even on a patch bump", async () => {
  const result = await select({
    api: fakeApi({
      pull: { title: "bump x from 1.4.0 to 1.4.1" },
      ciRuns: [{ id: 1, app: { slug: "github-actions" }, status: "completed", conclusion: "failure" }],
    }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [],
  });
  assert.equal(result.decision, "proceed");
  assert.deepEqual(result.file.classification.reasons, ["ci-status-red"]);
});

const POLICY = {
  autoMerge: {
    reviewOnly: [
      { repository: "o/r", ecosystem: "npm", directory: "/", dependency: "x", reviewed: "2026-10-17", basis: "runs with a secret", control: "docs/x.md#control" },
    ],
  },
};
const ROOT_FILES = [{ filename: "package.json", status: "modified", additions: 1, deletions: 1, patch: "@@ -1 +1 @@" }];
const selectMinor = (policy) =>
  select({
    api: fakeApi({ pull: { title: "bump x from 1.4.0 to 1.5.0" }, files: ROOT_FILES, ciRuns: [] }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [["npm", "/"]],
    policy,
    repository: "o/r",
  });

test("select proceeds on a minor bump of a review-only dependency and hands the model its control", async () => {
  const result = await selectMinor(POLICY);
  assert.equal(result.decision, "proceed");
  assert.deepEqual(result.file.classification.reasons, ["review-only:x"]);
  assert.equal(result.file.classification.reviewOnly[0].control, "docs/x.md#control");
});

test("select skips a minor bump of an unlisted dependency and reviews every bump when the policy is unreadable", async () => {
  const unlisted = structuredClone(POLICY);
  unlisted.autoMerge.reviewOnly[0].dependency = "y";
  assert.equal((await selectMinor(unlisted)).decision, "skip");
  const result = await selectMinor(null);
  assert.equal(result.decision, "proceed");
  assert.deepEqual(result.file.classification.reasons, ["dependabot-policy-unreadable"]);
});

test("readPolicy is the parsed file, or null with a warning when missing or not JSON", () => {
  const dir = mkdtempSync(join(tmpdir(), "dependabot-policy-"));
  const warnings = [];
  const log = (line) => warnings.push(line);
  assert.equal(readPolicy(join(dir, "absent.json"), log), null);
  writeFileSync(join(dir, "bad.json"), "{not json");
  assert.equal(readPolicy(join(dir, "bad.json"), log), null);
  writeFileSync(join(dir, "ok.json"), JSON.stringify(POLICY));
  assert.deepEqual(readPolicy(join(dir, "ok.json"), log), POLICY);
  assert.equal(warnings.length, 2);
  assert.match(warnings[0], /^::warning::cannot read the Dependabot policy .*ENOENT/);
});

test("readConfig is null for a missing file and for one with no entry, each with its own warning", () => {
  const dir = mkdtempSync(join(tmpdir(), "dependabot-config-"));
  const warnings = [];
  const log = (line) => warnings.push(line);
  assert.equal(readConfig(join(dir, "absent.yml"), log), null);
  writeFileSync(join(dir, "empty.yml"), "version: 2\nupdates: []\n");
  assert.equal(readConfig(join(dir, "empty.yml"), log), null, "as the pr-merge lane's parse_config");
  writeFileSync(join(dir, "ok.yml"), "version: 2\nupdates:\n  - package-ecosystem: npm\n    directory: /\n");
  assert.deepEqual(readConfig(join(dir, "ok.yml"), log), [["npm", "/"]]);
  assert.equal(warnings.length, 2);
  assert.match(warnings[0], /^::warning::cannot read the Dependabot config .*ENOENT/);
  assert.match(warnings[1], /^::warning::the Dependabot config .* has no updates entry that reads/);
});

test("select reports an unreadable config as its own reason and output", async () => {
  const result = await select({
    api: fakeApi({ pull: { title: "bump x from 1.4.0 to 1.4.1" }, files: [{ filename: "package-lock.json" }] }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: null,
  });
  assert.equal(result.decision, "proceed");
  assert.deepEqual(result.file.classification.reasons, ["dependabot-config-unreadable"]);
});

test("select applies the content rule from the base's dependabot.yml", async () => {
  const config = [["npm", "/"]];
  const args = { pr: 7, headSha: HEAD, appId: APP, dependabotId: DEPENDABOT, config };
  const pull = { title: "bump x from 1.4.0 to 1.4.1" };
  const clean = await select({ api: fakeApi({ pull, files: [{ filename: "package-lock.json", patch: "" }] }), ...args });
  assert.equal(clean.decision, "skip");
  const odd = await select({ api: fakeApi({ pull, files: [{ filename: "package-lock.json" }, { filename: "dist/x.js" }] }), ...args });
  assert.equal(odd.decision, "proceed");
  assert.deepEqual(odd.file.classification.reasons, ["dependabot-content:dist/x.js"]);
});

test("select sorts a patch bump review when the commits listing is short of the pull request's total", async () => {
  const args = { pr: 7, headSha: HEAD, appId: APP, dependabotId: DEPENDABOT, config: [["npm", "/"]] };
  const files = [{ filename: "package-lock.json", patch: "" }];
  const whole = await select({ api: fakeApi({ pull: { title: "bump x from 1.4.0 to 1.4.1" }, files }), ...args });
  assert.equal(whole.decision, "skip");
  const capped = await select({ api: fakeApi({ pull: { title: "bump x from 1.4.0 to 1.4.1", commits: 251 }, files }), ...args });
  assert.equal(capped.decision, "proceed");
  assert.deepEqual(capped.file.classification.reasons, ["commits-listed:1-of:251"]);
});

test("select reads the metadata in Dependabot's commits, and not in another author's", async () => {
  const message = [
    "bump x",
    "---",
    "updated-dependencies:",
    "- dependency-name: y",
    "  dependency-version: 1.4.1",
    "  update-type: version-update:semver-patch",
    "...",
  ].join("\n");
  const args = { pr: 7, headSha: HEAD, appId: APP, dependabotId: DEPENDABOT, config: [["npm", "/"]] };
  const pull = { title: "bump x from 1.4.0 to 1.4.1" };
  const disagree = await select({ api: fakeApi({ pull, commits: [dependabotCommit(HEAD, message)] }), ...args });
  assert.equal(disagree.decision, "proceed");
  assert.deepEqual(disagree.file.classification.reasons, ["sources-disagree"]);
  const other = { sha: HEAD, commit: { message, author: { name: "someone", email: "someone@example.test" }, ...SIGNED } };
  const ignored = await select({ api: fakeApi({ pull, commits: [other] }), ...args });
  assert.deepEqual(
    ignored.file.classification.reasons,
    [`commit-not-dependabot:${HEAD.slice(0, 12)}`],
    "another author's commit is review, and its metadata is not read",
  );
});

test("select counts a version-bump commit's paths as checked", async () => {
  const bump = {
    sha: OTHER,
    commit: {
      message: "chore: bump [dependabot skip]",
      author: { name: "github-actions[bot]", email: "41898282+github-actions[bot]@users.noreply.github.com" },
      ...SIGNED,
    },
  };
  const files = [{ filename: "package-lock.json" }, { filename: "plugins/x/CHANGELOG.md" }];
  const result = await select({
    api: fakeApi({ pull: { title: "bump x from 1.4.0 to 1.4.1" }, files, commits: [dependabotCommit(HEAD), bump], commitFiles: { [OTHER]: ["plugins/x/CHANGELOG.md"] } }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [["npm", "/"]],
  });
  assert.equal(result.decision, "skip");
});

test("select counts no round marker at a head the pull request no longer has", async () => {
  // #9131: `@dependabot recreate` replaced the reviewed commit, leaving two
  // markers at a head that is not among the current commits.
  const result = await select({
    api: fakeApi({ comments: [marker(OTHER, "merge"), marker(OTHER, "merge")] }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [],
    maxRounds: 2,
  });
  assert.equal(result.decision, "proceed");
  assert.equal(result.rounds, 0);
});

test("select counts the round marker at a current commit and not the one at a replaced head", async () => {
  const result = await select({
    api: fakeApi({ comments: [marker(OTHER, "merge"), marker(HEAD, "fix")] }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [],
    maxRounds: 2,
  });
  assert.equal(result.decision, "proceed");
  assert.equal(result.rounds, 1);
});

test("select counts a round marker that names no head toward the cap", async () => {
  const headless = { user: { id: APP }, body: "<!-- pr-unblock:review-dependency-round verdict=merge run=1-1 -->\nbody" };
  const result = await select({
    api: fakeApi({ comments: [headless, marker(HEAD, "fix")] }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [],
    maxRounds: 2,
  });
  assert.equal(result.decision, "escalate");
  assert.equal(result.rounds, 2);
});

test("select escalates once the round cap is reached, counting markers or model check runs", async () => {
  const byMarker = await select({
    api: fakeApi({ comments: [marker(OTHER, "fix"), marker(HEAD, "fix")], commits: [dependabotCommit(OTHER), dependabotCommit(HEAD)] }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [],
    maxRounds: 2,
  });
  assert.equal(byMarker.decision, "escalate");
  assert.equal(byMarker.escalationReason, "dependency-round-cap");
  assert.equal(byMarker.rounds, 2);
  const ran = [{ name: "pr-unblock / review-dependency", app: { slug: "github-actions" }, conclusion: "success" }];
  const byCheck = await select({
    api: fakeApi({ modelRuns: { [OTHER]: ran, [HEAD]: ran } }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [],
    maxRounds: 2,
  });
  assert.equal(byCheck.decision, "escalate");
});

test("select caps each patch and the total it hands the model", async () => {
  const big = "x".repeat(50_000);
  const files = Array.from({ length: 30 }, (_, i) => ({ filename: `f${i}`, status: "modified", additions: 1, deletions: 0, patch: big }));
  const result = await select({ api: fakeApi({ files }), pr: 7, headSha: HEAD, appId: APP, dependabotId: DEPENDABOT, config: [] });
  const patches = result.file.files.map((file) => file.patch ?? "");
  assert.ok(patches.every((patch) => patch.length <= 20_000 + 40));
  assert.ok(patches.join("").length <= 300_000 + 40 * 30);
  assert.equal(result.file.files.length, 30);
});

test("main writes the outputs, the context file and the run fields, with the security flag", async () => {
  const dir = mkdtempSync(join(tmpdir(), "review-dependency-"));
  const actors = join(dir, "actors.json");
  writeFileSync(actors, JSON.stringify({ actors: [{ id: DEPENDABOT, login: "dependabot[bot]", kind: "bot" }] }));
  const env = {
    GITHUB_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    GITHUB_OUTPUT: join(dir, "out"),
    PR_NUMBER: "7",
    HEAD_SHA: HEAD,
    APP_SENDER_ID: String(APP),
    TRUSTED_ACTORS: actors,
    DEPENDENCY_FILE: join(dir, "dependency.json"),
    CONTEXT_RUN_FILE: join(dir, "context.json"),
    DEPENDENCY_REVIEW_ROUNDS: "2",
    DEPENDABOT_CONFIG: join(dir, "dependabot.yml"),
    DEPENDABOT_POLICY: join(dir, "policy.json"),
  };
  const now = () => new Date("2026-10-22T10:11:12.345Z");
  await main(["select"], env, { api: fakeApi({ pull: { labels: [{ name: "security" }] } }), log: () => {}, now });
  const out = readFileSync(env.GITHUB_OUTPUT, "utf8");
  assert.equal(out, "proceed=true\nskip-reason=\nescalation-reason=\n");
  assert.equal(JSON.parse(readFileSync(env.DEPENDENCY_FILE, "utf8")).pr, 7);
  // The verdict job's run fields, one JSON line: the security label, no
  // config file (the main test points at none), the time to the second.
  assert.equal(
    readFileSync(env.CONTEXT_RUN_FILE, "utf8"),
    `${JSON.stringify({
      version: 1,
      pr: 7,
      head_sha: HEAD,
      security: true,
      config_unreadable: true,
      files_truncated: false,
      started_at: "2026-10-22T10:11:12Z",
      controls: [],
      config: [],
    })}\n`,
  );
});

test("main writes no context or run file when the select skips", async () => {
  const dir = mkdtempSync(join(tmpdir(), "review-dependency-"));
  const actors = join(dir, "actors.json");
  writeFileSync(actors, JSON.stringify({ actors: [{ id: DEPENDABOT, login: "dependabot[bot]", kind: "bot" }] }));
  const env = {
    GITHUB_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    GITHUB_OUTPUT: join(dir, "out"),
    PR_NUMBER: "7",
    HEAD_SHA: HEAD,
    APP_SENDER_ID: String(APP),
    TRUSTED_ACTORS: actors,
    DEPENDENCY_FILE: join(dir, "dependency.json"),
    CONTEXT_RUN_FILE: join(dir, "context.json"),
    DEPENDABOT_CONFIG: join(dir, "dependabot.yml"),
    DEPENDABOT_POLICY: join(dir, "policy.json"),
  };
  await main(["select"], env, { api: fakeApi({ pull: { head: { sha: "f".repeat(40), ref: "dependabot/npm_and_yarn/x" } } }), log: () => {} });
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), "proceed=false\nskip-reason=superseded-sha\nescalation-reason=\n");
  assert.equal(existsSync(env.DEPENDENCY_FILE), false);
  assert.equal(existsSync(env.CONTEXT_RUN_FILE), false);
});

// main over a readable base config and policy, with the registry stubbed.
async function mainWith({ title, policy = POLICY, provenance = async () => [] }) {
  const dir = mkdtempSync(join(tmpdir(), "review-dependency-"));
  const actors = join(dir, "actors.json");
  writeFileSync(actors, JSON.stringify({ actors: [{ id: DEPENDABOT, login: "dependabot[bot]", kind: "bot" }] }));
  writeFileSync(join(dir, "dependabot.yml"), "updates:\n  - package-ecosystem: npm\n    directory: /\n");
  writeFileSync(join(dir, "policy.json"), JSON.stringify(policy));
  const env = {
    GITHUB_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    GITHUB_OUTPUT: join(dir, "out"),
    PR_NUMBER: "7",
    HEAD_SHA: HEAD,
    APP_SENDER_ID: String(APP),
    TRUSTED_ACTORS: actors,
    DEPENDENCY_FILE: join(dir, "dependency.json"),
    CONTEXT_RUN_FILE: join(dir, "context.json"),
    DEPENDABOT_CONFIG: join(dir, "dependabot.yml"),
    DEPENDABOT_POLICY: join(dir, "policy.json"),
  };
  const lines = [];
  await main(["select"], env, { api: fakeApi({ pull: { title }, files: ROOT_FILES }), log: (line) => lines.push(line), provenance });
  const run = existsSync(env.CONTEXT_RUN_FILE) ? JSON.parse(readFileSync(env.CONTEXT_RUN_FILE, "utf8")) : null;
  return { out: readFileSync(env.GITHUB_OUTPUT, "utf8"), run, warnings: lines.filter((line) => line.startsWith("::warning::")) };
}

test("main records the matched review-only controls and the base config's pairs for the verdict job to check", async () => {
  const { out, run } = await mainWith({ title: "bump x from 1.4.0 to 1.5.0" });
  assert.match(out, /^proceed=true$/m);
  assert.deepEqual(run.controls, ["docs/x.md#control"]);
  assert.deepEqual(run.config, [["npm", "/"]]);
  assert.equal(run.config_unreadable, false);
});

test("main warns of a classifier gap when only a parse failure sends a pull request to review", async () => {
  const unparsed = await mainWith({ title: "chore: tidy" });
  assert.equal(unparsed.warnings.length, 1);
  assert.match(unparsed.warnings[0], /classifier gap: #7 .*unparsed-updates/);
  const unread = await mainWith({ title: "bump y from 1.4.0 to 1.5.0", provenance: async () => ["provenance-unreadable:y"] });
  assert.match(unread.warnings.join("\n"), /classifier gap: #7 .*provenance-unreadable:y/);
  // A real risk beside the gap, or a skip, is no classifier gap.
  assert.deepEqual((await mainWith({ title: "bump x from 1.4.0 to 2.0.0", policy: { autoMerge: { reviewOnly: [] } } })).warnings, []);
  assert.deepEqual((await mainWith({ title: "bump y from 1.4.0 to 1.5.0" })).warnings, []);
  assert.deepEqual((await mainWith({ title: "bump y from 1.4.0 to 1.5.0", provenance: async () => ["provenance-changed:y"] })).warnings, []);
});

test("select sends an otherwise auto bump whose provenance changed to review", async () => {
  const result = await select({
    api: fakeApi({ pull: { title: "bump y from 1.4.0 to 1.5.0" }, files: ROOT_FILES }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [["npm", "/"]],
    policy: POLICY,
    repository: "o/r",
    provenance: async (updates, segment) => (segment === "npm_and_yarn" && updates[0].version === "1.5.0" ? ["provenance-changed:y"] : []),
  });
  assert.equal(result.decision, "proceed");
  assert.deepEqual(result.file.classification.reasons, ["provenance-changed:y"]);
});
