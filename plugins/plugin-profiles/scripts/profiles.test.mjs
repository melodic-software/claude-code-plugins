import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { PassThrough } from "node:stream";
import { createHash } from "node:crypto";
import { chmodSync, cpSync, existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { delimiter, dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { parseProfile } from "../lib/profile-files.mjs";
import { pickProfile } from "./profiles.mjs";
import { tempDir, writeTree } from "../tests/temp.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, "profiles.mjs");
const STUB_BIN = join(HERE, "..", "tests", "bin");
const M = "melodic-software";
const ALWAYS_FILE = join(HERE, "..", "profiles", "always-on.yaml");
const ALWAYS = parseProfile(readFileSync(ALWAYS_FILE, "utf8"), ALWAYS_FILE).plugins.map((id) => id.split("@")[0]);
const BUILD = ["implementation", "toolchain", "review", "testing"];

const LOCAL_BEFORE = `{
  "permissions": {
    "allow": [
      "Bash(npm test)"
    ]
  },
  "enabledPlugins": {
    "songwriting@melodic-software": true,
    "review@melodic-software": false
  }
}
`;

/** A temp HOME and project with a stub claude listing every always-on member, a few build members, songwriting and a third-party plugin. */
function world({ local = LOCAL_BEFORE, prerequisiteMissing = false } = {}) {
  const root = tempDir();
  const home = join(root, "home");
  const project = join(root, "project");
  const plugins = [...ALWAYS, ...BUILD, "songwriting"].map((name) => `${name}@${M}`).concat("widget@vendor");
  const records = plugins.map((id) => {
    const name = id.split("@")[0];
    writeTree(root, { [`installs/${name}/.claude-plugin/plugin.json`]: { name } });
    return { id, version: "1.0.0", scope: "user", enabled: true, installPath: join(root, "installs", name) };
  });
  if (prerequisiteMissing) {
    writeTree(root, {
      "installs/implementation/prerequisites.json": {
        requires: [
          {
            id: "pp-absent-tool",
            kind: "cli",
            need: "required",
            for: ["plugin"],
            detect: { any: ["pp-absent-tool-zz9"] },
            degrade: "Without pp-absent-tool, implementation cannot build anything.",
            install: { docs: "https://example.com/pp-absent-tool" },
          },
        ],
      },
    });
  }
  writeTree(root, {
    "list.json": records,
    "home/.claude/settings.json": { theme: "dark", enabledPlugins: { [`songwriting@${M}`]: true, [`review@${M}`]: true } },
    "project/.claude/settings.json": { enabledPlugins: { [`toolchain@${M}`]: true } },
  });
  if (local !== null) writeTree(project, { ".claude/settings.local.json": local });
  const env = { PATH: `${STUB_BIN}${delimiter}${process.env.PATH}`, HOME: home, USERPROFILE: home, PP_STUB_LIST: join(root, "list.json"), PP_STUB_CALLS: join(root, "calls.txt") };
  if (process.env.SystemRoot) env.SystemRoot = process.env.SystemRoot;
  const run = (args, extra = {}, cli = CLI) => spawnSync(process.execPath, [cli, ...args], { cwd: project, env: { ...env, ...extra }, encoding: "utf8" });
  const localFile = join(project, ".claude", "settings.local.json");
  const read = () => (existsSync(localFile) ? readFileSync(localFile, "utf8") : null);
  const records_ = () => {
    const dir = join(home, ".claude", "plugins", "data", "plugin-profiles-inline", "records");
    return existsSync(dir) ? readdirSync(dir) : [];
  };
  return { root, home, project, env, run, localFile, read, records: records_, calls: () => (existsSync(env.PP_STUB_CALLS) ? readFileSync(env.PP_STUB_CALLS, "utf8") : "") };
}

const withoutProfileKeys = (text) => {
  const { enabledPlugins, skillOverrides, ...rest } = JSON.parse(text);
  return rest;
};

test("--dry-run prints the plan and writes nothing", () => {
  const w = world();
  const r = w.run(["apply", "build", "--for", "folder", "--dry-run"]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /Switches off \(1\): songwriting@melodic-software/);
  assert.match(r.stdout, /Left alone, from marketplaces this profile does not name \(1\): widget@vendor/);
  assert.match(r.stdout, /Not installed: debugging@melodic-software\. Install it with: claude plugin install debugging@melodic-software/);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual(w.records(), []);
});

test("with nobody to ask and no --yes, apply writes nothing and exits 1", () => {
  const w = world();
  const r = w.run(["apply", "build", "--for", "folder"]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /nobody to confirm/);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("AC1, AC16, AC17: apply writes the profile's entries, leaves the repository's and other marketplaces' plugins unmentioned, and changes no other key", () => {
  const w = world();
  const r = w.run(["apply", "build", "--for", "folder", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  const after = JSON.parse(w.read());
  assert.equal(after.enabledPlugins[`songwriting@${M}`], false);
  assert.equal(after.enabledPlugins[`review@${M}`], true);
  assert.equal(after.enabledPlugins[`guardrails@${M}`], true);
  assert.equal(`toolchain@${M}` in after.enabledPlugins, false, "a repository-enabled plugin stays unmentioned");
  assert.equal("widget@vendor" in after.enabledPlugins, false, "a plugin of another marketplace is never written");
  assert.deepEqual(withoutProfileKeys(w.read()), withoutProfileKeys(LOCAL_BEFORE));
});

test("AC19: clear after apply restores the file byte for byte", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const r = w.run(["clear", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual(w.records(), []);
});

test("AC19: with no settings file before the apply, clear removes the file", () => {
  const w = world({ local: null });
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.notEqual(w.read(), null);
  assert.equal(w.run(["clear", "--yes"]).status, 0);
  assert.equal(existsSync(w.localFile), false);
  assert.equal(existsSync(dirname(w.localFile)), true, "a .claude folder that was there before stays");
});

test("#16914: clear removes the .claude folder the first apply created, only while nothing else is in it", () => {
  const w = world({ local: null });
  rmSync(dirname(w.localFile), { recursive: true });
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(w.run(["apply", "review", "--for", "folder", "--yes"]).status, 0);
  const dry = w.run(["clear", "--dry-run"]);
  assert.match(dry.stdout, /Removes the file, and its folder when nothing else is in it, which the first apply created\./);
  assert.equal(w.run(["clear", "--yes"]).status, 0);
  assert.equal(existsSync(dirname(w.localFile)), false);
  const kept = world({ local: null });
  rmSync(dirname(kept.localFile), { recursive: true });
  assert.equal(kept.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  writeFileSync(join(dirname(kept.localFile), "settings.json"), "{}\n");
  assert.equal(kept.run(["clear", "--yes"]).status, 0);
  assert.equal(existsSync(join(dirname(kept.localFile), "settings.json")), true, "a file added since keeps the folder");
});

test("a second apply over a first keeps the first apply's before-values, so clear still restores the original", () => {
  const w = world();
  writeTree(w.home, { ".claude/plugin-profiles/notes.yaml": `plugins: [songwriting@${M}]\n` });
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(w.run(["apply", "notes", "--for", "folder", "--yes"]).status, 0);
  const after = JSON.parse(w.read());
  assert.equal(after.enabledPlugins[`songwriting@${M}`], true);
  assert.equal(after.enabledPlugins[`implementation@${M}`], false);
  assert.equal(w.run(["clear", "--yes"]).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("a second apply previews what it switches against the folder as it is now, not as it was before the first apply", () => {
  const w = world();
  writeTree(w.home, { ".claude/plugin-profiles/notes.yaml": `plugins: [songwriting@${M}]\n` });
  writeTree(w.root, { "installs/songwriting/.mcp.json": { mcpServers: { x: { command: "x" } } } });
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const preview = JSON.parse(w.run(["apply", "notes", "--for", "folder", "--dry-run", "--json"]).stdout);
  assert.ok(preview.enabled.includes(`songwriting@${M}`), `build switched songwriting off, so notes switches it on: ${preview.enabled}`);
  assert.deepEqual(preview.mcpOrLspOn, [`songwriting@${M}`]);
  assert.ok(preview.disabled.includes(`implementation@${M}`), `build switched implementation on, so notes switches it off: ${preview.disabled}`);
});

const IGNORED_REMOVE = (file) =>
  `Ignored, from ${file}: remove guardrails@${M}. A repository profile cannot switch off an always-on member; a user-level profile can.`;

test("a repository always-on.yaml that removes guardrails is ignored for that line: a folder apply keeps guardrails on and says why", () => {
  const w = world();
  const file = join(w.project, "docs", "conventions", "plugin-profiles", "always-on.yaml");
  writeTree(w.project, { "docs/conventions/plugin-profiles/always-on.yaml": `remove: [guardrails@${M}]\n` });
  const r = w.run(["apply", "build", "--for", "folder", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(JSON.parse(w.read()).enabledPlugins[`guardrails@${M}`], true);
  assert.ok(r.stdout.split("\n").includes(IGNORED_REMOVE(file)), r.stdout);
});

test("a repository profile's exclude of an always-on member is ignored, and the rest of that profile still applies", () => {
  const w = world();
  const file = join(w.project, "docs", "conventions", "plugin-profiles", "build.yaml");
  writeTree(w.project, { "docs/conventions/plugin-profiles/build.yaml": `exclude: [guardrails@${M}, review@${M}]\n` });
  const r = w.run(["apply", "build", "--for", "folder", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  const after = JSON.parse(w.read()).enabledPlugins;
  assert.equal(after[`guardrails@${M}`], true);
  assert.equal(after[`review@${M}`], false, "an exclude of a member that is not always-on still applies");
  assert.ok(r.stdout.includes(`Ignored, from ${file}: exclude guardrails@${M}.`), r.stdout);
});

test("a user-level always-on.yaml can still remove an always-on member", () => {
  const w = world();
  writeTree(w.home, { ".claude/plugin-profiles/always-on.yaml": `remove: [guardrails@${M}]\n` });
  const r = w.run(["apply", "build", "--for", "folder", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(JSON.parse(w.read()).enabledPlugins[`guardrails@${M}`], false);
  assert.doesNotMatch(r.stdout, /Ignored, from/);
});

test("apply --dry-run --json carries the ignored repository entries and marks what a repository profile switches on and hides", () => {
  const w = world();
  const dir = join(w.project, "docs", "conventions", "plugin-profiles");
  writeTree(w.project, {
    "docs/conventions/plugin-profiles/always-on.yaml": `remove: [guardrails@${M}]\n`,
    "docs/conventions/plugin-profiles/notes.yaml": `plugins: [songwriting@${M}, review@${M}]\nhide_skills: [stray-skill]\n`,
  });
  writeTree(w.home, { ".claude/plugin-profiles/notes.yaml": `plugins: [review@${M}]\n` });
  const preview = JSON.parse(w.run(["apply", "notes", "--for", "folder", "--dry-run", "--json"]).stdout);
  assert.deepEqual(preview.ignored, [{ file: join(dir, "always-on.yaml"), list: "remove", id: `guardrails@${M}` }]);
  assert.deepEqual(preview.repositoryOn, [], "songwriting is already on in the folder, so nothing a repository named switches on");
  assert.deepEqual(preview.repositorySkills, ["stray-skill"]);
  assert.ok(preview.lines.includes(IGNORED_REMOVE(join(dir, "always-on.yaml"))), preview.lines.join("\n"));
  assert.ok(preview.lines.includes("Hides skills a repository profile names: stray-skill"), preview.lines.join("\n"));
  const local = JSON.parse(w.read());
  local.enabledPlugins[`songwriting@${M}`] = false;
  writeFileSync(w.localFile, JSON.stringify(local));
  const again = JSON.parse(w.run(["apply", "notes", "--for", "folder", "--dry-run", "--json"]).stdout);
  assert.deepEqual(again.repositoryOn, [`songwriting@${M}`], "review is named by the user's notes.yaml too, so it is not marked");
  assert.ok(again.lines.some((l) => l.startsWith("Switches on (") && l.includes(`songwriting@${M} (from a repository profile)`)), again.lines.join("\n"));
});

test("a repository profile shapes the folder but never the user settings an initial apply writes", () => {
  const w = world({ local: null });
  writeTree(w.project, { "docs/conventions/plugin-profiles/build.yaml": `plugins: [songwriting@${M}]\n` });
  assert.doesNotMatch(w.run(["apply", "build", "--for", "folder", "--dry-run"]).stdout, /Switches off \(\d+\):.*songwriting/);
  const r = w.run(["apply", "build", "--for", "initial", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(JSON.parse(readFileSync(join(w.home, ".claude", "settings.json"), "utf8")).enabledPlugins[`songwriting@${M}`], false);
});

const settingsFiles = (w) => [join(w.home, ".claude", "settings.json"), join(w.project, ".claude", "settings.json"), w.localFile];
const snapshot = (files) => files.map((f) => (existsSync(f) ? readFileSync(f) : null));

test("AC2: a one-session apply writes a --settings file naming the profile, says to pass it again on resume, and leaves every settings file byte-identical", () => {
  const w = world();
  const before = snapshot(settingsFiles(w));
  const r = w.run(["apply", "build", "--for", "session", "--yes"], { CLAUDECODE: "1", CLAUDE_CODE_ENTRYPOINT: "cli" });
  assert.equal(r.status, 0, r.stderr);
  const sessionFile = /claude --settings "(.+)"/.exec(r.stdout)[1];
  const session = JSON.parse(readFileSync(sessionFile, "utf8"));
  assert.equal(session.env.PLUGIN_PROFILES_SESSION, "build");
  assert.equal(session.env.SESSION_SETTINGS_FILE, sessionFile, "the prerequisite readers read the file as the session layer");
  assert.equal(session.enabledPlugins[`songwriting@${M}`], false);
  assert.match(r.stdout, /A resumed session does not keep --settings; resume it with: claude --resume <session id>/);
  assert.deepEqual(snapshot(settingsFiles(w)), before);
  assert.deepEqual(w.records(), [], "a one-session apply records no folder profile");
});

test("regenerating a one-session file drops the entries the profile no longer writes", () => {
  const w = world();
  const profile = (text) => writeTree(w.home, { ".claude/plugin-profiles/notes.yaml": text });
  const regenerate = () => {
    const r = w.run(["apply", "notes", "--for", "session", "--yes"]);
    assert.equal(r.status, 0, r.stderr);
    return JSON.parse(readFileSync(/claude --settings "(.+)"/.exec(r.stdout)[1], "utf8"));
  };
  profile(`plugins: [songwriting@${M}, widget@vendor]\nhide_skills: [review:fanout]\n`);
  const first = regenerate();
  assert.equal(first.enabledPlugins["widget@vendor"], true);
  assert.equal(first.skillOverrides["review:fanout"], "off");
  profile(`plugins: [songwriting@${M}]\n`);
  const second = regenerate();
  assert.equal("widget@vendor" in second.enabledPlugins, false, "a marketplace the profile no longer names leaves the file");
  assert.equal("review:fanout" in (second.skillOverrides ?? {}), false, "a skill no longer hidden leaves the file");
  assert.equal(second.enabledPlugins[`songwriting@${M}`], true);
});

const launchJson = (w, args, extra = {}) => {
  const r = w.run(["launch", ...args, "--json"], extra);
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
};

test("launch writes one file per folder and profile, asks nothing, changes no settings file, and prints a command that clears an inherited marker", () => {
  const w = world();
  const before = snapshot(settingsFiles(w));
  const first = launchJson(w, ["build"]);
  assert.deepEqual(first.argv, ["env", "-u", "PLUGIN_PROFILES_SESSION", "-u", "PLUGIN_PROFILES_SESSION_FILE", "-u", "SESSION_SETTINGS_FILE", "claude", "--settings", first.file]);
  const session = JSON.parse(readFileSync(first.file, "utf8"));
  assert.equal(session.env.PLUGIN_PROFILES_SESSION, "build");
  assert.equal(session.enabledPlugins[`songwriting@${M}`], false);
  assert.equal(launchJson(w, ["build"]).file, first.file, "the same folder and profile reuse one file");
  const other = join(w.root, "other");
  writeTree(other, { "keep.txt": "x" });
  assert.notEqual(launchJson(w, ["build", "--folder", other]).file, first.file, "another folder gets its own file");
  assert.deepEqual(snapshot(settingsFiles(w)), before);
});

test("launch with no name takes this session's profile, else the folder's, else carries none", () => {
  const w = world();
  assert.equal(launchJson(w, [], { PLUGIN_PROFILES_SESSION: "build" }).profile, "build");
  const none = launchJson(w, []);
  assert.equal(none.profile, null);
  assert.deepEqual(none.argv, ["env", "-u", "PLUGIN_PROFILES_SESSION", "-u", "PLUGIN_PROFILES_SESSION_FILE", "-u", "SESSION_SETTINGS_FILE", "claude"]);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(launchJson(w, []).profile, "build");
});

test("launch --with merges a launcher's settings into one file the profile wins in, keyed apart from the plain file", () => {
  const w = world();
  const plain = launchJson(w, ["build"]).file;
  const own = JSON.stringify({ model: "opus", env: { LANE: "1" }, enabledPlugins: { [`songwriting@${M}`]: true, "widget@vendor": true } });
  const merged = launchJson(w, ["build", "--with", own]);
  assert.notEqual(merged.file, plain);
  const doc = JSON.parse(readFileSync(merged.file, "utf8"));
  assert.equal(doc.model, "opus");
  assert.deepEqual(doc.env, { LANE: "1", PLUGIN_PROFILES_SESSION: "build", PLUGIN_PROFILES_SESSION_FILE: merged.file, SESSION_SETTINGS_FILE: merged.file });
  assert.equal(doc.enabledPlugins[`songwriting@${M}`], false, "the profile's entry wins");
  assert.equal(doc.enabledPlugins["widget@vendor"], true, "an entry the profile leaves alone stays");
  assert.equal(JSON.parse(readFileSync(plain, "utf8")).model, undefined, "the plain file is unchanged");
  const noProfile = launchJson(w, ["--with", own], { PLUGIN_PROFILES_SESSION: "" });
  assert.deepEqual(noProfile.argv.slice(-2), ["--settings", own], "with no profile the launcher's own settings pass through");
});

test("apply without --for is a usage error and writes nothing, so a folder shared by other sessions is never chosen by default", () => {
  const w = world();
  const r = w.run(["apply", "build", "--yes"]);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /--for takes session, folder, initial/);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual(w.records(), []);
});

test("status in a session from a merged launch names the merged file it was started with", () => {
  const w = world();
  const merged = launchJson(w, ["build", "--with", JSON.stringify({ model: "opus" })]);
  const { env } = JSON.parse(readFileSync(merged.file, "utf8"));
  assert.equal(env.PLUGIN_PROFILES_SESSION_FILE, merged.file, "the file names itself");
  const r = w.run(["status"], env);
  assert.equal(r.status, 0, r.stderr);
  assert.ok(r.stdout.includes("resume it with: claude --resume <session id>"), r.stdout);
});

test("launch from a VS Code or Desktop session still writes the file and prints a command, since it starts a CLI session", () => {
  const w = world();
  for (const entry of ["claude-vscode", "claude-desktop"]) {
    const r = launchJson(w, ["build"], { CLAUDECODE: "1", CLAUDE_CODE_ENTRYPOINT: entry });
    assert.equal(r.profile, "build", entry);
    assert.ok(existsSync(r.file), entry);
  }
});

test("launch removes session files no launch has written for 30 days", () => {
  const w = world();
  const file = launchJson(w, ["build"]).file;
  const stale = join(dirname(file), "stale.json");
  writeFileSync(stale, "{}");
  const old = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000);
  utimesSync(stale, old, old);
  launchJson(w, ["build"]);
  assert.equal(existsSync(stale), false);
  assert.equal(existsSync(file), true);
});

test("an unattended launch whose profile misses a required prerequisite stops and writes nothing; an attended one says so and goes ahead", () => {
  const w = world({ prerequisiteMissing: true });
  const r = w.run(["launch", "build", "--unattended"]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /not launched: profile build switches on a plugin missing a required prerequisite/);
  assert.match(r.stderr, /pp-absent-tool/);
  assert.equal(existsSync(join(w.home, ".claude", "plugins", "data", "plugin-profiles-inline", "sessions")), false);
  const attended = w.run(["launch", "build"]);
  assert.equal(attended.status, 0, attended.stderr);
  assert.match(attended.stderr, /Missing required prerequisite of implementation@melodic-software/);
  assert.match(attended.stdout, /Start the session with: env -u PLUGIN_PROFILES_SESSION -u PLUGIN_PROFILES_SESSION_FILE -u SESSION_SETTINGS_FILE claude --settings /);
});

test("status prints the command that starts another session in the profile in force", () => {
  const w = world();
  assert.doesNotMatch(w.run(["status"]).stdout, /Start another session/);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.match(w.run(["status"]).stdout, /Start another session here in this profile with: claude --profile build \(or node \S*profiles\.mjs launch build --folder \S+\)/);
  assert.match(w.run(["status"], { PLUGIN_PROFILES_SESSION: "review" }).stdout, /claude --profile review \(or node \S*profiles\.mjs launch review --folder \S+\)/);
});

test("Q69: on VS Code a one-session apply is refused with the folder offer and writes nothing", () => {
  const w = world();
  const before = snapshot(settingsFiles(w));
  const r = w.run(["apply", "build", "--for", "session", "--yes"], { CLAUDECODE: "1", CLAUDE_CODE_ENTRYPOINT: "claude-vscode" });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /--for session is not available on VS Code; apply it to this folder instead: apply build --for folder/);
  assert.equal(existsSync(join(w.home, ".claude", "plugins", "data", "plugin-profiles-inline", "sessions")), false);
  assert.deepEqual(snapshot(settingsFiles(w)), before);
});

const CLOUD = { CLAUDECODE: "1", CLAUDE_CODE_REMOTE: "true", CLAUDE_CODE_ENTRYPOINT: "remote" };
const DESKTOP_WSL = { CLAUDECODE: "1", CLAUDE_CODE_ENTRYPOINT: "claude-desktop", WSL_DISTRO_NAME: "Ubuntu" };

test("Q69: cloud and Desktop WSL sessions: status says plugin profiles do not apply, and apply, clear and install write nothing", () => {
  for (const [surface, env] of [["a cloud session", CLOUD], ["a Claude Desktop WSL session", DESKTOP_WSL]]) {
    const w = world();
    const before = snapshot(settingsFiles(w));
    assert.match(w.run(["status"], env).stdout, new RegExp(`Surface: ${surface}; plugin profiles do not apply here and nothing is written`));
    for (const args of [["apply", "build", "--for", "folder", "--yes"], ["apply", "build", "--for", "initial", "--yes"], ["clear", "--yes"], ["install", `debugging@${M}`, "--yes"]]) {
      const r = w.run(args, env);
      assert.equal(r.status, 1, `${surface}: ${args.join(" ")}`);
      assert.match(r.stderr, /plugin profiles do not apply here/);
    }
    assert.deepEqual(snapshot(settingsFiles(w)), before, surface);
    assert.deepEqual(w.records(), [], surface);
    assert.equal(w.calls().includes("plugin install"), false, surface);
  }
});

test("status names the session's surface", () => {
  const w = world();
  for (const [entry, line] of [["cli", "Surface: the Claude Code CLI (applies --for session, folder, initial)."], ["claude-vscode", "Surface: VS Code (applies --for folder, initial)."], ["claude-desktop", "Surface: Claude Desktop (applies --for folder, initial)."]]) {
    const env = { CLAUDECODE: "1", CLAUDE_CODE_ENTRYPOINT: entry };
    assert.ok(w.run(["status"], env).stdout.split("\n").includes(line), entry);
    assert.equal(JSON.parse(w.run(["status", "--json"], env).stdout).surface.id, entry);
  }
});

test("#16432: apply --for initial sets the initial profile in user settings, status --for initial names it, and clear --for initial puts user settings back", () => {
  const w = world({ local: null });
  const userFile = join(w.home, ".claude", "settings.json");
  const before = readFileSync(userFile, "utf8");
  const r = w.run(["apply", "build", "--for", "initial", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  const user = JSON.parse(readFileSync(userFile, "utf8"));
  assert.equal(user.enabledPlugins[`implementation@${M}`], true, "a build member is on in user settings");
  assert.equal(user.enabledPlugins[`songwriting@${M}`], false);
  assert.equal(user.theme, "dark");
  assert.equal(existsSync(w.localFile), false, "an initial apply writes no folder file");
  const s = JSON.parse(w.run(["status", "--for", "initial", "--json"]).stdout);
  assert.deepEqual([s.profile, s.target, s.settingsFile], ["build", "initial", userFile]);
  assert.equal(w.run(["clear", "--for", "initial", "--yes"]).status, 0);
  assert.equal(readFileSync(userFile, "utf8"), before);
});

test("inside Claude Code with no known entrypoint, status reads surface not detected and only a folder apply runs", () => {
  const w = world();
  const unknown = { CLAUDECODE: "1" };
  assert.match(w.run(["status"], unknown).stdout, /Surface: surface not detected \(applies --for folder\)/);
  assert.equal(w.run(["apply", "build", "--for", "initial", "--yes"], unknown).status, 1);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"], unknown).status, 0);
});

/** Writes plugins/installed_plugins.json, the registry the session-start notice reads, from the stub's list plus extra ids. */
function installOnDisk(w, extra = []) {
  const list = JSON.parse(readFileSync(w.env.PP_STUB_LIST, "utf8"));
  const plugins = Object.fromEntries(list.map((r) => [r.id, [{ scope: r.scope, installPath: r.installPath, version: r.version }]]));
  for (const id of extra) plugins[id] = [{ scope: "user", installPath: w.root, version: "1.0.0" }];
  writeTree(w.home, { ".claude/plugins/installed_plugins.json": { version: 2, plugins } });
}

const sessionStart = (w, extra = {}, cli = CLI) => {
  writeFileSync(w.env.PP_STUB_CALLS, "");
  const r = w.run(["status", "--session-start"], { CLAUDECODE: "1", CLAUDE_CODE_ENTRYPOINT: "cli", ...extra }, cli);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stderr, "");
  assert.equal(w.calls(), "", "status --session-start started the stub claude");
  return r.stdout;
};

test("the session-start notice prints nothing in a folder with no applied profile, and speaks once one is applied", () => {
  const w = world();
  installOnDisk(w);
  assert.equal(sessionStart(w), "");
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.match(JSON.parse(sessionStart(w)).systemMessage, /Profile build applies here/);
});

test("Q69: in cloud and Desktop WSL sessions the session-start notice prints nothing and writes nothing, even where a profile is applied", () => {
  const w = world();
  installOnDisk(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.match(JSON.parse(sessionStart(w)).systemMessage, /Profile build applies here/, "on the CLI the notice speaks");
  const before = snapshot(settingsFiles(w));
  const records = w.records();
  for (const env of [CLOUD, DESKTOP_WSL]) assert.equal(sessionStart(w, env), "", env.CLAUDE_CODE_ENTRYPOINT);
  assert.deepEqual(snapshot(settingsFiles(w)), before);
  assert.deepEqual(w.records(), records);
});

test("B8: the session-start notice names the folder's profile on its own line, and on the CLI no surface or commands", () => {
  const w = world();
  installOnDisk(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const message = JSON.parse(sessionStart(w)).systemMessage;
  assert.match(message, /^Profile build applies here \(.+settings\.local\.json\)\.$/m);
  assert.doesNotMatch(message, /Surface:/);
  assert.doesNotMatch(message, /Start another session/);
  assert.doesNotMatch(message, /Differs from the profile/);
});

test("AC22: a plugin installed after the apply is named by the session-start notice", () => {
  const w = world();
  installOnDisk(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  installOnDisk(w, [`writing@${M}`]);
  assert.match(JSON.parse(sessionStart(w)).systemMessage, /Installed since the profile was applied: writing@melodic-software/);
});

test("a session started from a one-session file is named by status, with the flag to pass again on resume", () => {
  const w = world();
  installOnDisk(w);
  const file = /claude --settings "(.+)"/.exec(w.run(["apply", "build", "--for", "session", "--yes"]).stdout)[1];
  const message = JSON.parse(sessionStart(w, { PLUGIN_PROFILES_SESSION: "build" })).systemMessage;
  assert.match(message, /^This session runs in profile build\.$/m);
  assert.ok(existsSync(file), file);
  assert.match(message, /^Resume it in that profile with: claude --resume <session id>$/m);
  assert.doesNotMatch(message, /No profile is recorded/);
  assert.doesNotMatch(message, /Surface:/);
});

/** Copies this plugin into the plugin-cache layout under the temp HOME, so its options come from that HOME's settings.json. */
function installedCopy(w, options) {
  const root = join(w.home, ".claude", "plugins", "cache", M, "plugin-profiles", "0.0.0");
  cpSync(join(HERE, ".."), root, { recursive: true });
  const userFile = join(w.home, ".claude", "settings.json");
  const doc = JSON.parse(readFileSync(userFile, "utf8"));
  doc.pluginConfigs = { [`plugin-profiles@${M}`]: { options } };
  writeFileSync(userFile, `${JSON.stringify(doc, null, 2)}\n`);
  return join(root, "scripts", "profiles.mjs");
}

test("AC13: with remember_folder_profile false a folder apply is refused, writes nothing, and points at a one-session or initial apply", () => {
  const w = world();
  const cli = installedCopy(w, { remember_folder_profile: false });
  const before = snapshot(settingsFiles(w));
  const r = w.run(["apply", "build", "--for", "folder", "--yes"], {}, cli);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /folder remembering is off/);
  assert.match(r.stderr, /apply build --for session/);
  assert.deepEqual(snapshot(settingsFiles(w)), before);
  assert.equal(w.run(["apply", "build", "--for", "session", "--yes"], {}, cli).status, 0);
});

test("AC13: with remember_folder_profile false the notice names the initial profile and a folder profile left from before as not in force", () => {
  const w = world();
  installOnDisk(w);
  const on = installedCopy(w, { remember_folder_profile: true });
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"], {}, on).status, 0);
  const initial = w.run(["apply", "review", "--for", "initial", "--yes"], {}, on);
  assert.equal(initial.status, 0, initial.stderr);
  const off = installedCopy(w, { remember_folder_profile: false });
  const message = JSON.parse(sessionStart(w, {}, off)).systemMessage;
  assert.match(message, /Folder remembering is off: sessions start from the initial profile review/);
  assert.match(message, /This folder still holds the entries of profile build; run clear to remove them/);
  assert.doesNotMatch(message, /Profile build \(folder\)/);
});

test("AC8: a write that fails partway leaves the settings file and the record as they were", { skip: process.platform === "win32" || process.getuid?.() === 0 }, () => {
  const w = world();
  const dir = dirname(w.localFile);
  chmodSync(dir, 0o555);
  try {
    const r = w.run(["apply", "build", "--for", "folder", "--yes"]);
    assert.notEqual(r.status, 0);
    assert.equal(w.read(), LOCAL_BEFORE);
    assert.deepEqual(w.records(), []);
    assert.deepEqual(readdirSync(dir).sort(), ["settings.json", "settings.local.json"]);
  } finally {
    chmodSync(dir, 0o755);
  }
});

test("AC21: one concurrent write is re-planned over and kept", () => {
  const w = world();
  const r = w.run(["apply", "build", "--for", "folder", "--yes"], { PP_STUB_TOUCH: w.localFile, PP_STUB_TOUCH_TIMES: "1" });
  assert.equal(r.status, 0, r.stderr);
  const after = JSON.parse(w.read());
  assert.deepEqual(after.permissions.allow, ["Bash(npm test)", "Bash(stub-writer-1)"]);
  assert.equal(after.enabledPlugins[`songwriting@${M}`], false);
});

test("AC21: a writer that keeps changing the file makes apply fail with the file as that writer left it", () => {
  const w = world();
  const r = w.run(["apply", "build", "--for", "folder", "--yes"], { PP_STUB_TOUCH: w.localFile, PP_STUB_TOUCH_TIMES: "9" });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /kept changing/);
  const after = JSON.parse(w.read());
  assert.deepEqual(after.permissions.allow, ["Bash(npm test)", "Bash(stub-writer-1)", "Bash(stub-writer-2)"]);
  assert.deepEqual(after.enabledPlugins, JSON.parse(LOCAL_BEFORE).enabledPlugins);
  assert.deepEqual(w.records(), []);
});

test("D8: a switch cut off after its first write is recorded off-pending, named by status, and finished by the next apply", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes", "--defer-off"]).status, 0);
  assert.equal(JSON.parse(w.read()).enabledPlugins[`songwriting@${M}`], true, "the off entry waits");
  const pending = JSON.parse(w.run(["status", "--json"]).stdout);
  assert.equal(pending.phase, "off-pending");
  assert.deepEqual(pending.pending, [`songwriting@${M}`]);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(JSON.parse(w.read()).enabledPlugins[`songwriting@${M}`], false);
  const done = JSON.parse(w.run(["status", "--json"]).stdout);
  assert.equal(done.phase, "applied");
  assert.deepEqual(done.pending, []);
  assert.equal(w.run(["clear", "--yes"]).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("AC11: --defer-off also holds back the off entry of a plugin that only user settings switch on", () => {
  const w = world({ local: null });
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes", "--defer-off"]).status, 0);
  assert.equal(JSON.parse(w.read()).enabledPlugins[`songwriting@${M}`], undefined, "the first write leaves songwriting on through user settings");
  assert.deepEqual(JSON.parse(w.run(["status", "--json"]).stdout).pending, [`songwriting@${M}`]);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(JSON.parse(w.read()).enabledPlugins[`songwriting@${M}`], false);
});

test("AC12: status names the folder's profile and every entry that differs from it, and AC22 plugins installed since", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const doc = JSON.parse(w.read());
  doc.enabledPlugins[`implementation@${M}`] = false;
  writeFileSync(w.localFile, `${JSON.stringify(doc, null, 2)}\n`);
  const list = JSON.parse(readFileSync(w.env.PP_STUB_LIST, "utf8"));
  writeFileSync(w.env.PP_STUB_LIST, JSON.stringify([...list, { id: `writing@${M}`, version: "1.0.0", scope: "user", installPath: w.root }]));
  const s = JSON.parse(w.run(["status", "--json"]).stdout);
  assert.equal(s.profile, "build");
  assert.deepEqual(s.differs, [{ name: `implementation@${M}`, recorded: true, current: false }]);
  assert.deepEqual(s.installedSince, [`writing@${M}`]);
});

test("D4: status --session-start reads installed plugins from disk and never starts claude", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes", "--defer-off"]).status, 0);
  assert.match(JSON.parse(sessionStart(w)).systemMessage, /stay on until apply build --for folder runs again: songwriting@melodic-software/);
});

test("AC26: a plugin it switches on with a missing required prerequisite stops apply --yes, and the preview names the tool, its install line and the consequence", () => {
  const w = world({ prerequisiteMissing: true });
  const r = w.run(["apply", "build", "--for", "folder", "--yes"]);
  assert.equal(r.status, 1);
  assert.match(r.stdout, /Missing required prerequisite of implementation@melodic-software: pp-absent-tool: pp-absent-tool-zz9 was not found on PATH\./);
  assert.match(r.stdout, /Without pp-absent-tool, implementation cannot build anything\. Install \(docs: https:\/\/example\.com\/pp-absent-tool\)\./);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual(w.records(), []);
});

const SHIPPED = join(HERE, "..", "profiles");

test("AC5: check passes on the shipped profiles against the repository catalog and starts no claude", () => {
  const w = world();
  const r = w.run(["check"]);
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /Profile check passed against the melodic-software catalog\./);
  assert.equal(w.calls(), "", "the stub claude was called");
});

test("AC5: check exits 1 when a shipped build.yaml names nope@melodic-software", () => {
  const w = world();
  const shipped = join(w.root, "shipped");
  cpSync(SHIPPED, shipped, { recursive: true });
  writeFileSync(join(shipped, "build.yaml"), `${readFileSync(join(shipped, "build.yaml"), "utf8")}  - nope@${M}\n`);
  const r = w.run(["check", "--shipped", shipped]);
  assert.equal(r.status, 1, r.stdout + r.stderr);
  assert.match(r.stderr, /FAIL: .*build\.yaml: plugins names nope@melodic-software, which is not in the catalog melodic-software/);
  assert.doesNotMatch(r.stdout, /nope@/, "a finding goes to stderr only");
});

test("AC5: check reports an installed plugin no profile names and still exits 0", () => {
  const w = world();
  writeTree(w.home, { ".claude/plugins/installed_plugins.json": { version: 2, plugins: { [`songwriting@${M}`]: [{ scope: "user", installPath: w.root, version: "1.0.0" }] } } });
  const r = w.run(["check"]);
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /Report: Installed, and no profile names it \(an apply switches it off unless the repository enables it\): songwriting@melodic-software/);
});

test("AC5: check reports a malformed user or repository profile by its path, checks the other levels, and still exits 0", () => {
  const w = world();
  const userFile = join(w.home, ".claude", "plugin-profiles", "broken.yaml");
  const repoFile = join(w.project, "docs", "conventions", "plugin-profiles", "team.yaml");
  writeTree(w.root, { "home/.claude/plugin-profiles/broken.yaml": "plugins: notalist\n", "project/docs/conventions/plugin-profiles/team.yaml": "plugins:\n  - ghost@vendor\n" });
  const r = w.run(["check"]);
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.ok(r.stdout.includes(`Report: ${userFile}: plugins must be a list of names`), r.stdout + r.stderr);
  assert.ok(r.stdout.includes(`Report: ${repoFile}: ghost@vendor is not installed. Install it with: claude plugin install ghost@vendor`), r.stdout + r.stderr);
  assert.match(r.stdout, /Profile check passed against the melodic-software catalog\./);

  writeTree(w.root, { "project/docs/conventions/plugin-profiles/team.yaml": "flavor: blue\n" });
  const both = w.run(["check"]);
  assert.equal(both.status, 0, both.stdout + both.stderr);
  assert.ok(both.stdout.includes(`Report: ${repoFile}: unknown key "flavor"`), both.stdout + both.stderr);
});

test("check exits 2 naming the file when a shipped profile is malformed", () => {
  const w = world();
  const shipped = join(w.root, "shipped");
  cpSync(SHIPPED, shipped, { recursive: true });
  writeFileSync(join(shipped, "build.yaml"), "plugins: notalist\n");
  const r = w.run(["check", "--shipped", shipped]);
  assert.equal(r.status, 2, r.stdout + r.stderr);
  assert.ok(r.stderr.includes(`${join(shipped, "build.yaml")}: plugins must be a list of names`), r.stderr);
});

test("check in a cached install reads the catalog of the marketplace it was installed from", () => {
  const w = world();
  const cli = installedCopy(w, {});
  const market = join(w.root, "market");
  cpSync(join(HERE, "..", "..", "..", ".claude-plugin", "marketplace.json"), join(market, ".claude-plugin", "marketplace.json"));
  writeTree(w.home, { ".claude/plugins/known_marketplaces.json": { [M]: { source: { source: "github", repo: "melodic-software/claude-code-plugins" }, installLocation: market } } });
  const r = w.run(["check"], {}, cli);
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.match(r.stdout, /Profile check passed against the melodic-software catalog\./);
});

test("apply always-on --for initial switches on the always-on members alone in user settings", () => {
  const w = world({ local: null });
  const r = w.run(["apply", "always-on", "--for", "initial", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  const user = JSON.parse(readFileSync(join(w.home, ".claude", "settings.json"), "utf8")).enabledPlugins;
  assert.equal(user[`guardrails@${M}`], true);
  assert.equal(user[`implementation@${M}`], false, "a build member is not in the initial profile");
  assert.equal(user[`songwriting@${M}`], false);
});

test("clear previews like apply: --dry-run and a run with nobody to confirm write nothing, --yes restores", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const applied = w.read();
  const preview = w.run(["clear", "--dry-run"]);
  assert.equal(preview.status, 0, preview.stderr);
  assert.match(preview.stdout, /Clears profile build from .*settings\.local\.json/);
  assert.equal(w.read(), applied);
  const unconfirmed = w.run(["clear"]);
  assert.equal(unconfirmed.status, 1);
  assert.match(unconfirmed.stderr, /nobody to confirm/);
  assert.equal(w.read(), applied);
  assert.equal(w.run(["clear", "--yes"]).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("list --json names every shipped profile but always-on, which every profile includes, each with its description", () => {
  const w = world();
  const r = w.run(["list", "--json"]);
  assert.equal(r.status, 0, r.stderr);
  const profiles = JSON.parse(r.stdout);
  assert.deepEqual(profiles.map((p) => p.name).sort(), ["build", "discovery", "harness-upkeep", "interface-design", "planning", "review"]);
  assert.equal(profiles.find((p) => p.name === "build").description, "Write the change, test, review, verify, open and merge the PR, and run lanes.");
});

test("list --json adds a repository profile to the shipped ones", () => {
  const w = world();
  writeTree(w.project, { "docs/conventions/plugin-profiles/songs.yaml": `description: Write songs.\nplugins: [songwriting@${M}]\n` });
  const names = JSON.parse(w.run(["list", "--json"]).stdout).map((p) => p.name);
  assert.ok(names.includes("songs"), names.join(", "));
});

test("AC6, AC10: apply --dry-run --json previews an in-session switch as data, names the MCP plugin it switches on, and writes nothing", () => {
  const w = world();
  writeTree(w.root, { "installs/implementation/.mcp.json": { mcpServers: { x: { command: "x" } } } });
  const r = w.run(["apply", "build", "--for", "folder", "--defer-off", "--dry-run", "--json"]);
  assert.equal(r.status, 0, r.stderr);
  const preview = JSON.parse(r.stdout);
  assert.equal(preview.profile, "build");
  assert.equal(preview.upToDate, false);
  assert.deepEqual(preview.mcpOrLspOn, [`implementation@${M}`]);
  assert.deepEqual(preview.pending, [`songwriting@${M}`]);
  assert.ok(preview.lines.includes(`Switches off (1): songwriting@${M}`), preview.lines.join("\n"));
  assert.ok(preview.lines.includes("Switched off in a second write, after the next reload (1): every plugin it switches off"), preview.lines.join("\n"));
  assert.ok(preview.lines.some((l) => /^Writes \d+ plugin entries and \d+ skill entries now, and 1 off entry in the second write\.$/.test(l)), preview.lines.join("\n"));
  assert.ok(preview.lines.includes(`Switches on plugins with an MCP or language server: implementation@${M}`), preview.lines.join("\n"));
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual(w.records(), []);
});

test("#16747: apply --dry-run --json counts the plugins left alone and gives a command that names them", () => {
  const w = world();
  const preview = JSON.parse(w.run(["apply", "build", "--for", "folder", "--defer-off", "--dry-run", "--json"]).stdout);
  assert.equal(preview.untouched, undefined);
  const hint = `Left alone, from marketplaces this profile does not name (1); to name them, run in a terminal: node "${CLI}" apply build --for folder --dry-run`;
  assert.ok(preview.lines.includes(hint), preview.lines.join("\n"));
  assert.ok(!preview.lines.some((line) => line.includes("widget@vendor")), preview.lines.join("\n"));
  const named = w.run(["apply", "build", "--for", "folder", "--dry-run"]);
  assert.match(named.stdout, /Left alone, from marketplaces this profile does not name \(1\): widget@vendor/);
});

test("#16747: clear --dry-run --json says whether a profile is recorded, as data and lines", () => {
  const w = world();
  const none = JSON.parse(w.run(["clear", "--dry-run", "--json"]).stdout);
  assert.equal(none.recorded, false);
  assert.equal(none.sessionProfile, null);
  assert.equal(none.lines.length, 1);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const some = JSON.parse(w.run(["clear", "--dry-run", "--json"]).stdout);
  assert.equal(some.recorded, true);
  assert.match(some.lines[0], /^Clears profile build from /);
  assert.equal(w.run(["clear", "--json"]).status, 2);
});

test("#16747: clear in a session started in a one-session profile says the session keeps it", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const env = { PLUGIN_PROFILES_SESSION: "review" };
  const preview = JSON.parse(w.run(["clear", "--dry-run", "--json"], env).stdout);
  assert.equal(preview.sessionProfile, "review");
  assert.ok(
    preview.lines.includes("This session runs in profile review from a one-session settings file and keeps it after the clear; new sessions in this folder start without a folder profile."),
    preview.lines.join("\n"),
  );
  assert.match(w.run(["clear", "--yes"], env).stdout, /keeps it after the clear/);
});

test("apply --dry-run --json reads upToDate once the profile is applied", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(JSON.parse(w.run(["apply", "build", "--for", "folder", "--dry-run", "--json"]).stdout).upToDate, true);
});

test("apply --defer-off --dry-run --json is not up to date while an off entry is still owed", () => {
  const w = world();
  assert.equal(w.run(["apply", "review", "--for", "folder", "--yes"]).status, 0);
  const list = JSON.parse(readFileSync(w.env.PP_STUB_LIST, "utf8"));
  writeFileSync(w.env.PP_STUB_LIST, JSON.stringify([...list, { id: `gaming@${M}`, version: "1.0.0", scope: "user", installPath: w.root }]));
  const userFile = join(w.home, ".claude", "settings.json");
  const user = JSON.parse(readFileSync(userFile, "utf8"));
  user.enabledPlugins[`gaming@${M}`] = true;
  writeFileSync(userFile, JSON.stringify(user));
  const preview = JSON.parse(w.run(["apply", "review", "--for", "folder", "--defer-off", "--dry-run", "--json"]).stdout);
  assert.deepEqual(preview.pending, [`gaming@${M}`], "a plugin newly on at user level that review does not name");
  assert.equal(preview.upToDate, false);
});

test("apply --json without --dry-run is a usage error and writes nothing", () => {
  const w = world();
  const r = w.run(["apply", "build", "--for", "folder", "--yes", "--json"]);
  assert.equal(r.status, 2);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("AC11: an in-session switch in a session started from a one-session file is refused with the way to start one, and writes nothing", () => {
  const w = world();
  const before = snapshot(settingsFiles(w));
  const r = w.run(["apply", "review", "--for", "folder", "--defer-off", "--yes"], { PLUGIN_PROFILES_SESSION: "build" });
  assert.equal(r.status, 1);
  assert.match(r.stderr, /this session runs in profile build from a one-session settings file/);
  assert.match(r.stderr, /apply review --for session/);
  assert.deepEqual(snapshot(settingsFiles(w)), before);
  assert.deepEqual(w.records(), []);
});

/** world() plus the marketplaces the stub claude knows; userFile is the temp user settings.json. */
function installWorld(opts = {}) {
  const w = world(opts);
  writeTree(w.root, { "marketplaces.json": [{ name: M, source: "github" }] });
  const extra = { PP_STUB_MARKETPLACES: join(w.root, "marketplaces.json") };
  const userFile = join(w.home, ".claude", "settings.json");
  const user = () => JSON.parse(readFileSync(userFile, "utf8"));
  return { ...w, install: (args, more = {}) => w.run(["install", ...args], { ...extra, ...more }), userFile, user };
}

const installCalls = (w) => w.calls().split("\n").filter((line) => line.startsWith("plugin install"));

test("AC4: with nobody to ask and no --yes, install installs nothing", () => {
  const w = installWorld();
  const r = w.install([`debugging@${M}`]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /nobody to confirm/);
  assert.deepEqual(installCalls(w), []);
});

test("AC4, AC20: an approved install runs at user scope and leaves the plugin off in user settings when the initial profile lacks it", () => {
  const w = installWorld();
  const r = w.install([`debugging@${M}`, "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(installCalls(w), [`plugin install debugging@${M} --scope user`]);
  assert.equal(w.user().enabledPlugins[`debugging@${M}`], false);
  assert.equal(w.user().theme, "dark", "other user settings keys are kept");
});

test("AC20: an installed plugin the initial profile includes stays on", () => {
  const w = installWorld();
  const r = w.install([`markdown-format@${M}`, "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(w.user().enabledPlugins[`markdown-format@${M}`], true);
  assert.match(r.stdout, /Leaves it on/);
});

test("AC4: install --dry-run says what it would run and installs nothing", () => {
  const w = installWorld();
  const r = w.install([`debugging@${M}`, "--dry-run"]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /claude plugin install debugging@melodic-software --scope user/);
  assert.match(r.stdout, /switches it off in/);
  assert.deepEqual(installCalls(w), []);
});

test("AC4: a plugin of a marketplace this machine does not know is not installed", () => {
  const w = installWorld();
  const r = w.install(["gadget@unknown-market", "--yes"]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /unknown-market marketplace is not known/);
  assert.deepEqual(installCalls(w), []);
});

test("AC4: a plugin only a repository profile names is not installed, even with --yes", () => {
  const w = installWorld();
  writeTree(w.project, { "docs/conventions/plugin-profiles/repo-only.yaml": `plugins: [lurker@${M}]\n` });
  const r = w.install([`lurker@${M}`, "--yes"]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /only a repository profile names lurker@melodic-software/);
  assert.deepEqual(installCalls(w), []);
});

test("AC4: an installed plugin is never installed again or updated", () => {
  const w = installWorld();
  const r = w.install([`review@${M}`, "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /already installed/);
  assert.deepEqual(installCalls(w), []);
});

test("a failed install leaves user settings as they were and exits 2 with claude's reason", () => {
  const w = installWorld();
  const before = readFileSync(w.userFile, "utf8");
  const r = w.install([`debugging@${M}`, "--yes"], { PP_STUB_INSTALL_FAIL: "network unreachable" });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /network unreachable/);
  assert.equal(readFileSync(w.userFile, "utf8"), before);
});

const userProfile = (w, name) => join(w.home, ".claude", "plugin-profiles", `${name}.yaml`);

test("AC15: save writes a user profile that list then names with its description", () => {
  const w = world();
  const r = w.run(["save", "notes", "--level", "user", "--description", "Write songs: lyrics, chords.", "--plugins", `songwriting@${M}, review@${M}`, "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /Creates .*notes\.yaml/);
  const listed = JSON.parse(w.run(["list", "--json"]).stdout).find((p) => p.name === "notes");
  assert.deepEqual(listed, { name: "notes", description: "Write songs: lyrics, chords." });
  const applied = w.run(["apply", "notes", "--for", "folder", "--dry-run"]);
  assert.match(applied.stdout, /Switches on \(\d+\): [^\n]*review@melodic-software/);
  assert.doesNotMatch(applied.stdout, /Switches off \(\d+\): [^\n]*songwriting@melodic-software/);
});

test("save adds to the lists of an existing file and keeps its description", () => {
  const w = world();
  writeTree(w.home, { ".claude/plugin-profiles/notes.yaml": `description: Notes.\nplugins:\n  - songwriting@${M}\n` });
  const r = w.run(["save", "notes", "--level", "user", "--plugins", `review@${M}`, "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(readFileSync(userProfile(w, "notes"), "utf8"), `description: "Notes."\nplugins:\n  - "songwriting@${M}"\n  - "review@${M}"\n`);
});

test("save with nobody to ask and no --yes writes nothing", () => {
  const w = world();
  const r = w.run(["save", "notes", "--level", "user", "--plugins", `review@${M}`]);
  assert.equal(r.status, 1);
  assert.equal(existsSync(userProfile(w, "notes")), false);
});

test("AC24: save refuses a profile that excludes an always-on member", () => {
  const w = world();
  const r = w.run(["save", "notes", "--level", "user", "--exclude", `guardrails@${M}`, "--yes"]);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /exclude always-on members: guardrails@melodic-software/);
  assert.equal(existsSync(userProfile(w, "notes")), false);
});

test("AC24: save at the repository level refuses a remove or exclude of an always-on member, since apply would ignore it", () => {
  const w = world();
  for (const args of [["always-on", "--remove"], ["notes", "--exclude"]]) {
    const r = w.run(["save", args[0], "--level", "repository", args[1], `guardrails@${M}`, "--yes"]);
    assert.equal(r.status, 2, args.join(" "));
    assert.match(r.stderr, /A repository profile cannot switch off an always-on member; a user-level profile can\./);
  }
  assert.equal(existsSync(join(w.project, "docs", "conventions", "plugin-profiles")), false);
});

test("AC25: a hook-shipping plugin answered always on is saved to the user's always-on file and stays on under every profile", () => {
  const w = world();
  writeTree(w.root, { "installs/songwriting/hooks/hooks.json": { hooks: { Stop: [] } } });
  assert.match(w.run(["inventory"]).stdout, /songwriting@melodic-software 1\.0\.0 ships hooks/);
  assert.match(w.run(["apply", "build", "--for", "folder", "--dry-run"]).stdout, /Switches off plugins that ship hooks or a mod: songwriting@melodic-software/);
  assert.equal(w.run(["save", "always-on", "--level", "user", "--plugins", `songwriting@${M}`, "--yes"]).status, 0);
  const r = w.run(["apply", "build", "--for", "folder", "--dry-run"]);
  assert.doesNotMatch(r.stdout, /Switches off \(\d+\): [^\n]*songwriting/);
});

test("save at the repository level writes under the repository's convention home", () => {
  const w = world();
  const r = w.run(["save", "notes", "--level", "repository", "--plugins", `songwriting@${M}`, "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(existsSync(join(w.project, "docs", "conventions", "plugin-profiles", "notes.yaml")), true);
});

test("usage says so when this machine has no usage history", () => {
  const w = world();
  const r = w.run(["usage"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim(), "No usage history was found on this machine.");
});

test("usage lists skills and plugins most used first and leaves out unused ones", () => {
  const w = world();
  writeTree(w.home, {
    ".claude.json": {
      skillUsage: { "review:fanout": { usageCount: 3, lastUsedAt: Date.UTC(2026, 10, 1) }, "testing:write": { usageCount: 9 }, "idle:skill": { usageCount: 0 } },
      pluginUsage: { [`review@${M}`]: { usageCount: 12 } },
    },
  });
  const u = JSON.parse(w.run(["usage", "--json"]).stdout);
  assert.deepEqual(u.skills.map((s) => [s.name, s.count]), [["testing:write", 9], ["review:fanout", 3]]);
  assert.equal(u.skills[1].lastUsedAt, "2026-11-01T00:00:00.000Z");
  assert.deepEqual(u.plugins.map((p) => p.name), [`review@${M}`]);
});

/** Makes w.project a main checkout, with a .git folder as git lays it out. */
const gitInit = (w) => writeTree(w.project, { ".git/HEAD": "ref: refs/heads/main\n" });

/** A linked git worktree of w.project, laid out as git writes it, with an optional settings.local.json of its own. */
function linkedWorktree(w, local = null) {
  const wt = join(w.root, "wt");
  writeTree(w.project, { ".git/worktrees/wt/commondir": "../..\n", ".git/worktrees/wt/gitdir": `${join(wt, ".git")}\n` });
  writeTree(wt, { ".git": `gitdir: ${join(w.project, ".git", "worktrees", "wt")}\n` });
  if (local !== null) writeTree(wt, { ".claude/settings.local.json": local });
  const run = (args, extra = {}) => runIn(w, wt, args, extra);
  return { wt, run, file: join(wt, ".claude", "settings.local.json") };
}

const runIn = (w, cwd, args, extra = {}) => spawnSync(process.execPath, [CLI, ...args], { cwd, env: { ...w.env, ...extra }, encoding: "utf8" });
const esc = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const gitRecords = (w) => {
  const dir = join(w.project, ".git", "plugin-profiles", "records");
  return existsSync(dir) ? readdirSync(dir) : [];
};
const dataRecordsDir = (w) => join(w.home, ".claude", "plugins", "data", "plugin-profiles-inline", "records");

test("#16893: from a linked worktree and from a subdirectory, apply --for folder writes the main checkout's root file, and status there names it", () => {
  const w = world();
  gitInit(w);
  const t = linkedWorktree(w);
  const rootFile = join(realpathSync(w.project), ".claude", "settings.local.json");
  const r = t.run(["apply", "build", "--for", "folder", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(JSON.parse(w.read()).enabledPlugins[`songwriting@${M}`], false);
  assert.equal(existsSync(t.file), false, "the worktree gets no file of its own");
  const sub = join(w.project, "src");
  mkdirSync(sub);
  const named = new RegExp(`Profile build \\(folder\\) applied \\S+ to ${esc(rootFile)}, which every worktree of this repository reads\\.`);
  for (const run of [t.run, (args) => runIn(w, sub, args)]) assert.match(run(["status"]).stdout, named);
  assert.equal(runIn(w, sub, ["clear", "--yes"]).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("a folder outside git keeps today's status line, without the every-worktree words", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.match(w.run(["status"]).stdout, new RegExp(`Profile build \\(folder\\) applied \\S+ to ${esc(w.localFile)}\\.\\n`));
});

test("a folder whose .git is a file without a commondir, such as a submodule, is its own root and takes no profile from the checkout around it", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const t = linkedWorktree(w);
  rmSync(join(w.project, ".git", "worktrees", "wt", "commondir"));
  assert.match(t.run(["status"]).stdout, new RegExp(`No profile is recorded for ${esc(join(realpathSync(t.wt), ".claude", "settings.local.json"))}\\.`));
});

/** An earlier version's apply in the worktree: its own settings.local.json and a data-folder record of the entries it wrote. */
function earlierApply(w, t, entries) {
  writeTree(t.wt, { ".claude/settings.local.json": { enabledPlugins: entries } });
  const key = createHash("sha256").update(realpathSync(t.file)).digest("hex");
  writeTree(dataRecordsDir(w), {
    [`${key}.json`]: {
      schema: 1, profile: "songs", target: "folder", settingsFile: t.file, appliedAt: "2026-01-01T00:00:00.000Z", pluginVersion: "0.1.0",
      phase: "applied", pending: {}, createdFile: true, containers: { enabledPlugins: false, skillOverrides: false }, installed: [],
      entries: Object.fromEntries(Object.entries(entries).map(([id, after]) => [id, { before: ABSENT_VALUE, after }])), skillOverrides: {},
    },
  });
}
const ABSENT_VALUE = "absent";

test("#16914: a worktree file copied from the main checkout after an apply takes the root file's record, so status names it and clear --for worktree puts it back, leaving the root's record", () => {
  const w = world();
  gitInit(w);
  const before = w.read();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const t = linkedWorktree(w, JSON.parse(w.read()));
  assert.match(t.run(["status"]).stdout, new RegExp(esc(`An earlier profile, build, sits in ${t.file};`)));
  const r = t.run(["clear", "--for", "worktree", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(readFileSync(t.file, "utf8"), before, "the copy goes back to the root file's content before the apply");
  assert.match(w.run(["status"]).stdout, /Profile build \(folder\) applied/, "the root file keeps its profile and record");
  writeFileSync(t.file, `${JSON.stringify({ enabledPlugins: { "other@vendor": true } })}\n`);
  assert.doesNotMatch(t.run(["status"]).stdout, /An earlier profile/, "a file that does not hold every entry the root's record wrote is not adopted");
});

test("#16914: a hand-written worktree file with no record is named by status and the start notice for the entries the root file leaves unset, and clear leaves it", () => {
  const w = world();
  gitInit(w);
  const root = JSON.parse(w.read());
  const t = linkedWorktree(w, { enabledPlugins: { [Object.keys(root.enabledPlugins)[0]]: true, "skill-creator@claude-plugins-official": false }, skillOverrides: { "tdd:write": "off" } });
  const rootFile = join(realpathSync(w.project), ".claude", "settings.local.json");
  const line = `${t.file} also applies here for entries ${rootFile} does not set: skill-creator@claude-plugins-official, skill tdd:write. No profile wrote it, so clear leaves it; edit or remove that file to drop them.`;
  assert.ok(t.run(["status"]).stdout.split("\n").includes(line), t.run(["status"]).stdout);
  assert.ok(JSON.parse(sessionStart({ ...w, run: t.run })).systemMessage.includes(line));
  const before = readFileSync(t.file, "utf8");
  assert.equal(t.run(["clear", "--for", "worktree", "--yes"]).status, 0);
  assert.equal(readFileSync(t.file, "utf8"), before, "clear never deletes or edits an unrecorded file");
  writeFileSync(t.file, `${JSON.stringify({ enabledPlugins: { [Object.keys(root.enabledPlugins)[0]]: false } })}\n`);
  assert.doesNotMatch(t.run(["status"]).stdout, /also applies here/, "an entry the root file also sets is not in force from the worktree file");
});

test("#16893: an earlier worktree file with its own record is named as partly in force, the root's value wins in launch, and clear --for worktree puts it back", () => {
  const w = world();
  gitInit(w);
  installOnDisk(w);
  const t = linkedWorktree(w);
  const doc = JSON.parse(w.read());
  doc.enabledPlugins["widget@vendor"] = false;
  writeFileSync(w.localFile, `${JSON.stringify(doc, null, 2)}\n`);
  earlierApply(w, t, { "widget@vendor": true, "gadget@vendor": true });
  const rootFile = join(realpathSync(w.project), ".claude", "settings.local.json");
  const line = `An earlier profile, songs, sits in ${t.file}; Claude Code reads it only for plugins ${rootFile} does not set, so it is partly in force. Run clear --for worktree to put that file back.`;
  assert.ok(t.run(["status"]).stdout.split("\n").includes(line), t.run(["status"]).stdout);
  assert.deepEqual(JSON.parse(t.run(["status", "--json"]).stdout).earlier, { profile: "songs", file: t.file, line });
  assert.ok(JSON.parse(sessionStart({ ...w, run: t.run })).systemMessage.includes(line));
  const launched = JSON.parse(t.run(["launch", "build", "--json"]).stdout).enabledPlugins;
  assert.equal(launched["widget@vendor"], false, "where both files set a plugin, the root's value applies");
  assert.equal(launched["gadget@vendor"], true, "a plugin only the earlier file sets still counts");
  const r = t.run(["clear", "--for", "worktree", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(existsSync(t.file), false, "the file the earlier apply created is removed");
  assert.deepEqual(readdirSync(dataRecordsDir(w)), []);
  assert.doesNotMatch(t.run(["status"]).stdout, /An earlier profile/);
  assert.equal(JSON.parse(w.read()).enabledPlugins["widget@vendor"], false, "the root file is untouched");
});

test("#16893: clear --for worktree restores an earlier worktree file byte for byte", () => {
  const w = world();
  gitInit(w);
  const t = linkedWorktree(w, LOCAL_BEFORE);
  const key = createHash("sha256").update(realpathSync(t.file)).digest("hex");
  const after = { ...JSON.parse(LOCAL_BEFORE), enabledPlugins: { [`songwriting@${M}`]: false, [`review@${M}`]: false } };
  writeFileSync(t.file, `${JSON.stringify(after, null, 2)}\n`);
  writeTree(dataRecordsDir(w), {
    [`${key}.json`]: {
      schema: 1, profile: "songs", target: "folder", settingsFile: t.file, appliedAt: "2026-01-01T00:00:00.000Z", pluginVersion: "0.1.0",
      phase: "applied", pending: {}, createdFile: false, containers: { enabledPlugins: true, skillOverrides: false }, installed: [],
      entries: { [`songwriting@${M}`]: { before: true, after: false } }, skillOverrides: {},
    },
  });
  assert.equal(t.run(["clear", "--for", "worktree", "--yes"]).status, 0);
  assert.equal(readFileSync(t.file, "utf8"), LOCAL_BEFORE);
});

test("#16893: the record of a folder in git lands under .git/plugin-profiles/records, and clear still restores after the data folder is deleted", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(gitRecords(w).length, 1);
  assert.deepEqual(w.records(), [], "the data folder gets no copy");
  rmSync(join(w.home, ".claude", "plugins", "data"), { recursive: true, force: true });
  assert.match(w.run(["status"]).stdout, /Profile build \(folder\) applied /);
  assert.equal(w.run(["clear", "--yes"]).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual(gitRecords(w), []);
});

test("#16893: an apply from a linked worktree puts the record under the common git folder, never under the worktree's own gitdir", () => {
  const w = world();
  gitInit(w);
  const t = linkedWorktree(w);
  assert.equal(t.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(gitRecords(w).length, 1);
  assert.equal(existsSync(join(w.project, ".git", "worktrees", "wt", "plugin-profiles")), false);
  assert.deepEqual(w.records(), []);
});

test("#16893: with .git/plugin-profiles gone after an apply, as in a fresh clone, and no data-folder copy, clear says it has no record and changes nothing", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const applied = w.read();
  rmSync(join(w.project, ".git", "plugin-profiles"), { recursive: true, force: true });
  rmSync(join(w.home, ".claude", "plugins", "data"), { recursive: true, force: true });
  const r = w.run(["clear", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  const n = Object.keys(JSON.parse(applied).enabledPlugins).length;
  assert.match(r.stdout, new RegExp(`^No record of a profile apply was found for \\S+, so clear cannot tell which of its ${n} plugin entries and 0 skill entries a profile wrote; it changes nothing\\.`));
  assert.equal(w.read(), applied);
});

test("#16893: the initial profile's record lands under the config folder's plugin-profiles-state, outside the data folder", () => {
  const w = world({ local: null });
  const userFile = join(w.home, ".claude", "settings.json");
  const before = readFileSync(userFile, "utf8");
  assert.equal(w.run(["apply", "build", "--for", "initial", "--yes"]).status, 0);
  const dir = join(w.home, ".claude", "plugin-profiles-state", "records");
  assert.equal(readdirSync(dir).length, 1);
  rmSync(join(w.home, ".claude", "plugins", "data"), { recursive: true, force: true });
  assert.equal(w.run(["clear", "--for", "initial", "--yes"]).status, 0);
  assert.equal(readFileSync(userFile, "utf8"), before);
  assert.deepEqual(readdirSync(dir), []);
});

test("#16893: a record an earlier version left in the data folder is still found and cleared, and the next apply moves it to the primary home", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const [name] = gitRecords(w);
  mkdirSync(dataRecordsDir(w), { recursive: true });
  renameSync(join(w.project, ".git", "plugin-profiles", "records", name), join(dataRecordsDir(w), name));
  assert.match(w.run(["status"]).stdout, /Profile build \(folder\) applied /);
  assert.equal(w.run(["apply", "review", "--for", "folder", "--yes"]).status, 0);
  assert.deepEqual([gitRecords(w), w.records()], [[name], []]);
  renameSync(join(w.project, ".git", "plugin-profiles", "records", name), join(dataRecordsDir(w), name));
  assert.equal(w.run(["clear", "--yes"]).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual([gitRecords(w), w.records()], [[], []]);
});

test("#16893: clear with no record but plugin entries in the file says it cannot tell which a profile wrote, and changes nothing", () => {
  const w = world();
  const line = `No record of a profile apply was found for ${w.localFile}, so clear cannot tell which of its 2 plugin entries and 0 skill entries a profile wrote; it changes nothing. To drop them all, remove the enabledPlugins and skillOverrides keys from ${w.localFile}.`;
  const r = w.run(["clear", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim(), line);
  assert.equal(w.read(), LOCAL_BEFORE);
  const dry = JSON.parse(w.run(["clear", "--dry-run", "--json"]).stdout);
  assert.deepEqual([dry.recorded, dry.lines], [false, [line]]);
  const empty = world({ local: null });
  assert.equal(empty.run(["clear", "--yes"]).stdout.trim(), `No profile is recorded for ${empty.localFile}; nothing to clear.`);
});

test("#16893: a folder dry-run from a linked worktree names the live sessions in every worktree of the repository", () => {
  const w = world();
  gitInit(w);
  const t = linkedWorktree(w);
  const agents = join(w.root, "agents.json");
  writeFileSync(agents, JSON.stringify([
    { cwd: t.wt, sessionId: "me", name: "this one", kind: "interactive" },
    { cwd: w.project, sessionId: "b", name: "main checkout", kind: "interactive" },
    { cwd: w.root, sessionId: "c", name: "elsewhere", kind: "interactive" },
  ]));
  const r = t.run(["apply", "review", "--for", "folder", "--dry-run", "--json"], { PP_STUB_AGENTS: agents, CLAUDE_CODE_SESSION_ID: "me" });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout).othersInFolder, [{ name: "main checkout", sessionId: "b", kind: "interactive", oneSessionProfile: null }]);
});

test("D22: a folder dry-run names the other live sessions in the folder, leaving out this one", () => {
  const w = world();
  const agents = join(w.root, "agents.json");
  writeFileSync(agents, JSON.stringify([
    { cwd: w.project, sessionId: "me", name: "this one", kind: "interactive" },
    { cwd: w.project, sessionId: "b", name: "builder", kind: "background" },
    { cwd: w.root, sessionId: "c", name: "elsewhere", kind: "interactive" },
  ]));
  const r = w.run(["apply", "review", "--for", "folder", "--defer-off", "--dry-run", "--json"], { PP_STUB_AGENTS: agents, CLAUDE_CODE_SESSION_ID: "me" });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout).othersInFolder, [{ name: "builder", sessionId: "b", kind: "background", oneSessionProfile: null }]);
});

test("#16914: a folder dry-run marks a session started in a one-session profile, until it is resumed without it", () => {
  const w = world();
  sessionInBuild(w, "one-1");
  const agents = join(w.root, "agents.json");
  writeFileSync(agents, JSON.stringify([{ cwd: w.project, sessionId: "one-1", name: "probe-repo-04", kind: "interactive" }]));
  const others = () => JSON.parse(w.run(["apply", "review", "--for", "folder", "--defer-off", "--dry-run", "--json"], { PP_STUB_AGENTS: agents, CLAUDE_CODE_SESSION_ID: "me" }).stdout).othersInFolder;
  assert.equal(others()[0].oneSessionProfile, "build");
  hookStart(w, { session_id: "one-1", source: "resume" });
  assert.equal(others()[0].oneSessionProfile, null, "resumed without its profile, it follows the folder");
  assert.equal(startJson(w, ["--resume", "one-1"]).profile, "build", "its record still resumes it in build");
});

test("a launch with no profile from a profiled shell clears every inherited variable, and status ignores a file variable with no marker", () => {
  const w = world();
  const inherited = { PLUGIN_PROFILES_SESSION: "", PLUGIN_PROFILES_SESSION_FILE: "/parent/sessions/x-build.json", SESSION_SETTINGS_FILE: "/parent/sessions/x-build.json" };
  const none = launchJson(w, [], inherited);
  assert.equal(none.profile, null);
  assert.deepEqual(none.argv, ["env", "-u", "PLUGIN_PROFILES_SESSION", "-u", "PLUGIN_PROFILES_SESSION_FILE", "-u", "SESSION_SETTINGS_FILE", "claude"]);
  const r = w.run(["status"], inherited);
  assert.equal(r.status, 0, r.stderr);
  assert.doesNotMatch(r.stdout, /one-session settings file|\/parent\/sessions/);
});

test("an empty PLUGIN_PROFILES_SESSION counts as unset: status falls back to the folder profile and prints its launch command", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const r = w.run(["status"], { PLUGIN_PROFILES_SESSION: "" });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /Start another session here in this profile with: claude --profile build \(or node \S*profiles\.mjs launch build --folder /);
  assert.doesNotMatch(r.stdout, /one-session settings file/);
});

test("launch --json reports each plugin as the session will start with it, an entry the profile does not write included, under --dry-run too", () => {
  const w = world();
  const real = launchJson(w, ["build"]);
  const written = JSON.parse(readFileSync(real.file, "utf8")).enabledPlugins;
  assert.equal(`toolchain@${M}` in written, false, "the profile writes no entry for a plugin the repository enables");
  assert.equal(real.enabledPlugins[`toolchain@${M}`], true, "the repository's entry is in force for the session");
  assert.equal(real.enabledPlugins[`songwriting@${M}`], false, "the profile's entry wins over user settings");
  assert.deepEqual(launchJson(w, ["build", "--dry-run"]).enabledPlugins, real.enabledPlugins);
});

test("launch --dry-run checks and prints the command but writes no session file", () => {
  const w = world({ prerequisiteMissing: true });
  const sessions = join(w.home, ".claude", "plugins", "data", "plugin-profiles-inline", "sessions");
  const ok = launchJson(w, ["build", "--dry-run"]);
  assert.match(ok.file, /-build\.json$/);
  assert.equal(existsSync(sessions), false, "nothing written");
  const refused = w.run(["launch", "build", "--dry-run", "--unattended"]);
  assert.equal(refused.status, 1, "the unattended stop still applies");
  assert.equal(existsSync(sessions), false);
});

test("#16818: an installed copy clears a profile a --plugin-dir copy applied, whose record sits in plugin-profiles-inline", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(w.records().length, 1);
  const installed = installedCopy(w, {});
  assert.match(w.run(["status"], {}, installed).stdout, /Profile build \(folder\) applied /);
  const dry = JSON.parse(w.run(["clear", "--for", "folder", "--dry-run", "--json"], {}, installed).stdout);
  assert.equal(dry.recorded, true);
  assert.ok(!dry.lines.some((line) => line.includes("nothing to clear")), dry.lines.join("\n"));
  const r = w.run(["clear", "--for", "folder", "--yes"], {}, installed);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual(w.records(), []);
});

test("#16893: a CLAUDE_PLUGIN_DATA another plugin set is ignored, so the record and session file stay where every copy finds them", () => {
  const w = world();
  const foreign = { CLAUDE_PLUGIN_DATA: join(w.home, ".claude", "plugins", "data", "codex-openai-codex") };
  assert.match(launchJson(w, ["build", "--dry-run"], foreign).file, /plugin-profiles-inline[\\/]sessions[\\/]/);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"], foreign).status, 0);
  assert.equal(w.records().length, 1);
  assert.equal(existsSync(foreign.CLAUDE_PLUGIN_DATA), false);
  assert.match(w.run(["status"], {}, installedCopy(w, {})).stdout, /Profile build \(folder\) applied /);
  const own = { CLAUDE_PLUGIN_DATA: join(w.home, ".claude", "plugins", "data", "plugin-profiles-dev") };
  assert.match(launchJson(w, ["build", "--dry-run"], own).file, /plugin-profiles-dev[\\/]sessions[\\/]/);
});

test("#16893: clear names each entry edited since the apply that it overwrites, and leaves an entry already back at its before-value unnamed", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const doc = JSON.parse(w.read());
  doc.enabledPlugins[`implementation@${M}`] = false;
  doc.enabledPlugins[`songwriting@${M}`] = true;
  writeFileSync(w.localFile, `${JSON.stringify(doc, null, 2)}\n`);
  const dry = JSON.parse(w.run(["clear", "--dry-run", "--json"]).stdout);
  const named = dry.lines.filter((line) => line.startsWith("Overwrites a change made since the apply"));
  assert.deepEqual(named, [`Overwrites a change made since the apply: implementation@${M} is false, the profile wrote true; clear puts back absent.`]);
  assert.equal(w.run(["clear", "--yes"]).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("#16893: a plugin uninstalled after the apply leaves clear able to restore the file byte for byte", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const list = JSON.parse(readFileSync(w.env.PP_STUB_LIST, "utf8"));
  writeFileSync(w.env.PP_STUB_LIST, JSON.stringify(list.filter((p) => p.id !== `implementation@${M}`)));
  assert.match(w.run(["status"]).stdout, /Profile build \(folder\) applied /);
  const r = w.run(["clear", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("#16893: a plugin's state follows Claude Code's order: --settings over local over project over user", () => {
  const w = world();
  const id = "widget@vendor";
  const set = (file, value) => {
    const doc = existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : {};
    doc.enabledPlugins = { ...doc.enabledPlugins, [id]: value };
    writeFileSync(file, `${JSON.stringify(doc, null, 2)}\n`);
  };
  set(join(w.home, ".claude", "settings.json"), true);
  assert.equal(launchJson(w, ["build", "--dry-run"]).enabledPlugins[id], true, "user");
  set(join(w.project, ".claude", "settings.json"), false);
  assert.equal(launchJson(w, ["build", "--dry-run"]).enabledPlugins[id], false, "project over user");
  set(w.localFile, true);
  assert.equal(launchJson(w, ["build", "--dry-run"]).enabledPlugins[id], true, "local over project");
  const own = JSON.stringify({ enabledPlugins: { [id]: false } });
  assert.equal(launchJson(w, ["build", "--dry-run", "--with", own]).enabledPlugins[id], false, "--settings over local");
});

test("#16893: a one-session file names every plugin and skill entry any folder profile writes, so a folder switch elsewhere never reaches that session", () => {
  const w = world();
  writeTree(w.home, { ".claude/plugin-profiles/quiet.yaml": `description: Hides one skill.\nplugins: [songwriting@${M}]\nhide_skills: [some-standalone-skill]\n` });
  const names = JSON.parse(w.run(["list", "--json"]).stdout).map((p) => p.name);
  assert.ok(names.length > 1 && names.includes("build") && names.includes("quiet"), names.join(", "));
  const folderKeys = { enabledPlugins: new Set(), skillOverrides: new Set() };
  for (const name of names) {
    assert.equal(w.run(["apply", name, "--for", "folder", "--yes"]).status, 0, name);
    const doc = JSON.parse(w.read());
    for (const key of Object.keys(folderKeys)) for (const k of Object.keys(doc[key] ?? {})) folderKeys[key].add(k);
  }
  assert.ok(folderKeys.enabledPlugins.has(`songwriting@${M}`), "the folder applies wrote plugin entries");
  assert.ok(folderKeys.skillOverrides.has("some-standalone-skill"), "the folder applies wrote the hidden skill");
  for (const name of names) {
    const doc = JSON.parse(readFileSync(launchJson(w, [name]).file, "utf8"));
    for (const key of Object.keys(folderKeys)) {
      const missing = [...folderKeys[key]].filter((k) => !(k in (doc[key] ?? {})));
      assert.deepEqual(missing, [], `${name} session file leaves ${key} to the folder file`);
    }
  }
});

const byIdDir = (w) => join(w.home, ".claude", "plugins", "data", "plugin-profiles-inline", "sessions", "by-id");
const runWith = (w, args, input, extra = {}) => spawnSync(process.execPath, [CLI, ...args], { cwd: w.project, env: { ...w.env, ...extra }, input, encoding: "utf8" });
const startJson = (w, args, extra = {}) => {
  const r = w.run(["start", ...args, "--dry-run"], extra);
  assert.equal(r.status, 0, r.stderr);
  return { ...JSON.parse(r.stdout), stderr: r.stderr };
};
/** Runs the SessionStart hook as Claude Code does, with its JSON on stdin; returns the notice or "". */
const hookStart = (w, input, extra = {}) => {
  const r = runWith(w, ["status", "--session-start"], typeof input === "string" ? input : JSON.stringify(input), { CLAUDECODE: "1", CLAUDE_CODE_ENTRYPOINT: "cli", CLAUDE_PROJECT_DIR: w.project, ...extra });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stderr, "");
  return r.stdout ? JSON.parse(r.stdout).systemMessage : "";
};
/** A session launched in build here whose start hook recorded it under id. */
const sessionInBuild = (w, id) => {
  installOnDisk(w);
  const file = launchJson(w, ["build"]).file;
  hookStart(w, { session_id: id, source: "startup" }, JSON.parse(readFileSync(file, "utf8")).env);
  return file;
};

test("#16893 start: a named profile runs claude with the session file and the person's arguments, without the inherited markers, and exits with claude's status", () => {
  const w = world();
  const envFile = join(w.root, "env.jsonl");
  const r = w.run(["start", "build", "--model", "opus", "-p", "hi"], { PP_STUB_ENV: envFile, PP_STUB_EXIT: "7", PLUGIN_PROFILES_SESSION: "review", PLUGIN_PROFILES_SESSION_FILE: "/x", SESSION_SETTINGS_FILE: "/x" });
  assert.equal(r.status, 7, r.stderr);
  const started = readFileSync(envFile, "utf8").trim().split("\n").map((l) => JSON.parse(l)).find((c) => c.argv[0] === "--settings");
  const file = started.argv[1];
  assert.deepEqual(started.argv, ["--settings", file, "--model", "opus", "-p", "hi"]);
  for (const key of ["PLUGIN_PROFILES_SESSION", "PLUGIN_PROFILES_SESSION_FILE", "SESSION_SETTINGS_FILE"]) assert.equal(key in started.env, false, key);
  assert.equal(JSON.parse(readFileSync(file, "utf8")).env.PLUGIN_PROFILES_SESSION, "build");
  assert.ok(r.stderr.includes(`Starting claude in profile build (${file}).`), r.stderr);
});

test("#16893 start --dry-run prints the argv and the removed variables and starts nothing", () => {
  const w = world();
  const s = startJson(w, ["build", "--model", "opus"]);
  assert.deepEqual(s.argv, ["claude", "--settings", s.file, "--model", "opus"]);
  assert.deepEqual(s.env_removed, ["PLUGIN_PROFILES_SESSION", "PLUGIN_PROFILES_SESSION_FILE", "SESSION_SETTINGS_FILE"]);
  assert.equal(s.profile, "build");
  assert.equal(existsSync(s.file), false, "a dry run writes no session file");
  assert.doesNotMatch(w.calls(), /--settings/);
});

test("#16893 start: an unknown first word is refused with the list; no profile with nobody to pick is refused too", () => {
  const w = world();
  const unknown = w.run(["start", "nosuch"]);
  assert.equal(unknown.status, 2);
  assert.match(unknown.stderr, /start: no profile named nosuch; run start with no profile to pick one/);
  assert.match(unknown.stderr, /^build/m);
  const none = w.run(["start", "--model", "opus"]);
  assert.equal(none.status, 2);
  assert.match(none.stderr, /start: name a profile; nobody is there to pick one/);
  assert.match(none.stderr, /^review/m);
  assert.doesNotMatch(w.calls(), /--model/, "claude never started");
});

test("#16893 start --unattended stops on a missing required prerequisite before starting claude", () => {
  const w = world({ prerequisiteMissing: true });
  const r = w.run(["start", "build", "--unattended"]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, /not launched: profile build/);
  assert.doesNotMatch(w.calls(), /--settings/);
});

test("#16893 the start picker numbers the profiles, marks the folder's, asks again on a bad answer, and gives up on an empty one", async () => {
  const pick = async (text) => {
    const input = new PassThrough();
    const output = new PassThrough();
    let shown = "";
    output.on("data", (d) => (shown += d));
    const answer = pickProfile([{ name: "build", description: "Build." }, { name: "review", description: "Review." }], "review", { input, output });
    input.end(text);
    return { answer: await answer, shown };
  };
  const first = await pick("9\nx\n2\n");
  assert.equal(first.answer, "review");
  assert.match(first.shown, /1\. build: Build\./);
  assert.match(first.shown, /2\. review \(this folder's\): Review\./);
  assert.match(first.shown, /0\. No profile: the folder's settings/);
  assert.equal((await pick("0\n")).answer, null);
  assert.equal((await pick("\n")).answer, undefined);
  assert.equal((await pick("")).answer, undefined);
});

test("#16893 the session-start hook records the profile a session runs in by its id, and skips a bad id or bad input", () => {
  const w = world();
  const file = sessionInBuild(w, "abc-1");
  const rec = JSON.parse(readFileSync(join(byIdDir(w), "abc-1.json"), "utf8"));
  assert.deepEqual({ ...rec, at: undefined }, { sessionId: "abc-1", profile: "build", file, folder: w.project, at: undefined });
  assert.ok(!Number.isNaN(Date.parse(rec.at)));
  const env = JSON.parse(readFileSync(file, "utf8")).env;
  hookStart(w, { session_id: "../evil", source: "startup" }, env);
  hookStart(w, "not json", env);
  hookStart(w, "", env);
  assert.deepEqual(readdirSync(byIdDir(w)), ["abc-1.json"]);
});

test("#16893 a session resumed without its profile is told the command that resumes it there, even in a folder with no profile", () => {
  const w = world();
  sessionInBuild(w, "abc-1");
  const message = hookStart(w, { session_id: "abc-1", source: "resume" });
  assert.match(message, /This session ran in profile build; it is now running without it\. Resume it in that profile with: claude --resume abc-1 \(the plugin-profiles claude shell function restores the profile; without it, run node "\S+profiles\.mjs" start --resume abc-1\)\./);
  assert.equal(hookStart(w, { session_id: "abc-1", source: "startup" }), "", "a fresh start says nothing");
  assert.equal(hookStart(w, { session_id: "other", source: "resume" }), "", "no record, nothing to say");
});

test("#16893 start --resume takes the recorded profile; a given profile wins; no record resumes with the folder's settings", () => {
  const w = world();
  const file = sessionInBuild(w, "abc-1");
  const kept = startJson(w, ["--resume", "abc-1"]);
  assert.equal(kept.profile, "build");
  assert.deepEqual(kept.argv, ["claude", "--settings", file, "--resume", "abc-1"]);
  assert.match(kept.stderr, /Resuming abc-1 in profile build\./);
  assert.equal(startJson(w, ["-r", "abc-1"]).profile, "build");
  assert.deepEqual(startJson(w, ["--resume=abc-1"]).argv, ["claude", "--settings", file, "--resume=abc-1"]);
  const given = startJson(w, ["review", "--resume", "abc-1"]);
  assert.equal(given.profile, "review");
  assert.match(given.stderr, /Resuming abc-1 in profile review \(it ran in build\)\./);
  const none = startJson(w, ["--resume", "zzz"]);
  assert.equal(none.profile, null);
  assert.deepEqual(none.argv, ["claude", "--resume", "zzz"]);
  assert.match(none.stderr, /No profile is recorded for session zzz; resuming with this folder's settings\./);
  const picker = startJson(w, ["--resume"]);
  assert.deepEqual(picker.argv, ["claude", "--resume"]);
  assert.match(picker.stderr, /Pick the session; if it ran in a profile, its start notice gives the command that resumes it there\./);
});

test("#16893 start --resume rewrites a missing session file through launch", () => {
  const w = world();
  const file = sessionInBuild(w, "abc-1");
  rmSync(file);
  const r = w.run(["start", "--resume", "abc-1"], { PP_STUB_EXIT: "0" });
  assert.equal(r.status, 0, r.stderr);
  assert.ok(existsSync(file));
});

test("#16914: -c passes through unchanged, so it continues the conversation plain claude -c would, never another one", () => {
  const w = world();
  const none = startJson(w, ["-c"]);
  assert.deepEqual(none.argv, ["claude", "-c"]);
  assert.match(none.stderr, /Continuing with this folder's settings; if that session ran in a profile, its start notice gives the command that resumes it there\./);
  const file = sessionInBuild(w, "profiled-1");
  hookStart(w, { session_id: "plain-2", source: "startup" });
  assert.deepEqual(argsJson(w, ["-c"]).argv, ["claude", "-c"], "a profile session, then a newer plain one: claude -c continues the plain one");
  const used = JSON.parse(readFileSync(join(byIdDir(w), "profiled-1.json"), "utf8"));
  writeFileSync(join(byIdDir(w), "profiled-1.json"), JSON.stringify({ ...used, at: "2000-01-01T09:00:00.000Z" }));
  writeFileSync(join(byIdDir(w), "brief-3.json"), JSON.stringify({ sessionId: "brief-3", profile: "review", file, folder: w.project, at: "2000-01-01T10:00:00.000Z" }));
  const s = startJson(w, ["--continue", "--model", "opus"]);
  assert.deepEqual(s.argv, ["claude", "--continue", "--model", "opus"], "a session started earlier but used later: claude -c continues it, not the later start");
  assert.equal(s.profile, null);
  const given = startJson(w, ["review", "-c"]);
  assert.deepEqual(given.argv, ["claude", "--settings", given.file, "-c"]);
});

test("#16893 launch sweeps session records no session has written for 30 days", () => {
  const w = world();
  sessionInBuild(w, "abc-1");
  const stale = join(byIdDir(w), "abc-1.json");
  const old = new Date(Date.now() - 31 * 24 * 60 * 60 * 1000);
  utimesSync(stale, old, old);
  launchJson(w, ["build"]);
  assert.equal(existsSync(stale), false);
});

test("#16914: start takes always-on by name and lists it in the picker", async () => {
  const w = world();
  const r = startJson(w, ["always-on"]);
  assert.equal(r.profile, "always-on");
  assert.match(r.argv.join(" "), /--settings .*-always-on\.json/);
  const { PassThrough } = await import("node:stream");
  const input = new PassThrough();
  const output = new PassThrough();
  let shown = "";
  output.on("data", (c) => (shown += c));
  const { pickProfile } = await import("./profiles.mjs");
  const rows = [{ name: "always-on", description: "on" }, { name: "build", description: "b" }];
  const picked = pickProfile(rows, null, { input, output });
  input.end("1\n");
  assert.equal(await picked, "always-on");
  assert.match(shown, /^1\. always-on: on$/m);
});

test("#16914: start's refusal lists always-on among the profiles it can start", () => {
  const w = world();
  const r = w.run(["start", "nope"]);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /^always-on: /m);
});

test("#16914: a SIGTERM sent to start reaches claude, and start exits with claude's status", async () => {
  const w = world();
  const hang = join(w.root, "hang.txt");
  const { spawn } = await import("node:child_process");
  const child = spawn(process.execPath, [CLI, "start", "build"], { cwd: w.project, env: { ...w.env, PP_STUB_HANG: hang }, stdio: "ignore" });
  const exited = new Promise((done) => child.on("exit", (code) => done(code)));
  for (let i = 0; i < 200 && !(existsSync(hang) && readFileSync(hang, "utf8").trim()); i++) await new Promise((r) => setTimeout(r, 25));
  const claudePid = Number(readFileSync(hang, "utf8").trim().split("\n")[0]);
  assert.ok(claudePid > 0, "the stub claude started");
  child.kill("SIGTERM");
  assert.equal(await exited, 143);
  assert.match(readFileSync(hang, "utf8"), /^SIGTERM$/m, "claude received the SIGTERM");
  assert.throws(() => process.kill(claudePid, 0), /ESRCH/, "claude is no longer running");
});

test("#16914: an argument with a space and an ampersand reaches claude as one word", () => {
  const w = world();
  const envLog = join(w.root, "env.jsonl");
  const r = w.run(["start", "build", "-p", "a b & c"], { PP_STUB_ENV: envLog, PP_STUB_EXIT: "0" });
  assert.equal(r.status, 0, r.stderr);
  const call = readFileSync(envLog, "utf8").trim().split("\n").map((l) => JSON.parse(l)).find((c) => c.argv.includes("-p"));
  assert.deepEqual(call.argv.slice(-2), ["-p", "a b & c"]);
});

test("#16914: on Windows start spawns the claude.exe on PATH with no shell, and refuses a claude.cmd it would need a shell for", async () => {
  const { claudeCommand } = await import("./profiles.mjs");
  const files = new Set(["C:\\tools\\claude.exe", "D:\\npm\\claude.cmd"]);
  assert.deepEqual(claudeCommand({ Path: "C:\\none;C:\\tools" }, "win32", (p) => files.has(p)), { file: "C:\\tools\\claude.exe" });
  const cmdOnly = claudeCommand({ PATH: "D:\\npm" }, "win32", (p) => files.has(p));
  assert.equal(cmdOnly.file, undefined);
  assert.match(cmdOnly.refusal, /found D:\\npm\\claude\.cmd but no claude\.exe/);
  assert.match(claudeCommand({ PATH: "E:\\x" }, "win32", () => false).refusal, /no claude\.exe on PATH/);
  assert.deepEqual(claudeCommand({}, "linux"), { file: "claude" });
});

test("#16914: status says every worktree reads the folder file only once the repository has a linked worktree", () => {
  const w = world();
  writeTree(w.project, { ".git/HEAD": "ref: refs/heads/main\n" });
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const before = w.run(["status"]).stdout;
  assert.match(before, /Profile build \(folder\) applied /);
  assert.doesNotMatch(before, /every worktree/);
  writeTree(w.project, { ".git/worktrees/wt/commondir": "../..\n" });
  assert.match(w.run(["status"]).stdout, /, which every worktree of this repository reads\./);
});

test("#16914: a /resume inside a terminal in another profile says the session's record moves to that profile, and a later resume restores it", () => {
  const w = world();
  sessionInBuild(w, "abc-1");
  const review = launchJson(w, ["review"]).file;
  const reviewEnv = JSON.parse(readFileSync(review, "utf8")).env;
  const message = hookStart(w, { session_id: "abc-1", source: "resume" }, reviewEnv);
  assert.match(message, /^This session ran in profile build and now runs in review, so a later claude --resume abc-1 restores review\.$/m);
  assert.equal(JSON.parse(readFileSync(join(byIdDir(w), "abc-1.json"), "utf8")).profile, "review");
  assert.doesNotMatch(hookStart(w, { session_id: "abc-1", source: "resume" }, reviewEnv), /now runs in/, "the same profile again says nothing about a move");
});

test("#16914: the one-session start notice gives the session's own id in the resume command", () => {
  const w = world();
  const file = sessionInBuild(w, "abc-2");
  const message = hookStart(w, { session_id: "abc-2", source: "clear" }, JSON.parse(readFileSync(file, "utf8")).env);
  assert.match(message, /^Resume it in that profile with: claude --resume abc-2$/m);
});

const argsJson = (w, args, extra = {}) => {
  const r = w.run(["start", "--dry-run", "--claude-args", ...args], extra);
  assert.equal(r.status, 0, r.stderr);
  return { ...JSON.parse(r.stdout), stderr: r.stderr };
};

test("#16893 start --claude-args takes --profile from anywhere among the words and hands every other word to claude unchanged", () => {
  const w = world();
  const s = argsJson(w, ["--model", "opus", "--profile", "build", "-p", "hi"]);
  assert.equal(s.profile, "build");
  assert.deepEqual(s.argv, ["claude", "--settings", s.file, "--model", "opus", "-p", "hi"]);
  const eq = argsJson(w, ["-p", "hi", "--profile=review"]);
  assert.equal(eq.profile, "review");
  assert.deepEqual(eq.argv, ["claude", "--settings", eq.file, "-p", "hi"]);
  assert.deepEqual(argsJson(w, ["-p", "--", "--profile", "build"]).argv, ["claude", "-p", "--", "--profile", "build"], "a word after -- is claude's");
});

test("#16893 start --claude-args with no profile and no resume runs claude with the words unchanged, asks nothing and prints nothing", () => {
  const w = world();
  const s = argsJson(w, ["build", "--model", "opus"]);
  assert.equal(s.profile, null);
  assert.deepEqual(s.argv, ["claude", "build", "--model", "opus"], "a first word is not a profile here");
  assert.equal(s.stderr, "");
  const envFile = join(w.root, "env.jsonl");
  const r = w.run(["start", "--claude-args", "--model", "opus", "a b"], { PP_STUB_ENV: envFile, PP_STUB_EXIT: "3" });
  assert.equal(r.status, 3, r.stderr);
  assert.equal(r.stderr, "");
  const started = readFileSync(envFile, "utf8").trim().split("\n").map((l) => JSON.parse(l)).find((c) => c.argv.includes("--model"));
  assert.deepEqual(started.argv, ["--model", "opus", "a b"]);
});

test("#16893 start --claude-args resumes --resume in the profile the session ran in and passes -c through", () => {
  const w = world();
  const file = sessionInBuild(w, "abc-1");
  const resumed = argsJson(w, ["--resume", "abc-1", "--model", "opus"]);
  assert.equal(resumed.profile, "build");
  assert.deepEqual(resumed.argv, ["claude", "--settings", file, "--resume", "abc-1", "--model", "opus"]);
  const continued = argsJson(w, ["-c"]);
  assert.deepEqual(continued.argv, ["claude", "-c"]);
  assert.equal(argsJson(w, ["--resume", "abc-1", "--profile", "review"]).profile, "review", "a given profile wins");
});

test("#16893 start --profile works without --claude-args; an unknown or missing name, or a profile given twice, is refused before claude starts", () => {
  const w = world();
  const s = startJson(w, ["--model", "opus", "--profile", "build"]);
  assert.equal(s.profile, "build");
  assert.deepEqual(s.argv, ["claude", "--settings", s.file, "--model", "opus"]);
  for (const args of [["--profile", "nosuch"], ["--claude-args", "--profile", "nosuch"]]) {
    const r = w.run(["start", ...args]);
    assert.equal(r.status, 2, args.join(" "));
    assert.match(r.stderr, /start: no profile named nosuch; run start with no profile to pick one/);
    assert.match(r.stderr, /^build/m);
  }
  for (const args of [["--claude-args", "--profile"], ["--profile=", "-p"], ["build", "--profile", "review"], ["--profile", "build", "--profile", "review"]]) {
    const r = w.run(["start", ...args]);
    assert.equal(r.status, 2, args.join(" "));
    assert.match(r.stderr, /profiles\.mjs: .*(--profile|profile once)/, args.join(" "));
  }
  assert.deepEqual(w.calls().split("\n").filter((l) => l && !l.startsWith("plugin ")), [], "claude never started");
});

test("#16893 the session-start hook of an installed copy writes its root for the claude function, only when it changed; a worktree copy writes none", () => {
  const w = world();
  const pointer = join(w.home, ".claude", "plugin-profiles-state", "root");
  hookStart(w, { session_id: "abc-1", source: "startup" });
  assert.equal(existsSync(pointer), false, "a worktree or --plugin-dir copy writes no pointer");
  const cli = installedCopy(w, {});
  const hook = () => spawnSync(process.execPath, [cli, "status", "--session-start"], { cwd: w.project, env: { ...w.env, CLAUDECODE: "1", CLAUDE_CODE_ENTRYPOINT: "cli", CLAUDE_PROJECT_DIR: w.project }, input: JSON.stringify({ session_id: "abc-1", source: "startup" }), encoding: "utf8" });
  assert.equal(hook().status, 0);
  assert.equal(readFileSync(pointer, "utf8"), `${realpathSync(dirname(dirname(cli)))}\n`);
  const old = new Date(Date.now() - 24 * 60 * 60 * 1000);
  utimesSync(pointer, old, old);
  const set = statSync(pointer).mtimeMs;
  assert.equal(hook().status, 0);
  assert.equal(statSync(pointer).mtimeMs, set, "unchanged content is not rewritten");
  writeFileSync(pointer, "/somewhere/else\n");
  assert.equal(hook().status, 0);
  assert.equal(readFileSync(pointer, "utf8"), `${realpathSync(dirname(dirname(cli)))}\n`);
});
