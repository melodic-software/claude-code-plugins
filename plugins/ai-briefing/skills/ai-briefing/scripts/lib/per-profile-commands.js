// Per-profile runner subcommand handlers — domain logic only; return { code, payload, save* }.

import { existsSync, promises as fs } from "node:fs";
import path from "node:path";

import { AntiBot } from "./anti-bot.js";
import { categorize as runCategorize } from "./categorize-agent.js";
import { validateExtractorOutput } from "./chrome-extract.js";
import { probeGrokAvailability } from "./grok-availability.js";
import {
  buildOrderedHandles,
  loadFollowingList,
  resolveCutoff,
} from "./per-profile-following.js";
import { stateRoot } from "./paths.js";
import {
  findNextPendingHandle,
  getOrInitProfile,
  getStateForRun,
  scanProfileStatuses,
} from "./per-profile-run-lookup.js";
import { validateCaptures, withRetries } from "./per-profile-validate.js";
import { createWithProfile } from "./runner-context.js";
import { isoBasicTimestamp, RunState } from "./state.js";
import { synthesize as runSynthesize } from "./synthesize-agent.js";

const { profileCmd } = createWithProfile({ getStateForRun, getOrInitProfile });

const cmdInit = profileCmd({ skipStateLoad: true }, async ({ flags }) => {
  const scope = flags.scope || "all";
  const cutoff = await resolveCutoff(flags.cutoff);
  let antiBotCap = 90;
  if (flags["anti-bot-cap"]) {
    antiBotCap = Number(flags["anti-bot-cap"]);
    if (!Number.isFinite(antiBotCap) || antiBotCap <= 0) {
      return {
        code: 2,
        payload: {
          error: `--anti-bot-cap must be a positive number, got: ${flags["anti-bot-cap"]}`,
        },
      };
    }
  }
  const force = !!flags.force;

  const existing = await RunState.findLatestInProgress(stateRoot());
  if (existing && !force) {
    return {
      code: 2,
      payload: {
        error: `Run ${existing} already in_progress/paused. Use --force to start a new one.`,
        existing_run_id: existing,
      },
    };
  }

  const followingList = await loadFollowingList();
  const orderedHandles = buildOrderedHandles(followingList, scope);
  const runId = isoBasicTimestamp();

  const master = {
    run_id: runId,
    status: "in_progress",
    started_at: new Date().toISOString(),
    completed_at: null,
    cutoff,
    scope,
    current_index: 0,
    ordered_handles: orderedHandles,
    by_status: {
      complete: 0,
      partial: 0,
      failed: 0,
      pending: orderedHandles.length,
    },
    anti_bot: {
      navs_used: 0,
      cap: antiBotCap,
      session_count: 1,
      paused_at: null,
    },
    config: {
      with_replies_medium: !!flags["with-replies-medium"],
      no_replies: !!flags["no-replies"],
      selector_probe_interval: 10,
      retry_s1_s2: 2,
      retry_s3_s4: 1,
      delay_min_ms: 2000,
      delay_max_ms: 5000,
      dry_run: !!flags["dry-run"],
    },
  };

  const state = new RunState({ skillRoot: stateRoot(), runId });
  await state.saveMaster(master);

  return {
    code: 0,
    payload: {
      run_id: runId,
      total: orderedHandles.length,
      scope,
      cutoff,
      ordered_handles: orderedHandles,
      anti_bot: master.anti_bot,
      config: master.config,
    },
  };
});

const cmdNextHandle = profileCmd({ includeComplete: true }, async ({ state, master, runId }) => {
  if (master.status === "complete") {
    return {
      code: 0,
      payload: { done: true, run_id: runId, by_status: master.by_status },
    };
  }

  const antiBot = AntiBot.fromMaster(master);
  antiBot.navsUsed = master.anti_bot.navs_used || 0;

  if (antiBot.shouldPause()) {
    master.status = "paused";
    master.anti_bot.paused_at = new Date().toISOString();
    return {
      code: 1,
      payload: { paused: true, reason: "anti-bot-cap", anti_bot: master.anti_bot, run_id: runId },
      saveMaster: true,
    };
  }

  const next = await findNextPendingHandle(state, master);
  if (next) {
    return {
      code: 0,
      payload: {
        handle: next.handle,
        index: next.index,
        priority_bucket: next.priority_bucket,
        posts: { url: next.posts.url, js: next.posts.js },
        replies: next.replies ? { url: next.replies.url, js: next.replies.js } : null,
        profile_path: next.profile_path,
        cutoff: master.cutoff,
        anti_bot: master.anti_bot,
        run_id: runId,
      },
    };
  }

  master.status = "complete";
  master.completed_at = new Date().toISOString();
  return {
    code: 0,
    payload: { done: true, run_id: runId, by_status: master.by_status },
    saveMaster: true,
  };
});

const cmdCommitS1 = profileCmd(
  { requireIndex: true },
  async ({ master, runId, profile, handle, flags }) => {
    const capturesPath = flags.captures;
    if (!capturesPath) throw new Error("--captures=<file> required");
    const raw = JSON.parse(await fs.readFile(capturesPath, "utf-8"));

    const postsValidated = raw.posts ? validateExtractorOutput(raw.posts) : null;
    const repliesValidated = raw.replies ? validateExtractorOutput(raw.replies) : null;

    if (profile.status === "failed") {
      profile.status = "in_progress";
      profile.errors = [];
    }

    const s1Start = Date.now();
    profile.stages.S1_capture = {
      status: "complete",
      started_at: new Date(s1Start).toISOString(),
      completed_at: new Date().toISOString(),
      posts_count: postsValidated?.tw?.length ?? 0,
      replies_count: repliesValidated?.tw?.length ?? 0,
      fallback_tier: postsValidated?.fallback_tier ?? null,
      ran_replies: !!repliesValidated,
    };
    profile.raw_captures = { posts: postsValidated, replies: repliesValidated };

    const s2 = validateCaptures({
      posts: postsValidated,
      replies: repliesValidated,
      cutoff: master.cutoff,
    });
    profile.stages.S2_validate = s2;
    if (!s2.passed && profile.status !== "failed") profile.status = "partial";

    const navsThisCommit = (postsValidated ? 1 : 0) + (repliesValidated ? 1 : 0);
    master.anti_bot.navs_used = (master.anti_bot.navs_used || 0) + navsThisCommit;

    return {
      code: 0,
      payload: {
        s2_passed: s2.passed,
        posts_count: profile.stages.S1_capture.posts_count,
        replies_count: profile.stages.S1_capture.replies_count,
        oldest_captured: s2.oldest_captured,
        cutoff_reached: s2.cutoff_reached,
        navs_used: master.anti_bot.navs_used,
        handle,
        run_id: runId,
      },
      saveProfile: true,
      saveMaster: true,
    };
  },
);

const cmdSynthesize = profileCmd(
  { requireIndex: true },
  async ({ state, master, runId, profile, handle, priority_bucket, index }) => {
    if (!profile.raw_captures || (!profile.raw_captures.posts && !profile.raw_captures.replies)) {
      return {
        code: 2,
        payload: { error: "No raw_captures present; run commit-s1 first", handle, index },
      };
    }

    const seenUrls = await state.loadSeenItemsUrlSet();
    const dryRun = !!master.config?.dry_run;
    const maxRetries = master.config?.retry_s3_s4 ?? 1;

    const s3Start = Date.now();
    let candidates = [];
    try {
      candidates = await withRetries(
        () =>
          runSynthesize({
            handle,
            priorityBucket: priority_bucket,
            posts: profile.raw_captures.posts?.tw ?? [],
            replies: profile.raw_captures.replies?.tw ?? [],
            seenUrls,
            dryRun,
          }),
        maxRetries,
      );
      profile.synthesized_candidates = candidates;
      profile.stages.S3_synthesize = {
        status: "complete",
        candidate_count: candidates.length,
        duration_ms: Date.now() - s3Start,
      };
    } catch (err) {
      profile.stages.S3_synthesize = {
        status: "partial",
        duration_ms: Date.now() - s3Start,
        error: err.message,
      };
      profile.errors.push({ stage: "S3", error: err.message });
      if (profile.status !== "failed") profile.status = "partial";
    }

    return {
      code: 0,
      payload: {
        candidate_count: candidates.length,
        candidates,
        handle,
        s3_status: profile.stages.S3_synthesize.status,
        error: profile.stages.S3_synthesize.error,
        run_id: runId,
      },
      saveProfile: true,
    };
  },
);

const cmdCategorize = profileCmd(
  { requireIndex: true },
  async ({ master, runId, profile, handle }) => {
    const candidates = profile.synthesized_candidates || [];
    const dryRun = !!master.config?.dry_run;
    const maxRetries = master.config?.retry_s3_s4 ?? 1;

    const s4Start = Date.now();
    let items = [];
    if (candidates.length === 0) {
      profile.stages.S4_categorize = {
        status: "complete",
        categorized_count: 0,
        dropped_apolitical: 0,
        duration_ms: 0,
      };
    } else {
      try {
        items = await withRetries(() => runCategorize(candidates, { dryRun }), maxRetries);
        profile.categorized_items = items;
        profile.stages.S4_categorize = {
          status: "complete",
          categorized_count: items.length,
          dropped_apolitical: candidates.length - items.length,
          duration_ms: Date.now() - s4Start,
        };
      } catch (err) {
        profile.stages.S4_categorize = {
          status: "partial",
          duration_ms: Date.now() - s4Start,
          error: err.message,
        };
        profile.errors.push({ stage: "S4", error: err.message });
        if (profile.status !== "failed") profile.status = "partial";
      }
    }

    return {
      code: 0,
      payload: {
        categorized_count: items.length,
        dropped_apolitical: profile.stages.S4_categorize.dropped_apolitical ?? 0,
        items,
        handle,
        s4_status: profile.stages.S4_categorize.status,
        error: profile.stages.S4_categorize.error,
        run_id: runId,
      },
      saveProfile: true,
    };
  },
);

const cmdCommitAndCheckoff = profileCmd(
  { requireIndex: true },
  async ({ state, master, runId, profile, handle, priority_bucket, index }) => {
    const items = profile.categorized_items || [];

    const s5Start = Date.now();
    let persisted = { items_added: 0, duplicates_dropped: 0 };
    if (items.length > 0) {
      persisted = await state.appendToSeenItems(items);
      await state.appendDelta(handle, priority_bucket, items);
    }
    profile.stages.S5_persist = {
      status: "complete",
      ...persisted,
      duration_ms: Date.now() - s5Start,
    };

    const priorStatus = profile.status;
    if (priorStatus !== "complete") {
      profile.status = "complete";
    }
    profile.stages.S6_checkoff = { status: "complete" };

    if (index === master.current_index) {
      if (priorStatus === "pending" || priorStatus === "in_progress" || !priorStatus) {
        master.by_status.pending = Math.max(0, (master.by_status.pending || 0) - 1);
      } else if (priorStatus === "failed") {
        master.by_status.failed = Math.max(0, (master.by_status.failed || 0) - 1);
      } else if (priorStatus === "partial") {
        master.by_status.partial = Math.max(0, (master.by_status.partial || 0) - 1);
      }
      master.by_status.complete = (master.by_status.complete || 0) + 1;
      master.current_index += 1;
    } else if (priorStatus === "failed") {
      master.by_status.failed = Math.max(0, (master.by_status.failed || 0) - 1);
      master.by_status.complete = (master.by_status.complete || 0) + 1;
    }

    let paused = false;
    const navsUsed = master.anti_bot.navs_used || 0;
    if (
      navsUsed >= (master.anti_bot.cap || 90) &&
      master.current_index < master.ordered_handles.length
    ) {
      master.status = "paused";
      master.anti_bot.paused_at = new Date().toISOString();
      paused = true;
    }

    if (master.current_index >= master.ordered_handles.length) {
      master.status = "complete";
      master.completed_at = new Date().toISOString();
    }

    return {
      code: paused ? 1 : 0,
      payload: {
        status: profile.status,
        items_added: persisted.items_added,
        duplicates_dropped: persisted.duplicates_dropped,
        current_index: master.current_index,
        total: master.ordered_handles.length,
        paused,
        anti_bot: master.anti_bot,
        handle,
        run_id: runId,
      },
      saveProfile: true,
      saveMaster: true,
      appendLog: {
        handle,
        status: profile.status,
        s5_ms: profile.stages.S5_persist.duration_ms,
        items_added: persisted.items_added,
        duplicates_dropped: persisted.duplicates_dropped,
        current_index: master.current_index,
      },
    };
  },
);

const cmdMarkFailed = profileCmd(
  { requireIndex: true },
  async ({ master, runId, profile, handle, index, flags }) => {
    const stage = flags.stage || "orchestration";
    const error = flags.error || "unspecified";

    profile.status = "failed";
    profile.errors.push({ stage, error });
    if (!profile.stages[`${stage}_capture`] && stage === "S1") {
      profile.stages.S1_capture = { status: "failed", error };
    } else {
      profile.stages[`${stage}_failure`] = { status: "failed", error };
    }

    if (index === master.current_index) {
      master.by_status.pending = Math.max(0, (master.by_status.pending || 0) - 1);
      master.by_status.failed = (master.by_status.failed || 0) + 1;
      master.current_index += 1;
    }

    return {
      code: 0,
      payload: {
        status: "failed",
        current_index: master.current_index,
        by_status: master.by_status,
        handle,
        run_id: runId,
      },
      saveProfile: true,
      saveMaster: true,
      appendLog: {
        handle,
        status: "failed",
        stage_failed: stage,
        error,
        current_index: master.current_index,
      },
    };
  },
);

const cmdStatus = profileCmd({ includeComplete: true }, async ({ master, runId }) => ({
  code: 0,
  payload: {
    run_id: runId,
    status: master.status,
    current_index: master.current_index,
    total: master.ordered_handles.length,
    by_status: master.by_status,
    anti_bot: master.anti_bot,
    cutoff: master.cutoff,
    scope: master.scope,
  },
}));

const cmdSummary = profileCmd({ includeComplete: true }, async ({ state, master, runId }) => {
  const total = master.ordered_handles.length;

  const { complete, partial, failed, pending, failedHandles } = await scanProfileStatuses(
    state,
    master,
  );
  master.by_status = { complete, partial, failed, pending };

  if (master.current_index >= total && pending === 0) {
    master.status = "complete";
    if (!master.completed_at) master.completed_at = new Date().toISOString();
  }

  return {
    code: failed > 0 ? 3 : 0,
    payload: {
      run_id: runId,
      status: master.status,
      total,
      by_status: master.by_status,
      anti_bot: master.anti_bot,
      cutoff: master.cutoff,
      scope: master.scope,
      started_at: master.started_at,
      completed_at: master.completed_at,
      failed_handles: failedHandles,
    },
    saveMaster: true,
  };
});

const cmdDetectResume = profileCmd({ skipStateLoad: true }, async () => {
  const runsDir = path.join(stateRoot(), "context", "runs");
  if (!existsSync(runsDir)) {
    return { code: 0, payload: { noActiveRun: true, reason: "no-runs-dir" } };
  }
  const entries = await fs.readdir(runsDir, { withFileTypes: true });
  const live = (
    await Promise.all(
      entries
        .filter((e) => e.isDirectory())
        .map(async (e) => {
          const masterPath = path.join(runsDir, e.name, "master.json");
          if (!existsSync(masterPath)) return null;
          try {
            const m = JSON.parse(await fs.readFile(masterPath, "utf-8"));
            if (m.status === "in_progress" || m.status === "paused") {
              return { runId: e.name, master: m };
            }
          } catch {
            /* skip corrupt */
          }
          return null;
        }),
    )
  ).filter(Boolean);
  if (!live.length) {
    return { code: 0, payload: { noActiveRun: true } };
  }
  live.sort((a, b) => (b.master.started_at || "").localeCompare(a.master.started_at || ""));
  const { runId, master } = live[0];

  const deltasPath = path.join(runsDir, runId, "briefing-deltas.md");
  let deltasLines = 0;
  let itemsCount = 0;
  if (existsSync(deltasPath)) {
    const text = await fs.readFile(deltasPath, "utf-8");
    deltasLines = text.split("\n").length;
    itemsCount = (text.match(/^### /gm) || []).length;
  }

  const total = master.ordered_handles?.length ?? 0;
  const nextHandle = master.ordered_handles?.[master.current_index] ?? null;
  const completedHandles = master.ordered_handles?.slice(0, master.current_index) ?? [];

  return {
    code: 0,
    payload: {
      noActiveRun: false,
      run_id: runId,
      status: master.status,
      current_index: master.current_index,
      total,
      by_status: master.by_status,
      anti_bot: master.anti_bot,
      cutoff: master.cutoff,
      scope: master.scope,
      started_at: master.started_at,
      next_handle: nextHandle,
      completed_handles: completedHandles,
      items_added: itemsCount,
      deltas_lines: deltasLines,
      other_live_runs: live.slice(1).map((l) => l.runId),
    },
  };
});

const cmdAbandon = profileCmd({ includeComplete: true }, async ({ master, runId, flags }) => {
  if (master.status === "complete") {
    return {
      code: 2,
      payload: {
        error: `Run ${runId} is already complete; nothing to abandon`,
        run_id: runId,
        status: master.status,
      },
    };
  }
  master.status = "abandoned";
  master.abandoned_at = new Date().toISOString();
  master.abandon_reason = flags.reason || null;
  return {
    code: 0,
    payload: {
      run_id: runId,
      status: "abandoned",
      current_index: master.current_index,
      total: master.ordered_handles.length,
    },
    saveMaster: true,
  };
});

const cmdResumePaused = profileCmd({}, async ({ master, runId }) => {
  if (master.status !== "paused") {
    return {
      code: 2,
      payload: {
        error: `Run ${runId} is not paused (status=${master.status}); nothing to resume`,
        run_id: runId,
        status: master.status,
      },
    };
  }
  master.status = "in_progress";
  master.anti_bot.navs_used = 0;
  master.anti_bot.session_count = (master.anti_bot.session_count || 0) + 1;
  master.anti_bot.paused_at = null;
  return {
    code: 0,
    payload: {
      run_id: runId,
      status: "in_progress",
      current_index: master.current_index,
      total: master.ordered_handles.length,
      anti_bot: master.anti_bot,
    },
    saveMaster: true,
  };
});

const cmdGrokCheck = profileCmd({ skipStateLoad: true }, async () => {
  const probe = probeGrokAvailability();
  return {
    code: 0,
    payload: { ...probe, required_for_briefing: false },
  };
});

const cmdRetryFailed = profileCmd({ includeComplete: true }, async ({ state, master, runId }) => {
  const profiles = await Promise.all(master.ordered_handles.map((h, i) => state.loadProfile(i, h)));
  const handles = master.ordered_handles.flatMap((h, i) => {
    const p = profiles[i];
    if (p?.status !== "failed") return [];
    const lastErr = p.errors?.[p.errors.length - 1]?.error || "unknown";
    return [{ handle: h, index: i, last_error: lastErr }];
  });
  return {
    code: 0,
    payload: { handles, total: handles.length, run_id: runId },
  };
});

export function buildSubcommands() {
  return {
    init: cmdInit,
    "grok-check": cmdGrokCheck,
    "next-handle": cmdNextHandle,
    "commit-s1": cmdCommitS1,
    synthesize: cmdSynthesize,
    categorize: cmdCategorize,
    "commit-and-checkoff": cmdCommitAndCheckoff,
    "mark-failed": cmdMarkFailed,
    status: cmdStatus,
    summary: cmdSummary,
    "retry-failed": cmdRetryFailed,
    "resume-paused": cmdResumePaused,
    "detect-resume": cmdDetectResume,
    abandon: cmdAbandon,
  };
}

export const SUBCOMMANDS = buildSubcommands();
