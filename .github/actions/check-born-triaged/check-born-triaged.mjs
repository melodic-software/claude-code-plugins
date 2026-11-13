// Intake gate: skip an issue another skill routes, or one that
// /work-items:decompose published already triaged. A routing label (the
// tracker binding's container label, or a label starting with its wayfind
// prefix) skips on its own. The born-triaged rule, when applied, skips only
// when the issue carries the born-triaged marker, its author is a listed human
// or the lanes App (matched by numeric id), and it has an Issue Type and a
// status: a Work status field a trusted account set to anything but
// needs-triage (read-status.mjs folds it into the labels), or a status label.
// The agent-ready label alone is no status while the Work status is
// configured and unset (reason `label-only`).
// Anything else, including any read failure, lets intake run.
import { randomUUID } from "node:crypto";
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { trackerBindingText } from "../../scripts/pr-merge/merge-holds.mjs";
import { createGitHub } from "../check-trusted-trigger/check-trusted-trigger.mjs";
import { createRateLimitLatch } from "../log-api-budget/rate-guard.mjs";
import { isStatusLabel, statusReader } from "../resolve-config/read-status.mjs";

export const BORN_TRIAGED_MARKER = "<!-- work-items:born-triaged -->";

const AGENT_READY = "agent-ready";
// The bare labels that name a status; every other status label starts `status:`.
const STATUS_LABELS = new Set([AGENT_READY, "needs-human", "needs-spec", "admission-deferred"]);
// Reasons a later read can change: the publisher sets the type and some
// labels in calls after the issue is created.
const PENDING = new Set(["no-type", "no-status"]);

const triage = (reason) => ({ skip: "false", reason });

const isListReadable = (list) => list?.version === 1 && Array.isArray(list.actors);

function isTrustedAuthor(id, list, lanesAppId) {
  if (/^[1-9][0-9]*$/.test(String(lanesAppId ?? "")) && id === Number(lanesAppId)) {
    return true;
  }
  return list.actors.some((actor) => actor.id === id && actor.kind === "human");
}

// The listed humans' ids, comma-joined, for the intake lane's
// allowed-author-ids. Empty when the list is unreadable.
export function humanIds(list) {
  if (!isListReadable(list)) {
    return "";
  }
  return list.actors
    .filter((actor) => actor.kind === "human" && Number.isInteger(actor.id) && actor.id > 0)
    .map((actor) => actor.id)
    .join(",");
}

const labelNames = (issue) => (issue.labels ?? []).map((label) => label.name ?? "");

export const ROUTING_DEFAULTS = Object.freeze({ container: "spec-container", prefix: "wayfind:" });

// The routing labels of a tracker binding (the `tracker` mapping of
// work-items.yaml): `config.container_label` and `config.wayfind_label_prefix`,
// each its default when absent or empty. A value of another type throws.
export function routingLabels(tracker) {
  const config = tracker?.config ?? {};
  const pick = (key, fallback) => {
    const value = config[key];
    if (value === undefined || value === null || value === "") {
      return fallback;
    }
    if (typeof value !== "string") {
      throw new Error(`tracker.config.${key} is not a string`);
    }
    return value;
  };
  return { container: pick("container_label", ROUTING_DEFAULTS.container), prefix: pick("wayfind_label_prefix", ROUTING_DEFAULTS.prefix) };
}

export const routingLabel = (names, routing = ROUTING_DEFAULTS) =>
  names.find((name) => name === routing.container || name.startsWith(routing.prefix)) ?? null;

// Why `issue` is not born triaged, or null when it is. `trusted(id)` answers
// whether its author's numeric id is a listed human's or the lanes App's;
// `names` are its label names, by default as read.
export function notBornTriaged(issue, trusted, names = labelNames(issue)) {
  // The publisher writes the marker as the body's last line, so a quoted copy
  // mid-body does not count.
  if (!String(issue.body ?? "").trimEnd().endsWith(BORN_TRIAGED_MARKER)) {
    return "no-marker";
  }
  if (!Number.isInteger(issue.user?.id) || !trusted(issue.user.id)) {
    return "untrusted-author";
  }
  if (!issue.type?.name) {
    return "no-type";
  }
  if (!names.some((name) => STATUS_LABELS.has(name) || isStatusLabel(name))) {
    return "no-status";
  }
  return null;
}

export function checkBornTriaged({ issue, list, lanesAppId, names }) {
  if (!isListReadable(list)) {
    return triage("list-unreadable");
  }
  const reason = notBornTriaged(issue, (id) => isTrustedAuthor(id, list, lanesAppId), names);
  return reason ? triage(reason) : { skip: "true", reason: "born-triaged" };
}

// `statusOf(number, names)` gives the issue's label names as its Work status
// field adds to them (read-status.mjs statusReader); it is asked only once the
// marker, author and type pass. With `bornTriaged` false only a routing label
// skips, and the issue is read once.
export async function run({ fetchIssue, list, lanesAppId, statusOf, routing = ROUTING_DEFAULTS, bornTriaged = true, sleep = delay, attempts = 6, delayMs = 5000 }) {
  if (!isListReadable(list)) {
    return triage("list-unreadable");
  }
  let result = triage("issue-unreadable");
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    let issue;
    try {
      issue = await fetchIssue();
    } catch {
      return triage("issue-unreadable");
    }
    const label = routingLabel(labelNames(issue), routing);
    if (label) {
      return { skip: "true", reason: "routing-label", label };
    }
    if (!bornTriaged) {
      return triage("born-triaged-off");
    }
    result = checkBornTriaged({ issue, list, lanesAppId });
    if (statusOf && (result.reason === "born-triaged" || result.reason === "no-status")) {
      const number = Number(issue.number);
      const names = await statusOf(number, labelNames(issue));
      // The agent-ready label starts no lane run, and admission writes the
      // Work status, so with the field unset it is no status: intake triages
      // the issue at once rather than waiting for a status no one will set.
      const labelOnly = names.includes(AGENT_READY) && (await statusOf.unset?.(number));
      result = checkBornTriaged({ issue, list, lanesAppId, names: labelOnly ? names.filter((name) => name !== AGENT_READY) : names });
      if (labelOnly && result.reason === "no-status") {
        result = triage("label-only");
      }
    }
    if (!PENDING.has(result.reason)) {
      return result;
    }
    if (attempt < attempts) {
      await sleep(delayMs);
    }
  }
  return result;
}

// Every value is written in the delimited form, so no value can start a
// second output line.
function writeOutputs(outputs, outputPath = process.env.GITHUB_OUTPUT) {
  let text = "";
  for (const [name, value] of Object.entries(outputs)) {
    const delimiter = `ghadelimiter_${randomUUID()}`;
    text += `${name}<<${delimiter}\n${value}\n${delimiter}\n`;
  }
  appendFileSync(outputPath, text);
}

// The binding's routing labels; a missing file keeps the defaults, and an
// unreadable one keeps them with a warning naming `who`.
export function readRouting(path, { who = "check-born-triaged", log = console.log } = {}) {
  try {
    return routingLabels(JSON.parse(trackerBindingText(path)));
  } catch (error) {
    if (error.code !== "ENOENT") {
      log(`::warning::${who}: cannot read the routing labels from ${path} (${error.message}); using '${ROUTING_DEFAULTS.container}' and '${ROUTING_DEFAULTS.prefix}'`);
    }
    return ROUTING_DEFAULTS;
  }
}

async function main() {
  const { GITHUB_API_URL, GITHUB_TOKEN, REPOSITORY, ISSUE_NUMBER, TRUSTED_ACTORS_PATH, LANES_APP_ID, TRACKER_CONFIG, BORN_TRIAGED } = process.env;
  let list = null;
  try {
    list = JSON.parse(readFileSync(TRUSTED_ACTORS_PATH, "utf8"));
  } catch {
    // checkBornTriaged reports list-unreadable.
  }
  const routing = readRouting(TRACKER_CONFIG || ".base/docs/conventions/work-items.yaml");
  // Through the rate guard (rate-guard.mjs): a rate-limited answer logs an
  // error naming the reset and stops the job's later calls to that pool, and
  // a read while a stop holds is refused without a request. The step still
  // exits 0, and rate-limited=true stops the callers' API jobs.
  const latch = createRateLimitLatch({ fail: () => {} });
  const send = latch.guard(fetch);
  const issueUrl = `${GITHUB_API_URL}/repos/${REPOSITORY}/issues/${ISSUE_NUMBER}`;
  const fetchIssue = async () => {
    const response = await send(issueUrl, {
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${GITHUB_TOKEN}`,
        "x-github-api-version": "2022-11-28",
      },
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    return response.json();
  };
  const github = createGitHub({ token: GITHUB_TOKEN, apiUrl: GITHUB_API_URL || undefined });
  const statusOf = statusReader({ env: process.env, github, repository: REPOSITORY });
  const result = /^[1-9][0-9]*$/.test(ISSUE_NUMBER ?? "")
    ? await run({ fetchIssue, list, lanesAppId: LANES_APP_ID, statusOf, routing, bornTriaged: BORN_TRIAGED !== "false" })
    : triage("issue-unreadable");
  const rateLimited = latch.until(issueUrl) !== null ? "true" : "false";
  writeOutputs({ skip: result.skip, reason: result.reason, label: result.label ?? "", "human-ids": humanIds(list), "rate-limited": rateLimited });
  if (result.label) {
    console.log(`::notice::intake skips #${ISSUE_NUMBER}: it carries '${result.label}', a container or wayfind label, so the skill that filed it routes it`);
  }
  console.log(`check-born-triaged: skip=${result.skip} reason=${result.reason} rate-limited=${rateLimited}`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
