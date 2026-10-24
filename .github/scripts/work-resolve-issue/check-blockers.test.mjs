import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { main } from "./check-blockers.mjs";

const HUMAN = { id: 101, login: "person" };
const STRANGER = { id: 202, login: "stranger" };
const dir = mkdtempSync(join(tmpdir(), "check-blockers-"));
after(() => rmSync(dir, { recursive: true, force: true }));
const TRUSTED = join(dir, "trusted-actors.json");
writeFileSync(TRUSTED, JSON.stringify({ version: 1, actors: [{ kind: "human", id: HUMAN.id, login: HUMAN.login }] }));
const ENV = { GITHUB_REPOSITORY: "o/r", ISSUE_NUMBER: "42", TRUSTED_ACTORS_PATH: TRUSTED };

const issue = (number, state, { repo = "o/r", reason = state === "closed" ? "completed" : null, closer = HUMAN } = {}) => ({
  number,
  state,
  state_reason: reason,
  closed_by: state === "closed" ? closer : null,
  repository_url: `https://api.github.com/repos/${repo}`,
});
const pull = (number, merged) => ({ ...issue(number, "closed"), pull_request: { merged_at: merged ? "2026-10-01T00:00:00Z" : null } });

async function run(blockers, env = ENV) {
  const calls = [];
  const lines = [];
  const outputs = {};
  const github = async (method, path, body) => {
    calls.push(`${method} ${path}`);
    if (typeof blockers === "function") {
      return blockers(path);
    }
    if (path.includes("/dependencies/blocked_by")) {
      return blockers;
    }
    const match = path.match(/^\/repos\/o\/r\/issues\/(\d+)$/);
    if (match) {
      return blockers.find((item) => String(item.number) === match[1]);
    }
    if (method === "POST" && path === "/graphql") {
      // No merged pull request closed it.
      return { data: { repository: { issue: { timelineItems: { nodes: [{ closer: null }] } } } } };
    }
    throw new Error(`unexpected ${method} ${path} ${JSON.stringify(body)}`);
  };
  const code = await main({ env, github, log: (line) => lines.push(line), write: (values) => Object.assign(outputs, values) });
  return { code, calls, lines, outputs };
}

test("an open blocker skips the run with a notice naming it, and writes nothing", async () => {
  const { code, calls, lines, outputs } = await run([issue(7, "open"), issue(8, "closed"), issue(9, "open", { repo: "o/other" })]);
  assert.equal(code, 0);
  assert.deepEqual(outputs, { proceed: "false" });
  assert.ok(calls.every((call) => call.startsWith("GET ")));
  const notice = lines.find((line) => line.startsWith("::notice"));
  assert.match(notice, /#7/);
  assert.match(notice, /o\/other#9/);
  assert.doesNotMatch(notice, /#8\b/);
});

test("a blocker closed without doing the work still blocks: an unmerged pull request, not planned, duplicate, another repository", async () => {
  for (const blocker of [
    pull(7, false),
    issue(7, "closed", { reason: "not_planned" }),
    issue(7, "closed", { reason: "duplicate" }),
    issue(7, "closed", { repo: "o/other" }),
  ]) {
    const { code, lines, outputs } = await run([blocker]);
    assert.equal(code, 0);
    assert.deepEqual(outputs, { proceed: "false" }, JSON.stringify(blocker));
    assert.match(lines.find((line) => line.startsWith("::notice")), /#7/);
  }
});

test("an issue closed as completed by someone not on the trusted list still blocks", async () => {
  const { outputs, lines } = await run([issue(7, "closed", { closer: STRANGER })]);
  assert.deepEqual(outputs, { proceed: "false" });
  assert.match(lines.find((line) => line.startsWith("::notice")), /#7/);
});

test("every blocker done, or none, runs: a merged pull request, an issue a listed human closed as completed", async () => {
  assert.deepEqual((await run([issue(8, "closed"), pull(9, true)])).outputs, { proceed: "true" });
  assert.deepEqual((await run([])).outputs, { proceed: "true" });
});

test("a blocker list it cannot read skips the run with a warning and exits 0", async () => {
  const { code, lines, outputs } = await run(() => {
    throw new Error("GET failed: 502");
  });
  assert.equal(code, 0);
  assert.deepEqual(outputs, { proceed: "false" });
  assert.ok(lines.some((line) => line.startsWith("::warning")));
});

test("an issue number that is not one, or no trusted list, skips the run with a warning and reads nothing", async () => {
  for (const env of [{ ...ENV, ISSUE_NUMBER: "1; rm" }, { ...ENV, TRUSTED_ACTORS_PATH: join(dir, "missing.json") }]) {
    const { code, calls, lines, outputs } = await run([], env);
    assert.equal(code, 0);
    assert.deepEqual(calls, []);
    assert.deepEqual(outputs, { proceed: "false" });
    assert.ok(lines.some((line) => line.startsWith("::warning")));
  }
});
