// The review-only follow-up of a token window's full pass
// (https://github.com/melodic-software/claude-code-plugins/issues/17460).
import { readFileSync } from "node:fs";

import { annotationsPath } from "../lib/run-jobs.mjs";
import { escapeCommand } from "../pr-merge/rotation.mjs";
import { LOOKBACK_HOURS } from "./infra-failure.mjs";
import {
  ciRecoveryFirst,
  DEFER_MAX,
  DEFERRED,
  isRedChecks,
  newestByWorkflow,
  onlyAggregateFailed,
  passRateLimit,
  rateHeldNoted,
  reconciledPull,
  RECORDED_UPSTREAMS,
  reviewStopNoted,
  stoppedReviews,
  upstreamGate,
  waitingReview,
  withAnnotations,
} from "./reconcile.mjs";

export function readQueue(path) {
  const data = JSON.parse(readFileSync(path, "utf8"));
  if (!Array.isArray(data?.waiting_reviews) || !data.waiting_reviews.every(waitingReview)) {
    throw new Error("the follow-up queue has an unexpected shape");
  }
  const heads = new Map();
  for (const row of data.waiting_reviews) {
    heads.set(row.checksRunId, [...(heads.get(row.checksRunId) ?? []), row]);
  }
  return heads;
}

export async function followUp({ repo, call, say, now, env, readStatus }) {
  let heads;
  try {
    heads = readQueue(env.FOLLOWUP_PATH ?? "");
  } catch (error) {
    say(`no follow-up queue was read (${escapeCommand(error?.message ?? error)}); nothing re-run`);
    console.log("::notice title=reconcile::reconcile follow-up tick: 0 queued, 0 re-run");
    return { items: [], failed: 0 };
  }
  const since = now - LOOKBACK_HOURS * 3_600_000;
  const gateHold = upstreamGate(readStatus);
  const waitReset = (what, reset, how) => say(`${what} ${how}; waiting for the rate-limit reset at ${new Date(reset).toISOString()}`);
  const readJobs = async (r) => {
    const listed = await call("GET", `/repos/${repo}/actions/runs/${r.id}/jobs?filter=latest&per_page=100`);
    if (!Array.isArray(listed?.jobs) || listed.total_count > 100) {
      throw new Error(`run ${r.id}'s job listing is not one complete page`);
    }
    return withAnnotations(call, repo, listed.jobs, (job) => job?.conclusion === "failure");
  };
  const items = [];
  let failed = 0;
  let room = DEFER_MAX;
  const toFullPass = (pull, why) => say(`#${pull.number}: ${why}; the next full pass decides its reviews`);
  for (const [checksRunId, rows] of heads) {
    const pull = { number: rows[0].pr, head: { sha: rows[0].head } };
    try {
      const listing = await call("GET", `/repos/${repo}/actions/runs?head_sha=${pull.head.sha}&per_page=100`);
      if (!Array.isArray(listing?.workflow_runs) || listing.total_count > 100) {
        throw new Error("its run listing is not one complete page");
      }
      const own = listing.workflow_runs.filter((r) => r.head_repository?.full_name === repo);
      const checks = newestByWorkflow(own).find((r) => RECORDED_UPSTREAMS.has(r.path));
      if (checks?.id !== checksRunId) {
        toFullPass(pull, `checks run ${checksRunId} is no longer the head's newest`);
        continue;
      }
      if (checks.status !== "completed") {
        say(`#${pull.number}: checks run ${checks.id} has not finished; the next tick looks again`);
        continue;
      }
      if (!isRedChecks(checks)) {
        say(`#${pull.number}: checks run ${checks.id} ended ${checks.conclusion}; no queued review is re-run`);
        continue;
      }
      if (ciRecoveryFirst(own, since)) {
        toFullPass(pull, "a CI run on the head is the full pass's to recover first");
        continue;
      }
      const live = await call("GET", `/repos/${repo}/pulls/${pull.number}`);
      if (!reconciledPull(live, repo) || live.head.sha !== pull.head.sha) {
        toFullPass(pull, "the pull request is no longer an open ready PR into main at the queued head");
        continue;
      }
      const status = onlyAggregateFailed(await readJobs(checks));
      const notes = status && (status.annotations ?? (await call("GET", annotationsPath(repo, status.id))));
      if (!reviewStopNoted(notes) && !rateHeldNoted(notes)) {
        toFullPass(pull, `checks run ${checks.id} failed on more than a review stop`);
        continue;
      }
      const queued = new Set(rows.map((row) => row.reviewRunId));
      const found = await stoppedReviews({ call, repo, own, pull, env, now, readJobs, say, waitReset, gateHold });
      if (found.length === 0) {
        continue;
      }
      if (!found.every((item) => queued.has(item.id) && item.conclusion === DEFERRED)) {
        toFullPass(pull, "its stopped reviews are not all queued deferrals, and a full pass counts the re-run places");
      } else if (found.length > room) {
        say(`#${pull.number}: its deferred reviews wait, only ${room} of ${DEFER_MAX} recovery places left this pass`);
      } else {
        items.push(...found);
        room -= found.length;
      }
    } catch (error) {
      passRateLimit(error);
      failed += 1;
      console.log(`::error title=reconcile::#${pull.number} follow-up: ${escapeCommand(error?.message ?? error)}`);
    }
  }
  console.log(`::notice title=reconcile::reconcile follow-up tick: ${[...heads.values()].flat().length} queued, ${items.length} re-run`);
  return { items, failed };
}
