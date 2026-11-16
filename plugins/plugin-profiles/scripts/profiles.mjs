#!/usr/bin/env node
// Apply a plugin profile to a folder, to user settings, or to one session.
//
//   profiles.mjs apply <name> --for session|folder|initial [--dry-run [--json]] [--yes] [--defer-off]
//   profiles.mjs status [--for folder|initial] [--json] [--session-start]
//   profiles.mjs clear [--for folder|initial] [--dry-run] [--yes]
//   profiles.mjs list [--json]
//   profiles.mjs inventory [--json]
//   profiles.mjs usage [--json]
//   profiles.mjs install <name@marketplace> [--dry-run] [--yes]
//   profiles.mjs save <name> --level user|repository [--description <text>] [--plugins <ids>]
//                [--optional <ids>] [--remove <ids>] [--exclude <ids>] [--hide-skills <names>] [--dry-run] [--yes]
//   profiles.mjs check [--catalog <marketplace.json>] [--shipped <dir>]
//
// apply    Prints what the profile changes, then writes it on --yes or a yes typed at the prompt;
//          with nobody to ask and no --yes it writes nothing. --dry-run prints and stops; with
//          --json it prints the preview lines and what a caller branches on as one object. A plugin
//          it would switch on whose required prerequisites are missing stops the write unless a
//          person types yes to the stated consequence; --yes alone never covers that. --for folder
//          writes .claude/settings.local.json, initial writes user settings.json, session writes a
//          file for `claude --settings` and changes no settings file. --defer-off writes the
//          entries that switch plugins on and records the ones that switch plugins off as
//          pending, for an in-session switch; the next apply writes them. A target the surface
//          does not support (lib/surface.mjs) is refused, and so is --for folder when the
//          remember_folder_profile option is false, and --defer-off in a session that
//          PLUGIN_PROFILES_SESSION names.
// status   The profile recorded for the folder (or user settings), each entry that differs from
//          it, plugins installed since, a switch still pending, a one-session profile named by
//          PLUGIN_PROFILES_SESSION and the surface. With remember_folder_profile false it reports
//          the initial profile and names a folder record as not in force. --session-start reads
//          the installed plugins from disk, never from a nested claude, and prints a SessionStart
//          systemMessage only where a profile was applied.
// clear    Puts every entry the tool wrote back to its value before the first apply and removes
//          a settings file the tool created. Like apply it prints what it changes first and writes
//          on --yes or a yes typed at the prompt; --dry-run prints and stops.
// list     The profiles a folder apply can name, each with its description line.
// inventory  The installed plugins, their dependencies, what each ships and its skills.
// usage    How often each skill and plugin was used on this machine (lib/usage.mjs), most used
//          first, or that no usage history was found.
// install  Installs one missing plugin at user scope, only from a marketplace this machine already
//          knows and never for a plugin only a repository profile names. It prints what it does
//          first and installs on --yes or a yes typed at the prompt; with neither it installs
//          nothing. Afterwards it switches the plugin off in user settings unless the initial
//          profile (always-on plus the profile applied --for initial) includes it. It never
//          updates or uninstalls.
// save     Writes a profile file at the user or repository level: the lists given are added to
//          the file's own lists, --description replaces its description. It prints the whole file
//          first and writes on --yes or a yes typed at the prompt; ids are comma-separated.
// check    Checks the profile files at every level (lib/check.mjs says what fails and what is
//          only reported). --catalog defaults to the marketplace.json of the marketplace this
//          plugin was installed from (plugins/known_marketplaces.json), or of the repository a
//          checkout sits in; --shipped to this plugin's profiles/. Reads installed plugins from disk.
//
// Exit 0: done, previewed, nothing to change, or the check passed. Exit 1: not applied (no
// consent, a missing required prerequisite, settings changed by another writer) or the check
// failed. Exit 2: usage, profile or settings
// file error. apply names a missing plugin with its install command and installs nothing.
import { realpathSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import process from "node:process";
import { createInterface } from "node:readline/promises";
import { fileURLToPath } from "node:url";
import { CheckError, checkProfiles, readMarketplace } from "../lib/check.mjs";
import { InventoryError, installPlugin, inventory, knownMarketplaces, marketplaceLocation, recordsFromCli, recordsFromDisk } from "../lib/inventory.mjs";
import { PlanError, TARGET_LEVEL, effective, excludedAlwaysOn, plan } from "../lib/plan.mjs";
import { OptionsError, managedSettingsFiles, readOperatorOptions, resolveInstall } from "../lib/plugin-options.mjs";
import { missingRequired } from "../lib/prerequisite-gate.mjs";
import { replaceFile } from "../lib/atomic-file.mjs";
import { ALWAYS_ON, PLUGIN_ID, ProfileError, parseProfile, profileLevels, profileText, readCatalog, readProfileFiles, resolveCatalog } from "../lib/profile-files.mjs";
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
import { detectSurface, doesNotApply, refusal, surfaceLine } from "../lib/surface.mjs";
import { readUsage, usageFile } from "../lib/usage.mjs";

const OWN_ROOT = dirname(dirname(realpathSync(fileURLToPath(import.meta.url))));
const SESSION_VAR = "PLUGIN_PROFILES_SESSION";
const USAGE = `usage: profiles.mjs apply <name> --for session|folder|initial [--dry-run [--json]] [--yes] [--defer-off]
       profiles.mjs status [--for folder|initial] [--json] [--session-start]
       profiles.mjs clear [--for folder|initial] [--dry-run] [--yes]
       profiles.mjs list [--json]
       profiles.mjs inventory [--json]
       profiles.mjs usage [--json]
       profiles.mjs install <name@marketplace> [--dry-run] [--yes]
       profiles.mjs save <name> --level user|repository [--description <text>] [--plugins <ids>] [--optional <ids>] [--remove <ids>] [--exclude <ids>] [--hide-skills <names>] [--dry-run] [--yes]
       profiles.mjs check [--catalog <marketplace.json>] [--shipped <dir>]`;

class UsageError extends Error {}
class NotApplied extends Error {}

const dataDirName = (id) => id.replace(/[^A-Za-z0-9_-]/g, "-");
const marketplaceOf = (id) => id.slice(id.lastIndexOf("@") + 1);
const PROFILE_NAME = /^[a-z0-9][a-z0-9-]*$/;
const SAVE_LISTS = { plugins: "plugins", optional: "optional", remove: "remove", exclude: "exclude", hideSkills: "hideSkills" };
const NAMED = ["apply", "install", "save"];

const resumeLine = (file) => `A resumed session does not keep --settings: pass --settings "${file}" again with --resume.`;

/** remember_folder_profile from the operator's settings; only an explicit false turns it off. */
function remembersFolder(install) {
  return readOperatorOptions(install, managedSettingsFiles(), ["remember_folder_profile"], { booleans: true }).remember_folder_profile?.value !== "false";
}

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
  return {
    configDir,
    dataDir,
    projectDir,
    pluginVersion,
    paths: settingsPaths({ configDir, projectDir }),
    surface: detectSurface(env),
    remembersFolder: () => remembersFolder(install),
  };
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  if (!["apply", "status", "clear", "list", "inventory", "usage", "install", "save", "check"].includes(command)) throw new UsageError(command ? `unknown command ${command}` : "no command given");
  const opts = { command, name: null, target: command === "apply" ? null : "folder", dryRun: false, yes: false, deferOff: false, json: false, sessionStart: false, catalog: null, shipped: null, level: null, description: null };
  const flags = { apply: ["--dry-run", "--yes", "--defer-off", "--json"], status: ["--json", "--session-start"], clear: ["--dry-run", "--yes"], list: ["--json"], inventory: ["--json"], usage: ["--json"], install: ["--dry-run", "--yes"], save: ["--dry-run", "--yes"], check: [] }[command];
  const values = { check: ["--catalog", "--shipped"], list: [], inventory: [], usage: [], install: [], save: ["--level", "--description", "--plugins", "--optional", "--remove", "--exclude", "--hide-skills"] }[command] ?? ["--for"];
  const camel = (arg) => arg.slice(2).replace(/-(.)/g, (_, c) => c.toUpperCase());
  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i];
    if (values.includes(arg)) {
      if (rest[i + 1] === undefined) throw new UsageError(`${arg} needs a value`);
      opts[arg === "--for" ? "target" : camel(arg)] = rest[++i];
    }
    else if (flags.includes(arg)) opts[camel(arg)] = true;
    else if (NAMED.includes(command) && !arg.startsWith("--") && !opts.name) opts.name = arg;
    else throw new UsageError(`unexpected argument ${arg}`);
  }
  if (NAMED.includes(command) && !opts.name) throw new UsageError(`${command} needs a ${command === "install" ? "plugin as name@marketplace" : "profile name"}`);
  const targets = command === "apply" ? Object.keys(TARGET_LEVEL) : ["folder", "initial"];
  if (["apply", "status", "clear"].includes(command) && !targets.includes(opts.target)) throw new UsageError(`--for takes ${targets.join(", ")}`);
  if (opts.deferOff && opts.target === "session") throw new UsageError("--defer-off applies to a folder or user settings, not a one-session file");
  if (command === "apply" && opts.json && !opts.dryRun) throw new UsageError("apply --json prints a preview and needs --dry-run");
  return opts;
}

const levelsOf = (where) => profileLevels({ pluginRoot: OWN_ROOT, configDir: where.configDir, projectDir: where.projectDir });

/** The profiles an apply at target resolves; the initial profile never takes a repository's files. */
function catalogFor(where, target) {
  const levels = levelsOf(where);
  return readCatalog(target === "initial" ? levels.filter((l) => l.level !== "repository") : levels);
}

const sessionFile = (where, name) => join(where.dataDir, "sessions", `${name}.json`);
const targetFile = (where, target, name) => (target === "folder" ? where.paths.local : target === "initial" ? where.paths.user : sessionFile(where, name));

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
  const loaded = readLayers({ paths: where.paths, managedFiles: managedSettingsFiles() });
  const layers = { ...loaded, [TARGET_LEVEL[opts.target]]: base };
  const inv = inventory({ projectDir: where.projectDir, records: records() });
  const result = plan({ catalog, profile: opts.name, inventory: inv, layers, target: opts.target });
  const now = session ? {} : (settings.doc.enabledPlugins ?? {});
  const final = { enabledPlugins: { ...base.enabledPlugins, ...result.writes }, skillOverrides: { ...base.skillOverrides, ...result.skillWrites } };
  const pending = {};
  if (opts.deferOff) {
    for (const id of new Set([...Object.keys(now), ...Object.keys(final.enabledPlugins)])) {
      if (effective(loaded, id) === true && final.enabledPlugins[id] !== true) {
        pending[id] = final.enabledPlugins[id] ?? ABSENT;
        if (id in now) final.enabledPlugins[id] = now[id];
        else delete final.enabledPlugins[id];
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

/** The lines that say what an apply changes; the terminal prompt and the mod's preview both show them. */
function previewLines(p, gate) {
  const r = p.plan;
  const lines = [
    `Profile ${r.profile} for ${r.target}: ${p.file}`,
    `Switches on (${r.enabled.length}): ${list(r.enabled)}`,
    `Switches off (${r.disabled.length}): ${list(r.disabled)}`,
  ];
  if (Object.keys(p.pending).length) lines.push(`Left on until the next apply (${Object.keys(p.pending).length}): ${list(Object.keys(p.pending))}`);
  lines.push(`Writes ${Object.keys(p.edits.enabledPlugins).length} plugin entries and ${Object.keys(p.edits.skillOverrides).length} skill entries.`);
  if (r.hookPluginsOff.length) lines.push(`Switches off plugins that ship hooks or a mod: ${list(r.hookPluginsOff)}`);
  if (r.mcpOrLspOn.length) lines.push(`Switches on plugins with an MCP or language server: ${list(r.mcpOrLspOn)}`);
  for (const pin of r.pinned) lines.push(`Pinned by ${pin.by} settings (${pin.value}), left alone: ${pin.id}`);
  for (const m of r.missing) lines.push(`Not installed${m.optional ? " (optional)" : ""}: ${m.id}. Install it with: ${m.install}`);
  lines.push(`Left alone, from marketplaces this profile does not name (${r.untouched.length}): ${list(r.untouched)}`);
  for (const g of gate) {
    const tool = g.tool ? `${g.tool}: ${g.detail}.` : `${g.detail}.`;
    lines.push(`Missing required prerequisite of ${g.plugin}: ${tool}${g.degrade ? ` ${g.degrade}` : ""}${g.install.length ? ` Install (${g.install.join("; ")}).` : ""}`);
  }
  return lines;
}

/** What apply --dry-run --json prints: the preview lines and the facts a caller branches on. */
const previewJson = (p, gate, upToDate) => ({
  profile: p.plan.profile,
  target: p.plan.target,
  file: p.file,
  upToDate,
  enabled: p.plan.enabled,
  disabled: p.plan.disabled,
  pending: Object.keys(p.pending),
  mcpOrLspOn: p.plan.mcpOrLspOn,
  hookPluginsOff: p.plan.hookPluginsOff,
  prerequisitesMissing: gate.map((g) => g.plugin),
  lines: previewLines(p, gate),
});

async function ask(question) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    return (await rl.question(question)).trim().toLowerCase();
  } finally {
    rl.close();
  }
}

const interactive = () => Boolean(process.stdin.isTTY && process.stdout.isTTY);

async function consent(opts, gate, interactive, question = "Apply these changes? [y/N] ") {
  if (gate.length) {
    if (!interactive) throw new NotApplied("not applied: a plugin it switches on is missing a required prerequisite, and --yes does not accept that; run it in a terminal to decide, or install the tools first");
    if ((await ask("Apply anyway, with the consequences above? Type yes to apply: ")) !== "yes") throw new NotApplied("not applied");
    return;
  }
  if (opts.yes) return;
  if (!interactive) throw new NotApplied("not applied: nobody to confirm; pass --yes to apply without a prompt");
  if (!["y", "yes"].includes(await ask(question))) throw new NotApplied("not applied");
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
  const refused = refusal(where.surface, opts.target, opts.name);
  if (refused) throw new NotApplied(`not applied: ${refused}`);
  if (opts.target === "folder" && !where.remembersFolder()) {
    throw new NotApplied(`not applied: folder remembering is off (remember_folder_profile), so every session starts from the initial profile; start one session in ${opts.name} with apply ${opts.name} --for session, or set the initial profile with apply ${opts.name} --for initial`);
  }
  if (opts.deferOff && env[SESSION_VAR]) {
    throw new NotApplied(`not applied: this session runs in profile ${env[SESSION_VAR]} from a one-session settings file, so a switch here would not hold; start a session in ${opts.name} with apply ${opts.name} --for session, then the claude --settings command it prints`);
  }
  const catalog = catalogFor(where, opts.target);
  const records = () => recordsFromCli();
  let p = prepare(opts, where, catalog, records);
  const gate = missingRequired(
    p.plan.enabled.map((id) => p.inv.get(id)),
    { env, platform: process.platform, cwd: where.projectDir, dataDirOf: (id) => join(where.configDir, "plugins", "data", dataDirName(id)) },
  );
  const recorded = p.previous?.profile === opts.name && p.previous.phase === "applied";
  const upToDate = !changeCount(p) && opts.target !== "session" && recorded;
  if (opts.json) {
    io.out(JSON.stringify(previewJson(p, gate, upToDate), null, 2));
    return 0;
  }
  for (const line of previewLines(p, gate)) io.out(line);
  if (upToDate) {
    io.out("Nothing to change: the settings already match this profile.");
    return 0;
  }
  if (opts.dryRun) return 0;
  await consent(opts, gate, interactive());
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
  if (opts.target === "session") {
    io.out(`Start the session with: claude --settings "${p.file}"`);
    io.out(resumeLine(p.file));
  }
  return 0;
}

/** The record of one settings file compared with the file now. */
function recordedStatus(target, where, records) {
  const file = targetFile(where, target);
  const rec = readRecord(recordPath(where.dataDir, file));
  if (!rec) return { profile: null, target, settingsFile: file };
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

/**
 * What is in force for this run: a one-session profile named by the session's environment, and the
 * folder's record, or the initial profile's when folder remembering is off (leftover then names a
 * folder record that is not in force).
 */
function statusOf(opts, where, env, records) {
  const base = { surface: where.surface, rememberFolder: true, session: null, leftover: null };
  if (doesNotApply(where.surface)) return { ...base, profile: null, target: opts.target, settingsFile: targetFile(where, opts.target) };
  const name = env[SESSION_VAR];
  if (name) base.session = { profile: name, file: sessionFile(where, name) };
  let target = opts.target;
  if (target === "folder" && !where.remembersFolder()) {
    base.rememberFolder = false;
    base.leftover = readRecord(recordPath(where.dataDir, targetFile(where, "folder")))?.profile ?? null;
    target = "initial";
  }
  return { ...base, ...recordedStatus(target, where, records) };
}

function statusLines(s) {
  if (doesNotApply(s.surface)) return [surfaceLine(s.surface)];
  const lines = [];
  if (s.session) lines.push(`This session runs in profile ${s.session.profile} from a one-session settings file. ${resumeLine(s.session.file)}`);
  if (!s.rememberFolder) {
    lines.push(`Folder remembering is off: sessions start from the initial profile${s.profile ? ` ${s.profile}` : ""}.`);
    if (s.leftover) lines.push(`This folder still holds the entries of profile ${s.leftover}; run clear to remove them.`);
  }
  if (s.profile) {
    lines.push(`Profile ${s.profile} (${s.target}) applied ${s.appliedAt} to ${s.settingsFile}.`);
    if (s.pending.length) lines.push(`A switch is unfinished; these stay on until apply ${s.profile} --for ${s.target} runs again: ${list(s.pending)}`);
    for (const d of s.differs) lines.push(`Differs from the profile: ${d.name} is ${d.current}, the profile wrote ${d.recorded}`);
    if (s.installedSince.length) lines.push(`Installed since the profile was applied: ${list(s.installedSince)}`);
  } else if (s.rememberFolder) lines.push(`No profile is recorded for ${s.settingsFile}.`);
  lines.push(surfaceLine(s.surface));
  return lines;
}

/** The session-start notice speaks only where a profile was applied: this folder's, a leftover one, or this session's. */
const worthNotice = (s) => Boolean(s.session || s.leftover || (s.rememberFolder && s.profile));

function status(opts, where, env, io) {
  if (opts.sessionStart) {
    try {
      const s = statusOf(opts, where, env, () => recordsFromDisk(where.configDir));
      if (worthNotice(s)) io.out(JSON.stringify({ systemMessage: `plugin-profiles: ${statusLines(s).join(" ")}` }));
    } catch {
      // A session start never fails on a profile problem; status run by hand reports it.
    }
    return 0;
  }
  const s = statusOf(opts, where, env, () => recordsFromCli());
  io.out(opts.json ? JSON.stringify(s, null, 2) : statusLines(s).join("\n"));
  return 0;
}

async function clear(opts, where, io) {
  if (doesNotApply(where.surface)) throw new NotApplied(`not cleared: ${refusal(where.surface, opts.target)}`);
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
  const removes = rec.createdFile && Object.keys(JSON.parse(text)).length === 0;
  io.out(`Clears profile ${rec.profile} from ${file}.`);
  io.out(removes
    ? "Removes the file, which the first apply created."
    : `Puts back ${Object.keys(edits.enabledPlugins).length} plugin entries and ${Object.keys(edits.skillOverrides).length} skill entries to their values before the first apply.`);
  if (opts.dryRun) return 0;
  await consent(opts, [], interactive(), "Clear this profile? [y/N] ");
  try {
    if (removes) deleteSettings(file, settings.hash);
    else writeSettings(file, settings.hash, text);
  } catch (error) {
    if (error instanceof SettingsConflict) throw new NotApplied(`not cleared: ${file} changed while clearing; run clear again`);
    throw error;
  }
  deleteRecord(recPath);
  io.out(`Cleared profile ${rec.profile} from ${file}.`);
  return 0;
}

function listProfiles(opts, where, io) {
  const profiles = [...catalogFor(where, "folder").profiles.values()].map((p) => ({ name: p.name, description: p.description }));
  if (opts.json) io.out(JSON.stringify(profiles, null, 2));
  else for (const p of profiles) io.out(`${p.name}${p.description ? `: ${p.description}` : ""}`);
  return 0;
}

function listInventory(opts, where, io) {
  const inv = [...inventory({ projectDir: where.projectDir, records: recordsFromCli() }).values()];
  if (opts.json) io.out(JSON.stringify(inv, null, 2));
  else for (const p of inv) {
    const ships = Object.entries(p.ships).filter(([, v]) => v).map(([k]) => k);
    io.out(`${p.id} ${p.version ?? "?"}${ships.length ? ` ships ${ships.join(", ")}` : ""}${p.dependsOn.length ? ` needs ${p.dependsOn.join(", ")}` : ""}; skills: ${list(p.skills)}`);
  }
  return 0;
}

function usage(opts, env, io) {
  const u = readUsage(usageFile({ env, home: env.HOME || env.USERPROFILE || homedir() }));
  if (opts.json) io.out(JSON.stringify(u, null, 2));
  else if (!u.source) io.out("No usage history was found on this machine.");
  else {
    io.out(`Usage history from ${u.source}, most used first.`);
    for (const [what, rows] of [["Skills", u.skills], ["Plugins", u.plugins]]) {
      io.out(`${what} (${rows.length}):`);
      for (const r of rows) io.out(`  ${r.name} ${r.count}${r.lastUsedAt ? `, last ${r.lastUsedAt.slice(0, 10)}` : ""}`);
    }
  }
  return 0;
}

/** The plugins the initial profile switches on: always-on, plus the profile recorded for user settings. */
function initialMembers(where) {
  const catalog = catalogFor(where, "initial");
  const rec = readRecord(recordPath(where.dataDir, where.paths.user));
  const chosen = rec ? catalog.profiles.get(rec.profile) : null;
  return new Set([catalog.alwaysOn, chosen].filter(Boolean).flatMap((p) => [...p.plugins, ...p.optional]));
}

function switchOffAtUser(id, file) {
  for (let attempt = 1; ; attempt++) {
    const settings = readSettings(file);
    try {
      return writeSettings(file, settings.hash, editText(settings, { enabledPlugins: { [id]: false } }));
    } catch (error) {
      if (!(error instanceof SettingsConflict)) throw error;
      if (attempt === 2) throw new NotApplied(`installed ${id}, but ${file} kept changing, so it is still on there; switch it off with: claude plugin disable ${id} --scope user`);
    }
  }
}

async function install(opts, where, io) {
  const id = opts.name;
  if (!PLUGIN_ID.test(id)) throw new UsageError(`install takes one plugin as name@marketplace, not ${id}`);
  if (doesNotApply(where.surface)) throw new NotApplied(`not installed: ${surfaceLine(where.surface)}`);
  if (inventory({ projectDir: where.projectDir, records: recordsFromCli() }).has(id)) {
    io.out(`${id} is already installed; nothing to install.`);
    return 0;
  }
  const marketplace = marketplaceOf(id);
  if (!knownMarketplaces().has(marketplace)) {
    throw new NotApplied(`not installed: the ${marketplace} marketplace is not known on this machine, and this tool adds none; add it yourself with claude plugin marketplace add, then run install again`);
  }
  const naming = readProfileFiles(levelsOf(where)).filter((f) => f.def.plugins.includes(id) || f.def.optional.includes(id));
  if (naming.length && naming.every((f) => f.level === "repository")) {
    throw new NotApplied(`not installed: only a repository profile names ${id} (${naming.map((f) => f.path).join(", ")}), and a repository profile never installs a plugin on its own; add it to one of your own profiles with save --level user, or install it yourself with: claude plugin install ${id}`);
  }
  const keepOn = initialMembers(where).has(id);
  const file = where.paths.user;
  io.out(`Installs ${id} from the ${marketplace} marketplace at user scope: claude plugin install ${id} --scope user`);
  io.out(keepOn ? `Leaves it on in ${file}: the initial profile includes it.` : `Then switches it off in ${file}, since the initial profile does not include it; applying a profile that names it switches it on there.`);
  if (opts.dryRun) return 0;
  await consent(opts, [], interactive(), "Install it? [y/N] ");
  installPlugin(id);
  if (!keepOn) switchOffAtUser(id, file);
  io.out(`Installed ${id}${keepOn ? "" : `; it is off in ${file}`}.`);
  return 0;
}

const idsOf = (value) => (value ? value.split(",").map((v) => v.trim()).filter(Boolean) : []);

async function save(opts, where, io) {
  if (!PROFILE_NAME.test(opts.name)) throw new UsageError(`a profile name is lowercase letters, digits and dashes, not ${opts.name}`);
  if (!["user", "repository"].includes(opts.level)) throw new UsageError("save needs --level user or --level repository");
  const levels = levelsOf(where);
  const path = join(levels.find((l) => l.level === opts.level).dir, `${opts.name}.yaml`);
  const files = readProfileFiles(levels);
  const current = files.find((f) => f.path === path);
  const merged = { description: opts.description ?? current?.def.description ?? null };
  for (const [flag, field] of Object.entries(SAVE_LISTS)) merged[field] = [...new Set([...(current?.def[field] ?? []), ...idsOf(opts[flag])])];
  const text = profileText(merged);
  const def = parseProfile(text, path);
  const others = files.filter((f) => f.path !== path);
  const catalog = resolveCatalog([...others, { level: opts.level, name: opts.name, path, def }].sort((a, b) => levels.findIndex((l) => l.level === a.level) - levels.findIndex((l) => l.level === b.level)));
  const affected = opts.name === ALWAYS_ON ? [...catalog.profiles.values()] : [catalog.profiles.get(opts.name)];
  for (const p of affected) {
    const blocked = excludedAlwaysOn(catalog, p);
    if (blocked.length) throw new ProfileError(`${path}: profile ${p.name} would exclude always-on members: ${blocked.join(", ")}`);
  }
  const before = current ? readFileSync(path, "utf8") : null;
  if (before === text) {
    io.out(`Nothing to change: ${path} already holds this profile.`);
    return 0;
  }
  io.out(`${current ? "Replaces" : "Creates"} ${path}:`);
  for (const line of text.trimEnd().split("\n")) io.out(`  ${line}`);
  if (/(^|\s)#/m.test(before ?? "")) io.out("The file is written in the form above, so its comments are not kept.");
  if (opts.dryRun) return 0;
  await consent(opts, [], interactive(), "Write this file? [y/N] ");
  replaceFile(path, text);
  io.out(`Saved profile ${opts.name} to ${path}.`);
  return 0;
}

/** The marketplace.json this plugin came from: its marketplace's clone for a cached install, else the checkout it sits in. */
function defaultCatalog(where) {
  const { pluginId } = resolveInstall(OWN_ROOT);
  const root = pluginId ? marketplaceLocation(where.configDir, marketplaceOf(pluginId)) : join(OWN_ROOT, "..", "..");
  return join(root, ".claude-plugin", "marketplace.json");
}

function check(opts, where, io) {
  const catalog = readMarketplace(opts.catalog ?? defaultCatalog(where));
  const levels = levelsOf(where);
  if (opts.shipped) levels[0].dir = opts.shipped;
  const installed = new Set(inventory({ projectDir: where.projectDir, records: recordsFromDisk(where.configDir) }).keys());
  const { failures, reports } = checkProfiles({ files: readProfileFiles(levels), catalog, installed });
  for (const line of reports) io.out(`Report: ${line}`);
  if (!failures.length) {
    io.out(`Profile check passed against the ${catalog.name} catalog.`);
    return 0;
  }
  for (const line of failures) io.err(`FAIL: ${line}`);
  io.err(`Profile check failed: ${failures.length} problem(s) in the shipped profiles.`);
  return 1;
}

export async function main(argv, env = process.env, cwd = process.cwd(), io = { out: (s) => console.log(s), err: (s) => console.error(s) }) {
  try {
    const opts = parseArgs(argv);
    const where = locate(env, cwd);
    if (opts.command === "apply") return await apply(opts, where, env, io);
    if (opts.command === "status") return status(opts, where, env, io);
    if (opts.command === "clear") return await clear(opts, where, io);
    if (opts.command === "check") return check(opts, where, io);
    if (opts.command === "list") return listProfiles(opts, where, io);
    if (opts.command === "usage") return usage(opts, env, io);
    if (opts.command === "install") return await install(opts, where, io);
    if (opts.command === "save") return await save(opts, where, io);
    return listInventory(opts, where, io);
  } catch (error) {
    if (error instanceof NotApplied) {
      io.err(error.message);
      return 1;
    }
    if ([UsageError, PlanError, ProfileError, SettingsError, InventoryError, CheckError, OptionsError].some((type) => error instanceof type)) {
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
