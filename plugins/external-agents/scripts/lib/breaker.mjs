import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const file = (dataDir, product) => join(dataDir, "breaker", `${product}.json`);

export function readBreaker(dataDir, product) {
  try {
    return JSON.parse(readFileSync(file(dataDir, product), "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

export function openBreaker(dataDir, product, { failureClass, reason, now, resetAt, cooldownHours }) {
  const state = {
    product,
    class: failureClass,
    reason,
    opened_at: new Date(now).toISOString(),
    next_trial_at: resetAt ?? new Date(now + cooldownHours * 3_600_000).toISOString(),
  };
  const target = file(dataDir, product);
  mkdirSync(join(dataDir, "breaker"), { recursive: true });
  const tmp = `${target}.${process.pid}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(state, null, 2)}\n`);
  renameSync(tmp, target);
  return state;
}

export const closeBreaker = (dataDir, product) => rmSync(file(dataDir, product), { force: true });

/** @returns the open state while its next trial is still ahead, else null. */
export function blockedBy(dataDir, product, now) {
  const state = readBreaker(dataDir, product);
  return state && Date.parse(state.next_trial_at) > now ? state : null;
}
