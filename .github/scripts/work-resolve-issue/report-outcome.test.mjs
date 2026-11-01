// Expected values come from the lane's plan: a missing or invalid outcome file
// means `stopped`; `done` opens a ready PR whose body starts `Closes #<issue>`,
// with a Conventional Commits title (the run's, else one from the issue title), no
// label (the class lives on the issue only), and the hold line for
// untrusted-provenance work or a trust or lane-power diff; `pushback` and
// `stopped` comment and take the route stop-routes.json gives their stop:
// needs-human only for an intent, design, security or cost reason.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  capRetries,
  closingPulls,
  countRestarts,
  countTurnCapRestarts,
  decide,
  doneEvidence,
  findPrior,
  findPriorMain,
  main,
  mustHold,
  parseOutcomeMarker,
  pruneBranches,
  heldPaths,
  readHoldPaths,
  readFunding,
  readChecks,
  readIssueStop,
  readOutcome,
  readScanRefusal,
  SCAN_REFUSALS,
  readTurnCap,
  RESUMABLE,
  reusePlan,
  HOLD_LINE,
  HUMAN_MERGE_HOLD,
  trustedLabeler,
  unmarkedAnswer,
  waitedPull,
} from "./report-outcome.mjs";
import { closeStop } from "../lib/done-evidence.mjs";
import { LIMIT_DEFAULTS } from "./limits.mjs";
import { STOP_ROUTES } from "./stop-routes.mjs";
import { isPersonReason, parseReason } from "../lib/stop-reason.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const BRANCH = "work-resolve-issue/issue-77-123-1";
// The first line of every hand-back comment: the attended queue's escalation
// marker in the grammar of plugins/work-items/reference/escalation-marker.md.
const ESC = "<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\n";
// The issue history a retry reads to count the retries already made.
const HISTORY = [
  ["GET", /\/issues\/77\/comments$/, 200, []],
  ["GET", /\/issues\/77\/events$/, 200, []],
];

// The run-checks job's `checks` output for `branch` at `tip`, and the ref
// read main compares that tip with. A test puts it in the outcome directory as
// `runner-checks`, and env() hands it to main as RUNNER_CHECKS.
const CHECKED_TIP = "c".repeat(40);
const FRAGMENTS = "scripts/check-changelog-fragments.sh --check";
const checksFile = ({ branch = BRANCH, tip = CHECKED_TIP, results = [{ check: FRAGMENTS, exit: 0 }] } = {}) =>
  JSON.stringify({ version: 1, branch, tip, results });
// The runner's record when the activity lists no checks: decide() needs one
// to open a PR at all.
const NO_CHECKS = { tip: CHECKED_TIP, results: [] };
const branchTip = (branch = BRANCH, sha = CHECKED_TIP) => ["GET", new RegExp(`/git/ref/heads/${branch}$`), 200, { object: { sha } }];

function withDir(files, run) {
  const dir = tempDir("outcome-");
  try {
    for (const [name, text] of Object.entries(files)) {
      writeFileSync(join(dir, name), text);
    }
    return run(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const done = { exit: "done", reason: "", title: "docs(work-items): fix a typo", summary: "Fixed it." };

// The merge lane's denied paths, as the resolved config carries them.
const HOLD_GLOBS = [".github/**", "**/AGENTS.md", ".claude-plugin/**", "plugins/*/skills/**"];

function decideDone(overrides = {}) {
  return decide({
    outcome: done,
    issueNumber: 77,
    issueLabels: ["agent-ready", "work-class: read-only"],
    branch: BRANCH,
    changedFiles: ["plugins/work-items/README.md"],
    holdPaths: HOLD_GLOBS,
    checks: NO_CHECKS,
    ...overrides,
  });
}

test("a missing outcome file reads as stopped", () => {
  withDir({}, (dir) => {
    assert.equal(readOutcome(join(dir, "work-outcome.json")).exit, "stopped");
  });
});

for (const [name, text] of [
  ["not JSON", "{"],
  ["an unknown exit", JSON.stringify({ exit: "finished" })],
  ["an array", "[]"],
]) {
  test(`an outcome file holding ${name} reads as stopped`, () => {
    withDir({ "work-outcome.json": text }, (dir) => {
      assert.equal(readOutcome(join(dir, "work-outcome.json")).exit, "stopped");
    });
  });
}

test("a valid done outcome reads as done", () => {
  withDir({ "work-outcome.json": JSON.stringify(done) }, (dir) => {
    assert.equal(readOutcome(join(dir, "work-outcome.json")).exit, "done");
  });
});

test("done opens a PR whose body starts with Closes #N", () => {
  const plan = decideDone();
  assert.equal(plan.action, "open-pr");
  assert.ok(plan.body.startsWith("Closes #77\n"), plan.body);
});

// The PR links without closing only when the run names the work it leaves
// for later in `remaining`; the run's own `link` field decides nothing. The
// merge gate reads a plain `Refs: #N` first line as the PR's issue, so Refs
// alone adds no hold line.
const bodyOf = (outcome) =>
  withDir({ "work-outcome.json": JSON.stringify(outcome) }, (dir) => decideDone({ outcome: readOutcome(join(dir, "work-outcome.json")) }).body);

// A run that sets `link: refs` for the issue's own parent `Refs:` line and
// names no remaining work opens a PR that closes the issue.
test('"link": "refs" with no remaining work closes the issue', () => {
  for (const remaining of [undefined, []]) {
    const body = bodyOf({ ...done, link: "refs", remaining });
    assert.ok(body.startsWith("Closes #77\n"), body);
    assert.ok(!body.includes("## Remaining work"), body);
  }
});

test("remaining work opens a PR that starts Refs: #N, lists it, and carries no hold line", () => {
  const body = bodyOf({ ...done, remaining: ["Part B: the Windows host check", "The docs page"] });
  assert.ok(body.startsWith("Refs: #77\n\n## Summary"), body);
  assert.ok(body.includes("\n## Remaining work\n\n- Part B: the Windows host check\n- The docs page\n"), body);
  assert.ok(!body.includes("Closes #77"), body);
  assert.ok(!body.includes("Hold: a human merges this"), body);
});

test('remaining work opens a Refs PR whatever "link" says', () => {
  assert.ok(bodyOf({ ...done, link: "closes", remaining: ["Part B"] }).startsWith("Refs: #77\n"));
});

// A malformed `remaining` counts as empty, whatever `link` says: a wrong
// Closes fails pr-verify against the whole issue, a fix round at worst.
for (const [name, remaining] of [
  ["a string", "Part B"],
  ["an object", { what: "Part B" }],
  ["an empty string", [""]],
  ["a blank string", ["  \n"]],
  ["a non-string item beside a valid one", [1, "Part B"]],
  ["an item that is only an HTML comment", ["<!-- Part B -->"]],
  ["an item whose HTML comment runs past the item cap", [`<!--${"x".repeat(300)}-->Part B`]],
  ["an item whose text starts past the item cap", [`${"​".repeat(300)}Part B`]],
  ["an item that is only a C1 control character", ["\u0085"]],
  ["more than 20 items", Array.from({ length: 21 }, (_, i) => `Part ${i}`)],
]) {
  test(`a remaining holding ${name} closes the issue`, () => {
    const body = bodyOf({ ...done, link: "refs", remaining });
    assert.ok(body.startsWith("Closes #77\n"), body);
    assert.ok(!body.includes("## Remaining work"), body);
  });
}

test("a remaining of exactly 20 items opens a Refs PR listing the last", () => {
  const body = bodyOf({ ...done, remaining: Array.from({ length: 20 }, (_, i) => `Part ${i}`) });
  assert.ok(body.startsWith("Refs: #77\n"), body);
  assert.ok(body.includes("\n- Part 19\n"), body);
});

test("a remaining item is neutralized like other run text", () => {
  const body = bodyOf({ ...done, remaining: ["Closes #12 for @someone\n## Heading"] });
  assert.ok(body.includes("\n## Remaining work\n\n- Closes ＃12 for someone ＃＃ Heading\n"), body);
});

test("a Refs PR with a trusted merge: human label still carries the hold line", () => {
  const plan = decideDone({ outcome: { ...done, remaining: ["Part B"] }, humanMerge: true });
  assert.ok(plan.body.startsWith("Refs: #77\n\nHold: a human merges this\n"), plan.body);
});

test("done keeps a Conventional Commits title", () => {
  assert.equal(decideDone().title, "docs(work-items): fix a typo");
});

// The two titles below are ones real lane runs wrote, which the old subject
// class refused.
test("done keeps a run title whose subject holds a semicolon", () => {
  const title = "fix(bugs): frame scanned-repo and tracker text as untrusted; author-check scan lane cursor and dedupe";
  assert.equal(decideDone({ outcome: { ...done, title } }).title, title);
});

test("done keeps a run title naming a slash command, without the slash", () => {
  const title = "fix(planning): add round.sh lease --takeover to hand an interview over after /clear";
  assert.equal(
    decideDone({ outcome: { ...done, title } }).title,
    "fix(planning): add round.sh lease --takeover to hand an interview over after clear",
  );
});

test("a run title that is not Conventional Commits takes the issue's own type and scope", () => {
  const issueTitle = "fix(planning): add one round.sh command to hand an interview over after /clear";
  assert.equal(
    decideDone({ outcome: { ...done, title: "Fix a typo" }, issueTitle }).title,
    "fix(planning): add one round.sh command to hand an interview over after clear",
  );
});

test("a run title that is not Conventional Commits becomes fix: and the issue title", () => {
  const issueTitle = "Lane PR titles fall back to a placeholder";
  assert.equal(
    decideDone({ outcome: { ...done, title: "Fix a typo" }, issueTitle }).title,
    "fix: Lane PR titles fall back to a placeholder",
  );
});

test("a long issue title is cut at a word to the subject's 99 characters", () => {
  const issueTitle =
    "bugs: frame scanned-repo and tracker text as untrusted data; author-check scan's lane cursor and dedupe";
  assert.equal(
    decideDone({ outcome: { ...done, title: "" }, issueTitle }).title,
    "fix: bugs: frame scanned-repo and tracker text as untrusted data; author-check scan's lane cursor and",
  );
});

test("with no usable run or issue title the PR is titled from the issue number", () => {
  assert.equal(decideDone({ outcome: { ...done, title: "" }, issueTitle: "###" }).title, "fix: resolve issue 77");
});

test("done puts no label on the PR, so the class stays on the issue", () => {
  assert.equal(decideDone({ issueLabels: ["agent-ready", "work-class: mechanical"] }).labels, undefined);
});

test("read-only work on ordinary files carries no hold line", () => {
  assert.ok(!decideDone().body.includes("Hold: a human merges this"));
});

test("untrusted-provenance work carries the hold line", () => {
  const plan = decideDone({ issueLabels: ["work-class: untrusted-provenance"] });
  assert.ok(plan.body.split("\n").includes("Hold: a human merges this"), plan.body);
});

// Structural risk shows in the diff, which the review lanes read.
test("structural work on ordinary files carries no hold line", () => {
  const plan = decideDone({ issueLabels: ["work-class: structural"] });
  assert.ok(!plan.body.includes("Hold: a human merges this"), plan.body);
});

test("an issue with no work class, on ordinary files, carries no hold line", () => {
  const plan = decideDone({ issueLabels: ["agent-ready"] });
  assert.ok(!plan.body.includes("Hold: a human merges this"), plan.body);
});

test("scoped work on ordinary files carries no hold line", () => {
  const plan = decideDone({ issueLabels: ["work-class: scoped"] });
  assert.ok(!plan.body.includes("Hold: a human merges this"), plan.body);
});

for (const path of [".github/workflows/ci.yml", "AGENTS.md", "plugins/x/AGENTS.md", ".claude-plugin/marketplace.json", "plugins/x/skills/y/SKILL.md"]) {
  test(`a diff touching ${path}, under a merge-lane denied path, carries the hold line`, () => {
    const plan = decideDone({ changedFiles: ["README.md", path] });
    assert.ok(plan.body.split("\n").includes("Hold: a human merges this"), plan.body);
  });
}

test("with no readable denied-path list every done PR carries the hold line", () => {
  assert.ok(decideDone({ holdPaths: null }).body.split("\n").includes("Hold: a human merges this"));
});

test("the denied paths come from the resolved config the runner wrote", () => {
  withDir(
    { "resolved-config.json": JSON.stringify({ merge: { "diff-check": { "denied-paths": ["a/**"] } } }) },
    (dir) => assert.deepEqual(readHoldPaths(join(dir, "resolved-config.json")), ["a/**"]),
  );
  withDir({}, (dir) => assert.equal(readHoldPaths(join(dir, "resolved-config.json")), null));
});

// docs/conventions/pr-pipeline.yaml sets `denied-paths: []` on purpose: no
// path is denied, so only the other hold reasons hold a PR (#7793, #7795).
test("an empty denied-path list denies no path, so a PR with no other hold reason carries no hold line", () => {
  withDir({ "resolved-config.json": JSON.stringify({ merge: { "diff-check": { "denied-paths": [] } } }) }, (dir) => {
    const holdPaths = readHoldPaths(join(dir, "resolved-config.json"));
    assert.deepEqual(holdPaths, []);
    assert.ok(!decideDone({ holdPaths, changedFiles: [".github/workflows/ci.yml"] }).body.includes("Hold: a human merges this"));
  });
});

for (const [name, text] of [
  ["not JSON", "{"],
  ["no denied-paths key", JSON.stringify({ merge: { "diff-check": {} } })],
  ["a denied-paths string", JSON.stringify({ merge: { "diff-check": { "denied-paths": "a/**" } } })],
  ["a non-string denied path", JSON.stringify({ merge: { "diff-check": { "denied-paths": ["a/**", 7] } } })],
]) {
  test(`a resolved config holding ${name} reads as no denied-path list and holds the PR`, () => {
    withDir({ "resolved-config.json": text }, (dir) => {
      const holdPaths = readHoldPaths(join(dir, "resolved-config.json"));
      assert.equal(holdPaths, null);
      assert.ok(decideDone({ holdPaths }).body.split("\n").includes("Hold: a human merges this"));
    });
  });
}

// merge.diff-check.path-holds (owner decisions Q15 and Q16): off, a denied
// path holds nothing; on, it holds as before; an unreadable list still holds.
test("with path holds off a denied path holds nothing, and on it holds the PR", () => {
  const config = (pathHolds) => JSON.stringify({ merge: { "diff-check": { "denied-paths": ["a/**"], ...(pathHolds === undefined ? {} : { "path-holds": pathHolds }) } } });
  for (const off of [undefined, false]) {
    withDir({ "resolved-config.json": config(off) }, (dir) => {
      const holdPaths = heldPaths(join(dir, "resolved-config.json"));
      assert.deepEqual(holdPaths, []);
      assert.ok(!decideDone({ holdPaths, changedFiles: ["a/x.md"] }).body.includes("Hold: a human merges this"));
    });
  }
  withDir({ "resolved-config.json": config(true) }, (dir) => {
    const holdPaths = heldPaths(join(dir, "resolved-config.json"));
    assert.deepEqual(holdPaths, ["a/**"]);
    assert.ok(decideDone({ holdPaths, changedFiles: ["a/x.md"] }).body.split("\n").includes("Hold: a human merges this"));
  });
  withDir({ "resolved-config.json": "{" }, (dir) => assert.equal(heldPaths(join(dir, "resolved-config.json")), null));
});

test("an unreadable resolved config reads as no denied-path list and holds the PR", () => {
  withDir({}, (dir) => {
    const holdPaths = readHoldPaths(dir);
    assert.equal(holdPaths, null);
    assert.ok(decideDone({ holdPaths }).body.split("\n").includes("Hold: a human merges this"));
  });
});

// An owner decision that a person merges the issue's PR (#7287, #6008): the
// `merge: human` label holds the PR when a listed human or the lanes App put it
// on the issue.
test("a trusted merge: human label carries the hold line", () => {
  assert.ok(decideDone({ humanMerge: true }).body.split("\n").includes("Hold: a human merges this"));
});

test("without a trusted merge: human label scoped work carries no hold line", () => {
  assert.ok(!decideDone({ issueLabels: ["work-class: scoped"], humanMerge: false }).body.includes("Hold: a human merges this"));
});

const labeled = (name, login, id) => ({ event: "labeled", label: { name }, actor: { login, id } });

test("a label's labeler is trusted when its newest labeled event is a listed human's or the lanes App's", () => {
  const trust = { bot: "melodic-automation-lanes[bot]", humans: new Set([153232337]) };
  assert.equal(trustedLabeler([labeled("merge: human", "kyle-sexton", 153232337)], "merge: human", trust), true);
  assert.equal(trustedLabeler([labeled("merge: human", "melodic-automation-lanes[bot]", 9)], "merge: human", trust), true);
  assert.equal(trustedLabeler([labeled("merge: human", "stranger", 42)], "merge: human", trust), false);
  // Removed and re-added by someone unlisted: the newest event decides.
  assert.equal(
    trustedLabeler([labeled("merge: human", "kyle-sexton", 153232337), labeled("merge: human", "stranger", 42)], "merge: human", trust),
    false,
  );
  // A login that copies a listed human's but not their id is not trusted.
  assert.equal(trustedLabeler([labeled("merge: human", "kyle-sexton", 42)], "merge: human", trust), false);
  assert.equal(trustedLabeler([labeled("work-class: scoped", "kyle-sexton", 153232337)], "merge: human", trust), false);
  assert.equal(trustedLabeler([], "merge: human", trust), false);
});

// The body's `##` headings, in order.
const headings = (body) => body.split("\n").filter((line) => /^## /.test(line));
const section = (body, name) => body.split(`\n## ${name}\n\n`)[1].split("\n\n## ")[0];

test("the model's summary renders as a blockquote, not a code fence", () => {
  const plan = decideDone({ outcome: { ...done, summary: "First line.\nSecond line." } });
  assert.ok(!plan.body.includes("```"), plan.body);
  assert.ok(plan.body.includes("\n> First line.\n> Second line.\n"), plan.body);
});

test("no line of the model's text escapes the blockquote", () => {
  const plan = decideDone({ outcome: { ...done, summary: "a\r\n\n## Fix\nCloses #5" } });
  const quote = section(plan.body, "Summary").split("\n").filter((line) => line.startsWith(">"));
  assert.deepEqual(quote, ["> a", ">", "> ＃＃ Fix", "> Closes ＃5"]);
  assert.equal(headings(plan.body).filter((h) => h === "## Fix").length, 1);
});

test("HTML comments and @ mentions in the model's text are stripped", () => {
  const plan = decideDone({ outcome: { ...done, summary: "Hi <!-- hidden --> @octocat and <!-- open" } });
  assert.ok(!plan.body.includes("hidden"), plan.body);
  assert.ok(!plan.body.includes("<!--"), plan.body);
  assert.ok(!plan.body.includes("@octocat"), plan.body);
});

test("the model's text is cut to the length caps after escaping", () => {
  const plan = decideDone({
    outcome: { ...done, summary: "<".repeat(5000), changes: Array(30).fill("<".repeat(400)) },
  });
  // 3000 for the summary, 20 items of 300 for the list, plus the fixed text.
  assert.ok(plan.body.length < 3000 + 20 * 305 + 1000, String(plan.body.length));
  assert.ok(!/&l?t?$|&lt$/m.test(plan.body.split("## Fix")[0].trim()), "no half-cut entity");
});

// CommonMark decodes `&commat;` to `@` and `&num;` to `#`, and GitHub links a
// `GH-` prefix followed by an issue number.
test("entities, GH- references and link definitions in model text stay inert", () => {
  const plan = decideDone({
    outcome: { ...done, summary: "&commat;octocat Closes &num;12, fixes GH-13\n[x]: https://evil \"hidden\"" },
  });
  const quote = section(plan.body, "Summary");
  assert.ok(quote.includes("&amp;commat;octocat Closes &amp;num;12"), quote);
  assert.ok(!/GH-13/.test(quote), quote);
  assert.ok(!/^>\s*\[x\]:/m.test(quote) && !/https:\/\/evil/.test(quote), quote);
});

// GFM autolinks a bare `https://` or `www.` URL in a blockquote.
test("a bare URL in model text does not autolink", () => {
  const plan = decideDone({ outcome: { ...done, summary: "See https://evil.example and www.evil.example" } });
  assert.ok(!/https:\/\/evil|www\.evil/.test(plan.body), plan.body);
});

test("a not_done item marked required counts even when it names nothing", () => {
  withDir({ "work-outcome.json": JSON.stringify({ ...done, not_done: [{ what: 5, required: true }] }) }, (dir) => {
    const outcome = readOutcome(join(dir, "work-outcome.json"));
    const plan = decideDone({ outcome });
    assert.equal(plan.action, "retry");
    assert.equal(plan.stop, "required-undone");
  });
});

test("changes, verification and not_done fill Fix, Verification and Not verified", () => {
  const plan = decideDone({
    outcome: {
      ...done,
      changes: ["plugins/a/README.md: fixed the install command"],
      verification: ["scripts/check-changelog-fragments.sh --check: passed"],
      notDone: [{ what: "Did not render the page", required: false }],
    },
    runUrl: "https://example/run/1",
  });
  assert.equal(section(plan.body, "Fix"), "- plugins/a/README.md: fixed the install command");
  assert.equal(
    section(plan.body, "Verification"),
    "The runner ran no checks: the activity lists none.\n\nThe run reports:\n\n- scripts/check-changelog-fragments.sh --check: passed\n- The lane run: https://example/run/1\n\nLeft out: the items under Not verified.",
  );
  assert.equal(section(plan.body, "Not verified"), "- Did not render the page");
});

test("with no structured fields every section is still filled, with no branch line", () => {
  const plan = decideDone({ runUrl: "https://example/run/1" });
  assert.ok(!plan.body.includes("## Not verified"));
  assert.ok(!plan.body.includes(BRANCH), plan.body);
  assert.ok(plan.body.includes("\n> Fixed it.\n"), plan.body);
  assert.equal(section(plan.body, "Fix"), "The run listed no changes; the diff shows them.");
  assert.equal(
    section(plan.body, "Verification"),
    "The runner ran no checks: the activity lists none.\n\nThe run listed no checks.\n\n- The lane run: https://example/run/1\n\nLeft out: nothing the run reported.",
  );
});

// #7497: the runner's check results, not the outcome file, decide whether a
// done run is finished.
test("the runner's passing checks are listed under Verification with the tip they ran against", () => {
  const plan = decideDone({ checks: { tip: CHECKED_TIP, results: [{ check: FRAGMENTS, exit: 0 }] } });
  assert.equal(plan.action, "open-pr");
  assert.ok(
    section(plan.body, "Verification").startsWith(
      `The runner ran each check from the base copy against ${CHECKED_TIP}:\n\n- scripts/check-changelog-fragments.sh --check: passed\n`,
    ),
    plan.body,
  );
});

test("a done outcome with an empty not_done and a failing runner check is stopped", () => {
  const plan = decideDone({
    outcome: { ...done, notDone: [], verification: ["every check passed"] },
    checks: { tip: CHECKED_TIP, results: [{ check: FRAGMENTS, exit: 1 }] },
  });
  // An unfinished check goes back to agent-ready with the branch named.
  assert.equal(plan.action, "retry");
  assert.equal(plan.stop, "check-failed");
  assert.deepEqual(plan.addLabels, []);
  assert.deepEqual(plan.removeLabels, []);
  assert.ok(plan.comment.includes("- scripts/check-changelog-fragments.sh --check failed (exit 1)"), plan.comment);
  assert.ok(plan.comment.includes(`Partial work is on the branch \`${BRANCH}\``), plan.comment);
  assert.ok(!plan.comment.startsWith(ESC), plan.comment);
});

test("a done outcome whose runner check results are missing is stopped", () => {
  const plan = decideDone({ checks: null });
  assert.equal(plan.action, "retry");
  assert.ok(plan.comment.includes("check results are missing"), plan.comment);
});

test("the runner's check results count only for this branch, with a tip and whole-number exits", () => {
  const read = (text) => readChecks(text, { branch: BRANCH });
  assert.deepEqual(read(checksFile()), { tip: CHECKED_TIP, results: [{ check: FRAGMENTS, exit: 0 }] });
  assert.deepEqual(read(checksFile({ results: [] })), { tip: CHECKED_TIP, results: [] });
  for (const [label, text] of [
    ["another branch", checksFile({ branch: "work-resolve-issue/issue-77-124-1" })],
    ["no tip", checksFile({ tip: "" })],
    ["a string exit", checksFile({ results: [{ check: FRAGMENTS, exit: "0" }] })],
    ["more results than a body lists", checksFile({ results: Array(21).fill({ check: FRAGMENTS, exit: 0 }) })],
    ["no version", JSON.stringify({ branch: BRANCH, tip: CHECKED_TIP, results: [] })],
    ["not JSON", "{"],
    ["none", ""],
  ]) {
    assert.equal(read(text), null, label);
  }
  assert.equal(readChecks(checksFile({ branch: "" }), { branch: "" }), null);
});

// .claude/rules/pr-body-contract.md: the closing line first, then Summary,
// Fix, Verification and Related, in that order.
test("the body follows the PR body contract's order", () => {
  for (const notDone of [[], [{ what: "x", required: false }]]) {
    const plan = decideDone({ outcome: { ...done, notDone } });
    assert.ok(plan.body.startsWith("Closes #77\n"), plan.body);
    const required = headings(plan.body).filter((h) => h !== "## Not verified");
    assert.deepEqual(required, ["## Summary", "## Fix", "## Verification", "## Related"]);
  }
});

// The live PR conventions: the repository's own PR template when it has one,
// else the org default, and the canonical body policy in the standards repo.
// Both are fetched, not copied, so a change to either fails this test.
async function liveText(url) {
  const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
  assert.ok(response.ok, `${url} answered ${response.status}`);
  return response.text();
}

test("the body fills every section of the live PR template and policy", async () => {
  const local = new URL("../../pull_request_template.md", import.meta.url);
  const template = existsSync(local)
    ? readFileSync(local, "utf8")
    : await liveText("https://raw.githubusercontent.com/melodic-software/.github/main/.github/PULL_REQUEST_TEMPLATE.md");
  const policy = JSON.parse(
    await liveText(
      "https://raw.githubusercontent.com/melodic-software/standards/main/components/pr-convention-policy/policy.json",
    ),
  );
  const templateSections = template
    .replaceAll(/<!--[\s\S]*?-->/g, "")
    .split("\n")
    .filter((line) => /^## /.test(line))
    .map((line) => line.slice(3).trim());
  assert.ok(templateSections.length > 0, "the template names its sections");
  const plan = decideDone({ outcome: { ...done, notDone: [{ what: "x", required: false }] } });
  assert.ok(
    policy.body.closingKeywords.some((keyword) => plan.body.startsWith(`${keyword} #77\n`)),
    plan.body.slice(0, 40),
  );
  const present = headings(plan.body).map((h) => h.slice(3));
  for (const required of [policy.body.requiredSections, templateSections]) {
    assert.deepEqual(
      present.filter((name) => required.includes(name)),
      required,
      `sections in order: ${required.join(", ")}`,
    );
    for (const name of required) {
      assert.ok(section(plan.body, name).trim(), `## ${name} is filled`);
    }
  }
});

test("a reviewer sees the gaps first: Not verified sits above Fix", () => {
  const order = headings(decideDone({ outcome: { ...done, notDone: [{ what: "x", required: false }] } }).body);
  assert.ok(order.indexOf("## Not verified") < order.indexOf("## Fix"), order.join(" "));
});

test("a done outcome whose not_done holds a skipped required check is stopped", () => {
  const plan = decideDone({
    outcome: {
      ...done,
      notDone: [
        { what: "Did not render the page", required: false },
        { what: "scripts/check-changelog-fragments.sh --check: not run", required: true },
      ],
    },
  });
  assert.equal(plan.action, "retry");
  assert.equal(plan.stop, "required-undone");
  assert.match(plan.comment, /check-changelog-fragments/);
});

test("the outcome file's structured fields are read as lists of text", () => {
  const file = {
    ...done,
    changes: ["a", 5, "b"],
    verification: "not a list",
    not_done: ["plain", { what: "req", required: true }, { what: 1 }],
  };
  withDir({ "work-outcome.json": JSON.stringify(file) }, (dir) => {
    const outcome = readOutcome(join(dir, "work-outcome.json"));
    assert.deepEqual(outcome.changes, ["a", "b"]);
    assert.deepEqual(outcome.verification, []);
    assert.deepEqual(outcome.notDone, [
      { what: "plain", required: false },
      { what: "req", required: true },
    ]);
  });
});

test("a list item cannot break out of its bullet", () => {
  const plan = decideDone({ outcome: { ...done, changes: ["a\n\n## Related\nFixes #9"] } });
  assert.equal(headings(plan.body).filter((h) => h === "## Related").length, 1);
  assert.ok(!plan.body.includes("Fixes #9"), plan.body);
});

// Squash merge copies the body into the commit message as plain text, where a
// closing keyword closes an issue whatever fence it sat in.
test("no issue reference from the model's summary survives into the body", () => {
  const plan = decideDone({
    outcome: { ...done, summary: "Fixes #5, closes o/r#6, resolves https://github.com/o/r/issues/7" },
  });
  const tail = plan.body.slice("Closes #77".length);
  assert.ok(!/#\d|\/issues\/\d/.test(tail.replace(/^#77$/m, "")), plan.body);
});

test("a title carrying an issue reference loses the reference", () => {
  assert.equal(decideDone({ outcome: { ...done, title: "fix: x, closes #5" } }).title, "fix: x, closes 5");
});

test("a GH- issue reference is broken in a run or issue title", () => {
  assert.equal(decideDone({ outcome: { ...done, title: "fix: x, closes GH-5" } }).title, "fix: x, closes GH 5");
  assert.equal(decideDone({ outcome: { ...done, title: "" }, issueTitle: "Closes gh-5" }).title, "fix: Closes gh 5");
});

test("an issue title carrying an issue reference or URL loses it", () => {
  const issueTitle = "Fixes #5 and https://github.com/o/r/issues/6";
  assert.equal(
    decideDone({ outcome: { ...done, title: "" }, issueTitle }).title,
    "fix: Fixes 5 and https: github.com o r issues 6",
  );
});

test("a diff the compare listing may have cut short carries the hold line while a path is denied", () => {
  const files = Array.from({ length: 300 }, (_, i) => `docs/f${i}.md`);
  assert.ok(decideDone({ changedFiles: files }).body.split("\n").includes("Hold: a human merges this"));
});

test("with no denied path a diff at the compare cap carries no hold line, since the cut can hide nothing", () => {
  const files = Array.from({ length: 300 }, (_, i) => `docs/f${i}.md`);
  assert.ok(!decideDone({ changedFiles: files, holdPaths: [] }).body.includes("Hold: a human merges this"));
});

test("done with no branch is retried, since nothing was committed", () => {
  const plan = decideDone({ branch: "" });
  assert.equal(plan.action, "retry");
  assert.equal(plan.stop, "done-no-commit");
});

// collect-patch.sh exits 3, and writes no patch, when a run leaves content at
// a stub name such as .npmrc or .env: possibly a planted credential or config
// file. The run's outcome file and records are its own to forge, so the
// refusal holds whatever they say.
test("a run whose patch collector refused goes to a person, whatever its outcome or records say", () => {
  const base = { issueNumber: 77, issueLabels: ["agent-ready"], branch: "", changedFiles: [], collectRefused: true };
  for (const [name, args] of [
    ["done", { outcome: { exit: "done", reason: "", title: "", summary: "" } }],
    ["unread", { outcome: readOutcome("/nonexistent/work-outcome.json") }],
    ["turn cap", { outcome: readOutcome("/nonexistent/work-outcome.json"), turnCap: { cap: 50 }, turnCapRestarts: 0, limits: { ...LIMIT_DEFAULTS, "turn-cap-restarts": 1 } }],
    ["resumed", { outcome: { exit: "done", reason: "", title: "", summary: "" }, resumed: "work-resolve-issue/issue-77-1-1" }],
  ]) {
    const plan = decide({ ...base, ...args });
    assert.equal(plan.stop, "collect-refused", name);
    assert.deepEqual(plan.addLabels, ["needs-human"], name);
    assert.deepEqual(plan.removeLabels, ["agent-ready"], name);
    assert.match(plan.comment, /\.npmrc/, name);
  }
});

// apply-issue-patch's escalation reason: a done run whose patch was refused
// committed something that never landed, and the person sees why.
// A protected path goes to the host queue, a credential shape to a person (a
// token-leak path, owner decision on #11021), and any other invalid patch or
// an apply fault back to the lane.
for (const [reason, why, action, labels] of [
  ["patch-protected-path", /a path the issue lane may not push/, "host-run", ["host-run"]],
  ["patch-credential", /credential shape/, "hand-back", ["needs-human"]],
  ["patch-invalid", /not a valid patch/, "retry", []],
  ["patch-not-applied", /did not apply/, "retry", []],
  ["patch-apply-failed", /failed before it committed or refused the patch/, "retry", []],
]) {
  test(`done whose patch apply-issue-patch refused (${reason}) routes to ${action} naming the reason, not an empty run`, () => {
    const plan = decideDone({ branch: "", escalation: reason, humanLabel: "needs-human", runUrl: "https://example/o/r/actions/runs/123" });
    assert.equal(plan.action, action);
    assert.deepEqual(plan.addLabels, labels);
    assert.ok(plan.comment.includes(`\`${reason}\``), plan.comment);
    assert.match(plan.comment, why);
    assert.doesNotMatch(plan.comment, /committed nothing/);
    assert.ok(plan.comment.includes("https://example/o/r/actions/runs/123"), plan.comment);
  });
}

test("a refused patch on a resumed run goes to the host queue instead of opening the PR from the resumed branch", () => {
  const plan = decideDone({ branch: "", resumed: "work-resolve-issue/issue-77-100-1", checks: { tip: CHECKED_TIP, results: [{ check: FRAGMENTS, exit: 0 }] }, escalation: "patch-protected-path" });
  assert.equal(plan.action, "host-run");
  assert.ok(plan.comment.includes("`patch-protected-path`"), plan.comment);
  assert.ok(plan.comment.includes("Partial work is on the branch `work-resolve-issue/issue-77-100-1`"), plan.comment);
});

// A failure after apply-issue-patch made its branch (a later step) leaves the
// branch's plan as it was.
test("patch-apply-failed changes no plan for a run whose branch apply-issue-patch made", () => {
  const branch = "work-resolve-issue/issue-77-100-1";
  assert.deepEqual(decideDone({ branch, escalation: "patch-apply-failed" }), decideDone({ branch }));
});

test("patch-empty changes no plan: a done run with no commit, a resumed run, or a pushback", () => {
  const resumed = { branch: "", resumed: "work-resolve-issue/issue-77-100-1", checks: { tip: CHECKED_TIP, results: [{ check: FRAGMENTS, exit: 0 }] } };
  assert.deepEqual(decideDone({ ...resumed, escalation: "patch-empty" }), decideDone(resumed));
  assert.deepEqual(decideDone({ branch: "", escalation: "patch-empty" }), decideDone({ branch: "" }));
  assert.match(decideDone({ branch: "", escalation: "patch-empty" }).comment, /committed nothing/);
  const pushback = { exit: "pushback", reason: "Which file?", cause: "intent", title: "", summary: "" };
  for (const escalation of ["patch-empty", "patch-protected-path"]) {
    assert.deepEqual(decideDone({ outcome: pushback, branch: "", escalation }), decideDone({ outcome: pushback, branch: "" }), escalation);
  }
});

test("pushback comments, adds needs-human and removes agent-ready", () => {
  const plan = decide({
    outcome: { exit: "pushback", reason: "Which file?", cause: "intent", title: "", summary: "" },
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: "",
    changedFiles: [],
    humanLabel: "needs-human",
  });
  assert.equal(plan.action, "hand-back");
  assert.deepEqual(plan.addLabels, ["needs-human"]);
  assert.deepEqual(plan.removeLabels, ["agent-ready"]);
  assert.match(plan.comment, /Which file\?/);
});

// The owner's rule for when work stops for the owner: a pre-edit question reaches a person only as an intent
// question, which the run names with `cause: "intent"`; a choice of means or a
// design detail, or a pushback naming no cause, is the lane's to decide.
test("a pushback whose cause opens with a hold code holds on that code, whatever its reason", () => {
  const plain = { issueNumber: 77, issueLabels: ["agent-ready"], branch: "", changedFiles: [], humanLabel: "needs-human" };
  for (const [cause, stop] of [
    ["cost-risk: provisions a paid Azure plan", "cost-risk"],
    ["security-risk: the deploy token is in the log", "security-risk"],
    ["design-change: a new store", "design-change"],
  ]) {
    const plan = decide({ ...plain, outcome: { exit: "pushback", reason: "Which plan?", cause, title: "", summary: "" } });
    assert.equal(plan.action, "hand-back", cause);
    assert.equal(plan.stop, stop, cause);
    assert.ok(plan.addLabels.includes("needs-human"), cause);
  }
});

test("a pushback-means intake comment shows the cause the run named", () => {
  const plain = { issueNumber: 77, issueLabels: ["agent-ready"], branch: "", changedFiles: [], humanLabel: "needs-human" };
  const plan = decide({ ...plain, outcome: { exit: "pushback", reason: "Which helper?", cause: "means: two helpers fit", title: "", summary: "" } });
  assert.equal(plan.stop, "pushback-means");
  assert.match(plan.comment, /The cause the run named:\n\n> means: two helpers fit/, plan.comment);
});

test("a pushback without cause intent goes back through intake instead of reaching a person", () => {
  const plain = { issueNumber: 77, issueLabels: ["agent-ready"], branch: "", changedFiles: [], humanLabel: "needs-human" };
  for (const cause of [undefined, "", "design", "means", 7]) {
    const plan = decide({ ...plain, outcome: { exit: "pushback", reason: "Split the test file or fix only the rows?", cause, title: "", summary: "" } });
    assert.equal(plan.action, "intake", String(cause));
    assert.equal(plan.stop, "pushback-means", String(cause));
    assert.deepEqual(plan.removeLabels, ["agent-ready", "status: ready", "admission-deferred"], String(cause));
    assert.ok(!plan.addLabels.includes("needs-human") && !plan.comment.includes("work-items:escalation"), plan.comment);
    assert.equal(parseReason(plan.comment), null, plan.comment);
  }
  for (const cause of ["intent", "INTENT", " Intent\n", "intent-change", "Intent-Change"]) {
    const intent = decide({ ...plain, outcome: { exit: "pushback", reason: "Which outcome?", cause, title: "", summary: "" } });
    assert.equal(intent.action, "hand-back", JSON.stringify(cause));
    assert.equal(parseReason(intent.comment).reason, "intent");
  }
  withDir({ "work-outcome.json": JSON.stringify({ exit: "pushback", reason: "Which outcome?", cause: "intent" }) }, (dir) => {
    assert.equal(readOutcome(join(dir, "work-outcome.json")).cause, "intent");
  });
});

// A pushback with no intent cause holds only for a hold code its reason opens
// with or its cause names; a security word alone goes to intake, whose own
// security rules judge it.
test("a pushback holds only for an explicit hold code, never for a security word alone", () => {
  const plain = { issueNumber: 77, issueLabels: ["agent-ready"], branch: "", changedFiles: [], humanLabel: "needs-human" };
  const run = (reason, cause) => decide({ ...plain, outcome: { exit: "pushback", reason, cause, title: "", summary: "" } });
  for (const reason of [
    "Should the fix inject the config through DI or read the file directly?",
    "Should this use the GITHUB_TOKEN or the lanes App token for the call?",
    "Which of the security review lane's two prompts should change?",
    "This needs an API key the lane does not hold.",
    "The issue asks to print the deploy token in the log.",
  ]) {
    const plan = run(reason);
    assert.equal(plan.stop, "pushback-means", reason);
    assert.equal(plan.action, "intake", reason);
    assert.ok(!plan.addLabels.includes("needs-human"), reason);
  }
  for (const [reason, cause, stop, code] of [
    ["security-risk: the issue asks to print the deploy token in the log.", undefined, "security-risk", "security"],
    ["design-change: the fix replaces the lane's routing table with a service.", undefined, "design-change", "design"],
    ["This provisions a paid Azure plan that bills the owner.", "cost-risk", "cost-risk", "cost"],
    ["This needs a new shared store other services depend on.", "design-change", "design-change", "design"],
    ["The fix needs the token rotated.", "security-risk", "security-risk", "security"],
    ["Which outcome does the issue want?", "intent_change", "pushback", "intent"],
    ["Which outcome does the issue want?", "intent change", "pushback", "intent"],
    ["Which outcome does the issue want?", " Intent_Change\n", "pushback", "intent"],
    ["cost-risk: provisions a paid Azure plan.", "intent", "cost-risk", "cost"],
    ["design-change: a new store.", "intent", "design-change", "design"],
  ]) {
    const plan = run(reason, cause);
    assert.equal(plan.action, "hand-back", `${cause} ${reason}`);
    assert.equal(plan.stop, stop, `${cause} ${reason}`);
    assert.equal(parseReason(plan.comment).reason, code, plan.comment);
  }
  // A cause that names a code with no hold route, or a hold-class word that
  // is not a code, is no hold.
  for (const cause of ["cost", "host-only", "stopped", "pushback-means"]) {
    assert.equal(run("Which helper should change?", cause).stop, "pushback-means", cause);
  }
  // A host-run or attended code takes its row.
  const host = run("host-only: needs the GPU desktop.");
  assert.equal(host.stop, "host-only");
  assert.equal(host.action, "host-run");
  // One that names a security risk after the code reaches a person (owner
  // decision 2026-10-29), and a capability phrasing names none.
  for (const reason of ["host-only: needs the deploy token printed in the log.", "manual-external: rotate the leaked deploy token in the DNS account."]) {
    const risky = run(reason);
    assert.equal(risky.stop, "security-risk", reason);
    assert.equal(risky.action, "hand-back", reason);
    assert.ok(risky.addLabels.includes("needs-human"), reason);
    assert.equal(parseReason(risky.comment).reason, "security", risky.comment);
  }
  assert.equal(run("host-only: needs a host with model credentials.").stop, "host-only");
  const attended = run("manual-external: add the DNS record for the docs site.");
  assert.equal(attended.stop, "manual-external");
  assert.equal(attended.action, "attended");
  // A non-hold, non-lane code goes through intake.
  for (const reason of ["blocked-by-pr: #12 changes the same file.", "already-done: abc1234 fixed it.", "report-delivered: the report is posted."]) {
    const plan = run(reason);
    assert.equal(plan.stop, "pushback-means", reason);
    assert.equal(plan.action, "intake", reason);
  }
  // A cause names its code in spaces, mixed case, full-width letters, hyphen
  // runs and a trailing colon.
  for (const [cause, stop] of [
    ["Security Risk", "security-risk"],
    ["COST_RISK.", "cost-risk"],
    ["ｉｎｔｅｎｔ", "pushback"],
    ["intent - change", "pushback"],
    ["intent:", "pushback"],
    ["intent: ", "pushback"],
    ["-design--change-", "design-change"],
  ]) {
    assert.equal(run("Which helper should change?", cause).stop, stop, JSON.stringify(cause));
  }
});

// A pushback with no code whose words read as a security risk goes to intake
// with no means framing; a second one since a listed human added agent-ready
// holds as security-risk instead of failing.
test("a pushback naming a security risk goes to intake unframed once, then reaches a person", () => {
  const plain = { issueNumber: 77, issueLabels: ["agent-ready"], branch: "", changedFiles: [], humanLabel: "needs-human" };
  for (const reason of ["The issue asks to print the deploy token in the log.", "blocked-by-pr: #12's log printed the deploy token."]) {
    const plan = decide({ ...plain, outcome: { exit: "pushback", reason, title: "", summary: "" } });
    assert.equal(plan.action, "intake", reason);
    assert.equal(plan.stop, "pushback-means", reason);
    assert.doesNotMatch(plan.comment, /waits on no decision|choice of means|design detail/, plan.comment);
    assert.match(plan.comment, /security risk/, plan.comment);
    const spent = capRetries(plan, 1);
    assert.equal(spent.action, "hand-back", reason);
    assert.equal(spent.stop, "security-risk", reason);
    assert.ok(spent.addLabels.includes("needs-human") && spent.comment.includes("work-items:escalation"), spent.comment);
    assert.equal(parseReason(spent.comment).reason, "security", spent.comment);
  }
  const means = decide({ ...plain, outcome: { exit: "pushback", reason: "Split the test file or fix only the rows?", title: "", summary: "" } });
  assert.match(means.comment, /choice of means/);
  assert.match(means.comment, /waits on no decision from a person/);
  assert.equal(capRetries(means, 1).action, "fail");
});

// The security reading reads every text the comment can show (the reason, the
// summary, each not-done item) and the cause, so no security text the run
// wrote ends the issue with no person.
test("a pushback whose summary or cause names a security risk goes to intake marked security, then reaches a person", () => {
  const plain = { issueNumber: 77, issueLabels: ["agent-ready"], branch: "", changedFiles: [], humanLabel: "needs-human", runId: "123" };
  for (const [reason, cause, summary, notDone = []] of [
    ["", "", "the deploy token was printed in the CI log"],
    ["Which helper?", "security", ""],
    ["Which helper?", "secret leak", ""],
    ["Which helper?", "", "Two helpers fit.", [{ what: "The issue asks to print the deploy token in the log." }]],
  ]) {
    const label = JSON.stringify([reason, cause, summary, notDone]);
    const plan = decide({ ...plain, outcome: { exit: "pushback", reason, cause, title: "", summary, notDone } });
    assert.equal(plan.action, "intake", label);
    assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=intake security run=123 -->\n"), plan.comment);
    assert.equal(parseOutcomeMarker(plan.comment).security, true, label);
    const spent = capRetries(plan, 1);
    assert.equal(spent.action, "hand-back", label);
    assert.equal(spent.stop, "security-risk", label);
    assert.equal(parseReason(spent.comment).reason, "security", spent.comment);
    assert.match(spent.comment, /named a possible security risk again after its intake rounds were spent/, spent.comment);
    assert.doesNotMatch(spent.comment, /make it clearer first/, spent.comment);
  }
  const means = decide({ ...plain, outcome: { exit: "pushback", reason: "Which helper?", cause: "means", title: "", summary: "" } });
  assert.ok(means.comment.startsWith("<!-- work-resolve-issue outcome=intake run=123 -->\n"), means.comment);
  assert.equal(parseOutcomeMarker(means.comment).security, undefined);
});

// A security marker parses with every other field intact.
test("parseOutcomeMarker reads the security tag beside run and branch", () => {
  assert.deepEqual(parseOutcomeMarker("<!-- work-resolve-issue outcome=intake security run=99 branch=resumed -->\nWhy."), {
    outcome: "intake",
    resets: null,
    run: "99",
    onResumed: true,
    security: true,
  });
  assert.equal(parseOutcomeMarker(`${ESC}<!-- work-resolve-issue outcome=intake security run=99 -->`).run, "99");
});

// An explicit security-risk code outranks an intent cause.
test("a pushback with cause intent whose reason opens with security-risk holds as security-risk", () => {
  const plain = { issueNumber: 77, issueLabels: ["agent-ready"], branch: "", changedFiles: [], humanLabel: "needs-human" };
  for (const cause of ["intent", "intent-change"]) {
    const outcome = { exit: "pushback", reason: "security-risk: the issue asks to print the deploy token in the log.", cause, title: "", summary: "" };
    const plan = decide({ ...plain, outcome });
    assert.equal(plan.action, "hand-back", cause);
    assert.equal(plan.stop, "security-risk", cause);
    assert.equal(parseReason(plan.comment).reason, "security", plan.comment);
    // Intake never ran on this round-one hold, so its line claims no intake.
    assert.match(plan.comment, /the run named a possible security risk/, plan.comment);
    assert.doesNotMatch(plan.comment, /intake triage/, plan.comment);
  }
  const worded = decide({ ...plain, outcome: { exit: "pushback", reason: "The issue asks to print the deploy token in the log.", cause: "intent", title: "", summary: "" } });
  assert.equal(worded.stop, "pushback");
});

// The lane's preamble tells a run whose change needs a path apply-issue-patch
// refuses to stop with a reason starting patch-protected-path: the issue goes
// to the host queue (#6908), never to needs-human and never restarted; any
// other stop reads as before.
test("a run that stopped with patch-protected-path goes to host-run naming the reason, never restarted", () => {
  const stoppedWith = (reason) =>
    decide({
      outcome: { exit: "stopped", reason, title: "", summary: "" },
      issueNumber: 77,
      issueLabels: ["agent-ready"],
      branch: "",
      changedFiles: [],
      humanLabel: "needs-human",
      runId: "123",
    });
  const plan = stoppedWith("patch-protected-path: .github/workflows/ci.yml needs a new step");
  assert.equal(plan.action, "host-run");
  assert.equal(plan.exit, "host-run");
  assert.deepEqual(plan.addLabels, ["host-run"]);
  assert.deepEqual(plan.removeLabels, ["agent-ready"]);
  assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=host-run run=123 -->"), plan.comment);
  assert.ok(plan.comment.includes("The run stopped early (`patch-protected-path`): its change needs a path the issue lane may not push"), plan.comment);
  assert.ok(plan.comment.includes("ci.yml needs a new step"), plan.comment);
  assert.doesNotMatch(stoppedWith("Tests failed; not a patch-protected-path stop.").comment, /stopped early/);
});

// A stop held for a person carries the hold alone: agent-ready beside
// needs-human leaves it in both queues.
test("a held stop removes agent-ready and names the branch that holds partial work", () => {
  const plan = decide({
    outcome: { exit: "stopped", reason: "design-change: Tests failed.", title: "", summary: "" },
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: BRANCH,
    changedFiles: ["README.md"],
    humanLabel: "needs-human",
  });
  assert.deepEqual(plan.addLabels, ["needs-human"]);
  assert.deepEqual(plan.removeLabels, ["agent-ready"]);
  assert.ok(plan.comment.includes(BRANCH));
  assert.match(plan.comment, /A retry continues from it while it is not behind the default branch, and otherwise starts fresh from the default branch; delete the branch first to always start fresh\./);
  assert.ok(plan.comment.includes("remove `needs-human` and add `agent-ready` again"), plan.comment);
});

// main against a fake GitHub API: the calls it makes are the lane's effect on
// the issue, an unmanaged dependency, so they are what the test checks.
function fakeFetch(routes) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    const method = init.method ?? "GET";
    const path = new URL(url).pathname;
    calls.push({ method, path, body: init.body ? JSON.parse(init.body) : undefined });
    // An issue no open PR closes, unless a route says otherwise.
    // A held PR's human-merge-hold label write succeeds, unless a route says otherwise.
    const none =
      path === "/graphql"
        ? [method, /./, 200, { data: { repository: { issue: { closedByPullRequestsReferences: { nodes: [], pageInfo: { hasNextPage: false } } } } } }]
        : method === "POST" && /\/issues\/90\/labels$/.test(path)
          ? [method, /./, 200, []]
          : null;
    const route = routes.find(([m, p]) => m === method && p.test(path)) ?? none;
    const [, , status, body] = route ?? [method, /./, 404, { message: "Not Found" }];
    return { ok: status < 300, status, json: async () => body, text: async () => JSON.stringify(body) };
  };
  return { fetch, calls };
}

function env(dir) {
  return {
    ISSUE_NUMBER: "77",
    WORK_OUTCOME_DIR: dir,
    GH_TOKEN: "t",
    GITHUB_REPOSITORY: "o/r",
    GITHUB_API_URL: "https://api.example",
    GITHUB_SERVER_URL: "https://example",
    GITHUB_RUN_ID: "123",
    GITHUB_RUN_ATTEMPT: "1",
    TRACKER_CONFIG: join(dir, "absent.json"),
    RUNNER_CHECKS: existsSync(join(dir, "runner-checks")) ? readFileSync(join(dir, "runner-checks"), "utf8") : "",
  };
}

const ISSUE = [/./, 200, { number: 77, created_at: "2026-10-01T00:00:00Z", labels: [{ name: "agent-ready" }, { name: "work-class: read-only" }] }];

// #7291 (run 40284651739): a run that wrote no readable outcome file crashed,
// which needs no person. It keeps agent-ready, adds no label and posts a retry
// marker with no escalation marker, so work-unblock restarts it.
test("main with no outcome files keeps agent-ready and posts a retry, never needs-human", async () => {
  await withAsyncDir({}, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ...HISTORY,
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: env(dir), fetch }), 0);
    assert.ok(!calls.some((c) => c.path.endsWith("/labels")), JSON.stringify(calls));
    const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
    assert.ok(comment.startsWith("<!-- work-resolve-issue outcome=retry run=123 -->"), comment);
    assert.match(comment, /`outcome-unread`/);
    assert.match(comment, /retry 1 of 2/);
    assert.ok(!calls.some((c) => c.path.endsWith("/pulls")));
  });
});

test("main on a run whose issue changed after agent-ready comments that reason, not a missing outcome file", async () => {
  await withDir({ "lane.json": JSON.stringify({ branch: "", class: "issue-edited" }) }, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: env(dir), fetch }), 0);
    const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
    assert.match(comment, /the issue's title or body changed after `agent-ready` was added/);
    assert.doesNotMatch(comment, /no readable outcome file/);
  });
});

// agent-ready starts this lane, so a run that added it would start the next.
test("main refuses a human-gated label that is agent-ready and writes no label", async () => {
  // Not withDir: main reads the tracker config after its first await.
  const dir = tempDir("outcome-");
  try {
    writeFileSync(join(dir, "tracker.json"), JSON.stringify({ config: { role_labels: { "human-gated": " Agent-Ready" } } }));
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), TRACKER_CONFIG: join(dir, "tracker.json") }, fetch }), 1);
    assert.ok(!calls.some((c) => c.method === "POST"));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// A run its issue dimensions skipped took no model turn, so it left no
// outcome. Owner decision on #11021: an Uncertainty skip reaches no person; the
// issue drops agent-ready and status: ready and parks at status: confirmed
// with the reason, as admission parks the same refusal: the lanes App's
// admission comment first (intake-reenter lifts status: confirmed only beside
// it), then the labels, then the lane's outcome comment.
for (const [reason, step] of [
  ["research-first", "plan or research the approach"],
  ["probe-first", "run a probe or spike first"],
]) {
  test(`main on a ${reason} dimension skip parks the issue at status: confirmed with the reason, to no person`, async () => {
    await withDir({}, async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ["GET", /\/issues\/77\/comments/, 200, []],
        ["GET", /\/issues\/77\/events/, 200, []],
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/issues\/77\/labels\//, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: { ...env(dir), DIMENSION_SKIP: reason }, fetch }), 0);
      const writes = calls.filter((c) => c.method !== "GET");
      const [admission, labels, ...rest] = writes;
      assert.equal(admission.method, "POST");
      assert.ok(admission.body.body.startsWith("<!-- intake-triage admission -->\nNot admitted to the issue lane: "), admission.body.body);
      assert.ok(admission.body.body.includes(`\`${reason}\``) && admission.body.body.includes(step), admission.body.body);
      assert.deepEqual(labels.body, { labels: ["status: confirmed"] });
      const removed = rest.filter((c) => c.method === "DELETE").map((c) => decodeURIComponent(c.path.split("/labels/")[1]));
      assert.deepEqual(removed, ["agent-ready", "status: ready", "admission-deferred"]);
      const comment = rest.at(-1).body.body;
      assert.ok(comment.startsWith("<!-- work-resolve-issue outcome=parked run=123 -->\n"), comment);
      assert.ok(comment.includes(`\`${reason}\``) && comment.includes(step), comment);
      assert.ok(comment.includes("status: confirmed"), comment);
      assert.ok(!comment.includes("work-items:escalation") && !comment.includes("needs-human"), comment);
      assert.equal(parseReason(comment), null);
      assert.ok(!calls.some((c) => c.path.endsWith("/pulls") || c.path.includes("/compare/")));
    });
  });
}

// The lanes App keeps one admission comment per issue, so a park edits the one
// admission already wrote.
test("main on a dimension skip edits the lanes App's earlier admission comment in place", async () => {
  await withDir({}, async (dir) => {
    const own = { id: 501, user: { login: "melodic-automation-lanes[bot]" }, body: "<!-- intake-triage admission -->\nNot admitted to the issue lane yet: an older reason.", created_at: "2026-10-20T00:00:00Z" };
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["GET", /\/issues\/77\/comments/, 200, [own]],
      ["GET", /\/issues\/77\/events/, 200, []],
      ["PATCH", /\/issues\/comments\/501$/, 200, {}],
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["DELETE", /\/issues\/77\/labels\//, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), DIMENSION_SKIP: "probe-first" }, fetch }), 0);
    const patched = calls.filter((c) => c.method === "PATCH");
    assert.equal(patched.length, 1);
    assert.match(patched[0].body.body, /^<!-- intake-triage admission -->\nNot admitted to the issue lane: .*`probe-first`/);
    const posted = calls.filter((c) => c.method === "POST" && c.path.endsWith("/comments"));
    assert.deepEqual(posted.map((c) => c.body.body.split("\n")[0]), ["<!-- work-resolve-issue outcome=parked run=123 -->"]);
  });
});

// Owner Q93: intake splits a Size Large issue, so a split-required skip goes
// back through intake with no person: agent-ready and the status labels
// admission reads come off, and nothing adds needs-human.
test("main on a split-required dimension skip sends the issue back through intake, to no person", async () => {
  await withDir({}, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["GET", /\/issues\/77\/comments/, 200, []],
      ["GET", /\/issues\/77\/events/, 200, []],
      ["DELETE", /\/issues\/77\/labels\//, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), DIMENSION_SKIP: "split-required" }, fetch }), 0);
    assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/labels")));
    const removed = calls.filter((c) => c.method === "DELETE").map((c) => decodeURIComponent(c.path.split("/labels/")[1]));
    assert.deepEqual(removed, ["agent-ready", "status: ready", "admission-deferred"]);
    const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
    assert.ok(comment.startsWith("<!-- work-resolve-issue outcome=intake run=123 -->\n"), comment);
    assert.ok(!comment.includes("work-items:escalation") && !comment.includes("needs-human"), comment);
    assert.match(comment, /triage sweep sends it back through intake/);
    assert.match(comment, /owner Q93/);
  });
});

// A trusted split child keeps Size Large past admission (owner Q93), so the
// lane may skip it again: a second intake since a listed human added
// agent-ready fails, so intake and the lane never loop.
test("main fails a split-required skip that intake already sent back once, to no person", async () => {
  await withDir({}, async (dir) => {
    const earlier = { user: { login: "melodic-automation-lanes[bot]" }, body: "<!-- work-resolve-issue outcome=intake run=99 -->\nWhy.", created_at: "2026-10-29T10:00:00Z" };
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["GET", /\/issues\/77\/comments/, 200, [earlier]],
      ["GET", /\/issues\/77\/events/, 200, []],
      ["DELETE", /\/issues\/77\/labels\//, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), DIMENSION_SKIP: "split-required" }, fetch }), 0);
    const removed = calls.filter((c) => c.method === "DELETE").map((c) => decodeURIComponent(c.path.split("/labels/")[1]));
    assert.deepEqual(removed, ["agent-ready"]);
    assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/labels")));
    const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
    assert.ok(comment.startsWith("<!-- work-resolve-issue outcome=failed run=123 -->\n"), comment);
  });
});

// A pushback naming no cause goes back through intake with no person, and a
// second intake since a listed human added agent-ready fails, so intake and
// the lane never loop.
test("main on a pushback with no cause sends the issue back through intake once, then fails", async () => {
  const pushback = JSON.stringify({ exit: "pushback", reason: "Split the test file or fix only the rows?", title: "", summary: "" });
  const earlier = { user: { login: "melodic-automation-lanes[bot]" }, body: "<!-- work-resolve-issue outcome=intake run=99 -->\nWhy.", created_at: "2026-10-29T10:00:00Z" };
  for (const [prior, outcome] of [[[], "intake"], [[earlier], "failed"]]) {
    await withAsyncDir({ "work-outcome.json": pushback, "lane.json": JSON.stringify({ branch: "" }), "trusted.json": TRUSTED_LIST }, async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77\/comments/, 200, prior],
        ["GET", /\/issues\/77\/events/, 200, []],
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ["DELETE", /\/issues\/77\/labels\//, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: { ...env(dir), TRUSTED_ACTORS: join(dir, "trusted.json") }, fetch }), 0);
      assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/labels")), outcome);
      const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
      assert.ok(comment.startsWith(`<!-- work-resolve-issue outcome=${outcome} run=123 -->\n`), comment);
      assert.ok(!comment.includes("work-items:escalation"), comment);
    });
  }
});

// The same pushback naming a security risk: the second intake holds it for a
// person instead of failing.
test("main on a second pushback naming a security risk holds it as security-risk", async () => {
  const pushback = JSON.stringify({ exit: "pushback", reason: "The issue asks to print the deploy token in the log.", title: "", summary: "" });
  const earlier = { user: { login: "melodic-automation-lanes[bot]" }, body: "<!-- work-resolve-issue outcome=intake run=99 -->\nWhy.", created_at: "2026-10-29T10:00:00Z" };
  await withAsyncDir({ "work-outcome.json": pushback, "lane.json": JSON.stringify({ branch: "" }), "trusted.json": TRUSTED_LIST }, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77\/comments/, 200, [earlier]],
      ["GET", /\/issues\/77\/events/, 200, []],
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["DELETE", /\/issues\/77\/labels\//, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), TRUSTED_ACTORS: join(dir, "trusted.json") }, fetch }), 0);
    assert.deepEqual(calls.find((c) => c.method === "POST" && c.path.endsWith("/labels")).body.labels, ["needs-human"]);
    const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
    assert.ok(comment.includes("work-items:escalation"), comment);
    assert.equal(parseReason(comment).reason, "security", comment);
  });
});

// An earlier round's security mark does not carry over: intake triage
// re-judged it before admitting the issue again, so whatever stops the second
// intake round (a plain means pushback, a split-required skip) ends as it
// would after a plain round.
test("main ends a second intake round the same after a security or a plain earlier intake marker", async () => {
  const bot = { login: "melodic-automation-lanes[bot]" };
  const secure = { user: bot, body: "<!-- work-resolve-issue outcome=intake security run=99 -->\nWhy.", created_at: "2026-10-29T10:00:00Z" };
  const plainEarlier = { user: bot, body: "<!-- work-resolve-issue outcome=intake run=99 -->\nWhy.", created_at: "2026-10-29T10:00:00Z" };
  const means = JSON.stringify({ exit: "pushback", reason: "Split the test file or fix only the rows?", title: "", summary: "" });
  for (const [name, prior, files, extra] of [
    ["security then means pushback", secure, { "work-outcome.json": means, "lane.json": JSON.stringify({ branch: "" }) }, {}],
    ["plain then means pushback", plainEarlier, { "work-outcome.json": means, "lane.json": JSON.stringify({ branch: "" }) }, {}],
  ]) {
    await withAsyncDir({ ...files, "trusted.json": TRUSTED_LIST }, async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77\/comments/, 200, [prior]],
        ["GET", /\/issues\/77\/events/, 200, []],
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/issues\/77\/labels\//, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: { ...env(dir), TRUSTED_ACTORS: join(dir, "trusted.json"), ...extra }, fetch }), 0, name);
      const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
      assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/labels")), name);
      assert.ok(comment.startsWith("<!-- work-resolve-issue outcome=failed run=123 -->\n"), comment);
    });
  }
});

// A spent retry fails the same after a security or a plain intake round.
test("main fails a spent retry the same after a security or a plain earlier intake marker", async () => {
  const bot = { login: "melodic-automation-lanes[bot]" };
  const marker = (outcome, run, at) => ({ user: bot, body: `<!-- work-resolve-issue outcome=${outcome} run=${run} -->\nWhy.`, created_at: at });
  for (const first of ["intake security", "intake"]) {
    const prior = [marker(first, "97", "2026-10-29T10:00:00Z"), marker("retry", "98", "2026-10-29T11:00:00Z"), marker("retry", "99", "2026-10-29T12:00:00Z")];
    await withAsyncDir({}, async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ["GET", /\/issues\/77\/comments$/, 200, prior],
        ["GET", /\/issues\/77\/events$/, 200, []],
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0, first);
      const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
      assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/labels")), first);
      assert.equal(parseOutcomeMarker(comment).outcome, "failed");
    });
  }
});

// A report-delivered close closes the same after a security or a plain intake round.
test("main closes a report-delivered stop the same after a security or a plain earlier intake marker", async () => {
  const bot = { login: "melodic-automation-lanes[bot]" };
  const report = JSON.stringify({ exit: "stopped", reason: "report-delivered: the report is below", summary: "Rows 4 and 9 are stale." });
  for (const first of ["intake security", "intake"]) {
    const prior = [{ user: bot, body: `<!-- work-resolve-issue outcome=${first} run=97 -->\nWhy.`, created_at: "2026-10-29T10:00:00Z" }];
    await withAsyncDir({ "work-outcome.json": report }, async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ["GET", /\/issues\/77\/comments$/, 200, prior],
        ["GET", /\/issues\/77\/events$/, 200, []],
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
        ["PATCH", /\/issues\/77$/, 200, {}],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0, first);
      const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
      assert.ok(calls.some((c) => c.method === "PATCH" && c.body?.state === "closed"), first);
      assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/labels")), first);
      assert.ok(comment.length > 0, first);
    });
  }
});

// An issue whose author is outside the trusted list stops at the admit job;
// report-skip says so on the issue and takes agent-ready off, with no
// needs-human: a listed human re-files the work, and a retry stops again.
test("main on an outside-author stop removes agent-ready and posts one comment telling a listed human to re-file", async () => {
  await withDir({}, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77\/comments$/, 200, []],
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), DIMENSION_SKIP: "outside-author" }, fetch }), 0);
    assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/labels")));
    assert.deepEqual(calls.filter((c) => c.method === "DELETE").map((c) => c.path.split("/labels/")[1]), ["agent-ready"]);
    const comments = calls.filter((c) => c.method === "POST" && c.path.endsWith("/comments"));
    assert.equal(comments.length, 1);
    const comment = comments[0].body.body;
    assert.equal(parseOutcomeMarker(comment).outcome, "outside-author");
    assert.match(comment, /trusted/);
    assert.match(comment, /re-file/);
    assert.ok(!comment.includes("add `agent-ready` again"), comment);
  });
});

// lane.json's `stale`: the stale lane branch the run started fresh past,
// which issue-prior found no comment naming. report-outcome names it once on
// the issue, beside its usual report, and never deletes it.
test("main names lane.json's stale branch on the issue once, and deletes no branch", async () => {
  const stale = "work-resolve-issue/issue-77-400-1";
  await withAsyncDir({ "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: "", stale }) }, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), ESCALATION_REASON: "patch-protected-path" }, fetch }), 0);
    const named = calls.filter((c) => c.method === "POST" && c.path.endsWith("/comments") && c.body.body.startsWith("<!-- work-resolve-issue stale-branch="));
    assert.equal(named.length, 1);
    assert.equal(named[0].body.body.split("\n")[0], `<!-- work-resolve-issue stale-branch=${stale} -->`);
    assert.ok(named[0].body.body.includes(`\`${stale}\``), named[0].body.body);
    assert.doesNotMatch(named[0].body.body, /no lane deletes it/, "the next run on the issue deletes it");
    assert.match(named[0].body.body, /next run on this issue deletes it/);
    assert.equal(parseOutcomeMarker(named[0].body.body), null, "the stale comment is no outcome marker");
    assert.ok(!calls.some((c) => c.path.includes("/git/refs")), "no branch is deleted");
  });
});

test("main names no stale branch when lane.json has none, or one of another shape", async () => {
  for (const stale of ["", "main", "work-resolve-issue/issue-7-400-1"]) {
    await withAsyncDir({ "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: "", stale }) }, async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: { ...env(dir), ESCALATION_REASON: "patch-protected-path" }, fetch }), 0);
      assert.ok(!calls.some((c) => c.method === "POST" && c.body?.body?.includes("stale-branch=")), JSON.stringify(stale));
    });
  }
});

// A re-run of report-skip finds the lanes App's own outside-author comment and
// posts no second one; the same marker from anyone else (the outside author
// can write it) does not count.
test("main on an outside-author stop posts no second comment when the lanes App already posted one", async () => {
  const marker = "<!-- work-resolve-issue outcome=outside-author run=99 -->\nThe lane did not start this issue.";
  for (const [login, posts] of [
    ["melodic-automation-lanes[bot]", 0],
    ["stranger", 1],
  ]) {
    await withDir({}, async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77\/comments$/, 200, [{ id: 5, user: { login }, body: marker }]],
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: { ...env(dir), DIMENSION_SKIP: "outside-author" }, fetch }), 0);
      assert.equal(calls.filter((c) => c.method === "POST" && c.path.endsWith("/comments")).length, posts, login);
      assert.ok(calls.some((c) => c.method === "DELETE" && c.path.endsWith("/labels/agent-ready")), login);
    });
  }
});

test("main refuses a dimension skip it does not know and writes nothing", async () => {
  await withDir({}, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), DIMENSION_SKIP: "awaiting-human" }, fetch }), 1);
    assert.ok(!calls.some((c) => c.method !== "GET"));
  });
});

test("main on done with apply-issue-patch's escalation reason hands the issue back naming it", async () => {
  await withDir({ "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: "" }) }, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), ESCALATION_REASON: "patch-protected-path" }, fetch }), 0);
    const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
    assert.ok(comment.includes("`patch-protected-path`"), comment);
    assert.doesNotMatch(comment, /committed nothing/);
    assert.ok(!calls.some((c) => c.path.endsWith("/pulls")));
  });
});

// The read runner's scan job refused the run's output (say a patch over its
// 262144-byte cap), so it uploaded no outcome and its scan-refusal job a
// scan-refused-<attempt>.txt marker instead. The
// hand-back names the refusal, not a missing outcome file; the marker's text
// picks one fixed sentence and never reaches the comment.
// `labels` is the label the route adds: none for a retry, needs-human for a hold.
async function scanRefusedComment({ outcome = null, marker = null, name = "scan-refused-1.txt", read = "success", attempt = "1", lane = null, labels = [] } = {}) {
  const dir = tempDir("outcome-");
  try {
    if (lane) {
      writeFileSync(join(dir, "lane.json"), JSON.stringify(lane));
    }
    if (outcome) {
      writeFileSync(join(dir, "work-outcome.json"), JSON.stringify(outcome));
      writeFileSync(join(dir, "lane.json"), JSON.stringify({ branch: "" }));
    }
    const refusedDir = join(dir, "scan-refused");
    mkdirSync(refusedDir);
    if (marker !== null) {
      writeFileSync(join(refusedDir, name), marker);
    }
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ...HISTORY,
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), GITHUB_RUN_ATTEMPT: attempt, SCAN_REFUSED_DIR: refusedDir, SCAN_REFUSED_READ: read }, fetch }), 0);
    assert.deepEqual(calls.find((c) => c.method === "POST" && c.path.endsWith("/labels"))?.body.labels ?? [], labels);
    assert.ok(!calls.some((c) => c.path.endsWith("/pulls")));
    return calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("main retries a run whose scan refused an oversize patch naming the patch cap, not a missing outcome", async () => {
  const comment = await scanRefusedComment({ marker: "patch\n" });
  assert.ok(comment.includes("too-large: the patch was over its 262144-byte cap"), comment);
  assert.doesNotMatch(comment, /no readable outcome file/);
  assert.equal(parseOutcomeMarker(comment).outcome, "retry");
});

// A refusal means a model ran, so a lane.json that says it never started loses.
test("a scan refusal outranks a lane.json issue-file class in the hand-back", async () => {
  const comment = await scanRefusedComment({ marker: "patch\n", lane: { branch: "", class: "issue-edited" } });
  assert.ok(comment.includes("too-large: the patch was over its 262144-byte cap"), comment);
  assert.doesNotMatch(comment, /did not start/);
});

// Any other refusal may be a credential shape, so a person decides it.
test("main hands back a run whose scan refused any other output naming the scan refusal", async () => {
  const comment = await scanRefusedComment({ marker: "output", name: "scan-refused-2-rung-up.txt", attempt: "2", labels: ["needs-human"] });
  assert.ok(comment.includes("The scan job refused the run's output, so nothing was published. The run's log names why."), comment);
  assert.doesNotMatch(comment, /no readable outcome file|262144|too-large/);
});

test("a forged scan refusal marker's text never reaches the hand-back", async () => {
  const comment = await scanRefusedComment({ marker: "patch @someone #1 https://evil.example", labels: ["needs-human"] });
  assert.ok(comment.includes("The scan job refused the run's output, so nothing was published. The run's log names why."), comment);
  assert.doesNotMatch(comment, /someone|evil|262144|too-large/);
});

test("a file that is not a scan refusal marker is no refusal", async () => {
  const comment = await scanRefusedComment({ marker: "patch", name: "scan-refused-0.txt" });
  assert.ok(comment.includes("no readable outcome file"), comment);
});

test("an earlier attempt's refusal marker is no refusal of the current attempt", async () => {
  const comment = await scanRefusedComment({ marker: "patch", name: "scan-refused-1.txt", attempt: "2" });
  assert.ok(comment.includes("no readable outcome file"), comment);
  assert.doesNotMatch(comment, /scan job refused|262144/i);
});

test("with no readable run attempt no refusal marker is read", async () => {
  const comment = await scanRefusedComment({ marker: "patch", attempt: "" });
  assert.ok(comment.includes("no readable outcome file"), comment);
  assert.doesNotMatch(comment, /scan job refused|262144/i);
});

test("a readable outcome wins over a scan refusal marker", async () => {
  const comment = await scanRefusedComment({ outcome: { exit: "stopped", reason: "design-change: The issue names no file." }, marker: "patch", labels: ["needs-human"] });
  assert.ok(comment.includes("The issue names no file."), comment);
  assert.doesNotMatch(comment, /262144|scan job refused/i);
});

test("a failed marker download claims no refusal: the hand-back keeps the missing-outcome text", async () => {
  const comment = await scanRefusedComment({ read: "failure" });
  assert.ok(comment.includes("no readable outcome file"), comment);
  assert.doesNotMatch(comment, /scan job refused/i);
});

test("main refuses an escalation reason it does not know and writes nothing", async () => {
  await withDir({ "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: "" }) }, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), ESCALATION_REASON: "ci-fix-protected-path" }, fetch }), 1);
    assert.ok(!calls.some((c) => c.method !== "GET"));
  });
});

test("main on done opens a ready PR from the branch, labels it human-merge-hold when it holds, and writes nothing to the issue", async () => {
  await withDir(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: BRANCH }), "runner-checks": checksFile() },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        branchTip(),
        ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
        ["GET", /\/compare\//, 200, { files: [{ filename: "README.md" }] }],
        ["GET", /\/pulls$/, 200, []],
        ["POST", /\/pulls$/, 201, { number: 90, html_url: "https://example/o/r/pull/90" }],
        ["POST", /\/issues\/90\/labels$/, 200, []],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      const pull = calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body;
      assert.equal(pull.draft, false);
      assert.equal(pull.head, BRANCH);
      assert.equal(pull.base, "main");
      assert.ok(pull.body.startsWith("Closes #77\n"));
      assert.ok(pull.body.split("\n").includes(HOLD_LINE), pull.body);
      assert.deepEqual(calls.filter((c) => c.path.endsWith("/issues/90/labels")).map((c) => c.body), [{ labels: ["human-merge-hold"] }]);
      assert.ok(!calls.some((c) => c.method === "POST" && c.path.startsWith("/repos/o/r/issues/77/")));
    },
  );
});

// #7497: an outcome file that says done with nothing left undone opens no PR
// when the runner's checks failed, are missing, or ran on another tip.
test("main on done opens no PR and retries the issue when the runner's checks do not pass", async () => {
  for (const [label, files, tip] of [
    ["a failing check", { "runner-checks": checksFile({ results: [{ check: FRAGMENTS, exit: 1 }] }) }, CHECKED_TIP],
    ["no check results", {}, CHECKED_TIP],
    // Code the model started can rewrite the outcome artifact, so results
    // there are not the runner's: only run-checks' job output counts.
    ["results only in the outcome artifact", { "checks.json": checksFile() }, CHECKED_TIP],
    ["a tip the branch moved off", { "runner-checks": checksFile() }, "d".repeat(40)],
  ]) {
    await withAsyncDir(
      { "work-outcome.json": JSON.stringify({ ...done, not_done: [] }), "lane.json": JSON.stringify({ branch: BRANCH }), ...files },
      async (dir) => {
        const { fetch, calls } = fakeFetch([
          ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
          branchTip(BRANCH, tip),
          ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
          ["GET", /\/compare\//, 200, { files: [{ filename: "README.md" }] }],
          ...HISTORY,
          ["POST", /\/issues\/77\/labels$/, 200, []],
          ["POST", /\/issues\/77\/comments$/, 201, {}],
        ]);
        assert.equal(await main({ env: env(dir), fetch }), 0, label);
        assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/pulls")), label);
        assert.ok(!calls.some((c) => c.path.endsWith("/issues/77/labels")), label);
        const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/issues/77/comments")).body.body;
        assert.ok(comment.startsWith("<!-- work-resolve-issue outcome=retry run=123 -->"), comment);
        assert.ok(comment.includes(BRANCH), comment);
      },
    );
  }
});

// run-checks checks only this run's own lane branch, so a lane.json naming
// another run's branch carries results run-checks did not write.
test("main on done ignores check results for another run's lane branch", async () => {
  const other = "work-resolve-issue/issue-77-99-1";
  await withAsyncDir(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: other }), "runner-checks": checksFile({ branch: other }) },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        branchTip(other),
        ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
        ["GET", /\/compare\//, 200, { files: [{ filename: "README.md" }] }],
        ...HISTORY,
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/pulls")));
      assert.ok(calls.find((c) => c.method === "POST" && c.path.endsWith("/issues/77/comments")).body.body.includes("check results are missing"));
    },
  );
});

test("main on done writes the runner's check results into the PR body", async () => {
  await withAsyncDir(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: BRANCH }), "runner-checks": checksFile() },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        branchTip(),
        ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
        ["GET", /\/compare\//, 200, { files: [{ filename: "README.md" }] }],
        ["GET", /\/pulls$/, 200, []],
        ["POST", /\/pulls$/, 201, { number: 90 }],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      const body = calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body.body;
      assert.ok(body.includes(`against ${CHECKED_TIP}:\n\n- scripts/check-changelog-fragments.sh --check: passed\n`), body);
    },
  );
});

// The merge lane merges a plain Refs PR as a closing one, so opening it puts no
// hold on the issue: work-unblock hands the issue to triage once it merges.
test("main on done with Refs opens the PR and writes nothing to the issue", async () => {
  await withDir(
    { "work-outcome.json": JSON.stringify({ ...done, remaining: ["Part B"] }), "lane.json": JSON.stringify({ branch: BRANCH }), "runner-checks": checksFile() },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        branchTip(),
        ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
        ["GET", /\/compare\//, 200, { files: [{ filename: "README.md" }] }],
        ["GET", /\/pulls$/, 200, []],
        ["POST", /\/pulls$/, 201, { number: 90 }],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      const writes = calls.filter((c) => c.method !== "GET" && c.path !== "/graphql").map((c) => `${c.method} ${c.path}`);
      // No denied-path list reads here, so the PR holds and carries the hold label.
      assert.deepEqual(writes, ["POST /repos/o/r/pulls", "POST /repos/o/r/issues/90/labels"]);
      assert.ok(calls.find((c) => c.path.endsWith("/pulls") && c.method === "POST").body.body.startsWith("Refs: #77\n"));
    },
  );
});

// A create that fails on the network may still have opened the PR: it is read
// back, and created once more only when the read finds none. A read that
// lost its socket is sent again.
test("main after a dropped PR create reads the PR back, and creates it again only when absent", async () => {
  const dropped = () => Object.assign(new TypeError("fetch failed"), { cause: { code: "UND_ERR_SOCKET" } });
  for (const landed of [true, false]) {
    await withDir(
      { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: BRANCH }), "runner-checks": checksFile() },
      async (dir) => {
        const { fetch: inner, calls } = fakeFetch([
          ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
          branchTip(),
          ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
          ["GET", /\/compare\//, 200, { files: [{ filename: "README.md" }] }],
          ["POST", /\/pulls$/, 201, { number: 90 }],
          ["POST", /\/issues\/90\/labels$/, 200, []],
        ]);
        let createSent = false;
        let compareDropped = false;
        const fetch = async (url, init = {}) => {
          const path = new URL(url).pathname;
          if (path.includes("/compare/") && !compareDropped) {
            compareDropped = true;
            throw dropped();
          }
          if (path.endsWith("/pulls") && init.method === "POST" && !createSent) {
            createSent = true;
            await inner(url, init);
            throw dropped();
          }
          if (path.endsWith("/pulls") && (init.method ?? "GET") === "GET") {
            await inner(url, init);
            const open = createSent && landed ? [{ number: 90, user: { login: "melodic-automation-lanes[bot]" } }] : [];
            return { ok: true, status: 200, json: async () => open, text: async () => JSON.stringify(open) };
          }
          return inner(url, init);
        };
        assert.equal(await main({ env: env(dir), fetch, sleep: async () => {} }), 0);
        const sends = (method, suffix) => calls.filter((c) => c.method === method && c.path.endsWith(suffix)).length;
        assert.equal(sends("POST", "/pulls"), landed ? 1 : 2, `landed=${landed}`);
        assert.equal(sends("GET", "/pulls"), 2, `landed=${landed}`);
        assert.equal(calls.filter((c) => c.path.includes("/compare/")).length, 1, "the dropped compare read was sent again");
      },
    );
  }
});

test("main on a rerun reuses the open PR from the branch", async () => {
  await withDir(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: BRANCH }), "runner-checks": checksFile() },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        branchTip(),
        ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
        ["GET", /\/compare\//, 200, { files: [{ filename: "README.md" }] }],
        ["GET", /\/pulls$/, 200, [{ number: 90, user: { login: "melodic-automation-lanes[bot]" } }]],
        ["POST", /\/issues\/90\/labels$/, 200, []],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/pulls")));
      assert.deepEqual(calls.filter((c) => c.path.endsWith("/issues/90/labels")).map((c) => c.body), [{ labels: ["human-merge-hold"] }]);
    },
  );
});

// Anyone can open a PR between two branches of a public repository, so an
// open PR from the lane branch that the lanes App did not open is not reused.
test("main does not adopt an open PR from the branch that someone else opened", async () => {
  await withDir(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: BRANCH }), "runner-checks": checksFile() },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        branchTip(),
        ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
        ["GET", /\/compare\//, 200, { files: [{ filename: "README.md" }] }],
        ["GET", /\/pulls$/, 200, [{ number: 91, user: { login: "stranger" } }]],
        ["POST", /\/pulls$/, 422, { message: "A pull request already exists" }],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 1);
      assert.ok(calls.some((c) => c.method === "POST" && c.path.endsWith("/pulls")));
      assert.ok(!calls.some((c) => c.path.endsWith("/issues/91/labels")));
    },
  );
});

// A resumed run can finish the inherited work without a commit of its own:
// its branch was deleted, so the PR opens from the branch it resumed, once
// run-checks has checked that whole branch and every commit on it ahead of
// the default branch is the lanes App's.
const RESUMED = "work-resolve-issue/issue-77-100-1";
const APP_COMMIT = {
  author: { login: "melodic-automation-lanes[bot]", type: "Bot" },
  committer: { login: "web-flow" },
  commit: { verification: { verified: true, reason: "valid" } },
};
const resumedCompare = (commits = [APP_COMMIT, APP_COMMIT]) => [
  "GET",
  /\/compare\//,
  200,
  { files: [{ filename: "README.md" }], commits, total_commits: commits.length },
];

test("main on a resumed done with no commit of its own and no check results retries, naming the resumed branch", async () => {
  await withAsyncDir(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: "", resume: RESUMED }) },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ...HISTORY,
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/labels\//, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      assert.ok(!calls.some((c) => c.path.endsWith("/pulls")));
      const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/issues/77/comments")).body.body;
      assert.ok(comment.startsWith("<!-- work-resolve-issue outcome=retry"), comment);
      assert.match(comment, /resumed .* no new commit/);
      assert.ok(comment.includes(RESUMED), comment);
      assert.ok(!calls.some((c) => c.path.endsWith("/labels") || c.path.includes("/labels/")));
    },
  );
});

test("main on a resumed done with no commit of its own opens the PR from the resumed branch its checks passed on", async () => {
  await withAsyncDir(
    {
      "work-outcome.json": JSON.stringify(done),
      "lane.json": JSON.stringify({ branch: "", resume: RESUMED }),
      "runner-checks": checksFile({ branch: RESUMED }),
    },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        branchTip(RESUMED),
        ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
        resumedCompare(),
        ["GET", /\/pulls$/, 200, []],
        ["POST", /\/pulls$/, 201, { number: 90, head: { sha: CHECKED_TIP } }],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      // The compare reads the tip the runner checked, not wherever the name points now.
      assert.ok(calls.some((c) => c.path === `/repos/o/r/compare/main...${CHECKED_TIP}`), JSON.stringify(calls.map((c) => c.path)));
      assert.ok(!calls.some((c) => c.method === "PATCH"));
      const pull = calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls"))?.body;
      assert.ok(pull, "no PR was opened");
      assert.equal(pull.head, RESUMED);
      assert.ok(pull.body.startsWith("Closes #77\n"), pull.body);
      assert.ok(pull.body.includes(`against ${CHECKED_TIP}:\n\n- ${FRAGMENTS}: passed\n`), pull.body);
      assert.match(pull.body, /resumed `work-resolve-issue\/issue-77-100-1` and made no commit of its own/);
      assert.ok(pull.body.includes(`the runner checked that whole branch at ${CHECKED_TIP}`), pull.body);
      assert.ok(!calls.some((c) => c.method === "POST" && c.path.startsWith("/repos/o/r/issues/77/")));
    },
  );
});

// The resumed branch comes from lane.json, which code the model started can
// rewrite, so the runner opens it only when its checks name it, the branch is
// still at the tip they checked, they passed, and every commit ahead of the
// default branch is the lanes App's.
test("main on a resumed done retries when its branch's checks fail, moved, or carry a commit not the App's", async () => {
  for (const [label, checks, tip, compare] of [
    ["a failing check", checksFile({ branch: RESUMED, results: [{ check: FRAGMENTS, exit: 1 }] }), CHECKED_TIP, resumedCompare()],
    ["no checks ran", checksFile({ branch: RESUMED, results: [] }), CHECKED_TIP, resumedCompare()],
    ["results for another branch", checksFile(), CHECKED_TIP, resumedCompare()],
    ["a tip the branch moved off", checksFile({ branch: RESUMED }), "d".repeat(40), resumedCompare()],
    ["a commit not the App's", checksFile({ branch: RESUMED }), CHECKED_TIP, resumedCompare([APP_COMMIT, { ...APP_COMMIT, author: { login: "stranger" } }])],
    ["a cut-short commit listing", checksFile({ branch: RESUMED }), CHECKED_TIP, ["GET", /\/compare\//, 200, { files: [], commits: [APP_COMMIT], total_commits: 300 }]],
  ]) {
    await withAsyncDir(
      { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: "", resume: RESUMED }), "runner-checks": checks },
      async (dir) => {
        const { fetch, calls } = fakeFetch([
          ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
          branchTip(RESUMED, tip),
          ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
          compare,
          ...HISTORY,
          ["POST", /\/issues\/77\/labels$/, 200, []],
          ["DELETE", /\/labels\//, 200, []],
          ["POST", /\/issues\/77\/comments$/, 201, {}],
        ]);
        assert.equal(await main({ env: env(dir), fetch }), 0, label);
        assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/pulls")), label);
        const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/issues/77/comments")).body.body;
        assert.ok(comment.startsWith("<!-- work-resolve-issue outcome=retry"), `${label}: ${comment}`);
        assert.ok(comment.includes(RESUMED), `${label}: ${comment}`);
      },
    );
  }
});

// The branch name can move between the tip check and the PR open, so a PR
// whose head is not the checked tip is closed and the issue handed back.
test("main closes a resumed branch's new PR whose head is not the tip the runner checked, and retries", async () => {
  await withAsyncDir(
    {
      "work-outcome.json": JSON.stringify(done),
      "lane.json": JSON.stringify({ branch: "", resume: RESUMED }),
      "runner-checks": checksFile({ branch: RESUMED }),
    },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        branchTip(RESUMED),
        ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
        resumedCompare(),
        ["GET", /\/pulls$/, 200, []],
        ["POST", /\/pulls$/, 201, { number: 90, head: { sha: "d".repeat(40) } }],
        ["PATCH", /\/pulls\/90$/, 200, {}],
        ...HISTORY,
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/labels\//, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      assert.deepEqual(calls.find((c) => c.method === "PATCH" && c.path.endsWith("/pulls/90"))?.body, { state: "closed" });
      assert.ok(!calls.some((c) => c.path.endsWith("/issues/77/labels")));
      const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/issues/77/comments")).body.body;
      assert.ok(comment.startsWith("<!-- work-resolve-issue outcome=retry"), comment);
      assert.match(comment, /`pr-head-moved`/);
      assert.ok(comment.includes(CHECKED_TIP), comment);
    },
  );
});

test("a resumed done with no new commit is retried unless the runner's checks passed on the resumed branch", () => {
  for (const checks of [null, NO_CHECKS, { tip: CHECKED_TIP, results: [{ check: FRAGMENTS, exit: 1 }] }]) {
    const plan = decideDone({ branch: "", resumed: RESUMED, checks });
    assert.equal(plan.action, "retry");
    assert.equal(plan.stop, "resumed-unchecked");
    assert.match(plan.comment, /resumed `work-resolve-issue\/issue-77-100-1` and reported done with no new commit/);
  }
  const plan = decideDone({ branch: "", resumed: RESUMED, checks: { tip: CHECKED_TIP, results: [{ check: FRAGMENTS, exit: 0 }] } });
  assert.equal(plan.action, "open-pr");
  assert.equal(plan.branch, RESUMED);
});

test("main on a resumed stop with no commit of its own names no branch", async () => {
  await withDir(
    {
      "work-outcome.json": JSON.stringify({ exit: "stopped", reason: "design-change: Blocked." }),
      "lane.json": JSON.stringify({ branch: "", resume: RESUMED }),
    },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/labels\//, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      assert.ok(!calls.some((c) => c.path.endsWith("/pulls")));
      const comment = calls.find((c) => c.path.endsWith("/issues/77/comments")).body.body;
      assert.ok(!comment.includes(RESUMED), comment);
      assert.equal(parseOutcomeMarker(comment).onResumed, true, comment);
    },
  );
});

test("main refuses a lane.json branch that is not this issue's lane branch", async () => {
  await withDir(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: "main" }) },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ...HISTORY,
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      assert.ok(!calls.some((c) => c.path.endsWith("/pulls")));
    },
  );
});

// The limited exit (FINAL-DESIGN C2): a run the usage limit stopped leaves one
// marker comment naming when the limit resets, keeps agent-ready and adds no
// label. With no reset in the record, the reset is the run's end plus five
// hours (the shortest plan limit window).
test("a limit-stopped run is limited: one marker comment, agent-ready kept, no label", () => {
  const plan = decide({
    outcome: { exit: "stopped", reason: "", title: "", summary: "", unread: true },
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: "",
    changedFiles: [],
    limit: { resets: Date.parse("2026-10-17T18:00:00Z") },
    now: Date.parse("2026-10-17T12:00:00Z"),
    runId: "555",
  });
  assert.equal(plan.action, "limited");
  assert.deepEqual(plan.addLabels, []);
  assert.deepEqual(plan.removeLabels, []);
  assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=limited resets=2026-10-17T18:00:00Z run=555 -->\n"));
});

test("a limit stop with no reset time restarts five hours after the run ended", () => {
  const plan = decide({
    outcome: { exit: "stopped", reason: "", title: "", summary: "", unread: true },
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: "",
    changedFiles: [],
    limit: { resets: null },
    now: Date.parse("2026-10-17T12:00:00Z"),
    runId: "555",
  });
  assert.equal(plan.resets, "2026-10-17T17:00:00Z");
});

// A stated reset is held between one hour and seven days after the stop, so a
// reset in the past cannot loop restarts and one far off cannot park the issue.
test("a limit stop's stated reset is held between one hour and seven days out", () => {
  for (const [resets, expected] of [
    ["2026-10-01T00:00:00Z", "2026-10-17T13:00:00Z"],
    ["2027-01-01T00:00:00Z", "2026-10-24T12:00:00Z"],
  ]) {
    const plan = decide({
      outcome: { exit: "stopped", reason: "", title: "", summary: "", unread: true },
      issueNumber: 77,
      issueLabels: ["agent-ready"],
      branch: "",
      changedFiles: [],
      limit: { resets: Date.parse(resets) },
      now: Date.parse("2026-10-17T12:00:00Z"),
      runId: "555",
    });
    assert.equal(plan.resets, expected, resets);
  }
});

// The lane record can be forged by any code the run executed, so it never
// overrides an outcome the skill wrote.
test("a stop the skill reported goes to a person even with a limit record", () => {
  const plan = decide({
    outcome: { exit: "stopped", reason: "design-change: The tests cannot run here.", title: "", summary: "" },
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: "",
    changedFiles: [],
    limit: { resets: null },
  });
  assert.notEqual(plan.action, "limited");
  assert.deepEqual(plan.addLabels, ["needs-human"]);
  assert.match(plan.comment, /The tests cannot run here\./);
});

test("done with no branch is still retried, not limited, even with a limit record", () => {
  const plan = decide({
    outcome: { exit: "done", reason: "", title: "", summary: "" },
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: "",
    changedFiles: [],
    limit: { resets: null },
  });
  assert.equal(plan.action, "retry");
  assert.equal(plan.stop, "done-no-commit");
});

test("an unreadable outcome file with a limit record reads as limited", () => {
  const plan = decide({
    outcome: readOutcome("/nonexistent/work-outcome.json"),
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: "",
    changedFiles: [],
    limit: { resets: null },
    now: Date.parse("2026-10-17T12:00:00Z"),
  });
  assert.equal(plan.action, "limited");
});

test("a pushback stays a pushback even on a limit-stopped run", () => {
  const plan = decide({
    outcome: { exit: "pushback", reason: "Unclear.", cause: "intent", title: "", summary: "" },
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: "",
    changedFiles: [],
    limit: { resets: null },
  });
  assert.deepEqual(plan.addLabels, ["needs-human"]);
  assert.deepEqual(plan.removeLabels, ["agent-ready"]);
});

test("the limited marker reads back with its reset and run", () => {
  assert.deepEqual(parseOutcomeMarker("<!-- work-resolve-issue outcome=limited resets=2026-10-17T18:00:00Z run=555 -->\ntext"), {
    outcome: "limited",
    resets: Date.parse("2026-10-17T18:00:00Z"),
    run: "555",
    onResumed: false,
  });
  assert.equal(parseOutcomeMarker("<!-- work-resolve-issue outcome=stopped -->").outcome, "stopped");
  assert.equal(parseOutcomeMarker("hello"), null);
  assert.equal(parseOutcomeMarker("<!-- work-resolve-issue outcome=turn-cap cap=75 run=555 branch=resumed -->").onResumed, true);
});

const LIMIT_NOW = Date.parse("2026-10-17T12:00:00Z");
const LIMITED_LANE = JSON.stringify({ branch: "", class: "rate-limit", resets: "2026-10-17T18:00:00Z" });

test("main on a limit stop comments the marker and touches no label", async () => {
  await withDir({ "lane.json": LIMITED_LANE }, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["GET", /\/issues\/77\/comments$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: env(dir), fetch, now: LIMIT_NOW }), 0);
    const posted = calls.filter((c) => c.method === "POST");
    assert.equal(posted.length, 1);
    assert.ok(posted[0].body.body.startsWith("<!-- work-resolve-issue outcome=limited resets=2026-10-17T18:00:00Z run=123 -->"));
    assert.ok(!calls.some((c) => c.path.endsWith("/labels") || c.method === "DELETE"));
  });
});

test("main takes the fallback reset and clamp from the resolved config's limits", async () => {
  const resolved = JSON.stringify({ limits: { "fallback-reset": 2, "reset-clamp-min": 1, "reset-clamp-max": 3 } });
  for (const [lane, expected] of [
    [JSON.stringify({ branch: "", class: "rate-limit" }), "2026-10-17T14:00:00Z"],
    [LIMITED_LANE, "2026-10-17T15:00:00Z"],
  ]) {
    await withAsyncDir({ "lane.json": lane, "resolved.json": resolved }, async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ["GET", /\/issues\/77\/comments$/, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: { ...env(dir), RESOLVED_CONFIG: join(dir, "resolved.json") }, fetch, now: LIMIT_NOW }), 0);
      const posted = calls.filter((c) => c.method === "POST");
      assert.ok(posted[0].body.body.startsWith(`<!-- work-resolve-issue outcome=limited resets=${expected} run=123 -->`), posted[0].body.body);
    });
  }
});

test("main posts the limited marker once per run", async () => {
  await withDir({ "lane.json": LIMITED_LANE }, async (dir) => {
    const marker = "<!-- work-resolve-issue outcome=limited resets=2026-10-17T18:00:00Z run=123 -->";
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["GET", /\/issues\/77\/comments$/, 200, [{ user: { login: "melodic-automation-lanes[bot]" }, body: marker }]],
    ]);
    assert.equal(await main({ env: env(dir), fetch, now: LIMIT_NOW }), 0);
    assert.ok(!calls.some((c) => c.method === "POST"));
  });
});

test("a late rerun finds its marker past the first page of the whole history", async () => {
  await withDir({ "lane.json": LIMITED_LANE }, async (dir) => {
    const marker = "<!-- work-resolve-issue outcome=limited resets=2026-10-17T18:00:00Z run=123 -->";
    const filler = Array.from({ length: 100 }, () => ({ user: { login: "someone" }, body: "hi" }));
    const calls = [];
    const fetch = async (url, init = {}) => {
      const method = init.method ?? "GET";
      calls.push({ method, url });
      const { pathname, searchParams } = new URL(url);
      const ok = (body) => ({ ok: true, status: 200, json: async () => body });
      if (method !== "GET") {
        return { ok: true, status: 201, json: async () => ({}) };
      }
      if (pathname.endsWith("/comments")) {
        return ok(searchParams.get("page") === "1" ? filler : [{ user: { login: "melodic-automation-lanes[bot]" }, body: marker }]);
      }
      return ok(ISSUE[2]);
    };
    // Two days after the stop: a since-bounded read would miss the marker.
    assert.equal(await main({ env: env(dir), fetch, now: LIMIT_NOW + 2 * 86_400_000 }), 0);
    assert.ok(!calls.some((call) => call.method === "POST"));
    assert.ok(!calls.some((call) => call.url.includes("since=")));
  });
});

test("main does not take another account's copy of the marker as its own", async () => {
  await withDir({ "lane.json": LIMITED_LANE }, async (dir) => {
    const marker = "<!-- work-resolve-issue outcome=limited resets=2026-10-17T18:00:00Z run=123 -->";
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["GET", /\/issues\/77\/comments$/, 200, [{ user: { login: "stranger" }, body: marker }]],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: env(dir), fetch, now: LIMIT_NOW }), 0);
    assert.equal(calls.filter((c) => c.method === "POST").length, 1);
  });
});

// The turn cap (plan: turn-cap resume, PR 2): a run the classifier recorded as
// class max-turns, with no outcome of its own, names the cause. The marker is
// `outcome=turn-cap cap=<n> run=<id>` and the comment says "turn cap <n>
// reached" and names the branch. It restarts while restarts since a person
// last added agent-ready are under limits.turn-cap-restarts, else hands back.
const capped = (overrides = {}) =>
  decide({
    outcome: readOutcome("/nonexistent/work-outcome.json"),
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: BRANCH,
    changedFiles: [],
    turnCap: { cap: 75 },
    limits: { "turn-cap-restarts": 1 },
    runId: "555",
    checks: NO_CHECKS,
    ...overrides,
  });

test("a run at its turn cap with a restart left keeps agent-ready and names the cap and branch", () => {
  const plan = capped();
  assert.equal(plan.action, "turn-cap");
  assert.deepEqual(plan.addLabels, []);
  assert.deepEqual(plan.removeLabels, []);
  assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=turn-cap cap=75 run=555 -->\n"), plan.comment);
  assert.match(plan.comment, /turn cap 75 reached/);
  assert.ok(plan.comment.includes(BRANCH));
});

// A spent cap is a visible stop, not a person: agent-ready comes off, no label.
test("a run at its turn cap with no restart left fails, naming the cap, never needs-human", () => {
  for (const overrides of [{ turnCapRestarts: 1 }, { limits: { "turn-cap-restarts": 0 } }]) {
    const plan = capped(overrides);
    assert.equal(plan.action, "fail");
    assert.deepEqual(plan.addLabels, []);
    assert.deepEqual(plan.removeLabels, ["agent-ready"]);
    assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=failed run=555 -->\n"), plan.comment);
    assert.match(plan.comment, /`turn-cap-spent`/);
    assert.match(plan.comment, /turn cap 75 reached/);
    assert.ok(plan.comment.includes(BRANCH), plan.comment);
  }
});

test("a run at its turn cap that committed nothing names no branch", () => {
  const plan = capped({ branch: "" });
  assert.ok(!plan.comment.includes("work-resolve-issue/issue-"), plan.comment);
  assert.match(plan.comment, /committed nothing/);
});

// Code the run executed can forge lane.json, so a class beside an outcome the
// skill wrote never overrides it.
test("a forged turn-cap class beside a readable outcome keeps that outcome", () => {
  assert.equal(capped({ outcome: done }).action, "open-pr");
  const stoppedPlan = capped({ outcome: { exit: "stopped", reason: "design-change: The tests cannot run here.", title: "", summary: "" } });
  assert.ok(stoppedPlan.comment.startsWith(ESC + "<!-- work-resolve-issue outcome=stopped run=555 -->"), stoppedPlan.comment);
});

test("the turn-cap marker reads back with its run", () => {
  assert.deepEqual(parseOutcomeMarker("<!-- work-resolve-issue outcome=turn-cap cap=150 run=555 -->\ntext"), {
    outcome: "turn-cap",
    resets: null,
    run: "555",
    onResumed: false,
  });
});

// Run 40208736808 (#6377): write-issue refused with "the issue title or body
// changed after agent-ready was added; no issue file written", so no model
// ran, and the hand-back said only that no outcome file was read.
test("lane.json's issue-file classes name why the run never started; any other class is none", () => {
  for (const [lane, expected] of [
    [{ branch: "", class: "issue-edited" }, /the issue's title or body changed after `agent-ready` was added/],
    [{ branch: "", class: "issue-file" }, /could not write the issue file/],
    [{ branch: "", class: "max-turns" }, null],
    [{ branch: "", class: "" }, null],
  ]) {
    const reason = withDir({ "lane.json": JSON.stringify(lane) }, (dir) => readIssueStop(dir));
    if (expected === null) {
      assert.equal(reason, null, JSON.stringify(lane));
    } else {
      assert.match(reason, expected, JSON.stringify(lane));
    }
  }
  assert.equal(withDir({}, (dir) => readIssueStop(dir)), null, "no lane.json");
});

test("a run whose issue changed after agent-ready hands back naming that, not a missing outcome file", () => {
  const issueStop = withDir({ "lane.json": JSON.stringify({ branch: "", class: "issue-edited" }) }, (dir) => readIssueStop(dir));
  const plan = decide({
    outcome: readOutcome("/nonexistent/work-outcome.json"),
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: "",
    changedFiles: [],
    issueStop,
  });
  assert.equal(plan.action, "hand-back");
  assert.deepEqual(plan.addLabels, ["needs-human"]);
  assert.match(plan.comment, /the issue's title or body changed after `agent-ready` was added/);
  assert.doesNotMatch(plan.comment, /no readable outcome file/);
});

test("an issue-file record never replaces an outcome the run reported", () => {
  const plan = decide({
    outcome: { exit: "stopped", reason: "The tests cannot run here.", title: "", summary: "" },
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: "",
    changedFiles: [],
    issueStop: "The run did not start.",
  });
  assert.match(plan.comment, /The tests cannot run here\./);
  assert.doesNotMatch(plan.comment, /The run did not start\./);
});

test("lane.json's max-turns class is the turn-cap record; any other class is none", () => {
  for (const [lane, expected] of [
    [{ branch: "", class: "max-turns", "max-turns": "75" }, { cap: 75 }],
    [{ branch: "", class: "max-turns", "max-turns": "75; rm" }, { cap: null }],
    [{ branch: "", class: "rate-limit", "max-turns": "75" }, null],
    [{ branch: "", class: "timeout", "max-turns": "75" }, { cap: null, timeout: true }],
    [{ branch: "", class: "other", "max-turns": "75" }, null],
  ]) {
    withDir({ "lane.json": JSON.stringify(lane) }, (dir) => assert.deepEqual(readTurnCap(dir), expected, JSON.stringify(lane)));
  }
});

// A leg run-claude-cli stopped at its timeout (class timeout) ran out of time
// like a turn cap: with a restart left it keeps agent-ready, so work-unblock
// restarts it and the next run resumes its branch (turn-cap is RESUMABLE);
// it never hands back as stopped while a restart is left.
test("a leg timeout with no outcome of its own restarts from its branch like a turn cap, naming the time", () => {
  const timedOut = withDir({ "lane.json": JSON.stringify({ branch: "", class: "timeout", "max-turns": "75" }) }, (dir) => readTurnCap(dir));
  const plan = capped({ turnCap: timedOut });
  assert.equal(plan.action, "turn-cap");
  assert.deepEqual(plan.addLabels, []);
  assert.deepEqual(plan.removeLabels, []);
  assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=turn-cap run=555 -->\n"), plan.comment);
  assert.match(plan.comment, /its time ran out \(the launcher's leg timeout\)/);
  assert.ok(plan.comment.includes(BRANCH));
  assert.equal(parseOutcomeMarker(plan.comment).outcome, "turn-cap");
  assert.ok(RESUMABLE.has(parseOutcomeMarker(plan.comment).outcome), "the next run resumes the branch");
  const spent = capped({ turnCap: timedOut, turnCapRestarts: 1 });
  assert.equal(spent.action, "fail", "with its restarts used it stops, visibly, with no label");
});

test("restarts count the App's turn-cap markers since a person last added agent-ready, not this run's", () => {
  const marker = (run, at, login = "melodic-automation-lanes[bot]") => ({
    user: { login },
    body: `<!-- work-resolve-issue outcome=turn-cap cap=75 run=${run} -->`,
    created_at: at,
  });
  const comments = [
    marker("1", "2026-10-17T01:00:00Z"),
    marker("2", "2026-10-17T03:00:00Z"),
    marker("3", "2026-10-17T04:00:00Z", "stranger"),
    marker("555", "2026-10-17T05:00:00Z"),
  ];
  const events = [
    { event: "labeled", label: { name: "agent-ready" }, actor: { login: "kyle-sexton", id: 153232337 }, created_at: "2026-10-17T02:00:00Z" },
    { event: "labeled", label: { name: "agent-ready" }, actor: { login: "melodic-automation-lanes[bot]", id: 1 }, created_at: "2026-10-17T03:30:00Z" },
    // An unlisted triager's re-add resets nothing.
    { event: "labeled", label: { name: "agent-ready" }, actor: { login: "triager", id: 42 }, created_at: "2026-10-17T03:45:00Z" },
  ];
  const humans = new Set([153232337]);
  assert.equal(countTurnCapRestarts({ comments, events, bot: "melodic-automation-lanes[bot]", humans, runId: "555" }), 1);
});

const CAPPED_LANE = JSON.stringify({ branch: BRANCH, class: "max-turns", resets: "", "max-turns": "75" });

test("main at the turn cap with restarts left comments the marker once and touches no label", async () => {
  const resolved = JSON.stringify({ limits: { "turn-cap-restarts": 1 } });
  await withAsyncDir({ "lane.json": CAPPED_LANE, "resolved.json": resolved }, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["GET", /\/issues\/77\/comments$/, 200, []],
      ["GET", /\/issues\/77\/events$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), RESOLVED_CONFIG: join(dir, "resolved.json") }, fetch }), 0);
    const posted = calls.filter((c) => c.method !== "GET");
    assert.equal(posted.length, 1);
    assert.ok(posted[0].body.body.startsWith("<!-- work-resolve-issue outcome=turn-cap cap=75 run=123 -->"), posted[0].body.body);
  });
});

test("main on a rerun after its turn-cap marker posts nothing again", async () => {
  const resolved = JSON.stringify({ limits: { "turn-cap-restarts": 1 } });
  await withAsyncDir({ "lane.json": CAPPED_LANE, "resolved.json": resolved }, async (dir) => {
    const own = { user: { login: "melodic-automation-lanes[bot]" }, body: "<!-- work-resolve-issue outcome=turn-cap cap=75 run=123 -->", created_at: "2026-10-17T05:00:00Z" };
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["GET", /\/issues\/77\/comments$/, 200, [own]],
      ["GET", /\/issues\/77\/events$/, 200, []],
    ]);
    assert.equal(await main({ env: { ...env(dir), RESOLVED_CONFIG: join(dir, "resolved.json") }, fetch }), 0);
    assert.deepEqual(calls.filter((c) => c.method !== "GET"), []);
  });
});

// A turn cap with no restart left fails, an earlier security intake marker included.
test("main fails a spent turn cap after an earlier security intake marker", async () => {
  const secure = { user: { login: "melodic-automation-lanes[bot]" }, body: "<!-- work-resolve-issue outcome=intake security run=99 -->\nWhy.", created_at: "2026-10-29T10:00:00Z" };
  await withAsyncDir({ "lane.json": CAPPED_LANE }, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["GET", /\/issues\/77\/comments$/, 200, [secure]],
      ["GET", /\/issues\/77\/events$/, 200, []],
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: env(dir), fetch }), 0);
    assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/labels")));
    const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
    assert.equal(parseOutcomeMarker(comment).outcome, "failed");
  });
});

test("main at the turn cap with no restarts configured removes agent-ready and adds no label", async () => {
  await withAsyncDir({ "lane.json": CAPPED_LANE }, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["GET", /\/issues\/77\/comments$/, 200, []],
      ["GET", /\/issues\/77\/events$/, 200, []],
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: env(dir), fetch }), 0);
    assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/labels")));
    assert.ok(calls.some((c) => c.method === "DELETE" && c.path.endsWith("/labels/agent-ready")));
    const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
    assert.equal(parseOutcomeMarker(comment).outcome, "failed");
    assert.match(comment, /turn cap 75 reached/);
    assert.ok(comment.includes(BRANCH));
  });
});

// Idempotency per issue, before the resolve-issue mint. Expected values come
// from the owner's decisions: stop on an open lanes-App PR from a lane branch,
// or an open closing PR by the lanes App or a listed human (never an
// outsider's); reuse the first lane branch, newest first, ahead of main with
// no lanes-App PR in any state and no outcome marker for its run; else run.
const BOT = "melodic-automation-lanes[bot]";
const OWNER_ID = 153232337;
const HUMANS = new Set([OWNER_ID]);
const lane = (run, attempt = 1) => `work-resolve-issue/issue-77-${run}-${attempt}`;
// A lane tip as GET /commits/{sha} answered for a real lane branch
// (work-resolve-issue/issue-5911-39058616222-1): authored by the lanes App
// bot, committed by web-flow, verified with reason "valid".
const LANE_TIP = {
  author: { login: BOT, type: "Bot" },
  committer: { login: "web-flow" },
  commit: { committer: { date: "2026-10-16T10:00:00Z" }, verification: { verified: true, reason: "valid" } },
};
const branchFact = (name, { aheadBy = 2, behindBy = 0, tip = LANE_TIP, tipAt = Date.parse("2026-10-16T10:00:00Z"), pulls = [], sha = "a".repeat(40), commits = [LANE_TIP, LANE_TIP] } = {}) => ({
  sha,
  commits,
  name,
  aheadBy,
  behindBy,
  tip,
  tipAt,
  pulls,
});
const pullBy = (login, state = "open") => ({ state, user: { login } });
const closer = (typename, login, databaseId, repo = "o/r", state = "OPEN") => ({
  number: 501,
  state,
  author: { __typename: typename, login, ...(databaseId ? { databaseId } : {}) },
  repository: { nameWithOwner: repo },
});
const prior = (facts) => findPrior({ issueNumber: 77, repo: "o/r", bot: BOT, humans: HUMANS, branches: [], closing: [], markers: [], ...facts });

test("an open lanes-App PR from a lane branch stops the run", () => {
  assert.equal(prior({ branches: [branchFact(lane(400), { pulls: [pullBy(BOT)] })] }).action, "stop");
});

test("an open closing PR by a listed human or the lanes App stops the run", () => {
  for (const node of [closer("User", "kyle-sexton", OWNER_ID), closer("Bot", "melodic-automation-lanes"), closer("Bot", BOT)]) {
    assert.equal(prior({ closing: [node] }).action, "stop", JSON.stringify(node.author));
  }
});

test("an outsider's closing PR, or a listed human's in another repository, does not stop the run", () => {
  for (const node of [
    closer("User", "stranger", 42),
    closer("User", "melodic-automation-lanes[bot]", 42),
    closer("Bot", "other-app"),
    closer("User", "kyle-sexton", OWNER_ID, "fork/r"),
  ]) {
    assert.equal(prior({ closing: [node] }).action, "run", JSON.stringify(node));
  }
});

test("an outsider's open PR from a lane branch neither stops the run nor makes the branch stale", () => {
  assert.deepEqual(prior({ branches: [branchFact(lane(400), { pulls: [pullBy("stranger")] })] }), { action: "reuse", branch: lane(400) });
});

test("the newest unreported lane branch ahead of main is reused", () => {
  const branches = [branchFact(lane(400, 1)), branchFact(lane(400, 2)), branchFact(lane(399, 3))];
  assert.deepEqual(prior({ branches }), { action: "reuse", branch: lane(400, 2) });
});

test("a lane branch with a closed lanes-App PR, or no commits ahead, is not reused", () => {
  for (const branch of [branchFact(lane(400), { pulls: [pullBy(BOT, "closed")] }), branchFact(lane(400), { aheadBy: 0 })]) {
    assert.deepEqual(prior({ branches: [branch] }), { action: "run" });
  }
});

// Anyone with push access can create a branch with a lane name, so only a tip
// GitHub verified and the lanes App wrote counts as the lane's work.
test("a lane branch whose tip is unverified or not the lanes App's is passed over, not reused", () => {
  for (const [label, tip] of [
    ["unverified", { ...LANE_TIP, commit: { ...LANE_TIP.commit, verification: { verified: false, reason: "unsigned" } } }],
    ["another author", { ...LANE_TIP, author: { login: "stranger", type: "User" } }],
    ["no verification", { ...LANE_TIP, commit: { committer: LANE_TIP.commit.committer } }],
    ["no tip", null],
  ]) {
    assert.deepEqual(prior({ branches: [branchFact(lane(400), { tip })] }), { action: "run" }, label);
    const older = branchFact(lane(399));
    assert.deepEqual(prior({ branches: [branchFact(lane(400), { tip }), older] }), { action: "reuse", branch: lane(399) }, label);
  }
});

// A writer can sign their own commit with the App's noreply address as author,
// and GitHub then shows it verified with the bot as author; only the App's
// API commits carry web-flow as committer too.
test("a verified tip is the lane's work only with the bot as author and web-flow as committer", () => {
  for (const [label, tip] of [
    ["author bot, committer a person", { ...LANE_TIP, committer: { login: "stranger" } }],
    ["author bot, committer the bot", { ...LANE_TIP, committer: { login: BOT } }],
    ["author bot, no committer", { ...LANE_TIP, committer: null }],
    ["committer web-flow, author a person", { ...LANE_TIP, author: { login: "stranger", type: "User" } }],
    ["committer the bot, author a person", { ...LANE_TIP, author: { login: "stranger", type: "User" }, committer: { login: BOT } }],
  ]) {
    assert.deepEqual(prior({ branches: [branchFact(lane(400), { tip })] }), { action: "run" }, label);
  }
  assert.deepEqual(prior({ branches: [branchFact(lane(400))] }), { action: "reuse", branch: lane(400) });
});

// The sha goes into a request path, so anything but a full commit id fails
// the step rather than being passed over: matching-refs only ever answers
// full ids, so another shape means the answer itself is wrong.
test("--find-prior fails on a lane ref whose sha is not a full commit id", async () => {
  for (const sha of ["abc", "../../x", "A".repeat(40), undefined]) {
    await failsClosed(String(sha), { refs: [{ ref: `refs/heads/${lane(400)}`, object: { sha } }] });
  }
});

test("--find-prior runs the model when the only lane branch's tip is not the lanes App's", async () => {
  const commitAnswer = { ...LANE_TIP, author: { login: "stranger", type: "User" } };
  const { code, output } = await runPrior({ refs: [refOf(lane(400))], commitAnswer });
  assert.equal(code, 0);
  assert.equal(output, "proceed=true\nskip-reason=\nreuse-branch=\n");
});

// A reported run's branch is never reused: the model runs again, resuming the
// branch after a turn-cap, stop or limit and starting fresh after a pushback.
test("a stopped, pushback or limited marker for the branch's run keeps it from reuse", () => {
  for (const [outcome, action] of [["stopped", "resume"], ["pushback", "run"], ["limited", "resume"]]) {
    const markers = [{ outcome, run: "400", resets: null, at: Date.parse("2026-10-16T11:00:00Z") }];
    assert.equal(prior({ branches: [branchFact(lane(400))], markers }).action, action, outcome);
  }
});

test("a marker for another run leaves the branch reusable", () => {
  const markers = [{ outcome: "stopped", run: "399", resets: null, at: Date.parse("2026-10-16T11:00:00Z") }];
  assert.deepEqual(prior({ branches: [branchFact(lane(400))], markers }), { action: "reuse", branch: lane(400) });
});

test("a marker naming no run covers branches whose tip is older than it, not newer ones", () => {
  const markers = [{ outcome: "stopped", run: "", resets: null, at: Date.parse("2026-10-16T11:00:00Z") }];
  const older = branchFact(lane(399), { tipAt: Date.parse("2026-10-16T10:00:00Z") });
  const newer = branchFact(lane(400), { tipAt: Date.parse("2026-10-16T12:00:00Z") });
  assert.deepEqual(prior({ branches: [older], markers }), { action: "run" });
  assert.deepEqual(prior({ branches: [older, newer], markers }), { action: "reuse", branch: lane(400) });
});

// Resume (plan: turn-cap resume, PR 3): when the newest lanes-App outcome
// marker is turn-cap, stopped or limited and names a run whose lane branch
// passes the App-tip check and is ahead of main, the next run starts its lane
// branch at that branch's tip instead of main's.
const SHA_400 = "4".repeat(40);
const marked = (outcome, run, at = "2026-10-16T11:00:00Z") => ({ outcome, run, resets: null, at: Date.parse(at) });

test("a turn-cap, stopped, limited or funding marker for a run with an App-tipped branch resumes from it", () => {
  for (const outcome of ["turn-cap", "stopped", "limited", "funding"]) {
    const branches = [branchFact(lane(400), { sha: SHA_400 })];
    assert.deepEqual(prior({ branches, markers: [marked(outcome, "400")] }), {
      action: "resume",
      branch: lane(400),
      tip: SHA_400,
      cause: outcome,
    });
  }
});

test("a pushback marker, or a newer pushback for another run, resumes nothing", () => {
  const branches = [branchFact(lane(400), { sha: SHA_400 })];
  assert.deepEqual(prior({ branches, markers: [marked("pushback", "400")] }), { action: "run" });
  const newer = [marked("turn-cap", "400"), marked("pushback", "401", "2026-10-16T12:00:00Z")];
  assert.deepEqual(prior({ branches, markers: newer }), { action: "run" });
});

// A dimension skip ran nothing and touched no branch, so it leaves the
// earlier run's resume as it was.
test("a newer dimension-skip marker keeps an earlier run's resume", () => {
  const branches = [branchFact(lane(400), { sha: SHA_400 })];
  for (const reason of ["split-required", "research-first", "probe-first", "parked"]) {
    const markers = [marked("turn-cap", "400"), marked(reason, "401", "2026-10-16T12:00:00Z")];
    assert.deepEqual(prior({ branches, markers }), { action: "resume", branch: lane(400), tip: SHA_400, cause: "turn-cap" }, reason);
  }
});

// A not-assessed marker an earlier run left ran nothing either, so it also
// keeps the earlier run's resume.
test("a newer retired not-assessed marker keeps an earlier run's resume", () => {
  const branches = [branchFact(lane(400), { sha: SHA_400 })];
  const markers = [marked("turn-cap", "400"), marked("not-assessed", "401", "2026-10-16T12:00:00Z")];
  assert.deepEqual(prior({ branches, markers }), { action: "resume", branch: lane(400), tip: SHA_400, cause: "turn-cap" });
});

// A resumed run that committed nothing keeps no branch of its own, so the
// work is still on the run before it.
test("a newer turn-cap marker for a resumed run that kept no branch resumes the run before it", () => {
  const branches = [branchFact(lane(400), { sha: SHA_400 })];
  const markers = [marked("turn-cap", "400"), { ...marked("turn-cap", "401", "2026-10-16T12:00:00Z"), onResumed: true }];
  assert.equal(prior({ branches, markers }).branch, lane(400));
});

// Run 401 resumed 400 and committed, so its branch held 400's commits too; a
// person deleted it to start over. The older run's branch must not be resumed.
test("a resumable marker whose run's branch was deleted starts fresh, not from an older run's branch", () => {
  const branches = [branchFact(lane(400), { sha: SHA_400 })];
  for (const outcome of ["turn-cap", "limited", "stopped", "funding"]) {
    const markers = [marked("turn-cap", "400"), marked(outcome, "401", "2026-10-16T12:00:00Z")];
    assert.deepEqual(prior({ branches, markers }), { action: "run" }, outcome);
  }
});

test("a pushback for a resumed run that kept no branch still ends the chain", () => {
  const branches = [branchFact(lane(400), { sha: SHA_400 })];
  const markers = [marked("turn-cap", "400"), { ...marked("pushback", "401", "2026-10-16T12:00:00Z"), onResumed: true }];
  assert.deepEqual(prior({ branches, markers }), { action: "run" });
});

test("a marked run's branch that fails the App-tip check, has no commits or has a lanes-App PR resumes nothing", () => {
  for (const [label, fact] of [
    ["unverified", { tip: { ...LANE_TIP, commit: { ...LANE_TIP.commit, verification: { verified: false } } } }],
    ["another author", { tip: { ...LANE_TIP, author: { login: "stranger" } } }],
    ["no commits ahead", { aheadBy: 0 }],
    ["a closed lanes-App PR", { pulls: [pullBy(BOT, "closed")] }],
  ]) {
    const branches = [branchFact(lane(400), { sha: SHA_400, ...fact })];
    assert.deepEqual(prior({ branches, markers: [marked("turn-cap", "400")] }), { action: "run" }, label);
  }
});

// Someone with push access can put a commit under an App tip; a resume would
// carry it into the next PR, so every commit ahead must be the App's.
test("a marked run's branch with any commit not the lanes App's, or a cut-short listing, resumes nothing", () => {
  for (const [label, commits] of [
    ["a person's commit under the App tip", [{ ...LANE_TIP, author: { login: "stranger" } }, LANE_TIP]],
    ["an unverified commit", [{ ...LANE_TIP, commit: { verification: { verified: false } } }, LANE_TIP]],
    ["no commit list", null],
  ]) {
    const branches = [branchFact(lane(400), { sha: SHA_400, commits })];
    assert.deepEqual(prior({ branches, markers: [marked("turn-cap", "400")] }), { action: "run" }, label);
  }
});

// A resumed branch carries its base into the runner's whole-branch checks, so
// one behind main starts fresh from main under a new branch, and the old
// branch is left for a person to delete.
test("a marked run's branch behind main starts fresh instead of resuming", () => {
  for (const behindBy of [1, 865]) {
    const branches = [branchFact(lane(400), { sha: SHA_400, behindBy })];
    assert.deepEqual(
      prior({ branches, markers: [marked("stopped", "400")] }),
      { action: "run", stale: { branch: lane(400), tip: SHA_400, behindBy } },
      String(behindBy),
    );
  }
});

// The issue-fields job re-derives a resume claimed before the model ran;
// main moving during the run must not void it.
test("with keepBehind a marked run's branch behind main still resumes at its tip", () => {
  for (const behindBy of [0, 1, 865]) {
    const branches = [branchFact(lane(400), { sha: SHA_400, behindBy })];
    assert.deepEqual(
      prior({ branches, markers: [marked("stopped", "400")], keepBehind: true }),
      { action: "resume", branch: lane(400), tip: SHA_400, cause: "stopped" },
      String(behindBy),
    );
  }
});

test("keepBehind does not resume a branch that fails the other checks", () => {
  const branches = [branchFact(lane(400), { sha: SHA_400, behindBy: 3, pulls: [pullBy(BOT)] })];
  assert.equal(prior({ branches, markers: [marked("stopped", "400")], keepBehind: true }).action, "stop");
  const notApp = [branchFact(lane(400), { sha: SHA_400, behindBy: 3, commits: [LANE_TIP, { ...LANE_TIP, author: { login: "stranger" } }] })];
  assert.deepEqual(prior({ branches: notApp, markers: [marked("stopped", "400")], keepBehind: true }), { action: "run" });
});

test("a lanes-App PR open from a lane branch behind main still stops the run", () => {
  const branches = [branchFact(lane(400), { sha: SHA_400, behindBy: 865, pulls: [pullBy(BOT)] })];
  assert.equal(prior({ branches, markers: [marked("stopped", "400")] }).action, "stop");
});

// The fresh run that replaced a stale resume reports under its own run, so
// the next admission never falls back to the stale branch.
test("after a fresh run replaced a stale resume, the stale branch is not resumed again", () => {
  const branches = [branchFact(lane(400), { sha: SHA_400, behindBy: 865 })];
  for (const outcome of ["stopped", "turn-cap", "pushback"]) {
    const markers = [marked("stopped", "400"), marked(outcome, "401", "2026-10-23T16:00:00Z")];
    assert.deepEqual(prior({ branches, markers }), { action: "run" }, outcome);
  }
});

test("of a marked run's attempts, the newest is resumed", () => {
  const branches = [branchFact(lane(400, 1), { sha: "1".repeat(40) }), branchFact(lane(400, 2), { sha: "2".repeat(40) })];
  assert.equal(prior({ branches, markers: [marked("turn-cap", "400")] }).tip, "2".repeat(40));
});

test("an unreported branch is still reused before a marked one is resumed", () => {
  const branches = [branchFact(lane(401)), branchFact(lane(400), { sha: SHA_400 })];
  assert.deepEqual(prior({ branches, markers: [marked("turn-cap", "400")] }), { action: "reuse", branch: lane(401) });
});

test("--find-prior names the resumed branch, its tip and the cause, and still runs the model", async () => {
  const comments = [{ user: { login: BOT }, body: "<!-- work-resolve-issue outcome=turn-cap cap=75 run=400 -->", created_at: "2026-10-16T11:00:00Z" }];
  const comparison = { ahead_by: 1, behind_by: 0, total_commits: 1, commits: [LANE_TIP] };
  const { code, output } = await runPrior({ comments, refs: [refOf(lane(400))], comparison });
  assert.equal(code, 0);
  assert.equal(output, `proceed=true\nskip-reason=\nreuse-branch=\nresume-branch=${lane(400)}\nresume-tip=${"a".repeat(40)}\nresume-cause=turn-cap\n`);
});

test("--find-prior runs the model fresh, with no resume outputs, when the marked run's branch is behind main, naming that branch and its tip", async () => {
  const comments = [{ user: { login: BOT }, body: "<!-- work-resolve-issue outcome=stopped run=400 -->", created_at: "2026-10-16T11:00:00Z" }];
  const comparison = { ahead_by: 1, behind_by: 865, total_commits: 1, commits: [LANE_TIP] };
  const { code, calls, output } = await runPrior({ comments, refs: [refOf(lane(400))], comparison });
  assert.equal(code, 0);
  assert.equal(output, `proceed=true\nskip-reason=\nreuse-branch=\nstale-branch=${lane(400)}\nstale-tip=${"a".repeat(40)}\nstale-noted=false\n`);
  // Only the reads the resume decision already made: one compare per lane branch.
  assert.equal(calls.filter((c) => c.path.includes("/compare/")).length, 1);
  assert.deepEqual(writesToGitHub(calls), []);
});

// report-outcome names a stale branch once: a lanes App comment opening with
// its marker, from any earlier run, makes stale-noted true.
test("--find-prior marks a stale branch noted only when a lanes App comment opens with that branch's marker", async () => {
  const stopped = { user: { login: BOT }, body: "<!-- work-resolve-issue outcome=stopped run=400 -->", created_at: "2026-10-16T11:00:00Z" };
  const comparison = { ahead_by: 1, behind_by: 865, total_commits: 1, commits: [LANE_TIP] };
  const noted = async (comment) =>
    (await runPrior({ comments: [stopped, comment], refs: [refOf(lane(400))], comparison })).output.match(/^stale-noted=(.*)$/m)?.[1];
  assert.equal(await noted({ user: { login: BOT }, body: `<!-- work-resolve-issue stale-branch=${lane(400)} -->\nNamed.`, created_at: "2026-10-16T12:00:00Z" }), "true");
  assert.equal(await noted({ user: { login: BOT }, body: `<!-- work-resolve-issue stale-branch=${lane(401)} -->\nAnother branch.`, created_at: "2026-10-16T12:00:00Z" }), "false");
  assert.equal(await noted({ user: { login: "stranger" }, body: `<!-- work-resolve-issue stale-branch=${lane(400)} -->`, created_at: "2026-10-16T12:00:00Z" }), "false");
  assert.equal(await noted({ user: { login: BOT }, body: `Quoted: <!-- work-resolve-issue stale-branch=${lane(400)} -->`, created_at: "2026-10-16T12:00:00Z" }), "false");
});

test("--find-prior names no stale branch when a commit on the behind branch is not the lanes App's", async () => {
  const comments = [{ user: { login: BOT }, body: "<!-- work-resolve-issue outcome=stopped run=400 -->", created_at: "2026-10-16T11:00:00Z" }];
  const comparison = { ahead_by: 2, behind_by: 865, total_commits: 2, commits: [LANE_TIP, { ...LANE_TIP, author: { login: "stranger" } }] };
  const { code, output } = await runPrior({ comments, refs: [refOf(lane(400))], comparison });
  assert.equal(code, 0);
  assert.equal(output, "proceed=true\nskip-reason=\nreuse-branch=\n");
});

test("--find-prior with FIND_PRIOR_KEEP_BEHIND=true names a marked run's branch behind main as the resume", async () => {
  const comments = [{ user: { login: BOT }, body: "<!-- work-resolve-issue outcome=stopped run=400 -->", created_at: "2026-10-16T11:00:00Z" }];
  const comparison = { ahead_by: 1, behind_by: 865, total_commits: 1, commits: [LANE_TIP] };
  const { code, output } = await runPrior({ comments, refs: [refOf(lane(400))], comparison, env: { FIND_PRIOR_KEEP_BEHIND: "true" } });
  assert.equal(code, 0);
  assert.equal(output, `proceed=true\nskip-reason=\nreuse-branch=\nresume-branch=${lane(400)}\nresume-tip=${"a".repeat(40)}\nresume-cause=stopped\n`);
});

test("another issue's lane branches are never this issue's", () => {
  const branches = [branchFact("work-resolve-issue/issue-7-400-1"), branchFact("work-resolve-issue/issue-770-400-1", { pulls: [pullBy(BOT)] })];
  assert.deepEqual(prior({ branches }), { action: "run" });
});

test("with no lane branch and no closing PR the run goes ahead as before", () => {
  assert.deepEqual(prior({}), { action: "run" });
});

// The issue's lane branches a run deletes (#7948): a stopped run's branch,
// one whose run posted an outcome marker and whose tip is the lanes App's,
// with no pull request in any state. The branch the run reuses, resumes or
// starts fresh past, an unreported branch and this run's own are spared.
const prune = (facts) => {
  const all = { issueNumber: 77, repo: "o/r", bot: BOT, humans: HUMANS, branches: [], closing: [], markers: [], ...facts };
  return pruneBranches({ ...all, prior: findPrior(all) });
};

test("a stopped run's lane branch with no pull request is pruned", () => {
  const markers = [marked("pushback", "400")];
  assert.deepEqual(prune({ branches: [branchFact(lane(400))], markers }), [lane(400)]);
  // Every attempt of a stopped run that is not resumed goes.
  assert.deepEqual(prune({ branches: [branchFact(lane(400, 1)), branchFact(lane(400, 2))], markers }), [lane(400, 2), lane(400, 1)]);
});

test("a lane branch that backs a pull request in any state, by anyone, is kept", () => {
  for (const pull of [pullBy(BOT, "closed"), pullBy("stranger", "open"), pullBy("kyle-sexton", "closed")]) {
    assert.deepEqual(prune({ branches: [branchFact(lane(400), { pulls: [pull] })], markers: [marked("pushback", "400")] }), [], JSON.stringify(pull));
  }
});

test("an unreported lane branch, or one whose tip is not the lanes App's, is kept", () => {
  assert.deepEqual(prune({ branches: [branchFact(lane(400))] }), [], "unreported: the reuse branch");
  assert.deepEqual(prune({ branches: [branchFact(lane(401)), branchFact(lane(400))] }), [], "an older unreported branch");
  const tip = { ...LANE_TIP, author: { login: "stranger", type: "User" } };
  assert.deepEqual(prune({ branches: [branchFact(lane(400), { tip })], markers: [marked("pushback", "400")] }), [], "another author's tip");
  const commits = [LANE_TIP, tip];
  assert.deepEqual(prune({ branches: [branchFact(lane(400), { commits })], markers: [marked("pushback", "400")] }), [], "another author's commit");
  assert.deepEqual(prune({ branches: [branchFact(lane(400), { commits: null })], markers: [marked("pushback", "400")] }), [], "a listing cut short");
});

test("the branch the run resumes or starts fresh past is kept, and an older stopped run's goes", () => {
  const branches = [branchFact(lane(401), { sha: SHA_400 }), branchFact(lane(400))];
  const markers = [marked("stopped", "400", "2026-10-16T10:30:00Z"), marked("turn-cap", "401")];
  assert.equal(findPrior({ issueNumber: 77, repo: "o/r", bot: BOT, humans: HUMANS, branches, closing: [], markers }).branch, lane(401));
  assert.deepEqual(prune({ branches, markers }), [lane(400)]);
  const behind = [branchFact(lane(401), { sha: SHA_400, behindBy: 3 }), branchFact(lane(400))];
  assert.deepEqual(prune({ branches: behind, markers }), [lane(400)], "the stale branch is this run's data");
});

test("no branch of the run itself is pruned, whatever its attempt", () => {
  const branches = [branchFact(lane(400, 1)), branchFact(lane(400, 2)), branchFact(lane(399))];
  const markers = [marked("pushback", "399"), marked("pushback", "400")];
  const all = { issueNumber: 77, repo: "o/r", bot: BOT, humans: HUMANS, branches, closing: [], markers };
  assert.deepEqual(pruneBranches({ ...all, prior: findPrior(all), runId: "400" }), [lane(399)]);
});

test("--find-prior names a stopped run's branch with no pull request to prune, and none of this run's", async () => {
  const comments = [{ user: { login: BOT }, body: "<!-- work-resolve-issue outcome=pushback run=400 -->", created_at: "2026-10-16T11:00:00Z" }];
  const comparison = { ahead_by: 1, behind_by: 0, total_commits: 1, commits: [LANE_TIP] };
  const { code, calls, output } = await runPrior({ comments, refs: [refOf(lane(400))], comparison });
  assert.equal(code, 0);
  assert.equal(output, `proceed=true\nskip-reason=\nreuse-branch=\nprune-branches=${lane(400)}\n`);
  assert.deepEqual(writesToGitHub(calls), [], "the read job deletes nothing");
  const own = await runPrior({ comments, refs: [refOf(lane(400))], comparison, env: { GITHUB_RUN_ID: "400" } });
  assert.equal(own.output, "proceed=true\nskip-reason=\nreuse-branch=\n");
  const kept = await runPrior({ comments, refs: [refOf(lane(400))], comparison, pulls: [pullBy(BOT, "closed")] });
  assert.equal(kept.output, "proceed=true\nskip-reason=\nreuse-branch=\n");
});

// findPriorMain against a fake GitHub API: its only effect is the step
// outputs, and it writes nothing to GitHub.
async function withAsyncDir(files, run) {
  const dir = tempDir("prior-");
  try {
    for (const [name, text] of Object.entries(files)) {
      writeFileSync(join(dir, name), text);
    }
    return await run(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const TRUSTED_LIST = JSON.stringify({
  version: 1,
  actors: [
    { id: OWNER_ID, login: "kyle-sexton", kind: "human" },
    { id: 337595936, login: BOT, kind: "bot" },
  ],
});
const graphql = (nodes, pageInfo = { hasNextPage: false, endCursor: null }) => ({
  data: { repository: { issue: { closedByPullRequestsReferences: { nodes, pageInfo } } } },
});
const refOf = (name) => ({ ref: `refs/heads/${name}`, object: { sha: "a".repeat(40) } });

// `graphqlPages`, when given, answers the closing-PR query by its `after`
// cursor: page i is served for cursor `c<i>` (page 0 for none).
async function runPrior({
  comments = [],
  nodes = [],
  closingAnswer = graphql(nodes),
  refs = [],
  pulls = [],
  comparison = { ahead_by: 2, behind_by: 0 },
  repoAnswer = { default_branch: "main" },
  commitAnswer = LANE_TIP,
  graphqlPages,
  env = {},
}) {
  return withAsyncDir({ "trusted.json": TRUSTED_LIST, output: "" }, async (dir) => {
    const fake = fakeFetch([
      ["GET", /\/issues\/77\/comments$/, 200, comments],
      ["POST", /^\/graphql$/, 200, closingAnswer],
      ["GET", /\/git\/matching-refs\/heads\/work-resolve-issue\/issue-77-$/, 200, refs],
      ["GET", /\/repos\/o\/r$/, 200, repoAnswer],
      ["GET", /\/compare\//, 200, comparison],
      ["GET", /\/pulls$/, 200, pulls],
      // GET /commits/{ref} resolves a short sha or a branch name too, so any
      // ref answers here.
      ["GET", /^\/repos\/o\/r\/commits\/[^/]+$/, 200, commitAnswer],
    ]);
    const { calls } = fake;
    const fetch = async (url, init = {}) => {
      if (graphqlPages && new URL(url).pathname === "/graphql") {
        const { after } = JSON.parse(init.body).variables;
        calls.push({ method: "POST", path: "/graphql", body: JSON.parse(init.body) });
        const index = after ? Number(after.slice(1)) : 0;
        const pageInfo = { hasNextPage: index + 1 < graphqlPages.length, endCursor: `c${index + 1}` };
        const body = { data: { repository: { issue: { closedByPullRequestsReferences: { nodes: graphqlPages[index], pageInfo } } } } };
        return { ok: true, status: 200, json: async () => body };
      }
      return fake.fetch(url, init);
    };
    const code = await findPriorMain({
      env: {
        ISSUE_NUMBER: "77",
        GITHUB_REPOSITORY: "o/r",
        GITHUB_API_URL: "https://api.example",
        GH_TOKEN: "t",
        TRUSTED_ACTORS_PATH: join(dir, "trusted.json"),
        GITHUB_OUTPUT: join(dir, "output"),
        ...env,
      },
      fetch,
    });
    return { code, calls, output: readFileSync(join(dir, "output"), "utf8") };
  });
}

const writesToGitHub = (calls) => calls.filter((c) => c.method !== "GET" && c.path !== "/graphql");

test("--find-prior stops not-applicable on an open lanes-App PR, with no comment and no reuse branch", async () => {
  const { code, calls, output } = await runPrior({ refs: [refOf(lane(400))], pulls: [pullBy(BOT)] });
  assert.equal(code, 0);
  assert.equal(output, "proceed=false\nskip-reason=not-applicable\nreuse-branch=\n");
  assert.deepEqual(writesToGitHub(calls), []);
});

test("--find-prior stops not-applicable on a listed human's closing PR", async () => {
  const { output } = await runPrior({ nodes: [closer("User", "kyle-sexton", OWNER_ID)] });
  assert.equal(output, "proceed=false\nskip-reason=not-applicable\nreuse-branch=\n");
});

test("--find-prior goes ahead on an outsider's closing PR", async () => {
  const { output } = await runPrior({ nodes: [closer("User", "stranger", 42)] });
  assert.equal(output, "proceed=true\nskip-reason=\nreuse-branch=\n");
});

test("--find-prior goes ahead past a listed human's merged or closed closing PR, which GitHub lists despite includeClosedPrs: false", async () => {
  for (const state of ["MERGED", "CLOSED"]) {
    const { output } = await runPrior({ nodes: [closer("User", "kyle-sexton", OWNER_ID, "o/r", state)] });
    assert.equal(output, "proceed=true\nskip-reason=\nreuse-branch=\n", state);
  }
});

test("closingPulls keeps only the open closing PRs and asks GitHub for each one's state", async () => {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push(body);
    return graphql(["OPEN", "MERGED", "CLOSED"].map((state, i) => ({ ...closer("User", "stranger", 42, "o/r", state), number: 600 + i })));
  };
  const nodes = await closingPulls(github, { owner: "o", name: "r", number: 77 });
  assert.deepEqual(nodes.map((node) => node.number), [600]);
  assert.match(calls[0].query, /nodes \{ number state /);
});

test("--find-prior names an unreported lane branch ahead of main as the reuse branch", async () => {
  const { code, calls, output } = await runPrior({ refs: [refOf(lane(400))] });
  assert.equal(code, 0);
  assert.equal(output, `proceed=false\nskip-reason=not-applicable\nreuse-branch=${lane(400)}\n`);
  assert.deepEqual(writesToGitHub(calls), []);
});

test("--find-prior runs the model again for a branch its run's hand-back already reported", async () => {
  const comments = [{ user: { login: BOT }, body: "<!-- work-resolve-issue outcome=stopped run=400 -->\nStopped.", created_at: "2026-10-16T11:00:00Z" }];
  const { output } = await runPrior({ comments, refs: [refOf(lane(400))] });
  assert.ok(output.startsWith("proceed=true\nskip-reason=\nreuse-branch=\n"), output);
});

test("--find-prior does not take another account's copy of a marker as a report", async () => {
  const comments = [{ user: { login: "stranger" }, body: "<!-- work-resolve-issue outcome=stopped run=400 -->", created_at: "2026-10-16T11:00:00Z" }];
  const { output } = await runPrior({ comments, refs: [refOf(lane(400))] });
  assert.equal(output, `proceed=false\nskip-reason=not-applicable\nreuse-branch=${lane(400)}\n`);
});

test("--find-prior fails and writes no output when a read fails, so the mint never follows", async () => {
  await withAsyncDir({ "trusted.json": TRUSTED_LIST, output: "" }, async (dir) => {
    const { fetch } = fakeFetch([["GET", /\/issues\/77\/comments$/, 200, []]]);
    const code = await findPriorMain({
      env: {
        ISSUE_NUMBER: "77",
        GITHUB_REPOSITORY: "o/r",
        GITHUB_API_URL: "https://api.example",
        TRUSTED_ACTORS_PATH: join(dir, "trusted.json"),
        GITHUB_OUTPUT: join(dir, "output"),
      },
      fetch,
    });
    assert.equal(code, 1);
    assert.equal(readFileSync(join(dir, "output"), "utf8"), "");
  });
});

test("--find-prior reads every page of closing PRs, so outsiders' PRs cannot hide a trusted one", async () => {
  const outsiders = Array.from({ length: 100 }, (_, i) => ({ ...closer("User", `stranger${i}`, 1000 + i), number: 600 + i }));
  const { code, calls, output } = await runPrior({ graphqlPages: [outsiders, [closer("User", "kyle-sexton", OWNER_ID)]] });
  assert.equal(code, 0);
  assert.deepEqual(calls.filter((c) => c.path === "/graphql").map((c) => c.body.variables.after), [null, "c1"]);
  assert.equal(output, "proceed=false\nskip-reason=not-applicable\nreuse-branch=\n");
});

test("--find-prior fails on a pull request listing that is not a list", async () => {
  for (const pulls of [{ message: "odd" }, "x"]) {
    const { code, output } = await runPrior({ refs: [refOf(lane(400))], pulls });
    assert.equal(code, 1, JSON.stringify(pulls));
    assert.equal(output, "");
  }
});

// Each answer of the wrong shape fails the step with no outputs written.
const failsClosed = async (label, facts) => {
  const { code, output } = await runPrior(facts);
  assert.equal(code, 1, label);
  assert.equal(output, "", label);
};

test("--find-prior fails past the 50-page cap of closing PRs", async () => {
  const pages = Array.from({ length: 51 }, (_, i) => [{ ...closer("User", `stranger${i}`, 1000 + i), number: 600 + i }]);
  await failsClosed("51 pages", { graphqlPages: pages });
});

test("--find-prior fails on a closing PR with no state", async () => {
  for (const state of [undefined, null, 1]) {
    await failsClosed(String(state), { nodes: [{ ...closer("User", "stranger", 42), state }] });
  }
});

test("--find-prior fails on a closing-PR page with no page information", async () => {
  const page = (pageInfo) => ({ data: { repository: { issue: { closedByPullRequestsReferences: { nodes: [], pageInfo } } } } });
  for (const pageInfo of [undefined, {}, { hasNextPage: "false" }]) {
    await failsClosed(JSON.stringify(pageInfo) ?? "no pageInfo", { closingAnswer: page(pageInfo) });
  }
});

test("--find-prior fails at once on a next page with no cursor, after one closing-PR read", async () => {
  for (const endCursor of [null, ""]) {
    const { code, calls, output } = await runPrior({ closingAnswer: graphql([], { hasNextPage: true, endCursor }) });
    assert.equal(code, 1, String(endCursor));
    assert.equal(output, "", String(endCursor));
    assert.equal(calls.filter((c) => c.path === "/graphql").length, 1, String(endCursor));
  }
});

test("--find-prior fails on a lanes-App marker naming no run whose time cannot be read", async () => {
  for (const created_at of [undefined, "not a date"]) {
    const comments = [{ user: { login: BOT }, body: "<!-- work-resolve-issue outcome=stopped -->", created_at }];
    await failsClosed(String(created_at), { comments });
  }
});

test("--find-prior fails on a lane-branch listing that is not a list", async () => {
  await failsClosed("matching-refs object", { refs: { message: "odd" } });
});

test("--find-prior fails on a repository answer with no default branch", async () => {
  for (const repoAnswer of [{}, { default_branch: "" }, { default_branch: 5 }]) {
    await failsClosed(JSON.stringify(repoAnswer), { refs: [refOf(lane(400))], repoAnswer });
  }
});

test("--find-prior fails on a tip commit with no readable time when a marker names no run", async () => {
  const comments = [{ user: { login: BOT }, body: "<!-- work-resolve-issue outcome=stopped -->", created_at: "2026-10-16T11:00:00Z" }];
  for (const commitAnswer of [{}, { ...LANE_TIP, commit: { ...LANE_TIP.commit, committer: { date: "not a date" } } }]) {
    await failsClosed(JSON.stringify(commitAnswer), { comments, refs: [refOf(lane(400))], commitAnswer });
  }
});

test("--find-prior fails on a comparison with no whole-number behind_by", async () => {
  for (const behind of [undefined, "3", null, 1.5, -1]) {
    await failsClosed(String(behind), { refs: [refOf(lane(400))], comparison: { ahead_by: 1, behind_by: behind } });
  }
});

test("--find-prior fails on a comparison with no whole-number ahead_by", async () => {
  for (const comparison of [{}, { ahead_by: "3" }, { ahead_by: null }, { ahead_by: 1.5 }, { ahead_by: -1 }]) {
    const { code, output } = await runPrior({ refs: [refOf(lane(400))], comparison });
    assert.equal(code, 1, JSON.stringify(comparison));
    assert.equal(output, "");
  }
});

// Hand-back markers name the run, so a later --find-prior matches the branch
// issue-<N>-<run>-* to its report.
test("hand-back markers carry run= and read back with it", () => {
  for (const outcome of [
    { exit: "stopped", reason: "design-change: Tests failed.", title: "", summary: "" },
    { exit: "pushback", reason: "Which file?", cause: "intent", title: "", summary: "" },
  ]) {
    const plan = decide({ outcome, issueNumber: 77, issueLabels: [], branch: BRANCH, changedFiles: [], runId: "555" });
    assert.ok(plan.comment.startsWith(`${ESC}<!-- work-resolve-issue outcome=${outcome.exit} run=555 -->\n`), plan.comment);
    assert.deepEqual(parseOutcomeMarker(plan.comment), { outcome: outcome.exit, resets: null, run: "555", onResumed: false });
  }
});

test("a reuse PR body with no runner checks is fixed text, held, and follows the PR body contract's order", () => {
  const plan = reusePlan({
    issueNumber: 77,
    issueTitle: "Lane PR titles fall back",
    branch: lane(400),
    earlierRunUrl: "https://example/o/r/actions/runs/400",
  });
  assert.equal(plan.title, "fix: Lane PR titles fall back");
  assert.ok(plan.body.startsWith("Closes #77\n\nHold: a human merges this\n"), plan.body);
  assert.deepEqual(headings(plan.body), ["## Summary", "## Fix", "## Verification", "## Related"]);
  assert.ok(plan.body.includes("https://example/o/r/actions/runs/400"), plan.body);
});

const reuseEnv = (dir, branch = lane(400)) => ({ ...env(dir), REUSE_BRANCH: branch });
const PR_ROUTES = [
  ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
  ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
  ["GET", /\/compare\//, 200, { files: [{ filename: "README.md" }] }],
  ["GET", /\/pulls$/, 200, []],
  ["POST", /\/pulls$/, 201, { number: 90 }],
];
const model = { ...done, summary: "MODEL-SUMMARY-TEXT", title: "docs(work-items): model title" };

test("a reused branch whose own run's outcome is here opens the normal PR from it", async () => {
  await withAsyncDir({ "work-outcome.json": JSON.stringify(model), "lane.json": JSON.stringify({ branch: lane(400) }), "runner-checks": checksFile({ branch: lane(400) }) }, async (dir) => {
    const { fetch, calls } = fakeFetch([branchTip(lane(400)), ...PR_ROUTES]);
    assert.equal(await main({ env: reuseEnv(dir), fetch }), 0);
    const pull = calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body;
    assert.equal(pull.head, lane(400));
    assert.equal(pull.title, "docs(work-items): model title");
    assert.ok(pull.body.includes("MODEL-SUMMARY-TEXT"), pull.body);
  });
});

test("a reused branch with another run's or no outcome opens a held PR with none of the model's text", async () => {
  for (const files of [
    { "work-outcome.json": JSON.stringify(model), "lane.json": JSON.stringify({ branch: lane(399) }) },
    {},
    { "lane.json": JSON.stringify({ branch: lane(400) }) },
  ]) {
    await withAsyncDir(files, async (dir) => {
      const { fetch, calls } = fakeFetch(PR_ROUTES);
      assert.equal(await main({ env: reuseEnv(dir), fetch }), 0);
      const pull = calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body;
      assert.equal(pull.head, lane(400));
      assert.equal(pull.base, "main");
      assert.equal(pull.title, "fix: resolve issue 77");
      assert.ok(pull.body.split("\n").includes("Hold: a human merges this"), pull.body);
      assert.ok(!pull.body.includes("MODEL-SUMMARY-TEXT") && !pull.body.includes("model title"), pull.body);
      assert.ok(pull.body.includes("https://example/o/r/actions/runs/400"), pull.body);
      assert.ok(!calls.some((c) => c.path.endsWith("/comments") || c.path.endsWith("/issues/77/labels")), Object.keys(files).join());
      assert.deepEqual(calls.filter((c) => c.path.endsWith("/issues/90/labels")).map((c) => c.body), [{ labels: ["human-merge-hold"] }]);
    });
  }
});

test("a reused branch ignores a limit record, so no limited marker restarts it", async () => {
  await withAsyncDir({ "lane.json": JSON.stringify({ branch: lane(400), class: "rate-limit", resets: "2026-10-17T18:00:00Z" }) }, async (dir) => {
    const { fetch, calls } = fakeFetch(PR_ROUTES);
    assert.equal(await main({ env: reuseEnv(dir), fetch, now: LIMIT_NOW }), 0);
    assert.ok(!calls.some((c) => c.path.endsWith("/comments")));
    assert.ok(calls.some((c) => c.method === "POST" && c.path.endsWith("/pulls")));
  });
});

test("a reuse branch that is not this issue's lane branch is refused", async () => {
  for (const branch of ["main", "work-resolve-issue/issue-7-400-1", "work-resolve-issue/issue-77-400-1/x"]) {
    await withAsyncDir({}, async (dir) => {
      const { fetch, calls } = fakeFetch(PR_ROUTES);
      assert.equal(await main({ env: reuseEnv(dir, branch), fetch }), 1);
      assert.deepEqual(calls, [], branch);
    });
  }
});

// The summary pass: on a reuse, a read-only model pass over the branch diff
// and the issue writes reuse-summary.json beside runner facts (issue, branch,
// the tip it read). A reuse PR holds on mustHold's conditions whether or not
// it carries a usable summary; with none, it keeps the fixed text.
const TIP = "a".repeat(40);
const summaryFile = (overrides = {}, output = {}) =>
  JSON.stringify({
    version: 1,
    issue: 77,
    branch: lane(400),
    tip: TIP,
    output: { title: "docs(work-items): summary title", summary: "SUMMARY-PASS-TEXT", changes: ["CHANGE-ONE"], ...output },
    ...overrides,
  });
// Readable denied paths, so the README-only, read-only-class reuse PRs below
// hold only because no runner checks or leak scan reached them.
const RESOLVED = JSON.stringify({ merge: { "diff-check": { "denied-paths": HOLD_GLOBS, "path-holds": true } } });
const summaryEnv = (dir) => ({ ...reuseEnv(dir), REUSE_SUMMARY_DIR: dir, RESOLVED_CONFIG: join(dir, "resolved.json") });
const tipRoute = (sha = TIP) => ["GET", /\/git\/ref\/heads\/work-resolve-issue\/issue-77-400-1$/, 200, { object: { sha } }];
const usable = { title: "docs(work-items): summary title", summary: "SUMMARY-PASS-TEXT", changes: ["CHANGE-ONE"] };

test("a reuse PR with a usable summary carries it under the hold line", () => {
  const plan = reusePlan({ issueNumber: 77, branch: lane(400), summary: usable, changedFiles: ["README.md"], holdPaths: HOLD_GLOBS });
  assert.equal(plan.title, "docs(work-items): summary title");
  assert.ok(plan.body.startsWith("Closes #77\n\nHold: a human merges this\n\n## Summary\n"), plan.body);
  assert.ok(plan.body.includes("> SUMMARY-PASS-TEXT"), plan.body);
  assert.ok(plan.body.includes("- CHANGE-ONE"), plan.body);
  assert.deepEqual(headings(plan.body), ["## Summary", "## Fix", "## Verification", "## Related"]);
});

test("a reuse PR lists the files the branch changes, denied paths marked and first", () => {
  for (const summary of [usable, null]) {
    const plan = reusePlan({
      issueNumber: 77,
      branch: lane(400),
      summary,
      changedFiles: ["README.md", ".github/workflows/x.yml"],
      holdPaths: HOLD_GLOBS,
    });
    const fix = plan.body.slice(plan.body.indexOf("## Fix"), plan.body.indexOf("## Verification"));
    assert.ok(fix.includes("- .github/workflows/x.yml (denied path)\n- README.md\n"), fix);
  }
});

test("a reuse PR lists a file name holding a comment opener in full, escaped", () => {
  const plan = reusePlan({ issueNumber: 77, branch: lane(400), changedFiles: ["a<!--b.md"], holdPaths: HOLD_GLOBS });
  assert.ok(plan.body.includes("\n- a&lt;!--b.md\n"), plan.body);
});

test("format and bidi characters are dropped from file names and summary text", () => {
  const plan = reusePlan({
    issueNumber: 77,
    branch: lane(400),
    summary: { ...usable, summary: "SUM‮MARY​TEXT" },
    changedFiles: ["evil‮dm.​sh"],
    holdPaths: HOLD_GLOBS,
  });
  assert.ok(plan.body.includes("\n- evildm.sh\n"), plan.body);
  assert.ok(plan.body.includes("> SUMMARYTEXT"), plan.body);
  assert.ok(!/[‮​]/.test(plan.body), plan.body);
});

test("a reuse PR's file list says when the denied paths or the listing cannot be read", () => {
  const unmarked = reusePlan({ issueNumber: 77, branch: lane(400), changedFiles: [".github/workflows/x.yml"], holdPaths: null });
  assert.ok(unmarked.body.includes("so none is marked") && !unmarked.body.includes("(denied path)"), unmarked.body);
  const missing = reusePlan({ issueNumber: 77, branch: lane(400), changedFiles: null, holdPaths: HOLD_GLOBS });
  assert.ok(missing.body.includes("The changed-file list is unavailable"), missing.body);
});

test("main opens a held reuse PR when the compare request fails, saying the file list is unavailable", async () => {
  await withAsyncDir({ "reuse-summary.json": summaryFile(), "resolved.json": RESOLVED }, async (dir) => {
    const routes = [tipRoute(), ...PR_ROUTES.map((r) => (String(r[1]) === String(/\/compare\//) ? ["GET", /\/compare\//, 500, { message: "boom" }] : r))];
    const { fetch, calls } = fakeFetch(routes);
    assert.equal(await main({ env: summaryEnv(dir), fetch }), 0);
    const pull = calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body;
    assert.ok(pull.body.includes("The changed-file list is unavailable"), pull.body);
    assert.ok(pull.body.includes("SUMMARY-PASS-TEXT"), pull.body);
    assert.ok(pull.body.split("\n").includes("Hold: a human merges this"), pull.body);
  });
});

test("main opens a held reuse PR from a summary bound to this issue, branch and tip", async () => {
  await withAsyncDir({ "reuse-summary.json": summaryFile(), "resolved.json": RESOLVED }, async (dir) => {
    const { fetch, calls } = fakeFetch([tipRoute(), ...PR_ROUTES]);
    assert.equal(await main({ env: summaryEnv(dir), fetch }), 0);
    const pull = calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body;
    assert.equal(pull.head, lane(400));
    assert.equal(pull.title, "docs(work-items): summary title");
    assert.ok(pull.body.includes("SUMMARY-PASS-TEXT") && pull.body.includes("CHANGE-ONE"), pull.body);
    assert.ok(pull.body.includes("\n- README.md\n") && !pull.body.includes("(denied path)"), pull.body);
    assert.ok(pull.body.split("\n").includes("Hold: a human merges this"), pull.body);
  });
});

test("main keeps the fixed text and the hold line when the summary is missing or unusable", async () => {
  for (const [label, files, tip] of [
    ["no summary file", {}, TIP],
    ["another issue", { "reuse-summary.json": summaryFile({ issue: 7 }) }, TIP],
    ["another branch", { "reuse-summary.json": summaryFile({ branch: lane(399) }) }, TIP],
    ["the branch moved", { "reuse-summary.json": summaryFile() }, "b".repeat(40)],
    ["no structured output", { "reuse-summary.json": summaryFile({ output: null }) }, TIP],
    ["an empty summary", { "reuse-summary.json": summaryFile({}, { summary: "  " }) }, TIP],
    ["not JSON", { "reuse-summary.json": "{" }, TIP],
    ["another version", { "reuse-summary.json": summaryFile({ version: 2 }) }, TIP],
  ]) {
    await withAsyncDir(files, async (dir) => {
      const { fetch, calls } = fakeFetch([tipRoute(tip), ...PR_ROUTES]);
      assert.equal(await main({ env: summaryEnv(dir), fetch }), 0, label);
      const pull = calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body;
      assert.equal(pull.title, "fix: resolve issue 77", label);
      assert.ok(pull.body.split("\n").includes("Hold: a human merges this"), label);
      assert.ok(!pull.body.includes("SUMMARY-PASS-TEXT") && !pull.body.includes("CHANGE-ONE"), label);
    });
  }
});

test("main keeps the hold line when the branch tip cannot be read", async () => {
  await withAsyncDir({ "reuse-summary.json": summaryFile() }, async (dir) => {
    const { fetch, calls } = fakeFetch(PR_ROUTES);
    assert.equal(await main({ env: summaryEnv(dir), fetch }), 0);
    const pull = calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body;
    assert.ok(pull.body.split("\n").includes("Hold: a human merges this"), pull.body);
    assert.ok(!pull.body.includes("SUMMARY-PASS-TEXT"), pull.body);
  });
});

test("a branch's own outcome wins over a summary, so the summary never stands in for a report", async () => {
  await withAsyncDir(
    { "work-outcome.json": JSON.stringify(model), "lane.json": JSON.stringify({ branch: lane(400) }), "reuse-summary.json": summaryFile(), "runner-checks": checksFile({ branch: lane(400), tip: TIP }) },
    async (dir) => {
      const { fetch, calls } = fakeFetch([tipRoute(), ...PR_ROUTES]);
      assert.equal(await main({ env: summaryEnv(dir), fetch }), 0);
      const pull = calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body;
      assert.ok(pull.body.includes("MODEL-SUMMARY-TEXT") && !pull.body.includes("SUMMARY-PASS-TEXT"), pull.body);
    },
  );
});

// main on a done run of an issue with these labels and `labeled` events, under
// a resolved config that denies no path, so only the label can hold the PR.
async function runHumanMerge({ labels, events = [], eventsStatus = 200, trusted = TRUSTED_LIST, open = [], labelStatus = 200 }) {
  return withAsyncDir(
    {
      "work-outcome.json": JSON.stringify(done),
      "lane.json": JSON.stringify({ branch: BRANCH }),
      "runner-checks": checksFile(),
      "resolved.json": JSON.stringify({ merge: { "diff-check": { "denied-paths": [] } } }),
      ...(trusted === null ? {} : { "trusted.json": trusted }),
    },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, 200, { number: 77, labels: labels.map((name) => ({ name })) }],
        ["GET", /\/issues\/77\/events$/, eventsStatus, events],
        branchTip(),
        ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
        ["GET", /\/compare\//, 200, { files: [{ filename: "README.md" }] }],
        ["GET", /\/pulls$/, 200, open],
        ["POST", /\/pulls$/, 201, { number: 90 }],
        ["POST", /\/issues\/90\/labels$/, labelStatus, []],
        ["PATCH", /\/pulls\/90$/, 200, {}],
        ...HISTORY,
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/issues\/77\/labels\//, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      const code = await main({
        env: { ...env(dir), RESOLVED_CONFIG: join(dir, "resolved.json"), TRUSTED_ACTORS: join(dir, "trusted.json") },
        fetch,
        sleep: async () => {},
      });
      return { code, calls, body: calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls"))?.body.body };
    },
  );
}

const MERGE_HUMAN = ["agent-ready", "work-class: scoped", "merge: human"];
const holds = (body) => body.split("\n").includes("Hold: a human merges this");

test("main holds the PR when the owner put merge: human on the issue", async () => {
  const { code, body } = await runHumanMerge({ labels: MERGE_HUMAN, events: [labeled("merge: human", "kyle-sexton", OWNER_ID)] });
  assert.equal(code, 0);
  assert.ok(holds(body), body);
});

test("main holds the PR when the lanes App put merge: human on the issue", async () => {
  const { body } = await runHumanMerge({ labels: MERGE_HUMAN, events: [labeled("merge: human", BOT, 337595936)] });
  assert.ok(holds(body), body);
});

test("main without merge: human holds no PR and reads no label events", async () => {
  const { body, calls } = await runHumanMerge({ labels: ["agent-ready", "work-class: scoped"] });
  assert.ok(!holds(body), body);
  assert.ok(!calls.some((c) => c.path.endsWith("/events")));
});

// The hold line is body text the lanes App can edit, so a held PR also
// carries a label only a listed person's removal lifts (ci-status's
// human-merge hold step).
const holdLabelPosts = (calls) => calls.filter((c) => c.method === "POST" && c.path.endsWith("/issues/90/labels"));

test("main labels a held PR human-merge-hold right after it opens", async () => {
  assert.equal(HUMAN_MERGE_HOLD, "human-merge-hold");
  const { code, calls } = await runHumanMerge({ labels: MERGE_HUMAN, events: [labeled("merge: human", "kyle-sexton", OWNER_ID)] });
  assert.equal(code, 0);
  assert.deepEqual(holdLabelPosts(calls).map((c) => c.body), [{ labels: ["human-merge-hold"] }]);
  assert.ok(!calls.some((c) => c.method === "PATCH"));
});

test("main puts no human-merge-hold label on a PR that does not hold", async () => {
  const { code, calls } = await runHumanMerge({ labels: ["agent-ready", "work-class: scoped"] });
  assert.equal(code, 0);
  assert.deepEqual(holdLabelPosts(calls), []);
});

test("main labels a held PR it reuses from an earlier attempt", async () => {
  const { code, calls } = await runHumanMerge({
    labels: MERGE_HUMAN,
    events: [labeled("merge: human", "kyle-sexton", OWNER_ID)],
    open: [{ number: 90, user: { login: BOT } }],
  });
  assert.equal(code, 0);
  assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/pulls")));
  assert.deepEqual(holdLabelPosts(calls).map((c) => c.body), [{ labels: ["human-merge-hold"] }]);
});

test("main closes a held PR it cannot label and retries the issue", async () => {
  const { code, calls } = await runHumanMerge({
    labels: MERGE_HUMAN,
    events: [labeled("merge: human", "kyle-sexton", OWNER_ID)],
    labelStatus: 500,
  });
  assert.equal(code, 0);
  assert.ok(holdLabelPosts(calls).length >= 2, "the label write is resent");
  assert.deepEqual(calls.find((c) => c.method === "PATCH" && c.path.endsWith("/pulls/90"))?.body, { state: "closed" });
  const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/issues/77/comments")).body.body;
  assert.ok(comment.startsWith("<!-- work-resolve-issue outcome=retry"), comment);
  assert.match(comment, /`hold-label-failed`/);
});

test("main ignores merge: human from a labeler who is not a listed human or the lanes App", async () => {
  const { body } = await runHumanMerge({ labels: MERGE_HUMAN, events: [labeled("merge: human", "stranger", 42)] });
  assert.ok(!holds(body), body);
});

test("main holds the PR when merge: human's labeler cannot be read", async () => {
  assert.ok(holds((await runHumanMerge({ labels: MERGE_HUMAN, eventsStatus: 500, events: { message: "boom" } })).body));
  assert.ok(holds((await runHumanMerge({ labels: MERGE_HUMAN, events: [labeled("merge: human", "kyle-sexton", OWNER_ID)], trusted: null })).body));
});

// The funding stop (ci-workflows#781): a run that exits 1 with
// api_error_status 400 and "regain access on <date>" (a spend limit or a zero
// balance), or 401 (a disabled key). The runner copies those fields into
// lane.json; report-outcome names the cause `funding` and waits.
const fundingLane = (fields) =>
  JSON.stringify({ branch: "", class: "other", resets: "", "max-turns": "75", resume: "", ...fields });
const readFundingOf = (fields) => withDir({ "lane.json": fundingLane(fields) }, (dir) => readFunding(dir));

test("a failed run with 400 and a regain date is a funding stop until that date", () => {
  assert.deepEqual(
    readFundingOf({ failed: "true", "api-error-status": "400", "error-text": "Credit balance too low. You will regain access on 2026-11-01." }),
    { regain: Date.parse("2026-11-01") },
  );
});

test("a failed run with 401 is a funding stop with no date", () => {
  assert.deepEqual(readFundingOf({ failed: "true", "api-error-status": "401", "error-text": "API key disabled" }), { regain: null });
});

test("a regain date that cannot be read still names a funding stop", () => {
  assert.deepEqual(
    readFundingOf({ failed: "true", "api-error-status": "400", "error-text": "You will regain access on the first business day" }),
    { regain: null },
  );
});

for (const [why, fields] of [
  ["a 400 with no regain text", { failed: "true", "api-error-status": "400", "error-text": "prompt is too long" }],
  ["a run that did not fail", { failed: "false", "api-error-status": "400", "error-text": "You will regain access on 2026-11-01." }],
  ["a 429", { failed: "true", "api-error-status": "429", "error-text": "You will regain access on 2026-11-01." }],
  ["no status", { failed: "true", "error-text": "You will regain access on 2026-11-01." }],
]) {
  test(`${why} is no funding stop`, () => {
    assert.equal(readFundingOf(fields), null);
  });
}

const unread = { exit: "stopped", reason: "", title: "", summary: "", unread: true };
const decideFunding = (overrides) =>
  decide({ outcome: unread, issueNumber: 77, issueLabels: ["agent-ready"], branch: BRANCH, changedFiles: [], runId: "555", ...overrides });

test("a funding stop keeps agent-ready, adds no label and leaves a funding marker with the regain date", () => {
  const plan = decideFunding({ funding: { regain: Date.parse("2026-11-01T00:00:00Z") } });
  assert.equal(plan.action, "funding");
  assert.deepEqual(plan.addLabels, []);
  assert.deepEqual(plan.removeLabels, []);
  assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=funding resets=2026-11-01T00:00:00Z run=555 -->\n"), plan.comment);
  assert.match(plan.comment, /funding/);
  assert.deepEqual(parseOutcomeMarker(plan.comment), { outcome: "funding", resets: Date.parse("2026-11-01T00:00:00Z"), run: "555", onResumed: false });
});

test("a funding stop with no date leaves a marker with no reset, and work-unblock, not a person, restarts it", () => {
  const plan = decideFunding({ funding: { regain: null } });
  assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=funding run=555 -->\n"), plan.comment);
  assert.equal(parseOutcomeMarker(plan.comment).resets, null);
  assert.match(plan.comment, /work-unblock starts it again after limits\.fallback-reset hours/);
  assert.doesNotMatch(plan.comment, /a person/);
});

// work-unblock's fail route after limits.limit-stops-per-issue leaves an
// outcome=failed marker naming the stopped run; a person's new agent-ready
// then resumes that run's branch like the limit or funding marker it follows.
test("a failed marker is resumable", () => {
  assert.ok(RESUMABLE.has("failed"));
});

test("a funding stop wins over a turn-cap or limit record, so it counts as neither", () => {
  const plan = decideFunding({ funding: { regain: null }, turnCap: { cap: 75 }, limit: { resets: null }, limits: { "turn-cap-restarts": 0 } });
  assert.equal(plan.action, "funding");
});

test("a stop the skill reported goes to a person even with a funding record", () => {
  const plan = decideFunding({ outcome: { exit: "stopped", reason: "design-change: Blocked.", title: "", summary: "" }, funding: { regain: null } });
  assert.equal(plan.action, "hand-back");
});

// collect-base-activity runs a script activity from a copy of its own
// directory under $RUNNER_TEMP, so every import must resolve inside it.
// collect-base-activity puts the base .github/scripts/lib/ beside that copy.
test("the script loads from a copy of its own directory alone, beside the shared lib", async () => {
  const copy = tempDir("base-script-");
  try {
    const here = dirname(fileURLToPath(import.meta.url));
    cpSync(here, join(copy, "base-script"), { recursive: true });
    cpSync(join(here, "..", "lib"), join(copy, "lib"), { recursive: true });
    const module = await import(pathToFileURL(join(copy, "base-script", "report-outcome.mjs")).href);
    assert.equal(typeof module.main, "function");
  } finally {
    rmSync(copy, { recursive: true, force: true });
  }
});

// work-resolve-issue.yml's run-checks step, run against a throwaway base and
// lane branch. Expected values come from #7497 and W-92 (a): each check runs
// from the base copy against the lane branch, and reads the scripts/ data
// (.txt, .json, .jsonl) the merged ref would hold: the base's, with the
// branch's own changes since the merge base; a committed symlink there fails
// the step.
function runChecksScript(step = "run-checks") {
  const lines = readFileSync(new URL("../../workflows/work-resolve-issue.yml", import.meta.url), "utf8").split("\n");
  const id = lines.findIndex((line) => line.trim() === `id: ${step}`);
  assert.notEqual(id, -1, `work-resolve-issue.yml has the ${step} step`);
  const start = lines.findIndex((line, i) => i > id && /^\s+run: \|$/.test(line));
  const keyIndent = lines[start].search(/\S/);
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && line.search(/\S/) <= keyIndent) break;
    body.push(line);
  }
  const indent = Math.min(...body.filter((l) => l.trim()).map((l) => l.search(/\S/)));
  return body.map((l) => l.slice(indent)).join("\n");
}

// The lane repository forks from a commit holding the base's check and a
// scripts/list.txt saying bad; the lane branch then commits its own files and
// the default branch moves on with `baseFiles`, and BASE is a clone of that
// tip. The base's check passes only when scripts/list.txt says ok, the branch
// holds .changes/good.md and `extraCheck` holds; the branch's copy of the check
// logs "lane" and always passes, so running it gives a different log and result.
function runChecks({
  goodFragment,
  branchList = "ok\n",
  symlink,
  checks = ["scripts/check-x.sh --check"],
  forkFiles = {},
  laneFiles = {},
  laneDeletes = [],
  baseFiles = {},
  extraCheck = "true",
  unrelatedBase = false,
  env = () => ({}),
}) {
  const root = tempDir("run-checks-");
  try {
    const base = join(root, "base");
    const laneDir = join(root, "lane");
    const out = join(root, "out");
    const log = join(root, "log");
    const write = (path, text) => {
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, text);
    };
    const gitIn = (dir, ...args) => {
      const run = spawnSync("git", ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", ...args], { encoding: "utf8" });
      assert.equal(run.status, 0, `git ${args.join(" ")}: ${run.stderr}`);
      return run.stdout;
    };
    const git = (...args) => gitIn(laneDir, ...args);
    const commitAll = (dir, files, message) => {
      for (const [path, text] of Object.entries(files)) write(join(dir, path), text);
      gitIn(dir, "add", "-A");
      gitIn(dir, "commit", "-qm", message, "--allow-empty");
    };
    const baseCheck = `#!/usr/bin/env bash\necho "base $PWD $CHECK_DATA_ROOT $*" >>"$LOG"\ngrep -qx ok scripts/list.txt && [ -f .changes/good.md ] && ${extraCheck}\n`;
    const forkTree = { "scripts/list.txt": "bad\n", "scripts/check-x.sh": baseCheck, ...forkFiles };
    mkdirSync(laneDir, { recursive: true });
    git("init", "-q", "-b", "main");
    commitAll(laneDir, forkTree, "fork");
    git("checkout", "-q", "-b", "lane");
    for (const path of laneDeletes) rmSync(join(laneDir, path));
    if (symlink) {
      symlinkSync(symlink.target, join(laneDir, "scripts", symlink.name));
    }
    const laneTree = { "scripts/list.txt": branchList, "scripts/check-x.sh": '#!/usr/bin/env bash\necho lane >>"$LOG"\nexit 0\n', ...laneFiles };
    if (goodFragment) laneTree[".changes/good.md"] = "x\n";
    commitAll(laneDir, laneTree, "lane");
    git("checkout", "-q", "main");
    commitAll(laneDir, baseFiles, "base moves on");
    if (unrelatedBase) {
      mkdirSync(base, { recursive: true });
      gitIn(base, "init", "-q", "-b", "main");
      commitAll(base, forkTree, "unrelated");
    } else {
      gitIn(root, "clone", "-q", "--branch", "main", laneDir, base);
    }
    git("checkout", "-q", "lane");
    const tip = git("rev-parse", "HEAD").trim();
    write(join(root, "resolved.json"), JSON.stringify({ lane: { slots: [{ name: "resolve-issue", checks }] } }));
    const run = spawnSync("bash", ["-e", "-o", "pipefail", "-c", runChecksScript()], {
      encoding: "utf8",
      env: { ...process.env, BASE: base, LANE: laneDir, BRANCH, RESOLVED: join(root, "resolved.json"), GITHUB_OUTPUT: out, LOG: log, ...env(tip) },
    });
    const output = existsSync(out) ? readFileSync(out, "utf8").split("\n").find((line) => line.startsWith("checks=")) : undefined;
    return {
      status: run.status,
      stdout: run.stdout,
      tip,
      laneDir,
      checks: output === undefined ? null : JSON.parse(output.slice("checks=".length)),
      log: existsSync(log) ? readFileSync(log, "utf8") : "",
    };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test("the runner runs each check's code from the base copy, reading the lane branch's committed scripts/ data", () => {
  const passing = runChecks({ goodFragment: true });
  assert.equal(passing.status, 0, passing.stdout);
  assert.deepEqual(passing.checks, {
    version: 1,
    branch: BRANCH,
    tip: passing.tip,
    results: [{ check: "scripts/check-x.sh --check", exit: 0 }],
  });
  assert.equal(passing.log, `base ${passing.laneDir} ${passing.laneDir} --check\n`);
  const badList = runChecks({ goodFragment: true, branchList: "bad\n" });
  assert.equal(badList.status, 0, badList.stdout);
  assert.deepEqual(badList.checks.results, [{ check: "scripts/check-x.sh --check", exit: 1 }]);
  assert.equal(badList.log, `base ${badList.laneDir} ${badList.laneDir} --check\n`);
  const failing = runChecks({ goodFragment: false });
  assert.equal(failing.status, 0, failing.stdout);
  assert.deepEqual(failing.checks.results, [{ check: "scripts/check-x.sh --check", exit: 1 }]);
});

test("a scripts/ data file the default branch added after the lane branch forked is the base's copy", () => {
  const run = runChecks({ goodFragment: true, baseFiles: { "scripts/added.txt": "base\n" }, extraCheck: "grep -qx base scripts/added.txt" });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.checks.results, [{ check: "scripts/check-x.sh --check", exit: 0 }]);
});

test("a scripts/ data file the default branch changed and the lane branch did not is the base's copy", () => {
  const run = runChecks({
    goodFragment: true,
    forkFiles: { "scripts/shared.json": "fork\n" },
    baseFiles: { "scripts/shared.json": "base\n" },
    extraCheck: "grep -qx base scripts/shared.json",
  });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.checks.results, [{ check: "scripts/check-x.sh --check", exit: 0 }]);
});

test("a scripts/ data file the lane branch changed is the branch's copy", () => {
  const run = runChecks({
    goodFragment: true,
    forkFiles: { "scripts/own.jsonl": "fork\n" },
    laneFiles: { "scripts/own.jsonl": "lane\n" },
    extraCheck: "grep -qx lane scripts/own.jsonl",
  });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.checks.results, [{ check: "scripts/check-x.sh --check", exit: 0 }]);
});

test("a scripts/ data file the lane branch deleted is absent", () => {
  const run = runChecks({
    goodFragment: true,
    forkFiles: { "scripts/gone.txt": "fork\n" },
    laneDeletes: ["scripts/gone.txt"],
    extraCheck: "[ ! -e scripts/gone.txt ]",
  });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.checks.results, [{ check: "scripts/check-x.sh --check", exit: 0 }]);
});

test("the runner fails and runs no check when the lane branch shares no history with the base tip", () => {
  const run = runChecks({ goodFragment: true, unrelatedBase: true });
  assert.equal(run.status, 1, run.stdout);
  assert.match(run.stdout, /::error::cannot find the lane branch's merge base with the base tip/);
  assert.equal(run.checks, null);
  assert.equal(run.log, "");
});

test("the runner fails and runs no check when the lane branch commits a symlink under scripts/", () => {
  const run = runChecks({ goodFragment: true, symlink: { name: "link.txt", target: "/etc/hostname" } });
  assert.equal(run.status, 1, run.stdout);
  assert.match(run.stdout, /::error::the lane branch's scripts\/ holds a symlink/);
  assert.equal(run.checks, null);
  assert.equal(run.log, "");
});


test("the runner writes no check results for a check outside scripts/ or with free arguments", () => {
  for (const check of ["plugins/x/scripts/check.sh", "scripts/check-x.sh ../etc", "scripts/check-x.sh; true"]) {
    const run = runChecks({ goodFragment: true, checks: [check] });
    assert.equal(run.status, 1, check);
    assert.equal(run.checks, null, check);
  }
});

test("the runner records an empty result list when the activity lists no checks", () => {
  const run = runChecks({ goodFragment: true, checks: [] });
  assert.equal(run.status, 0, run.stdout);
  assert.deepEqual(run.checks.results, []);
});

// /work-items:attend-queue lists an issue as escalated only from a comment
// whose first line is exactly the escalation marker (work-items reference
// escalation-marker.md), so every plan that adds the human-gated label opens
// with it, and a plan that keeps agent-ready for a restart carries none.
test("every hand-back opens with the attended queue's escalation marker, and no other route carries one", () => {
  const plain = { issueNumber: 77, issueLabels: [], branch: BRANCH, changedFiles: [], runId: "555" };
  const handBacks = [
    decide({ ...plain, outcome: { exit: "pushback", reason: "Which file?", cause: "intent", title: "", summary: "" } }),
    decide({ ...plain, outcome: { exit: "stopped", reason: "design-change: Tests failed.", title: "", summary: "" } }),
    decide({ ...plain, outcome: { exit: "done", reason: "", title: "", summary: "" }, escalation: "patch-credential" }),
  ];
  for (const plan of handBacks) {
    assert.deepEqual(plan.addLabels, ["needs-human"], plan.comment);
    assert.equal(plan.comment.split("\n")[0], "<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->", plan.comment);
  }
  const restarts = [
    capped(),
    capped({ limits: { "turn-cap-restarts": 0 } }),
    decide({ ...plain, outcome: { exit: "done", reason: "", title: "", summary: "" }, escalation: "patch-protected-path" }),
    decide({ ...plain, outcome: readOutcome("/nonexistent/work-outcome.json") }),
    decide({ ...plain, outcome: { exit: "stopped", reason: "Tests failed.", title: "", summary: "" } }),
    decide({ ...plain, outcome: { exit: "stopped", reason: "blocked-by-pr: #5 adds the helper", title: "", summary: "" } }),
    decide({ ...plain, outcome: { exit: "stopped", reason: "already-done: on main at abc1234", title: "", summary: "" } }),
    decideFunding({ funding: { regain: null } }),
    decideFunding({ limit: { resets: Date.parse("2026-10-17T18:00:00Z") }, now: Date.parse("2026-10-17T12:00:00Z") }),
  ];
  for (const plan of restarts) {
    assert.ok(!plan.addLabels.includes("needs-human"), plan.comment);
    assert.ok(!plan.comment.includes("work-items:escalation"), plan.comment);
  }
});

// Every comment that reaches a person says which of the owner's reasons
// applies, as a marker and a visible line (../lib/stop-reason.mjs); `none`
// never reaches one.
test("every person-routed comment carries the stop-reason marker and the Reason line", async () => {
  const holds = Object.keys(STOP_ROUTES).filter((reason) => STOP_ROUTES[reason].route === "hold");
  assert.ok(holds.length > 0);
  const plain = { issueNumber: 77, issueLabels: [], branch: BRANCH, changedFiles: [], runId: "555", humanLabel: "needs-human" };
  for (const reason of holds) {
    const outcome = { exit: "stopped", reason: "Why.", title: "", summary: "", changes: [], verification: [], notDone: [], steps: [], unread: true, stop: reason };
    const plan = decide({ ...plain, outcome });
    assert.equal(plan.action, "hand-back", reason);
    const code = parseReason(plan.comment)?.reason;
    assert.ok(isPersonReason(code), `${reason}: ${code}`);
    assert.ok(plan.comment.split("\n").includes(`Reason: \`${code}\``), plan.comment);
  }
  const pushback = decide({ ...plain, outcome: { exit: "pushback", reason: "Which file?", cause: "intent", title: "", summary: "" } });
  assert.equal(parseReason(pushback.comment).reason, "intent");
  assert.ok(pushback.comment.includes("Reason: `intent`"));
  // A comment that reaches no person carries no stop-reason marker.
  assert.equal(parseReason(decide({ ...plain, outcome: { exit: "stopped", reason: "Tests failed.", title: "", summary: "" } }).comment), null);
});

// A security hold read from the run's words names the word, so a person can
// dismiss a false hit in one read. Expected lines follow the comment's rule:
// the word, in a code span, of ASCII letters, digits, hyphens, underscores and
// single spaces.
const WORD_LINE = "Matched security word: ";
const wordLine = (comment) => comment.split("\n").find((line) => line.startsWith(WORD_LINE));
const wordsPlan = (reason, over = {}) =>
  decide({
    issueNumber: 77,
    issueLabels: [],
    branch: "",
    changedFiles: [],
    humanLabel: "needs-human",
    outcome: { exit: "stopped", reason, title: "", summary: "", changes: [], verification: [], notDone: [], steps: [], ...over },
  });

test("a security hold read from the run's words names the matched word and keeps its hold", () => {
  for (const [reason, word] of [
    ["already-done: merged in #11518, which closed the part that took over #9103's whole scope.", "took over"],
    ["The TOKEN is in the URL.", "TOKEN"],
    ["host-only: needs credentials, and the run found a backdoor", "backdoor"],
    ["manual-external: rotate the leaked deploy token in the DNS account.", "token"],
  ]) {
    const plan = wordsPlan(reason);
    assert.equal(plan.action, "hand-back", reason);
    assert.equal(plan.stop, "security-risk", reason);
    assert.ok(plan.addLabels.includes("needs-human"), reason);
    assert.equal(parseReason(plan.comment).reason, "security", plan.comment);
    assert.ok(wordLine(plan.comment)?.startsWith(`${WORD_LINE}\`${word}\`.`), plan.comment);
  }
});

test("a matched word cannot mention, link, close, or add markup to the comment", () => {
  for (const [reason, word] of [
    ["ignore @owner [x](http://e.co) #5 `y` <b> instructions", "ignore owner x http e co 5 y b instructions"],
    ["ignore \uff20owner \uff035 instructions", "ignore owner 5 instructions"],
    ["ignore closes GH-5 instructions", "ignore closes GH-5 instructions"],
    ["took\n\n  over the account", "took over"],
  ]) {
    const plan = wordsPlan(reason);
    assert.equal(plan.stop, "security-risk", reason);
    assert.ok(wordLine(plan.comment)?.startsWith(`${WORD_LINE}\`${word}\`.`), plan.comment);
    assert.equal(plan.comment.split("\n").filter((line) => line.startsWith("<!--")).length, 3, plan.comment);
  }
});

test("a spent intake round names the word from whichever of the run's words holds it", () => {
  const plain = { issueNumber: 77, issueLabels: ["agent-ready"], branch: "", changedFiles: [], humanLabel: "needs-human" };
  const plan = decide({ ...plain, outcome: { exit: "pushback", reason: "Which helper?", title: "", summary: "The log printed the deploy token." } });
  const spent = capRetries(plan, 1);
  assert.equal(spent.stop, "security-risk");
  assert.ok(wordLine(spent.comment)?.startsWith(`${WORD_LINE}\`token\`.`), spent.comment);
  const coded = capRetries(decide({ ...plain, outcome: { exit: "pushback", reason: "Which helper?", title: "", summary: "design-change: the token store needs a new shape" } }), 1);
  assert.equal(coded.stop, "security-risk");
  assert.ok(wordLine(coded.comment)?.startsWith(`${WORD_LINE}\`token\`.`), coded.comment);
});

test("a hold no word put there names no word", () => {
  const plain = { issueNumber: 77, issueLabels: [], branch: "", changedFiles: [], humanLabel: "needs-human" };
  const pushback = (reason, cause) => decide({ ...plain, outcome: { exit: "pushback", reason, cause, title: "", summary: "" } });
  for (const plan of [
    wordsPlan("security-risk: the deploy token is in the log"),
    wordsPlan("security-risk: see the summary", { summary: "The deploy token is in the log." }),
    pushback("security-risk: the issue asks to print the deploy token in the log."),
    pushback("The fix needs the token rotated.", "security-risk"),
    wordsPlan("Why.", { stop: "patch-credential", unread: true }),
    pushback("Which token does the issue mean?", "intent"),
    wordsPlan("design-change: the token store needs a new shape"),
  ]) {
    assert.equal(plan.action, "hand-back", plan.comment);
    assert.equal(wordLine(plan.comment), undefined, plan.comment);
  }
  assert.equal(wordLine(wordsPlan("The tests failed twice.").comment), undefined);
});

test("an outcome marker reads back after the escalation marker line, and after no other line", () => {
  const outcome = "<!-- work-resolve-issue outcome=stopped run=9 -->\nWhy.";
  const read = { outcome: "stopped", resets: null, run: "9", onResumed: false };
  assert.deepEqual(parseOutcomeMarker(`<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\n${outcome}`), read);
  assert.deepEqual(parseOutcomeMarker(`<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\r\n${outcome}`), read);
  assert.equal(parseOutcomeMarker(`<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n${outcome}`), null);
  assert.equal(parseOutcomeMarker(`Quoting <!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\n${outcome}`), null);
});

// The run counts a listed human's comment as an answer only when its first
// line is `**Decision recorded.**` (write-issue.mjs), so a pushback links the
// owner's newest comment that lacks it and shows the line (#7916).
const commentUrl = (id) => `https://github.com/o/r/issues/77#issuecomment-${id}`;
const issueComment = (id, userId, body, extra = {}) => ({ id, user: { id: userId }, body, html_url: commentUrl(id), performed_via_github_app: null, ...extra });
const STRANGER_ID = 999;

test("unmarkedAnswer names the newest listed human's own comment only when it lacks the decision line", () => {
  const unmarked = issueComment(2, OWNER_ID, "Use `claude auth status`.");
  const pick = (comments) => unmarkedAnswer(comments, HUMANS, BOT);
  assert.equal(pick([issueComment(1, OWNER_ID, "**Decision recorded.** Option 1."), unmarked]), commentUrl(2));
  assert.equal(pick([unmarked, issueComment(3, STRANGER_ID, "Me too.")]), commentUrl(2), "a stranger's comment is not the owner's");
  assert.equal(pick([unmarked, issueComment(3, OWNER_ID, "**Decision recorded.** Via an App.", { performed_via_github_app: { slug: "x" } })]), null, "an App-posted newest comment links no older one");
  for (const body of ["> **Decision recorded.** Quoted.", "Context first.\n**Decision recorded.** Option 2.", "**Decision recorded.**Option 2."]) {
    assert.equal(pick([issueComment(4, OWNER_ID, body)]), commentUrl(4), body);
  }
  for (const body of ["**Decision recorded.** Option 2.", "\n  **Decision recorded.**\nOption 2.", "**Decision recorded.**"]) {
    assert.equal(pick([unmarked, issueComment(5, OWNER_ID, body)]), null, body);
  }
  assert.equal(pick([]), null);
  assert.equal(pick([issueComment(6, STRANGER_ID, "Hi.")]), null);
  for (const html_url of ["https://evil.example/o/r/issues/77#issuecomment-6 extra", "javascript:alert(1)", undefined]) {
    assert.equal(pick([issueComment(6, OWNER_ID, "Hi.", { html_url })]), null, String(html_url));
  }
  // A comment the lane's last outcome comment already answered is not linked again.
  const report = { id: 7, user: { login: BOT }, body: `${ESC}<!-- work-resolve-issue outcome=pushback run=5 -->\nWhy.`, html_url: commentUrl(7) };
  assert.equal(pick([unmarked, report]), null);
  assert.equal(pick([unmarked, report, issueComment(8, OWNER_ID, "Still option 1.")]), commentUrl(8));
  assert.equal(pick([unmarked, { ...report, user: { login: "someone" } }]), commentUrl(2), "only the lanes App's marker counts");
});

test("a pushback links the unmarked comment, shows the decision line, and its retry text names the line", () => {
  const plain = { issueNumber: 77, issueLabels: [], branch: "", changedFiles: [], humanLabel: "needs-human" };
  const pushback = { exit: "pushback", reason: "Which file?", cause: "intent", title: "", summary: "" };
  const linked = decide({ ...plain, outcome: pushback, unmarked: commentUrl(2) }).comment;
  assert.ok(linked.includes(`The newest comment from a listed maintainer, ${commentUrl(2)}, does not start with \`**Decision recorded.**\``), linked);
  assert.ok(linked.includes("\n```\n**Decision recorded.** <answer>\n```\n"), linked);
  const retry = "To retry, answer the question in a comment whose first line is `**Decision recorded.**`, then remove `needs-human` and add `agent-ready` again.";
  assert.ok(linked.endsWith(retry), linked);
  const unlinked = decide({ ...plain, outcome: pushback }).comment;
  assert.ok(!unlinked.includes("newest comment") && unlinked.endsWith(retry), unlinked);
  const stopped = decide({ ...plain, outcome: { exit: "stopped", reason: "Tests failed.", title: "", summary: "" }, unmarked: commentUrl(2) }).comment;
  assert.ok(!stopped.includes(commentUrl(2)) && !stopped.includes("**Decision recorded.**"), stopped);
});

test("main on a pushback reads the issue's comments and links the owner's unmarked one; a failed read leaves it out", async () => {
  const pushback = JSON.stringify({ exit: "pushback", reason: "Which file?", cause: "intent", title: "", summary: "" });
  for (const [route, linked] of [
    [["GET", /\/issues\/77\/comments$/, 200, [issueComment(2, OWNER_ID, "Use `claude auth status`.")]], true],
    [["GET", /\/issues\/77\/comments$/, 500, { message: "boom" }], false],
  ]) {
    await withAsyncDir({ "work-outcome.json": pushback, "lane.json": JSON.stringify({ branch: "" }), "trusted.json": TRUSTED_LIST }, async (dir) => {
      const { fetch, calls } = fakeFetch([
        route,
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: { ...env(dir), TRUSTED_ACTORS: join(dir, "trusted.json") }, fetch }), 0);
      const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
      assert.equal(comment.includes(commentUrl(2)), linked, comment);
      assert.match(comment, /first line is `\*\*Decision recorded\.\*\*`, then remove `needs-human`/);
    });
  }
});

// main reads a pushback's cause from work-outcome.json: a hold-class cause
// reaches a person as that code with no code in the reason.
test("main on a pushback whose work-outcome.json names cause cost-risk holds it as cost-risk", async () => {
  const pushback = JSON.stringify({ exit: "pushback", reason: "This provisions a paid Azure plan.", cause: "cost-risk", title: "", summary: "" });
  await withAsyncDir({ "work-outcome.json": pushback, "lane.json": JSON.stringify({ branch: "" }), "trusted.json": TRUSTED_LIST }, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77\/comments$/, 200, []],
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: { ...env(dir), TRUSTED_ACTORS: join(dir, "trusted.json") }, fetch }), 0);
    const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
    assert.equal(parseReason(comment).reason, "cost", comment);
    assert.ok(calls.some((c) => c.method === "POST" && c.path.endsWith("/labels")), "adds the human-gated label");
  });
});

// stop-routes.json routes every stop. Expected values are the owner's
// direction of 2026-10-27: a person only for an intent, design, security or
// cost reason; a host-only or protected-path stop to the host queue's one
// signal, host-run; a crash or unfinished check back to agent-ready under a
// hard retry cap, and past it a visible stop with no label.
const stoppedPlan = (reason, overrides = {}) =>
  decide({
    outcome: { exit: "stopped", reason, title: "", summary: "" },
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: BRANCH,
    changedFiles: [],
    humanLabel: "needs-human",
    runId: "555",
    ...overrides,
  });

test("route hold: a run's intent, design, security or cost code goes to a person", () => {
  for (const code of ["intent-change", "design-change", "security-risk", "cost-risk"]) {
    const plan = stoppedPlan(`${code}: the issue asks for X but the code needs Y`);
    assert.equal(plan.action, "hand-back", code);
    assert.equal(plan.stop, code);
    assert.deepEqual(plan.addLabels, ["needs-human"], code);
    assert.deepEqual(plan.removeLabels, ["agent-ready"], code);
    assert.ok(plan.comment.startsWith(ESC), code);
  }
});

// #6930 and #6887: the work needs a host the lane cannot reach.
test("route host-run: a run's host-only code adds host-run, removes agent-ready and escalates to no person", () => {
  const plan = stoppedPlan("host-only: the work needs the Claude Code 2.1.296 native bundle on a host");
  assert.equal(plan.action, "host-run");
  assert.deepEqual(plan.addLabels, ["host-run"]);
  assert.deepEqual(plan.removeLabels, ["agent-ready"]);
  assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=host-run run=555 -->\n"), plan.comment);
  assert.ok(!plan.comment.includes("needs-human"), plan.comment);
  assert.match(plan.comment, /2\.1\.296 native bundle/);
  assert.match(plan.comment, /remove `host-run` and add `agent-ready` again/);
  assert.ok(RESUMABLE.has(parseOutcomeMarker(plan.comment).outcome));
});

// Owner decision 2026-10-28: a manual external step goes to attended, never
// to needs-human, which keeps meaning an owner decision.
test("route attended: a run's manual-external code adds attended, removes agent-ready and escalates to no person", () => {
  const plan = stoppedPlan("manual-external: the record needs a DNS change at the registrar");
  assert.equal(plan.action, "attended");
  assert.equal(plan.stop, "manual-external");
  assert.deepEqual(plan.addLabels, ["attended"]);
  assert.deepEqual(plan.removeLabels, ["agent-ready"]);
  assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=attended run=555 -->\n"), plan.comment);
  assert.ok(!plan.comment.includes("needs-human"), plan.comment);
  assert.match(plan.comment, /a DNS change at the registrar/);
  assert.match(plan.comment, /removes `attended` and adds `agent-ready` again/);
  assert.ok(RESUMABLE.has(parseOutcomeMarker(plan.comment).outcome));
});

test("route retry: a crash keeps agent-ready, names the branch and counts toward the cap", () => {
  const plan = decide({ outcome: readOutcome("/nonexistent/work-outcome.json"), issueNumber: 77, issueLabels: [], branch: BRANCH, changedFiles: [], runId: "555" });
  assert.equal(plan.action, "retry");
  assert.deepEqual(plan.addLabels, []);
  assert.deepEqual(plan.removeLabels, []);
  assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=retry run=555 -->\n"), plan.comment);
  assert.ok(plan.comment.includes(BRANCH), plan.comment);
  assert.ok(RESUMABLE.has("retry"), "the next run continues the branch");
});

test("route fail: a retry past limits.stop-retries removes agent-ready and adds no label", () => {
  const plan = decide({ outcome: readOutcome("/nonexistent/work-outcome.json"), issueNumber: 77, issueLabels: [], branch: BRANCH, changedFiles: [], runId: "555" });
  assert.equal(capRetries(plan, 1, { "stop-retries": 2 }).action, "retry");
  assert.match(capRetries(plan, 1, { "stop-retries": 2 }).comment, /retry 2 of 2/);
  for (const [retries, cap] of [[2, 2], [0, 0]]) {
    const spent = capRetries(plan, retries, { "stop-retries": cap });
    assert.equal(spent.action, "fail", `${retries} of ${cap}`);
    assert.deepEqual(spent.addLabels, []);
    assert.deepEqual(spent.removeLabels, ["agent-ready"]);
    assert.ok(spent.comment.startsWith("<!-- work-resolve-issue outcome=failed run=555 -->\n"), spent.comment);
    assert.match(spent.comment, /`outcome-unread`/);
    assert.match(spent.comment, /limits\.stop-retries/);
    assert.ok(!spent.comment.includes("work-items:escalation"), spent.comment);
  }
  const hold = stoppedPlan("design-change: Unclear.");
  assert.equal(capRetries(hold, 9, { "stop-retries": 0 }), hold, "a plan that is not a retry is left as it is");
});

// Owner direction 2026-10-29: a stop with no code names no intent, design,
// security or cost finding, so it retries once and then fails, never a person.
test("a stop with no code retries once, then fails, and never goes to a person", () => {
  const plan = stoppedPlan("I could not finish this.");
  assert.equal(plan.stop, "stopped");
  assert.equal(plan.action, "retry");
  assert.deepEqual(plan.addLabels, []);
  assert.deepEqual(plan.removeLabels, []);
  assert.match(plan.comment, /retry 1 of 1/);
  const spent = capRetries(plan, 1, { "stop-retries": 2 });
  assert.equal(spent.action, "fail");
  assert.deepEqual(spent.addLabels, []);
  assert.deepEqual(spent.removeLabels, ["agent-ready"]);
  assert.ok(!spent.comment.includes("work-items:escalation"), spent.comment);
  assert.equal(capRetries(plan, 0, { "stop-retries": 0 }).action, "fail", "the lane-wide cap still bounds it");
});

// A run that waits on an unmerged pull request names no owner reason, so it
// keeps agent-ready instead of going to a person.
test("route wait: a blocked-by-pr code keeps agent-ready and names the pull request in its marker", () => {
  const plan = stoppedPlan("blocked-by-pr: #10743 adds the binding this needs; see also #77");
  assert.equal(plan.action, "wait");
  assert.equal(plan.pr, "10743");
  assert.deepEqual(plan.addLabels, []);
  assert.deepEqual(plan.removeLabels, []);
  assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=wait pr=10743 run=555 -->\n"), plan.comment);
  assert.match(plan.comment, /once #10743 merges or closes/);
  assert.deepEqual(parseOutcomeMarker(plan.comment), { outcome: "wait", resets: null, run: "555", onResumed: false, pr: "10743" });
  assert.ok(RESUMABLE.has("wait"), "the next run continues the branch");
  assert.equal(capRetries(plan, 2, { "stop-retries": 2 }).action, "fail", "waits are bounded too");
  assert.equal(waitedPull("blocked-by-pr: waits on ＃12", 77), "12");
  assert.equal(waitedPull("blocked-by-pr: nothing named", 77), "");
});

test("route close: already-done and report-delivered close the issue as completed, to no person", () => {
  for (const reason of ["already-done: both items are on main at abb359be", "report-delivered: the report is below"]) {
    const plan = stoppedPlan(reason, { issueLabels: ["agent-ready", "work-class: read-only"], branch: "" });
    assert.equal(plan.action, "close", reason);
    assert.deepEqual(plan.addLabels, []);
    assert.deepEqual(plan.removeLabels, ["agent-ready"]);
    assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=closed run=555 -->\n"), plan.comment);
    assert.match(plan.comment, /closes the issue as completed/);
    assert.ok(plan.comment.includes(reason), plan.comment);
  }
  // The close comment reads back as its stop and the run's own reason, which
  // isTrustedClose re-checks (owner Q9, 2026-10-29).
  const done = stoppedPlan("already-done: #5 shipped it\nand abb359be too", { issueLabels: ["agent-ready", "work-class: read-only"], branch: "" });
  assert.deepEqual(closeStop(done.comment), { stop: "already-done", reason: "already-done: ＃5 shipped it\nand abb359be too" });
  const report = stoppedPlan("report-delivered: the report is below", { issueLabels: ["agent-ready", "work-class: read-only"], branch: "" });
  assert.equal(closeStop(report.comment).stop, "report-delivered");
  assert.equal(closeStop(stoppedPlan("the tests failed").comment), null, "a retry comment is no close");
  // A report closes only a read-only issue the run committed nothing for.
  assert.equal(stoppedPlan("report-delivered: the report is below").action, "retry");
  for (const opts of [{}, { issueLabels: ["agent-ready"], branch: "" }, { issueLabels: ["agent-ready", "work-class: read-only"], branch: "work/7" }]) {
    const retry = stoppedPlan("report-delivered: the report is below", opts);
    assert.equal(retry.action, "retry");
    assert.match(retry.comment, /so it retries instead of closing\./, retry.comment);
  }
});

// main against a fake API for the routes whose effect needs a read first.
// `trusted` adds the trusted-actor list, whose humans' pull requests a wait accepts.
const stopRun = async ({ reason, summary = "", routes, trusted = false }) => {
  let result;
  const files = { "work-outcome.json": JSON.stringify({ exit: "stopped", reason, summary }), ...(trusted && { "trusted.json": TRUSTED_LIST }) };
  await withAsyncDir(files, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ...routes,
      ["GET", /\/issues\/77\/comments/, 200, []],
      ["GET", /\/issues\/77\/events/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
      ["DELETE", /\/issues\/77\/labels\//, 200, []],
      ["PATCH", /\/issues\/77$/, 200, {}],
    ]);
    result = { code: await main({ env: { ...env(dir), ...(trusted && { TRUSTED_ACTORS: join(dir, "trusted.json") }) }, fetch }), calls };
  });
  return result;
};

const APP_USER = { login: BOT, type: "Bot", id: 337595936 };

test("main waits on an open pull request, and retries when the named one is not open", async () => {
  const open = await stopRun({ reason: "blocked-by-pr: #5 adds the helper", routes: [["GET", /\/pulls\/5$/, 200, { state: "open", merged_at: null, user: APP_USER }]] });
  assert.equal(open.code, 0);
  assert.ok(!open.calls.some((c) => c.method === "DELETE" || c.method === "PATCH"));
  assert.match(open.calls.find((c) => c.method === "POST").body.body, /^<!-- work-resolve-issue outcome=wait pr=5 run=123 -->/);
  const merged = await stopRun({ reason: "blocked-by-pr: #5 adds the helper", routes: [["GET", /\/pulls\/5$/, 200, { state: "closed", merged_at: "2026-10-29T14:07:27Z" }]] });
  assert.equal(merged.code, 0);
  assert.match(merged.calls.find((c) => c.method === "POST").body.body, /^<!-- work-resolve-issue outcome=retry run=123 -->/);
  assert.ok(!merged.calls.some((c) => c.method === "DELETE"));
  assert.match(merged.calls.find((c) => c.method === "POST").body.body, /#5 is not an open pull request here, so it retries instead\./);
});

// Security review on #10978: anyone can open a pull request, so a wait on one
// only the lanes App or a listed human opened, as closed-by-open-pr reads it.
test("main waits only on an open pull request the lanes App or a listed human opened, and retries on anyone else's", async () => {
  const waitOn = (user, trusted = false) =>
    stopRun({ reason: "blocked-by-pr: #5 adds the helper", trusted, routes: [["GET", /\/pulls\/5$/, 200, { state: "open", merged_at: null, user }]] });
  const marker = async (run) => (await run).calls.find((c) => c.method === "POST").body.body;
  assert.match(await marker(waitOn({ login: "kyle-sexton", type: "User", id: OWNER_ID }, true)), /^<!-- work-resolve-issue outcome=wait pr=5 run=123 -->/);
  for (const [name, user, trusted] of [
    ["an outsider", { login: "someone", type: "User", id: 555 }, true],
    ["another App", { login: "other-app[bot]", type: "Bot", id: 556 }, true],
    ["a Bot with a listed human's id", { login: "other-app[bot]", type: "Bot", id: OWNER_ID }, true],
    ["a listed human with no readable list", { login: "kyle-sexton", type: "User", id: OWNER_ID }, false],
  ]) {
    const body = await marker(waitOn(user, trusted));
    assert.match(body, /^<!-- work-resolve-issue outcome=retry run=123 -->/, name);
    assert.match(body, /#5 was not opened by the lanes App or a listed human, so it retries instead\./, name);
  }
});

test("main closes an already-done issue only when its cited commit is on the default branch and cites the issue", async () => {
  const tiedCommit = ["GET", /\/commits\/abb359be$/, 200, { commit: { message: "fix(lane): resolve both items (#80)\n\nFixes #77", committer: { date: "2026-10-28T00:00:00Z" } }, files: [] }];
  const done = await stopRun({
    reason: "already-done: both items are on main at abb359be",
    routes: [["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }], ["GET", /\/compare\/abb359be\.\.\.main$/, 200, { status: "ahead" }], tiedCommit],
  });
  assert.equal(done.code, 0);
  assert.deepEqual(done.calls.find((c) => c.method === "PATCH").body, { state: "closed", state_reason: "completed" });
  assert.ok(done.calls.some((c) => c.method === "DELETE" && c.path.endsWith("/labels/agent-ready")));
  const unproven = await stopRun({
    reason: "already-done: both items are on main at abb359be",
    routes: [["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }], ["GET", /\/compare\/abb359be\.\.\.main$/, 200, { status: "diverged" }], tiedCommit],
  });
  assert.ok(!unproven.calls.some((c) => c.method === "PATCH"), "no proof, no close");
  assert.match(unproven.calls.find((c) => c.method === "POST").body.body, /^<!-- work-resolve-issue outcome=retry run=123 -->/);
  assert.match(unproven.calls.find((c) => c.method === "POST").body.body, /cites no pull request merged into the default branch, or commit on it, made after the issue opened whose commit message closes this issue,/);
  // Run 40844966342: a release commit on main closed an issue it never touched.
  const release = await stopRun({
    reason: "already-done: both items are on main at abb359be",
    routes: [
      ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
      ["GET", /\/compare\/abb359be\.\.\.main$/, 200, { status: "ahead" }],
      ["GET", /\/commits\/abb359be$/, 200, { commit: { message: "chore(release): cut 3.2.0 (#77)", committer: { date: "2026-10-28T00:00:00Z" } }, files: [{ filename: "CHANGELOG.md" }] }],
    ],
  });
  assert.ok(!release.calls.some((c) => c.method === "PATCH"), "an unrelated commit on main is no proof");
  assert.match(release.calls.find((c) => c.method === "POST").body.body, /^<!-- work-resolve-issue outcome=retry run=123 -->/);
  const later = await stopRun({
    reason: "already-done: effaced text, then the commit abb359be",
    routes: [["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }], ["GET", /\/compare\/abb359be\.\.\.main$/, 200, { status: "identical" }], tiedCommit],
  });
  assert.ok(later.calls.some((c) => c.method === "PATCH"), "a hex-looking word before the SHA hides nothing");
});

// doneEvidence against a fake client: each route answers its path, and a path
// no route names fails the read, as a GitHub error would. An issue never
// reopened answers its event list empty unless a route says otherwise.
const NO_EVENTS = [/\/issues\/77\/events\?per_page=100&page=1$/, []];
const evidenceClient = (routes) => async (method, path) => {
  const route = [...routes, NO_EVENTS].find(([pattern]) => pattern.test(path));
  if (method !== "GET" || !route) {
    throw new Error(`no route for ${method} ${path}`);
  }
  return route[1];
};
const ON_MAIN = [
  [/\/repos\/o\/r$/, { default_branch: "main" }],
  [/\/compare\/abb359be\.\.\.main$/, { status: "ahead" }],
];

// The issue, opened before every change below; its body names a path, which
// proves nothing.
const EVIDENCE_ISSUE = [/\/issues\/77$/, { created_at: "2026-10-01T00:00:00Z", body: "The table in `docs/lanes.md:12` is stale." }];
const MERGE_SHA = "cafe".repeat(10);
// A merged pull request #5 whose merge commit says `message`; its title and
// body, which stay editable after the merge, say `body` (by default the same).
// A null message leaves the merge commit unreadable.
const evidencePull = (message, { body = message, base = "main", mergedAt = "2026-10-29T14:07:27Z", files = [{ filename: "docs/lanes.md" }] } = {}) =>
  evidenceClient([
    [/\/repos\/o\/r$/, { default_branch: "main" }],
    [/\/pulls\/5$/, { merged_at: mergedAt, merge_commit_sha: MERGE_SHA, base: { ref: base }, title: "fix: tidy", body }],
    [/\/pulls\/5\/files/, files],
    ...(message === null ? [] : [[new RegExp(`/commits/${MERGE_SHA}$`), { commit: { message, committer: { date: mergedAt } } }]]),
    EVIDENCE_ISSUE,
  ]);

test("doneEvidence takes a merged pull request only when its merge commit closes the issue", async () => {
  const reason = "already-done: #5 shipped it";
  assert.equal(await doneEvidence(evidencePull("Tidies an unrelated table."), "/repos/o/r", reason, 77), false, "an unrelated merged PR");
  assert.equal(await doneEvidence(evidencePull("Closes #770"), "/repos/o/r", reason, 77), false, "#770 is not #77");
  assert.equal(await doneEvidence(evidencePull("fix: tidy (#5)\n\nCloses #77"), "/repos/o/r", reason, 77), true);
});

// Re-review on #10978: a pull request's title and body stay editable after
// it merges, so only its merge commit, which a squash fills from the body, counts.
test("doneEvidence reads the closing keyword from the merge commit, not the pull request's current body", async () => {
  const reason = "already-done: #5 shipped it";
  assert.equal(await doneEvidence(evidencePull("fix: tidy (#5)", { body: "Closes #77" }), "/repos/o/r", reason, 77), false, "a body edited after the merge");
  assert.equal(await doneEvidence(evidencePull("fix: tidy (#5)\n\nCloses #77", { body: "Tidies a table." }), "/repos/o/r", reason, 77), true);
  assert.equal(await doneEvidence(evidencePull(null, { body: "Closes #77" }), "/repos/o/r", reason, 77), false, "an unreadable merge commit");
});

// Security review on #10978: only a GitHub closing keyword says a change
// finishes the issue; a Refs line, a follow-up or a squash suffix does not.
test("doneEvidence counts a citation only as a closing keyword before #<issue>", async () => {
  const reason = "already-done: #5 shipped it";
  for (const [message, closes] of [
    ["Refs: #77", false],
    ["Filed #77 for follow-up", false],
    ["Tidy the table (#77)", false],
    ["Closes #770", false],
    ["fix #77a", false],
    ["Fixes #77", true],
    ["fixes: #77", true],
    ["RESOLVED #77.", true],
    ["Part of it.\n\nClosed #77", true],
    ["This does not fix #77", false],
    ['Revert "fix: tidy (#5)"\n\nThis reverts commit abc1234.\n\nCloses #77', false],
  ]) {
    assert.equal(await doneEvidence(evidencePull(message), "/repos/o/r", reason, 77), closes, message);
  }
});

test("doneEvidence takes a merged pull request only into the default branch and after the issue opened", async () => {
  const reason = "already-done: #5 shipped it";
  assert.equal(await doneEvidence(evidencePull("Closes #77", { base: "release/3.x" }), "/repos/o/r", reason, 77), false, "merged into another branch");
  assert.equal(await doneEvidence(evidencePull("Closes #77", { mergedAt: "2026-09-30T00:00:00Z" }), "/repos/o/r", reason, 77), false, "merged before the issue opened");
  assert.equal(await doneEvidence(evidencePull("Closes #77", { mergedAt: "not a date" }), "/repos/o/r", reason, 77), false, "an unreadable merge time");
});

// Re-review on #10978: lane pull requests carry `Closes #N`, so a change to a
// path the issue names is no evidence of its own.
test("doneEvidence takes no change to a path the issue names as evidence", async () => {
  assert.equal(await doneEvidence(evidencePull("Tidies a file."), "/repos/o/r", "already-done: #5 shipped it", 77), false, "a pull request");
  const commit = evidenceClient([
    ...ON_MAIN,
    [/\/commits\/abb359be$/, { commit: { message: "fix: tidy", committer: { date: "2026-10-28T00:00:00Z" } }, files: [{ filename: "docs/lanes.md" }] }],
    EVIDENCE_ISSUE,
  ]);
  assert.equal(await doneEvidence(commit, "/repos/o/r", "already-done: on main at abb359be", 77), false, "a commit");
});

test("doneEvidence takes a default-branch commit only when its message closes the issue", async () => {
  const reason = "already-done: on main at abb359be";
  const commit = (message, date = "2026-10-28T00:00:00Z") =>
    evidenceClient([...ON_MAIN, [/\/commits\/abb359be$/, { commit: { message, committer: { date } }, files: [] }], EVIDENCE_ISSUE]);
  assert.equal(await doneEvidence(commit("fix(lane): drop the stale row\n\nFixes #77"), "/repos/o/r", reason, 77), true);
  assert.equal(await doneEvidence(commit("fix(lane): drop the stale row\n\nRefs #77"), "/repos/o/r", reason, 77), false, "a Refs line closes nothing");
  assert.equal(await doneEvidence(commit("chore(release): cut 3.2.0"), "/repos/o/r", reason, 77), false, "an unrelated release commit");
  assert.equal(await doneEvidence(commit("fix: tidy\n\nFixes #77", "2026-09-30T00:00:00Z"), "/repos/o/r", reason, 77), false, "committed before the issue opened");
});

// Review on #10978: a reason may cite an issue before the pull request that
// closed it, so each cited number is tried, not only the first.
test("doneEvidence tries each pull request the reason cites", async () => {
  const github = evidenceClient([
    [/\/repos\/o\/r$/, { default_branch: "main" }],
    [/\/pulls\/60$/, { merged_at: "2026-10-29T14:07:27Z", merge_commit_sha: MERGE_SHA, base: { ref: "main" } }],
    [new RegExp(`/commits/${MERGE_SHA}$`), { commit: { message: "fix: tidy (#60)\n\nCloses #77" } }],
    EVIDENCE_ISSUE,
  ]);
  assert.equal(await doneEvidence(github, "/repos/o/r", "already-done: duplicate of #50, fixed by #60", 77), true);
  assert.equal(await doneEvidence(github, "/repos/o/r", "already-done: duplicate of #50, #51 and #52, fixed by #60", 77), false, "past the first three numbers");
});

// Security review on #10978: a person who reopened the issue after the cited
// merge said the work is not done, so that merge proves nothing; work merged
// after the reopen does, and an event list that does not read proves nothing.
test("doneEvidence takes only work merged after the issue was last reopened", async () => {
  const reason = "already-done: #5 shipped it";
  const pull = (events) =>
    evidenceClient([
      [/\/repos\/o\/r$/, { default_branch: "main" }],
      [/\/pulls\/5$/, { merged_at: "2026-10-29T14:07:27Z", merge_commit_sha: MERGE_SHA, base: { ref: "main" } }],
      [new RegExp(`/commits/${MERGE_SHA}$`), { commit: { message: "fix: tidy (#5)\n\nCloses #77" } }],
      [/\/issues\/77\/events\?/, events],
      EVIDENCE_ISSUE,
    ]);
  const reopen = (at) => ({ event: "reopened", created_at: at });
  assert.equal(await doneEvidence(pull([reopen("2026-10-29T15:00:00Z")]), "/repos/o/r", reason, 77), false, "reopened after the merge");
  assert.equal(await doneEvidence(pull([reopen("2026-10-20T00:00:00Z"), { event: "closed", created_at: "2026-10-21T00:00:00Z" }]), "/repos/o/r", reason, 77), true, "reopened before the merge");
  assert.equal(await doneEvidence(pull(null), "/repos/o/r", reason, 77), false, "an unreadable event list");
});

test("doneEvidence proves nothing when a read fails", async () => {
  const commit = [/\/commits\/abb359be$/, { commit: { message: "Fixes #77", committer: { date: "2026-10-28T00:00:00Z" } }, files: [] }];
  // The issue read fails, so its time cannot be read.
  assert.equal(await doneEvidence(evidenceClient([...ON_MAIN, commit]), "/repos/o/r", "already-done: abb359be", 77), false);
  // The commit read fails, though the compare says it is on main.
  assert.equal(await doneEvidence(evidenceClient([...ON_MAIN, EVIDENCE_ISSUE]), "/repos/o/r", "already-done: abb359be", 77), false);
  // The default branch read fails.
  assert.equal(await doneEvidence(evidenceClient([commit, EVIDENCE_ISSUE]), "/repos/o/r", "already-done: abb359be", 77), false);
  // Each read answering, the same evidence holds.
  assert.equal(await doneEvidence(evidenceClient([...ON_MAIN, commit, EVIDENCE_ISSUE]), "/repos/o/r", "already-done: abb359be", 77), true);
});

test("main posts a delivered report and closes the issue", async () => {
  const run = await stopRun({ reason: "report-delivered: the audit found three stale rows", summary: "Rows 4, 9 and 12 name retired lanes.", routes: [] });
  assert.equal(run.code, 0);
  assert.match(run.calls.find((c) => c.method === "POST").body.body, /three stale rows/);
  assert.match(run.calls.find((c) => c.method === "POST").body.body, /The run's report:\n\n> Rows 4, 9 and 12 name retired lanes\./);
  assert.deepEqual(run.calls.find((c) => c.method === "PATCH").body, { state: "closed", state_reason: "completed" });
});

test("retries count the App's retry markers since a listed human last added agent-ready, not this run's", () => {
  const marker = (outcome, run, at) => ({ user: { login: "melodic-automation-lanes[bot]" }, body: `<!-- work-resolve-issue outcome=${outcome} run=${run} -->`, created_at: at });
  const comments = [marker("retry", "1", "2026-10-17T01:00:00Z"), marker("retry", "2", "2026-10-17T03:00:00Z"), marker("turn-cap", "3", "2026-10-17T04:00:00Z"), marker("retry", "555", "2026-10-17T05:00:00Z")];
  const events = [{ event: "labeled", label: { name: "agent-ready" }, actor: { login: "kyle-sexton", id: 153232337 }, created_at: "2026-10-17T02:00:00Z" }];
  const args = { comments, events, bot: "melodic-automation-lanes[bot]", humans: new Set([153232337]), runId: "555" };
  assert.equal(countRestarts({ ...args, outcome: "retry" }), 1);
  assert.equal(countRestarts({ ...args, outcome: "turn-cap" }), 1);
});

test("main fails a crashed run whose retries are spent: agent-ready off, no label, no person", async () => {
  const earlier = (run, at) => ({ user: { login: "melodic-automation-lanes[bot]" }, body: `<!-- work-resolve-issue outcome=retry run=${run} -->`, created_at: at });
  await withAsyncDir({}, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["GET", /\/issues\/77\/comments$/, 200, [earlier("1", "2026-10-17T01:00:00Z"), earlier("2", "2026-10-17T02:00:00Z")]],
      ["GET", /\/issues\/77\/events$/, 200, []],
      ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: env(dir), fetch }), 0);
    assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/labels")), JSON.stringify(calls));
    assert.ok(calls.some((c) => c.method === "DELETE" && c.path.endsWith("/labels/agent-ready")));
    const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
    assert.equal(parseOutcomeMarker(comment).outcome, "failed");
  });
});

test("main hands a run to a person when COLLECT_REFUSED is exactly true, and retries it otherwise", async () => {
  for (const [value, held] of [["true", true], ["TRUE", false], ["", false]]) {
    await withAsyncDir({}, async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ...HISTORY,
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: { ...env(dir), COLLECT_REFUSED: value }, fetch }), 0);
      const label = calls.find((c) => c.method === "POST" && c.path.endsWith("/labels"));
      assert.equal(label?.body.labels[0] === "needs-human", held, value);
      assert.equal(calls.some((c) => c.method === "DELETE"), held, value);
    });
  }
});

test("main keeps agent-ready on a spent retry whose failed marker could not be posted, so the stranded sweep still finds it", async () => {
  const earlier = (run, at) => ({ user: { login: "melodic-automation-lanes[bot]" }, body: `<!-- work-resolve-issue outcome=retry run=${run} -->`, created_at: at });
  await withAsyncDir({}, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["GET", /\/issues\/77\/comments$/, 200, [earlier("1", "2026-10-17T01:00:00Z"), earlier("2", "2026-10-17T02:00:00Z")]],
      ["GET", /\/issues\/77\/events$/, 200, []],
      ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 500, { message: "boom" }],
    ]);
    assert.equal(await main({ env: env(dir), fetch }), 1);
    assert.ok(!calls.some((c) => c.method === "DELETE"), JSON.stringify(calls));
  });
});

test("main on a rerun after its own retry marker posts nothing again", async () => {
  const own = { user: { login: "melodic-automation-lanes[bot]" }, body: "<!-- work-resolve-issue outcome=retry run=123 -->", created_at: "2026-10-17T05:00:00Z" };
  await withAsyncDir({}, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["GET", /\/issues\/77\/comments$/, 200, [own]],
      ["GET", /\/issues\/77\/events$/, 200, []],
    ]);
    assert.equal(await main({ env: env(dir), fetch }), 0);
    assert.deepEqual(calls.filter((c) => c.method !== "GET"), []);
  });
});

// The owner's rule: a patch not proven clear of a credential holds, whatever
// exit or forgeable record the run left beside it.
test("a patch-credential escalation and a scan's output refusal hold past any exit or record", () => {
  const unread = () => readOutcome("/nonexistent/work-outcome.json");
  const refused = () => ({ ...unread(), stop: "scan-refused-output", reason: SCAN_REFUSALS.output });
  const base = { issueNumber: 77, issueLabels: ["agent-ready"], branch: "", changedFiles: [], humanLabel: "needs-human", runId: "555" };
  const records = { turnCap: { cap: 50 }, turnCapRestarts: 0, limits: { ...LIMIT_DEFAULTS, "turn-cap-restarts": 1 } };
  for (const [name, args] of [
    ["stopped", { outcome: { exit: "stopped", reason: "Tests failed.", title: "", summary: "" }, escalation: "patch-credential" }],
    ["turn cap", { outcome: unread(), escalation: "patch-credential", ...records }],
    ["limit", { outcome: unread(), escalation: "patch-credential", limit: { resets: null } }],
    ["funding", { outcome: unread(), escalation: "patch-credential", funding: { regain: null } }],
  ]) {
    const plan = decide({ ...base, ...args });
    assert.equal(plan.action, "hand-back", name);
    assert.equal(plan.stop, "patch-credential", name);
    assert.deepEqual(plan.addLabels, ["needs-human"], name);
    assert.match(plan.comment, /credential shape/, name);
    assert.doesNotMatch(plan.comment, /reported done/, name);
  }
  for (const [name, args] of [
    ["turn cap", records],
    ["limit", { limit: { resets: null } }],
    ["funding", { funding: { regain: null } }],
  ]) {
    const plan = decide({ ...base, outcome: refused(), ...args });
    assert.equal(plan.action, "hand-back", name);
    assert.equal(plan.stop, "scan-refused-output", name);
    assert.deepEqual(plan.addLabels, ["needs-human"], name);
  }
});

test("an escalation that does not hold still yields to the turn-cap restart", () => {
  const plan = decide({
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: "",
    changedFiles: [],
    humanLabel: "needs-human",
    runId: "555",
    outcome: readOutcome("/nonexistent/work-outcome.json"),
    escalation: "patch-invalid",
    turnCap: { cap: 50 },
    turnCapRestarts: 0,
    limits: { ...LIMIT_DEFAULTS, "turn-cap-restarts": 1 },
  });
  assert.notEqual(plan.stop, "patch-invalid");
  assert.deepEqual(plan.addLabels ?? [], []);
});

test("a scan fault retries with no person, up to limits.stop-retries, and every scan refusal has a route", () => {
  for (const kind of Object.keys(SCAN_REFUSALS)) assert.ok(Object.hasOwn(STOP_ROUTES, `scan-refused-${kind}`), kind);
  const outcome = { ...readOutcome("/nonexistent/work-outcome.json"), stop: "scan-refused-fault", reason: SCAN_REFUSALS.fault };
  const plan = decide({ issueNumber: 77, issueLabels: ["agent-ready"], branch: "", changedFiles: [], humanLabel: "needs-human", runId: "555", outcome });
  assert.equal(plan.action, "retry");
  assert.equal(plan.stop, "scan-refused-fault");
  assert.deepEqual(plan.addLabels ?? [], []);
  assert.equal(capRetries(plan, 1, { "stop-retries": 2 }).action, "retry");
  const spent = capRetries(plan, 2, { "stop-retries": 2 });
  assert.equal(spent.action, "fail");
  assert.deepEqual(spent.addLabels ?? [], []);
});

test("scan markers: only fault, or fault beside patch, reads as fault; anything else beside either reads as output", () => {
  for (const [base, rungUp, want] of [
    ["fault", "", "fault"],
    ["fault", "patch", "fault"],
    ["patch", "fault", "fault"],
    ["fault", "output", "output"],
    ["output", "fault", "output"],
    ["fault", "forged", "output"],
  ]) {
    const dir = tempDir("scan-refused-");
    try {
      writeFileSync(join(dir, "scan-refused-1.txt"), `${base}\n`);
      if (rungUp) writeFileSync(join(dir, "scan-refused-1-rung-up.txt"), `${rungUp}\n`);
      assert.equal(readScanRefusal(dir, "1"), want, `${base} then ${rungUp}`);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

test("a current attempt with a patch and an output scan marker reads as output, in either order", () => {
  for (const [base, rungUp] of [["patch", "output"], ["output", "patch"]]) {
    const dir = tempDir("scan-refused-");
    try {
      writeFileSync(join(dir, "scan-refused-1.txt"), `${base}\n`);
      writeFileSync(join(dir, "scan-refused-1-rung-up.txt"), `${rungUp}\n`);
      assert.equal(readScanRefusal(dir, "1"), "output", `${base} then ${rungUp}`);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

// A reuse PR holds on exactly decide()'s conditions plus its own leak scan
// (mustHold), and a clean one opens with no hold line. Each case pairs a clean
// reuse, which carries none, with the same reuse and one condition changed.
const CLEAN_CHECKS = { tip: TIP, results: [{ check: FRAGMENTS, exit: 0 }], scan: "clean" };
const CLEAN_REUSE = {
  issueNumber: 77,
  issueLabels: ["agent-ready", "work-class: scoped"],
  branch: lane(400),
  changedFiles: ["README.md"],
  holdPaths: HOLD_GLOBS,
  humanMerge: false,
  checks: CLEAN_CHECKS,
};
const reuseHeld = (overrides = {}) => reusePlan({ ...CLEAN_REUSE, ...overrides }).body.split("\n").includes(HOLD_LINE);
const CAPPED = Array.from({ length: 300 }, (_, i) => `docs/page-${i}.md`);
const HOLD_CASES = {
  "the denied paths cannot be read": { holdPaths: null },
  "the compare request failed": { changedFiles: null },
  "the listing is cut at the cap while a path is denied": { changedFiles: CAPPED },
  "a changed path is denied": { changedFiles: ["README.md", ".github/workflows/x.yml"] },
  "the issue is labeled untrusted-provenance": { issueLabels: ["agent-ready", "work-class: untrusted-provenance"] },
  "a trusted labeler set merge: human": { humanMerge: true },
};
// A reuse's scan word, when it is anything but clean: lint-repo's gitleaks
// does not cover what scanLeak flags, so a missing scan holds like a finding.
const SCAN_CASES = {
  "the leak scan found something": { checks: { ...CLEAN_CHECKS, scan: "found" } },
  "the leak scan failed": { checks: { ...CLEAN_CHECKS, scan: "failed" } },
  "the leak scan never ran": { checks: { tip: TIP, results: CLEAN_CHECKS.results } },
  "the runner checks and their scan are missing": { checks: null },
};

for (const [name, overrides] of Object.entries({ ...HOLD_CASES, ...SCAN_CASES })) {
  test(`a reuse PR holds when ${name}, and the same clean reuse does not`, () => {
    assert.equal(reuseHeld(), false, "the clean reuse");
    assert.equal(reuseHeld(overrides), true, name);
  });
}

test("a reuse PR with a clean scan does not hold only because no runner check reported, and says what checks its head", () => {
  const { body } = reusePlan({ ...CLEAN_REUSE, checks: { ...CLEAN_CHECKS, results: [] } });
  assert.ok(!body.split("\n").includes(HOLD_LINE), body);
  assert.ok(body.includes("ci-status, pr-verify and the security review lane check the head before it merges."), body);
  assert.ok(!body.includes("a person reviews the diff"), body);
});

test("a clean reuse PR names the clean leak scan and leaves the person's review out", () => {
  const { body } = reusePlan(CLEAN_REUSE);
  assert.ok(body.startsWith("Closes #77\n\n## Summary\n"), body);
  assert.ok(body.includes("leak scan read everything the branch changes"), body);
  assert.ok(!body.includes("a person reviews the diff"), body);
  const found = reusePlan({ ...CLEAN_REUSE, ...SCAN_CASES["the leak scan found something"] }).body;
  assert.ok(found.includes("leak scan found a credential shape") && found.includes("a person reviews the diff"), found);
});

test("a capped listing holds a reuse PR only while some path is denied", () => {
  assert.equal(reuseHeld({ changedFiles: CAPPED, holdPaths: [] }), false);
  assert.equal(reuseHeld({ changedFiles: CAPPED }), true);
});

// A failed runner check is not a reason for a person: the PR opens, its
// Verification section names the failure, and its own CI stays red until fixed.
test("a reuse PR whose runner check failed opens unheld and names the failure in Verification", () => {
  const plan = reusePlan({ ...CLEAN_REUSE, checks: { ...CLEAN_CHECKS, results: [{ check: FRAGMENTS, exit: 1 }] } });
  assert.equal(plan.hold, false);
  assert.ok(!plan.body.split("\n").includes(HOLD_LINE), plan.body);
  assert.ok(plan.body.includes(`${FRAGMENTS}: failed (exit 1)`), plan.body);
  assert.ok(plan.body.includes("ci-status, pr-verify and the security review lane check the head before it merges."), plan.body);
});

test("a reuse PR whose runner check failed still holds on a leak scan that is not clean", () => {
  const failed = [{ check: FRAGMENTS, exit: 1 }];
  for (const checks of [{ ...CLEAN_CHECKS, results: failed, scan: "found" }, { ...CLEAN_CHECKS, results: failed, scan: "failed" }, { tip: TIP, results: failed }]) {
    const plan = reusePlan({ ...CLEAN_REUSE, checks });
    assert.equal(plan.hold, true, JSON.stringify(checks));
    assert.ok(plan.body.split("\n").includes(HOLD_LINE), plan.body);
  }
});

test("mustHold: a reuse holds on any scan word but clean; a failed runner check and runner checks that did not report hold nothing", () => {
  const facts = { issueLabels: CLEAN_REUSE.issueLabels, humanMerge: false, holdPaths: HOLD_GLOBS, changedFiles: ["README.md"], reused: true };
  assert.equal(mustHold({ ...facts, checks: CLEAN_CHECKS }), false, "clean reuse");
  assert.equal(mustHold({ ...facts, checks: { tip: TIP, results: CLEAN_CHECKS.results } }), true, "scan missing");
  assert.equal(mustHold({ ...facts, checks: null }), true, "checks and scan missing");
  assert.equal(mustHold({ ...facts, checks: { ...CLEAN_CHECKS, scan: "failed" } }), true, "scan failed");
  assert.equal(mustHold({ ...facts, checks: { ...CLEAN_CHECKS, scan: "found" } }), true, "scan found");
  assert.equal(mustHold({ ...facts, checks: { ...CLEAN_CHECKS, results: [{ check: FRAGMENTS, exit: 1 }] } }), false, "a failed check");
  assert.equal(mustHold({ ...facts, checks: { ...CLEAN_CHECKS, results: [] } }), false, "reuse, clean scan, no runner check reported");
  assert.equal(mustHold({ ...facts, reused: false, checks: null }), false, "no reuse, runner checks missing");
  assert.equal(mustHold({ ...facts, reused: false, checks: { tip: TIP, results: [{ check: FRAGMENTS, exit: 1 }] } }), false, "no reuse, a failed check");
});

test("decide() and reusePlan() hold on the same runner facts, through one mustHold", () => {
  const held = (body) => body.split("\n").includes(HOLD_LINE);
  for (const [name, overrides] of Object.entries({ "nothing": {}, ...HOLD_CASES })) {
    // decide() stops a done run whose checks are missing or failed before it reaches the hold.
    if (overrides.checks !== undefined) continue;
    const facts = { ...CLEAN_REUSE, ...overrides };
    const plan = decide({ outcome: done, branch: BRANCH, ...facts });
    assert.equal(plan.action, "open-pr", name);
    assert.equal(held(plan.body), mustHold(facts), `decide(): ${name}`);
    assert.equal(held(reusePlan(facts).body), mustHold({ ...facts, reused: true }), `reusePlan(): ${name}`);
    assert.equal(held(plan.body), held(reusePlan(facts).body), name);
  }
});

test("readChecks carries a reused branch's scan word, reads an unknown one as failed, and adds none to a record without one", () => {
  const record = (scan) => JSON.stringify({ version: 1, branch: BRANCH, tip: CHECKED_TIP, results: [], ...(scan === undefined ? {} : { scan }) });
  for (const word of ["clean", "found", "failed"]) assert.equal(readChecks(record(word), { branch: BRANCH }).scan, word);
  for (const word of ["CLEAN", "", null, 1, { clean: true }]) assert.equal(readChecks(record(word), { branch: BRANCH }).scan, "failed", JSON.stringify(word));
  assert.deepEqual(readChecks(record(undefined), { branch: BRANCH }), { tip: CHECKED_TIP, results: [] });
});

// main on a reuse with no outcome of its own: the runner's checks for the
// reused branch at TIP, with `scan` (null: none), and the issue's labels and events.
async function runReuse({ scan = "clean", exit = 0, labels = ["agent-ready", "work-class: scoped"], events = [], eventsStatus = 200, files = [{ filename: "README.md" }], compareStatus = 200 } = {}) {
  const checks = JSON.stringify({ version: 1, branch: lane(400), tip: TIP, results: [{ check: FRAGMENTS, exit }], ...(scan === null ? {} : { scan }) });
  return withAsyncDir({ "runner-checks": checks, "resolved.json": RESOLVED, "trusted.json": TRUSTED_LIST }, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, 200, { number: 77, labels: labels.map((name) => ({ name })) }],
      ["GET", /\/issues\/77\/events$/, eventsStatus, events],
      tipRoute(),
      ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
      ["GET", /\/compare\//, compareStatus, compareStatus === 200 ? { files } : { message: "boom" }],
      ["GET", /\/pulls$/, 200, []],
      ["POST", /\/pulls$/, 201, { number: 90 }],
    ]);
    const code = await main({ env: { ...reuseEnv(dir), RESOLVED_CONFIG: join(dir, "resolved.json"), TRUSTED_ACTORS: join(dir, "trusted.json") }, fetch });
    assert.equal(code, 0);
    return { calls, body: calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body.body };
  });
}

test("main opens a clean reuse PR with no hold line, and holds it on a leak scan that is not clean", async () => {
  assert.ok(!holds((await runReuse()).body));
  for (const scan of ["found", "failed", null]) assert.ok(holds((await runReuse({ scan })).body), String(scan));
});

test("main opens a reuse PR whose runner check failed with no hold line or hold label, and still holds it on a leak scan that is not clean", async () => {
  const holdLabeled = (calls) => calls.some((c) => c.method === "POST" && c.path.endsWith("/labels") && c.body?.labels?.includes(HUMAN_MERGE_HOLD));
  const failing = await runReuse({ exit: 1 });
  assert.ok(!holds(failing.body), failing.body);
  assert.ok(failing.body.includes(`${FRAGMENTS}: failed (exit 1)`), failing.body);
  assert.ok(!holdLabeled(failing.calls));
  for (const scan of ["found", null]) assert.ok(holds((await runReuse({ exit: 1, scan })).body), String(scan));
});

test("main holds a reuse PR on a denied path or a failed compare, and opens a clean one unheld", async () => {
  assert.ok(!holds((await runReuse()).body));
  assert.ok(holds((await runReuse({ files: [{ filename: ".github/workflows/x.yml" }] })).body), "a denied path");
  assert.ok(holds((await runReuse({ compareStatus: 500 })).body), "a failed compare");
});

test("main reads merge: human on a reuse too, and holds when its labeler cannot be read", async () => {
  const labels = ["agent-ready", "work-class: scoped", "merge: human"];
  assert.ok(!holds((await runReuse({ labels, events: [labeled("merge: human", "stranger", 42)] })).body), "an untrusted labeler");
  assert.ok(holds((await runReuse({ labels, events: [labeled("merge: human", "kyle-sexton", OWNER_ID)] })).body), "the owner");
  assert.ok(holds((await runReuse({ labels, eventsStatus: 500, events: { message: "boom" } })).body), "unreadable events");
});

// The run-checks step puts the reuse scan's word in the record only on a
// reused branch, and only for the tip it checked; anything else is failed.
test("the checks record carries the reuse scan's word for the checked tip, failed for another tip or no word, and none off a reuse", () => {
  const scanOf = (env) => runChecks({ goodFragment: true, env }).checks.scan;
  assert.equal(scanOf((tip) => ({ REUSE: "true", SCAN: "clean", SCAN_TIP: tip })), "clean");
  assert.equal(scanOf((tip) => ({ REUSE: "true", SCAN: "found", SCAN_TIP: tip })), "found");
  assert.equal(scanOf(() => ({ REUSE: "true", SCAN: "clean", SCAN_TIP: "e".repeat(40) })), "failed", "another tip");
  assert.equal(scanOf(() => ({ REUSE: "true", SCAN: "", SCAN_TIP: "" })), "failed", "the scan step set no word");
  assert.equal(scanOf((tip) => ({ REUSE: "true", SCAN: "clean\nscan=clean", SCAN_TIP: tip })), "failed", "not one word");
  assert.equal(scanOf((tip) => ({ REUSE: "", SCAN: "found", SCAN_TIP: tip })), undefined, "not a reuse");
});

// The reuse-scan step against a throwaway base holding the gate and the scan
// script, and a lane branch cloned from it.
function runReuseScan(laneFiles) {
  const root = tempDir("reuse-scan-");
  try {
    const base = join(root, "base");
    const laneDir = join(root, "lane");
    const out = join(root, "out");
    const gitIn = (dir, ...args) => {
      const run = spawnSync("git", ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@t", ...args], { encoding: "utf8" });
      assert.equal(run.status, 0, `git ${args.join(" ")}: ${run.stderr}`);
      return run.stdout;
    };
    for (const file of ["lib/publish-gate.mjs", ".github/scripts/work-resolve-issue/scan-reuse.mjs"]) {
      mkdirSync(dirname(join(base, file)), { recursive: true });
      cpSync(fileURLToPath(new URL(`../../../${file}`, import.meta.url)), join(base, file));
    }
    gitIn(root, "init", "-q", "-b", "main", base);
    gitIn(base, "add", "-A");
    gitIn(base, "commit", "-qm", "base");
    gitIn(root, "clone", "-q", base, laneDir);
    gitIn(laneDir, "checkout", "-q", "-b", "lane");
    for (const [file, bytes] of Object.entries(laneFiles)) writeFileSync(join(laneDir, file), bytes);
    gitIn(laneDir, "add", "-A");
    gitIn(laneDir, "commit", "-qm", "lane", "--allow-empty");
    const tip = gitIn(laneDir, "rev-parse", "HEAD").trim();
    const run = spawnSync("bash", ["-e", "-o", "pipefail", "-c", runChecksScript("reuse-scan")], {
      encoding: "utf8",
      env: { ...process.env, BASE: base, LANE: laneDir, GITHUB_OUTPUT: out },
    });
    assert.equal(run.status, 0, run.stderr);
    const outputs = Object.fromEntries(readFileSync(out, "utf8").trim().split("\n").map((line) => line.split("=")));
    return { ...outputs, tip, stdout: run.stdout, stderr: run.stderr };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

// Samples built from parts, so no line of this file forms the shape it tests.
const SAMPLE_KEY = ["sk", "ant", "api03", "x".repeat(40)].join("-");
const SAMPLE_ASSIGNMENT = `${"pass"}word = "${"hunter"}2-zz9"`;

test("the reuse-scan step scans what the branch changes and records its word and tip", () => {
  const clean = runReuseScan({ "notes.md": "a plain change\n" });
  assert.deepEqual({ scan: clean.scan, tip: clean.tip }, { scan: "clean", tip: clean.tip });
  const keyed = runReuseScan({ "notes.md": `key ${SAMPLE_KEY}\n` });
  assert.equal(keyed.scan, "found", "a credential format");
  assert.match(keyed.stderr, /scan-reuse: Anthropic key; rotate this credential/);
  assert.equal(runReuseScan({ "notes.md": `${SAMPLE_ASSIGNMENT}\n` }).scan, "found", "a plain assignment, which the read runner only warns on");
  assert.equal(runReuseScan({ "blob.bin": Buffer.concat([Buffer.from([0, 1, 0]), Buffer.from(SAMPLE_KEY), Buffer.from([0])]) }).scan, "found", "a binary file");
  assert.equal(runReuseScan({ [`${SAMPLE_KEY}.txt`]: "x\n" }).scan, "found", "a credential-format file name");
  const quiet = runReuseScan({ "notes.md": `key ${SAMPLE_KEY}\n` });
  assert.ok(!`${quiet.stdout}${quiet.stderr}`.includes(SAMPLE_KEY), "the step never prints the match");
});

test("scan-reuse.mjs prints failed when the scan cannot finish, and refuses arguments that are not a repository and two SHAs", () => {
  const script = fileURLToPath(new URL("./scan-reuse.mjs", import.meta.url));
  const root = tempDir("scan-reuse-");
  try {
    const run = spawnSync(process.execPath, [script, join(root, "absent"), "a".repeat(40), "b".repeat(40)], { encoding: "utf8" });
    assert.deepEqual({ status: run.status, stdout: run.stdout }, { status: 0, stdout: "failed\n" });
    for (const args of [[], [root, "main", "b".repeat(40)], [root, "a".repeat(40)]]) {
      const bad = spawnSync(process.execPath, [script, ...args], { encoding: "utf8" });
      assert.deepEqual({ status: bad.status, stdout: bad.stdout }, { status: 2, stdout: "" }, args.join(" "));
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// #10698 (run 40732936415): the earlier-work check read no closing PR at
// 17:11, a listed human's open #10686 gained a closing keyword at 17:13, and the
// lane still opened a second PR at 17:19. report-outcome reads the closers
// again before the open.
async function openWithClosers(nodes, { own = [] } = {}) {
  return withAsyncDir(
    {
      "work-outcome.json": JSON.stringify(done),
      "lane.json": JSON.stringify({ branch: BRANCH }),
      "runner-checks": checksFile(),
      "trusted.json": TRUSTED_LIST,
    },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        branchTip(),
        ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
        ["GET", /\/compare\//, 200, { files: [{ filename: "README.md" }] }],
        ["GET", /\/pulls$/, 200, own],
        ["POST", /^\/graphql$/, 200, graphql(nodes)],
        ["POST", /\/pulls$/, 201, { number: 90 }],
        ...HISTORY,
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/labels\//, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      const lines = [];
      const log = console.log;
      console.log = (line) => lines.push(line);
      try {
        const code = await main({ env: { ...env(dir), TRUSTED_ACTORS: join(dir, "trusted.json") }, fetch });
        return { code, calls, lines };
      } finally {
        console.log = log;
      }
    },
  );
}
const opened = (calls) => calls.some((c) => c.method === "POST" && c.path === "/repos/o/r/pulls");

test("main on done opens no PR when a listed human's open PR already closes the issue, and keeps agent-ready", async () => {
  const { code, calls, lines } = await openWithClosers([{ ...closer("User", "kyle-sexton", OWNER_ID), number: 10686 }]);
  assert.equal(code, 0);
  assert.ok(!opened(calls), JSON.stringify(calls));
  assert.ok(lines.some((line) => line.includes("#10686")), lines.join("\n"));
  assert.ok(!calls.some((c) => c.path.endsWith("/issues/77/labels") || c.method === "DELETE"));
  const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/issues/77/comments")).body.body;
  assert.ok(comment.startsWith("<!-- work-resolve-issue outcome=retry run=123 -->"), comment);
  assert.match(comment, /`closed-by-open-pr`/);
  // Quoted as the stop's words, so its `#` is neutralized like any run text.
  assert.match(comment, /PR .10686 already closes this issue/);
  assert.ok(comment.includes(BRANCH), comment);
});

test("main on done still opens the PR when no open PR closes the issue, or only an outsider's does", async () => {
  for (const nodes of [[], [closer("User", "stranger", 42)], [closer("User", "kyle-sexton", OWNER_ID, "fork/r")]]) {
    const { code, calls } = await openWithClosers(nodes);
    assert.equal(code, 0, JSON.stringify(nodes));
    assert.ok(opened(calls), JSON.stringify(nodes));
    assert.ok(!calls.some((c) => c.path.endsWith("/issues/77/comments")), JSON.stringify(nodes));
  }
});

// A rerun of the report finds the lanes App's own PR from this branch, which
// closes the issue itself, so it is never read as a second PR.
test("main on done keeps the lanes App's own open PR from the branch without reading the closers", async () => {
  const { code, calls } = await openWithClosers([closer("Bot", BOT)], { own: [{ number: 90, user: { login: BOT }, head: { sha: CHECKED_TIP } }] });
  assert.equal(code, 0);
  assert.ok(!calls.some((c) => c.path === "/graphql"));
  assert.ok(!opened(calls));
  assert.ok(!calls.some((c) => c.path.endsWith("/issues/77/comments")));
});

test("main opens no PR when the closing PRs cannot be read", async () => {
  await withAsyncDir(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: BRANCH }), "runner-checks": checksFile() },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        branchTip(),
        ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
        ["GET", /\/compare\//, 200, { files: [{ filename: "README.md" }] }],
        ["GET", /\/pulls$/, 200, []],
        ["POST", /^\/graphql$/, 200, { errors: [{ message: "boom" }] }],
        ["POST", /\/pulls$/, 201, { number: 90 }],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 1);
      assert.ok(!opened(calls));
    },
  );
});
