// The lane concurrency level L the adaptive throughput controller would pick
// for the next window, as a pure function of the previous decision, one
// window's readings, that window's lane demand and the resolved limits.
// Nothing reads it yet: it is the decide part of collect, decide, publish and
// read, and lane-level.vectors.json is its truth table.
//
//   previous  { level, streak, holdUntil } from the last decision, or null
//   readings  { at, pools: { <pool>: { used, limit } }, signals: [..], reset? }
//             at and reset are epoch seconds; used and limit come from the
//             pool's x-ratelimit headers; signals name each limit signal seen
//             (403, 429, a secondary-limit or GraphQL rate-limit error,
//             retry-after, a breaker trip)
//   demand    { waiting, running }: the most lane runs waiting for a slot
//             and the most running in the window, or null when unread
//   config    the resolved `limits` leaf: `lane-level` and `api`
//
// Returns { level, streak, holdUntil, reason }, reason one of step-up,
// step-down, streak, hot, hold, no-demand, no-fit, ceiling, missing-data.

export const LANE_LEVEL_DEFAULTS = Object.freeze({
  floor: 2,
  ceiling: 6,
  default: 3,
  "clean-windows": 2,
  pools: Object.freeze(["lanes-app"]),
});

// Shares are decimal configuration, so a boundary the config states exactly
// (0.7 x 3 x 5000) must not flip on binary rounding.
const EPSILON = 1e-9;

const isCount = (value) => Number.isInteger(value) && value >= 0;

function settings(config = {}) {
  const set = { ...LANE_LEVEL_DEFAULTS, ...(config["lane-level"] ?? {}) };
  const clamp = (level) => Math.min(set.ceiling, Math.max(set.floor, level));
  return { ...set, start: clamp(set.default), clamp, api: config.api ?? {} };
}

function shares(readings, s) {
  const out = [];
  for (const pool of s.pools) {
    const { used, limit } = readings?.pools?.[pool] ?? {};
    const { plan, "writer-pause": writerPause, "limit-cap": cap } = s.api[pool] ?? {};
    if (!Number.isFinite(used) || !Number.isFinite(limit) || limit <= 0 || !Number.isFinite(plan) || !Number.isFinite(writerPause)) {
      return null;
    }
    // As limits.api reads them: plan is a share of the planned budget, the
    // header's limit at most limit-cap; writer-pause a share of the header's.
    const planned = Number.isFinite(cap) ? Math.min(limit, cap) : limit;
    out.push({ planned: used / planned, left: (limit - used) / limit, plan, writerPause });
  }
  return out;
}

export function decide(previous, readings, demand, config) {
  const s = settings(config);
  const level = Number.isInteger(previous?.level) ? s.clamp(previous.level) : s.start;
  const streak = isCount(previous?.streak) ? Math.min(previous.streak, s["clean-windows"]) : 0;
  const holdUntil = Number.isFinite(previous?.holdUntil) ? previous.holdUntil : 0;
  const hold = (reason, next = {}) => ({ level, streak, holdUntil, reason, ...next });

  if (Array.isArray(readings?.signals) && readings.signals.length > 0) {
    const reset = Number.isFinite(readings.reset) ? readings.reset : 0;
    return { level: Math.max(s.floor, Math.floor(level / 2)), streak: 0, holdUntil: Math.max(holdUntil, reset), reason: "step-down" };
  }
  const pools = Number.isFinite(readings?.at) ? shares(readings, s) : null;
  if (pools === null) {
    return hold("missing-data");
  }
  if (pools.some((p) => p.left <= p.writerPause + EPSILON)) {
    return hold("hot", { streak: 0 });
  }
  if (readings.at < holdUntil) {
    return hold("hold", { streak: 0 });
  }
  if (!isCount(demand?.waiting) || !isCount(demand?.running)) {
    return hold("missing-data");
  }
  if (demand.waiting === 0 && demand.running < level) {
    return hold("no-demand");
  }
  const counted = Math.min(streak + 1, s["clean-windows"]);
  if (streak + 1 < s["clean-windows"]) {
    return hold("streak", { streak: counted });
  }
  if (level >= s.ceiling) {
    return hold("ceiling", { streak: counted });
  }
  if (pools.some((p) => (p.planned * (level + 1)) / level > p.plan + EPSILON)) {
    return hold("no-fit", { streak: counted });
  }
  return { level: level + 1, streak: 0, holdUntil, reason: "step-up" };
}
