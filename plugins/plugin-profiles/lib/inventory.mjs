// The installed plugins and what each one ships. The one module that runs `claude plugin` or
// reads Claude Code's plugin registry.
//
//   recordsFromCli([run])               -> install records from `claude plugin list --json`
//   recordsFromDisk(configDir, [read])  -> the same records from plugins/installed_plugins.json,
//   inventory({projectDir, records})    -> Map<id, {id, version, installPath, dependsOn, ships, skills}>
//   knownMarketplaces([run])            -> Set of the marketplace names this machine has added
//   marketplaceLocation(configDir, name) -> the folder plugins/known_marketplaces.json gives that
//                                          marketplace's clone, or throws InventoryError
//   installPlugin(id, [run])            -> installs one plugin at user scope, or throws InventoryError
//
// A project or local install counts only in its own project. dependsOn holds the plugin.json
// dependencies as name@marketplace, a bare name meaning the plugin's own marketplace. ships says
// whether hooks/hooks.json registers hooks or a mod, and whether the plugin carries an MCP or a
// language server. skills names each skills/<name>/SKILL.md the plugin carries.
//
// installPlugin never passes --marketplace, which would add a marketplace, nor --yes, which would
// accept a command a marketplace declares: a plugin that needs either is left for a person to
// install by hand.
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { claudeCommand } from "./claude-command.mjs";

export class InventoryError extends Error {}

const SCOPE_RANK = { local: 3, project: 2 };

function claude(args) {
  const what = `claude ${args.slice(0, 2).join(" ")}`;
  const { file, refusal } = claudeCommand();
  if (refusal) return new Error(`${what} could not start (${refusal})`);
  const result = spawnSync(file, args, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (result.error) return new Error(`${what} could not start (${result.error.code ?? result.error.message})`);
  if (result.status !== 0) return new Error(`${what} exited ${result.status}: ${`${result.stderr}${result.stdout}`.trim()}`);
  return result.stdout;
}

const runClaude = () => claude(["plugin", "list", "--json"]);

function parseJson(text, what) {
  if (text instanceof Error) throw new InventoryError(text.message);
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new InventoryError(`${what} is not valid JSON (${error.message})`);
  }
}

export function recordsFromCli(run = runClaude) {
  const records = parseJson(run(), "claude plugin list --json");
  if (!Array.isArray(records)) throw new InventoryError("claude plugin list --json did not return a list");
  return records;
}

export function knownMarketplaces(run = () => claude(["plugin", "marketplace", "list", "--json"])) {
  const list = parseJson(run(), "claude plugin marketplace list --json");
  if (!Array.isArray(list)) throw new InventoryError("claude plugin marketplace list --json did not return a list");
  return new Set(list.map((m) => m?.name).filter((name) => typeof name === "string"));
}

export function marketplaceLocation(configDir, name) {
  const path = join(configDir, "plugins", "known_marketplaces.json");
  const location = readJson(path)?.[name]?.installLocation;
  if (typeof location !== "string" || !location) throw new InventoryError(`${path} gives no installLocation for the ${name} marketplace`);
  return location;
}

export function installPlugin(id, run = (args) => claude(args)) {
  const out = run(["plugin", "install", id, "--scope", "user"]);
  if (out instanceof Error) throw new InventoryError(out.message);
}

export function recordsFromDisk(configDir, read = (path) => readFileSync(path, "utf8")) {
  const path = join(configDir, "plugins", "installed_plugins.json");
  let text;
  try {
    text = read(path);
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw new InventoryError(`${path} cannot be read (${error.code ?? error.message})`);
  }
  const plugins = parseJson(text, path)?.plugins ?? {};
  return Object.entries(plugins).flatMap(([id, list]) => (Array.isArray(list) ? list : [list]).map((r) => ({ ...r, id })));
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

const nonEmpty = (value) => (Array.isArray(value) ? value.length > 0 : value != null && typeof value === "object" ? Object.keys(value).length > 0 : Boolean(value));

function skillsIn(root) {
  try {
    return readdirSync(join(root, "skills"), { withFileTypes: true })
      .filter((e) => e.isDirectory() && existsSync(join(root, "skills", e.name, "SKILL.md")))
      .map((e) => e.name)
      .sort();
  } catch {
    return [];
  }
}

function describe(id, record) {
  const root = record.installPath ?? "";
  const manifest = readJson(join(root, ".claude-plugin", "plugin.json")) ?? {};
  const hooks = readJson(join(root, "hooks", "hooks.json")) ?? {};
  const marketplace = id.slice(id.lastIndexOf("@") + 1);
  const dependsOn = (Array.isArray(manifest.dependencies) ? manifest.dependencies : [])
    .map((dep) => (typeof dep === "string" ? dep : dep?.name))
    .filter((dep) => typeof dep === "string" && dep)
    .map((dep) => (dep.includes("@") ? dep : `${dep}@${marketplace}`));
  return {
    id,
    version: record.version ?? null,
    installPath: record.installPath ?? null,
    dependsOn,
    ships: {
      hooks: nonEmpty(hooks.hooks),
      mod: nonEmpty(hooks.modules),
      mcp: nonEmpty(manifest.mcpServers) || existsSync(join(root, ".mcp.json")),
      lsp: nonEmpty(manifest.lspServers) || existsSync(join(root, ".lsp.json")),
    },
    skills: root ? skillsIn(root) : [],
  };
}

export function inventory({ projectDir, records }) {
  const here = resolve(projectDir);
  const best = new Map();
  for (const r of records) {
    if (typeof r?.id !== "string" || !r.id.includes("@")) continue;
    const rank = SCOPE_RANK[r.scope] ?? 1;
    if (rank > 1 && (r.projectPath == null || resolve(r.projectPath) !== here)) continue;
    if ((best.get(r.id)?.rank ?? 0) < rank) best.set(r.id, { rank, record: r });
  }
  return new Map([...best].map(([id, { record }]) => [id, describe(id, record)]));
}
