// Expected values come from the lane's plan: a missing or invalid outcome file
// means `stopped`; `done` opens a ready PR whose body starts `Closes #<issue>`,
// with a Conventional Commits title (the run's, else one from the issue title), no
// label (the class lives on the issue only), and the hold line for
// untrusted-provenance work or a trust or lane-power diff; `pushback` and
// `stopped` comment, add needs-human and remove agent-ready.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  countTurnCapRestarts,
  decide,
  findPrior,
  findPriorMain,
  main,
  parseOutcomeMarker,
  readHoldPaths,
  readFunding,
  readChecks,
  readOutcome,
  readTurnCap,
  reusePlan,
  trustedLabeler,
} from "./report-outcome.mjs";

const BRANCH = "work-resolve-issue/issue-77-123-1";
// The first line of every hand-back comment: the attended queue's escalation
// marker in the grammar of plugins/work-items/reference/escalation-marker.md.
const ESC = "<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\n";

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
  const dir = mkdtempSync(join(tmpdir(), "outcome-"));
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

// PR #9621: the run set `link: refs` for the issue's own parent `Refs:` line
// and named no remaining work, so the PR closes the issue.
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
    assert.equal(decideDone({ outcome }).exit, "stopped");
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
  assert.equal(plan.action, "hand-back");
  assert.equal(plan.exit, "stopped");
  assert.deepEqual(plan.addLabels, ["needs-human"]);
  assert.deepEqual(plan.removeLabels, ["agent-ready"]);
  assert.ok(plan.comment.includes("- scripts/check-changelog-fragments.sh --check failed (exit 1)"), plan.comment);
});

test("a done outcome whose runner check results are missing is stopped", () => {
  const plan = decideDone({ checks: null });
  assert.equal(plan.exit, "stopped");
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
  assert.equal(plan.action, "hand-back");
  assert.equal(plan.exit, "stopped");
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

test("done with no branch is stopped, since nothing was committed", () => {
  const plan = decideDone({ branch: "" });
  assert.equal(plan.action, "hand-back");
  assert.equal(plan.exit, "stopped");
});

// apply-issue-patch's escalation reason: a done run whose patch was refused
// committed something that never landed, and the person sees why.
for (const [reason, why] of [
  ["patch-protected-path", /a path the issue lane may not push/],
  ["patch-invalid", /not a valid patch/],
  ["patch-not-applied", /did not apply/],
]) {
  test(`done whose patch apply-issue-patch refused (${reason}) hands back naming the reason, not an empty run`, () => {
    const plan = decideDone({ branch: "", escalation: reason, runUrl: "https://example/o/r/actions/runs/123" });
    assert.equal(plan.action, "hand-back");
    assert.equal(plan.exit, "stopped");
    assert.ok(plan.comment.includes(`\`${reason}\``), plan.comment);
    assert.match(plan.comment, why);
    assert.doesNotMatch(plan.comment, /committed nothing/);
    assert.ok(plan.comment.includes("https://example/o/r/actions/runs/123"), plan.comment);
  });
}

test("a refused patch on a resumed run hands back instead of opening the PR from the resumed branch", () => {
  const plan = decideDone({ branch: "", resumed: "work-resolve-issue/issue-77-100-1", checks: { tip: CHECKED_TIP, results: [{ check: FRAGMENTS, exit: 0 }] }, escalation: "patch-protected-path" });
  assert.equal(plan.action, "hand-back");
  assert.ok(plan.comment.includes("`patch-protected-path`"), plan.comment);
  assert.ok(plan.comment.includes("Partial work is on the branch `work-resolve-issue/issue-77-100-1`"), plan.comment);
});

test("patch-empty changes no plan: a done run with no commit, a resumed run, or a pushback", () => {
  const resumed = { branch: "", resumed: "work-resolve-issue/issue-77-100-1", checks: { tip: CHECKED_TIP, results: [{ check: FRAGMENTS, exit: 0 }] } };
  assert.deepEqual(decideDone({ ...resumed, escalation: "patch-empty" }), decideDone(resumed));
  assert.deepEqual(decideDone({ branch: "", escalation: "patch-empty" }), decideDone({ branch: "" }));
  assert.match(decideDone({ branch: "", escalation: "patch-empty" }).comment, /committed nothing/);
  const pushback = { exit: "pushback", reason: "Which file?", title: "", summary: "" };
  for (const escalation of ["patch-empty", "patch-protected-path"]) {
    assert.deepEqual(decideDone({ outcome: pushback, branch: "", escalation }), decideDone({ outcome: pushback, branch: "" }), escalation);
  }
});

test("pushback comments, adds needs-human and removes agent-ready", () => {
  const plan = decide({
    outcome: { exit: "pushback", reason: "Which file?", title: "", summary: "" },
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

// A stopped issue goes to a person, so it carries the hold alone: agent-ready
// beside needs-human leaves it in both queues.
test("stopped removes agent-ready and names the branch that holds partial work", () => {
  const plan = decide({
    outcome: { exit: "stopped", reason: "Tests failed.", title: "", summary: "" },
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
    const route = routes.find(([m, p]) => m === method && p.test(path));
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
    TRACKER_CONFIG: join(dir, "absent.json"),
    RUNNER_CHECKS: existsSync(join(dir, "runner-checks")) ? readFileSync(join(dir, "runner-checks"), "utf8") : "",
  };
}

const ISSUE = [/./, 200, { number: 77, labels: [{ name: "agent-ready" }, { name: "work-class: read-only" }] }];

test("main with no outcome files comments stopped and adds needs-human", async () => {
  await withDir({}, async (dir) => {
    const { fetch, calls } = fakeFetch([
      ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
      ["POST", /\/issues\/77\/labels$/, 200, []],
      ["POST", /\/issues\/77\/comments$/, 201, {}],
    ]);
    assert.equal(await main({ env: env(dir), fetch }), 0);
    assert.deepEqual(calls.find((c) => c.path.endsWith("/labels")).body, { labels: ["needs-human"] });
    assert.ok(calls.some((c) => c.method === "POST" && c.path.endsWith("/comments")));
    assert.ok(!calls.some((c) => c.path.endsWith("/pulls")));
  });
});

// agent-ready starts this lane, so a run that added it would start the next.
test("main refuses a human-gated label that is agent-ready and writes no label", async () => {
  // Not withDir: main reads the tracker config after its first await.
  const dir = mkdtempSync(join(tmpdir(), "outcome-"));
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
// outcome: report-outcome hands the issue to a person with the next step.
for (const [reason, step] of [
  ["split-required", "/work-items:decompose"],
  ["research-first", "research"],
  ["probe-first", "probe"],
]) {
  test(`main on a ${reason} dimension skip hands the issue back naming the next step`, async () => {
    await withDir({}, async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/issues\/77\/labels\/agent-ready$/, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: { ...env(dir), DIMENSION_SKIP: reason }, fetch }), 0);
      assert.deepEqual(calls.find((c) => c.method === "POST" && c.path.endsWith("/labels")).body, { labels: ["needs-human"] });
      assert.ok(calls.some((c) => c.method === "DELETE" && c.path.endsWith("/labels/agent-ready")));
      const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
      assert.match(comment, new RegExp(`^${ESC}<!-- work-resolve-issue outcome=${reason} run=123 -->`));
      assert.equal(parseOutcomeMarker(comment).outcome, reason);
      assert.ok(comment.includes(step), comment);
      assert.ok(comment.includes("https://example/o/r/actions/runs/123"), comment);
      assert.ok(!calls.some((c) => c.path.endsWith("/pulls") || c.path.includes("/compare/")));
    });
  });
}

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

test("main on done opens a ready PR from the branch and adds no label to it", async () => {
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
      assert.ok(!calls.some((c) => c.path.endsWith("/issues/90/labels")));
      assert.ok(!calls.some((c) => c.method === "POST" && c.path.startsWith("/repos/o/r/issues/77/")));
    },
  );
});

// #7497: an outcome file that says done with nothing left undone opens no PR
// when the runner's checks failed, are missing, or ran on another tip.
test("main on done opens no PR and hands the issue back when the runner's checks do not pass", async () => {
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
          ["POST", /\/issues\/77\/labels$/, 200, []],
          ["POST", /\/issues\/77\/comments$/, 201, {}],
        ]);
        assert.equal(await main({ env: env(dir), fetch }), 0, label);
        assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/pulls")), label);
        assert.deepEqual(calls.find((c) => c.path.endsWith("/issues/77/labels")).body, { labels: ["needs-human"] }, label);
        const comment = calls.find((c) => c.path.endsWith("/issues/77/comments")).body.body;
        assert.ok(comment.startsWith(ESC + "<!-- work-resolve-issue outcome=stopped run=123 -->"), comment);
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
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/pulls")));
      assert.ok(calls.find((c) => c.path.endsWith("/issues/77/comments")).body.body.includes("check results are missing"));
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
      const writes = calls.filter((c) => c.method !== "GET").map((c) => `${c.method} ${c.path}`);
      assert.deepEqual(writes, ["POST /repos/o/r/pulls"]);
      assert.ok(calls.find((c) => c.path.endsWith("/pulls") && c.method === "POST").body.body.startsWith("Refs: #77\n"));
    },
  );
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
      assert.ok(!calls.some((c) => c.path.endsWith("/issues/90/labels")));
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

test("main on a resumed done with no commit of its own and no check results hands back, naming the resumed branch", async () => {
  await withDir(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: "", resume: RESUMED }) },
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
      assert.ok(comment.startsWith(ESC + "<!-- work-resolve-issue outcome=stopped"), comment);
      assert.match(comment, /resumed .* no new commit/);
      assert.ok(comment.includes(RESUMED), comment);
      assert.deepEqual(calls.find((c) => c.method === "POST" && c.path.endsWith("/labels")).body, { labels: ["needs-human"] });
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
test("main on a resumed done hands back when its branch's checks fail, moved, or carry a commit not the App's", async () => {
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
          ["POST", /\/issues\/77\/labels$/, 200, []],
          ["DELETE", /\/labels\//, 200, []],
          ["POST", /\/issues\/77\/comments$/, 201, {}],
        ]);
        assert.equal(await main({ env: env(dir), fetch }), 0, label);
        assert.ok(!calls.some((c) => c.method === "POST" && c.path.endsWith("/pulls")), label);
        const comment = calls.find((c) => c.path.endsWith("/issues/77/comments")).body.body;
        assert.ok(comment.startsWith(ESC + "<!-- work-resolve-issue outcome=stopped"), `${label}: ${comment}`);
        assert.ok(comment.includes(RESUMED), `${label}: ${comment}`);
      },
    );
  }
});

// The branch name can move between the tip check and the PR open, so a PR
// whose head is not the checked tip is closed and the issue handed back.
test("main closes a resumed branch's new PR whose head is not the tip the runner checked, and hands back", async () => {
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
        ["POST", /\/issues\/77\/labels$/, 200, []],
        ["DELETE", /\/labels\//, 200, []],
        ["POST", /\/issues\/77\/comments$/, 201, {}],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      assert.deepEqual(calls.find((c) => c.method === "PATCH" && c.path.endsWith("/pulls/90"))?.body, { state: "closed" });
      assert.deepEqual(calls.find((c) => c.path.endsWith("/issues/77/labels")).body, { labels: ["needs-human"] });
      const comment = calls.find((c) => c.path.endsWith("/issues/77/comments")).body.body;
      assert.ok(comment.startsWith(ESC + "<!-- work-resolve-issue outcome=stopped"), comment);
      assert.ok(comment.includes(CHECKED_TIP), comment);
    },
  );
});

test("a resumed done with no new commit is stopped unless the runner's checks passed on the resumed branch", () => {
  for (const checks of [null, NO_CHECKS, { tip: CHECKED_TIP, results: [{ check: FRAGMENTS, exit: 1 }] }]) {
    const plan = decideDone({ branch: "", resumed: RESUMED, checks });
    assert.equal(plan.action, "hand-back");
    assert.match(plan.comment, /resumed `work-resolve-issue\/issue-77-100-1` and reported done with no new commit/);
  }
  const plan = decideDone({ branch: "", resumed: RESUMED, checks: { tip: CHECKED_TIP, results: [{ check: FRAGMENTS, exit: 0 }] } });
  assert.equal(plan.action, "open-pr");
  assert.equal(plan.branch, RESUMED);
});

test("main on a resumed stop with no commit of its own names no branch", async () => {
  await withDir(
    {
      "work-outcome.json": JSON.stringify({ exit: "stopped", reason: "Blocked." }),
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
    outcome: { exit: "stopped", reason: "The tests cannot run here.", title: "", summary: "" },
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

test("done with no branch still hands back even with a limit record", () => {
  const plan = decide({
    outcome: { exit: "done", reason: "", title: "", summary: "" },
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: "",
    changedFiles: [],
    limit: { resets: null },
  });
  assert.notEqual(plan.action, "limited");
  assert.deepEqual(plan.addLabels, ["needs-human"]);
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
    outcome: { exit: "pushback", reason: "Unclear.", title: "", summary: "" },
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

test("a run at its turn cap with no restart left hands back, naming the cap", () => {
  for (const overrides of [{ turnCapRestarts: 1 }, { limits: { "turn-cap-restarts": 0 } }]) {
    const plan = capped(overrides);
    assert.equal(plan.action, "hand-back");
    assert.deepEqual(plan.addLabels, ["needs-human"]);
    assert.deepEqual(plan.removeLabels, ["agent-ready"]);
    assert.ok(plan.comment.startsWith(ESC + "<!-- work-resolve-issue outcome=turn-cap cap=75 run=555 -->\n"), plan.comment);
    assert.match(plan.comment, /turn cap 75 reached/);
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
  const stoppedPlan = capped({ outcome: { exit: "stopped", reason: "The tests cannot run here.", title: "", summary: "" } });
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

test("lane.json's max-turns class is the turn-cap record; any other class is none", () => {
  for (const [lane, expected] of [
    [{ branch: "", class: "max-turns", "max-turns": "75" }, { cap: 75 }],
    [{ branch: "", class: "max-turns", "max-turns": "75; rm" }, { cap: null }],
    [{ branch: "", class: "rate-limit", "max-turns": "75" }, null],
  ]) {
    withDir({ "lane.json": JSON.stringify(lane) }, (dir) => assert.deepEqual(readTurnCap(dir), expected, JSON.stringify(lane)));
  }
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

test("main at the turn cap with no restarts configured hands the issue to a person", async () => {
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
    assert.deepEqual(calls.find((c) => c.path.endsWith("/labels")).body, { labels: ["needs-human"] });
    assert.ok(calls.some((c) => c.method === "DELETE" && c.path.endsWith("/labels/agent-ready")));
    const comment = calls.find((c) => c.method === "POST" && c.path.endsWith("/comments")).body.body;
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
const closer = (typename, login, databaseId, repo = "o/r") => ({
  number: 501,
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
  for (const reason of ["split-required", "research-first", "probe-first"]) {
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
      { action: "run", stale: { branch: lane(400), behindBy } },
      String(behindBy),
    );
  }
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

test("--find-prior runs the model fresh, with no resume outputs, when the marked run's branch is behind main", async () => {
  const comments = [{ user: { login: BOT }, body: "<!-- work-resolve-issue outcome=stopped run=400 -->", created_at: "2026-10-16T11:00:00Z" }];
  const comparison = { ahead_by: 1, behind_by: 865, total_commits: 1, commits: [LANE_TIP] };
  const { code, output } = await runPrior({ comments, refs: [refOf(lane(400))], comparison });
  assert.equal(code, 0);
  assert.equal(output, "proceed=true\nskip-reason=\nreuse-branch=\n");
});

test("another issue's lane branches are never this issue's", () => {
  const branches = [branchFact("work-resolve-issue/issue-7-400-1"), branchFact("work-resolve-issue/issue-770-400-1", { pulls: [pullBy(BOT)] })];
  assert.deepEqual(prior({ branches }), { action: "run" });
});

test("with no lane branch and no closing PR the run goes ahead as before", () => {
  assert.deepEqual(prior({}), { action: "run" });
});

// findPriorMain against a fake GitHub API: its only effect is the step
// outputs, and it writes nothing to GitHub.
async function withAsyncDir(files, run) {
  const dir = mkdtempSync(join(tmpdir(), "prior-"));
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
    { exit: "stopped", reason: "Tests failed.", title: "", summary: "" },
    { exit: "pushback", reason: "Which file?", title: "", summary: "" },
  ]) {
    const plan = decide({ outcome, issueNumber: 77, issueLabels: [], branch: BRANCH, changedFiles: [], runId: "555" });
    assert.ok(plan.comment.startsWith(`${ESC}<!-- work-resolve-issue outcome=${outcome.exit} run=555 -->\n`), plan.comment);
    assert.deepEqual(parseOutcomeMarker(plan.comment), { outcome: outcome.exit, resets: null, run: "555", onResumed: false });
  }
});

test("the reuse PR body is fixed text, held, and follows the PR body contract's order", () => {
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
      assert.ok(!calls.some((c) => c.path.endsWith("/comments") || c.path.endsWith("/labels")), Object.keys(files).join());
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
// the tip it read). Owner decision: a reuse PR keeps the hold line whether or
// not it carries a usable summary; with none, it keeps today's fixed text.
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
// Readable denied paths, so a hold decided from runner facts (decide()'s
// predicate) would not hold the README-only, read-only-class reuse PRs below:
// only the rule that every reuse PR is held puts the hold line on them.
const RESOLVED = JSON.stringify({ merge: { "diff-check": { "denied-paths": HOLD_GLOBS } } });
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
async function runHumanMerge({ labels, events = [], eventsStatus = 200, trusted = TRUSTED_LIST }) {
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
        ["GET", /\/pulls$/, 200, []],
        ["POST", /\/pulls$/, 201, { number: 90 }],
      ]);
      const code = await main({
        env: { ...env(dir), RESOLVED_CONFIG: join(dir, "resolved.json"), TRUSTED_ACTORS: join(dir, "trusted.json") },
        fetch,
      });
      return { code, calls, body: calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body.body };
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

test("a funding stop with no date leaves a marker with no reset", () => {
  const plan = decideFunding({ funding: { regain: null } });
  assert.ok(plan.comment.startsWith("<!-- work-resolve-issue outcome=funding run=555 -->\n"), plan.comment);
  assert.equal(parseOutcomeMarker(plan.comment).resets, null);
});

test("a funding stop wins over a turn-cap or limit record, so it counts as neither", () => {
  const plan = decideFunding({ funding: { regain: null }, turnCap: { cap: 75 }, limit: { resets: null }, limits: { "turn-cap-restarts": 0 } });
  assert.equal(plan.action, "funding");
});

test("a stop the skill reported goes to a person even with a funding record", () => {
  const plan = decideFunding({ outcome: { exit: "stopped", reason: "Blocked.", title: "", summary: "" }, funding: { regain: null } });
  assert.equal(plan.action, "hand-back");
});

// collect-base-activity runs a script activity from a copy of its own
// directory under $RUNNER_TEMP, so every import must resolve inside it.
test("the script loads from a copy of its own directory alone", async () => {
  const copy = mkdtempSync(join(tmpdir(), "base-script-"));
  try {
    cpSync(dirname(fileURLToPath(import.meta.url)), copy, { recursive: true });
    const module = await import(pathToFileURL(join(copy, "report-outcome.mjs")).href);
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
function runChecksScript() {
  const lines = readFileSync(new URL("../../workflows/work-resolve-issue.yml", import.meta.url), "utf8").split("\n");
  const id = lines.findIndex((line) => /^\s+id: run-checks$/.test(line));
  assert.notEqual(id, -1, "work-resolve-issue.yml has the run-checks step");
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
}) {
  const root = mkdtempSync(join(tmpdir(), "run-checks-"));
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
      env: { ...process.env, BASE: base, LANE: laneDir, BRANCH, RESOLVED: join(root, "resolved.json"), GITHUB_OUTPUT: out, LOG: log },
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
test("every hand-back opens with the attended queue's escalation marker, and a restart carries none", () => {
  const plain = { issueNumber: 77, issueLabels: [], branch: BRANCH, changedFiles: [], runId: "555" };
  const handBacks = [
    decide({ ...plain, outcome: { exit: "pushback", reason: "Which file?", title: "", summary: "" } }),
    decide({ ...plain, outcome: { exit: "stopped", reason: "Tests failed.", title: "", summary: "" } }),
    decide({ ...plain, outcome: { exit: "done", reason: "", title: "", summary: "" }, escalation: "patch-protected-path" }),
    capped({ limits: { "turn-cap-restarts": 0 } }),
  ];
  for (const plan of handBacks) {
    assert.deepEqual(plan.addLabels, ["needs-human"], plan.comment);
    assert.equal(plan.comment.split("\n")[0], "<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->", plan.comment);
  }
  const restarts = [
    capped(),
    decideFunding({ funding: { regain: null } }),
    decideFunding({ limit: { resets: Date.parse("2026-10-17T18:00:00Z") }, now: Date.parse("2026-10-17T12:00:00Z") }),
  ];
  for (const plan of restarts) {
    assert.deepEqual(plan.addLabels, [], plan.comment);
    assert.ok(!plan.comment.includes("work-items:escalation"), plan.comment);
  }
});

test("an outcome marker reads back after the escalation marker line, and after no other line", () => {
  const outcome = "<!-- work-resolve-issue outcome=stopped run=9 -->\nWhy.";
  const read = { outcome: "stopped", resets: null, run: "9", onResumed: false };
  assert.deepEqual(parseOutcomeMarker(`<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\n${outcome}`), read);
  assert.deepEqual(parseOutcomeMarker(`<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\r\n${outcome}`), read);
  assert.equal(parseOutcomeMarker(`<!-- work-items:escalation lane=pr-unblock kind=escalated -->\n${outcome}`), null);
  assert.equal(parseOutcomeMarker(`Quoting <!-- work-items:escalation lane=work-resolve-issue kind=escalated -->\n${outcome}`), null);
});
