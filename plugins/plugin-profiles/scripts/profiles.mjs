#!/usr/bin/env node
// Apply a plugin profile to a folder, to user settings, or to one session.
//
//   profiles.mjs apply <name> --for session|folder|initial [--dry-run [--json]] [--yes] [--defer-off]
//   profiles.mjs launch [<name>] [--folder <dir>] [--with <settings file or JSON>] [--unattended] [--dry-run] [--json]
//   profiles.mjs status [--for folder|initial] [--json] [--session-start]
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
//          writes the .claude/settings.local.json Claude Code reads, at the repository root in git
//          (lib/folder-file.mjs; https://code.claude.com/docs/en/settings#where-claude-code-keeps-the-local-file-in-a-git-repository); initial writes user settings.json; session writes a file for
//          `claude --settings` and changes no settings file. The record of a folder in git goes
//          under its .git/plugin-profiles, of user settings under ~/.claude/plugin-profiles-state. --defer-off writes the
//          entries that switch plugins on and records the ones that switch plugins off as
//          pending, for an in-session switch; the next apply writes them. A target the surface
//          does not support (lib/surface.mjs) is refused, and so is --for folder when the
//          remember_folder_profile option is false, and --defer-off in a session that
//          PLUGIN_PROFILES_SESSION names.
// launch   The one way a launcher starts a session in a profile. It writes the one-session file
//          for the folder and profile (one per folder and profile, rewritten on every launch) and
//          prints the command that starts a session with it; it asks nothing and changes no
//          settings file. The name defaults to this session's profile: the one
//          PLUGIN_PROFILES_SESSION names, else the folder's recorded one; with neither, the command
//          carries no profile. --with adds a launcher's own settings (claude keeps only the last
//          --settings), written to a file keyed by the folder, profile and merged content. The
//          command always clears an inherited PLUGIN_PROFILES_SESSION,
//          PLUGIN_PROFILES_SESSION_FILE and SESSION_SETTINGS_FILE; the file sets its own. A
//          session file no launch has written for 30 days is removed by the next launch. The
//          session it starts is a claude CLI process whatever surface runs launch, so no surface
//          refuses it. The file sets PLUGIN_PROFILES_SESSION_FILE to its own path for status, and
//          SESSION_SETTINGS_FILE to the same path for the prerequisite readers.
//          --unattended stops (exit 1) when the profile switches on a plugin missing a required
//          prerequisite; otherwise that is printed and the launch goes ahead. --dry-run does every
//          check and prints the same result but writes no file. --json prints the
//          result as data, with argv the words a launcher runs before its own arguments and, with a
//          profile, enabledPlugins: each plugin any settings layer names, on or off as the session
//          will start with it, the session file read as the session layer.
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
import { spawn } from "node:child_process";
import { existsSync, readdirSync, realpathSync, readFileSync, rmdirSync, rmSync, statSync } from "node:fs";
import { constants as osConstants, homedir } from "node:os";
import { createHash } from "node:crypto";
import { basename, dirname, join, resolve, win32 as win32Path } from "node:path";
import process from "node:process";
import { createInterface } from "node:readline/promises";
import { fileURLToPath } from "node:url";
import { CheckError, checkProfiles, readMarketplace } from "../lib/check.mjs";
import { InventoryError, installPlugin, inventory, knownMarketplaces, marketplaceLocation, recordsFromCli, recordsFromDisk } from "../lib/inventory.mjs";
import { PlanError, TARGET_LEVEL, effective, excludedAlwaysOn, plan } from "../lib/plan.mjs";
import { OptionsError, managedSettingsFiles, readOperatorOptions, resolveInstall } from "../lib/plugin-options.mjs";
import { missingRequired } from "../lib/prerequisite-gate.mjs";
import { replaceFile } from "../lib/atomic-file.mjs";
import { ALWAYS_ON, PLUGIN_ID, ProfileError, everyProfile, ignoredLine, parseProfile, profileLevels, profileNamed, profileText, readCatalog, readProfileFiles, resolveCatalog, sourcesOf } from "../lib/profile-files.mjs";
import { folderLevel } from "../lib/folder-file.mjs";
import { ABSENT, baseline, deleteRecord, findRecord, holdsEveryEntry, nextRecord, realPath, restoreEdits, saveRecord } from "../lib/record.mjs";
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
import { othersInFolder } from "../lib/sessions.mjs";
import { detectSurface, doesNotApply, refusal, surfaceLine } from "../lib/surface.mjs";
import { readUsage, usageFile } from "../lib/usage.mjs";

const OWN_ROOT = dirname(dirname(realpathSync(fileURLToPath(import.meta.url))));
const SESSION_VAR = "PLUGIN_PROFILES_SESSION";
// Set by the file itself, so status names the file a session was launched with, merged or not.
const SESSION_FILE_VAR = "PLUGIN_PROFILES_SESSION_FILE";
// The variable the prerequisite readers in plugin-diagnostics and harness-ops define (their
// lib/enabled-plugin-roots.mjs), so they read this file as the session layer.
const SESSION_SETTINGS_VAR = "SESSION_SETTINGS_FILE";
/** The profile this session was started in, or null; an empty marker counts as unset. */
const sessionProfile = (env) => env[SESSION_VAR] || null;
/** The variables a started claude never inherits; its session file sets its own. */
const CLEARED = [SESSION_VAR, SESSION_FILE_VAR, SESSION_SETTINGS_VAR];
const USAGE = `usage: profiles.mjs apply <name> --for session|folder|initial [--dry-run [--json]] [--yes] [--defer-off]
       profiles.mjs launch [<name>] [--folder <dir>] [--with <settings file or JSON>] [--unattended] [--dry-run] [--json]
       profiles.mjs start [<profile> | --profile <profile>] [--with <settings file or JSON>] [--unattended] [--dry-run] [claude arguments]
       profiles.mjs start [--with <settings file or JSON>] [--unattended] [--dry-run] --claude-args [claude arguments, --profile <profile> among them]
       profiles.mjs status [--for folder|initial] [--json] [--session-start]
       profiles.mjs clear [--for folder|initial|worktree] [--dry-run [--json]] [--yes]
       profiles.mjs list [--json]
       profiles.mjs inventory [--json]
       profiles.mjs usage [--json]
       profiles.mjs install <name@marketplace> [--dry-run] [--yes]
       profiles.mjs save <name> --level user|repository [--description <text>] [--plugins <ids>] [--optional <ids>] [--remove <ids>] [--exclude <ids>] [--hide-skills <names>] [--dry-run] [--yes]
       profiles.mjs check [--catalog <marketplace.json>] [--shipped <dir>]`;

class UsageError extends Error {}
class NotApplied extends Error {}
class StartRefused extends Error {}

const dataDirName = (id) => id.replace(/[^A-Za-z0-9_-]/g, "-");
const marketplaceOf = (id) => id.slice(id.lastIndexOf("@") + 1);
const PROFILE_NAME = /^[a-z0-9][a-z0-9-]*$/;
const SAVE_LISTS = { plugins: "plugins", optional: "optional", remove: "remove", exclude: "exclude", hideSkills: "hideSkills" };
const NAMED = ["apply", "install", "save"];
const SESSION_DAYS = 30;
const OWN_DATA_NAME = /^plugin-profiles(-|$)/;

const RESUME_LINE = "A resumed session does not keep --settings; resume it with: claude --resume <session id>";
const SESSION_ID = /^[A-Za-z0-9-]+$/;
const validId = (id) => typeof id === "string" && SESSION_ID.test(id);
const byIdDir = (dataDir) => join(dataDir, "sessions", "by-id");
const readJson = (path) => {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
};

/** remember_folder_profile from the operator's settings; only an explicit false turns it off. */
function remembersFolder(install) {
  return readOperatorOptions(install, managedSettingsFiles(), ["remember_folder_profile"], { booleans: true }).remember_folder_profile?.value !== "false";
}

/** Where this run reads and writes: the config folder and data folder come from this script's own install path. */
function locate(env, cwd, folder = null) {
  const install = resolveInstall(OWN_ROOT);
  const configDir = install.userSettings
    ? dirname(install.userSettings)
    : env.CLAUDE_CONFIG_DIR || join(env.HOME || env.USERPROFILE || homedir(), ".claude");
  const ownData = env.CLAUDE_PLUGIN_DATA && OWN_DATA_NAME.test(basename(env.CLAUDE_PLUGIN_DATA)) ? env.CLAUDE_PLUGIN_DATA : null;
  const dataDir = install.pluginId
    ? join(configDir, "plugins", "data", dataDirName(install.pluginId))
    : ownData || join(configDir, "plugins", "data", "plugin-profiles-inline");
  const projectDir = folder ? resolve(cwd, folder) : env.CLAUDE_PROJECT_DIR || cwd;
  const pluginVersion = JSON.parse(readFileSync(join(OWN_ROOT, ".claude-plugin", "plugin.json"), "utf8")).version;
  const home = env.HOME || env.USERPROFILE || homedir();
  return {
    configDir,
    dataDir,
    projectDir,
    pluginVersion,
    home,
    folder: folderLevel(projectDir, { home }),
    paths: settingsPaths({ configDir, projectDir, home }),
    surface: detectSurface(env),
    remembersFolder: () => remembersFolder(install),
  };
}

/** Data folders of other copies of this plugin, such as a --plugin-dir copy's plugin-profiles-inline. */
function otherDataDirs(where) {
  const root = join(where.configDir, "plugins", "data");
  try {
    return readdirSync(root, { withFileTypes: true })
      .filter((d) => d.isDirectory() && OWN_DATA_NAME.test(d.name))
      .map((d) => join(root, d.name))
      .filter((dir) => resolve(dir) !== resolve(where.dataDir));
  } catch {
    return [];
  }
}

/** Where a settings file's record lives first: the repository's git common folder, the config folder for user settings, else null. */
function primaryHome(where, file) {
  if (realPath(file) === realPath(where.paths.user)) return join(where.configDir, "plugin-profiles-state");
  const level = folderLevel(dirname(dirname(file)), { home: where.home });
  return level.recordInGit ? join(level.commonDir, "plugin-profiles") : null;
}

/** A settings file's record: its primary home first, then this copy's data folder, then other copies'. */
const homesOf = (where, file) => [primaryHome(where, file), where.dataDir, ...otherDataDirs(where)].filter(Boolean);
const recordOf = (where, file) => {
  const own = findRecord(homesOf(where, file), file);
  return own.record ? own : { ...own, record: adoptedRecord(where, file) };
};

/** A worktree's own file copied from the main checkout after an apply carries the root file's entries but no record: it takes the root file's. */
function adoptedRecord(where, file) {
  const { earlier, local } = where.paths;
  if (!earlier || realPath(file) !== realPath(earlier)) return null;
  const root = findRecord(homesOf(where, local), local).record;
  try {
    return root && holdsEveryEntry(root, readSettings(file).doc) ? { ...root, settingsFile: file } : null;
  } catch {
    return null;
  }
}

/**
 * start keeps its own flags and hands every other word to claude unchanged, except --profile, which names the profile
 * anywhere before a bare --. After --claude-args every word is claude's but --profile, and no first word names a profile.
 */
function parseStart(rest) {
  const opts = { command: "start", name: null, profile: null, passthrough: false, target: "session", folder: null, with: null, unattended: false, dryRun: false, json: false, claudeArgs: [] };
  let ended = false;
  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i];
    if (ended) opts.claudeArgs.push(arg);
    else if (arg === "--profile" || arg.startsWith("--profile=")) {
      const value = arg === "--profile" ? rest[++i] : arg.slice("--profile=".length);
      if (!value || value.startsWith("-")) throw new UsageError("--profile needs a profile name");
      if (opts.profile) throw new UsageError("start takes one --profile");
      opts.profile = value;
    } else if (arg === "--") {
      ended = true;
      opts.claudeArgs.push(arg);
    } else if (opts.passthrough) opts.claudeArgs.push(arg);
    else if (arg === "--claude-args") opts.passthrough = true;
    else if (arg === "--dry-run") opts.dryRun = true;
    else if (arg === "--unattended") opts.unattended = true;
    else if (arg === "--with") {
      if (rest[i + 1] === undefined) throw new UsageError("--with needs a value");
      opts.with = rest[++i];
    } else opts.claudeArgs.push(arg);
  }
  return opts;
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  if (command === "start") return parseStart(rest);
  if (!["apply", "launch", "status", "clear", "list", "inventory", "usage", "install", "save", "check"].includes(command)) throw new UsageError(command ? `unknown command ${command}` : "no command given");
  const opts = { command, name: null, target: command === "apply" ? null : command === "launch" ? "session" : "folder", dryRun: false, yes: false, deferOff: false, json: false, sessionStart: false, catalog: null, shipped: null, level: null, description: null, folder: null, with: null, unattended: false };
  const flags = { apply: ["--dry-run", "--yes", "--defer-off", "--json"], launch: ["--unattended", "--json", "--dry-run"], status: ["--json", "--session-start"], clear: ["--dry-run", "--yes", "--json"], list: ["--json"], inventory: ["--json"], usage: ["--json"], install: ["--dry-run", "--yes"], save: ["--dry-run", "--yes"], check: [] }[command];
  const values = { check: ["--catalog", "--shipped"], launch: ["--folder", "--with"], list: [], inventory: [], usage: [], install: [], save: ["--level", "--description", "--plugins", "--optional", "--remove", "--exclude", "--hide-skills"] }[command] ?? ["--for"];
  const camel = (arg) => arg.slice(2).replace(/-(.)/g, (_, c) => c.toUpperCase());
  for (let i = 0; i < rest.length; i++) {
    const arg = rest[i];
    if (values.includes(arg)) {
      if (rest[i + 1] === undefined) throw new UsageError(`${arg} needs a value`);
      opts[arg === "--for" ? "target" : camel(arg)] = rest[++i];
    }
    else if (flags.includes(arg)) opts[camel(arg)] = true;
    else if ([...NAMED, "launch"].includes(command) && !arg.startsWith("--") && !opts.name) opts.name = arg;
    else throw new UsageError(`unexpected argument ${arg}`);
  }
  if (NAMED.includes(command) && !opts.name) throw new UsageError(`${command} needs a ${command === "install" ? "plugin as name@marketplace" : "profile name"}`);
  const targets = command === "apply" ? Object.keys(TARGET_LEVEL) : command === "clear" ? Object.keys(TARGET_FILES) : ["folder", "initial"];
  if (["apply", "status", "clear"].includes(command) && !targets.includes(opts.target)) throw new UsageError(`--for takes ${targets.join(", ")}`);
  if (opts.deferOff && opts.target === "session") throw new UsageError("--defer-off applies to a folder or user settings, not a one-session file");
  if (["apply", "clear"].includes(command) && opts.json && !opts.dryRun) throw new UsageError(`${command} --json prints a preview and needs --dry-run`);
  return opts;
}

const levelsOf = (where) => profileLevels({ pluginRoot: OWN_ROOT, configDir: where.configDir, projectDir: where.projectDir });

/** The profiles an apply at target resolves; the initial profile never takes a repository's files. */
function catalogFor(where, target) {
  const levels = levelsOf(where);
  return readCatalog(target === "initial" ? levels.filter((l) => l.level !== "repository") : levels);
}

const shortHash = (text) => createHash("sha256").update(text).digest("hex").slice(0, 16);
const sessionsDir = (where) => join(where.dataDir, "sessions");
/** One file per folder and profile; a launcher's own settings add a key of the merged content. */
const sessionFile = (where, name, content = null) =>
  join(sessionsDir(where), `${shortHash(realPath(where.projectDir))}-${name}${content ? `-${shortHash(content)}` : ""}.json`);
const TARGET_FILES = { folder: (where) => where.paths.local, initial: (where) => where.paths.user, worktree: (where) => join(where.projectDir, ".claude", "settings.local.json") };
const targetFile = (where, target, name) => TARGET_FILES[target]?.(where) ?? sessionFile(where, name);

function diff(now, final) {
  const out = {};
  for (const key of new Set([...Object.keys(now), ...Object.keys(final)])) if (now[key] !== final[key]) out[key] = final[key] ?? null;
  return out;
}

/** Every skill some profile hides; a one-session file names each, so a folder file's entry for one never reaches the session. */
const hideableSkills = (catalog) => new Set(everyProfile(catalog).flatMap((p) => [...p.hideSkills]));

/** Reads every input, plans, and works out the exact entries the target file ends with. */
function prepare(opts, where, catalog, records) {
  const file = targetFile(where, opts.target, opts.name);
  const settings = readSettings(file);
  const session = opts.target === "session";
  const { path: recPath, found: recFound, record: previous } = session ? { path: null, found: null, record: null } : recordOf(where, file);
  const base = session ? { enabledPlugins: {}, skillOverrides: {} } : baseline(settings.doc, previous);
  const loaded = readLayers({ paths: where.paths, managedFiles: managedSettingsFiles() });
  const layers = { ...loaded, [TARGET_LEVEL[opts.target]]: base };
  const inv = inventory({ projectDir: where.projectDir, records: records() });
  const result = plan({ catalog, profile: opts.name, inventory: inv, layers, current: loaded, target: opts.target });
  const now = settings.doc.enabledPlugins ?? {};
  const final = { enabledPlugins: { ...base.enabledPlugins, ...result.writes }, skillOverrides: { ...base.skillOverrides, ...result.skillWrites } };
  if (session) for (const skill of hideableSkills(catalog)) final.skillOverrides[skill] ??= "on";
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
  const edits = { enabledPlugins: diff(now, final.enabledPlugins), skillOverrides: diff(settings.doc.skillOverrides ?? {}, final.skillOverrides) };
  if (session) edits.env = { [SESSION_VAR]: opts.name, [SESSION_FILE_VAR]: file, [SESSION_SETTINGS_VAR]: file };
  return { file, settings, recPath, recFound, previous, inv, plan: result, final, pending, edits, loaded };
}

const changeCount = (p) => Object.keys(p.edits.enabledPlugins).length + Object.keys(p.edits.skillOverrides).length;
const sameChange = (a, b) => JSON.stringify([a.final, a.pending, a.edits]) === JSON.stringify([b.final, b.pending, b.edits]);
const list = (ids) => (ids.length ? ids.join(", ") : "none");
const KEPT_BECAUSE = {
  profile: "this profile switches it on",
  repository: "the repository's settings enable it",
  managed: "managed settings pin it",
  folder: "folder settings pin it",
};

/** What a profile that leaves out always-on says about the always-on plugins: which go off, and which stay on and why. */
function alwaysOnLines(r) {
  const guardrailsOff = r.alwaysOnOff.some((id) => id.startsWith("guardrails@"));
  return [
    ...(r.alwaysOnOff.length
      ? [`Switches off ${guardrailsOff ? "guardrails and the other always-on plugins" : "always-on plugins"} that other profiles keep on (${r.alwaysOnOff.length}): ${list(r.alwaysOnOff)}`]
      : []),
    ...r.alwaysOnKept.map((k) => `Always-on plugin left on, because ${KEPT_BECAUSE[k.by]}: ${k.id}`),
  ];
}

/**
 * The lines that say what an apply changes; the terminal prompt and the mod's preview both show them.
 * The mod's preview counts the plugins left alone instead of naming them all; the terminal names them.
 */
function previewLines(p, gate, { nameUntouched = true } = {}) {
  const r = p.plan;
  const on = r.enabled.map((id) => (r.repositoryOn.includes(id) ? `${id} (from a repository profile)` : id));
  const lines = [
    `Profile ${r.profile} for ${r.target}: ${p.file}`,
    ...r.ignored.map(ignoredLine),
    `Switches on (${r.enabled.length}): ${list(on)}`,
    `Switches off (${r.disabled.length}): ${list(r.disabled)}`,
  ];
  lines.push(...alwaysOnLines(r));
  const left = Object.keys(p.pending);
  if (left.length) {
    const named = left.filter((id) => r.disabled.includes(id));
    const rest = left.filter((id) => !r.disabled.includes(id));
    const ofOff = named.length === r.disabled.length ? "every plugin it switches off" : `${named.length} of the plugins it switches off`;
    lines.push(`Switched off in a second write, after the next reload (${left.length}): ${named.length ? ofOff : ""}${named.length && rest.length ? ", plus " : ""}${rest.length ? list(rest) : ""}`);
  }
  const writes = `${Object.keys(p.edits.enabledPlugins).length} plugin entries and ${Object.keys(p.edits.skillOverrides).length} skill entries`;
  lines.push(left.length ? `Writes ${writes} now, and ${left.length} off ${left.length === 1 ? "entry" : "entries"} in the second write.` : `Writes ${writes}.`);
  if (r.repositorySkills.length) lines.push(`Hides skills a repository profile names: ${list(r.repositorySkills)}`);
  if (r.hookPluginsOff.length) lines.push(`Switches off plugins that ship hooks or a mod: ${list(r.hookPluginsOff)}`);
  if (r.mcpOrLspOn.length) lines.push(`Switches on plugins with an MCP or language server: ${list(r.mcpOrLspOn)}`);
  for (const pin of r.pinned) lines.push(`Pinned by ${pin.by} settings (${pin.value}), left alone: ${pin.id}`);
  for (const m of r.missing) lines.push(`Not installed${m.optional ? " (optional)" : ""}: ${m.id}. Install it with: ${m.install}`);
  const leftAlone = `Left alone, from marketplaces this profile does not name (${r.untouched.length})`;
  lines.push(nameUntouched || !r.untouched.length
    ? `${leftAlone}: ${list(r.untouched)}`
    : `${leftAlone}; to name them, run in a terminal: node "${fileURLToPath(import.meta.url)}" apply ${r.profile} --for ${r.target} --dry-run`);
  for (const g of gate) {
    const tool = g.tool ? `${g.tool}: ${g.detail}.` : `${g.detail}.`;
    lines.push(`Missing required prerequisite of ${g.plugin}: ${tool}${g.degrade ? ` ${g.degrade}` : ""}${g.install.length ? ` Install (${g.install.join("; ")}).` : ""}`);
  }
  return lines;
}

/** What apply --dry-run --json prints: the preview lines and the facts a caller branches on. */
const previewJson = (p, gate, upToDate, others) => ({
  profile: p.plan.profile,
  target: p.plan.target,
  file: p.file,
  upToDate,
  enabled: p.plan.enabled,
  disabled: p.plan.disabled,
  pending: Object.keys(p.pending),
  mcpOrLspOn: p.plan.mcpOrLspOn,
  hookPluginsOff: p.plan.hookPluginsOff,
  alwaysOnOff: p.plan.alwaysOnOff,
  alwaysOnKept: p.plan.alwaysOnKept,
  prerequisitesMissing: gate.map((g) => g.plugin),
  ignored: p.plan.ignored,
  repositoryOn: p.plan.repositoryOn,
  repositorySkills: p.plan.repositorySkills,
  othersInFolder: others,
  lines: previewLines(p, gate, { nameUntouched: false }),
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
    createdFolder: !existsSync(dirname(p.file)),
    final: p.final,
    phase: Object.keys(p.pending).length ? "off-pending" : "applied",
    pending: p.pending,
    installed: [...p.inv.keys()],
  });
  saveRecord(p.recPath, record);
  try {
    if (changeCount(p)) writeSettings(p.file, p.settings.hash, text);
  } catch (error) {
    if (p.previous && p.recFound === p.recPath) saveRecord(p.recPath, p.previous);
    else deleteRecord(p.recPath);
    throw error;
  }
  if (p.recFound && p.recFound !== p.recPath) deleteRecord(p.recFound);
}

async function apply(opts, where, env, io) {
  const refused = refusal(where.surface, opts.target, opts.name);
  if (refused) throw new NotApplied(`not applied: ${refused}`);
  if (opts.target === "folder" && !where.remembersFolder()) {
    throw new NotApplied(`not applied: folder remembering is off (remember_folder_profile), so every session starts from the initial profile; start one session in ${opts.name} with apply ${opts.name} --for session, or set the initial profile with apply ${opts.name} --for initial`);
  }
  if (opts.deferOff && sessionProfile(env)) {
    throw new NotApplied(`not applied: this session runs in profile ${sessionProfile(env)} from a one-session settings file, so a switch here would not hold; start a session in ${opts.name} with apply ${opts.name} --for session, then the claude --settings command it prints`);
  }
  const catalog = catalogFor(where, opts.target);
  const records = () => recordsFromCli();
  let p = prepare(opts, where, catalog, records);
  const gate = missingRequired(
    p.plan.enabled.map((id) => p.inv.get(id)),
    { env, platform: process.platform, cwd: where.projectDir, dataDirOf: (id) => join(where.configDir, "plugins", "data", dataDirName(id)) },
  );
  const recorded = p.previous?.profile === opts.name && p.previous.phase === "applied";
  const upToDate = !changeCount(p) && !Object.keys(p.pending).length && opts.target !== "session" && recorded;
  if (opts.json) {
    const others = opts.target === "folder"
      ? othersInFolder(where.projectDir, env.CLAUDE_CODE_SESSION_ID, undefined, { home: where.home }).map((s) => ({ ...s, oneSessionProfile: oneSessionProfileOf(where, s.sessionId) }))
      : [];
    io.out(JSON.stringify(previewJson(p, gate, upToDate, others), null, 2));
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
    io.out(RESUME_LINE);
  }
  return 0;
}

/** The profile a launch from this session defaults to: the session's own, else the folder's recorded one. */
function ownProfile(where, env) {
  return sessionProfile(env) ?? folderProfile(where);
}

/** The profile recorded for this folder while folder remembering is on, else null. */
const folderProfile = (where) => (where.remembersFolder() ? recordOf(where, where.paths.local).record?.profile ?? null : null);

/** A launcher's own settings, given as claude --settings takes them: a JSON object or a file holding one. */
function launcherSettings(value) {
  if (value === null) return null;
  if (value.trim().startsWith("{")) {
    try {
      const doc = JSON.parse(value);
      if (doc && typeof doc === "object" && !Array.isArray(doc)) return doc;
    } catch {
      // Reported below.
    }
    throw new UsageError("--with holds text that is not a JSON object");
  }
  return readSettings(resolve(value)).doc;
}

/** Removes the files in dir, session files by default, that nothing has written for SESSION_DAYS days, keeping keep. */
function sweepSessions(where, keep, dir = sessionsDir(where)) {
  const cutoff = Date.now() - SESSION_DAYS * 24 * 60 * 60 * 1000;
  for (const name of readdirSync(dir)) {
    const file = join(dir, name);
    if (file === keep || !name.endsWith(".json")) continue;
    try {
      if (statSync(file).mtimeMs < cutoff) rmSync(file, { force: true });
    } catch {
      // Another launch removed it first.
    }
  }
}

const quoted = (word) => (/^[A-Za-z0-9_@%+=:,./-]+$/.test(word) ? word : `"${word.replace(/(["\\$`])/g, "\\$1")}"`);

/** The plan for a one-session profile and its missing required prerequisites; with nobody there to decide, a missing one refuses. */
function profileGate(name, opts, where, env, verb) {
  const p = prepare({ ...opts, name, target: "session" }, where, catalogFor(where, "session"), () => recordsFromCli());
  const gate = missingRequired(
    p.plan.enabled.map((id) => p.inv.get(id)),
    { env, platform: process.platform, cwd: where.projectDir, dataDirOf: (id) => join(where.configDir, "plugins", "data", dataDirName(id)) },
  );
  const lines = [
    ...alwaysOnLines(p.plan),
    ...previewLines(p, gate).filter((line) => line.startsWith("Missing required prerequisite") || line.startsWith("Not installed")),
  ];
  if (gate.length && opts.unattended) throw new NotApplied(`not ${verb}: profile ${name} switches on a plugin missing a required prerequisite, and nobody is there to decide.\n${lines.join("\n")}`);
  return { p, gate, lines };
}

/** Writes the session file for name (none when null) and returns what claude is started with; launch and start share it. */
function launchSettings(name, opts, where, env, io) {
  const own = launcherSettings(opts.with);
  const result = { profile: name, folder: where.projectDir, file: null, prerequisitesMissing: [], settingsArgs: [] };
  if (name) {
    const { p, gate, lines } = profileGate(name, opts, where, env, "launched");
    result.prerequisitesMissing = gate.map((g) => g.plugin);
    const doc = { ...own };
    doc.enabledPlugins = { ...own?.enabledPlugins, ...p.final.enabledPlugins };
    const skills = { ...own?.skillOverrides, ...p.final.skillOverrides };
    if (Object.keys(skills).length) doc.skillOverrides = skills;
    else delete doc.skillOverrides;
    doc.env = { ...own?.env, [SESSION_VAR]: name };
    result.file = sessionFile(where, name, own ? JSON.stringify(doc) : null);
    doc.env[SESSION_FILE_VAR] = result.file;
    doc.env[SESSION_SETTINGS_VAR] = result.file;
    const layers = { ...p.loaded, session: doc };
    const ids = new Set(Object.values(layers).flatMap((layer) => Object.keys(layer?.enabledPlugins ?? {})));
    result.enabledPlugins = Object.fromEntries([...ids].sort().map((id) => [id, effective(layers, id)]));
    if (!opts.dryRun) {
      replaceFile(result.file, `${JSON.stringify(doc, null, 2)}\n`);
      sweepSessions(where, result.file);
      if (existsSync(byIdDir(where.dataDir))) sweepSessions(where, null, byIdDir(where.dataDir));
    }
    for (const line of lines) io.err(line);
  } else if (own && !opts.with.trim().startsWith("{")) result.file = resolve(opts.with);
  if (result.file) result.settingsArgs.push("--settings", result.file);
  else if (own) result.settingsArgs.push("--settings", JSON.stringify(own));
  return result;
}

function launch(opts, where, env, io) {
  const name = opts.name ?? ownProfile(where, env);
  const { settingsArgs, ...rest } = launchSettings(name, opts, where, env, io);
  const result = { ...rest, argv: ["env", ...CLEARED.flatMap((v) => ["-u", v]), "claude", ...settingsArgs] };
  result.command = result.argv.map(quoted).join(" ");
  if (opts.json) {
    io.out(JSON.stringify(result, null, 2));
    return 0;
  }
  io.out(name ? `Profile ${name} for ${where.projectDir}: ${result.file}` : `No profile for ${where.projectDir}: the session starts with the folder's settings.`);
  io.out(`Start the session with: ${result.command}`);
  if (result.file) io.out(RESUME_LINE);
  return 0;
}

/** The record the session-start hook wrote for a session id, from this copy's data folder or another copy's. */
function sessionRecord(where, id) {
  const latest = (rec) => [rec.at, rec.plainSince].filter((t) => typeof t === "string").sort().at(-1) ?? "";
  const found = [where.dataDir, ...otherDataDirs(where)].map((dir) => readJson(join(byIdDir(dir), `${id}.json`))).filter((rec) => rec?.profile);
  return found.sort((a, b) => latest(b).localeCompare(latest(a)))[0] ?? null;
}

/** The one-session profile a live session runs in, from its record, or null once it was resumed without it. */
function oneSessionProfileOf(where, id) {
  const rec = validId(id) ? sessionRecord(where, id) : null;
  return rec && !rec.plainSince ? rec.profile : null;
}

/** The first resume or continue flag among claude's arguments: resume with an id, the resume picker, or continue. */
function resumeOf(args) {
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--") return null;
    if (arg.startsWith("--resume=")) return { kind: "resume", id: arg.slice("--resume=".length) };
    if (arg === "--resume" || arg === "-r") {
      const next = args[i + 1];
      return next !== undefined && !next.startsWith("-") ? { kind: "resume", id: next } : { kind: "pick" };
    }
    if (arg === "-c" || arg === "--continue") return { kind: "continue" };
  }
  return null;
}

const profileLine = (p) => `${p.name}${p.description ? `: ${p.description}` : ""}`;

/** Asks for one profile by number: its name, null for no profile, undefined when the person gives no answer. */
export function pickProfile(rows, marked, { input = process.stdin, output = process.stdout } = {}) {
  const write = (line) => output.write(`${line}\n`);
  rows.forEach((p, i) => write(`${i + 1}. ${profileLine({ ...p, name: p.name === marked ? `${p.name} (this folder's)` : p.name })}`));
  write("0. No profile: the folder's settings");
  const rl = createInterface({ input, output });
  return new Promise((done) => {
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      rl.close();
      input.pause?.();
      done(value);
    };
    rl.on("line", (line) => {
      const text = line.trim();
      const n = /^\d+$/.test(text) ? Number(text) : -1;
      if (!text) finish(undefined);
      else if (n === 0) finish(null);
      else if (n >= 1 && n <= rows.length) finish(rows[n - 1].name);
      else {
        write(`Type a number from 0 to ${rows.length}, or press Enter to stop.`);
        rl.prompt();
      }
    });
    rl.on("close", () => finish(undefined));
    rl.setPrompt("Start which profile? ");
    rl.prompt();
  });
}

/** Runs claude with stdio inherited and without the cleared variables; resolves to its exit status, 128 plus the signal number when a signal ended it. */
function runClaude(args, env, io) {
  const childEnv = { ...env };
  for (const name of CLEARED) delete childEnv[name];
  const command = claudeCommand(env, process.platform);
  if (command.refusal) {
    io.err(`${command.refusal}\nRun it yourself: claude ${args.map(quoted).join(" ")}`);
    return Promise.resolve(127);
  }
  let child = null;
  const ignore = () => {};
  const forward = (signal) => () => child?.kill(signal);
  const handlers = { SIGINT: ignore, SIGTERM: forward("SIGTERM"), SIGHUP: forward("SIGHUP") };
  for (const [signal, handler] of Object.entries(handlers)) process.on(signal, handler);
  return new Promise((done) => {
    child = spawn(command.file, args, { stdio: "inherit", env: childEnv });
    child.on("error", (error) => {
      io.err(`start: could not run claude: ${error.message}`);
      done(127);
    });
    child.on("exit", (code, signal) => done(code ?? 128 + (osConstants.signals[signal] ?? 0)));
  }).finally(() => {
    for (const [signal, handler] of Object.entries(handlers)) process.off(signal, handler);
  });
}

/**
 * The claude executable to spawn without a shell: on Windows the claude.exe found on PATH, since a .cmd runs only
 * through a shell, which would split or interpret the person's arguments (https://nodejs.org/api/child_process.html#spawning-bat-and-cmd-files-on-windows).
 */
export function claudeCommand(env, platform, isFile = (path) => existsSync(path)) {
  if (platform !== "win32") return { file: "claude" };
  const pathVar = Object.keys(env).find((key) => key.toUpperCase() === "PATH");
  const dirs = (pathVar ? env[pathVar] : "").split(";").filter(Boolean);
  const exe = dirs.map((dir) => win32Path.join(dir, "claude.exe")).find(isFile);
  if (exe) return { file: exe };
  const script = dirs.flatMap((dir) => ["claude.cmd", "claude.bat"].map((name) => win32Path.join(dir, name))).find(isFile);
  return {
    refusal: script
      ? `start: found ${script} but no claude.exe on PATH; a .cmd runs only through a shell, which would split or interpret your arguments, so start needs the native claude.exe.`
      : "start: no claude.exe on PATH.",
  };
}

/** What a start resumes and in which profile: the claude arguments to run, the profile, a session file to reuse, and the line to print. */
function resumePlan(args, given, where) {
  const res = resumeOf(args);
  const plan = { args, name: given, reuse: null, folder: null, line: null, res };
  if (res?.kind === "pick" && !given) plan.line = "Pick the session; if it ran in a profile, its start notice gives the command that resumes it there.";
  if (res?.kind === "continue" && !given) plan.line = "Continuing with this folder's settings; if that session ran in a profile, its start notice gives the command that resumes it there.";
  if (res?.kind !== "resume") return plan;
  const rec = validId(res.id) ? sessionRecord(where, res.id) : null;
  if (!rec) {
    plan.line = given ? `Resuming ${res.id} in profile ${given}.` : `No profile is recorded for session ${res.id}; resuming with this folder's settings.`;
    return plan;
  }
  const id = rec.sessionId ?? res.id;
  if (given && given !== rec.profile) {
    plan.line = `Resuming ${id} in profile ${given} (it ran in ${rec.profile}).`;
    return plan;
  }
  plan.name = rec.profile;
  plan.line = `Resuming ${id} in profile ${rec.profile}.`;
  if (existsSync(rec.file ?? "")) plan.reuse = rec.file;
  else plan.folder = rec.folder;
  return plan;
}

async function start(opts, where, env, io) {
  const catalog = catalogFor(where, "folder");
  const rows = everyProfile(catalog).map((p) => ({ name: p.name, description: p.description }));
  const listing = rows.map(profileLine).join("\n");
  const args = [...opts.claudeArgs];
  const named = (name) => {
    if (!profileNamed(catalog, name)) throw new StartRefused(`start: no profile named ${name}; run start with no profile to pick one\n${listing}`);
    return name;
  };
  let given = opts.profile ? named(opts.profile) : null;
  if (!opts.passthrough && args.length && !args[0].startsWith("-")) {
    if (given) throw new UsageError("start takes the profile once: as its first word or with --profile");
    given = named(args.shift());
  }
  const plan = resumePlan(args, given, where);
  const plain = opts.passthrough && !plan.res && !given;
  if (!plan.res && !given && !plain) {
    if (!interactive()) throw new StartRefused(`start: name a profile; nobody is there to pick one\n${listing}`);
    const picked = await pickProfile(rows, folderProfile(where));
    if (picked === undefined) throw new NotApplied("start: no profile picked; claude was not started");
    plan.name = picked;
  }
  let file = plan.reuse;
  let settingsArgs = plan.reuse && !opts.with ? ["--settings", plan.reuse] : null;
  if (settingsArgs) {
    if (opts.unattended) profileGate(plan.name, opts, where, env, "resumed");
  } else {
    const at = plan.folder && !opts.with ? locate(env, where.projectDir, plan.folder) : where;
    ({ file, settingsArgs } = launchSettings(plan.name, opts, at, env, io));
  }
  const argv = [...settingsArgs, ...plan.args];
  const line = plan.line ?? (plan.name ? `Starting claude in profile ${plan.name} (${file}).` : "Starting claude with this folder's settings.");
  if (!plain) io.err(line);
  if (opts.dryRun) {
    io.out(JSON.stringify({ argv: ["claude", ...argv], env_removed: CLEARED, file, profile: plan.name }, null, 2));
    return 0;
  }
  return runClaude(argv, env, io);
}

/** The record of one settings file compared with the file now. */
function recordedStatus(target, where, records) {
  const file = targetFile(where, target);
  const rec = recordOf(where, file).record;
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
    repositoryWide: target === "folder" && where.folder.worktrees,
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
  const name = sessionProfile(env);
  if (name) base.session = { profile: name, file: env[SESSION_FILE_VAR] || sessionFile(where, name) };
  let target = opts.target;
  if (target === "folder" && !where.remembersFolder()) {
    base.rememberFolder = false;
    base.leftover = recordOf(where, targetFile(where, "folder")).record?.profile ?? null;
    target = "initial";
  }
  base.earlier = earlierProfile(where);
  const recorded = recordedStatus(target, where, records);
  const inForce = name ?? (base.rememberFolder || target === "initial" ? recorded.profile : null);
  return { ...base, ...recorded, launchCommand: inForce ? launchCommandOf(inForce, where) : null, startCommand: inForce ? `claude --profile ${inForce}` : null };
}

/** A profile an earlier version applied to the folder's own file, which Claude Code still reads below the folder file; else null. */
function earlierProfile(where) {
  const file = where.paths.earlier;
  if (!file) return null;
  const profile = recordOf(where, file).record?.profile;
  if (profile) {
    const line = `An earlier profile, ${profile}, sits in ${file}; Claude Code reads it only for plugins ${where.paths.local} does not set, so it is partly in force. Run clear --for worktree to put that file back.`;
    return { profile, file, line };
  }
  const own = readSettings(file).doc;
  const root = readSettings(where.paths.local).doc;
  const [plugins, skills] = ["enabledPlugins", "skillOverrides"].map((key) => Object.keys(own[key] ?? {}).filter((name) => !(name in (root[key] ?? {}))));
  if (!plugins.length && !skills.length) return null;
  const entries = [...plugins, ...skills.map((name) => `skill ${name}`)];
  const line = `${file} also applies here for entries ${where.paths.local} does not set: ${list(entries)}. No profile wrote it, so clear leaves it; edit or remove that file to drop them.`;
  return { profile: null, file, line };
}

/** The command that starts another session here in a profile: launch writes its file and prints the claude line. */
const launchCommandOf = (name, where) =>
  ["node", join(OWN_ROOT, "scripts", "profiles.mjs"), "launch", name, "--folder", where.projectDir].map(quoted).join(" ");

function statusLines(s) {
  if (doesNotApply(s.surface)) return [surfaceLine(s.surface)];
  const lines = [];
  if (s.session) lines.push(`This session runs in profile ${s.session.profile} from a one-session settings file. ${RESUME_LINE}`);
  if (!s.rememberFolder) {
    lines.push(`Folder remembering is off: sessions start from the initial profile${s.profile ? ` ${s.profile}` : ""}.`);
    if (s.leftover) lines.push(`This folder still holds the entries of profile ${s.leftover}; run clear to remove them.`);
  }
  if (s.profile) {
    lines.push(`Profile ${s.profile} (${s.target}) applied ${s.appliedAt} to ${s.settingsFile}${s.repositoryWide ? ", which every worktree of this repository reads" : ""}.`);
    if (s.pending.length) lines.push(`A switch is unfinished; these stay on until apply ${s.profile} --for ${s.target} runs again: ${list(s.pending)}`);
    for (const d of s.differs) lines.push(`Differs from the profile: ${d.name} is ${d.current}, the profile wrote ${d.recorded}`);
    if (s.installedSince.length) lines.push(`Installed since the profile was applied: ${list(s.installedSince)}`);
  } else if (s.rememberFolder) lines.push(`No profile is recorded for ${s.settingsFile}.`);
  if (s.earlier) lines.push(s.earlier.line);
  if (s.launchCommand) lines.push(`Start another session here in this profile with: ${s.startCommand} (or ${s.launchCommand})`);
  lines.push(surfaceLine(s.surface));
  return lines;
}

/** The session-start notice, one short line each: what is in force and what needs the person, without status's commands; the surface only off the CLI. */
function noticeLines(s, sessionId) {
  if (doesNotApply(s.surface)) return [surfaceLine(s.surface)];
  const lines = [];
  if (s.session) {
    lines.push(`This session runs in profile ${s.session.profile}.`);
    lines.push(`Resume it in that profile with: claude --resume ${validId(sessionId) ? sessionId : "<session id>"}`);
  } else if (s.profile) {
    lines.push(`Profile ${s.profile} applies here (${s.settingsFile}${s.repositoryWide ? ", which every worktree of this repository reads" : ""}).`);
  }
  if (!s.rememberFolder) {
    lines.push(`Folder remembering is off: sessions start from the initial profile${s.profile ? ` ${s.profile}` : ""}.`);
    if (s.leftover) lines.push(`This folder still holds the entries of profile ${s.leftover}; run clear to remove them.`);
  }
  if (s.profile && !s.session) {
    if (s.pending.length) lines.push(`A switch is unfinished; these stay on until apply ${s.profile} --for ${s.target} runs again: ${list(s.pending)}`);
    for (const d of s.differs) lines.push(`Differs from the profile: ${d.name} is ${d.current}, the profile wrote ${d.recorded}`);
    if (s.installedSince.length) lines.push(`Installed since the profile was applied: ${list(s.installedSince)}`);
  }
  if (s.earlier) lines.push(s.earlier.line);
  if (s.surface.id !== "cli") lines.push(surfaceLine(s.surface));
  return lines;
}

/** The session-start notice speaks only where a profile was applied: this folder's, a leftover or earlier one, or this session's. */
const worthNotice = (s) => Boolean(s.session || s.leftover || s.earlier || (s.rememberFolder && s.profile));

/** The SessionStart hook's JSON from stdin, or an empty object when there is none or it is not an object. */
function hookInput(io) {
  const doc = (() => {
    try {
      return JSON.parse(io.stdin());
    } catch {
      return null;
    }
  })();
  return doc && typeof doc === "object" ? doc : {};
}

/** Records the profile this session runs in under its id, or for a session resumed without one, the line naming the profile it ran in. */
function sessionStartRecord(where, env, input) {
  if (doesNotApply(where.surface) || !validId(input.session_id)) return null;
  const name = sessionProfile(env);
  if (name && env[SESSION_FILE_VAR]) {
    const before = input.source === "resume" ? sessionRecord(where, input.session_id) : null;
    const rec = { sessionId: input.session_id, profile: name, file: env[SESSION_FILE_VAR], folder: where.projectDir, at: new Date().toISOString() };
    replaceFile(join(byIdDir(where.dataDir), `${input.session_id}.json`), `${JSON.stringify(rec, null, 2)}\n`);
    return before && before.profile !== name
      ? `This session ran in profile ${before.profile} and now runs in ${name}, so a later claude --resume ${input.session_id} restores ${name}.`
      : null;
  }
  const rec = !name && input.source === "resume" ? sessionRecord(where, input.session_id) : null;
  if (rec && !rec.plainSince) replaceFile(join(byIdDir(where.dataDir), `${input.session_id}.json`), `${JSON.stringify({ ...rec, plainSince: new Date().toISOString() }, null, 2)}\n`);
  return rec ? `This session ran in profile ${rec.profile}; it is now running without it. Resume it in that profile with: claude --resume ${input.session_id} (the plugin-profiles claude shell function restores the profile; without it, run node "${join(OWN_ROOT, "scripts", "profiles.mjs")}" start --resume ${input.session_id}).` : null;
}

/** Points the dotfiles claude function at this installed copy when the pointer differs; never a worktree or --plugin-dir copy, and never throws. */
function writeRootPointer(where) {
  if (doesNotApply(where.surface) || !resolveInstall(OWN_ROOT).pluginId) return;
  const file = join(where.configDir, "plugin-profiles-state", "root");
  const text = `${OWN_ROOT}\n`;
  try {
    if (!existsSync(file) || readFileSync(file, "utf8") !== text) replaceFile(file, text);
  } catch {
    return;
  }
}

function status(opts, where, env, io) {
  if (opts.sessionStart) {
    writeRootPointer(where);
    const input = hookInput(io);
    const resumed = (() => {
      try {
        return sessionStartRecord(where, env, input);
      } catch {
        return null;
      }
    })();
    const lines = resumed ? [resumed] : [];
    try {
      const s = statusOf(opts, where, env, () => recordsFromDisk(where.configDir));
      if (worthNotice(s)) lines.push(...noticeLines(s, input.session_id));
    } catch {
      // A session start never fails on a profile problem; status run by hand reports it.
    }
    if (lines.length) io.out(JSON.stringify({ systemMessage: `plugin-profiles:\n${lines.join("\n")}` }));
    return 0;
  }
  const s = statusOf(opts, where, env, () => recordsFromCli());
  io.out(opts.json ? JSON.stringify(s, null, 2) : statusLines(s).join("\n"));
  return 0;
}

/** The line saying that a one-session profile outlasts a clear, or null outside such a session. */
const keepsSessionProfile = (env) =>
  sessionProfile(env)
    ? `This session runs in profile ${sessionProfile(env)} from a one-session settings file and keeps it after the clear; new sessions in this folder start without a folder profile.`
    : null;

/** Recorded entries edited since the apply that clear would change again: neither the profile's value nor the one clear puts back. */
function overwrittenEdits(rec, doc) {
  const out = [];
  for (const [key, section] of [["enabledPlugins", "entries"], ["skillOverrides", "skillOverrides"]]) {
    for (const [name, { before, after }] of Object.entries(rec[section])) {
      const current = doc[key]?.[name] ?? ABSENT;
      if (current !== after && current !== before && rec.pending?.[name] === undefined) out.push({ name, current, after, before });
    }
  }
  return out;
}

/** Removes a folder only when it is empty; a folder that holds anything stays. */
function removeEmptyFolder(dir) {
  try {
    rmdirSync(dir);
  } catch {}
}

async function clear(opts, where, env, io) {
  if (doesNotApply(where.surface)) throw new NotApplied(`not cleared: ${refusal(where.surface, opts.target)}`);
  const file = targetFile(where, opts.target);
  const { found: recPath, record: rec } = recordOf(where, file);
  const keeps = keepsSessionProfile(env);
  const preview = (recorded, lines) => {
    if (opts.json) io.out(JSON.stringify({ recorded, sessionProfile: sessionProfile(env), lines: keeps ? [...lines, keeps] : lines }, null, 2));
    else for (const line of keeps ? [...lines, keeps] : lines) io.out(line);
  };
  if (!rec) {
    const doc = readSettings(file).doc;
    const [plugins, skills] = ["enabledPlugins", "skillOverrides"].map((key) => Object.keys(doc[key] ?? {}).length);
    preview(false, [plugins + skills
      ? `No record of a profile apply was found for ${file}, so clear cannot tell which of its ${plugins} plugin entries and ${skills} skill entries a profile wrote; it changes nothing. To drop them all, remove the enabledPlugins and skillOverrides keys from ${file}.`
      : `No profile is recorded for ${file}; nothing to clear.`]);
    return 0;
  }
  const settings = readSettings(file);
  const { edits, dropEmpty } = restoreEdits(rec);
  const text = editText(settings, edits, { dropEmpty });
  const removes = rec.createdFile && Object.keys(JSON.parse(text)).length === 0;
  preview(true, [
    `Clears profile ${rec.profile} from ${file}.`,
    removes
      ? `Removes the file${rec.createdFolder ? ", and its folder when nothing else is in it," : ""} which the first apply created.`
      : `Puts back ${Object.keys(edits.enabledPlugins).length} plugin entries and ${Object.keys(edits.skillOverrides).length} skill entries to their values before the first apply.`,
    ...overwrittenEdits(rec, settings.doc).map(
      (e) => `Overwrites a change made since the apply: ${e.name} is ${e.current}, the profile wrote ${e.after}; clear puts back ${e.before}.`,
    ),
  ]);
  if (opts.dryRun) return 0;
  await consent(opts, [], interactive(), "Clear this profile? [y/N] ");
  try {
    if (removes) {
      deleteSettings(file, settings.hash);
      if (rec.createdFolder) removeEmptyFolder(dirname(file));
    } else writeSettings(file, settings.hash, text);
  } catch (error) {
    if (error instanceof SettingsConflict) throw new NotApplied(`not cleared: ${file} changed while clearing; run clear again`);
    throw error;
  }
  if (recPath) deleteRecord(recPath);
  io.out(`Cleared profile ${rec.profile} from ${file}.`);
  return 0;
}

function listProfiles(opts, where, io) {
  const profiles = [...catalogFor(where, "folder").profiles.values()].map((p) => ({ name: p.name, description: p.description }));
  if (opts.json) io.out(JSON.stringify(profiles, null, 2));
  else for (const p of profiles) io.out(profileLine(p));
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

/** The plugins the initial profile switches on: the profile recorded for user settings with what it merges, else always-on. */
function initialMembers(where) {
  const catalog = catalogFor(where, "initial");
  const rec = recordOf(where, where.paths.user).record;
  const chosen = (rec && catalog.profiles.get(rec.profile)) ?? catalog.alwaysOn;
  return new Set(sourcesOf(catalog, chosen).flatMap((p) => [...p.plugins, ...p.optional]));
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
  const merged = { description: opts.description ?? current?.def.description ?? null, alwaysOn: current?.def.alwaysOn ?? null };
  for (const [flag, field] of Object.entries(SAVE_LISTS)) merged[field] = [...new Set([...(current?.def[field] ?? []), ...idsOf(opts[flag])])];
  const text = profileText(merged);
  const def = parseProfile(text, path);
  const others = files.filter((f) => f.path !== path);
  const catalog = resolveCatalog([...others, { level: opts.level, name: opts.name, path, def }].sort((a, b) => levels.findIndex((l) => l.level === a.level) - levels.findIndex((l) => l.level === b.level)));
  const ignored = [catalog.alwaysOn, ...catalog.profiles.values()].flatMap((p) => p.ignored).filter((e) => e.file === path);
  if (ignored.length) throw new ProfileError(ignored.map(ignoredLine).join(" "));
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
  const unreadable = [];
  const files = levels.flatMap((level) => {
    try {
      return readProfileFiles([level]);
    } catch (error) {
      if (level.level === "shipped" || !(error instanceof ProfileError)) throw error;
      unreadable.push(`${error.message} (the other ${level.level} profiles in ${level.dir} were not checked)`);
      return [];
    }
  });
  const { failures, reports } = checkProfiles({ files, catalog, installed });
  for (const line of [...unreadable, ...reports]) io.out(`Report: ${line}`);
  if (!failures.length) {
    io.out(`Profile check passed against the ${catalog.name} catalog.`);
    return 0;
  }
  for (const line of failures) io.err(`FAIL: ${line}`);
  io.err(`Profile check failed: ${failures.length} problem(s) in the shipped profiles.`);
  return 1;
}

const readStdin = () => (process.stdin.isTTY ? "" : readFileSync(0, "utf8"));

export async function main(argv, env = process.env, cwd = process.cwd(), io = { out: (s) => console.log(s), err: (s) => console.error(s), stdin: readStdin }) {
  try {
    const opts = parseArgs(argv);
    const where = locate(env, cwd, opts.folder);
    io.stdin ??= readStdin;
    if (opts.command === "start") return await start(opts, where, env, io);
    if (opts.command === "apply") return await apply(opts, where, env, io);
    if (opts.command === "launch") return launch(opts, where, env, io);
    if (opts.command === "status") return status(opts, where, env, io);
    if (opts.command === "clear") return await clear(opts, where, env, io);
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
    if (error instanceof StartRefused) {
      io.err(error.message);
      return 2;
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
