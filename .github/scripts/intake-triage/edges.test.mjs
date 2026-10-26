import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { MAX_TEXT_BLOCKERS, parseBlockedBy, textBlockers, writeEdges } from "./edges.mjs";

describe("textBlockers", () => {
  const URL = "https://github.com/o/r/issues";
  for (const [name, body, numbers] of [
    ["a Blocked by line", "Blocked by #12", [12]],
    ["a Blocked by: list", "Blocked by: #12, #13", [12, 13]],
    ["a Depends on line", "Depends on #12", [12]],
    ["a list item that starts with Blocked by", "- Blocked by: #12", [12]],
    ["a bold label", "**Blocked by:** #12", [12]],
    ["any case", "BLOCKED BY: #12", [12]],
    ["an issue URL of this repository", `Blocked by: ${URL}/12`, [12]],
    ["an issue URL with an anchor", `Depends on ${URL}/12#issuecomment-5`, [12]],
    ["a Depends on heading's list", "## Depends on\n\n- #7571\n- #7572 (the parser)\n* #7573\n1. #7574", [7571, 7572, 7573, 7574]],
    ["a Blocked by heading's list, up to the next heading", "### Blocked by:\n- #1\n- #2\n## Next\n- #3", [1, 2]],
    ["a heading's list item URL", `## Blocked by\n- ${URL}/9`, [9]],
    ["a repeated number once", "Blocked by: #12\n## Depends on\n- #12", [12]],
    // #8994's and #8989's shape: prose names the blocker too, and only the line counts.
    [
      "only the line, not prose that mentions issues",
      "## Problem\n\n#8753 makes it skip. #7613 adds the disclosure.\n\n## Criterion moved from #8753\n\n- One.\n\nBlocked by: #8753\n\n<!-- work-items:born-triaged -->\n",
      [8753],
    ],
    ["none", "Blocked by: none", []],
    ["none with a mention after it", "Blocked by: none (was #12)", []],
    ["no issue at all", "Blocked by the release", []],
    ["a mid-sentence mention", "This is blocked by #12.", []],
    ["a list item outside a section", "## Plan\n- #12", []],
    ["a quoted line", "> Blocked by: #12", []],
    ["an indented quoted line", "  > Depends on #12", []],
    ["a backtick fence", "```\nBlocked by: #12\n```\nBlocked by: #13", [13]],
    ["a tilde fence", "~~~md\nDepends on #12\n~~~", []],
    ["a fence a shorter one does not close", "````\n```\nBlocked by: #12\n````", []],
    ["inline code", "Blocked by: `#12`, #13", [13]],
    ["an HTML comment across lines", "<!--\nBlocked by: #12\n-->", []],
    ["a cross-repository reference", "Blocked by: other/repo#12, o/r#13", []],
    ["another repository's URL", "Blocked by: https://github.com/o/other/issues/12", []],
    ["a repository whose name only ends the same", "Blocked by: https://github.com/xo/r/issues/12", []],
    ["a pull request URL", `Blocked by: https://github.com/o/r/pull/12`, []],
    ["an HTML entity", "Blocked by: &#12;", []],
    ["a leading zero", "Blocked by: #012", []],
    ["a word after the number", "Blocked by: #12abc", []],
    ["a Blocked-by-like word", "Blocked byproduct #12", []],
    ["a link labeled #N to another repository's issue", "Blocked by: [#12](https://github.com/other/repo/issues/12)", []],
    ["a link to this repository's issue, by its target", `Blocked by: [#13](${URL}/12), [the parser](<${URL}/14> "title")`, [12, 14]],
    ["a bare #N inside a link to elsewhere", "Depends on [see #12 there](https://example.com/x), #13", [13]],
    ["a link labeled #N in a heading's list", "## Blocked by\n- [#12](https://github.com/o/other/issues/12)\n- #13", [13]],
    ["a reference link labeled #N to another repository's issue", "Blocked by: [#12][x], [#13][]\n\n[x]: https://github.com/other/repo/issues/12\n[#13]: https://github.com/other/repo/issues/13", []],
    ["a shortcut reference link labeled #N to another repository's issue", "Blocked by: [#12]\n\n[#12]: https://github.com/other/repo/issues/12", []],
    ["a reference link to this repository's issue, by its target", `Blocked by: [the parser][P]\n\n[p]: ${URL}/14`, [14]],
    ["a bracketed #N with no definition", "Blocked by: [#12]", [12]],
    ["an empty body", "", []],
    ["a missing body", null, []],
  ]) {
    test(`reads ${name}`, () => {
      assert.deepEqual(textBlockers(body, "o/r"), { numbers, dropped: 0 });
    });
  }

  test(`keeps the first ${MAX_TEXT_BLOCKERS} and counts the rest`, () => {
    const list = Array.from({ length: MAX_TEXT_BLOCKERS + 3 }, (_, index) => `#${index + 1}`).join(", ");
    assert.deepEqual(textBlockers(`Blocked by: ${list}`, "o/r"), {
      numbers: Array.from({ length: MAX_TEXT_BLOCKERS }, (_, index) => index + 1),
      dropped: 3,
    });
  });

  test("matches the repository by name, regex characters taken literally", () => {
    assert.deepEqual(textBlockers("Blocked by: https://github.com/a.b/c/issues/4", "a.b/c").numbers, [4]);
    assert.deepEqual(textBlockers("Blocked by: https://github.com/axb/c/issues/4", "a.b/c").numbers, []);
  });
});

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

function fakeGitHub({ issues = {}, existing = [], postError, listError } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (method === "GET" && path.startsWith("/repos/o/r/issues/7/dependencies/blocked_by")) {
      if (listError) {
        throw listError;
      }
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
    assert.deepEqual(result, { written: [12, 13], skipped: [], missed: [], unwritten: [], undeleted: [] });
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

  test("an edge GitHub refuses is skipped", async () => {
    const refused = fakeGitHub({ issues: { 12: open(12) }, postError: new GitHubError(422, "POST") });
    assert.deepEqual(await writeEdges({ github: refused.github, repository: "o/r", number: 7, blockers: [12] }), {
      written: [],
      skipped: [{ number: 12, why: "GitHub refused the edge" }],
      missed: [],
      unwritten: [],
      undeleted: [],
    });
  });

  for (const status of [403, 429, 500, 502]) {
    test(`a ${status} on the edge write misses that edge, and the edge the run wrote is deleted, so no partial set stands`, async () => {
      const fake = fakeGitHub({ issues: { 12: open(12), 13: open(13) } });
      const github = async (method, path, body) => {
        if (method === "POST" && body?.issue_id === 1013) {
          throw new GitHubError(status, "POST");
        }
        return fake.github(method, path, body);
      };
      assert.deepEqual(await writeEdges({ github, repository: "o/r", number: 7, blockers: [12, 13] }), {
        written: [],
        skipped: [],
        missed: [{ number: 13, status }],
        unwritten: [12],
        undeleted: [],
      });
      assert.ok(fake.calls.some(({ method, path }) => method === "DELETE" && path === "/repos/o/r/issues/7/dependencies/blocked_by/1012"));
    });
  }

  test("an edge already there stays when another edge misses; only the run's own write is deleted", async () => {
    const fake = fakeGitHub({ issues: { 12: open(12), 13: open(13), 14: open(14) }, existing: [{ number: 14 }] });
    const github = async (method, path, body) => {
      if (method === "POST" && body?.issue_id === 1012) {
        throw new GitHubError(502, "POST");
      }
      return fake.github(method, path, body);
    };
    const result = await writeEdges({ github, repository: "o/r", number: 7, blockers: [12, 13, 14] });
    assert.deepEqual(result.unwritten, [13]);
    assert.deepEqual(
      fake.calls.filter(({ method }) => method === "DELETE").map(({ path }) => path),
      ["/repos/o/r/issues/7/dependencies/blocked_by/1013"],
    );
  });

  for (const status of [403, 500]) {
    test(`a ${status} on deleting the run's edge leaves it written and names it`, async () => {
      const fake = fakeGitHub({ issues: { 12: open(12), 13: open(13) } });
      const github = async (method, path, body) => {
        if (method === "POST" && body?.issue_id === 1013) {
          throw new GitHubError(429, "POST");
        }
        if (method === "DELETE") {
          throw new GitHubError(status, "DELETE");
        }
        return fake.github(method, path, body);
      };
      assert.deepEqual(await writeEdges({ github, repository: "o/r", number: 7, blockers: [12, 13] }), {
        written: [12],
        skipped: [],
        missed: [{ number: 13, status: 429 }],
        unwritten: [],
        undeleted: [{ number: 12, status }],
      });
    });
  }

  test("a 403 on reading the existing edges misses every edge and writes none", async () => {
    const fake = fakeGitHub({ issues: { 12: open(12), 13: open(13) }, listError: new GitHubError(403, "GET") });
    assert.deepEqual(await writeEdges({ github: fake.github, repository: "o/r", number: 7, blockers: [12, 13] }), {
      written: [],
      skipped: [],
      missed: [
        { number: 12, status: 403 },
        { number: 13, status: 403 },
      ],
      unwritten: [],
      undeleted: [],
    });
    assert.deepEqual(posts(fake.calls), []);
  });

  test("a 503 on reading a blocker misses its edge", async () => {
    const fake = fakeGitHub({ issues: { 13: open(13) } });
    const github = async (method, path, body) => {
      if (method === "GET" && path === "/repos/o/r/issues/12") {
        throw new GitHubError(503, path);
      }
      return fake.github(method, path, body);
    };
    const result = await writeEdges({ github, repository: "o/r", number: 7, blockers: [12, 13] });
    assert.deepEqual(result.missed, [{ number: 12, status: 503 }]);
    assert.deepEqual(result.written, []);
    assert.deepEqual(result.unwritten, [13], "an edge written after the miss is deleted too");
  });

  test("any other error stops it", async () => {
    const unauthorized = fakeGitHub({ issues: { 12: open(12) }, postError: new GitHubError(401, "POST") });
    await assert.rejects(writeEdges({ github: unauthorized.github, repository: "o/r", number: 7, blockers: [12] }));
    const thrown = fakeGitHub({ issues: { 12: open(12) }, postError: new TypeError("fetch failed") });
    await assert.rejects(writeEdges({ github: thrown.github, repository: "o/r", number: 7, blockers: [12] }));
  });

  test("reads nothing when no blocker is named", async () => {
    const fake = fakeGitHub();
    assert.deepEqual(await writeEdges({ github: fake.github, repository: "o/r", number: 7, blockers: [] }), { written: [], skipped: [], missed: [], unwritten: [], undeleted: [] });
    assert.deepEqual(fake.calls, []);
  });
});
