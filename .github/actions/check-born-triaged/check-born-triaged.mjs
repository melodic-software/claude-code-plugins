// Intake gate: skip an issue that /work-items:decompose published already
// triaged. Skip only when the issue carries the born-triaged marker, its
// author is a listed human or the lanes App (matched by numeric id), and it
// has an Issue Type and a status label. Anything else, including any read
// failure, lets intake run.
import { randomUUID } from "node:crypto";
import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { setTimeout as delay } from "node:timers/promises";
import { pathToFileURL } from "node:url";

import { rateLimitLatch } from "../log-api-budget/rate-guard.mjs";

export const BORN_TRIAGED_MARKER = "<!-- work-items:born-triaged -->";

const ROLE_LABELS = new Set(["agent-ready", "needs-human"]);
// Reasons a later read can change: the publisher sets the type and some
// labels in calls after the issue is created.
const PENDING = new Set(["no-type", "no-status"]);

const triage = (reason) => ({ skip: "false", reason });

const isListReadable = (list) => list?.version === 1 && Array.isArray(list.actors);

function isTrustedAuthor(id, list, lanesAppId) {
  if (!Number.isInteger(id)) {
    return false;
  }
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

export function checkBornTriaged({ issue, list, lanesAppId }) {
  if (!isListReadable(list)) {
    return triage("list-unreadable");
  }
  // The publisher writes the marker as the body's last line, so a quoted copy
  // mid-body does not count.
  if (!String(issue.body ?? "").trimEnd().endsWith(BORN_TRIAGED_MARKER)) {
    return triage("no-marker");
  }
  if (!isTrustedAuthor(issue.user?.id, list, lanesAppId)) {
    return triage("untrusted-author");
  }
  if (!issue.type?.name) {
    return triage("no-type");
  }
  const labels = (issue.labels ?? []).map((label) => label.name ?? "");
  if (!labels.some((name) => ROLE_LABELS.has(name) || name.startsWith("status:"))) {
    return triage("no-status");
  }
  return { skip: "true", reason: "born-triaged" };
}

export async function run({ fetchIssue, list, lanesAppId, sleep = delay, attempts = 6, delayMs = 5000 }) {
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
    result = checkBornTriaged({ issue, list, lanesAppId });
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

async function main() {
  const { GITHUB_API_URL, GITHUB_TOKEN, REPOSITORY, ISSUE_NUMBER, TRUSTED_ACTORS_PATH, LANES_APP_ID } = process.env;
  let list = null;
  try {
    list = JSON.parse(readFileSync(TRUSTED_ACTORS_PATH, "utf8"));
  } catch {
    // checkBornTriaged reports list-unreadable.
  }
  // Through the rate guard (rate-guard.mjs): a rate-limited answer fails the
  // step naming the reset, and any later read is refused without a request.
  const send = rateLimitLatch.guard(fetch);
  const fetchIssue = async () => {
    const response = await send(`${GITHUB_API_URL}/repos/${REPOSITORY}/issues/${ISSUE_NUMBER}`, {
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
  const result = /^[1-9][0-9]*$/.test(ISSUE_NUMBER ?? "")
    ? await run({ fetchIssue, list, lanesAppId: LANES_APP_ID })
    : triage("issue-unreadable");
  writeOutputs({ ...result, "human-ids": humanIds(list) });
  console.log(`check-born-triaged: skip=${result.skip} reason=${result.reason}`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  await main();
}
