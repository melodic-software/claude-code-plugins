import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { parseBlockedBy, writeEdges } from "./edges.mjs";

describe("parseBlockedBy", () => {
  for (const [name, lines, numbers] of [
    ["none", ["Blocked by: none"], []],
    ["one issue", ["Blocked by: #12"], [12]],
    ["a comma list", ["Blocked by: #12, #345"], [12, 345]],
    ["a repeated number once", ["Blocked by: #12, #12"], [12]],
    ["a missing line as none", ["Size: Small"], []],
    ["a quoted line as missing", ["> Blocked by: #12"], []],
    ["an indented line as missing", ["  Blocked by: #12"], []],
  ]) {
    test(`reads ${name}`, () => {
      assert.deepEqual(parseBlockedBy(lines), { numbers, problem: null });
    });
  }

  for (const [name, value] of [
    ["a bare number", "#12, 13"],
    ["a cross-repository reference", "other/repo#12"],
    ["a mention", "#12 @someone"],
    ["a URL", "https://github.com/o/r/issues/12"],
    ["a leading zero", "#012"],
    ["an empty value", ""],
  ]) {
    test(`${name} names no issue`, () => {
      const parsed = parseBlockedBy([`Blocked by: ${value}`]);
      assert.deepEqual(parsed.numbers, []);
      assert.match(parsed.problem, /not none or a list of #<number>/);
    });
  }

  test("two lines name no issue", () => {
    assert.deepEqual(parseBlockedBy(["Blocked by: #1", "Blocked by: #2"]), {
      numbers: [],
      problem: "more than one `Blocked by:` line",
    });
  });
});

const REPO_URL = "https://api.github.com/repos/o/r";
const open = (number) => ({ id: 1000 + number, number, state: "open", repository_url: REPO_URL });

function fakeGitHub({ issues = {}, existing = [], postError } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (method === "GET" && path.startsWith("/repos/o/r/issues/7/dependencies/blocked_by")) {
      return existing;
    }
    const match = /^\/repos\/o\/r\/issues\/([0-9]+)$/.exec(path);
    if (method === "GET" && match) {
      const issue = issues[match[1]];
      if (issue === undefined) {
        throw new GitHubError(404, path);
      }
      return issue;
    }
    if (method === "POST" && postError) {
      throw postError;
    }
    return {};
  };
  return { github, calls };
}
const posts = (calls) => calls.filter(({ method }) => method === "POST");

describe("writeEdges", () => {
  test("posts each open blocker's REST id, not its number", async () => {
    const fake = fakeGitHub({ issues: { 12: open(12), 13: open(13) } });
    const result = await writeEdges({ github: fake.github, repository: "o/r", number: 7, blockers: [12, 13] });
    assert.deepEqual(result, { written: [12, 13], skipped: [] });
    assert.deepEqual(
      posts(fake.calls).map(({ path, body }) => [path, body]),
      [
        ["/repos/o/r/issues/7/dependencies/blocked_by", { issue_id: 1012 }],
        ["/repos/o/r/issues/7/dependencies/blocked_by", { issue_id: 1013 }],
      ],
    );
  });

  test("skips the issue itself, a pull request, a closed issue, another repository's issue, a missing one and an edge already there", async () => {
    const fake = fakeGitHub({
      issues: {
        20: { ...open(20), pull_request: {} },
        21: { ...open(21), state: "closed" },
        22: { ...open(22), repository_url: "https://api.github.com/repos/o/other" },
        24: open(24),
        25: open(25),
      },
      existing: [{ number: 24 }],
    });
    const result = await writeEdges({ github: fake.github, repository: "o/r", number: 7, blockers: [7, 20, 21, 22, 23, 24, 25] });
    assert.deepEqual(result.written, [25]);
    assert.deepEqual(result.skipped, [
      { number: 7, why: "the issue itself" },
      { number: 20, why: "a pull request" },
      { number: 21, why: "not open" },
      { number: 22, why: "not an issue in this repository" },
      { number: 23, why: "no such issue" },
      { number: 24, why: "the edge is already there" },
    ]);
    assert.deepEqual(
      posts(fake.calls).map(({ body }) => body),
      [{ issue_id: 1025 }],
    );
  });

  test("writes at most 50 edges", async () => {
    const blockers = Array.from({ length: 51 }, (_, index) => 100 + index);
    const fake = fakeGitHub({ issues: Object.fromEntries(blockers.map((n) => [n, open(n)])) });
    const result = await writeEdges({ github: fake.github, repository: "o/r", number: 7, blockers });
    assert.equal(posts(fake.calls).length, 50);
    assert.deepEqual(result.skipped, [{ number: 150, why: "past the first 50" }]);
  });

  test("an edge GitHub refuses is skipped; any other error stops it", async () => {
    const refused = fakeGitHub({ issues: { 12: open(12) }, postError: new GitHubError(422, "POST") });
    assert.deepEqual(await writeEdges({ github: refused.github, repository: "o/r", number: 7, blockers: [12] }), {
      written: [],
      skipped: [{ number: 12, why: "GitHub refused the edge" }],
    });
    const broken = fakeGitHub({ issues: { 12: open(12) }, postError: new GitHubError(500, "POST") });
    await assert.rejects(writeEdges({ github: broken.github, repository: "o/r", number: 7, blockers: [12] }));
  });

  test("reads nothing when no blocker is named", async () => {
    const fake = fakeGitHub();
    assert.deepEqual(await writeEdges({ github: fake.github, repository: "o/r", number: 7, blockers: [] }), { written: [], skipped: [] });
    assert.deepEqual(fake.calls, []);
  });
});
