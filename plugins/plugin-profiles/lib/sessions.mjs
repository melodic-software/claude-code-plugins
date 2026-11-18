// The other live Claude Code sessions working in one folder, from `claude agents --json`.
//
//   othersInFolder(folder, ownSessionId, run) -> [{name, sessionId, kind}]
//
// A folder switch changes the plugins of every session there at its next reload, so the switch's
// confirmation names them. It never fails a switch: a claude without `agents`, a timeout or output
// it cannot read gives [].
import { spawnSync } from "node:child_process";
import { claudeCommand } from "./claude-command.mjs";
import { folderLevel } from "./folder-file.mjs";
import { realPath } from "./record.mjs";

function listAgents() {
  const { file, refusal } = claudeCommand();
  if (refusal) return { error: new Error(refusal) };
  return spawnSync(file, ["agents", "--json"], { encoding: "utf8", timeout: 10_000, maxBuffer: 16 * 1024 * 1024 });
}

/** Other sessions whose folder resolves to the same settings file: in a git repository, those in every worktree and subdirectory. */
export function othersInFolder(folder, ownSessionId, run = listAgents, levelOptions = {}) {
  const result = run();
  if (result.error || result.status !== 0) return [];
  let agents;
  try {
    agents = JSON.parse(result.stdout);
  } catch {
    return [];
  }
  if (!Array.isArray(agents)) return [];
  const fileOf = (dir) => realPath(folderLevel(dir, levelOptions).file);
  const here = fileOf(folder);
  return agents
    .filter((a) => a && typeof a.cwd === "string" && a.sessionId !== ownSessionId && fileOf(a.cwd) === here)
    .map((a) => ({ name: a.name || a.sessionId, sessionId: a.sessionId, kind: a.kind ?? null }));
}
