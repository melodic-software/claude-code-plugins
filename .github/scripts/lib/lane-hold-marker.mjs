// The marker a hold job keeps as its lane-hold-<lane> artifact, which monitor
// signal 13 lists to count held runs (maintenance-monitor-signals collect.mjs).
// Only a hold job sets LANE_HOLD_MARKER, a path whose file name is the lane;
// everywhere else this writes nothing. The body is the lane and the run id
// only, since the repository is public. A write that fails leaves the hold as
// it is: the marker is a record, not part of the hold.
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
