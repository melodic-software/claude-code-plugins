import { randomUUID } from "node:crypto";
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { AGENT_READY } from "../../scripts/lib/lane-vocabulary.mjs";
import { trackerBindingText } from "../../scripts/pr-merge/merge-holds.mjs";
import { createGitHub } from "../../scripts/lib/github-client.mjs";
import { trustedListPath } from "../../scripts/lib/trusted-actors.mjs";
import { createRateLimitLatch } from "../log-api-budget/rate-guard.mjs";
import { isStatusLabel, statusReader } from "../resolve-config/read-status.mjs";

export const BORN_TRIAGED_MARKER = "<!-- work-items:born-triaged -->";

const STATUS_LABELS = new Set([AGENT_READY, "needs-human", "needs-spec", "admission-deferred"]);
const PENDING = new Set(["no-type", "no-status"]);

const triage = (reason) => ({ skip: "false", reason });

const isListReadable = (list) => list?.version === 1 && Array.isArray(list.actors);

function isTrustedAuthor(id, list, lanesAppId) {
  if (/^[1-9][0-9]*$/.test(String(lanesAppId ?? "")) && id === Number(lanesAppId)) {
    return true;
  }
  return list.actors.some((actor) => actor.id === id && actor.kind === "human");
}

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

export const ROUTING_DEFAULTS = Object.freeze({ container: "spec-container", prefix: "wayfind:", owned: "session-owned" });

export function routingLabels(tracker) {
  const config = tracker?.config ?? {};
  const pick = (source, key, fallback, name = key) => {
    const value = source?.[key];
    if (value === undefined || value === null || value === "") {
      return fallback;
    }
    if (typeof value !== "string") {
      throw new Error(`tracker.config.${name} is not a string`);
    }
    return value;
  };
  return {
    container: pick(config, "container_label", ROUTING_DEFAULTS.container),
    prefix: pick(config, "wayfind_label_prefix", ROUTING_DEFAULTS.prefix),
    owned: pick(config.role_labels, "session-owned", ROUTING_DEFAULTS.owned, "role_labels.session-owned"),
  };
}

export const routingLabel = (names, routing = ROUTING_DEFAULTS) =>
  names.find((name) => name === routing.container || name === (routing.owned ?? ROUTING_DEFAULTS.owned) || name.startsWith(routing.prefix)) ?? null;

export const ROUTED_BY = "a container, wayfind or session-owned label, so the skill or session that filed it routes it";

export function notBornTriaged(issue, trusted, names = labelNames(issue)) {
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

function writeOutputs(outputs, outputPath = process.env.GITHUB_OUTPUT) {
  let text = "";
  for (const [name, value] of Object.entries(outputs)) {
    const delimiter = `ghadelimiter_${randomUUID()}`;
    text += `${name}<<${delimiter}\n${value}\n${delimiter}\n`;
  }
  appendFileSync(outputPath, text);
}

export function readRouting(path, { who = "check-born-triaged", log = console.log } = {}) {
  try {
    return routingLabels(JSON.parse(trackerBindingText(path)));
  } catch (error) {
    if (error.code !== "ENOENT") {
      log(`::warning::${who}: cannot read the routing labels from ${path} (${error.message}); using '${ROUTING_DEFAULTS.container}', '${ROUTING_DEFAULTS.prefix}' and '${ROUTING_DEFAULTS.owned}'`);
    }
    return ROUTING_DEFAULTS;
  }
}

async function main() {
  const { GITHUB_API_URL, GITHUB_TOKEN, REPOSITORY, ISSUE_NUMBER, TRUSTED_ACTORS_PATH, LANES_APP_ID, TRACKER_CONFIG, BORN_TRIAGED } = process.env;
  let list = null;
  try {
    list = JSON.parse(readFileSync(trustedListPath(process.env, TRUSTED_ACTORS_PATH), "utf8"));
  } catch {
  }
  const routing = readRouting(TRACKER_CONFIG || ".base/docs/conventions/work-items.yaml");
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
    console.log(`::notice::intake skips #${ISSUE_NUMBER}: it carries '${result.label}', ${ROUTED_BY}`);
  }
  console.log(`check-born-triaged: skip=${result.skip} reason=${result.reason} rate-limited=${rateLimited}`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
