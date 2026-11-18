import assert from "node:assert/strict";
import { rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { after, describe, test } from "node:test";

import { main } from "./check-human-pull.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";

const HUMAN = { id: 101, login: "person" };
const STRANGER = { id: 202, login: "stranger" };
const dir = tempDir("check-human-pull-");
after(() => rmSync(dir, { recursive: true, force: true }));
const TRUSTED = join(dir, "trusted-actors.json");
writeFileSync(TRUSTED, JSON.stringify({ version: 1, actors: [{ kind: "human", id: HUMAN.id, login: HUMAN.login }] }));
const ENV = { GITHUB_REPOSITORY: "o/r", ISSUE_NUMBER: "42", TRUSTED_ACTORS_PATH: TRUSTED };

const refsEvent = (number) => ({
  event: "cross-referenced",
  source: { issue: { number, state: "open", pull_request: {}, repository_url: "https://api.github.com/repos/o/r", body: "Refs: #42" } },
});
const closingNode = (number, author) => ({ number, state: "OPEN", author: { __typename: "User", login: author.login, databaseId: author.id }, repository: { nameWithOwner: "o/r" } });

async function run({ timeline = [], closing = [], pulls = {} } = {}) {
  const outputs = {};
  const lines = [];
  const github = async (method, path) => {
    if (path.startsWith("/repos/o/r/issues/42/timeline")) {
      return timeline;
    }
    if (method === "POST" && path === "/graphql") {
      return { data: { repository: { issue: { closedByPullRequestsReferences: { nodes: closing, pageInfo: { hasNextPage: false } } } } } };
    }
    const pull = path.match(/^\/repos\/o\/r\/pulls\/(\d+)$/)?.[1];
    if (pull && pulls[pull]) {
      return { number: Number(pull), state: "open", draft: pulls[pull].draft ?? false, user: pulls[pull].user };
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  const code = await main({ env: ENV, github, log: (line) => lines.push(line), write: (values) => Object.assign(outputs, values) });
  return { code, outputs, lines };
}

describe("check-human-pull", () => {
  test("names a listed human's open draft pull request that names the issue by its Refs line", async () => {
    const { code, outputs, lines } = await run({ timeline: [refsEvent(7)], pulls: { 7: { user: HUMAN, draft: true } } });
    assert.equal(code, 0);
    assert.deepEqual(outputs, { pull: "7" });
    assert.match(lines.join("\n"), /#7/);
  });

  test("names a listed human's open pull request that closes the issue", async () => {
    const { outputs } = await run({ closing: [closingNode(8, HUMAN)], pulls: { 8: { user: HUMAN } } });
    assert.deepEqual(outputs, { pull: "8" });
  });

  test("names none when no open pull request names the issue", async () => {
    const { code, outputs } = await run();
    assert.equal(code, 0);
    assert.deepEqual(outputs, { pull: "" });
  });

  test("names none when only an author who is not a listed human has one open", async () => {
    const { outputs } = await run({ timeline: [refsEvent(9)], closing: [closingNode(9, STRANGER)], pulls: { 9: { user: STRANGER } } });
    assert.deepEqual(outputs, { pull: "" });
  });

  test("fails, writing no output, when the pull requests cannot be read", async () => {
    const outputs = {};
    await assert.rejects(
      main({
        env: ENV,
        github: async () => {
          throw new Error("read failed");
        },
        log: () => {},
        write: (values) => Object.assign(outputs, values),
      }),
      /read failed/,
    );
    assert.deepEqual(outputs, {});
  });
});
