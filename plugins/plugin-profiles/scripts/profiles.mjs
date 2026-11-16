#!/usr/bin/env node
// Apply a plugin profile to a folder, to user settings, or to one session.
//
//   profiles.mjs apply <name> --for session|folder|initial [--dry-run] [--yes] [--defer-off]
//   profiles.mjs status [--for folder|initial] [--json] [--session-start]
//   profiles.mjs clear [--for folder|initial]
//   profiles.mjs inventory [--json]
//
// apply    Prints what the profile changes, then writes it on --yes or a yes typed at the prompt;
//          with nobody to ask and no --yes it writes nothing. --dry-run prints and stops. A plugin
//          it would switch on whose required prerequisites are missing stops the write unless a
//          person types yes to the stated consequence; --yes alone never covers that. --for folder
//          writes .claude/settings.local.json, initial writes user settings.json, session writes a
//          file for `claude --settings` and changes no settings file. --defer-off writes the
//          entries that switch plugins on and records the ones that switch plugins off as
//          pending, for an in-session switch; the next apply writes them.
// status   The profile recorded for the folder (or user settings), each entry that differs from
//          it, plugins installed since, and a switch still pending. --session-start reads the
//          installed plugins from disk, never from a nested claude, and prints a SessionStart
//          systemMessage only when there is something to say.
// clear    Puts every entry the tool wrote back to its value before the first apply and removes
//          a settings file the tool created.
// inventory  The installed plugins, their dependencies and what each ships.
//
// Exit 0: done, previewed, or nothing to change. Exit 1: not applied (no consent, a missing
// required prerequisite, settings changed by another writer). Exit 2: usage, profile or settings
// file error. A missing plugin is named with its install command; this tool installs nothing.
import { realpathSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import process from "node:process";
import { createInterface } from "node:readline/promises";
import { fileURLToPath } from "node:url";
import { InventoryError, inventory, recordsFromCli, recordsFromDisk } from "../lib/inventory.mjs";
import { PlanError, TARGET_LEVEL, plan } from "../lib/plan.mjs";
import { managedSettingsFiles, resolveInstall } from "../lib/plugin-options.mjs";
import { missingRequired } from "../lib/prerequisite-gate.mjs";
import { ProfileError, profileLevels, readCatalog } from "../lib/profile-files.mjs";
import { ABSENT, baseline, deleteRecord, nextRecord, readRecord, recordPath, restoreEdits, saveRecord } from "../lib/record.mjs";
import {
  SettingsConflict,
  SettingsError,
  deleteSettings,
  editText,
  readLayers,
  readSettings,
  settingsPaths,
  writeSettings,
} from "../lib/settings-io.mjs";

const OWN_ROOT = dirname(dirname(realpathSync(fileURLToPath(import.meta.url))));
const SESSION_VAR = "PLUGIN_PROFILES_SESSION";
const USAGE = `usage: profiles.mjs apply <name> --for session|folder|initial [--dry-run] [--yes] [--defer-off]
       profiles.mjs status [--for folder|initial] [--json] [--session-start]
       profiles.mjs clear [--for folder|initial]
       profiles.mjs inventory [--json]`;

class UsageError extends Error {}
class NotApplied extends Error {}

const dataDirName = (id) => id.replace(/[^A-Za-z0-9_-]/g, "-");

/** Where this run reads and writes: the config folder and data folder come from this script's own install path. */
function locate(env, cwd) {
  const install = resolveInstall(OWN_ROOT);
  const configDir = install.userSettings
    ? dirname(install.userSettings)
    : env.CLAUDE_CONFIG_DIR || join(env.HOME || env.USERPROFILE || homedir(), ".claude");
  const dataDir = install.pluginId
    ? join(configDir, "plugins", "data", dataDirName(install.pluginId))
    : env.CLAUDE_PLUGIN_DATA || join(configDir, "plugins", "data", "plugin-profiles-inline");
  const projectDir = env.CLAUDE_PROJECT_DIR || cwd;
  const pluginVersion = JSON.parse(readFileSync(join(OWN_ROOT, ".claude-plugin", "plugin.json"), "utf8")).version;
  return { configDir, dataDir, projectDir, pluginVersion, paths: settingsPaths({ configDir, projectDir }) };
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  if (!["apply", "status", "clear", "inventory"].includes(command)) throw new UsageError(command ? `unknown command ${command}` : "no command given");
  const opts = { command, name: null, target: command === "apply" ? null : "folder", dryRun: false, yes: false, deferOff: false, json: false, sessionStart: false };
  const flags = { apply: ["--dry-run", "--yes", "--defer-off"], status: ["--json", "--session-start"], clear: [], inventory: ["--json"] }[command];
  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i];
    if (arg === "--for" && command !== "inventory") opts.target = rest[++i];
    else if (flags.includes(arg)) opts[arg.slice(2).replace(/-(.)/g, (_, c) => c.toUpperCase())] = true;
    else if (command === "apply" && !arg.startsWith("--") && !opts.name) opts.name = arg;
    else throw new UsageError(`unexpected argument ${arg}`);
  }
  if (command === "apply" && !opts.name) throw new UsageError("apply needs a profile name");
  const targets = command === "apply" ? Object.keys(TARGET_LEVEL) : ["folder", "initial"];
  if (command !== "inventory" && !targets.includes(opts.target)) throw new UsageError(`--for takes ${targets.join(", ")}`);
  if (opts.deferOff && opts.target === "session") throw new UsageError("--defer-off applies to a folder or user settings, not a one-session file");
  return opts;
}

const targetFile = (where, target, name) =>
  target === "folder" ? where.paths.local : target === "initial" ? where.paths.user : join(where.dataDir, "sessions", `${name}.json`);

function diff(now, final) {
  const out = {};
  for (const key of new Set([...Object.keys(now), ...Object.keys(final)])) if (now[key] !== final[key]) out[key] = final[key] ?? null;
  return out;
}

/** Reads every input, plans, and works out the exact entries the target file ends with. */
function prepare(opts, where, catalog, records) {
  const file = targetFile(where, opts.target, opts.name);
  const settings = readSettings(file);
  const session = opts.target === "session";
  const recPath = session ? null : recordPath(where.dataDir, file);
  const previous = session ? null : readRecord(recPath);
  const base = session ? { enabledPlugins: {}, skillOverrides: {} } : baseline(settings.doc, previous);
  const layers = readLayers({ paths: where.paths, managedFiles: managedSettingsFiles() });
  layers[TARGET_LEVEL[opts.target]] = base;
  const inv = inventory({ projectDir: where.projectDir, records: records() });
  const result = plan({ catalog, profile: opts.name, inventory: inv, layers, target: opts.target });
  const now = session ? {} : (settings.doc.enabledPlugins ?? {});
  const final = { enabledPlugins: { ...base.enabledPlugins, ...result.writes }, skillOverrides: { ...base.skillOverrides, ...result.skillWrites } };
  const pending = {};
  if (opts.deferOff) {
    for (const [id, value] of Object.entries(now)) {
      if (value === true && final.enabledPlugins[id] !== true) {
        pending[id] = final.enabledPlugins[id] ?? ABSENT;
        final.enabledPlugins[id] = true;
      }
    }
  }
  const edits = { enabledPlugins: diff(now, final.enabledPlugins), skillOverrides: diff(session ? {} : (settings.doc.skillOverrides ?? {}), final.skillOverrides) };
  if (session) edits.env = { [SESSION_VAR]: opts.name };
  return { file, settings, recPath, previous, inv, plan: result, final, pending, edits };
}

const changeCount = (p) => Object.keys(p.edits.enabledPlugins).length + Object.keys(p.edits.skillOverrides).length;
const sameChange = (a, b) => JSON.stringify([a.final, a.pending, a.edits]) === JSON.stringify([b.final, b.pending, b.edits]);
const list = (ids) => (ids.length ? ids.join(", ") : "none");

function preview(p, gate, out) {
  const r = p.plan;
  out(`Profile ${r.profile} for ${r.target}: ${p.file}`);
  out(`Switches on (${r.enabled.length}): ${list(r.enabled)}`);
  out(`Switches off (${r.disabled.length}): ${list(r.disabled)}`);
  if (Object.keys(p.pending).length) out(`Left on until the next apply (${Object.keys(p.pending).length}): ${list(Object.keys(p.pending))}`);
  out(`Writes ${Object.keys(p.edits.enabledPlugins).length} plugin entries and ${Object.keys(p.edits.skillOverrides).length} skill entries.`);
  if (r.hookPluginsOff.length) out(`Switches off plugins that ship hooks or a mod: ${list(r.hookPluginsOff)}`);
  if (r.mcpOrLspOn.length) out(`Switches on plugins with an MCP or language server: ${list(r.mcpOrLspOn)}`);
  for (const pin of r.pinned) out(`Pinned by ${pin.by} settings (${pin.value}), left alone: ${pin.id}`);
  for (const m of r.missing) out(`Not installed${m.optional ? " (optional)" : ""}: ${m.id}. Install it with: ${m.install}`);
  out(`Left alone, from marketplaces this profile does not name (${r.untouched.length}): ${list(r.untouched)}`);
  for (const g of gate) {
    const tool = g.tool ? `${g.tool}: ${g.detail}.` : `${g.detail}.`;
    out(`Missing required prerequisite of ${g.plugin}: ${tool}${g.degrade ? ` ${g.degrade}` : ""}${g.install.length ? ` Install (${g.install.join("; ")}).` : ""}`);
  }
}

async function ask(question) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    return (await rl.question(question)).trim().toLowerCase();
  } finally {
    rl.close();
  }
}

async function consent(opts, gate, interactive) {
  if (gate.length) {
    if (!interactive) throw new NotApplied("not applied: a plugin it switches on is missing a required prerequisite, and --yes does not accept that; run it in a terminal to decide, or install the tools first");
    if ((await ask("Apply anyway, with the consequences above? Type yes to apply: ")) !== "yes") throw new NotApplied("not applied");
    return;
  }
  if (opts.yes) return;
  if (!interactive) throw new NotApplied("not applied: nobody to confirm; pass --yes to apply without a prompt");
  if (!["y", "yes"].includes(await ask("Apply these changes? [y/N] "))) throw new NotApplied("not applied");
}

function commit(p, opts, where) {
  const text = editText(p.settings, p.edits);
  if (opts.target === "session") return writeSettings(p.file, p.settings.hash, text);
  const record = nextRecord(p.previous, {
    profile: opts.name,
    target: opts.target,
    settingsFile: p.file,
    appliedAt: new Date().toISOString(),
    pluginVersion: where.pluginVersion,
    doc: p.settings.doc,
    exists: p.settings.exists,
    final: p.final,
    phase: Object.keys(p.pending).length ? "off-pending" : "applied",
    pending: p.pending,
    installed: [...p.inv.keys()],
  });
  saveRecord(p.recPath, record);
  try {
    if (changeCount(p)) writeSettings(p.file, p.settings.hash, text);
  } catch (error) {
    if (p.previous) saveRecord(p.recPath, p.previous);
    else deleteRecord(p.recPath);
    throw error;
  }
}

async function apply(opts, where, env, io) {
  if (env.CLAUDE_CODE_REMOTE === "true") throw new NotApplied("plugin profiles do not apply here: a cloud session reads no local or user settings");
  const catalog = readCatalog(profileLevels({ pluginRoot: OWN_ROOT, configDir: where.configDir, projectDir: where.projectDir }));
  const records = () => recordsFromCli();
  let p = prepare(opts, where, catalog, records);
  const gate = missingRequired(
    p.plan.enabled.map((id) => p.inv.get(id)),
    { env, platform: process.platform, cwd: where.projectDir, dataDirOf: (id) => join(where.configDir, "plugins", "data", dataDirName(id)) },
  );
  preview(p, gate, io.out);
  const recorded = p.previous?.profile === opts.name && p.previous.phase === "applied";
  if (!changeCount(p) && opts.target !== "session" && recorded) {
    io.out("Nothing to change: the settings already match this profile.");
    return 0;
  }
  if (opts.dryRun) return 0;
  await consent(opts, gate, Boolean(process.stdin.isTTY && process.stdout.isTTY));
  try {
    commit(p, opts, where);
  } catch (error) {
    if (!(error instanceof SettingsConflict)) throw error;
    const again = prepare(opts, where, catalog, records);
    if (!sameChange(p, again)) throw new NotApplied(`not applied: ${p.file} changed while applying and the change alters the plan; run apply again to see the new preview`);
    p = again;
    try {
      commit(p, opts, where);
    } catch (second) {
      if (second instanceof SettingsConflict) throw new NotApplied(`not applied: ${p.file} kept changing while applying; it is left as the other writer left it`);
      throw second;
    }
  }
  io.out(`Applied ${opts.name} to ${p.file}.`);
  if (opts.target === "session") io.out(`Start the session with: claude --settings "${p.file}"`);
  return 0;
}

function statusOf(opts, where, records) {
  const file = targetFile(where, opts.target);
  const rec = readRecord(recordPath(where.dataDir, file));
  if (!rec) return { profile: null, target: opts.target, settingsFile: file };
  const doc = readSettings(file).doc;
  const differs = [];
  for (const [key, section] of [["enabledPlugins", "entries"], ["skillOverrides", "skillOverrides"]]) {
    for (const [name, { after }] of Object.entries(rec[section])) {
      const current = doc[key]?.[name] ?? ABSENT;
      if (current !== after && rec.pending?.[name] === undefined) differs.push({ name, recorded: after, current });
    }
  }
  const installedSince = [...inventory({ projectDir: where.projectDir, records: records() }).keys()].filter((id) => !rec.installed.includes(id));
  return {
    profile: rec.profile,
    target: rec.target,
    settingsFile: file,
    phase: rec.phase,
    appliedAt: rec.appliedAt,
    differs,
    installedSince,
    pending: Object.keys(rec.pending ?? {}),
  };
}

function statusLines(s) {
  if (!s.profile) return [`No profile is recorded for ${s.settingsFile}.`];
  const lines = [`Profile ${s.profile} (${s.target}) applied ${s.appliedAt} to ${s.settingsFile}.`];
  if (s.pending.length) lines.push(`A switch is unfinished; these stay on until apply ${s.profile} --for ${s.target} runs again: ${list(s.pending)}`);
  for (const d of s.differs) lines.push(`Differs from the profile: ${d.name} is ${d.current}, the profile wrote ${d.recorded}`);
  if (s.installedSince.length) lines.push(`Installed since the profile was applied: ${list(s.installedSince)}`);
  return lines;
}

function status(opts, where, io) {
  if (opts.sessionStart) {
    try {
      const s = statusOf(opts, where, () => recordsFromDisk(where.configDir));
      if (s.profile && (s.pending.length || s.differs.length || s.installedSince.length)) {
        io.out(JSON.stringify({ systemMessage: `plugin-profiles: ${statusLines(s).join(" ")}` }));
      }
    } catch {
      // A session start never fails on a profile problem; status run by hand reports it.
    }
    return 0;
  }
  const s = statusOf(opts, where, () => recordsFromCli());
  io.out(opts.json ? JSON.stringify(s, null, 2) : statusLines(s).join("\n"));
  return 0;
}

function clear(opts, where, env, io) {
  if (env.CLAUDE_CODE_REMOTE === "true") throw new NotApplied("plugin profiles do not apply here: a cloud session reads no local or user settings");
  const file = targetFile(where, opts.target);
  const recPath = recordPath(where.dataDir, file);
  const rec = readRecord(recPath);
  if (!rec) {
    io.out(`No profile is recorded for ${file}; nothing to clear.`);
    return 0;
  }
  const settings = readSettings(file);
  const { edits, dropEmpty } = restoreEdits(rec);
  const text = editText(settings, edits, { dropEmpty });
  try {
    if (rec.createdFile && Object.keys(JSON.parse(text)).length === 0) deleteSettings(file, settings.hash);
    else writeSettings(file, settings.hash, text);
  } catch (error) {
    if (error instanceof SettingsConflict) throw new NotApplied(`not cleared: ${file} changed while clearing; run clear again`);
    throw error;
  }
  deleteRecord(recPath);
  io.out(`Cleared profile ${rec.profile} from ${file}.`);
  return 0;
}

function listInventory(opts, where, io) {
  const inv = [...inventory({ projectDir: where.projectDir, records: recordsFromCli() }).values()];
  if (opts.json) io.out(JSON.stringify(inv, null, 2));
  else for (const p of inv) {
    const ships = Object.entries(p.ships).filter(([, v]) => v).map(([k]) => k);
    io.out(`${p.id} ${p.version ?? "?"}${ships.length ? ` ships ${ships.join(", ")}` : ""}${p.dependsOn.length ? ` needs ${p.dependsOn.join(", ")}` : ""}`);
  }
  return 0;
}

export async function main(argv, env = process.env, cwd = process.cwd(), io = { out: (s) => console.log(s), err: (s) => console.error(s) }) {
  try {
    const opts = parseArgs(argv);
    const where = locate(env, cwd);
    if (opts.command === "apply") return await apply(opts, where, env, io);
    if (opts.command === "status") return status(opts, where, io);
    if (opts.command === "clear") return clear(opts, where, env, io);
    return listInventory(opts, where, io);
  } catch (error) {
    if (error instanceof NotApplied) {
      io.err(error.message);
      return 1;
    }
    if ([UsageError, PlanError, ProfileError, SettingsError, InventoryError].some((type) => error instanceof type)) {
      io.err(`profiles.mjs: ${error.message}${error instanceof UsageError ? `\n${USAGE}` : ""}`);
      return 2;
    }
    if (typeof error.code === "string") {
      io.err(`profiles.mjs: nothing written for this step: ${error.message}`);
      return 2;
    }
    throw error;
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = await main(process.argv.slice(2));
}
