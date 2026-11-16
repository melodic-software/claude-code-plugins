// The other live Claude Code sessions working in one folder, from `claude agents --json`.
//
//   othersInFolder(folder, ownSessionId, run) -> [{name, sessionId, kind}]
//
// A folder switch changes the plugins of every session there at its next reload, so the switch's
// confirmation names them. It never fails a switch: a claude without `agents`, a timeout or output
// it cannot read gives [].
import { spawnSync } from "node:child_process";
import { realPath } from "./record.mjs";

const listAgents = () =>
  spawnSync("claude", ["agents", "--json"], { encoding: "utf8", shell: process.platform === "win32", timeout: 10_000, maxBuffer: 16 * 1024 * 1024 });

export function othersInFolder(folder, ownSessionId, run = listAgents) {
  const result = run();
  if (result.error || result.status !== 0) return [];
  let agents;
  try {
    agents = JSON.parse(result.stdout);
  } catch {
    return [];
  }
  if (!Array.isArray(agents)) return [];
  const here = realPath(folder);
  return agents
    .filter((a) => a && typeof a.cwd === "string" && a.sessionId !== ownSessionId && realPath(a.cwd) === here)
    .map((a) => ({ name: a.name || a.sessionId, sessionId: a.sessionId, kind: a.kind ?? null }));
}
