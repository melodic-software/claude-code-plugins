// State management — master.json, per-profile JSON, seen-items append, briefing-deltas.md, synthesis-log.jsonl
// Atomic writes via temp+rename.

import { randomBytes } from "node:crypto";
import { existsSync, promises as fs } from "node:fs";
import path from "node:path";

const LEADING_AT_REGEX = /^@/;
const TRACKING_PARAM_REGEX = /^utm_|^ref$|^s$|^t$|^cb$/i;
const TRAILING_SLASHES_REGEX = /\/+$/;
const ISO_BASIC_DASH_COLON_REGEX = /[-:]/g;
const ISO_BASIC_MILLIS_REGEX = /\.\d{3}/;
const ISO_BASIC_FRACTION_REGEX = /\..*/;

export function slugifyHandle(handle) {
  return handle.replace(LEADING_AT_REGEX, "").toLowerCase();
}

export function profileFilename(index, handle) {
  const padded = String(index + 1).padStart(3, "0");
  return `${padded}-${slugifyHandle(handle)}.json`;
}

export async function atomicWriteText(filePath, text) {
  const dir = path.dirname(filePath);
  await fs.mkdir(dir, { recursive: true });
  const tmpPath = path.join(
    dir,
    `.${path.basename(filePath)}.${randomBytes(4).toString("hex")}.tmp`,
  );
  await fs.writeFile(tmpPath, text, "utf-8");
  await fs.rename(tmpPath, filePath);
}

export async function atomicWriteJson(filePath, data) {
  await atomicWriteText(filePath, JSON.stringify(data, null, 2));
}

export async function readJson(filePath) {
  const raw = await fs.readFile(filePath, "utf-8");
  return JSON.parse(raw);
}

export class RunState {
  constructor({ skillRoot, runId }) {
    this.skillRoot = skillRoot;
    this.runId = runId;
    this.runDir = path.join(skillRoot, "context", "runs", runId);
    this.masterPath = path.join(this.runDir, "master.json");
    this.profilesDir = path.join(this.runDir, "per-profile");
    this.logPath = path.join(this.runDir, "synthesis-log.jsonl");
    this.deltasPath = path.join(this.runDir, "briefing-deltas.md");
    this.seenItemsPath = path.join(skillRoot, "context", "seen-items.json");
  }

  static async findLatestInProgress(skillRoot) {
    const runsDir = path.join(skillRoot, "context", "runs");
    if (!existsSync(runsDir)) return null;
    const entries = await fs.readdir(runsDir, { withFileTypes: true });
    const candidates = (
      await Promise.all(
        entries
          .filter((e) => e.isDirectory())
          .map(async (e) => {
            const masterPath = path.join(runsDir, e.name, "master.json");
            if (!existsSync(masterPath)) return null;
            try {
              const m = JSON.parse(await fs.readFile(masterPath, "utf-8"));
              if (m.status === "in_progress" || m.status === "paused") {
                return { runId: e.name, started: m.started_at };
              }
            } catch {
              /* skip corrupt */
            }
            return null;
          }),
      )
    ).filter(Boolean);
    candidates.sort((a, b) => (b.started || "").localeCompare(a.started || ""));
    return candidates[0]?.runId ?? null;
  }

  async loadMaster() {
    return await readJson(this.masterPath);
  }

  async saveMaster(master) {
    await atomicWriteJson(this.masterPath, master);
  }

  async loadProfile(index, handle) {
    const fp = path.join(this.profilesDir, profileFilename(index, handle));
    if (!existsSync(fp)) return null;
    return await readJson(fp);
  }

  async saveProfile(profile) {
    const fp = path.join(this.profilesDir, profileFilename(profile.index, profile.handle));
    await atomicWriteJson(fp, profile);
  }

  async loadSeenItemsUrlSet() {
    if (!existsSync(this.seenItemsPath)) return new Set();
    const seen = await readJson(this.seenItemsPath);
    const set = new Set();
    for (const item of seen.items || []) {
      if (item.url) set.add(normalizeUrl(item.url));
    }
    return set;
  }

  async appendToSeenItems(items) {
    let seen = { last_run: null, items: [], runs: [] };
    if (existsSync(this.seenItemsPath)) seen = await readJson(this.seenItemsPath);
    // biome-ignore lint/suspicious/noUnnecessaryConditions: seen is reassigned from readJson() (untyped disk JSON) on the line above; persisted state may lack `items`, so the `|| []` guard is real. Biome only sees the literal initializer.
    seen.items = seen.items || [];

    const existingUrls = new Set(seen.items.map((i) => normalizeUrl(i.url)));
    let added = 0;
    let dupes = 0;

    for (const item of items) {
      const urls = item.urls || [];
      const primary = urls[0];
      if (!primary) continue;
      const norm = normalizeUrl(primary);
      if (existingUrls.has(norm)) {
        dupes++;
        continue;
      }
      existingUrls.add(norm);
      seen.items.push({
        url: primary,
        title: item.title,
        provider: item.bucket,
        tier: item.tier,
        source_type: item.source_type ?? "twitter",
        first_seen: new Date().toISOString().substring(0, 10),
        confidence: "high",
        run_id: this.runId,
      });
      added++;
    }

    seen.last_run = new Date().toISOString();
    await atomicWriteJson(this.seenItemsPath, seen);
    return { items_added: added, duplicates_dropped: dupes };
  }

  async appendDelta(handle, priorityBucket, items) {
    if (!items || items.length === 0) return;
    const lines = [];
    lines.push(`## ${handle} (${priorityBucket}) — ${items.length} item(s)\n`);
    for (const item of items) {
      lines.push(`### ${item.bucket} [${item.tier}] — ${item.title}`);
      lines.push(item.summary);
      if (item.urls?.length) lines.push(`URLs: ${item.urls.join(", ")}`);
      if (item.date) lines.push(`Date: ${item.date}`);
      lines.push("");
    }
    lines.push("");
    await fs.mkdir(path.dirname(this.deltasPath), { recursive: true });
    await fs.appendFile(this.deltasPath, lines.join("\n"), "utf-8");
  }

  async appendLog(entry) {
    await fs.mkdir(path.dirname(this.logPath), { recursive: true });
    const line = `${JSON.stringify({ ts: new Date().toISOString(), ...entry })}\n`;
    await fs.appendFile(this.logPath, line, "utf-8");
  }
}

export function normalizeUrl(url) {
  if (!url) return "";
  try {
    const u = new URL(url);
    // Strip tracking params
    for (const k of [...u.searchParams.keys()]) {
      if (TRACKING_PARAM_REGEX.test(k)) u.searchParams.delete(k);
    }
    let host = u.hostname.toLowerCase();
    if (host === "twitter.com") host = "x.com";
    const pathname = u.pathname.replace(TRAILING_SLASHES_REGEX, "");
    return `${u.protocol}//${host}${pathname}${u.search}`;
  } catch {
    return url.toLowerCase().replace(TRAILING_SLASHES_REGEX, "");
  }
}

export function isoBasicTimestamp(date = new Date()) {
  return date
    .toISOString()
    .replace(ISO_BASIC_DASH_COLON_REGEX, "")
    .replace(ISO_BASIC_MILLIS_REGEX, "")
    .replace(ISO_BASIC_FRACTION_REGEX, "");
}
