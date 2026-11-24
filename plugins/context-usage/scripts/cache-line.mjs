#!/usr/bin/env node

import { spawnSync } from "node:child_process";

const SELF = "~/.claude/context-usage/cache-line.mjs";
const ESC = "\u001b[";
const paint = (color, text, on) => (on ? `${ESC}${color}m${text}${ESC}0m` : text);
// biome-ignore lint/suspicious/noControlCharactersInRegex: stripping them is the point
const clean = (s) => s.replace(/[\u0000-\u001f\u007f-\u009f]/g, "");
const isNum = (v) => typeof v === "number" && Number.isFinite(v);

function formatTokens(n) {
  if (n < 1000) return String(n);
  const k = Math.round(n / 1000);
  if (k < 1000) return `${k}k`;
  return `${(n / 1_000_000).toFixed(1).replace(/\.0$/, "")}M`;
}

function clock(epochSeconds) {
  const d = new Date(epochSeconds * 1000);
  const pad = (v) => String(v).padStart(2, "0");
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function cacheLine(payload, color) {
  const pc = payload?.prompt_cache;
  if (!pc || typeof pc !== "object" || Array.isArray(pc)) return "";
  if (pc.caching_observed === false) return paint("2", "cache not reported", color);
  if (typeof pc.warm !== "boolean") return "";

  const parts = [];
  if (pc.warm) {
    let head = `${paint("32", "●", color)} warm`;
    if (isNum(pc.expires_at)) head += ` until ${clock(pc.expires_at)}`;
    if (typeof pc.ttl === "string") head += ` (${clean(pc.ttl)})`;
    parts.push(head);
  } else {
    parts.push(`${paint("31", "○", color)} cold`);
    if (isNum(pc.recache_tokens_if_cold) && pc.recache_tokens_if_cold > 0) {
      parts.push(`next message re-caches ~${formatTokens(pc.recache_tokens_if_cold)}`);
    }
  }
  if (isNum(pc.hit_ratio)) parts.push(`hit ${Math.round(pc.hit_ratio * 100)}%`);
  if (isNum(pc.misses) && pc.misses > 0) {
    let miss = `misses ${pc.misses}`;
    const raw = pc.last_miss_cause?.causes;
    const causes = Array.isArray(raw) ? raw.filter((c) => typeof c === "string").map(clean) : [];
    if (causes.length > 0) miss += ` (last: ${causes.join(", ")})`;
    parts.push(miss);
  }
  return `cache ${parts.join(" · ")}`;
}

const shellQuote = (s) => `'${s.replaceAll("'", "'\\''")}'`;

function wire(settingsText) {
  let settings = {};
  try {
    settings = JSON.parse(settingsText || "{}");
  } catch {
    return { error: "settings.json is not valid JSON; nothing printed" };
  }
  const current = typeof settings?.statusLine === "object" ? settings.statusLine : null;
  const existing = typeof current?.command === "string" ? current.command : "";
  if (existing.includes("cache-line.mjs")) {
    return { statusLine: current, note: "already wired; no change" };
  }
  const command = existing ? `node ${SELF} --after ${shellQuote(existing)}` : `node ${SELF}`;
  return {
    statusLine: { ...(current ?? { type: "command" }), command },
  };
}

async function readStdin() {
  let input = "";
  for await (const chunk of process.stdin) input += chunk;
  return input;
}

async function main() {
  const args = process.argv.slice(2);
  const input = await readStdin();

  if (args[0] === "--wire") {
    const out = wire(input);
    if (out.error) {
      process.stderr.write(`${out.error}\n`);
      process.exitCode = 1;
      return;
    }
    if (out.note) process.stderr.write(`${out.note}\n`);
    process.stdout.write(`${JSON.stringify({ statusLine: out.statusLine }, null, 2)}\n`);
    return;
  }

  if (args[0] === "--after" && typeof args[1] === "string") {
    const opts = { input, stdio: ["pipe", "pipe", "inherit"] };
    const shells = [
      ["bash", ["-c", args[1]]],
      ["sh", ["-c", args[1]]],
    ];
    if (process.platform === "win32")
      shells.push(["powershell.exe", ["-NoProfile", "-Command", args[1]]]);
    let run;
    for (const [bin, argv] of shells) {
      run = spawnSync(bin, argv, opts);
      if (run.error?.code !== "ENOENT") break;
    }
    if (run.error) process.stderr.write(`cache-line: ${run.error.message}\n`);
    const prior = run.stdout ? run.stdout.toString() : "";
    if (prior) process.stdout.write(prior.endsWith("\n") ? prior : `${prior}\n`);
  }

  let payload;
  try {
    payload = JSON.parse(input);
  } catch {
    return;
  }
  const line = cacheLine(payload, !process.env.NO_COLOR);
  if (line) process.stdout.write(`${line}\n`);
}

main().catch(() => {});
