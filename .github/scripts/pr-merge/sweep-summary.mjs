#!/usr/bin/env node
import { readFileSync, renameSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

const BLOCKER_CHARS = 300;

export function normalizeReason(reason) {
  const raw = reason == null || reason === false ? "not ready" : String(reason);
  const [first, ...rest] = raw.split(";")[0].split(":");
  const kept = [first.trim()];
  for (const segment of rest) {
    if (segment === "" || /^\s|[\d#,]/.test(segment)) break;
    kept.push(segment);
  }
  return kept.join(":");
}

const trimBlocker = (text) =>
  Array.from(String(text).replaceAll(/[\r\n`]/g, " "))
    .slice(0, BLOCKER_CHARS)
    .join("");

export function summarize({
  runId,
  event,
  live,
  startedAt,
  results,
  candidates,
  held,
  gateOutcome,
  cursor,
  listingHeld = false,
  listingHeldReason = null,
}) {
  const refusals = new Map();
  let enqueued = 0;
  let merged = 0;
  let readyUnmerged = 0;
  for (const result of results) {
    if (result.enqueued) enqueued += 1;
    if (result.merged) merged += 1;
    if (result.enqueued || result.merged) continue;
    if (result.ready && result.reportOnly === true) {
      readyUnmerged += 1;
      continue;
    }
    const key = result.ready
      ? "enqueue failed"
      : normalizeReason(result.reason);
    refusals.set(key, (refusals.get(key) ?? 0) + 1);
  }
  const skipped = results.filter((result) => "carried" in result).length;
  const reached = results.length - held.length - skipped;
  const stopped =
    gateOutcome === "success" &&
    Number.isInteger(candidates) &&
    reached < candidates;
  const listed = Number.isInteger(candidates) ? candidates + skipped : null;
  return {
    run_id: runId,
    event,
    live,
    started_at: startedAt,
    candidates: listed,
    skipped,
    enqueued,
    merged,
    ready_unmerged: readyUnmerged,
    refusal_counts: Object.fromEntries(refusals),
    held: held.length,
    listing_held: listingHeld,
    listing_held_reason: listingHeld ? listingHeldReason : null,
    budget_stop: stopped
      ? {
          reached,
          skipped,
          candidates: listed,
          next_after: Number.isInteger(cursor?.last) ? cursor.last : null,
        }
      : null,
    results: results.map((result) => ({
      ...result,
      blockers: Array.isArray(result.blockers)
        ? result.blockers.map(trimBlocker)
        : [],
    })),
  };
}

function readJson(path, fallback) {
  try {
    return path ? JSON.parse(readFileSync(path, "utf8")) : fallback;
  } catch {
    return fallback;
  }
}

export function main(env = process.env) {
  const results = readJson(env.SUMMARY_PATH, []);
  const held = readJson(env.HELD_PATH, []);
  const candidates = readJson(env.CANDIDATES_PATH, null);
  const out = summarize({
    runId: Number(env.GITHUB_RUN_ID) || null,
    event: env.EVENT || null,
    live: env.LIVE === "true",
    startedAt: env.RUN_STARTED_AT || null,
    results: Array.isArray(results) ? results : [],
    candidates: Array.isArray(candidates) ? candidates.length : null,
    held: Array.isArray(held) ? held : [],
    gateOutcome: env.GATE_OUTCOME,
    cursor: readJson(env.CURSOR_PATH, null),
    listingHeld: env.LISTING_HELD === "true",
    listingHeldReason: env.LISTING_HELD_REASON || null,
  });
  const to = env.SWEEP_SUMMARY_TO;
  writeFileSync(`${to}.tmp`, JSON.stringify(out));
  renameSync(`${to}.tmp`, to);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) main();
