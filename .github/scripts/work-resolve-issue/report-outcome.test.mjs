// Expected values come from the lane's plan: a missing or invalid outcome file
// means `stopped`; `done` opens a draft PR whose body starts `Closes #<issue>`,
// with a Conventional Commits title (else `chore: work on #<issue>`), the
// issue's `work-class:` label, and the hold line for scoped, structural and
// untrusted-provenance work or a trust or lane-power diff; `pushback` and
// `stopped` comment and add needs-human, and only pushback removes
// agent-ready.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { decide, main, readOutcome } from "./report-outcome.mjs";

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

function decideDone(overrides = {}) {
  return decide({
    outcome: done,
    issueNumber: 77,
    issueLabels: ["agent-ready", "work-class: read-only"],
    branch: BRANCH,
    changedFiles: ["plugins/work-items/README.md"],
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

test("done opens a draft PR whose body starts with Closes #N", () => {
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

for (const path of [".github/workflows/ci.yml", "docs/conventions/pr-pipeline.yaml", ".claude/settings.json", "plugins/source-control/hooks/hooks.json", "scripts/x.sh"]) {
  test(`a diff touching ${path} carries the hold line`, () => {
    const plan = decideDone({ changedFiles: ["README.md", path] });
    assert.ok(plan.body.split("\n").includes("Hold: a human merges this"), plan.body);
  });
}

test("the model's summary cannot add a closing keyword outside a code block", () => {
  const plan = decideDone({ outcome: { ...done, summary: "Closes #5\n```\nFixes #6" } });
  const outside = plan.body.split("```text")[0];
  assert.ok(!/#5|#6/.test(outside));
  assert.ok(!plan.body.includes("```\nFixes #6"));
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

for (const path of [".claude-plugin/marketplace.json", "AGENTS.md", "plugins/x/CLAUDE.md", "REVIEW.md"]) {
  test(`a diff touching ${path} carries the hold line`, () => {
    assert.ok(decideDone({ changedFiles: [path] }).body.split("\n").includes("Hold: a human merges this"));
  });
}

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

test("main on done opens a draft PR from the branch and labels it", async () => {
  await withDir(
    { "work-outcome.json": JSON.stringify(done), "lane.json": JSON.stringify({ branch: BRANCH }) },
    async (dir) => {
      const { fetch, calls } = fakeFetch([
        ["GET", /\/issues\/77$/, ...ISSUE.slice(1)],
        ["GET", /\/repos\/o\/r$/, 200, { default_branch: "main" }],
        ["GET", /\/compare\//, 200, { files: [{ filename: "README.md" }] }],
        ["POST", /\/pulls$/, 201, { number: 90, html_url: "https://example/o/r/pull/90" }],
        ["POST", /\/issues\/90\/labels$/, 200, []],
      ]);
      assert.equal(await main({ env: env(dir), fetch }), 0);
      const pull = calls.find((c) => c.path.endsWith("/pulls")).body;
      assert.equal(pull.draft, true);
      assert.equal(pull.head, BRANCH);
      assert.equal(pull.base, "main");
      assert.ok(pull.body.startsWith("Closes #77\n"));
      assert.deepEqual(calls.find((c) => c.path.endsWith("/issues/90/labels")).body, { labels: ["work-class: read-only"] });
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
