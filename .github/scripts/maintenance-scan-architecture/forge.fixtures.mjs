import { readFileSync } from "node:fs";

const captured = (name) => JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8"));

export const RUNS = captured("workflow-runs.json");
export const JOBS = captured("run-jobs.json");
export const ISSUES = captured("issues-page.json");
export const LABEL = captured("label.json");
export const ISSUE = captured("issue.json");

const [RUN] = RUNS.workflow_runs;
const OPEN_ISSUE = ISSUES.find((item) => !item.pull_request);
const PULLS = ISSUES.filter((item) => item.pull_request);

export const run = (index, { at, sha }) => ({ ...structuredClone(RUN), id: RUN.id - index, run_number: RUN.run_number - index, created_at: new Date(at).toISOString(), head_sha: sha });

export function jobsOf(scan) {
  const jobs = structuredClone(JOBS.jobs)
    .filter((job) => scan !== "absent" || job.name !== "Scan")
    .map((job) => (job.name === "Scan" ? { ...job, conclusion: scan } : job));
  return { ...JOBS, total_count: jobs.length, jobs };
}

export const issue = (index, title = `${OPEN_ISSUE.title} ${index}`) => ({ ...structuredClone(OPEN_ISSUE), number: OPEN_ISSUE.number - index, title });

const pageOf = (path) => Number(/[?&]page=(\d+)/.exec(path)?.[1] ?? 1);
const perPageOf = (path) => Number(/[?&]per_page=(\d+)/.exec(path)?.[1] ?? 30);
const slice = (items, path) => items.slice((pageOf(path) - 1) * perPageOf(path), pageOf(path) * perPageOf(path));

export function forge({ runs = [], open = 0, filed = [], label = true } = {}) {
  const calls = [];
  const posts = [];
  const openItems = [...PULLS.map((item) => structuredClone(item)), ...Array.from({ length: open }, (_, i) => issue(i))];
  const allItems = [...openItems, ...filed.map((title, i) => issue(open + i, title))];
  const scans = new Map(runs.map((entry, i) => [run(i, entry).id, entry.scan ?? "success"]));
  const listed = runs.map((entry, i) => run(i, entry));
  const call = async (method, path, body) => {
    calls.push(`${method} ${path}`);
    if (method === "POST") {
      posts.push(body);
      return { ...structuredClone(ISSUE), number: ISSUE.number + posts.length, title: body.title, labels: body.labels.map((name) => ({ name })), type: { name: body.type } };
    }
    if (path.includes("/labels/")) return label ? structuredClone(LABEL) : null;
    if (path.includes("/actions/workflows/")) return { total_count: listed.length, workflow_runs: slice(listed, path) };
    const jobsFor = /\/actions\/runs\/(\d+)\/jobs/.exec(path);
    if (jobsFor) return jobsOf(scans.get(Number(jobsFor[1])));
    if (path.includes("/issues?")) return slice(path.includes("state=all") ? allItems : openItems, path);
    throw new Error(`the fake forge has no answer for ${method} ${path}`);
  };
  return { call, calls, posts };
}
