import { appendFileSync, mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { replaceFile } from "./atomic-file.mjs";
import { PLUGIN_ID } from "./profile-files.mjs";

export const SESSION_DAYS = 30;
export const PROFILE_NAME = /^[a-z0-9][a-z0-9-]*$/;
const DAY = 24 * 60 * 60 * 1000;
const ISO_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
const logFile = (dataDir) => join(dataDir, "exceptions.jsonl");

/** Appends timestamped records to the machine's exception log. */
export function appendExceptions(dataDir, records, now = Date.now()) {
  const at = new Date(now).toISOString();
  mkdirSync(dataDir, { recursive: true });
  appendFileSync(logFile(dataDir), records.map((record) => JSON.stringify({ ...record, at }) + "\n").join(""));
}

function readEntry(line, cutoff) {
  try {
    const entry = JSON.parse(line);
    const at = Date.parse(entry.at);
    if (typeof entry.at !== "string" || !ISO_TIME.test(entry.at) || !Number.isFinite(at) || at < cutoff) return null;
    if (typeof entry.profile !== "string" || !PROFILE_NAME.test(entry.profile) ||
        typeof entry.plugin !== "string" || !PLUGIN_ID.test(entry.plugin)) return null;
    if (entry.kind === "reviewed" || (entry.kind === "exception" &&
        typeof entry.sessionId === "string" && entry.sessionId && typeof entry.folder === "string" && entry.folder)) return entry;
  } catch {
    return null;
  }
  return null;
}

/** Reads retained records and atomically prunes expired or malformed lines. */
export function readExceptions(dataDir, now = Date.now()) {
  const file = logFile(dataDir);
  let original;
  try {
    original = readFileSync(file, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
  const records = [];
  const retained = [];
  for (const line of original.split("\n")) {
    const entry = readEntry(line, now - SESSION_DAYS * DAY);
    if (!entry) continue;
    records.push(entry);
    retained.push(line + "\n");
  }
  const text = retained.join("");
  if (text !== original) {
    const changed = new Error("exception log changed during pruning");
    try {
      replaceFile(file, text, { beforeRename: () => {
        if (readFileSync(file, "utf8") !== original) throw changed;
      } });
    } catch (error) {
      if (error !== changed) throw error;
    }
  }
  return records;
}

/** Summarizes distinct sessions per profile and plugin after each pair's last review. */
export function exceptionCounts(records) {
  const pairs = new Map();
  for (const { kind, profile, plugin, sessionId, at } of records) {
    const key = `${profile}:${plugin}`;
    if (kind === "reviewed" || !pairs.has(key)) pairs.set(key, { profile, plugin, sessions: new Set(), lastAt: null });
    if (kind === "reviewed") continue;
    const pair = pairs.get(key);
    pair.sessions.add(sessionId);
    if (!pair.lastAt || Date.parse(at) > Date.parse(pair.lastAt)) pair.lastAt = at;
  }
  return [...pairs.values()].map(({ sessions, ...pair }) => ({ ...pair, count: sessions.size, sessions: [...sessions] }));
}

/** Finds pairs in this profile with at least three distinct sessions since review. */
export const exceptionsToReview = (records, profile) =>
  exceptionCounts(records).filter((pair) => pair.profile === profile && pair.count >= 3);
