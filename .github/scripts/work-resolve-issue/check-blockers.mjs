#!/usr/bin/env node
import { join } from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { readRouting, ROUTED_BY, routingLabel } from "../../actions/check-born-triaged/check-born-triaged.mjs";
import { createGitHub } from "../lib/github-client.mjs";
import { loadTrustedList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { writeOutputs } from "../../actions/check-kill-switch/check-kill-switch.mjs";
import { statusReader } from "../../actions/resolve-config/read-status.mjs";
import { authorTrust, blockersOf, clearedPastReport, closedByTrusted, finishedParent, judgedSince, openSubIssues, stillBlocking, trustedElsewhere, UNTRUSTED, untrustedHold } from "../intake-triage/admit.mjs";
import { loadRules } from "../intake-triage/issue-spec.mjs";
import { trustedSplitChild } from "../intake-triage/size-split.mjs";

const NUMBER = /^[1-9][0-9]{0,9}$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

const named = (blocker, repository) => {
  const repo = String(blocker?.repository_url ?? "").match(/\/repos\/([^/]+\/[^/]+)$/)?.[1] ?? "?";
  return `${repo.toLowerCase() === repository.toLowerCase() ? "" : repo}#${blocker?.number}`;
};

export async function main({ env = process.env, github, log = console.log, write = (outputs) => writeOutputs(outputs, env.GITHUB_OUTPUT) } = {}) {
  const repository = env.GITHUB_REPOSITORY ?? "";
  const number = env.ISSUE_NUMBER ?? "";
  let outsider;
  let held;
  let routed = null;
  let pending;
  let subs;
  let splitChild;
  let drift = false;
  let finished = null;
  let rechecked = false;
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
    const issue = await client("GET", base);
    const routing = readRouting(join(env.BASE_PATH || ".base", "docs/conventions/work-items.yaml"), { who: "check-blockers", log });
    const labels = (issue?.labels ?? []).map((label) => String(label?.name ?? label));
    const isApp = (actor) => actor?.id === appId;
    if (env.RECHECK === "true" && !routingLabel(labels, routing) && !untrustedHold({ labels: issue?.labels, events: [], humans, isApp })) {
      const blockers = await blockersOf(client, base);
      pending = await stillBlocking(blockers, repository, async () => true, async () => true);
      rechecked = blockers.length === 0 || pending.length > 0;
      subs = [];
    }
    if (!rechecked) {
      const trust = await authorTrust(client, repository, issue, humans, appId);
      outsider = trust === null;
      drift = trust === "drift";
      const events = outsider ? [] : await statusReader({ env, github: client, repository, log }).events(Number(number));
      held = !outsider && untrustedHold({ labels: issue?.labels, events, humans, isApp });
      routed = outsider || held ? null : routingLabel(labels, routing);
      if (!outsider && !held && !routed) {
        const after = judgedSince(events, (actor) => humans.has(actor?.id) || isApp(actor));
        const closed = closedByTrusted({ github: client, repository, humans, appId });
        const trusted = clearedPastReport({ github: client, repository, isApp, trusted: (blocker) => closed(blocker, { blocker: true }), after });
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
  if (routed) {
    return skip(`::notice title=map issue::the run is skipped: the issue carries '${routed.replace(/[\r\n%]/g, " ")}', ${ROUTED_BY}; work-unblock never re-fires it while the label stays`);
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
  write({ proceed: "true", untrusted: "false", "split-child": String(splitChild || drift || finished !== null), ...(finished && { "verify-close": finished.join(",") }) });
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
