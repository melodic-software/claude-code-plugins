// The hourly triage sweep: finds open issues no intake verdict holds and
// dispatches intake-triage.yml for them, with the job's own token only. An
// issue qualifies when it is no pull request, is over an hour old, its author
// is a listed human or the lanes App (as the intake lane admits on open), it
// carries no routing label (intake skips one: check-born-triaged.mjs), and
// either:
//
// - its labels, as its Work status field decides them (read-status.mjs
//   statusLabels, from one issuesByStatus listing), hold no `status:` label
//   and no agent-ready, admission-deferred or hold, whatever comments intake
//   left: a triage that posted no comment or two, a
//   verdict apply-verdict could not write (an issue the lanes App opened,
//   whose --check refuses the App as actor while a github-actions[bot]
//   dispatch passes), or an issue work-unblock handed back after its lane PR
//   ended or unparked to needs-triage once a blocker closed; or
// - /work-items:decompose published it born triaged in `status: ready`, with
//   no agent-ready, admission-deferred or hold, no open blocker and no open
//   sub-issue: intake's dispatch runs it (a dispatch skips the born-triaged
//   gate), including once a wait admission left on it has cleared.
//
// The needs-triage floor label is no triage label: it lands on open whether
// or not intake runs. github-actions[bot] issues are left out: the lane
// sweep's can quote fork-controlled log lines. Per issue, one comment holds the runs
// dispatched and, once read, how each ended; after 2 that reached intake and left it untriaged (a run the
// kill switch or a gate skipped before intake does not count, up to 6
// dispatches, and nor do the first 24 whose verdict stopped on a GitHub 5xx,
// a network error, a deferred triage or a kill switch) the sweep sets its Work status to
// needs-triage (write-status.mjs) and rewrites that comment to hand it to a
// maintainer, listing the runs. That write first reads the field fresh and
// leaves any state but unset or needs-triage (or ready, on an issue listed
// at status: ready), so an issue admitted
// since the listing is never demoted. It files no issue. No model. The count is per triage cycle: a work-unblock
// hand-back comment the lanes App posted after the state comment's last edit
// starts a new cycle with no runs, in the same comment. An issue still at
// needs-triage whose own state comment hands it off is skipped
// without a REST read, found by one GraphQL search that returns the hits'
// comments, so hand-offs cannot use up the call budget.
//
// A run whose verdict a lanes kill switch voided (apply-verdict's VOIDED_STEP)
// wrote nothing, so it counts as a transient stop, not an attempt.
//
// Accepted exposure: intake reads an issue's comments, and anyone can comment
// in the hour before the sweep dispatches. Intake treats them as untrusted
// data and applies only allowlisted labels, never agent-ready.
import { appendFileSync, readFileSync } from "node:fs";
import { join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { BORN_TRIAGED_MARKER, humanIds, readRouting, ROUTING_DEFAULTS, routingLabel } from "../../actions/check-born-triaged/check-born-triaged.mjs";
import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { budgetedCall, createBudget } from "./collect.mjs";
import { UNTRUSTED_LABELS } from "../pr-merge/merge-holds.mjs";
import { loadTrustedActors, statusLabels as labelsByField } from "../../actions/resolve-config/read-status.mjs";
import { statusWriter } from "../../actions/resolve-config/write-status.mjs";

const outOfBudget = (error) => /call budget/.test(error.message);

export const MAX_DISPATCHES = 5;
const MAX_HANDED = 5;
const MAX_CHECKED = 20;
const MAX_ISSUE_PAGES = 15;
const COMMENT_PAGES = 3;
// A run counts as an attempt only when it reached intake (reachedIntake) and
// its verdict did not stop on a transient answer (classifyRun).
const ATTEMPTS = 2;
// judgment: about a day of hourly sweeps. Past this many runs that stopped on a
// transient answer, each further one counts as an attempt, so a fault that
// never clears still reaches a person.
export const TRANSIENT_LIMIT = 24;
export const RUN_LIMIT = 6;
const MIN_AGE_MS = 3_600_000;
const BOT = "github-actions[bot]";
// `filed` is HANDED once the comment hands the issue to a maintainer. An older
// sweep's record holds the number of the issue it filed, or FILING while that
// filing was under way; both stop the sweep too.
export const FILING = "?";
export const HANDED = "handed";
// Each run id in `runs=` may carry `+` (it reached intake and counts), `~` (it
// reached intake and stopped on a transient answer) or `-` (it did not reach
// intake), so a finished run is read once; an unmarked id is unread.
const STATE = /^<!-- claude-lane triage-sweep runs=([0-9,+~-]*) filed=([0-9]*|\?|handed) -->/;
// work-unblock's comment when it hands an issue back to triage after its lane
// PR merged with Refs: or closed unmerged (label-unblocked.mjs handedMarker),
// the issue lane's when a stop's intake route sends it back
// (report-outcome.mjs, outcome=intake), admission's when a blocker's
// report-delivered close sends it back (admit.mjs retriageNote), and
// work-unblock's when it unparks the issue to needs-triage, as its first line.
// Admission edits its comment in place, so a hand-back counts from its last edit.
const HAND_BACK = /^(?:<!-- work-unblock handed triage #[1-9][0-9]* -->|<!-- work-unblock unparked triage -->(?:\n|$)|<!-- work-resolve-issue outcome=intake[ >]|<!-- intake-triage admission -->\n<!-- intake-triage retriage -->)/;
// The visible text of the hand-off comment, which the search matches.
const HANDED_TEXT = "so the sweep no longer dispatches it";
const FLOOR = "needs-triage";
// The Work status states a hand-off may replace (null for unset): untriaged,
// and ready only on an issue the listing saw at status: ready (bornReady),
// since admission and work-unblock also write ready.
const HAND_OFF_FROM = [null, FLOOR];
const BORN_HAND_OFF_FROM = [...HAND_OFF_FROM, "ready"];
// Labels a verdict or a person leaves: an issue with one is triaged.
const TRIAGED = /^(needs-human|needs-spec|needs-owner-decision|needs-reporter-info|agent-ready|admission-deferred)$|^status: /;
// What keeps a born-triaged `status: ready` issue out of admission on purpose.
const ADMISSION_HOLDS = new Set(["agent-ready", "admission-deferred", "needs-human", "needs-owner-decision", "needs-reporter-info", ...UNTRUSTED_LABELS]);

// An issue's lowercased label names; `labels`, when given, stands in for its
// own (as its Work status field decides them, statusListing).
const names = (i, labels) => (labels ?? (i.labels ?? []).map((l) => l.name)).map((n) => String(n ?? "").toLowerCase());
// An open sub-issue makes admission wait (admit.mjs openSubIssues), so it
// would only send the issue back at status: ready. Admission's own wait
// comment is not consulted: admission edits it in place, so it can outlive
// the wait it describes and would park a cleared issue for good.
const bornReady = (i, labels) =>
  String(i.body ?? "")
    .trimEnd()
    .endsWith(BORN_TRIAGED_MARKER) &&
  labels.includes("status: ready") &&
  !labels.some((n) => ADMISSION_HOLDS.has(n)) &&
  !(i.issue_dependencies_summary?.blocked_by > 0) &&
  !((i.sub_issues_summary?.total ?? 0) > (i.sub_issues_summary?.completed ?? 0));

// `statusLabels` (statusListing) maps an issue number to its label names as
// its Work status field decides them; an issue it leaves out is judged by its
// own labels, except one in its `held` set (Work status mid-write), which is
// not dispatched this pass (conservative: no dispatch on a state not read).
// An issue whose own labels hold a routing label (check-born-triaged.mjs
// routingLabel) is never one: intake skips it.
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

// `appId` is the lanes App's account id: only its hand-back starts a new
// cycle, so no one else can reset the dispatch count.
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

// `details` lists each run as {id, conclusion}, for the hand-off; `reached`
// maps each run read so far to its mark (classifyRun).
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

// Whether a run reached intake, from its jobs: the Intake Triage caller job, or
// a job of the reusable it calls ("Intake Triage / ..."), finished neither
// skipped nor cancelled. The kill switch, a degraded upstream or a born-triaged
// gate skips it; a run cancelled before it, or that never started, lists it
// cancelled, skipped or not at all. A run from before the job rename names the
// caller intake-triage and the verdict job apply-verdict.
const INTAKE_JOB = /^(?:Intake Triage|intake-triage)(?: \/ |$)/;
const INTAKE_APPLY_JOB = /^(?:Intake Triage|intake-triage) \/ .*-apply$/;
const APPLY_JOB = "Apply Verdict";
const APPLY_JOB_BEFORE_RENAME = "apply-verdict";
export const reachedIntake = (jobs) =>
  (jobs ?? []).some((j) => INTAKE_JOB.test(String(j.name ?? "")) && j.status === "completed" && !["skipped", "cancelled"].includes(j.conclusion));
const applyJob = (jobs) => {
  const done = jobs.filter((j) => j.status === "completed");
  return done.find((j) => j.name === APPLY_JOB) ?? done.find((j) => j.name === APPLY_JOB_BEFORE_RENAME);
};

// A run's mark, from its jobs and one annotations read (`annotations(path)`
// returns a check run's annotation list): `-` when it never reached intake,
// `~` when it stopped on a transient answer, `+` otherwise, so whatever cannot
// be told apart counts. Transient is either:
// - apply-verdict failed or succeeded, and every failure annotation, every
//   "not written" warning and every `held: ` notice it left names a GitHub 5xx, a timeout or a network
//   failure (runs 41814429466 and 41814435576: "failed with status 500",
//   "GitHub answered 500"); or
// - apply-verdict was skipped because the reusable's apply job deferred an
//   otherwise clean triage on a permission denial (run 41807993284), which
//   writes nothing so that a later run retries it; or
// - apply-verdict ran VOIDED_STEP (voidedVerdict), read from the jobs alone.
// No open-incident signal is read: the run's own upstream check skips intake
// while githubstatus.com lists Actions in an outage, which marks it `-`, and
// nothing records an API incident at the time a run ran.
const TRANSIENT = /failed with status 5\d\d\b|GitHub answered 5\d\d\b|\bfetch failed\b|aborted due to timeout/;
// apply-verdict joins several write failures into one annotation (its
// missedAnnotation), so a note is transient only when every status it reports
// is a 5xx: "GitHub answered 500" beside "GitHub answered 403" counts. A note
// that reports no status is read by TRANSIENT alone (a timeout, a reset).
const STATUS = /(?:failed with status|GitHub answered) (\d{3})\b/g;
const transientNote = (message) => {
  const statuses = [...message.matchAll(STATUS)].map((m) => m[1]);
  return statuses.length > 0 ? statuses.every((code) => code.startsWith("5")) : TRANSIENT.test(message);
};
const DEFERRED = "permission denial(s) on an otherwise clean triage";
// apply-verdict's notice when a fault held it green (its closing), read as a
// failure annotation is.
const HELD = /^held: /;
const EXIT_LINE = /^Process completed with exit code \d+\.$/;
// The apply-verdict step (intake-triage.yml) that runs only when a lanes kill
// switch refused its token, so the run wrote no verdict.
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

// What the marks add up to: `attempts` the runs that count (an unread run
// counts), `dispatches` the runs RUN_LIMIT sees. The first TRANSIENT_LIMIT
// transient runs count toward neither; each one past them counts toward both.
export function tally(runs, marks) {
  const all = runs.map((id) => marks.get(id) ?? "+");
  const forgiven = Math.min(all.filter((m) => m === "~").length, TRANSIENT_LIMIT);
  return { attempts: all.filter((m) => m !== "-").length - forgiven, dispatches: runs.length - forgiven };
}

// `reached` counts the attempts; unread, every run counts. RUN_LIMIT bounds
// the runs that never reached intake: the sweep's own kill-switch check stops
// it while the switch is on, so only a gate that keeps skipping intake (a long
// upstream degradation, a born-triaged read that keeps failing) gets there.
// `dispatches` leaves out the transient runs tally forgives.
export function decide({ state, latest, reached = state.runs.length, dispatches = state.runs.length }) {
  if (state.filed) return "stop";
  if (state.runs.length === 0) return "dispatch";
  if (latest?.status !== "completed") return "wait";
  return reached >= ATTEMPTS || dispatches >= RUN_LIMIT ? "hand" : "dispatch";
}

const FILED_TITLE = /^Intake triage left #([1-9][0-9]*) untriaged after /;
const SEARCH_PAGES = 10;

// The numbers `pick` takes from one search's items. A failed or incomplete
// search excludes nothing: those issues are then read and skipped by their state.
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

// The issues this sweep handed off in a comment, from one GraphQL search per
// 50 issues that also returns each hit's first 100 comments, so a hit costs no
// REST read. The search only finds issues where github-actions commented and
// some comment, by anyone, holds the hand-off text, so a hit counts only when
// the bot's own state comment reads filed=handed and no hand-back
// by the lanes App (`appId`, as readState takes it) is newer than it; anything
// else is read and judged as usual. A failed search excludes nothing.
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

// The issues handed to a maintainer, so their comments cost no reads: those an
// older sweep filed a hand-off issue for (only a title the bot wrote counts),
// and those whose own state comment hands them off (handedInSweepComments).
// The caller skips them only while they are at needs-triage.
async function handedOff(call, repo, appId) {
  const filed = await search(call, `repo:${repo} is:issue author:app/github-actions in:title "Intake triage left"`, (item) =>
    item.user?.login === BOT ? Number(FILED_TITLE.exec(String(item.title ?? ""))?.[1] ?? 0) : 0,
  );
  return new Set([...filed, ...(await handedInSweepComments(call, repo, appId))]);
}

// One pass. `call` returns null for a GET that 404s. `setStatus(number,
// state)` (write-status.mjs statusWriter's set) writes the Work status field.
// `statusLabels` is statusListing's map, read once before the pass; `routing`
// the binding's routing labels (readRouting).
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
  const candidates = selected.filter((i) => !(filed.has(i.number) && atFloor(i)));
  result.candidates = candidates.length;
  // A hold a person set since the listing stands (write-status.mjs keepHold):
  // the issue is held, so it is neither handed off nor recorded. So does any
  // state past triage the field reads now (HAND_OFF_FROM): the listing can
  // read field events stale, and the issue may have been admitted since.
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
  // Issues the sweep already handed off cost their reads and do not count
  // toward MAX_CHECKED, so they cannot starve the issues behind them.
  let checked = 0;
  for (const issue of candidates) {
    const { number } = issue;
    if (checked >= MAX_CHECKED) break;
    if (result.dispatched.length >= MAX_DISPATCHES && result.handed.length >= MAX_HANDED) break;
    try {
      const comments = [];
      let full = false;
      for (let page = 1; page <= COMMENT_PAGES; page += 1) {
        const batch = (await call("GET", `/repos/${repo}/issues/${number}/comments?per_page=100&page=${page}`)) ?? [];
        comments.push(...batch);
        full = batch.length === 100;
        if (!full) break;
      }
      // Past the pages read, the state comment may be hidden: a person
      // decides, so the state is set once.
      if (full) {
        if (atFloor(issue)) continue;
        checked += 1;
        if (await handOff(issue)) result.handedOff.push(number);
        continue;
      }
      const state = readState(comments, appId);
      // Handed to a maintainer already: it is at needs-triage.
      if (state.filed) continue;
      checked += 1;
      const last = state.runs.at(-1);
      const latest = state.runs.length > 0 ? await call("GET", `/repos/${repo}/actions/runs/${last}`) : null;
      // A run the API no longer has counts as finished.
      const finished = state.runs.length > 0 && latest === null ? { status: "completed" } : latest;
      // Once the runs could hand the issue off, read each run the state has
      // not recorded (classifyRun). A read that finds no run counts the run
      // and is recorded; one that fails counts it for this pass only.
      const known = new Map(state.reached);
      const reached = new Map(known);
      // At RUN_LIMIT the issue is handed off whatever the reads say, so with the
      // hand slots used up it stops and nothing is read.
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
      // Unread, every run counts.
      const { attempts, dispatches } = tally(state.runs, reached);
      let action = decide({ state, latest: finished, reached: attempts, dispatches });
      if (action === "wait") result.waiting.push(number);
      if (action === "dispatch" && result.dispatched.length >= MAX_DISPATCHES) action = "stop";
      if (action === "hand" && result.handed.length >= MAX_HANDED) action = "stop";
      // A capped issue records what this pass read, so no later pass reads it
      // again. The record is best effort: a failed write costs a re-read.
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
        continue;
      }
      // Never start a run the budget left cannot record, or a hand-off it cannot finish.
      // A hand-off reads each run's conclusion but a transient one's.
      const reads = state.runs.filter((id) => id !== last && reached.get(id) !== "~").length;
      if ((action === "dispatch" && remaining() < 2) || (action === "hand" && remaining() < reads + 2)) {
        result.truncated = `stopped at #${number}: too little call budget left`;
        break;
      }
      // intake-triage.yml admits this token's dispatch whoever wrote the
      // issue, so the author check in selectCandidates is the only one.
      if (action === "dispatch") {
        const sent = await call("POST", `/repos/${repo}/actions/workflows/intake-triage.yml/dispatches`, {
          ref: "main",
          inputs: { "issue-number": String(number) },
          // Without it, API version 2022-11-28 answers 204 with no run id.
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
        // The state first, then the record that stops later passes: a failed
        // record leaves the issue for the next pass, which sets it again.
        if (!(await handOff(issue))) continue;
        await writeState(call, repo, number, state, { runs: state.runs, filed: HANDED, repoUrl, details: runs, reached: known });
        result.handed.push(number);
      }
    } catch (error) {
      if (outOfBudget(error)) {
        result.truncated = `stopped at #${number}: ${error.message}`;
        break;
      }
      result.failed.push({ number, error: error.message });
    }
  }
  return result;
}

// Each open issue the Work status field or a status label places, mapped to
// its label names as the field decides them (read-status.mjs statusLabels),
// from one issuesByStatus (resolve-config.mjs) listing of every state, so the
// field can add a candidate as well as drop one. No config, no map. The map's
// `held` is the set of issues the listing left out mid-write (issuesByStatus
// `held`): selectCandidates skips them this pass rather than judge them by
// labels that could miss a field hold; the next pass lists them again.
// With the field unset, the agent-ready label is dropped: it starts no lane
// run, and admission writes the Work status, so the issue is triaged.
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
  // The field read and write send their own API version, which `call` cannot,
  // so they go through their own client, outside the call budget. A listing
  // that fails stops the pass: without it a field-only hold would not hold.
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
