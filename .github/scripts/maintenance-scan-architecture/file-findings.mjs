import { appendFileSync, readFileSync } from "node:fs";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { budgetedClient, pages } from "../lib/github-rest.mjs";
import { countOpen, openItemCap, SOURCE_LABEL } from "./lane.mjs";

const MAX_ITEMS = 10;
const MAX_TITLE = 120;
const MAX_BODY = 6000;
export const ISSUE_TYPE = "Task";

export function readItems(text) {
  const doc = JSON.parse(text);
  const items = doc?.items;
  if (!Array.isArray(items) || items.length > MAX_ITEMS) throw new Error(`the findings hold no items list of at most ${MAX_ITEMS}`);
  for (const [index, item] of items.entries()) {
    const keys = Object.keys(item ?? {}).sort().join(",");
    if (keys !== "body,title") throw new Error(`item ${index + 1} holds keys ${keys || "none"}, not exactly title and body`);
    if (typeof item.title !== "string" || item.title.trim() === "" || item.title.length > MAX_TITLE || /[\r\n]/.test(item.title)) {
      throw new Error(`item ${index + 1} has no one-line title of at most ${MAX_TITLE} characters`);
    }
    if (typeof item.body !== "string" || item.body.trim() === "" || item.body.length > MAX_BODY) {
      throw new Error(`item ${index + 1} has no body of at most ${MAX_BODY} characters`);
    }
  }
  return items.map(({ title, body }) => ({ title: title.trim(), body }));
}

const key = (title) => title.trim().replace(/\s+/g, " ").toLowerCase();

export async function fileFindings({ items, cap, call, repository }) {
  if (items.length === 0) return { filed: [], skipped: [], room: null };
  if (!(await call("GET", `/repos/${repository}/labels/${encodeURIComponent(SOURCE_LABEL)}`))) {
    throw new Error(`label ${SOURCE_LABEL} does not exist; the lane never creates a label, so it files nothing`);
  }
  const open = await countOpen(call, repository, SOURCE_LABEL, cap);
  let room = Math.max(0, cap - open);
  const seen = new Set((await pages(call, `/repos/${repository}/issues?state=all&labels=${encodeURIComponent(SOURCE_LABEL)}`, { max: 10 })).map((issue) => key(issue.title)));
  const filed = [];
  const skipped = [];
  for (const item of items) {
    if (room === 0) {
      skipped.push({ title: item.title, why: `the open \`${SOURCE_LABEL}\` issues reached the cap of ${cap}` });
      continue;
    }
    if (seen.has(key(item.title))) {
      skipped.push({ title: item.title, why: `an issue with this title already carries \`${SOURCE_LABEL}\`` });
      continue;
    }
    const issue = await call("POST", `/repos/${repository}/issues`, { title: item.title, body: item.body, labels: [SOURCE_LABEL], type: ISSUE_TYPE });
    seen.add(key(item.title));
    filed.push({ number: issue.number, title: item.title });
    room -= 1;
  }
  return { filed, skipped, room, open };
}

export function summary({ filed, skipped }) {
  return [
    "### Architecture scan filings",
    "",
    `Filed ${filed.length}, skipped ${skipped.length}.`,
    "",
    ...filed.map((issue) => `- filed #${issue.number}`),
    ...skipped.map((item) => `- skipped one item: ${item.why}`),
    "",
  ].join("\n");
}

async function main(command, env) {
  const items = readItems(readFileSync(env.FINDINGS_FILE, "utf8"));
  if (command === "check") {
    console.log(`::notice::the findings hold ${items.length} well-formed item(s)`);
    return;
  }
  if (command !== "file") throw new Error("usage: file-findings.mjs check | file");
  const { cap, source, warnings } = openItemCap(env.BASE_DIR);
  for (const warning of warnings) console.log(`::warning::${warning}`);
  const call = budgetedClient(env, { budget: Number(env.CALL_BUDGET ?? 40) });
  const result = await fileFindings({ items, cap, call, repository: env.REPOSITORY });
  console.log(`::notice::architecture scan filed ${result.filed.length} of ${items.length} item(s) under ${SOURCE_LABEL} (cap ${cap} from the ${source} layer)`);
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, summary(result));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main(process.argv[2], process.env).catch((error) => {
    console.log(`::error::architecture scan filing: ${String(error.message).split("\n")[0]}`);
    process.exitCode = 1;
  });
}
