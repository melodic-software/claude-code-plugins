import { mkdirSync, writeFileSync } from "node:fs";
import { basename, dirname } from "node:path";
import process from "node:process";

export function markLaneHold(env = process.env) {
  const path = env.LANE_HOLD_MARKER;
  if (!path) return false;
  try {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, `${basename(path)} ${env.GITHUB_RUN_ID ?? ""}\n`);
    return true;
  } catch {
    return false;
  }
}
