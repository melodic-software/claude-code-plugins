import { spawnSync } from "node:child_process";
import { claudeCommand } from "./claude-command.mjs";
import { folderLevel } from "./folder-file.mjs";
import { realPath } from "./record.mjs";

function listAgents(env = process.env) {
  const { file, refusal } = claudeCommand(env);
  if (refusal) return { error: new Error(refusal) };
  return spawnSync(file, ["agents", "--json"], { env, encoding: "utf8", timeout: 10_000, maxBuffer: 16 * 1024 * 1024 });
}

function agentsOf(run) {
  const result = run();
  if (result.error || result.status !== 0) return [];
  try {
    const agents = JSON.parse(result.stdout);
    return Array.isArray(agents) ? agents : [];
  } catch {
    return [];
  }
}

export const liveFolders = (env, run = () => listAgents(env)) =>
  agentsOf(run).filter((a) => a && typeof a.cwd === "string").map((a) => a.cwd);

/** Other sessions whose folder resolves to the same settings file: in a git repository, those in every worktree and subdirectory. */
export function othersInFolder(folder, ownSessionId, run = listAgents, levelOptions = {}) {
  const agents = agentsOf(run);
  const fileOf = (dir) => realPath(folderLevel(dir, levelOptions).file);
  const here = fileOf(folder);
  return agents
    .filter((a) => a && typeof a.cwd === "string" && a.sessionId !== ownSessionId && fileOf(a.cwd) === here)
    .map((a) => ({ name: a.name || a.sessionId, sessionId: a.sessionId, kind: a.kind ?? null }));
}
