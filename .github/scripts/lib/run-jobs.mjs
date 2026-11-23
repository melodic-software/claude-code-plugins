export const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
export const jobsKey = (id, attempt) => `${id}:${attempt}`;

export const slimJob = (job) => ({
  id: job.id,
  name: job.name,
  status: job.status,
  conclusion: job.conclusion,
  ...(job.runner_id === undefined ? {} : { runner_id: job.runner_id }),
  steps: Array.isArray(job.steps) ? job.steps.map((s) => ({ name: s?.name, number: s?.number, status: s?.status, conclusion: s?.conclusion })) : job.steps,
});

/** The `graphql(query, variables)` readNodes takes, for a github-client.mjs client. */
export const graphqlCall = (github) => (query, variables) => github("POST", "/graphql", { query, variables });

const CHECK_RUNS_PAGE = 30;
const STEP_FIELDS = "totalCount nodes { name number status conclusion }";
/**
 * Runs' first-attempt check runs with their steps and annotations. Two step
 * connections, the first and the last 100, cover a job of up to 200 steps
 * (pr-verify's Check Intent lists 117). Measured: 5 runs answered in about
 * 2 s for 5 points, 10 in about 6 s, and 25 hit GraphQL's 10 s limit (504).
 */
export const RUN_JOBS = {
  batch: 5,
  query: `query($ids: [ID!]!) { nodes(ids: $ids) { ... on WorkflowRun { databaseId runAttempt checkSuite { checkRuns(first: ${CHECK_RUNS_PAGE}, filterBy: { checkType: ALL }) { totalCount nodes { databaseId name status conclusion head: steps(first: 100) { ${STEP_FIELDS} } tail: steps(last: 100) { ${STEP_FIELDS} } annotations(first: 100) { totalCount nodes { annotationLevel title message } } } } } } } }`,
};
/** Runs' first-attempt check runs without steps: 25 a query answer in about a second. */
export const RUN_CHECK_RUNS = {
  batch: 25,
  query: `query($ids: [ID!]!) { nodes(ids: $ids) { ... on WorkflowRun { databaseId runAttempt checkSuite { checkRuns(first: ${CHECK_RUNS_PAGE}, filterBy: { checkType: ALL }) { totalCount nodes { id databaseId name status conclusion } } } } } }`,
};
/** Check runs' annotations, 25 a query. */
export const CHECK_RUN_ANNOTATIONS = {
  batch: 25,
  query: "query($ids: [ID!]!) { nodes(ids: $ids) { ... on CheckRun { databaseId annotations(first: 100) { totalCount nodes { annotationLevel title message } } } } }",
};

/**
 * Each id's node, in order, or null where the answer has none, an error names
 * it, or its query failed: the caller reads that one through REST. `read` is
 * RUN_JOBS, RUN_CHECK_RUNS or CHECK_RUN_ANNOTATIONS. Fewer ids left than
 * `minBatch` are sent no query. With `latch`, a query that fails or answers
 * none of its ids (`answers(node, index)`) sets latch.failed, and no query is
 * sent while it is set.
 */
export async function readNodes(graphql, read, ids, { minBatch = 1, latch, answers = (node) => node !== null } = {}) {
  const out = ids.map(() => null);
  const fail = () => {
    if (latch) latch.failed = true;
  };
  for (let at = 0; ids.length - at >= minBatch && !latch?.failed; at += read.batch) {
    const slice = ids.slice(at, at + read.batch);
    let result;
    try {
      result = await graphql(read.query, { ids: slice });
    } catch {
      fail();
      continue;
    }
    const errors = result?.errors ?? [];
    const named = errors.map((e) => (e?.path?.[0] === "nodes" && Number.isInteger(e.path[1]) ? e.path[1] : null));
    if (!Array.isArray(result?.data?.nodes) || named.includes(null)) {
      fail();
      continue;
    }
    result.data.nodes.forEach((node, i) => {
      if (i < slice.length && !named.includes(i)) out[at + i] = node ?? null;
    });
    if (!slice.some((_, i) => answers(out[at + i], at + i))) fail();
  }
  return out;
}

const lower = (value) => (typeof value === "string" ? value.toLowerCase() : null);
const wholeNodes = (connection) =>
  Array.isArray(connection?.nodes) && connection.nodes.length === connection.totalCount && connection.nodes.every(isObject) ? connection.nodes : null;
const firstAttemptChecks = (node, run) => {
  const checks = node?.databaseId === run?.id && node.runAttempt === 1 ? wholeNodes(node.checkSuite?.checkRuns) : null;
  return checks?.length ? checks : null;
};
const restJob = (check) => ({
  id: check.databaseId,
  ...(typeof check.id === "string" ? { node_id: check.id } : {}),
  name: check.name,
  status: lower(check.status),
  conclusion: lower(check.conclusion),
});
const restAnnotation = (a) => ({ annotation_level: lower(a.annotationLevel), title: a.title, message: a.message });

/** A RUN_CHECK_RUNS node's jobs as the REST jobs list shapes them, oldest first, without steps, or null when it does not answer for the run in full. */
export function restJobs(node, run) {
  const checks = firstAttemptChecks(node, run);
  if (!checks?.every((c) => Number.isSafeInteger(c.databaseId) && typeof c.id === "string")) return null;
  return checks.map(restJob).sort((a, b) => a.id - b.id);
}

/** A CHECK_RUN_ANNOTATIONS node's annotations as REST shapes the fields the rules read, or null. */
export function restAnnotations(node, job) {
  const nodes = node?.databaseId === job.id ? wholeNodes(node.annotations) : null;
  return nodes && nodes.map(restAnnotation);
}

export const firstAttemptJobsPath = (repo, id) => `/repos/${repo}/actions/runs/${id}/attempts/1/jobs?per_page=100`;
export const annotationsPath = (repo, id) => `/repos/${repo}/check-runs/${id}/annotations?per_page=100`;

/**
 * The REST answers one RUN_JOBS node stands in for, by path: the run's
 * first-attempt job listing and each job's annotations. Undefined, so REST
 * reads the run, unless the node answers for the first attempt in full: every
 * job, every step and every annotation listed. A job with no steps stands in
 * only when it was skipped, since stepsKnown reads such a job's runner_id,
 * which GraphQL does not give; a skipped job never had a runner.
 */
export function servedReads(repo, run, node) {
  const checks = firstAttemptChecks(node, run);
  if (!checks) return undefined;
  const reads = new Map();
  const jobs = [];
  for (const check of checks) {
    const { head, tail } = check;
    const annotations = wholeNodes(check.annotations);
    if (!Number.isSafeInteger(check.databaseId) || !Array.isArray(head?.nodes) || !Array.isArray(tail?.nodes) || head.totalCount !== tail.totalCount || !annotations) {
      return undefined;
    }
    const steps = new Map([...head.nodes, ...tail.nodes].map((s) => [s?.number, s]));
    if (steps.size !== head.totalCount || ![...steps.keys()].every(Number.isSafeInteger) || (steps.size === 0 && lower(check.conclusion) !== "skipped")) {
      return undefined;
    }
    jobs.push({
      ...restJob(check),
      ...(steps.size === 0 ? { runner_id: null } : {}),
      steps: [...steps.values()].sort((a, b) => a.number - b.number).map((s) => ({ name: s.name, number: s.number, status: lower(s.status), conclusion: lower(s.conclusion) })),
    });
    reads.set(annotationsPath(repo, check.databaseId), annotations.map(restAnnotation));
  }
  reads.set(firstAttemptJobsPath(repo, run.id), { total_count: jobs.length, jobs: jobs.sort((a, b) => a.id - b.id) });
  return reads;
}

/**
 * Reads the runs' first-attempt jobs through RUN_JOBS into `cache`, by the
 * REST path each answer stands in for. A batch of one run is left to REST,
 * where it costs the same one call. A run the answer does not cover in full is
 * read through REST; after a query fails, by error or GraphQL's own rate
 * limit, or answers for none of its runs, every later run is too
 * (`latch.failed`), so this never stops a pass REST would finish.
 */
export async function serveFirstAttemptJobs(graphql, repo, runs, cache, latch) {
  const wanted = [...new Map(runs.filter((r) => Number.isSafeInteger(r?.id) && typeof r.node_id === "string" && !cache.has(firstAttemptJobsPath(repo, r.id))).map((r) => [r.id, r])).values()];
  const nodes = await readNodes(graphql, RUN_JOBS, wanted.map((r) => r.node_id), {
    minBatch: 2,
    latch,
    answers: (node, i) => node?.databaseId === wanted[i].id && node.runAttempt === 1,
  });
  wanted.forEach((r, i) => {
    for (const [path, answer] of servedReads(repo, r, nodes[i]) ?? []) cache.set(path, answer);
  });
}
