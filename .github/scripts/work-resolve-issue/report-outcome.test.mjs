// Expected values come from the lane's plan: a missing or invalid outcome file
// means `stopped`; `done` opens a ready PR whose body starts `Closes #<issue>`,
// with a Conventional Commits title (the run's, else one from the issue title), no
// label (the class lives on the issue only), and the hold line for scoped, structural and
// untrusted-provenance work or a trust or lane-power diff; `pushback` and
// `stopped` comment and add needs-human, and only pushback removes
// agent-ready.
import assert from "node:assert/strict";
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

import {
  decide,
  findPrior,
  findPriorMain,
  main,
  parseOutcomeMarker,
  readHoldPaths,
  readOutcome,
  reusePlan,
} from "./report-outcome.mjs";

const BRANCH = "work-resolve-issue/issue-77-123-1";

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

// A recorded keep-Refs decision (#7741): the PR links without closing, and a
// human merges it because the merge gate finds no closing issue to read.
test('done with "link": "refs" opens a PR that starts Refs: #N and carries the hold line', () => {
  withDir({ "work-outcome.json": JSON.stringify({ ...done, link: "refs" }) }, (dir) => {
    const plan = decideDone({ outcome: readOutcome(join(dir, "work-outcome.json")) });
    assert.ok(plan.body.startsWith("Refs: #77\n"), plan.body);
    assert.ok(!plan.body.includes("Closes #77"), plan.body);
    assert.ok(plan.body.split("\n").includes("Hold: a human merges this"), plan.body);
  });
});

test("an unknown link value still closes the issue", () => {
  withDir({ "work-outcome.json": JSON.stringify({ ...done, link: "fixes" }) }, (dir) => {
    const plan = decideDone({ outcome: readOutcome(join(dir, "work-outcome.json")) });
    assert.ok(plan.body.startsWith("Closes #77\n"), plan.body);
  });
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

for (const cls of ["scoped", "structural", "untrusted-provenance"]) {
  test(`${cls} work carries the hold line`, () => {
    const plan = decideDone({ issueLabels: [`work-class: ${cls}`] });
    assert.ok(plan.body.split("\n").includes("Hold: a human merges this"), plan.body);
  });
}

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
    "The run reports:\n\n- scripts/check-changelog-fragments.sh --check: passed\n- The lane run: https://example/run/1\n\nLeft out: the items under Not verified.",
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
    "The run listed no checks.\n\n- The lane run: https://example/run/1\n\nLeft out: nothing the run reported.",
  );
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

test("a diff the compare listing may have cut short carries the hold line", () => {
  const files = Array.from({ length: 300 }, (_, i) => `docs/f${i}.md`);
  assert.ok(decideDone({ changedFiles: files }).body.split("\n").includes("Hold: a human merges this"));
});

test("done with no branch is stopped, since nothing was committed", () => {
  const plan = decideDone({ branch: "" });
  assert.equal(plan.action, "hand-back");
  assert.equal(plan.exit, "stopped");
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

test("stopped keeps agent-ready and names the branch that holds partial work", () => {
  const plan = decide({
    outcome: { exit: "stopped", reason: "Tests failed.", title: "", summary: "" },
    issueNumber: 77,
    issueLabels: ["agent-ready"],
    branch: BRANCH,
    changedFiles: ["README.md"],
    humanLabel: "needs-human",
  });
  assert.deepEqual(plan.addLabels, ["needs-human"]);
  assert.deepEqual(plan.removeLabels, []);
  assert.ok(plan.comment.includes(BRANCH));
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

test("main on done opens a ready PR from the branch and adds no label to it", async () => {
  await withDir(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: BRANCH }) },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
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
    },
  );
});

test("main on a rerun reuses the open PR from the branch", async () => {
  await withDir(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: BRANCH }) },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
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
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: BRANCH }) },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
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
  });
  assert.equal(parseOutcomeMarker("<!-- work-resolve-issue outcome=stopped -->").outcome, "stopped");
  assert.equal(parseOutcomeMarker("hello"), null);
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
const branchFact = (name, { aheadBy = 2, tip = LANE_TIP, tipAt = Date.parse("2026-10-16T10:00:00Z"), pulls = [] } = {}) => ({
  name,
  aheadBy,
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

test("a stopped, pushback or limited marker for the branch's run keeps it from reuse", () => {
  for (const outcome of ["stopped", "pushback", "limited"]) {
    const markers = [{ outcome, run: "400", resets: null, at: Date.parse("2026-10-16T11:00:00Z") }];
    assert.deepEqual(prior({ branches: [branchFact(lane(400))], markers }), { action: "run" }, outcome);
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
  comparison = { ahead_by: 2 },
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
  assert.equal(output, "proceed=true\nskip-reason=\nreuse-branch=\n");
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
    assert.ok(plan.comment.startsWith(`<!-- work-resolve-issue outcome=${outcome.exit} run=555 -->\n`), plan.comment);
    assert.deepEqual(parseOutcomeMarker(plan.comment), { outcome: outcome.exit, resets: null, run: "555" });
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
  await withAsyncDir({ "work-outcome.json": JSON.stringify(model), "lane.json": JSON.stringify({ branch: lane(400) }) }, async (dir) => {
    const { fetch, calls } = fakeFetch(PR_ROUTES);
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
// the tip it read). Owner decision: with a usable summary the PR carries it
// and no automatic hold line; with none, today's fixed text and the hold stay.
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
const RESOLVED = JSON.stringify({ merge: { "diff-check": { "denied-paths": HOLD_GLOBS } } });
const summaryEnv = (dir) => ({ ...reuseEnv(dir), REUSE_SUMMARY_DIR: dir, RESOLVED_CONFIG: join(dir, "resolved.json") });
const tipRoute = (sha = TIP) => ["GET", /\/git\/ref\/heads\/work-resolve-issue\/issue-77-400-1$/, 200, { object: { sha } }];
const usable = { title: "docs(work-items): summary title", summary: "SUMMARY-PASS-TEXT", changes: ["CHANGE-ONE"] };

test("a reuse PR with a usable summary carries it and no hold line", () => {
  const plan = reusePlan({
    issueNumber: 77,
    branch: lane(400),
    summary: usable,
    issueLabels: ["agent-ready"],
    changedFiles: ["plugins/work-items/README.md"],
    holdPaths: HOLD_GLOBS,
  });
  assert.equal(plan.title, "docs(work-items): summary title");
  assert.ok(plan.body.startsWith("Closes #77\n\n## Summary\n"), plan.body);
  assert.ok(!plan.body.includes("Hold:"), plan.body);
  assert.ok(plan.body.includes("> SUMMARY-PASS-TEXT"), plan.body);
  assert.ok(plan.body.includes("- CHANGE-ONE"), plan.body);
  assert.deepEqual(headings(plan.body), ["## Summary", "## Fix", "## Verification", "## Related"]);
});

test("a summarized reuse PR is still held where any lane PR would be", () => {
  for (const [label, facts] of [
    ["held class", { issueLabels: ["work-class: structural"], changedFiles: ["README.md"], holdPaths: HOLD_GLOBS }],
    ["denied path", { issueLabels: [], changedFiles: [".github/workflows/x.yml"], holdPaths: HOLD_GLOBS }],
    ["unreadable hold paths", { issueLabels: [], changedFiles: ["README.md"], holdPaths: null }],
    ["compare cap", { issueLabels: [], changedFiles: Array.from({ length: 300 }, (_, i) => `f${i}.md`), holdPaths: HOLD_GLOBS }],
  ]) {
    const plan = reusePlan({ issueNumber: 77, branch: lane(400), summary: usable, ...facts });
    assert.ok(plan.body.split("\n").includes("Hold: a human merges this"), label);
    assert.ok(plan.body.includes("SUMMARY-PASS-TEXT"), label);
  }
});

test("main opens a reuse PR from a summary bound to this issue, branch and tip, with no hold line", async () => {
  await withAsyncDir({ "reuse-summary.json": summaryFile(), "resolved.json": RESOLVED }, async (dir) => {
    const { fetch, calls } = fakeFetch([tipRoute(), ...PR_ROUTES]);
    assert.equal(await main({ env: summaryEnv(dir), fetch }), 0);
    const pull = calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body;
    assert.equal(pull.head, lane(400));
    assert.equal(pull.title, "docs(work-items): summary title");
    assert.ok(pull.body.includes("SUMMARY-PASS-TEXT") && pull.body.includes("CHANGE-ONE"), pull.body);
    assert.ok(!pull.body.includes("Hold:"), pull.body);
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
    await withAsyncDir({ ...files, "resolved.json": RESOLVED }, async (dir) => {
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
  await withAsyncDir({ "reuse-summary.json": summaryFile(), "resolved.json": RESOLVED }, async (dir) => {
    const { fetch, calls } = fakeFetch(PR_ROUTES);
    assert.equal(await main({ env: summaryEnv(dir), fetch }), 0);
    const pull = calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body;
    assert.ok(pull.body.split("\n").includes("Hold: a human merges this"), pull.body);
    assert.ok(!pull.body.includes("SUMMARY-PASS-TEXT"), pull.body);
  });
});

test("a branch's own outcome wins over a summary, so the summary never stands in for a report", async () => {
  await withAsyncDir(
    { "work-outcome.json": JSON.stringify(model), "lane.json": JSON.stringify({ branch: lane(400) }), "reuse-summary.json": summaryFile() },
    async (dir) => {
      const { fetch, calls } = fakeFetch([tipRoute(), ...PR_ROUTES]);
      assert.equal(await main({ env: summaryEnv(dir), fetch }), 0);
      const pull = calls.find((c) => c.method === "POST" && c.path.endsWith("/pulls")).body;
      assert.ok(pull.body.includes("MODEL-SUMMARY-TEXT") && !pull.body.includes("SUMMARY-PASS-TEXT"), pull.body);
    },
  );
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
