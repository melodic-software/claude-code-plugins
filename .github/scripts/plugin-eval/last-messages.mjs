#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, isAbsolute, resolve } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { scanLeak } from "../../../lib/publish-gate.mjs";

const objects = (text) =>
  text.split("\n").flatMap((line) => {
    try {
      const value = JSON.parse(line);
      return value && typeof value === "object" ? [value] : [];
    } catch {
      return [];
    }
  });

/** The final reply in a trace's parsed lines, or null, as calibrate-judge.py's trace_reply reads it. */
export function lastMessage(lines) {
  const result = lines.findLast((line) => line.type === "result" && typeof line.result === "string");
  if (result) return result.result;
  for (const line of lines.toReversed()) {
    const content = line.type === "assistant" ? line.message?.content : null;
    const texts = (Array.isArray(content) ? content : []).filter((part) => part?.type === "text").map((part) => String(part.text ?? ""));
    if (texts.length) return texts.join("\n");
  }
  return null;
}

/** One record per run of every case and arm; a tracePath resolves against `base`. */
export function replies(result, base) {
  const records = [];
  for (const c of Array.isArray(result?.cases) ? result.cases : []) {
    for (const [arm, runs] of Object.entries(c?.arms ?? {})) {
      (Array.isArray(runs) ? runs : []).forEach((run, index) => {
        const path = typeof run?.tracePath === "string" && run.tracePath ? (isAbsolute(run.tracePath) ? run.tracePath : resolve(base, run.tracePath)) : "";
        let message;
        try {
          message = path ? lastMessage(objects(readFileSync(path, "utf8"))) : null;
        } catch {
          message = null;
        }
        records.push({ case: c.name ?? c.dir ?? "case", arm, run: index + 1, last_message: message });
      });
    }
  }
  return records;
}

/**
 * `last-messages.mjs <results.json> <out.jsonl>`: one JSON line per run, written only when
 * lib/publish-gate.mjs scanLeak blocks nothing in the file; a block writes nothing and prints
 * a warning naming the rule. No reply is printed. Exit 0 written or withheld, 2 on a usage error
 * or an unreadable result.
 */
export function main(args = process.argv.slice(2)) {
  const [file, out] = args;
  if (!file || !out || args.length !== 2) {
    console.error("usage: last-messages.mjs <results.json> <out.jsonl>");
    return 2;
  }
  let result;
  try {
    result = JSON.parse(readFileSync(file, "utf8"));
  } catch (error) {
    console.error(`last-messages: cannot read ${file}: ${error.name}`);
    return 2;
  }
  const records = replies(result, dirname(resolve(file)));
  const bytes = Buffer.from(records.map((record) => `${JSON.stringify(record)}\n`).join(""), "utf8");
  const { block } = scanLeak(bytes);
  const suite = basename(dirname(resolve(out)));
  if (block) {
    console.log(`::warning title=Eval replies withheld::The leak scan matched ${block} in the ${suite} replies, so the artifact carries no ${basename(out)}.`);
    return 0;
  }
  writeFileSync(out, bytes);
  console.log(`last-messages: ${records.length} replies kept for ${suite}`);
  return 0;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = main();
}
