import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { planFiling } from "../../../plugins/improvement/scripts/filing-plan.mjs";
import { DRIFT_TITLE } from "../intake-triage/issue-spec.mjs";
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

export const SECURITY_DEFECT = /\bsecurity[-\s]defects?\b|\bvulnerab|\bCWE-\d+|\bCVE-\d{4}-\d+|\bexploit|\binjection\b|\bbypass|\bexfiltrat|\bcredentials?\b|\bsecrets?\b|\btokens?\b|\bprivilege[-\s]escalation\b|\bauth(?:entication|orization)?\b|\btravers|\bXSS\b|\bSSRF\b|\bRCE\b|\bescape|\bleak|\bunsaniti|\bTOCTOU\b/i;

export function withoutSecurityDefects(items) {
  const kept = items.filter((item) => !SECURITY_DEFECT.test(item.title) && !SECURITY_DEFECT.test(item.body));
  return { kept, dropped: items.length - kept.length };
}

export const trustedShape = (item) => DRIFT_TITLE.test(item.title) || item.body.includes("<!--");

export function withoutTrustedShapes(items) {
  const kept = items.filter((item) => !trustedShape(item));
  return { kept, dropped: items.length - kept.length };
}

export async function fileFindings({ items, cap, call, repository }) {
  if (items.length === 0) return { filed: [], skipped: [], room: null };
  if (!(await call("GET", `/repos/${repository}/labels/${encodeURIComponent(SOURCE_LABEL)}`))) {
    throw new Error(`label ${SOURCE_LABEL} does not exist; the lane never creates a label, so it files nothing`);
  }
  const open = await countOpen(call, repository, SOURCE_LABEL, cap);
  const existingTitles = (await pages(call, `/repos/${repository}/issues?state=all&labels=${encodeURIComponent(SOURCE_LABEL)}`, { max: 10 })).map((issue) => issue.title);
  const plan = planFiling({ label: SOURCE_LABEL, labelExists: true, cap, open, existingTitles, candidates: items.map((item) => item.title) });
  const filed = [];
  for (const item of plan.file.map((index) => items[index])) {
    const issue = await call("POST", `/repos/${repository}/issues`, { title: item.title, body: item.body, labels: [SOURCE_LABEL], type: ISSUE_TYPE });
    filed.push({ number: issue.number, title: item.title });
  }
  return { filed, skipped: plan.skipped, room: plan.room, open };
}

const MAX_BULLETS = 5;

export function summary({ filed, skipped }) {
  const lines = [...filed.map((issue) => `- filed #${issue.number}`), ...skipped.map((item) => `- skipped one item: ${item.why}`)];
  const shown = lines.slice(0, MAX_BULLETS);
  const verdict = filed.length > 0 ? `Filed: ${filed.length} issue(s), skipped ${skipped.length}.` : `Filed nothing: skipped ${skipped.length}.`;
  return [
    "### maintenance-scan-architecture / file-findings",
    "",
    verdict,
    "",
    ...shown,
    ...(lines.length > shown.length ? ["", "<details><summary>Every item</summary>", "", ...lines, "", "</details>"] : []),
    "",
  ].join("\n");
}

export async function main(command, env) {
  if (command === "check" && !env.CHECKED_FILE) throw new Error("check needs CHECKED_FILE, a path apart from the read-only opened findings");
  const { kept: clean, dropped } = withoutSecurityDefects(readItems(readFileSync(env.FINDINGS_FILE, "utf8")));
  if (dropped > 0) console.log(`::warning::dropped ${dropped} item(s) that name a security defect; run /architecture:improve with a person present to review them privately`);
  const { kept: items, dropped: shaped } = withoutTrustedShapes(clean);
  if (shaped > 0) console.log(`::warning::dropped ${shaped} item(s) shaped like an issue another script trusts (an Upstream drift: title or an HTML comment marker in the body)`);
  if (command === "check") {
    mkdirSync(path.dirname(env.CHECKED_FILE), { recursive: true });
    writeFileSync(env.CHECKED_FILE, `${JSON.stringify({ items })}\n`, { flag: "wx" });
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
