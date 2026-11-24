import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { CHECK_RUN_ANNOTATIONS, readNodes, restAnnotations, restJobs, RUN_CHECK_RUNS, RUN_JOBS, serveFirstAttemptJobs, servedReads, slimJob } from "./run-jobs.mjs";

const REPO = "melodic-software/claude-code-plugins";
const PARITY = JSON.parse(readFileSync(new URL("./fixtures/jobs-graphql-parity.json", import.meta.url), "utf8"));

test("a recorded GraphQL answer stands in for REST's job listing and annotations on every field the rules read", () => {
  assert.equal(PARITY.graphql.data.nodes.length, 2);
  for (const node of PARITY.graphql.data.nodes) {
    const rest = PARITY.rest[node.databaseId];
    const reads = servedReads(REPO, { id: node.databaseId }, node);
    assert.ok(reads, `run ${node.databaseId} is served`);
    const listing = reads.get(`/repos/${REPO}/actions/runs/${node.databaseId}/attempts/1/jobs?per_page=100`);
    const fields = (job) => ({ id: job.id, name: job.name, status: job.status, conclusion: job.conclusion, steps: job.steps });
    const byId = (a, b) => a.id - b.id;
    assert.equal(listing.total_count, rest.listing.total_count);
    assert.deepEqual(listing.jobs.map(fields), [...rest.listing.jobs].sort(byId).map(fields));
    for (const job of rest.listing.jobs) {
      if (job.steps.length === 0) {
        assert.equal(listing.jobs.find((j) => j.id === job.id).runner_id, job.runner_id, "a job with no steps carries the runner_id stepsKnown reads");
      }
      assert.deepEqual(reads.get(`/repos/${REPO}/check-runs/${job.id}/annotations?per_page=100`), rest.annotations[job.id]);
    }
  }
  assert.ok(
    PARITY.graphql.data.nodes.some((n) => n.checkSuite.checkRuns.nodes.some((c) => c.head.totalCount > 100)),
    "pr-verify's Check Intent lists more steps than one connection page",
  );
});

test("a node that does not answer for the run's first attempt in full is left to REST", () => {
  const node = PARITY.graphql.data.nodes.find((n) => n.checkSuite.checkRuns.nodes.some((c) => c.head.totalCount > 100));
  const run = { id: node.databaseId };
  const checks = node.checkSuite.checkRuns;
  const withCheck = (change) => ({ ...node, checkSuite: { checkRuns: { ...checks, nodes: checks.nodes.map((c, i) => (i === checks.nodes.length - 1 ? change(c) : c)) } } });
  const cases = {
    "no node": null,
    "another run": { ...node, databaseId: node.databaseId + 1 },
    "attempt 2": { ...node, runAttempt: 2 },
    "a job not listed": { ...node, checkSuite: { checkRuns: { ...checks, totalCount: checks.totalCount + 1 } } },
    "no jobs": { ...node, checkSuite: { checkRuns: { totalCount: 0, nodes: [] } } },
    "a null job": { ...node, checkSuite: { checkRuns: { ...checks, nodes: [...checks.nodes.slice(1), null] } } },
    "steps past both pages": withCheck((c) => ({ ...c, head: { ...c.head, totalCount: 201 }, tail: { ...c.tail, totalCount: 201 } })),
    "an annotation not listed": withCheck((c) => ({ ...c, annotations: { ...c.annotations, totalCount: c.annotations.totalCount + 1 } })),
    "a ran job with no steps": withCheck((c) => ({ ...c, head: { totalCount: 0, nodes: [] }, tail: { totalCount: 0, nodes: [] } })),
  };
  assert.ok(servedReads(REPO, run, node));
  for (const [label, changed] of Object.entries(cases)) {
    assert.equal(servedReads(REPO, run, changed), undefined, label);
  }
});

const RECORDED_RUN = { id: 43092202279, run_attempt: 1 };
const recordedCheckRun = (id, databaseId, name, conclusion) => ({ id, databaseId, name, status: "COMPLETED", conclusion });
const RECORDED_NODE = {
  databaseId: 43092202279,
  runAttempt: 1,
  checkSuite: {
    checkRuns: {
      totalCount: 6,
      nodes: [
        recordedCheckRun("CR_kwDOTCGFQM8AAAAecsxang", 130775014046, "unarmed-status", "SKIPPED"),
        recordedCheckRun("CR_kwDOTCGFQM8AAAAecp1zog", 130771940258, "post-merge-dispatch", "SKIPPED"),
        recordedCheckRun("CR_kwDOTCGFQM8AAAAecpy5Dw", 130771892495, "dispatch-full-run", "SKIPPED"),
        recordedCheckRun("CR_kwDOTCGFQM8AAAAecpy4dg", 130771892342, "gate-check", "SKIPPED"),
        recordedCheckRun("CR_kwDOTCGFQM8AAAAecpy3Fw", 130771891991, "merge", "SKIPPED"),
        recordedCheckRun("CR_kwDOTCGFQM8AAAAecpyvPw", 130771889983, "enable-auto-merge", "SUCCESS"),
      ],
    },
  },
};
const recordedJob = (id, node_id, name, conclusion) => ({ id, node_id, name, status: "completed", conclusion });
const RECORDED_JOBS = [
  recordedJob(130771889983, "CR_kwDOTCGFQM8AAAAecpyvPw", "enable-auto-merge", "success"),
  recordedJob(130771891991, "CR_kwDOTCGFQM8AAAAecpy3Fw", "merge", "skipped"),
  recordedJob(130771892342, "CR_kwDOTCGFQM8AAAAecpy4dg", "gate-check", "skipped"),
  recordedJob(130771892495, "CR_kwDOTCGFQM8AAAAecpy5Dw", "dispatch-full-run", "skipped"),
  recordedJob(130771940258, "CR_kwDOTCGFQM8AAAAecp1zog", "post-merge-dispatch", "skipped"),
  recordedJob(130775014046, "CR_kwDOTCGFQM8AAAAecsxang", "unarmed-status", "skipped"),
];
const RECORDED = JSON.parse(readFileSync(new URL("./fixtures/recorded-annotations.json", import.meta.url), "utf8"));
const RECORDED_ANNOTATIONS_NODE = RECORDED.graphql;

test("the GraphQL check-run and annotation readers answer as the REST jobs and annotations reads of the same run", () => {
  assert.deepEqual(restJobs(RECORDED_NODE, RECORDED_RUN), RECORDED_JOBS);
  assert.equal(RECORDED.rest.length, 28);
  assert.deepEqual(restAnnotations(RECORDED_ANNOTATIONS_NODE, { id: RECORDED.checkRun }), RECORDED.rest);
});

test("a GraphQL answer that is cut short, holds a null, is another run's or a re-run's is no answer", () => {
  const checkRuns = RECORDED_NODE.checkSuite.checkRuns;
  const variants = [
    { ...RECORDED_NODE, runAttempt: 2 },
    { ...RECORDED_NODE, databaseId: 1 },
    { ...RECORDED_NODE, checkSuite: { checkRuns: { ...checkRuns, totalCount: 31 } } },
    { ...RECORDED_NODE, checkSuite: { checkRuns: { ...checkRuns, nodes: [...checkRuns.nodes.slice(1), null] } } },
    { ...RECORDED_NODE, checkSuite: { checkRuns: { totalCount: 0, nodes: [] } } },
    { ...RECORDED_NODE, checkSuite: null },
    null,
  ];
  for (const node of variants) assert.equal(restJobs(node, RECORDED_RUN), null, JSON.stringify(node)?.slice(0, 80));
  const annotations = RECORDED_ANNOTATIONS_NODE.annotations;
  for (const node of [
    { ...RECORDED_ANNOTATIONS_NODE, annotations: { ...annotations, totalCount: 101 } },
    { ...RECORDED_ANNOTATIONS_NODE, annotations: null },
    { ...RECORDED_ANNOTATIONS_NODE, databaseId: 1 },
    null,
  ]) {
    assert.equal(restAnnotations(node, { id: 130771889983 }), null, JSON.stringify(node)?.slice(0, 80));
  }
});

const fakeGraphql = (answer) => {
  const sent = [];
  const graphql = async (query, variables) => {
    sent.push(variables.ids);
    return answer(variables.ids, query);
  };
  return { graphql, sent };
};
const ids = (n) => Array.from({ length: n }, (_, i) => `N${i}`);
const echo = (list) => ({ data: { nodes: list.map((id) => ({ id })) } });

test("readNodes sends `batch` ids a query and returns each id's node in order", async () => {
  const { graphql, sent } = fakeGraphql(echo);
  const out = await readNodes(graphql, CHECK_RUN_ANNOTATIONS, ids(26));
  assert.deepEqual(sent.map((s) => s.length), [25, 1]);
  assert.deepEqual(out.map((n) => n.id), ids(26));
});

test("readNodes nulls only the node an error names, and the whole query on an error that names none", async () => {
  const { graphql } = fakeGraphql((list) => ({ ...echo(list), errors: [{ path: ["nodes", 1, "checkSuite"] }] }));
  assert.deepEqual(await readNodes(graphql, RUN_CHECK_RUNS, ids(3)), [{ id: "N0" }, null, { id: "N2" }]);
  const unnamed = fakeGraphql((list) => ({ ...echo(list), errors: [{ message: "Something went wrong" }] }));
  assert.deepEqual(await readNodes(unnamed.graphql, RUN_CHECK_RUNS, ids(3)), [null, null, null]);
});

test("without a latch a failed query leaves its ids null and the next batch is still sent", async () => {
  let calls = 0;
  const graphql = async (_query, { ids: list }) => {
    calls += 1;
    if (calls === 1) throw new Error("POST /graphql failed with status 502");
    return echo(list);
  };
  const out = await readNodes(graphql, RUN_CHECK_RUNS, ids(27));
  assert.equal(calls, 2);
  assert.deepEqual(out.slice(0, 25), Array(25).fill(null));
  assert.deepEqual(out.slice(25).map((n) => n.id), ["N25", "N26"]);
});

test("with a latch a query that fails or answers none of its ids stops every later query", async () => {
  for (const answer of [
    () => {
      throw new Error("POST /graphql failed with status 502");
    },
    (list) => ({ data: { nodes: list.map(() => null) } }),
    () => ({ data: {} }),
  ]) {
    const { graphql, sent } = fakeGraphql(answer);
    const latch = { failed: false };
    await readNodes(graphql, RUN_JOBS, ids(12), { latch });
    assert.equal(sent.length, 1);
    assert.equal(latch.failed, true);
    await readNodes(graphql, RUN_JOBS, ids(12), { latch });
    assert.equal(sent.length, 1, "a set latch sends nothing");
  }
  const { graphql, sent } = fakeGraphql(echo);
  const latch = { failed: false };
  await readNodes(graphql, RUN_JOBS, ids(12), { latch });
  assert.deepEqual(sent.map((s) => s.length), [5, 5, 2]);
  assert.equal(latch.failed, false);
});

test("readNodes sends no query for fewer ids left than minBatch", async () => {
  const { graphql, sent } = fakeGraphql(echo);
  const out = await readNodes(graphql, RUN_JOBS, ids(6), { minBatch: 2 });
  assert.deepEqual(sent.map((s) => s.length), [5]);
  assert.equal(out[5], null);
  assert.deepEqual(await readNodes(graphql, RUN_JOBS, ids(1), { minBatch: 2 }), [null]);
  assert.equal(sent.length, 1);
});

test("serveFirstAttemptJobs caches each served run under its REST paths and leaves the others out", async () => {
  const [verify, review] = PARITY.graphql.data.nodes;
  const runs = [
    { id: verify.databaseId, node_id: "WFR_verify" },
    { id: review.databaseId, node_id: "WFR_review" },
    { id: 7, node_id: "WFR_7" },
  ];
  const byId = { WFR_verify: verify, WFR_review: { ...review, runAttempt: 2 }, WFR_7: null };
  const { graphql, sent } = fakeGraphql((list, query) => {
    assert.equal(query, RUN_JOBS.query);
    return { data: { nodes: list.map((id) => byId[id]) } };
  });
  const cache = new Map();
  const latch = { failed: false };
  await serveFirstAttemptJobs(graphql, REPO, runs, cache, latch);
  assert.deepEqual(sent, [["WFR_verify", "WFR_review", "WFR_7"]]);
  assert.equal(latch.failed, false);
  const served = servedReads(REPO, runs[0], verify);
  assert.deepEqual([...cache.keys()].sort(), [...served.keys()].sort(), "only the first-attempt run is served");
  await serveFirstAttemptJobs(graphql, REPO, runs.slice(0, 1), cache, latch);
  assert.equal(sent.length, 1, "a cached run is not read again");
});

test("slimJob keeps the fields the rules read and drops the rest", () => {
  const job = {
    id: 1,
    node_id: "CR_1",
    name: "test",
    status: "completed",
    conclusion: "failure",
    runner_id: 42,
    html_url: "https://github.com/x",
    steps: [{ name: "Set up job", number: 1, status: "completed", conclusion: "success", started_at: "2026-11-01T00:00:00Z" }],
  };
  assert.deepEqual(slimJob(job), {
    id: 1,
    name: "test",
    status: "completed",
    conclusion: "failure",
    runner_id: 42,
    steps: [{ name: "Set up job", number: 1, status: "completed", conclusion: "success" }],
  });
});
