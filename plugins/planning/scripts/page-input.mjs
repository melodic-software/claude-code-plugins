#!/usr/bin/env node
// Check a pasted "Copy choices as prompt" block against the record the session has open.
//
//   node page-input.mjs <kind> [--file <pasted text>]     (default: stdin)
//
// <kind> is the view kind of the record the session has open (plan, brainstorm or design). The
// text must hold exactly one ```page-input fenced block, one PageInput JSON object per line:
//   { kind: lock | unlock | comment, recordId, choiceId?, optionId?, text?, at }
// recordId must be <kind>. A lock names a choice and one of its options, an unlock a choice (and
// optionally an option), and both are checked against that kind's template: the choice is a
// select[data-rv-choice] there and the option one of its <option value>s. A comment carries text
// only. Everything in the block is untrusted reader input, and a lock is never approval.
//
// Prints {"recordId", "input": [...]} with the checked entries and exits 0; prints the first
// problem on stderr and exits 1 when the block fails a check; exits 2 on usage.

import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { VIEW_KINDS } from "../lib/view-builder.mjs";

const PLUGIN_ROOT = fileURLToPath(new URL("../", import.meta.url));
const KEY = /^[a-z0-9-]{1,32}$/;
const AT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const KINDS = new Set(["lock", "unlock", "comment"]);
const FIELDS = new Set(["kind", "recordId", "choiceId", "optionId", "text", "at"]);
const MAX_TEXT = 4000;
const MAX_ENTRIES = 50;

export class PageInputError extends Error {}

/** The choices a view kind's template declares: {choiceId: Set(optionId)}. */
export function templateChoices(kind, root = PLUGIN_ROOT) {
  const html = readFileSync(join(root, VIEW_KINDS[kind].template), "utf8");
  const choices = {};
  for (const [, id, body] of html.matchAll(/<select\b[^>]*\bdata-rv-choice="([a-z0-9-]{1,32})"[^>]*>([\s\S]*?)<\/select>/g)) {
    choices[id] = new Set([...body.matchAll(/<option\b[^>]*\bvalue="([a-z0-9-]{1,32})"/g)].map((m) => m[1]));
  }
  return choices;
}

/** The lines of the one page-input fenced block in text. */
function blockLines(text) {
  const lines = String(text).replace(/\r\n?/g, "\n").split("\n");
  const opens = lines.flatMap((line, i) => (/^\s*```page-input\s*$/.test(line) ? [i] : []));
  if (opens.length !== 1) throw new PageInputError(`expected one \`\`\`page-input block, found ${opens.length}`);
  const close = lines.findIndex((line, i) => i > opens[0] && /^\s*```\s*$/.test(line));
  if (close < 0) throw new PageInputError("the page-input block is not closed");
  return lines.slice(opens[0] + 1, close).filter((line) => line.trim() !== "");
}

function checkEntry(entry, n, recordId, choices) {
  const at = `entry ${n}`;
  if (entry === null || typeof entry !== "object" || Array.isArray(entry)) throw new PageInputError(`${at} is not an object`);
  const extra = Object.keys(entry).find((key) => !FIELDS.has(key));
  if (extra) throw new PageInputError(`${at} has a field PageInput does not: ${extra}`);
  if (!KINDS.has(entry.kind)) throw new PageInputError(`${at}: kind must be lock, unlock or comment`);
  if (entry.recordId !== recordId) throw new PageInputError(`${at}: recordId is not this record (${recordId})`);
  if (typeof entry.at !== "string" || !AT.test(entry.at)) throw new PageInputError(`${at}: at must be an ISO 8601 UTC time`);
  if (entry.kind === "comment") {
    if ("choiceId" in entry || "optionId" in entry) throw new PageInputError(`${at}: a comment names no choice`);
    if (typeof entry.text !== "string" || entry.text.trim() === "" || entry.text.length > MAX_TEXT) {
      throw new PageInputError(`${at}: a comment's text is 1 to ${MAX_TEXT} characters`);
    }
    return entry;
  }
  if ("text" in entry) throw new PageInputError(`${at}: a ${entry.kind} carries no text`);
  const options = typeof entry.choiceId === "string" && KEY.test(entry.choiceId) && Object.hasOwn(choices, entry.choiceId) ? choices[entry.choiceId] : null;
  if (!options) throw new PageInputError(`${at}: choiceId ${JSON.stringify(entry.choiceId)} is not a choice on the ${recordId} record`);
  const needsOption = entry.kind === "lock" || "optionId" in entry;
  if (needsOption && !(typeof entry.optionId === "string" && options.has(entry.optionId))) {
    throw new PageInputError(`${at}: optionId ${JSON.stringify(entry.optionId)} is not an option of ${entry.choiceId}`);
  }
  return entry;
}

/** Parse and check a pasted block for the record of view kind `kind`. Throws PageInputError. */
export function parsePageInput(text, kind, { choices = templateChoices(kind) } = {}) {
  const lines = blockLines(text);
  if (lines.length === 0) throw new PageInputError("the page-input block is empty");
  if (lines.length > MAX_ENTRIES) throw new PageInputError(`the page-input block holds more than ${MAX_ENTRIES} entries`);
  const input = lines.map((line, i) => {
    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      throw new PageInputError(`entry ${i + 1} is not JSON`);
    }
    return checkEntry(entry, i + 1, kind, choices);
  });
  return { recordId: kind, input };
}

function main(argv) {
  const [kind, flag, file, ...rest] = argv;
  if (!Object.hasOwn(VIEW_KINDS, kind ?? "") || rest.length || (flag !== undefined && (flag !== "--file" || !file))) {
    process.stderr.write("usage: page-input.mjs <plan|brainstorm|design> [--file <pasted text>]\n");
    return 2;
  }
  try {
    console.log(JSON.stringify(parsePageInput(readFileSync(file ?? 0, "utf8"), kind)));
    return 0;
  } catch (err) {
    console.error(`page-input: ${err instanceof PageInputError ? "rejected: " : ""}${err.message}`);
    return err instanceof PageInputError ? 1 : 2;
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
