#!/usr/bin/env node
// Status-line segment for the main conversation's prompt cache.
//
// Reads a Claude Code statusline JSON payload on stdin and prints one line from its
// `prompt_cache` object, or nothing when the payload has none. It shows the expiry as a
// clock time rather than a countdown: Claude Code re-runs the status line when a warm
// cache reaches `expires_at`, so the line stays true without `refreshInterval`.
//
// Basis: https://code.claude.com/docs/en/statusline#prompt-cache-fields and
// #last-miss-cause. As of: 2026-10-10. Recheck trigger: that section renames a field read
// here, or stops re-running the status line at `expires_at`.
//
// A status line must never break, so every failure prints nothing and exits 0.

import { pathToFileURL } from "node:url";

const ESC = "\u001b[";
const paint = (color, text, on) =>
	on ? `${ESC}${color}m${text}${ESC}0m` : text;

export function formatTokens(n) {
	if (n < 1000) return String(n);
	if (n < 1_000_000) return `${Math.round(n / 1000)}k`;
	return `${(n / 1_000_000).toFixed(1).replace(/\.0$/, "")}M`;
}

function clock(epochSeconds) {
	const d = new Date(epochSeconds * 1000);
	const pad = (v) => String(v).padStart(2, "0");
	return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

const isNum = (v) => typeof v === "number" && Number.isFinite(v);

export function cacheLine(payload, { color = true } = {}) {
	const pc =
		payload && typeof payload === "object" ? payload.prompt_cache : undefined;
	if (!pc || typeof pc !== "object") return "";
	if (pc.caching_observed === false)
		return paint("2", "cache not reported", color);

	const parts = [];
	if (pc.warm === true) {
		let head = `${paint("32", "●", color)} warm`;
		if (isNum(pc.expires_at)) head += ` until ${clock(pc.expires_at)}`;
		if (typeof pc.ttl === "string") head += ` (${pc.ttl})`;
		parts.push(head);
	} else {
		parts.push(`${paint("31", "○", color)} cold`);
		if (isNum(pc.recache_tokens_if_cold) && pc.recache_tokens_if_cold > 0) {
			parts.push(
				`next message re-caches ~${formatTokens(pc.recache_tokens_if_cold)}`,
			);
		}
	}
	if (isNum(pc.hit_ratio)) parts.push(`hit ${Math.round(pc.hit_ratio * 100)}%`);
	if (isNum(pc.misses) && pc.misses > 0) {
		let miss = `misses ${pc.misses}`;
		const raw = pc.last_miss_cause?.causes;
		const causes = Array.isArray(raw)
			? raw.filter((c) => typeof c === "string")
			: [];
		if (causes.length > 0) miss += ` (last: ${causes.join(", ")})`;
		parts.push(miss);
	}
	return `cache ${parts.join(" · ")}`;
}

async function main() {
	let input = "";
	for await (const chunk of process.stdin) input += chunk;
	let payload;
	try {
		payload = JSON.parse(input);
	} catch {
		return;
	}
	const line = cacheLine(payload, { color: !("NO_COLOR" in process.env) });
	if (line) process.stdout.write(`${line}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
	main().catch(() => {});
}
