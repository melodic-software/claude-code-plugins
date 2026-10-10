// Which routing rows are installed and reachable here, under the routing-as-data detection contract
// (docs/conventions/routing-as-data/README.md, Detection). Pure: every input arrives as an argument.
//
//   installed(rows, {pluginRoot, home, projectDir, projectMcpServers, pluginList, mcpList})
//     -> {installed: [row ids], reachable: {id: true | false | null}, reason?, uncertain?}
//      | {installed: null, reason}
//
// pluginList and mcpList are lazy readers returning the text of `claude plugin list --json` and
// `claude mcp list`, or an Error. The MCP reader runs only after the plugin list parses.
// A bare plugin detect means this plugin's own marketplace: the one in the plugin-list record whose
// installPath is pluginRoot. Without that record, or when its marketplace is inline, skills-dir or
// synced, a bare name matches in any marketplace and `reason` says so; a bare name some row also
// detects qualified is then left out of installed and listed in `uncertain`.
import { existsSync, realpathSync, statSync } from "node:fs";
import { join, resolve } from "node:path";

// Marketplace names that do not identify a marketplace a sibling plugin could come from.
const NO_MARKETPLACE = ["inline", "skills-dir", "synced"];

const isDir = (p) => existsSync(p) && statSync(p).isDirectory();

/** Plugin ids in effect here: a project or local record enabled for this project, or any other scope
 * (user, managed) enabled. A fresh local install reads `enabled: true, projectEnabled: false` with this
 * project as `projectPath`; the CLI may emit `projectPath: null`. */
function enabledPlugins(records, projectDir) {
  const here = resolve(projectDir);
  const forHere = (r) => r.projectEnabled || (r.enabled && r.projectPath != null && resolve(r.projectPath) === here);
  return new Set(records.filter((r) => (["project", "local"].includes(r.scope) ? forHere(r) : r.enabled)).map((r) => r.id));
}

/** The marketplace of the record installed at pluginRoot, or null. Each record resolves in its own
 * try, so a missing or unreadable installPath skips only that record. */
function ownMarketplace(records, pluginRoot) {
  const real = (p) => (process.platform === "win32" ? realpathSync.native(p).toLowerCase() : realpathSync.native(p));
  const root = real(pluginRoot);
  for (const r of records) {
    try {
      if (r.installPath && real(r.installPath) === root) return r.id.slice(r.id.lastIndexOf("@") + 1);
    } catch {
      // skip this record
    }
  }
  return null;
}

/** Server name to connected (true or false) from `claude mcp list` lines shaped `name: target - status`. */
function mcpStatus(text) {
  const status = new Map();
  for (const line of text.split("\n")) {
    const m = line.match(/^(.+?): .* - (.*)$/);
    if (m) status.set(m[1], /Connected$/.test(m[2]) && !/Not connected$/i.test(m[2]));
  }
  return status;
}

export function installed(rows, { pluginRoot, home, projectDir, projectMcpServers, pluginList, mcpList }) {
  const pluginText = pluginList();
  if (pluginText instanceof Error) return { installed: null, reason: pluginText.message };
  let plugins, own;
  try {
    const records = JSON.parse(pluginText);
    plugins = enabledPlugins(records, projectDir);
    own = ownMarketplace(records, pluginRoot);
  } catch (e) {
    return { installed: null, reason: `unreadable plugin list: ${e.message}` };
  }
  const mcpText = mcpList();
  if (mcpText instanceof Error) return { installed: null, reason: mcpText.message };
  const listed = mcpStatus(mcpText);
  const servers = [...listed.keys(), ...projectMcpServers];
  const server = (row) => servers.find((s) => s === row.detect || s.endsWith(`:${row.detect}`));
  const skillDirs = [join(home, ".claude/skills"), join(projectDir, ".claude/skills")];
  const resolved = own && !NO_MARKETPLACE.includes(own);
  const names = new Set([...plugins].filter((id) => typeof id === "string").map((id) => id.slice(0, id.lastIndexOf("@"))));
  const qualified = new Map(rows.filter((r) => r.detect.includes("@")).map((r) => [r.detect.slice(0, r.detect.lastIndexOf("@")), r.detect]));
  const uncertain = {};
  const barePlugin = (row) => row.kind === "plugin" || (row.kind === "skill" && /^\/[^:]+:/.test(row.id));
  const byName = (row) => {
    if (!names.has(row.detect)) return false;
    if (!qualified.has(row.detect)) return true;
    uncertain[row.id] = `${row.detect} also used by ${qualified.get(row.detect)}`;
    return false;
  };

  const present = (row) => {
    if (row.detect.includes("@")) return plugins.has(row.detect);
    if (barePlugin(row)) return resolved ? plugins.has(`${row.detect}@${own}`) : byName(row);
    if (row.kind === "mcp") return server(row) !== undefined;
    if (row.kind === "skill") return skillDirs.some((d) => isDir(join(d, row.detect)));
    return false; // kind tool: only the session's own tool listing can tell
  };
  // true or false when this module can tell; null when only an account, a key or the session can.
  const reach = (row) => {
    if (row.kind === "mcp") return listed.get(server(row)) ?? null;
    return row.account === "none" ? true : null;
  };
  const found = rows.filter(present);
  return {
    installed: [...new Set(found.map((r) => r.id))],
    reachable: Object.fromEntries(found.map((r) => [r.id, reach(r)])),
    ...(!resolved && { reason: `own marketplace unresolved (${own ?? "no record at this plugin's path"}); matched by name` }),
    ...(Object.keys(uncertain).length && { uncertain }),
  };
}
