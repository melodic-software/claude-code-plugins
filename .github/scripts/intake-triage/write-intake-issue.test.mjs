// test-scope: plugins/work-items/skills/triage/schemas/ci-verdict.schema.json .github/actions/check-trusted-trigger/fixtures/trusted-actors.json
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";

import { MARKER as LANE_MARKER } from "./post-triage.mjs";
import { main, MARKER, MERGED_LIMIT, narrowType, OPEN_LIMIT, trustedComments } from "./write-intake-issue.mjs";

const SCHEMA = JSON.parse(readFileSync(new URL("../../../plugins/work-items/skills/triage/schemas/ci-verdict.schema.json", import.meta.url), "utf8"));
const dir = mkdtempSync(join(tmpdir(), "write-intake-issue-"));
after(() => rmSync(dir, { recursive: true, force: true }));
const ACTORS = new URL("../../actions/check-trusted-trigger/fixtures/trusted-actors.json", import.meta.url).pathname;

const KYLE = { login: "kyle-sexton", id: 153232337, type: "User" };
const ACTIONS = { login: "github-actions[bot]", id: 41898282, type: "Bot" };
const page = (from, count, extra = {}) => Array.from({ length: count }, (_, i) => ({ number: from - i, title: `t${from - i}`, ...extra }));

function fakeGitHub({ types = [{ name: "Task", isEnabled: true }, { name: "Old", isEnabled: false }], typesFail = false, comments = [] } = {}) {
  return async (method, path, body) => {
    if (path === "/repos/o/r/issues/7") return { number: 7, title: "Fix it", body: "Done when: fixed.", user: { login: "kyle-sexton" }, labels: [{ name: "needs-triage" }] };
    if (path.startsWith("/repos/o/r/issues/7/comments")) return comments;
    if (path.includes("state=open")) {
      const n = Number(/[?&]page=(\d+)/.exec(path)[1]);
      return n <= 3 ? [...page(1000 - (n - 1) * 100, 99), { number: 7, title: "self" }] : [];
    }
    if (path.includes("state=closed")) {
      const n = Number(/[?&]page=(\d+)/.exec(path)[1]);
      return page(500 - (n - 1) * 100, 100, { pull_request: { merged_at: `2026-11-${String(10 + n).padStart(2, "0")}T00:00:00Z` } });
    }
    if (method === "POST" && path === "/graphql") {
      if (typesFail) throw new Error("no access");
      return { data: { repository: { issueTypes: { nodes: types } } } };
    }
    throw new Error(`unexpected ${method} ${path} ${JSON.stringify(body)}`);
  };
}

const run = async (opts = {}, env = {}) => {
  const issueFile = join(dir, `issue-${Math.random()}.json`);
  const schemaFile = join(dir, `schema-${Math.random()}.json`);
  writeFileSync(schemaFile, JSON.stringify(SCHEMA));
  const lines = [];
  const code = await main({
    env: { GITHUB_REPOSITORY: "o/r", ISSUE_NUMBER: "7", ISSUE_FILE: issueFile, SCHEMA_FILE: schemaFile, TRUSTED_ACTORS_PATH: ACTORS, BOT_SENDER_IDS: "41898282 337595936", ...env },
    github: fakeGitHub(opts),
    log: (line) => lines.push(line),
  });
  return { code, lines, issueFile, schemaFile };
};

describe("write-intake-issue", () => {
  test("its marker is the lane's", () => assert.equal(MARKER, LANE_MARKER));

  test("writes the issue, the open issues less itself, and the merged pull requests newest first", async () => {
    const { code, issueFile } = await run();
    assert.equal(code, 0);
    const issue = JSON.parse(readFileSync(issueFile, "utf8"));
    assert.deepEqual([issue.number, issue.title, issue.body, issue.author, issue.labels], [7, "Fix it", "Done when: fixed.", "kyle-sexton", ["needs-triage"]]);
    assert.equal(issue.open_issues.length, OPEN_LIMIT);
    assert.ok(!issue.open_issues.some((other) => other.number === 7));
    assert.deepEqual(Object.keys(issue.open_issues[0]), ["number", "title"]);
    assert.equal(issue.merged_pulls.length, MERGED_LIMIT);
    assert.equal(issue.merged_pulls[0].merged_at, "2026-11-11T00:00:00Z");
  });

  test("keeps a listed human's and a bot sender's comments, never the lane's marker comment or another bot's", () => {
    const kept = trustedComments(
      [
        { user: KYLE, body: "decision" },
        { user: ACTIONS, body: `${MARKER}\nold verdict` },
        { user: ACTIONS, body: "sweep note" },
        { user: { login: "dependabot[bot]", id: 49699333, type: "Bot" }, body: "listed bot, not a sender" },
        { user: { login: "kyle-sexton", id: 153232337, type: "Bot" }, body: "wrong type" },
        { user: { login: "stranger", id: 9, type: "User" }, body: "x" },
      ],
      new Set([153232337]),
      new Set([41898282]),
    );
    assert.deepEqual(kept.map((c) => c.body), ["decision", "sweep note"]);
  });

  test("narrows the schema's type to the enabled Issue Types, or drops it", async () => {
    const typed = await run();
    assert.deepEqual(JSON.parse(readFileSync(typed.schemaFile, "utf8")).properties.type, { type: "string", enum: ["Task"] });
    const untyped = await run({ typesFail: true });
    assert.equal(untyped.code, 0);
    assert.ok(!("type" in JSON.parse(readFileSync(untyped.schemaFile, "utf8")).properties));
    assert.ok(!("type" in narrowType(SCHEMA, []).properties));
    assert.ok("type" in SCHEMA.properties, "narrowType leaves the input alone");
  });

  test("leaves no file on a malformed number or bot list", async () => {
    for (const env of [{ ISSUE_NUMBER: "x" }, { BOT_SENDER_IDS: "41898282,bad" }]) {
      const { code, issueFile } = await run({}, env);
      assert.equal(code, 1);
      assert.ok(!existsSync(issueFile));
    }
  });
});
