// Following-list registry + ordered-handle construction for per-profile runner.

import { existsSync, promises as fs } from "node:fs";
import path from "node:path";

import { configDir, SEED_DIR, SKILL_ROOT, stateRoot } from "./paths.js";

export { SKILL_ROOT };

// Reads the X/Twitter handle registry. Resolution ladder: the active profile's
// tracked `following-list.json` under the consumer project first, then the
// bundled neutral seed. `--refresh-following` re-scrapes the source account's
// following and writes the profile copy.
export async function loadFollowingList() {
  const candidates = [
    path.join(configDir(), "following-list.json"),
    path.join(SEED_DIR, "following-list.json"),
  ];
  for (const candidate of candidates) {
    try {
      return JSON.parse(await fs.readFile(candidate, "utf-8"));
    } catch (err) {
      if (err.code !== "ENOENT") throw err;
    }
  }
  throw new Error(
    `following-list missing — expected one of:\n  ${candidates.join("\n  ")}\n` +
      "Run `/ai-briefing:setup` to scaffold a profile.",
  );
}

export function buildOrderedHandles(followingList, scope) {
  const sp = followingList.scan_priority;
  const sortAlpha = (arr) =>
    [...(arr || [])].sort((a, b) => a.localeCompare(b, "en", { sensitivity: "base" }));

  const high = sortAlpha(sp.high_signal_required);
  const leadership = sortAlpha(sp.leadership_low_volume);
  const medium = sortAlpha(sp.medium_signal);
  const low = sortAlpha(sp.low_signal_skip_default);

  switch (scope) {
    case "all":
      return [...high, ...leadership, ...medium, ...low];
    case "all-non-skip":
      return [...high, ...leadership, ...medium];
    case "high":
      return [...high];
    case "test":
      return high.slice(0, 3);
    default:
      throw new Error(`Unknown scope: ${scope}`);
  }
}

export function priorityBucketFor(handle, sp) {
  const lcEq = (arr) => (arr || []).some((h) => h.toLowerCase() === handle.toLowerCase());
  if (lcEq(sp.high_signal_required)) return "high_signal_required";
  if (lcEq(sp.leadership_low_volume)) return "leadership_low_volume";
  if (lcEq(sp.medium_signal)) return "medium_signal";
  if (lcEq(sp.low_signal_skip_default)) return "low_signal_skip_default";
  return "unknown";
}

export function shouldRunReplies(priorityBucket, master) {
  const cfg = master.config || {};
  if (cfg.no_replies) return false;
  if (priorityBucket === "high_signal_required") return true;
  if (priorityBucket === "leadership_low_volume") return true;
  if (priorityBucket === "medium_signal" && cfg.with_replies_medium) return true;
  return false;
}

export async function resolveCutoff(explicit) {
  if (explicit) return explicit;
  const seenPath = path.join(stateRoot(), "context", "seen-items.json");
  if (existsSync(seenPath)) {
    const seen = JSON.parse(await fs.readFile(seenPath, "utf-8"));
    const opened = seen?.current_meeting_window?.opened_date;
    if (opened) return opened;
    if (seen?.last_meeting_date) return new Date(seen.last_meeting_date).toISOString();
  }
  return new Date(Date.now() - 14 * 24 * 3600 * 1000).toISOString();
}
