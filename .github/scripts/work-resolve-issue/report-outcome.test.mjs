// Expected values come from the lane's plan: a missing or invalid outcome file
// means `stopped`; `done` opens a ready PR whose body starts `Closes #<issue>`,
// with a Conventional Commits title (else `chore: work on #<issue>`), the
// issue's `work-class:` label, and the hold line for scoped, structural and
// untrusted-provenance work or a trust or lane-power diff; `pushback` and
// `stopped` comment and add needs-human, and only pushback removes
// agent-ready.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { decide, main, readHoldPaths, readOutcome } from "./report-outcome.mjs";

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

test("done keeps a Conventional Commits title", () => {
  assert.equal(decideDone().title, "docs(work-items): fix a typo");
});

test("done replaces a title that is not Conventional Commits", () => {
  assert.equal(decideDone({ outcome: { ...done, title: "Fix a typo" } }).title, "chore: work on #77");
});

test("done copies the issue's work-class label and only that", () => {
  assert.deepEqual(decideDone().labels, ["work-class: read-only"]);
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

test("a title carrying an issue reference falls back", () => {
  assert.equal(decideDone({ outcome: { ...done, title: "fix: x, closes #5" } }).title, "chore: work on #77");
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

test("main on done opens a ready PR from the branch and labels it", async () => {
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
      assert.deepEqual(calls.find((c) => c.path.endsWith("/issues/90/labels")).body, { labels: ["work-class: read-only"] });
    },
  );
});

test("main on a rerun reuses the open PR from the branch and still labels it", async () => {
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
      assert.ok(calls.some((c) => c.method === "POST" && c.path.endsWith("/issues/90/labels")));
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
