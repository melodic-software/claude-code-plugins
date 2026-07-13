// Run/profile resolution + pending-handle scan for per-profile runner.

import { existsSync, promises as fs } from "node:fs";
import path from "node:path";

import { findSequential } from "./async-seq.js";
import { buildExtractorJs } from "./chrome-extract.js";
import {
  loadFollowingList,
  priorityBucketFor,
  shouldRunReplies,
} from "./per-profile-following.js";
import { stateRoot } from "./paths.js";
import { profileFilename, RunState } from "./state.js";

export async function findLatestRunId({ includeComplete = false } = {}) {
  const runsDir = path.join(stateRoot(), "context", "runs");
  if (!existsSync(runsDir)) return null;
  const entries = await fs.readdir(runsDir, { withFileTypes: true });
  const live = [];
  const completed = [];
  const scanned = await Promise.all(
    entries
      .filter((e) => e.isDirectory())
      .map(async (e) => {
        const masterPath = path.join(runsDir, e.name, "master.json");
        if (!existsSync(masterPath)) return null;
        try {
          const m = JSON.parse(await fs.readFile(masterPath, "utf-8"));
          const isLive = m.status === "in_progress" || m.status === "paused";
          const entry = { runId: e.name, started: m.started_at || "" };
          return { isLive, isComplete: m.status === "complete", entry };
        } catch {
          return null;
        }
      }),
  );
  for (const row of scanned) {
    if (!row) continue;
    if (row.isLive) live.push(row.entry);
    else if (includeComplete && row.isComplete) completed.push(row.entry);
  }
  // Prefer live runs over completed when both exist — a newer completed run
  // (e.g. after init --force on top of an older paused one) MUST NOT shadow
  // unfinished work and cause next-handle to return done:true prematurely.
  const pool = live.length > 0 ? live : completed;
  pool.sort((a, b) => b.started.localeCompare(a.started));
  return pool[0]?.runId ?? null;
}

export async function getStateForRun(flags, { includeComplete = false } = {}) {
  let runId = flags.resume || null;
  if (!runId) runId = await findLatestRunId({ includeComplete });
  if (!runId) {
    throw new Error("No matching run found. Run `init` first or pass --resume=<run-id>.");
  }
  const state = new RunState({ skillRoot: stateRoot(), runId });
  const master = await state.loadMaster();
  return { state, master, runId };
}

export async function getOrInitProfile(state, master, index) {
  const handle = master.ordered_handles[index];
  if (handle === undefined)
    throw new Error(`Index ${index} out of range (total ${master.ordered_handles.length})`);
  const sp = (await loadFollowingList()).scan_priority;
  const priority_bucket = priorityBucketFor(handle, sp);
  let profile = await state.loadProfile(index, handle);
  if (!profile) {
    profile = {
      handle,
      index,
      priority_bucket,
      status: "in_progress",
      stages: {},
      raw_captures: {},
      synthesized_candidates: [],
      categorized_items: [],
      errors: [],
    };
  }
  return { profile, handle, priority_bucket };
}

export async function scanProfileStatuses(state, master) {
  const profiles = await Promise.all(
    master.ordered_handles.map((handle, i) => state.loadProfile(i, handle)),
  );
  let complete = 0;
  let partial = 0;
  let failed = 0;
  let pending = 0;
  const failedHandles = [];
  profiles.forEach((p, i) => {
    const handle = master.ordered_handles[i];
    if (!p) {
      pending++;
      return;
    }
    if (p.status === "complete") complete++;
    else if (p.status === "partial") partial++;
    else if (p.status === "failed") {
      failed++;
      const lastErr = p.errors?.[p.errors.length - 1]?.error || "unknown";
      failedHandles.push({ handle, index: i, last_error: lastErr });
    } else pending++;
  });
  return { complete, partial, failed, pending, failedHandles };
}

export async function findNextPendingHandle(state, master) {
  const handles = master.ordered_handles.slice(master.current_index);
  return findSequential(handles, async (handle, offset) => {
    const i = master.current_index + offset;
    const existing = await state.loadProfile(i, handle);
    if (existing?.status === "complete") return null;

    const sp = (await loadFollowingList()).scan_priority;
    const priority_bucket = priorityBucketFor(handle, sp);
    const wantReplies = shouldRunReplies(priority_bucket, master);
    const posts = buildExtractorJs({ handle, surface: "posts", cutoffIso: master.cutoff });
    const replies = wantReplies
      ? buildExtractorJs({ handle, surface: "with_replies", cutoffIso: master.cutoff })
      : null;
    const profile_path = path.join(state.profilesDir, profileFilename(i, handle));
    return { handle, index: i, priority_bucket, posts, replies, profile_path };
  });
}
