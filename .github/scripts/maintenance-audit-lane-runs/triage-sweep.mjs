import { appendFileSync, readFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { BORN_TRIAGED_MARKER, humanIds, readRouting, ROUTING_DEFAULTS, routingLabel } from "../../actions/check-born-triaged/check-born-triaged.mjs";
import { createGitHub } from "../lib/github-client.mjs";
import { budgetedCall, createBudget } from "./collect.mjs";
import { UNTRUSTED_LABELS } from "../pr-merge/merge-holds.mjs";
import { loadTrustedActors, statusLabels as labelsByField } from "../../actions/resolve-config/read-status.mjs";
import { statusWriter } from "../../actions/resolve-config/write-status.mjs";

const outOfBudget = (error) => /call budget/.test(error.message);
const STOP_PASS = Symbol("stop the pass");

export const MAX_DISPATCHES = 5;
const MAX_HANDED = 5;
const MAX_CHECKED = 20;
const MAX_ISSUE_PAGES = 15;
const COMMENT_PAGES = 3;
const ATTEMPTS = 2;
export const TRANSIENT_LIMIT = 24;
export const RUN_LIMIT = 6;
const MIN_AGE_MS = 3_600_000;
const HOUR_MS = 3_600_000;
const BOT = "github-actions[bot]";
export const FILING = "?";
export const HANDED = "handed";
const STATE = /^<!-- claude-lane triage-sweep runs=([0-9,+~-]*) filed=([0-9]*|\?|handed) -->/;
const HAND_BACK = /^(?:<!-- work-unblock handed triage #[1-9][0-9]* -->|<!-- work-unblock unparked triage -->(?:\n|$)|<!-- work-resolve-issue outcome=intake[ >]|<!-- intake-triage admission -->\n<!-- intake-triage retriage -->)/;
const HANDED_TEXT = "so the sweep no longer dispatches it";
const FLOOR = "needs-triage";
const HAND_OFF_FROM = [null, FLOOR];
const BORN_HAND_OFF_FROM = [...HAND_OFF_FROM, "ready"];
const TRIAGED = /^(needs-human|needs-spec|needs-owner-decision|needs-reporter-info|agent-ready|admission-deferred)$|^status: /;
const ADMISSION_HOLDS = new Set(["agent-ready", "admission-deferred", "needs-human", "needs-owner-decision", "needs-reporter-info", ...UNTRUSTED_LABELS]);

const names = (i, labels) => (labels ?? (i.labels ?? []).map((l) => l.name)).map((n) => String(n ?? "").toLowerCase());
const bornReady = (i, labels) =>
  String(i.body ?? "")
    .trimEnd()
    .endsWith(BORN_TRIAGED_MARKER) &&
  labels.includes("status: ready") &&
  !labels.some((n) => ADMISSION_HOLDS.has(n)) &&
  !(i.issue_dependencies_summary?.blocked_by > 0) &&
  !((i.sub_issues_summary?.total ?? 0) > (i.sub_issues_summary?.completed ?? 0));

export function selectCandidates({ issues, now, authorIds, statusLabels = new Map(), routing = ROUTING_DEFAULTS }) {
  const untriagedOrReady = (i) => {
    if (statusLabels.held?.has(i.number)) return false;
    if (routingLabel((i.labels ?? []).map((l) => l.name ?? ""), routing)) return false;
    const labels = names(i, statusLabels.get(i.number));
    return !labels.some((n) => TRIAGED.test(n)) || bornReady(i, labels);
  };
  return issues
    .filter((i) => !i.pull_request && authorIds.has(String(i.user?.id)) && untriagedOrReady(i) && now - new Date(i.created_at) >= MIN_AGE_MS)
    .sort((a, b) => new Date(a.created_at) - new Date(b.created_at) || a.number - b.number);
}

const neverCommented = (i) => i.comments === 0;
const rotatedPastCheckedCap = (group, eligibleCount, now) => {
  if (eligibleCount <= MAX_CHECKED) return group;
  const start = Math.floor(now / HOUR_MS) % group.length;
  return [...group.slice(start), ...group.slice(0, start)];
};

export function readState(comments, appId = null) {
  const handBack = Math.max(
    ...comments
      .filter((c) => appId !== null && String(c.user?.id) === String(appId) && HAND_BACK.test(String(c.body ?? "")))
      .map((c) => Date.parse(c.updated_at ?? c.created_at))
      .filter(Number.isFinite),
  );
  for (const c of comments) {
    const m = c.user?.login === BOT ? STATE.exec(String(c.body ?? "")) : null;
    if (m) {
      if (handBack > Date.parse(c.updated_at ?? c.created_at)) {
        return { commentId: c.id, runs: [], filed: null, reached: new Map() };
      }
      const entries = m[1] ? m[1].split(",") : [];
      return {
        commentId: c.id,
        runs: entries.map((e) => Number.parseInt(e, 10)),
        filed: m[2] === FILING || m[2] === HANDED ? m[2] : m[2] ? Number(m[2]) : null,
        reached: new Map(entries.filter((e) => /[+~-]$/.test(e)).map((e) => [Number.parseInt(e, 10), e.at(-1)])),
      };
    }
  }
  return { commentId: null, runs: [], filed: null, reached: new Map() };
}

const runEntry = (reached) => (id) => `${id}${reached.get(id) ?? ""}`;
export const renderState = ({ runs, filed, runUrl, repoUrl, details = [], reached = new Map() }) =>
  `<!-- claude-lane triage-sweep runs=${runs.map(runEntry(reached)).join(",")} filed=${filed ?? ""} -->\n` +
  (filed === HANDED
    ? [
        `Intake triage did not triage this issue after ${runs.length} dispatches, ${HANDED_TEXT} and set its Work status to needs-triage for a maintainer. Triage it by hand, and read the runs for why intake did not:`,
        "",
        ...details.map(
          (r) =>
            `- ${repoUrl}/actions/runs/${r.id} (${r.reached === "~" ? "a transient stop: a GitHub 5xx, a network error, a deferred triage or a kill switch" : `${r.conclusion ?? "unknown"}${r.reached === "-" ? ", intake did not run" : ""}`})`,
        ),
      ].join("\n")
    : filed === FILING
    ? `Intake triage did not triage this issue after ${runs.length} dispatches; the sweep set its Work status to needs-triage for a maintainer.`
    : filed
    ? `Intake triage did not triage this issue after ${runs.length} dispatches; #${filed} hands it to a maintainer.`
    : `The triage sweep dispatched [intake triage](${runUrl}) for this issue (dispatch ${runs.length}; ${ATTEMPTS} runs that reach intake, or ${RUN_LIMIT} dispatches, hand it to a maintainer).`);

const INTAKE_JOB = /^(?:Intake Triage|intake-triage)(?: \/ |$)/;
const INTAKE_APPLY_JOB = /^(?:(?:Intake Triage|intake-triage) \/ (?:.*-apply|Apply)|Post Triage|post-triage)$/;
const APPLY_JOB = "Apply Verdict";
const APPLY_JOB_BEFORE_RENAME = "apply-verdict";
export const reachedIntake = (jobs) =>
  (jobs ?? []).some((j) => INTAKE_JOB.test(String(j.name ?? "")) && j.status === "completed" && !["skipped", "cancelled"].includes(j.conclusion));
const applyJob = (jobs) => {
  const done = jobs.filter((j) => j.status === "completed");
  return done.find((j) => j.name === APPLY_JOB) ?? done.find((j) => j.name === APPLY_JOB_BEFORE_RENAME);
};

const TRANSIENT = /failed with status 5\d\d\b|GitHub answered 5\d\d\b|\bfetch failed\b|aborted due to timeout/;
const STATUS = /(?:failed with status|GitHub answered) (\d{3})\b/g;
const transientNote = (message) => {
  const statuses = [...message.matchAll(STATUS)].map((m) => m[1]);
  return statuses.length > 0 ? statuses.every((code) => code.startsWith("5")) : TRANSIENT.test(message);
};
const DEFERRED = "permission denial(s) on an otherwise clean triage";
const HELD = /^held: /;
const EXIT_LINE = /^Process completed with exit code \d+\.$/;
export const VOIDED_STEP = "Report the voided verdict";
export const voidedVerdict = (jobs) => Boolean(applyJob(jobs ?? [])?.steps?.some((s) => s?.name === VOIDED_STEP && s.conclusion === "success"));
const checkRunPath = (job) => {
  const id = /\/check-runs\/([0-9]+)$/.exec(String(job?.check_run_url ?? ""))?.[1];
  return id ? `/check-runs/${id}/annotations?per_page=100` : null;
};
export async function classifyRun(jobs, annotations) {
  if (!reachedIntake(jobs)) return "-";
  if (voidedVerdict(jobs)) return "~";
  const apply = applyJob(jobs);
  if (apply?.conclusion === "skipped") {
    const reusable = jobs.find((j) => INTAKE_APPLY_JOB.test(String(j.name ?? "")) && j.conclusion === "success");
    const path = checkRunPath(reusable);
    if (!path) return "+";
    const notes = (await annotations(path)) ?? [];
    return notes.some((a) => a?.annotation_level === "warning" && String(a.message ?? "").includes(DEFERRED)) ? "~" : "+";
  }
  const path = ["failure", "success"].includes(apply?.conclusion) ? checkRunPath(apply) : null;
  if (!path) return "+";
  const notes = ((await annotations(path)) ?? [])
    .filter(
      (a) =>
        a?.annotation_level === "failure" ||
        (a?.annotation_level === "warning" && /not written/.test(String(a.message ?? ""))) ||
        (a?.annotation_level === "notice" && HELD.test(String(a.message ?? ""))),
    )
    .filter((a) => !EXIT_LINE.test(String(a.message ?? "")));
  return notes.length > 0 && notes.every((a) => transientNote(String(a.message ?? ""))) ? "~" : "+";
}

export function tally(runs, marks) {
  const all = runs.map((id) => marks.get(id) ?? "+");
  const forgiven = Math.min(all.filter((m) => m === "~").length, TRANSIENT_LIMIT);
  return { attempts: all.filter((m) => m !== "-").length - forgiven, dispatches: runs.length - forgiven };
}

export function decide({ state, latest, reached = state.runs.length, dispatches = state.runs.length }) {
  if (state.filed) return "stop";
  if (state.runs.length === 0) return "dispatch";
  if (latest?.status !== "completed") return "wait";
  return reached >= ATTEMPTS || dispatches >= RUN_LIMIT ? "hand" : "dispatch";
}

const FILED_TITLE = /^Intake triage left #([1-9][0-9]*) untriaged after /;
const SEARCH_PAGES = 10;

async function search(call, query, pick) {
  const q = encodeURIComponent(query);
  const numbers = new Set();
  try {
    for (let page = 1; page <= SEARCH_PAGES; page += 1) {
      const found = await call("GET", `/search/issues?q=${q}&per_page=100&page=${page}`);
      if (found?.incomplete_results !== false) return new Set();
      for (const item of found.items ?? []) {
        const number = pick(item);
        if (number) numbers.add(number);
      }
      if ((found.items ?? []).length < 100) break;
    }
  } catch (error) {
    if (outOfBudget(error)) throw error;
    return new Set();
  }
  return numbers;
}

const HANDED_QUERY = `query($q: String!, $after: String) {
  search(query: $q, type: ISSUE, first: 50, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes { ... on Issue { number comments(first: 100) { nodes { author { __typename login ... on Bot { databaseId } } body createdAt updatedAt } } } }
  }
}`;
const isActionsBot = (author) => author?.__typename === "Bot" && author.login === "github-actions";

export function handedInComments(comments, appId = null) {
  const state = comments.find((c) => isActionsBot(c.author) && STATE.test(String(c.body ?? "")));
  if (STATE.exec(String(state?.body ?? ""))?.[2] !== HANDED) return false;
  const at = Date.parse(state.updatedAt ?? state.createdAt);
  return !comments.some(
    (c) =>
      appId !== null &&
      c.author?.__typename === "Bot" &&
      String(c.author.databaseId) === String(appId) &&
      HAND_BACK.test(String(c.body ?? "")) &&
      !(Date.parse(c.updatedAt ?? c.createdAt) <= at),
  );
}

async function handedInSweepComments(call, repo, appId) {
  const numbers = new Set();
  const q = `repo:${repo} is:issue is:open commenter:app/github-actions in:comments "${HANDED_TEXT}"`;
  let after = null;
  try {
    for (let page = 1; page <= SEARCH_PAGES; page += 1) {
      const answer = await call("POST", "/graphql", { query: HANDED_QUERY, variables: { q, after } });
      const found = answer?.data?.search;
      if (!found || answer.errors) return new Set();
      for (const node of found.nodes ?? []) {
        if (Number.isInteger(node?.number) && handedInComments(node.comments?.nodes ?? [], appId)) numbers.add(node.number);
      }
      if (!found.pageInfo?.hasNextPage) break;
      after = found.pageInfo.endCursor;
    }
  } catch (error) {
    if (outOfBudget(error)) throw error;
    return new Set();
  }
  return numbers;
}

async function handedOff(call, repo, appId) {
  const filed = await search(call, `repo:${repo} is:issue author:app/github-actions in:title "Intake triage left"`, (item) =>
    item.user?.login === BOT ? Number(FILED_TITLE.exec(String(item.title ?? ""))?.[1] ?? 0) : 0,
  );
  return new Set([...filed, ...(await handedInSweepComments(call, repo, appId))]);
}

export async function runSweep({ call, remaining = () => Infinity, repo, serverUrl, now, authorIds, appId = null, setStatus = async () => {}, statusLabels = new Map(), routing = ROUTING_DEFAULTS }) {
  const repoUrl = `${serverUrl}/${repo}`;
  const issues = [];
  for (let page = 1; page <= MAX_ISSUE_PAGES; page += 1) {
    const batch = await call("GET", `/repos/${repo}/issues?state=open&per_page=100&page=${page}`);
    issues.push(...batch);
    if (batch.length < 100) break;
  }
  const result = { candidates: 0, dispatched: [], handed: [], handedOff: [], held: [], left: [], waiting: [], failed: [], truncated: null };
  const selected = selectCandidates({ issues, now, authorIds, statusLabels, routing });
  const atFloor = (i) => names(i, statusLabels.get(i.number)).includes(FLOOR);
  const filed = selected.length > 0 ? await handedOff(call, repo, appId) : new Set();
  const eligible = selected.filter((i) => !(filed.has(i.number) && atFloor(i)));
  const candidates = [...eligible.filter(neverCommented), ...rotatedPastCheckedCap(eligible.filter((i) => !neverCommented(i)), eligible.length, now)];
  result.candidates = candidates.length;
  const listedReady = (i) => names(i, statusLabels.get(i.number)).includes("status: ready");
  const handOff = async (issue) => {
    const { number } = issue;
    const written = await setStatus(number, FLOOR, { keepHold: true, from: listedReady(issue) ? BORN_HAND_OFF_FROM : HAND_OFF_FROM });
    if (written?.outcome === "held") result.held.push(number);
    if (written?.outcome === "moved") {
      result.left.push(number);
      console.log(`triage-sweep: #${number} left as is: its Work status is ${written.state}`);
    }
    return written?.outcome !== "held" && written?.outcome !== "moved";
  };
  let checked = 0;
  const redispatches = [];
  let outOfCalls = false;
  for (const issue of candidates) {
    const { number } = issue;
    if (checked >= MAX_CHECKED) break;
    if (result.dispatched.length >= MAX_DISPATCHES && result.handed.length >= MAX_HANDED) break;
    if (neverCommented(issue) && result.dispatched.length + result.failed.length >= MAX_DISPATCHES) continue;
    try {
      const comments = [];
      let full = false;
      for (let page = 1; page <= COMMENT_PAGES; page += 1) {
        const batch = (await call("GET", `/repos/${repo}/issues/${number}/comments?per_page=100&page=${page}`)) ?? [];
        comments.push(...batch);
        full = batch.length === 100;
        if (!full) break;
      }
      if (full) {
        if (atFloor(issue)) continue;
        checked += 1;
        if (await handOff(issue)) result.handedOff.push(number);
        continue;
      }
      const state = readState(comments, appId);
      if (state.filed) continue;
      checked += 1;
      const last = state.runs.at(-1);
      const latest = state.runs.length > 0 ? await call("GET", `/repos/${repo}/actions/runs/${last}`) : null;
      const finished = state.runs.length > 0 && latest === null ? { status: "completed" } : latest;
      const known = new Map(state.reached);
      const reached = new Map(known);
      const capped = state.runs.length >= RUN_LIMIT && result.handed.length >= MAX_HANDED;
      if (state.runs.length >= ATTEMPTS && finished?.status === "completed" && !capped) {
        for (const id of state.runs.filter((r) => !known.has(r))) {
          try {
            const answer = await call("GET", `/repos/${repo}/actions/runs/${id}/jobs?per_page=100`);
            known.set(id, answer === null ? "+" : await classifyRun(answer.jobs ?? [], (path) => call("GET", `/repos/${repo}${path}`)));
            reached.set(id, known.get(id));
          } catch (error) {
            if (outOfBudget(error)) throw error;
            reached.set(id, "+");
          }
        }
      }
      const { attempts, dispatches } = tally(state.runs, reached);
      const action = decide({ state, latest: finished, reached: attempts, dispatches });
      if (action === "wait") result.waiting.push(number);
      const entry = { issue, state, known, reached, last, latest };
      if (action === "dispatch" && state.runs.length > 0) {
        if ((await act(entry, "stop")) === STOP_PASS) break;
        redispatches.push({ ...entry, state: { ...state, reached: known } });
        continue;
      }
      if ((await act(entry, action)) === STOP_PASS) break;
    } catch (error) {
      if (endsPass(number, error)) break;
    }
  }
  if (outOfCalls) return result;
  for (const entry of redispatches) {
    if ((await act(entry, "dispatch")) === STOP_PASS) break;
  }
  return result;

  function endsPass(number, error) {
    if (!outOfBudget(error)) {
      result.failed.push({ number, error: error.message });
      return false;
    }
    result.truncated = `stopped at #${number}: ${error.message}`;
    outOfCalls = true;
    return true;
  }

  async function act({ issue, state, known, reached, last, latest }, action) {
    const { number } = issue;
    try {
      if (action === "dispatch" && result.dispatched.length >= MAX_DISPATCHES) action = "stop";
      if (action === "hand" && result.handed.length >= MAX_HANDED) action = "stop";
      if (action === "stop" && known.size > state.reached.size && remaining() > 0) {
        try {
          await writeState(call, repo, number, state, {
            runs: state.runs,
            filed: null,
            runUrl: `${repoUrl}/actions/runs/${last}`,
            reached: known,
          });
        } catch (error) {
          if (outOfBudget(error)) throw error;
        }
        return;
      }
      const reads = state.runs.filter((id) => id !== last && reached.get(id) !== "~").length;
      if ((action === "dispatch" && remaining() < 2) || (action === "hand" && remaining() < reads + 2)) {
        result.truncated = `stopped at #${number}: too little call budget left`;
        return STOP_PASS;
      }
      if (action === "dispatch") {
        const sent = await call("POST", `/repos/${repo}/actions/workflows/intake-triage.yml/dispatches`, {
          ref: "main",
          inputs: { "issue-number": String(number) },
          return_run_details: true,
        });
        const id = Number(sent?.workflow_run_id);
        if (!Number.isInteger(id) || id <= 0) throw new Error("the dispatch returned no run id");
        result.dispatched.push(number);
        await writeState(call, repo, number, state, {
          runs: [...state.runs, id],
          filed: null,
          runUrl: `${repoUrl}/actions/runs/${id}`,
          reached: known,
        });
      }
      if (action === "hand") {
        const runs = [];
        for (const id of state.runs) {
          const run = id === last ? latest : reached.get(id) === "~" ? null : await call("GET", `/repos/${repo}/actions/runs/${id}`);
          runs.push({ id, conclusion: run?.conclusion ?? null, reached: reached.get(id) });
        }
        if (!(await handOff(issue))) return;
        await writeState(call, repo, number, state, { runs: state.runs, filed: HANDED, repoUrl, details: runs, reached: known });
        result.handed.push(number);
      }
    } catch (error) {
      if (endsPass(number, error)) return STOP_PASS;
    }
  }
}

export async function statusListing({ github, repository, config, trustedActors, issuesByStatus }) {
  if (!config) return new Map();
  const listed = await issuesByStatus(github, repository, config.order, { config, trustedActors });
  const agentReady = new Set((config.labels["agent-ready"] ?? []).map((name) => name.toLowerCase()));
  const byField = (i) => ((i.state ?? null) === null ? i.labels.filter((name) => !agentReady.has(name.toLowerCase())) : labelsByField(i.state, i.labels, config));
  const map = new Map(listed.map((i) => [i.number, byField(i)]));
  map.held = new Set((listed.held ?? []).map((i) => i.number));
  return map;
}

async function writeState(call, repo, number, state, next) {
  const body = { body: renderState(next) };
  if (state.commentId) await call("PATCH", `/repos/${repo}/issues/comments/${state.commentId}`, body);
  else await call("POST", `/repos/${repo}/issues/${number}/comments`, body);
}

async function main() {
  const env = process.env;
  const budget = createBudget(Number(env.CALL_BUDGET ?? 120));
  const call = budgetedCall(env, budget);
  const list = JSON.parse(readFileSync(env.TRUSTED_ACTORS_PATH, "utf8"));
  const authorIds = new Set(humanIds(list).split(",").filter(Boolean));
  const appId = /^[1-9][0-9]*$/.test(env.LANES_APP_ID ?? "") ? env.LANES_APP_ID : null;
  if (appId) authorIds.add(appId);
  const github = createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
  const { set } = await statusWriter({ env, github, repository: env.REPOSITORY });
  const { issueStatusFromBase, issuesByStatus } = await import("../../actions/resolve-config/resolve-config.mjs");
  const statusLabels = await statusListing({ github, repository: env.REPOSITORY, config: issueStatusFromBase(env), trustedActors: loadTrustedActors(env), issuesByStatus });
  const result = await runSweep({
    call,
    remaining: () => budget.limit - budget.used,
    repo: env.REPOSITORY,
    serverUrl: env.GITHUB_SERVER_URL,
    now: new Date(),
    authorIds,
    appId,
    setStatus: set,
    statusLabels,
    routing: readRouting(join(env.BASE_PATH || ".base", "docs/conventions/work-items.yaml"), { who: "triage-sweep" }),
  });
  const numbers = (xs) => xs.map((n) => `#${n}`).join(", ") || "none";
  const lines = [
    "### Triage sweep",
    "",
    `Candidates: ${result.candidates}. Dispatched: ${numbers(result.dispatched)}. Handed to a maintainer after ${ATTEMPTS} runs that reached intake or ${RUN_LIMIT} dispatches: ${numbers(result.handed)}. Handed off for too many comments: ${numbers(result.handedOff)}. Held by a person's hold: ${numbers(result.held)}. Left as is past triage: ${numbers(result.left)}. Waiting on a run: ${numbers(result.waiting)}. Calls: ${budget.used}.`,
    "",
    ...(result.truncated ? [`- ${result.truncated}`] : []),
    ...result.failed.map((f) => `- failed #${f.number}: ${f.error}`),
  ];
  appendFileSync(env.GITHUB_STEP_SUMMARY, `${lines.join("\n")}\n`);
  console.log(
    `triage-sweep: candidates ${result.candidates}, dispatched ${result.dispatched.length}, handed ${result.handed.length}, waiting ${result.waiting.length}, failed ${result.failed.length}, calls ${budget.used}`,
  );
  if (result.failed.length > 0) {
    console.log(`::error::${result.failed.length} triage sweep issue(s) failed; see the step summary`);
    process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
