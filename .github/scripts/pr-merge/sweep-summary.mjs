#!/usr/bin/env node
// sweep-summary.mjs: one pr-merge sweep's verdicts as data the API can read
// (a step summary it cannot). pr-merge.yml runs it after the summary step and
// uploads what it writes as the `pr-merge-summary` artifact:
//   run_id, event, live, started_at   the run
//   candidates                        candidates.json's length (held excluded)
//   enqueued, merged                  rows the gate enqueued or merged
//   refusal_counts                    every other row, by normalized reason
//   held                              held.json's length
//   budget_stop                       {reached, candidates, next_after} when
//                                     the gate ended green before the last
//                                     candidate (its only early exit), else null
//   results                           the summary rows, blockers trimmed as
//                                     the step summary trims them
// A reason is read as the step summary reads it (`.reason // "not ready"`),
// then normalized so counts aggregate across PRs: cut at `;`, then keep the
// first `:` segment and each next one until one names a PR, a run or free text
// (a digit, `#` or `,`, or a leading space). The raw reason stays in results.
//
// Environment:
//   SUMMARY_PATH       pr-merge-summary.json (missing: an empty sweep)
//   HELD_PATH          held.json
//   CANDIDATES_PATH    candidates.json
//   CURSOR_PATH        the gate cursor, {"last": <PR number>}
//   SWEEP_SUMMARY_TO   the file to write
//   GITHUB_RUN_ID, EVENT, LIVE, GATE_OUTCOME, RUN_STARTED_AT
import { readFileSync, renameSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

const BLOCKER_CHARS = 300;

export function normalizeReason(reason) {
	const raw =
		reason === null || reason === undefined || reason === false
			? "not ready"
			: String(reason);
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
}) {
	const refusals = {};
	let enqueued = 0;
	let merged = 0;
	for (const result of results) {
		if (result.enqueued) enqueued += 1;
		if (result.merged) merged += 1;
		if (!result.enqueued && !result.merged) {
			const key = normalizeReason(result.reason);
			refusals[key] = (refusals[key] ?? 0) + 1;
		}
	}
	const reached = results.length - held.length;
	const stopped =
		gateOutcome === "success" &&
		Number.isInteger(candidates) &&
		reached < candidates;
	return {
		run_id: runId,
		event,
		live,
		started_at: startedAt,
		candidates,
		enqueued,
		merged,
		refusal_counts: refusals,
		held: held.length,
		budget_stop: stopped
			? {
					reached,
					candidates,
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
	});
	const to = env.SWEEP_SUMMARY_TO;
	writeFileSync(`${to}.tmp`, JSON.stringify(out));
	renameSync(`${to}.tmp`, to);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) main();
