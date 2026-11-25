// test-scope: plugins/work-items/skills/triage/schemas/ci-verdict.schema.json .github/actions/check-trusted-trigger/fixtures/trusted-actors.json
// test-scope: .github/scripts/intake-triage/fixtures/intake-issue/*
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, describe, test } from "node:test";

import { MARKER as LANE_MARKER } from "./post-triage.mjs";
import { main, MARKER, MERGED_LIMIT, narrowType, OPEN_LIMIT, trustedComments } from "./write-intake-issue.mjs";

const fixture = (name) => JSON.parse(readFileSync(new URL(`./fixtures/intake-issue/${name}`, import.meta.url), "utf8"));
const ISSUE = fixture("issue.json");
const COMMENTS = fixture("comments.json");
const OPEN = fixture("open-issues-page-1.json");
const CLOSED = fixture("closed-issues-page-1.json");
const TYPES = fixture("issue-types.json");
const SCHEMA = JSON.parse(readFileSync(new URL("../../../plugins/work-items/skills/triage/schemas/ci-verdict.schema.json", import.meta.url), "utf8"));
const dir = mkdtempSync(join(tmpdir(), "write-intake-issue-"));
after(() => rmSync(dir, { recursive: true, force: true }));
const ACTORS = new URL("../../actions/check-trusted-trigger/fixtures/trusted-actors.json", import.meta.url).pathname;
const N = ISSUE.number;
const REPO = "/repos/o/r";
const pageOf = (path) => Number(/[?&]page=(\d+)/.exec(path)[1]);
const isMarker = (comment) => comment.body.startsWith(MARKER);

function fakeGitHub({ types = TYPES, typesFail = false, comments = COMMENTS } = {}) {
  return async (method, path, body) => {
    if (path === `${REPO}/issues/${N}`) return structuredClone(ISSUE);
    if (path.startsWith(`${REPO}/issues/${N}/comments`)) return pageOf(path) === 1 ? structuredClone(comments) : [];
    if (path.includes("state=open")) return pageOf(path) === 1 ? structuredClone(OPEN) : [];
    if (path.includes("state=closed")) return pageOf(path) === 1 ? structuredClone(CLOSED) : [];
    if (method === "POST" && path === "/graphql") {
      if (typesFail) throw new Error("no access");
      return structuredClone(types);
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
    env: { GITHUB_REPOSITORY: "o/r", ISSUE_NUMBER: String(N), ISSUE_FILE: issueFile, SCHEMA_FILE: schemaFile, TRUSTED_ACTORS_PATH: ACTORS, BOT_SENDER_IDS: "41898282 337595936", ...env },
    github: fakeGitHub(opts),
    log: (line) => lines.push(line),
  });
  return { code, lines, issueFile, schemaFile };
};

describe("write-intake-issue, over recorded GitHub answers", () => {
  test("its marker is the lane's, and the recorded comments hold the lane's marker comment", () => {
    assert.equal(MARKER, LANE_MARKER);
    assert.ok(COMMENTS.some(isMarker));
  });

  test("writes the issue as GitHub answered it, the open issues less itself, and the merged pull requests newest first", async () => {
    const { code, issueFile } = await run();
    assert.equal(code, 0);
    const issue = JSON.parse(readFileSync(issueFile, "utf8"));
    assert.deepEqual(
      [issue.number, issue.title, issue.body, issue.author, issue.labels],
      [ISSUE.number, ISSUE.title, ISSUE.body, ISSUE.user.login, ISSUE.labels.map((label) => label.name)],
    );
    const open = OPEN.filter((other) => !other.pull_request && other.number !== N).map(({ number, title }) => ({ number, title }));
    assert.ok(open.length > 0 && open.length <= OPEN_LIMIT);
    assert.deepEqual(issue.open_issues, open);
    const merged = CLOSED.filter((other) => other.pull_request?.merged_at);
    assert.ok(merged.length > 0 && CLOSED.some((other) => other.pull_request && !other.pull_request.merged_at), "the recorded page holds merged and unmerged pull requests");
    assert.equal(issue.merged_pulls.length, Math.min(merged.length, MERGED_LIMIT));
    assert.ok(issue.merged_pulls.every((pull, i, all) => i === 0 || all[i - 1].merged_at >= pull.merged_at), "newest first");
    assert.deepEqual(new Set(issue.merged_pulls.map((pull) => pull.number)), new Set(merged.map((pull) => pull.number)));
  });

  test("keeps the recorded listed human's and bot senders' comments, never the lane's marker comment", async () => {
    const { issueFile } = await run();
    const written = JSON.parse(readFileSync(issueFile, "utf8")).comments;
    assert.deepEqual(written.map((c) => c.body), COMMENTS.filter((c) => !isMarker(c)).map((c) => c.body));
    assert.deepEqual(written.map((c) => c.author), COMMENTS.filter((c) => !isMarker(c)).map((c) => c.user.login));
  });

  test("drops a bot that is not a sender, a listed human's id under another type, and an unlisted person", () => {
    const human = COMMENTS.find((c) => c.user.type === "User");
    const appComments = COMMENTS.filter((c) => c.user.type === "Bot" && c.user.id !== 41898282);
    assert.ok(human && appComments.length > 0);
    const asBot = { ...human, user: { ...human.user, type: "Bot" } };
    const stranger = { ...human, user: { login: "stranger", id: 9, type: "User" } };
    const kept = trustedComments([...COMMENTS, asBot, stranger], new Set([human.user.id]), new Set([41898282]));
    assert.deepEqual(kept, COMMENTS.filter((c) => !isMarker(c) && !appComments.includes(c)));
  });

  test("narrows the schema's type to the recorded enabled Issue Types, or drops it", async () => {
    const enabled = TYPES.data.repository.issueTypes.nodes.filter((t) => t.isEnabled).map((t) => t.name);
    assert.ok(enabled.length > 0);
    const typed = await run();
    assert.deepEqual(JSON.parse(readFileSync(typed.schemaFile, "utf8")).properties.type, { type: "string", enum: enabled });
    const disabled = structuredClone(TYPES);
    disabled.data.repository.issueTypes.nodes[0].isEnabled = false;
    const fewer = await run({ types: disabled });
    assert.deepEqual(JSON.parse(readFileSync(fewer.schemaFile, "utf8")).properties.type.enum, enabled.slice(1));
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
