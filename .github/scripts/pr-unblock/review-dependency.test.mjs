import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { ciStatusOf, countRounds, gateHoldOnly, main, newestRound, readConfig, readPolicy, roundLine, rounds, select as selectLive } from "./review-dependency.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

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

function fakeApi({ pull = {}, comments = [], gateRuns = [], ciRuns = [], annotations = {}, files = [], modelRuns = {}, commits = null, commitFiles = {}, texts = {} } = {}) {
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
    getText: async (path) => texts[path] ?? null,
    listIssueComments: async () => comments,
    listPullFiles: async () => files,
    listPullCommits: async () => listed,
    listCheckRuns: async (sha, name) => ({ "CI Status": gateRuns, "ci-status": ciRuns })[name] ?? modelRuns[sha] ?? [],
    listAnnotations: async (id) => {
      if (!Object.hasOwn(annotations, id)) throw new Error(`GET check-runs/${id}/annotations returned 500`);
      return annotations[id];
    },
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

// The contract-only ci-status a full run in flight superseded, as GitHub
// annotated it on the run that sent #10776 to a person.
const EXIT = { annotation_level: "failure", message: "Process completed with exit code 1." };
const superseded = (sha) => ({
  annotation_level: "failure",
  message: `superseded by full run https://github.com/o/r/actions/runs/40778283306 in flight on ${sha}: its own ci-status check run is newer than this one and decides the merge gate.`,
});
const NOTICE = { annotation_level: "notice", message: "github-token=2 not-modified=0" };
const supersededRun = { id: 9, app: { slug: "github-actions" }, status: "completed", conclusion: "failure" };
const patchBump = (annotations) =>
  select({
    api: fakeApi({ pull: { title: "bump x from 1.4.0 to 1.4.1" }, ciRuns: [supersededRun], annotations }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [],
  });

test("select does not read a ci-status a full run in flight superseded as red", async () => {
  const result = await patchBump({ 9: [EXIT, superseded(HEAD), NOTICE] });
  assert.equal(result.decision, "skip");
  assert.equal(result.skipReason, "not-applicable");
  assert.equal(result.classification.reasons.includes("ci-status-red"), false);
});

test("select reads CI Status's superseded note, not its ci-status alias's red", async () => {
  const alias = { id: 10, app: { slug: "github-actions" }, status: "completed", conclusion: "failure" };
  const result = await select({
    api: fakeApi({ pull: { title: "bump x from 1.4.0 to 1.4.1" }, gateRuns: [supersededRun], ciRuns: [alias], annotations: { 9: [EXIT, superseded(HEAD)] } }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [],
  });
  assert.equal(result.decision, "skip");
  assert.equal(result.classification.reasons.includes("ci-status-red"), false);
});

test("select keeps a superseded-looking ci-status red unless only the marker for this head explains it", async () => {
  for (const annotations of [
    { 9: [EXIT, superseded(OTHER)] },
    { 9: [EXIT, superseded(HEAD), { annotation_level: "failure", message: "check-contract: the title is not a Conventional Commit" }] },
    { 9: [EXIT, NOTICE] },
    { 9: [] },
    {},
  ]) {
    const result = await patchBump(annotations);
    assert.equal(result.decision, "proceed", JSON.stringify(annotations));
    assert.deepEqual(result.file.classification.reasons, ["ci-status-red"]);
  }
});

const gateHold = (pr) => ({
  annotation_level: "failure",
  message: `#${pr} is by an author no review lane reviews and changes trust-gate paths: .github/workflows/maintenance-repin-ci-workflows.yml .github/workflows/release-publish-plugins.yml. A person merges it; a person on the trusted-actor list approving this head clears it.`,
});
const majorBump = (annotations) =>
  select({ api: fakeApi({ gateRuns: [supersededRun], annotations }), pr: 7, headSha: HEAD, appId: APP, dependabotId: DEPENDABOT, config: [] });

test("select skips a pull request whose only CI Status failure is the trust-gate hold, with no model turn, escalation or label", async () => {
  const result = await majorBump({ 9: [NOTICE, EXIT, gateHold(7), NOTICE] });
  assert.equal(result.decision, "skip");
  assert.equal(result.skipReason, "gate-hold");
  assert.equal(result.escalationReason, undefined, "no escalation, so no needs-human label and no security reason");
  assert.equal(result.file, undefined, "no context file, so no model turn");
});

test("select hands the model a trust-gate hold for another pull request, or one beside another failure", async () => {
  const contract = { annotation_level: "failure", message: "check-contract: the title is not a Conventional Commit" };
  for (const annotations of [{ 9: [EXIT, gateHold(8)] }, { 9: [EXIT, gateHold(7), contract] }, { 9: [EXIT] }, {}]) {
    const result = await majorBump(annotations);
    assert.equal(result.decision, "proceed", JSON.stringify(annotations));
    assert.deepEqual(result.file.classification.reasons, ["major:x", "ci-status-red"]);
    assert.equal(result.file.merge_clears_gate_hold, false, JSON.stringify(annotations));
  }
});

const verdictHold = (pr) => ({
  annotation_level: "failure",
  message: `#${pr} by Dependabot swaps only action refs, each to a tagged commit, on trust-gate paths: .github/workflows/ci.yml, and merge.dependabot.trusted-action-owners does not list the owner of: evilcorp/setup-tool. The lanes App's review-dependency verdict=merge at this head clears it, as does a person on the trusted-actor list approving this head.`,
});

test("select hands the model a trust-gate hold a merge verdict clears, and tells it so", async () => {
  const result = await majorBump({ 9: [NOTICE, EXIT, verdictHold(7)] });
  assert.equal(result.decision, "proceed");
  assert.equal(result.skipReason, undefined);
  assert.equal(result.file.merge_clears_gate_hold, true);
  assert.deepEqual(result.file.classification.reasons, ["major:x", "ci-status-red"]);
});

test("the CDN pins record hold is one a merge verdict clears (owner decision Q154 A)", async () => {
  const pinsHold = (pr) => ({
    annotation_level: "failure",
    message: `#${pr} by Dependabot changes only the CDN pins record on trust-gate paths: lib/cdn-pins/pins.json. The lanes App's review-dependency verdict=merge at this head clears it, as does a person on the trusted-actor list approving this head.`,
  });
  assert.equal(gateHoldOnly([EXIT, pinsHold(7)], 7), "verdict");
  assert.equal(gateHoldOnly([EXIT, pinsHold(8)], 7), false);
  assert.equal(gateHoldOnly([EXIT, pinsHold(7), gateHold(7)], 7), "person");
  const result = await majorBump({ 9: [EXIT, pinsHold(7)] });
  assert.equal(result.decision, "proceed");
  assert.equal(result.file.merge_clears_gate_hold, true);
});

test("a merge-verdict hold for another pull request, or beside another failure, is not one the verdict clears", async () => {
  const contract = { annotation_level: "failure", message: "check-contract: the title is not a Conventional Commit" };
  for (const annotations of [{ 9: [EXIT, verdictHold(8)] }, { 9: [EXIT, verdictHold(7), contract] }]) {
    const result = await majorBump(annotations);
    assert.equal(result.decision, "proceed", JSON.stringify(annotations));
    assert.equal(result.file.merge_clears_gate_hold, false, JSON.stringify(annotations));
  }
  const both = await majorBump({ 9: [EXIT, verdictHold(7), gateHold(7)] });
  assert.deepEqual([both.decision, both.skipReason], ["skip", "gate-hold"], "a hold only a person clears beside it wins");
});

test("newestRound is the lanes App's newest marker by comment time, or null", () => {
  const at = (comment, created_at, id) => ({ ...comment, created_at, id });
  const comments = [
    at(marker(HEAD, "merge"), "2026-11-23T10:05:00Z", 3),
    at(marker(OTHER, "fix"), "2026-11-23T10:01:00Z", 9),
    at(marker(OTHER, "escalate", 1), "2026-11-23T10:09:00Z", 10),
  ];
  assert.deepEqual(newestRound(comments, APP), { head: HEAD, verdict: "merge", run: "1-1", createdAt: "2026-11-23T10:05:00Z" });
  assert.equal(newestRound([...comments, at({ user: { id: APP }, body: "<!-- pr-unblock:review-dependency-round head=x -->" }, "2026-11-23T10:07:00Z", 11)], APP), null);
  assert.equal(newestRound([at(marker(HEAD, "merge", 1), "2026-11-23T10:05:00Z", 3)], APP), null);
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
  const dir = tempDir("dependabot-policy-");
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
  const dir = tempDir("dependabot-config-");
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

test("select makes a github-actions[bot] commit review, even one touching only covered files", async () => {
  const actions = {
    sha: OTHER,
    commit: {
      message: "chore: bump [dependabot skip]",
      author: { name: "github-actions[bot]", email: "41898282+github-actions[bot]@users.noreply.github.com" },
      ...SIGNED,
    },
  };
  const files = [{ filename: "package-lock.json" }];
  const result = await select({
    api: fakeApi({ pull: { title: "bump x from 1.4.0 to 1.4.1" }, files, commits: [dependabotCommit(HEAD), actions], commitFiles: { [OTHER]: ["package-lock.json"] } }),
    pr: 7,
    headSha: HEAD,
    appId: APP,
    dependabotId: DEPENDABOT,
    config: [["npm", "/"]],
  });
  assert.equal(result.decision, "proceed");
  assert.deepEqual(result.file.classification.reasons, [`commit-not-dependabot:${OTHER.slice(0, 12)}`]);
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

test("select counts every round marker when the commits listing is not the whole pull request", async () => {
  // The listing stops at 250 commits, so a head missing from it proves nothing.
  const result = await select({
    api: fakeApi({ pull: { commits: 251 }, comments: [marker(HEAD, "fix"), marker(HEAD, "fix")], commits: [dependabotCommit(OTHER)] }),
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
  const dir = tempDir("review-dependency-");
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

test("main with STANDARDS_DIR set needs no TRUSTED_ACTORS or DEPENDABOT_POLICY and reads the standards checkout's list", async () => {
  const dir = tempDir("review-dependency-");
  const standards = join(dir, "standards");
  mkdirSync(join(standards, "components/trusted-actors"), { recursive: true });
  writeFileSync(
    join(standards, "components/trusted-actors/trusted-actors.json"),
    JSON.stringify({ actors: [{ id: DEPENDABOT, login: "dependabot[bot]", kind: "bot" }] }),
  );
  const env = {
    GITHUB_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    GITHUB_OUTPUT: join(dir, "out"),
    PR_NUMBER: "7",
    HEAD_SHA: HEAD,
    APP_SENDER_ID: String(APP),
    STANDARDS_DIR: standards,
    DEPENDENCY_FILE: join(dir, "dependency.json"),
    CONTEXT_RUN_FILE: join(dir, "context.json"),
    DEPENDABOT_CONFIG: join(dir, "dependabot.yml"),
  };
  await main(["select"], env, { api: fakeApi({}), log: () => {} });
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), "proceed=true\nskip-reason=\nescalation-reason=\n");
});

test("main writes no context or run file when the select skips", async () => {
  const dir = tempDir("review-dependency-");
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
  const lines = [];
  await main(["select"], { ...env, GITHUB_OUTPUT: join(dir, "held") }, { api: fakeApi({ gateRuns: [supersededRun], annotations: { 9: [EXIT, gateHold(7)] } }), log: (line) => lines.push(line) });
  assert.equal(readFileSync(join(dir, "held"), "utf8"), "proceed=false\nskip-reason=gate-hold\nescalation-reason=\n");
  assert.equal(existsSync(env.CONTEXT_RUN_FILE), false);
  assert.ok(lines.some((line) => line.includes("trust-gate hold") && line.includes("content was not judged")), "the step summary says why no review ran");
  assert.ok(!lines.some((line) => /security/i.test(line)), "a gate hold names no security risk");
});

async function mainWith({ title, policy = POLICY, provenance = async () => [] }) {
  const dir = tempDir("review-dependency-");
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

const CLI = "@anthropic-ai/claude-code";
const PIN_FILES = [{ filename: "package-lock.json", status: "modified", additions: 1, deletions: 1, patch: "" }];
const pinTexts = (pin) => ({
  "package.json": `${JSON.stringify({ devDependencies: { [CLI]: "2.1.317" }, allowScripts: { [`${CLI}@${pin}`]: true } }, null, 2)}\n`,
  "package-lock.json": JSON.stringify({ packages: { [`node_modules/${CLI}`]: { version: "2.1.317" } } }),
});
const pinArgs = { pr: 7, headSha: HEAD, appId: APP, dependabotId: DEPENDABOT, config: [] };

test("select writes the pin patch with no model turn when the head's pin lags its lockfile", async () => {
  const result = await select({ api: fakeApi({ files: PIN_FILES, texts: pinTexts("2.1.316") }), ...pinArgs });
  assert.equal(result.decision, "pin");
  assert.deepEqual([result.pin.from, result.pin.to], ["2.1.316", "2.1.317"]);
  assert.match(result.pin.patch, new RegExp(`^-.*"${CLI}@2\\.1\\.316": true$\\n^\\+.*"${CLI}@2\\.1\\.317": true$`, "m"));
  assert.equal(result.file, undefined, "no context file: the model does not run");
});

test("select hands the model a pull request whose pin already matches, and one that changes neither root npm file", async () => {
  assert.equal((await select({ api: fakeApi({ files: PIN_FILES, texts: pinTexts("2.1.317") }), ...pinArgs })).decision, "proceed");
  const other = [{ filename: "plugins/x/package.json", status: "modified", additions: 1, deletions: 1, patch: "" }];
  const api = { ...fakeApi({ files: other }), getText: async () => assert.fail("no root npm file changed, so nothing is read") };
  assert.equal((await select({ api, ...pinArgs })).decision, "proceed");
});

test("main writes the pin patch, its SHA-256 and a step summary line, and posts no-model-turn", async () => {
  const dir = tempDir("review-dependency-");
  const actors = join(dir, "actors.json");
  writeFileSync(actors, JSON.stringify({ actors: [{ id: DEPENDABOT, login: "dependabot[bot]", kind: "bot" }] }));
  const env = {
    GITHUB_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    GITHUB_OUTPUT: join(dir, "out"),
    GITHUB_STEP_SUMMARY: join(dir, "summary"),
    PR_NUMBER: "7",
    HEAD_SHA: HEAD,
    APP_SENDER_ID: String(APP),
    TRUSTED_ACTORS: actors,
    DEPENDENCY_FILE: join(dir, "dependency.json"),
    CONTEXT_RUN_FILE: join(dir, "context.json"),
    PIN_PATCH_FILE: join(dir, "patch.diff"),
    DEPENDABOT_CONFIG: join(dir, "dependabot.yml"),
    DEPENDABOT_POLICY: join(dir, "policy.json"),
  };
  await main(["select"], env, { api: fakeApi({ files: PIN_FILES, texts: pinTexts("2.1.316") }), log: () => {} });
  const patch = readFileSync(env.PIN_PATCH_FILE, "utf8");
  const sum = createHash("sha256").update(patch).digest("hex");
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), `pin-state=written\npin-sha256=${sum}\nproceed=false\nskip-reason=no-model-turn\nescalation-reason=\n`);
  assert.match(readFileSync(env.GITHUB_STEP_SUMMARY, "utf8"), /^@anthropic-ai\/claude-code install-script pin: 2\.1\.316 to 2\.1\.317/);
  assert.equal(existsSync(env.DEPENDENCY_FILE), false);
});

const GROUPS = [{ ecosystem: "pip", directories: ["plugins/explainer-video", "lib/media-render"], patterns: ["playwright"] }];
const GROUP_FILES = [
  { filename: "lib/media-render/requirements.in", status: "modified", additions: 1, deletions: 1, patch: "" },
  { filename: "lib/media-render/requirements.txt", status: "modified", additions: 3, deletions: 3, patch: "" },
];
const LOCK_HEADER = "# This file was autogenerated by uv via the following command:\n#    uv pip compile requirements.in --universal --generate-hashes --python-version 3.12 -o requirements.txt\n";
const groupTexts = (lagging) => ({
  "lib/media-render/requirements.in": "playwright==1.65.2\n",
  "plugins/explainer-video/requirements.in": `manim[typst]==0.21.0\nplaywright==${lagging}\n`,
  "plugins/explainer-video/requirements.txt": `${LOCK_HEADER}playwright==${lagging} \\\n    --hash=sha256:${"a".repeat(64)}\n    # via -r requirements.in\n`,
});
const relockArgs = { ...pinArgs, groups: GROUPS, config: [["pip", "/plugins/explainer-video"], ["pip", "/lib/media-render"]] };

test("select hands the relock job the directory a dependency-name group left behind, with no model turn", async () => {
  const texts = groupTexts("1.65.1");
  const result = await select({ api: fakeApi({ files: GROUP_FILES, texts }), ...relockArgs });
  assert.equal(result.decision, "relock");
  assert.deepEqual(result.relock, {
    directory: "plugins/explainer-video",
    name: "playwright",
    from: "1.65.1",
    to: "1.65.2",
    in_before: texts["plugins/explainer-video/requirements.in"],
    in_after: "manim[typst]==0.21.0\nplaywright==1.65.2\n",
    txt_before: texts["plugins/explainer-video/requirements.txt"],
  });
  assert.equal(result.file, undefined, "no context file: the model does not run");
});

test("select relocks nothing when the group's directories already agree", async () => {
  const result = await select({ api: fakeApi({ files: GROUP_FILES, texts: groupTexts("1.65.2") }), ...relockArgs });
  assert.equal(result.decision, "proceed");
  assert.equal(result.relockError, "");
});

test("select hands the model a pull request whose lagging lock another command wrote, with the reason", async () => {
  const texts = { ...groupTexts("1.65.1") };
  texts["plugins/explainer-video/requirements.txt"] = texts["plugins/explainer-video/requirements.txt"].replace("-o requirements.txt", "-o requirements.txt --index-url https://evil.example/simple");
  const result = await select({ api: fakeApi({ files: GROUP_FILES, texts }), ...relockArgs });
  assert.equal(result.decision, "proceed");
  assert.match(result.relockError, /was not compiled by/);
});

test("main writes the relock request the relock job reads, its SHA-256, and posts no-model-turn", async () => {
  const dir = tempDir("review-dependency-");
  const actors = join(dir, "actors.json");
  writeFileSync(actors, JSON.stringify({ actors: [{ id: DEPENDABOT, login: "dependabot[bot]", kind: "bot" }] }));
  const config = join(dir, "dependabot.yml");
  writeFileSync(
    config,
    "version: 2\nupdates:\n  - package-ecosystem: pip\n    directories:\n      - /plugins/explainer-video\n      - /lib/media-render\n    groups:\n      playwright:\n        group-by: dependency-name\n        patterns:\n          - \"playwright\"\n",
  );
  const relockDir = join(dir, "relock");
  mkdirSync(relockDir);
  const env = {
    GITHUB_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    GITHUB_OUTPUT: join(dir, "out"),
    GITHUB_STEP_SUMMARY: join(dir, "summary"),
    PR_NUMBER: "7",
    HEAD_SHA: HEAD,
    APP_SENDER_ID: String(APP),
    TRUSTED_ACTORS: actors,
    DEPENDENCY_FILE: join(dir, "dependency.json"),
    CONTEXT_RUN_FILE: join(dir, "context.json"),
    RELOCK_DIR: relockDir,
    DEPENDABOT_CONFIG: config,
    DEPENDABOT_POLICY: join(dir, "policy.json"),
  };
  const texts = groupTexts("1.65.1");
  await main(["select"], env, { api: fakeApi({ files: GROUP_FILES, texts }), log: () => {} });
  const request = readFileSync(join(relockDir, "request.json"), "utf8");
  assert.equal(JSON.parse(request).to, "1.65.2");
  assert.equal(readFileSync(join(relockDir, "requirements.in"), "utf8"), "manim[typst]==0.21.0\nplaywright==1.65.2\n");
  assert.equal(readFileSync(join(relockDir, "requirements.txt"), "utf8"), texts["plugins/explainer-video/requirements.txt"]);
  const sum = createHash("sha256").update(request).digest("hex");
  assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), `relock-state=written\nrelock-sha256=${sum}\nproceed=false\nskip-reason=no-model-turn\nescalation-reason=\n`);
  assert.match(readFileSync(env.GITHUB_STEP_SUMMARY, "utf8"), /^plugins\/explainer-video: playwright 1\.65\.1 to 1\.65\.2, relocked by review-dependency-relock/);
});

test("main warns and hands the model a pin it cannot move", async () => {
  const dir = tempDir("review-dependency-");
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
  const texts = { ...pinTexts("2.1.316"), "package-lock.json": JSON.stringify({ packages: { [`node_modules/${CLI}`]: { version: "2.1.318" } } }) };
  const lines = [];
  await main(["select"], env, { api: fakeApi({ files: PIN_FILES, texts }), log: (line) => lines.push(line) });
  assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), /^proceed=true\n/);
  assert.ok(lines.some((line) => line.startsWith("::warning::the @anthropic-ai/claude-code install-script pin was not moved (the moved pin is refused: allow-scripts-version)")));
});

test("select only writes a hashed CDN request for a Dependabot manifest bump with matching base targets", async () => {
  const manifestPath = "lib/cdn-pins/package.json";
  const pinsPath = "lib/cdn-pins/pins.json";
  const scriptPath = "lib/cdn-pins/sync.mjs";
  const target = "docs/view.md";
  const record = JSON.stringify({ packages: { x: { version: "1.0.0" } }, targets: [{ path: target, packages: ["x"], integrity: true }] });
  const baseScript = "export function sync() {}\n";
  const manifest = '{"dependencies":{"x":"2.0.0"}}\n';
  const lockPath = "lib/cdn-pins/package-lock.json";
  const lockText = '{"lockfileVersion":3,"packages":{"node_modules/x":{"version":"2.0.0"}}}\n';
  const texts = { [manifestPath]: manifest, [lockPath]: lockText, [pinsPath]: record, [target]: "view\n", [scriptPath]: "throw new Error('head code')\n" };
  const changed = (filename) => ({ filename, status: "modified" });
  const lock = changed(lockPath);
  for (const { why, files = [changed(manifestPath)], pull, headTexts = texts, omit, written = false } of [
    { why: "manifest only", written: true },
    { why: "lock only, versions already synced", files: [lock], headTexts: { ...texts, [manifestPath]: '{"dependencies":{"x":"1.0.0"}}\n' } },
    { why: "lock with a manifest bump", files: [lock], written: true },
    { why: "both", files: [changed(manifestPath), lock], written: true },
    { why: "a bump of a package pins.json does not list", headTexts: { ...texts, [manifestPath]: '{"dependencies":{"x":"1.0.0","z":"3.0.0"}}\n' } },
    { why: "a manifest that does not parse", headTexts: { ...texts, [manifestPath]: "{" } },
    { why: "non-Dependabot", pull: { user: { id: 1, login: "someone" } } },
    { why: "extra path", files: [changed(manifestPath), changed(target)] },
    { why: "incomplete changed-file listing", pull: { changed_files: 2 } },
    { why: "renamed into the manifest", files: [{ filename: manifestPath, previous_filename: target, status: "renamed" }] },
    { why: "missing base pins", omit: pinsPath },
    { why: "missing base script", omit: scriptPath },
    { why: "different target metadata", headTexts: { ...texts, [pinsPath]: record.replace("true", "false") } },
    { why: "missing head target", headTexts: { ...texts, [target]: null } },
    { why: "missing head lock", headTexts: { ...texts, [lockPath]: null } },
  ]) {
    const dir = tempDir("cdn-select-");
    mkdirSync(join(dir, "lib/cdn-pins"), { recursive: true });
    const requestDir = join(dir, "cdn-request");
    mkdirSync(requestDir);
    if (omit !== pinsPath) writeFileSync(join(dir, pinsPath), record);
    if (omit !== scriptPath) writeFileSync(join(dir, scriptPath), baseScript);
    const env = {
      BASE_DIR: dir,
      CDN_SYNC_DIR: requestDir,
      GITHUB_TOKEN: "t",
      GITHUB_REPOSITORY: "o/r",
      GITHUB_OUTPUT: join(dir, "output"),
      PR_NUMBER: "7",
      HEAD_SHA: HEAD,
      APP_SENDER_ID: String(APP),
      TRUSTED_ACTORS: join(dir, "actors.json"),
      DEPENDENCY_FILE: join(dir, "dependency.json"),
      CONTEXT_RUN_FILE: join(dir, "context.json"),
      DEPENDABOT_CONFIG: join(dir, "dependabot.yml"),
      DEPENDABOT_POLICY: join(dir, "policy.json"),
    };
    writeFileSync(env.TRUSTED_ACTORS, JSON.stringify({ actors: [{ id: DEPENDABOT, login: "dependabot[bot]", kind: "bot" }] }));
    const api = fakeApi({ files, pull, texts: headTexts });
    await main(["select"], env, { api, log: () => {} });
    const path = join(requestDir, "request.json");
    assert.equal(existsSync(path), written, why);
    if (written) {
      const request = readFileSync(path, "utf8");
      assert.deepEqual(JSON.parse(request), { script: baseScript, manifest, lock: lockText, files: { [pinsPath]: record, [target]: "view\n" } });
      const sum = createHash("sha256").update(request).digest("hex");
      assert.equal(readFileSync(env.GITHUB_OUTPUT, "utf8"), `cdn-sync-state=written\ncdn-sync-sha256=${sum}\nproceed=false\nskip-reason=no-model-turn\nescalation-reason=\n`);
    } else if (why.startsWith("lock only") || why.startsWith("a bump of") || why.startsWith("a manifest")) {
      assert.match(readFileSync(env.GITHUB_OUTPUT, "utf8"), /^proceed=true$/m, `${why}: the model reviews it`);
    }
  }
});
