// prune-branches.mjs: the prune job deletes only a named lane branch of the
// issue that is not this run's, the reuse or the resume branch, and that a
// fresh read shows with no pull request in any state, at the tip it read.
import assert from "node:assert/strict";
import { test } from "node:test";

import { DELETE_REF, ZERO_OID } from "../branch-cleanup/cleanup.mjs";
import { prune } from "./prune-branches.mjs";

const lane = (run, attempt = 1) => `work-resolve-issue/issue-77-${run}-${attempt}`;
const SHA = "a".repeat(40);
const ENV = { ISSUE_NUMBER: "77", RUN_ID: "500", REPOSITORY: "o/r", REUSE_BRANCH: "", RESUME_BRANCH: "" };

// A fake client: the read answers each aliased ref from `refs` (name -> ref
// node or null); a delete is recorded and answered by `refuse`.
function fake(refs, { readError = null, refuse = () => false, into = {} } = {}) {
  const calls = [];
  const call = async (method, path, body) => {
    calls.push({ method, path, body });
    if (body.query === DELETE_REF) {
      if (refuse(body.variables.name)) throw new Error("POST /graphql: refused");
      return { data: { updateRefs: { clientMutationId: null } } };
    }
    if (readError) throw new Error(readError);
    const repository = { id: "R_1" };
    for (const [key, value] of Object.entries(body.variables)) {
      if (/^b\d+$/.test(key)) repository[key] = refs[value.replace(/^refs\/heads\//, "")] ?? null;
      if (/^n\d+$/.test(key)) repository[`p${key.slice(1)}`] = { totalCount: into[value] ?? 0 };
    }
    return { data: { repository } };
  };
  return { call, calls };
}
const ref = (count = 0, oid = SHA) => ({ target: { oid }, associatedPullRequests: { totalCount: count } });
const deletes = (calls) => calls.filter((c) => c.body.query === DELETE_REF).map((c) => c.body.variables);

test("a named stopped-run branch with no pull request is deleted at the tip read, one request per branch", async () => {
  const { call, calls } = fake({ [lane(400)]: ref(), [lane(401)]: ref(0, "b".repeat(40)) });
  const result = await prune({ ...ENV, PRUNE_BRANCHES: `${lane(400)} ${lane(401)}` }, { call, log: () => {} });
  assert.deepEqual(result.deleted, [lane(400), lane(401)]);
  assert.equal(calls.filter((c) => c.body.query !== DELETE_REF).length, 1, "one read for every branch");
  assert.deepEqual(deletes(calls), [
    { repositoryId: "R_1", name: `refs/heads/${lane(400)}`, beforeOid: SHA, afterOid: ZERO_OID },
    { repositoryId: "R_1", name: `refs/heads/${lane(401)}`, beforeOid: "b".repeat(40), afterOid: ZERO_OID },
  ]);
  const read = calls[0].body;
  assert.match(read.query, /associatedPullRequests\(states: \[OPEN, CLOSED, MERGED\]\)/);
});

// The run job's runner ran the model, so the list is a claim: the run's own
// branches and the reuse and resume branches are spared even when named.
test("the run's own branch and the reuse and resume branches are never deleted, even when named", async () => {
  const names = [lane(500, 1), lane(500, 2), lane(401), lane(402), lane(400)];
  const { call, calls } = fake(Object.fromEntries(names.map((name) => [name, ref()])));
  const result = await prune(
    { ...ENV, PRUNE_BRANCHES: names.join(" "), REUSE_BRANCH: lane(401), RESUME_BRANCH: lane(402) },
    { call, log: () => {} },
  );
  assert.deepEqual(result.deleted, [lane(400)]);
  assert.deepEqual(deletes(calls).map((d) => d.name), [`refs/heads/${lane(400)}`]);
});

test("a name that is not this issue's lane branch is refused before any read", async () => {
  for (const name of ["main", "work-resolve-issue/issue-7-400-1", "work-resolve-issue/issue-770-400-1", `${lane(400)}x`, "pr-unblock/issue-77-400-1"]) {
    const { call, calls } = fake({ [name]: ref() });
    const result = await prune({ ...ENV, PRUNE_BRANCHES: name }, { call, log: () => {} });
    assert.deepEqual(result.deleted, [], name);
    assert.equal(calls.length, 0, name);
  }
});

test("a branch that backs a pull request, is gone, or reads oddly is kept", async () => {
  const { call, calls } = fake({
    [lane(400)]: ref(1),
    [lane(401)]: { target: { oid: SHA } },
    [lane(402)]: ref(0, "not a sha"),
    [lane(404)]: ref("0"),
  });
  const result = await prune({ ...ENV, PRUNE_BRANCHES: [400, 401, 402, 403, 404].map((run) => lane(run)).join(" ") }, { call, log: () => {} });
  assert.deepEqual(result.deleted, []);
  assert.deepEqual(deletes(calls), []);
});

test("a branch an open pull request targets is kept", async () => {
  const { call, calls } = fake({ [lane(400)]: ref(), [lane(401)]: ref() }, { into: { [lane(400)]: 1 } });
  const result = await prune({ ...ENV, PRUNE_BRANCHES: `${lane(400)} ${lane(401)}` }, { call, log: () => {} });
  assert.deepEqual(result.deleted, [lane(401)]);
  assert.match(calls[0].body.query, /pullRequests\(baseRefName: \$n0, states: \[OPEN\]\)/);
  assert.equal(calls[0].body.variables.n0, lane(400));
});

test("a deleted branch's log line names a restore that works from GitHub's copy", async () => {
  const lines = [];
  const { call } = fake({ [lane(400)]: ref() });
  await prune({ ...ENV, PRUNE_BRANCHES: lane(400) }, { call, log: (line) => lines.push(line) });
  assert.ok(lines.some((line) => line.includes(`gh api repos/o/r/git/refs -f ref=refs/heads/${lane(400)} -f sha=${SHA}`)), lines.join("\n"));
});

test("a failed read deletes nothing", async () => {
  const { call, calls } = fake({ [lane(400)]: ref() }, { readError: "POST /graphql: Resource not accessible by integration" });
  const result = await prune({ ...ENV, PRUNE_BRANCHES: lane(400) }, { call, log: () => {} });
  assert.deepEqual(result.deleted, []);
  assert.deepEqual(deletes(calls), []);
});

test("a refused delete is logged and the next branch still goes", async () => {
  const lines = [];
  const { call } = fake({ [lane(400)]: ref(), [lane(401)]: ref() }, { refuse: (name) => name.endsWith(lane(400)) });
  const result = await prune({ ...ENV, PRUNE_BRANCHES: `${lane(400)} ${lane(401)}` }, { call, log: (line) => lines.push(line) });
  assert.deepEqual(result.deleted, [lane(401)]);
  assert.ok(lines.some((line) => line.startsWith("::warning::") && line.includes(lane(400))), lines.join("\n"));
});

test("a repeated name is read and deleted once, and the list is capped", async () => {
  const names = Array.from({ length: 25 }, (_, i) => lane(300 + i));
  const { call, calls } = fake(Object.fromEntries(names.map((name) => [name, ref()])));
  const result = await prune({ ...ENV, PRUNE_BRANCHES: [lane(300), ...names].join(" ") }, { call, log: () => {} });
  assert.equal(result.deleted.length, 20);
  assert.equal(new Set(deletes(calls).map((d) => d.name)).size, 20);
});

test("an environment that is not an issue, run and repository refuses before any call", async () => {
  for (const env of [{ ISSUE_NUMBER: "x" }, { RUN_ID: "" }, { REPOSITORY: "o" }]) {
    const { call, calls } = fake({});
    await assert.rejects(prune({ ...ENV, PRUNE_BRANCHES: lane(400), ...env }, { call, log: () => {} }), JSON.stringify(env));
    assert.equal(calls.length, 0);
  }
});
