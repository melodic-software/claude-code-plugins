import { appendFileSync, mkdirSync, readFileSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";
import { replaceFile } from "./atomic-file.mjs";
import { PLUGIN_ID } from "./profile-files.mjs";

export const SESSION_DAYS = 30;
export const PROFILE_NAME = /^[a-z0-9][a-z0-9-]*$/;
const DAY = 24 * 60 * 60 * 1000;
const ISO_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
const logFile = (dataDir) => join(dataDir, "exceptions.jsonl");

const pause = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
const STALE_LOCK_MS = 10_000;

/**
 * Runs fn holding the log's lock, a directory every appender and pruner creates, so a prune never renames over an
 * append. A lock left by a crashed run is taken over once stale. Past waitMs, fn runs anyway when force is set (an
 * append is never dropped), and is skipped otherwise (a prune can wait for the next read).
 */
export function withLogLock(dataDir, fn, { waitMs = 0, force = false } = {}) {
  const lock = join(dataDir, "exceptions.lock");
  const deadline = Date.now() + waitMs;
  mkdirSync(dataDir, { recursive: true });
  for (;;) {
    try {
      mkdirSync(lock);
      break;
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
    }
    let age = 0;
    try {
      age = Date.now() - statSync(lock).mtimeMs;
    } catch {
      continue;
    }
    if (age > STALE_LOCK_MS) rmSync(lock, { recursive: true, force: true });
    else if (Date.now() >= deadline) return force ? fn() : undefined;
    else pause(10);
  }
  try {
    return fn();
  } finally {
    rmSync(lock, { recursive: true, force: true });
  }
}

/** Appends timestamped records to the machine's exception log. */
export function appendExceptions(dataDir, records, now = Date.now()) {
  const at = new Date(now).toISOString();
  const text = records.map((record) => JSON.stringify({ ...record, at }) + "\n").join("");
  withLogLock(dataDir, () => appendFileSync(logFile(dataDir), text), { waitMs: 2000, force: true });
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

const readLog = (file) => {
  try {
    return readFileSync(file, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
};

/** The records of the log's text still within retention, and the text that keeps only their lines. */
function retainedOf(original, now) {
  const records = [];
  let text = "";
  for (const line of original.split("\n")) {
    const entry = readEntry(line, now - SESSION_DAYS * DAY);
    if (!entry) continue;
    records.push(entry);
    text += line + "\n";
  }
  return { records, text };
}

/** Reads retained records and, under the log's lock, prunes expired or malformed lines. */
export function readExceptions(dataDir, now = Date.now()) {
  const file = logFile(dataDir);
  const original = readLog(file);
  if (original === null) return [];
  const { records, text } = retainedOf(original, now);
  if (text !== original) {
    withLogLock(dataDir, () => {
      const current = readLog(file);
      if (current !== null) replaceFile(file, retainedOf(current, now).text);
    });
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
