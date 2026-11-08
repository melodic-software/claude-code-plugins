#!/usr/bin/env node
// check-blockers.mjs: the issue lane's admission checks a label added by hand
// would otherwise skip, in the admit job before any model run. No model, no
// write; it never fails the job or hands the issue to a person.
//
// - Authorship first, by admission's rule (admit.mjs authorAdmitted): an
//   issue neither a listed human nor the lanes App wrote does not run, for
//   good, whoever added agent-ready, since the run would work from an
//   outsider's text: `untrusted` and `outsider` are true, and
//   work-resolve-issue.yml's report-skip removes agent-ready and comments that
//   a listed human re-files the work as a new issue. No read past the issue's own.
// The issue's events are its label events plus its Work status field
// changes shaped as label events (read-status.mjs statusEvents), so a verdict
// or admission written only to the field counts as one.
//
// - Then provenance, by admission's rule (admit.mjs untrustedHold): an issue
//   carrying one of UNTRUSTED_LABELS, or whose newest removal of one
//   was by neither a listed human nor the lanes App, does not run, for good:
//   `untrusted` is true, and work-unblock's sweep never re-fires the run.
// - Then blockers (owner decision Q95): an issue a blocker still blocks, as
//   admission judges it (admit.mjs blockerDone: a pull request merged here, or
//   an issue closed, for any reason, by a listed human or, here only, a merge
//   or commit; another repository's issue is read there), does not run until
//   none does; the sweep re-fires it then.
// - Then sub-issues: an umbrella, an issue with an open sub-issue, is no work
//   for the lane (owner Q93, intake admission's wait: its work is its
//   sub-issues'), nor a decision for a person, so it does not run while one
//   is open and the sweep re-fires it once none is. The issue read's
//   sub_issues_summary answers for an issue with none open, at no extra call
//   (admit.mjs openSubIssues).
//
// Either way `proceed` is false, agent-ready stays on, and a notice says why.
// A read that fails also skips, with a warning, and is not final, so the
// sweep retries it.
//
// With RECHECK=true it is the read runner's in-slot re-check
// (pr-run-activity-read.yml broker-check), after admission passed and the run
// waited for its slot: one read of the blocked_by list decides when the list
// is empty (proceed) or names an open blocker (blocked, as above). A list of
// closed blockers alone takes the full check, since only it judges who
// closed them.
//
// Environment:
//   GH_TOKEN             the job's GITHUB_TOKEN (issues: read)
//   GITHUB_REPOSITORY    owner/repo
//   ISSUE_NUMBER         the issue agent-ready was added to
//   TRUSTED_ACTORS_PATH  the default branch's trusted-actor list
//   BASE_PATH            the default branch's checkout (default `.base`),
//                        whose models.issue-status the field read reads
//   LANES_APP_ID         the lanes App bot's numeric user id
//   RECHECK              `true` for the in-slot re-check above
//   GITHUB_OUTPUT        receives proceed=true|false and untrusted=true|false,
//                        outsider=true on the outside-author stop, and with
//                        proceed=true split-child=true|false: whether the issue
//                        is a trusted size-split sub-issue (admit.mjs
//                        trustedSplitChild) or a finished parent (admit.mjs
//                        finishedParent), resolve-config's split-child input,
//                        so Size Large does not skip either; and verify-close,
//                        a finished parent's sub-issue numbers, comma-joined
//                        (else empty), report-outcome's VERIFY_CLOSE
//   GITHUB_API_URL
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { createGitHub, loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { statusReader } from "../../actions/resolve-config/read-status.mjs";
import { authorAdmitted, blockersOf, clearedPastReport, closedByTrusted, finishedParent, judgedSince, loadRules, openSubIssues, stillBlocking, trustedElsewhere, trustedSplitChild, UNTRUSTED, untrustedHold } from "../intake-triage/admit.mjs";

const NUMBER = /^[1-9][0-9]{0,9}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

// `#n` for a blocker in this repository, `owner/repo#n` for one elsewhere.
const named = (blocker, repository) => {
  const repo = String(blocker?.repository_url ?? "").match(/\/repos\/([^/]+\/[^/]+)$/)?.[1] ?? "?";
  return `${repo.toLowerCase() === repository.toLowerCase() ? "" : repo}#${blocker?.number}`;
};

export async function main({ env = process.env, github, log = console.log, write = (outputs) => writeOutputs(outputs, env.GITHUB_OUTPUT) } = {}) {
  const repository = env.GITHUB_REPOSITORY ?? "";
  const number = env.ISSUE_NUMBER ?? "";
  let outsider;
  let held;
  let pending;
  let subs;
  let splitChild;
  let finished = null;
  let rechecked = false;
  // Logs why the run does not proceed and writes its outputs; never fails the job.
  const skip = (message, outputs = { proceed: "false", untrusted: "false" }) => {
    log(message);
    write(outputs);
    return 0;
  };
  try {
    if (!REPO.test(repository) || !NUMBER.test(number) || !NUMBER.test(env.LANES_APP_ID ?? "")) {
      throw new Error("GITHUB_REPOSITORY, ISSUE_NUMBER or LANES_APP_ID is not set to a repository, issue number and App id");
    }
    const appId = Number(env.LANES_APP_ID);
    const { humans } = loadTrustedList(env.TRUSTED_ACTORS_PATH);
    const client = github ?? createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const base = `/repos/${repository}/issues/${number}`;
    if (env.RECHECK === "true") {
      const blockers = await blockersOf(client, base);
      pending = await stillBlocking(blockers, repository, async () => true, async () => true);
      rechecked = blockers.length === 0 || pending.length > 0;
      subs = [];
    }
    if (!rechecked) {
      const issue = await client("GET", base);
      outsider = !authorAdmitted(issue, humans, appId);
      const events = outsider ? [] : await statusReader({ env, github: client, repository, log }).events(Number(number));
      const isApp = (actor) => actor?.id === appId;
      held = !outsider && untrustedHold({ labels: issue?.labels, events, humans, isApp });
      if (!outsider && !held) {
        // The same close admission counts (admit.mjs closedByTrusted), so a split
        // parent the lanes App closed does not hold an issue admission let through.
        // A blocker the App closed report-delivered no longer holds once a
        // verdict or admission postdates its close (admit.mjs reportCleared).
        const after = judgedSince(events, (actor) => humans.has(actor?.id) || isApp(actor));
        const closed = closedByTrusted({ github: client, repository, humans, appId });
        const trusted = clearedPastReport({ github: client, repository, isApp, trusted: closed, after });
        pending = await stillBlocking(await blockersOf(client, base), repository, trusted, (blocker) => trustedElsewhere(client, blocker, humans));
        subs = pending.length > 0 ? [] : await openSubIssues(client, base, issue);
        if (pending.length === 0 && subs.length === 0) {
          const taskList = loadRules(fileURLToPath(new URL("../../actions/resolve-config/admission-rules.json", import.meta.url)))["task-list"];
          splitChild = await trustedSplitChild(client, repository, Number(number), humans, appId, taskList);
          finished = await finishedParent({ github: client, repository, issue, trusted: closed });
        }
      }
    }
  } catch (error) {
    return skip(`::warning title=admission unread::the run is skipped and agent-ready kept: its labels, events, blockers, sub-issues or split-child provenance could not be read (${String(error?.message ?? error).replace(/[\r\n%]/g, " ")}); work-unblock's sweep re-fires it`);
  }
  if (outsider) {
    return skip("::notice title=outside author::the run is stopped: the issue's author is neither a listed human nor the lanes App, so the lane will not work from its text; report-skip removes agent-ready and asks a listed human to re-file the work as a new issue; work-unblock never re-fires this run", { proceed: "false", untrusted: "true", outsider: "true" });
  }
  if (held) {
    return skip(`::notice title=untrusted provenance::the run is stopped: \`${UNTRUSTED}\` holds the issue (on it, or last removed by neither a listed human nor the lanes App), so a person decides it; work-unblock never re-fires this run`, { proceed: "false", untrusted: "true" });
  }
  if (pending.length > 0) {
    return skip(`::notice title=blocked::the run is skipped and agent-ready kept while ${pending.map((blocker) => named(blocker, repository)).join(", ")} still blocks it (not a pull request merged here or an issue closed by a listed human or a merge); work-unblock's sweep re-fires it once none does`);
  }
  if (subs.length > 0) {
    return skip(`::notice title=umbrella::the run is skipped and agent-ready kept: the issue is an umbrella whose work is its sub-issues', and ${subs.map((sub) => `sub-issue #${sub.number}`).join(", ")} ${subs.length > 1 ? "are" : "is"} open; work-unblock's sweep re-fires it once none is`);
  }
  if (rechecked) {
    write({ proceed: "true", untrusted: "false" });
    return 0;
  }
  write({ proceed: "true", untrusted: "false", "split-child": String(splitChild || finished !== null), ...(finished && { "verify-close": finished.join(",") }) });
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
