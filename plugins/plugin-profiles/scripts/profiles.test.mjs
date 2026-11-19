import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { PassThrough } from "node:stream";
import { createHash } from "node:crypto";
import { chmodSync, cpSync, existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { basename, delimiter, dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { parseProfile } from "../lib/profile-files.mjs";
import { askPerFolder, main, pickProfile } from "./profiles.mjs";
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

test("Q69: cloud sessions: status says plugin profiles do not apply, and apply, clear and install write nothing", () => {
  for (const [surface, env] of [["a cloud session", CLOUD]]) {
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
    const env = { CLAUDECODE: "1", CLAUDE_CODE_ENTRYPOINT: entry, WSL_DISTRO_NAME: "Ubuntu" };
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

test("Q69: in cloud sessions the session-start notice prints nothing and writes nothing, even where a profile is applied", () => {
  const w = world();
  installOnDisk(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.match(JSON.parse(sessionStart(w)).systemMessage, /Profile build applies here/, "on the CLI the notice speaks");
  const before = snapshot(settingsFiles(w));
  const records = w.records();
  assert.equal(sessionStart(w, CLOUD), "", "cloud");
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

test("#17354: apply --finish-pending does nothing once the folder's record is gone or no longer off-pending", () => {
  const w = world();
  const nothing = (name) => new RegExp(`^Nothing to finish: no unfinished switch to ${name} is recorded for ${esc(w.localFile)}\\.$`, "m");
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes", "--defer-off"]).status, 0);
  const finished = w.run(["apply", "build", "--for", "folder", "--finish-pending"]);
  assert.equal(finished.status, 0, finished.stderr);
  assert.equal(JSON.parse(w.read()).enabledPlugins[`songwriting@${M}`], false, "an off-pending record of this profile is finished");
  assert.equal(JSON.parse(w.run(["status", "--json"]).stdout).phase, "applied");
  const applied = w.read();
  const again = w.run(["apply", "build", "--for", "folder", "--finish-pending"]);
  assert.equal(again.status, 0, again.stderr);
  assert.match(again.stdout, nothing("build"));
  assert.equal(w.read(), applied, "an applied record is left alone");
  assert.equal(w.run(["apply", "review", "--for", "folder", "--yes", "--defer-off"]).status, 0);
  const other = w.read();
  assert.match(w.run(["apply", "build", "--for", "folder", "--finish-pending"]).stdout, nothing("build"));
  assert.equal(w.read(), other, "a switch to another profile is not finished as this one");
  assert.equal(w.run(["clear", "--yes"]).status, 0);
  const gone = w.run(["apply", "review", "--for", "folder", "--finish-pending"]);
  assert.equal(gone.status, 0, gone.stderr);
  assert.match(gone.stdout, nothing("review"));
  assert.equal(w.read(), LOCAL_BEFORE, "a cleared folder stays cleared");
  assert.deepEqual(w.records(), []);
  assert.equal(w.run(["apply", "build", "--for", "session", "--finish-pending"]).status, 2, "only a folder or user settings has a switch to finish");
});

test("#17354: a reset in another terminal while apply --finish-pending lists the installed plugins makes the finish write nothing, even when the deferred switch left the settings bytes unchanged", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const doc = JSON.parse(w.read());
  doc.enabledPlugins[`songwriting@${M}`] = true;
  writeFileSync(w.localFile, `${JSON.stringify(doc, null, 2)}\n`);
  rmSync(dataRecordsDir(w), { recursive: true });
  const before = w.read();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes", "--defer-off"]).status, 0);
  assert.equal(w.read(), before, "the deferred switch wrote no byte");
  const during = join(w.root, "during.json");
  writeFileSync(during, JSON.stringify({ argv: [CLI, "reset", "--yes"], cwd: elsewhere(w) }));
  const r = w.run(["apply", "build", "--for", "folder", "--finish-pending"], { PP_STUB_DURING_LIST: during });
  assert.equal(existsSync(during), false, "the reset ran during the finish");
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, new RegExp(`^Nothing to finish: the unfinished switch to build recorded for ${esc(w.localFile)} changed while finishing \\(a reset, a clear or another switch\\); nothing was written\\.$`, "m"));
  assert.equal(JSON.parse(w.read()).enabledPlugins[`songwriting@${M}`], true, "the cancelled switch is not reapplied");
  assert.deepEqual(w.records(), []);
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

test("check fails a shipped profile whose list is not in alphabetical order", () => {
  const w = world();
  const shipped = join(w.root, "shipped");
  cpSync(SHIPPED, shipped, { recursive: true });
  writeFileSync(join(shipped, "build.yaml"), `${readFileSync(join(shipped, "build.yaml"), "utf8")}optional:\n  - tdd@${M}\n  - review@${M}\n`);
  const r = w.run(["check", "--shipped", shipped]);
  assert.equal(r.status, 1, r.stdout + r.stderr);
  assert.match(r.stderr, /FAIL: .*build\.yaml: optional is not in alphabetical order: review@melodic-software goes before tdd@melodic-software/);
});

test("#17038: check still fails a shipped profile that excludes an always-on member without always_on false", () => {
  const w = world();
  const shipped = join(w.root, "shipped");
  cpSync(SHIPPED, shipped, { recursive: true });
  writeFileSync(join(shipped, "build.yaml"), `${readFileSync(join(shipped, "build.yaml"), "utf8")}exclude: [guardrails@${M}]\n`);
  const r = w.run(["check", "--shipped", shipped]);
  assert.equal(r.status, 1, r.stdout + r.stderr);
  assert.match(r.stderr, /profile build excludes always-on member guardrails@melodic-software/);
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

test("list --json names every shipped profile but always-on, each with its description", () => {
  const w = world();
  const r = w.run(["list", "--json"]);
  assert.equal(r.status, 0, r.stderr);
  const profiles = JSON.parse(r.stdout);
  assert.deepEqual(profiles.map((p) => p.name).sort(), ["build", "discovery", "harness-upkeep", "improve", "interface-design", "native", "planning", "review"]);
  assert.equal(profiles.find((p) => p.name === "build").description, "Write the change, test, review, verify, open and merge the PR, and run lanes.");
  assert.match(profiles.find((p) => p.name === "native").description, /guardrails included/);
  assert.match(profiles.find((p) => p.name === "improve").description, /^Targeted improvement of existing code/);
});

test("#17355: the shipped improve profile holds exactly its 13 members, in alphabetical order", () => {
  const file = join(SHIPPED, "improve.yaml");
  const improve = parseProfile(readFileSync(file, "utf8"), file);
  const members = ["architecture", "code-metrics", "code-tidying", "codebase-health", "coupling", "implementation", "improvement", "overengineering", "performance", "review", "testing", "toolchain", "verification"];
  assert.deepEqual(improve.plugins, members.map((name) => `${name}@${M}`));
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
  assert.equal(readFileSync(userProfile(w, "notes"), "utf8"), `description: "Notes."\nplugins:\n  - "review@${M}"\n  - "songwriting@${M}"\n`);
});

test("save writes and previews every list in alphabetical order, whatever order the ids came in", () => {
  const w = world();
  const args = ["save", "notes", "--level", "user", "--plugins", `tdd@${M},review@${M},code-tidying@${M}`, "--optional", `spelling@${M},bash-format@${M}`, "--hide-skills", "zeta-skill,alpha-skill"];
  const sorted = `plugins:\n  - "code-tidying@${M}"\n  - "review@${M}"\n  - "tdd@${M}"\noptional:\n  - "bash-format@${M}"\n  - "spelling@${M}"\nhide_skills:\n  - "alpha-skill"\n  - "zeta-skill"\n`;
  const preview = w.run([...args, "--dry-run"]);
  assert.equal(preview.status, 0, preview.stderr);
  assert.ok(preview.stdout.includes(sorted.replace(/^/gm, "  ").trimEnd()), preview.stdout);
  assert.equal(existsSync(userProfile(w, "notes")), false);
  assert.equal(w.run([...args, "--yes"]).status, 0);
  assert.equal(readFileSync(userProfile(w, "notes"), "utf8"), sorted);
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

const ALWAYS_ON_OFF = /^Switches off guardrails and the other always-on plugins that other profiles keep on \(\d+\): .*guardrails@melodic-software/m;

test("#17038: start native --dry-run plans every governed plugin off but the switcher, and its preview names guardrails as off", () => {
  const w = world();
  writeTree(w.project, { ".claude/settings.json": {} });
  const r = w.run(["start", "native", "--dry-run"]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stderr, ALWAYS_ON_OFF);
  const plugins = launchJson(w, ["native"]).enabledPlugins;
  const governed = Object.keys(plugins).filter((id) => id.endsWith(`@${M}`));
  assert.ok(governed.includes(`guardrails@${M}`), governed.join(", "));
  assert.deepEqual(governed.filter((id) => plugins[id]), [`plugin-profiles@${M}`]);
  assert.equal("widget@vendor" in plugins, false, "a plugin of another marketplace is left alone");
});

test("#17038: the folder preview of native says guardrails and the other always-on plugins are off", () => {
  const w = world();
  const preview = JSON.parse(w.run(["apply", "native", "--for", "folder", "--defer-off", "--dry-run", "--json"]).stdout);
  assert.ok(preview.alwaysOnOff.includes(`guardrails@${M}`), preview.alwaysOnOff.join(", "));
  assert.ok(preview.lines.some((line) => ALWAYS_ON_OFF.test(line)), preview.lines.join("\n"));
  assert.deepEqual(JSON.parse(w.run(["apply", "build", "--for", "folder", "--dry-run", "--json"]).stdout).alwaysOnOff, []);
});

test("#17038: native in a repository whose settings enable guardrails says guardrails stays on and why, and never that it is off", () => {
  const w = world();
  writeTree(w.project, { ".claude/settings.json": { enabledPlugins: { [`guardrails@${M}`]: true } } });
  const preview = JSON.parse(w.run(["apply", "native", "--for", "folder", "--dry-run", "--json"]).stdout);
  assert.ok(!preview.alwaysOnOff.includes(`guardrails@${M}`), preview.alwaysOnOff.join(", "));
  assert.ok(preview.lines.includes(`Always-on plugin left on, because the repository's settings enable it: guardrails@${M}`), preview.lines.join("\n"));
  assert.ok(preview.lines.some((line) => line.startsWith("Switches off always-on plugins that other profiles keep on")), preview.lines.join("\n"));
  assert.ok(!preview.lines.some((line) => /guardrails and the other/.test(line)), preview.lines.join("\n"));
});

test("#17038: a user profile with always_on false that lists guardrails says it stays on because the profile switches it on", () => {
  const w = world();
  writeTree(w.home, { ".claude/plugin-profiles/guarded.yaml": `always_on: false\nplugins: [plugin-profiles@${M}, guardrails@${M}]\n` });
  const r = w.run(["start", "guarded", "--dry-run"]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stderr, /^Always-on plugin left on, because this profile switches it on: guardrails@melodic-software$/m);
  assert.match(r.stderr, /^Switches off always-on plugins that other profiles keep on/m);
});

test("#17038: a repository profile's always_on false is ignored: always-on stays on and the preview says the line was ignored", () => {
  const w = world();
  const file = join(w.project, "docs", "conventions", "plugin-profiles", "notes.yaml");
  writeTree(w.project, { "docs/conventions/plugin-profiles/notes.yaml": `always_on: false\nplugins: [songwriting@${M}]\n` });
  const r = w.run(["apply", "notes", "--for", "folder", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(JSON.parse(w.read()).enabledPlugins[`guardrails@${M}`], true);
  assert.ok(r.stdout.split("\n").includes(`Ignored, from ${file}: always_on: false. A repository profile cannot switch off an always-on member; a user-level profile can.`), r.stdout);
  assert.doesNotMatch(r.stdout, /always-on plugins that other profiles keep on/);
});

test("#17038: from a session in native, the switcher starts another profile, and clear returns the folder to its state before", () => {
  const w = world();
  const inNative = { PLUGIN_PROFILES_SESSION: "native" };
  assert.equal(w.run(["apply", "native", "--for", "folder", "--yes"], inNative).status, 0);
  assert.equal(JSON.parse(w.read()).enabledPlugins[`guardrails@${M}`], false);
  assert.equal(startJson(w, ["build"], inNative).profile, "build");
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"], inNative).status, 0);
  assert.equal(JSON.parse(w.read()).enabledPlugins[`guardrails@${M}`], true);
  assert.equal(w.run(["clear", "--yes"], inNative).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("#17038: save keeps a user profile's always_on false and accepts its exclude of an always-on member", () => {
  const w = world();
  writeTree(w.home, { ".claude/plugin-profiles/bare.yaml": `always_on: false\nplugins: [plugin-profiles@${M}]\n` });
  const r = w.run(["save", "bare", "--level", "user", "--exclude", `guardrails@${M}`, "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(readFileSync(join(w.home, ".claude", "plugin-profiles", "bare.yaml"), "utf8"), /^always_on: false$/m);
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

test("#16914: start --resume takes the newest record of a session across every copy's data folder", () => {
  const w = world();
  const build = sessionInBuild(w, "abc-1");
  const review = launchJson(w, ["review"]).file;
  const other = join(w.home, ".claude", "plugins", "data", "plugin-profiles-melodic-software", "sessions", "by-id", "abc-1.json");
  const own = JSON.parse(readFileSync(join(byIdDir(w), "abc-1.json"), "utf8"));
  const write = (at) => writeTree(dirname(other), { "abc-1.json": { sessionId: "abc-1", profile: "review", file: review, folder: w.project, at } });
  write(new Date(Date.parse(own.at) + 60_000).toISOString());
  assert.equal(startJson(w, ["--resume", "abc-1"]).profile, "review", "a later resume through another copy wins");
  write("2000-01-01T00:00:00.000Z");
  const older = startJson(w, ["--resume", "abc-1"]);
  assert.equal(older.profile, "build", "an older copy's record loses");
  assert.deepEqual(older.argv, ["claude", "--settings", build, "--resume", "abc-1"]);
});

test("#16914: an unattended resume reusing its session file refuses on a missing required prerequisite, as an unattended start does; an attended one reuses the file without listing plugins", () => {
  const w = world({ prerequisiteMissing: true });
  const file = sessionInBuild(w, "abc-1");
  const refused = w.run(["start", "--resume", "abc-1", "--unattended", "--dry-run"]);
  assert.equal(refused.status, 1);
  assert.match(refused.stderr, /not resumed: profile build switches on a plugin missing a required prerequisite/);
  assert.equal(w.run(["start", "build", "--unattended", "--dry-run"]).status, 1, "the start it mirrors refuses too");
  const listed = () => w.calls().split("\n").filter((line) => line.startsWith("plugin list")).length;
  const before = listed();
  assert.ok(before > 0, "the stub logs each plugin list call, as the unattended checks just made");
  const attended = startJson(w, ["--resume", "abc-1"]);
  assert.deepEqual(attended.argv, ["claude", "--settings", file, "--resume", "abc-1"]);
  assert.doesNotMatch(attended.stderr, /Missing required prerequisite/);
  assert.equal(listed(), before, "an attended resume never runs claude plugin list");
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
  const { claudeCommand } = await import("../lib/claude-command.mjs");
  const files = new Set(["C:\\tools\\claude.exe", "D:\\npm\\claude.cmd"]);
  assert.deepEqual(claudeCommand({ Path: "C:\\none;C:\\tools" }, "win32", (p) => files.has(p)), { file: "C:\\tools\\claude.exe" });
  const cmdOnly = claudeCommand({ PATH: "D:\\npm" }, "win32", (p) => files.has(p));
  assert.equal(cmdOnly.file, undefined);
  assert.match(cmdOnly.refusal, /found D:\\npm\\claude\.cmd but no claude\.exe/);
  assert.match(claudeCommand({ PATH: "E:\\x" }, "win32", () => false).refusal, /no claude\.exe on PATH/);
  assert.deepEqual(claudeCommand({}, "linux"), { file: "claude" });
});

test("#17063: no spawn in the plugin runs through a shell, which prints DEP0190 on Windows", () => {
  const root = join(HERE, "..");
  const sources = readdirSync(root, { recursive: true }).filter((f) => f.endsWith(".mjs"));
  const shelled = sources.filter((f) => /\bshell\s*:/.test(readFileSync(join(root, f), "utf8")));
  assert.deepEqual(shelled, []);
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

test("#16914: words after a bare -- stay claude's: neither --resume, -c nor --profile there picks a profile or a session file", () => {
  const w = world();
  sessionInBuild(w, "abc-1");
  for (const words of [["--", "--resume", "abc-1"], ["--", "--profile", "build"], ["--", "-c"], ["-p", "--", "--resume=abc-1"]]) {
    const r = argsJson(w, words);
    assert.deepEqual(r.argv, ["claude", ...words], words.join(" "));
    assert.equal(r.profile, null, words.join(" "));
  }
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

const pointersDir = (w) => join(w.home, ".claude", "plugin-profiles-state", "repositories");
const pointers = (w) => (existsSync(pointersDir(w)) ? readdirSync(pointersDir(w)) : []);
/** A folder outside every repository, so a reset run there finds folders only through what the machine records. */
const elsewhere = (w) => {
  const dir = join(w.root, "elsewhere");
  mkdirSync(dir, { recursive: true });
  return dir;
};
const reset = (w, args = [], extra = {}) => runIn(w, elsewhere(w), ["reset", ...args], extra);
const resetJson = (w, extra = {}) => {
  const r = reset(w, ["--dry-run", "--json"], extra);
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
};
const recordedFiles = (preview) => preview.folders.filter((f) => f.recorded).map((f) => f.file).sort();
/** Claude Code's ~/.claude.json naming the folders it has opened, as its projects map does. */
const knowFolders = (w, ...folders) => writeTree(w.home, { ".claude.json": { projects: Object.fromEntries(folders.map((f) => [f, { allowedTools: [] }])) } });
const rootLocal = (dir) => join(realpathSync(dir), ".claude", "settings.local.json");
/** A second main checkout beside w.project, holding LOCAL_BEFORE. */
function secondRepository(w, name = "project2") {
  const dir = join(w.root, name);
  writeTree(dir, { ".git/HEAD": "ref: refs/heads/main\n", ".claude/settings.local.json": LOCAL_BEFORE });
  return dir;
}

test("#17354: an apply in git writes one pointer per repository, and the pointer alone finds its records", () => {
  const w = world();
  gitInit(w);
  const p2 = secondRepository(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(w.run(["apply", "review", "--for", "folder", "--yes"]).status, 0);
  assert.equal(runIn(w, p2, ["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(pointers(w).length, 2, "one pointer per repository, however many applies");
  assert.deepEqual(recordedFiles(resetJson(w)), [rootLocal(w.project), rootLocal(p2)].sort());
  rmSync(pointersDir(w), { recursive: true });
  assert.deepEqual(recordedFiles(resetJson(w)), [], "with no pointer and no known folder, a repository's records are not found");
});

test("#17354: a folder applied before reset shipped, with no repository pointer, is found through ~/.claude.json and restored", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  rmSync(pointersDir(w), { recursive: true });
  knowFolders(w, w.project);
  assert.deepEqual(recordedFiles(resetJson(w)), [rootLocal(w.project)]);
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual(gitRecords(w), []);
});

test("#17354: a folder known only from a one-session record is found", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  rmSync(pointersDir(w), { recursive: true });
  writeTree(byIdDir(w), { "s1.json": { sessionId: "s1", profile: "review", file: join(w.root, "gone.json"), folder: w.project, at: "2026-11-01T00:00:00.000Z" } });
  assert.deepEqual(recordedFiles(resetJson(w)), [rootLocal(w.project)]);
});

test("#17354: a folder known only from a live session is found", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  rmSync(pointersDir(w), { recursive: true });
  const agents = join(w.root, "agents.json");
  writeFileSync(agents, JSON.stringify([{ cwd: join(w.project, "src"), sessionId: "a", name: "live", kind: "interactive" }]));
  mkdirSync(join(w.project, "src"));
  assert.deepEqual(recordedFiles(resetJson(w)), []);
  assert.deepEqual(recordedFiles(resetJson(w, { PP_STUB_AGENTS: agents })), [rootLocal(w.project)]);
});

test("#17354: a reset run inside a repository finds it with no pointer and no other source", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  rmSync(pointersDir(w), { recursive: true });
  assert.deepEqual(recordedFiles(resetJson(w)), []);
  const here = w.run(["reset", "--dry-run", "--json"]);
  assert.equal(here.status, 0, here.stderr);
  assert.deepEqual(recordedFiles(JSON.parse(here.stdout)), [rootLocal(w.project)]);
});

test("#17354: a session start in a repository applied before reset shipped writes its pointer, so reset finds it after the worktree it was applied from is gone", () => {
  const w = world();
  gitInit(w);
  installOnDisk(w);
  const t = linkedWorktree(w);
  assert.equal(t.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  rmSync(pointersDir(w), { recursive: true });
  const started = t.run(["status", "--session-start"], { CLAUDECODE: "1", CLAUDE_CODE_ENTRYPOINT: "cli" });
  assert.equal(started.status, 0, started.stderr);
  assert.equal(pointers(w).length, 1, "the session start wrote the repository's pointer");
  rmSync(t.wt, { recursive: true });
  knowFolders(w, t.wt);
  assert.deepEqual(recordedFiles(resetJson(w)), [rootLocal(w.project)]);
  assert.equal(reset(w, ["--yes"]).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("#17354: a submodule's record is found through its pointer", () => {
  const w = world();
  gitInit(w);
  const sub = join(w.project, "sub");
  writeTree(w.project, { ".git/modules/sub/HEAD": "ref: refs/heads/main\n", "sub/.git": "gitdir: ../.git/modules/sub\n", "sub/.claude/settings.local.json": LOCAL_BEFORE });
  assert.equal(runIn(w, sub, ["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.ok(existsSync(join(w.project, ".git", "modules", "sub", "plugin-profiles", "records")));
  knowFolders(w, w.project);
  assert.equal(pointers(w).length, 1);
  const [name] = pointers(w);
  const text = readFileSync(join(pointersDir(w), name), "utf8");
  rmSync(pointersDir(w), { recursive: true });
  assert.deepEqual(recordedFiles(resetJson(w)), [], "the superproject's folder never reaches the submodule's record");
  writeTree(pointersDir(w), { [name]: text });
  assert.deepEqual(recordedFiles(resetJson(w)), [rootLocal(sub)]);
  assert.equal(reset(w, ["--yes"]).status, 0);
  assert.equal(readFileSync(join(sub, ".claude", "settings.local.json"), "utf8"), LOCAL_BEFORE);
});

/** A plain folder beside w.project holding LOCAL_BEFORE, with the profile applied there. */
function secondFolder(w, profile = "build") {
  const dir = join(w.root, "project2");
  writeTree(dir, { ".claude/settings.local.json": LOCAL_BEFORE });
  assert.equal(runIn(w, dir, ["apply", profile, "--for", "folder", "--yes"]).status, 0);
  return { dir, file: join(dir, ".claude", "settings.local.json") };
}
const sha = (text) => createHash("sha256").update(text).digest("hex");
const dataRecordOf = (w, file) => join(dataRecordsDir(w), `${sha(realpathSync(file))}.json`);
const RESULT = /^(Restored|Removed|Skipped|Finished|Already restored) /;
const resultLines = (stdout) => stdout.split("\n").filter((line) => RESULT.test(line));
/** The state a reset killed part way leaves for file: its record saved as restoring, the file as given. */
function cutOff(w, file, { written }) {
  const path = dataRecordOf(w, file);
  const applied = readFileSync(file, "utf8");
  const rec = JSON.parse(readFileSync(path, "utf8"));
  writeFileSync(path, `${JSON.stringify({ ...rec, phase: "restoring", restoredHash: sha(LOCAL_BEFORE), fromHash: sha(applied) }, null, 2)}\n`);
  if (written) writeFileSync(file, LOCAL_BEFORE);
}
/** Runs reset in this process, so a test can act when reset prints one file's result, as another terminal would between two files. */
async function resetDuring(w, args, onResult) {
  assert.ok(w.env.HOME.startsWith(w.root) && w.env.PATH.startsWith(STUB_BIN), "an in-process reset runs only against the test's HOME and stub claude");
  const out = [];
  const err = [];
  let acted = false;
  const io = {
    out: (line) => {
      out.push(line);
      if (!acted && RESULT.test(line)) {
        acted = true;
        onResult(line);
      }
    },
    err: (line) => err.push(line),
    stdin: () => "",
  };
  const status = await main(["reset", ...args], { ...w.env }, elsewhere(w), io);
  return { status, stdout: out.join("\n"), stderr: err.join("\n") };
}

/** Runs reset in this process as from a terminal: answer(prompt) gives the line typed at each [y/N] question; prompts lists the questions in order. */
async function resetAtTerminal(w, answer, args = []) {
  assert.ok(w.env.HOME.startsWith(w.root) && w.env.PATH.startsWith(STUB_BIN), "an in-process reset runs only against the test's HOME and stub claude");
  const input = new PassThrough();
  const output = new PassThrough();
  const prompts = [];
  let shown = "";
  output.on("data", (chunk) => {
    shown += chunk;
    const at = shown.lastIndexOf(" [y/N] ");
    if (at === -1 || at !== shown.length - 7) return;
    const prompt = shown.slice(0, at);
    shown = "";
    prompts.push(prompt);
    input.write(`${answer(prompt)}\n`);
  });
  const out = [];
  const err = [];
  const io = { out: (line) => out.push(line), err: (line) => err.push(line), stdin: () => "", terminal: { input, output } };
  const status = await main(["reset", ...args], { ...w.env }, elsewhere(w), io);
  return { status, stdout: out.join("\n"), stderr: err.join("\n"), prompts };
}
const FIRST = /^Reset the \d+ files? above/;

test("#17354: at a terminal, a no to the one question keeps the recorded files and still asks each file's own question", async () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const applied = w.read();
  const loose = join(w.root, "loose");
  writeTree(loose, { ".claude/settings.local.json": LOCAL_BEFORE });
  const looseFile = join(loose, ".claude", "settings.local.json");
  knowFolders(w, w.project, loose);
  const r = await resetAtTerminal(w, (prompt) => (FIRST.test(prompt) ? "n" : "y"));
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.prompts.length, 2, r.prompts.join("\n"));
  assert.match(r.prompts[0], FIRST);
  assert.match(r.prompts[1], new RegExp(`^${esc(looseFile)} has no profile record\\.`));
  assert.deepEqual(resultLines(r.stdout).sort(), [
    `Removed the 2 plugin and skill entries of ${looseFile}, which had no record.`,
    `Skipped ${w.localFile}: you answered no, so it is left as it is, and its record is kept.`,
  ].sort());
  assert.equal(w.read(), applied);
  assert.equal(w.records().length, 1);
  assert.deepEqual(JSON.parse(readFileSync(looseFile, "utf8")), withoutProfileKeys(LOCAL_BEFORE));
  writeFileSync(looseFile, LOCAL_BEFORE);
  const none = await resetAtTerminal(w, () => "n");
  assert.equal(none.status, 1, none.stdout);
  assert.equal(none.prompts.length, 2, "every question is asked before nothing is written");
  assert.match(none.stderr, /^not reset: nothing was written$/m);
  assert.deepEqual(resultLines(none.stdout), []);
  assert.deepEqual([w.read(), readFileSync(looseFile, "utf8")], [applied, LOCAL_BEFORE]);
});

test("#17354: reset with nothing recorded says so and writes nothing", () => {
  const w = world();
  const r = reset(w, ["--dry-run"]);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /^No profile is recorded anywhere reset can find; nothing to reset\.$/m);
  assert.equal(reset(w, ["--yes"]).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("#17354: reset previews two folders and the initial profile, and after one yes each folder file is back byte for byte, a file the apply created is gone, and user settings hold their earlier entries", () => {
  const w = world();
  const userFile = join(w.home, ".claude", "settings.json");
  const userBefore = readFileSync(userFile, "utf8");
  const p2 = join(w.root, "project2");
  mkdirSync(p2);
  const p2File = join(p2, ".claude", "settings.local.json");
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(runIn(w, p2, ["apply", "review", "--for", "folder", "--yes"]).status, 0);
  assert.equal(runIn(w, elsewhere(w), ["apply", "build", "--for", "initial", "--yes"]).status, 0, "from a folder with no file of its own, which would pin the plugins");
  assert.notEqual(readFileSync(userFile, "utf8"), userBefore);
  const preview = resetJson(w);
  assert.deepEqual(recordedFiles(preview), [w.localFile, p2File, userFile].sort());
  for (const f of preview.folders) assert.ok(f.lines.some((line) => line.includes(f.file)), JSON.stringify(f));
  assert.match(preview.lines.join("\n"), new RegExp(`${esc(p2File)}: profile review .*removes the file, which the first apply created`));
  assert.match(preview.lines.join("\n"), new RegExp(`${esc(userFile)}: profile build \\(the initial profile\\)`));
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.equal(existsSync(p2File), false);
  assert.equal(existsSync(dirname(p2File)), false, "the .claude folder the apply created goes once empty");
  assert.equal(readFileSync(userFile, "utf8"), userBefore);
  assert.deepEqual(w.records(), []);
  assert.deepEqual(readdirSync(join(w.home, ".claude", "plugin-profiles-state", "records")), []);
});

test("#17354: with neither a typed yes nor --yes, reset writes nothing and says so", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const applied = w.read();
  const r = reset(w);
  assert.equal(r.status, 1);
  assert.match(r.stdout, new RegExp(esc(w.localFile)));
  assert.match(r.stderr, /^not reset: nobody to confirm, so nothing was written; pass --yes to reset without a prompt$/m);
  assert.equal(w.read(), applied);
  assert.equal(w.records().length, 1);
});

test("#17354: reset prints one line per folder: restored, or skipped with its reason", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const [name] = w.records();
  const rec = JSON.parse(readFileSync(join(dataRecordsDir(w), name), "utf8"));
  const gone = join(w.root, "gone", ".claude", "settings.local.json");
  writeTree(dataRecordsDir(w), { "gone.json": { ...rec, settingsFile: gone } });
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [
    `Skipped ${gone}: folder not found; record kept.`,
    `Restored ${w.localFile} (profile build).`,
  ]);
  assert.deepEqual(w.records(), ["gone.json"]);
});

test("#17354: reset --yes --json prints only each file's result line, as data", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const r = reset(w, ["--yes", "--json"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(JSON.parse(r.stdout), { lines: [`Restored ${w.localFile} (profile build).`] });
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.equal(reset(w, ["--json"]).status, 2, "--json writes only with --yes");
});

test("#17354: a file reset cannot write is skipped with the reason, the files after it are still reset, and reset exits 3", { skip: process.platform === "win32" || process.getuid?.() === 0 }, () => {
  const w = world();
  const first = join(w.root, "aaa");
  writeTree(first, { ".claude/settings.local.json": LOCAL_BEFORE });
  assert.equal(runIn(w, first, ["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const firstFile = join(first, ".claude", "settings.local.json");
  const applied = readFileSync(firstFile, "utf8");
  chmodSync(join(first, ".claude"), 0o555);
  try {
    const r = reset(w, ["--yes"]);
    assert.equal(r.status, 3, r.stdout + r.stderr);
    assert.match(r.stdout, new RegExp(`^Skipped ${esc(firstFile)}: .*EACCES.*; run reset again\\.$`, "m"));
    assert.ok(resultLines(r.stdout).includes(`Restored ${w.localFile} (profile build).`), r.stdout);
    assert.doesNotMatch(r.stderr, /nothing written for this step/);
    assert.equal(readFileSync(firstFile, "utf8"), applied);
  } finally {
    chmodSync(join(first, ".claude"), 0o755);
  }
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("#17354: reset never writes a committed .claude/settings.json, even when a record names it", () => {
  const w = world();
  const committed = join(w.project, ".claude", "settings.json");
  const before = readFileSync(committed, "utf8");
  writeTree(dataRecordsDir(w), {
    "committed.json": {
      schema: 1, profile: "build", target: "folder", settingsFile: committed, appliedAt: "2026-11-01T00:00:00.000Z", pluginVersion: "0.6.1",
      phase: "applied", pending: {}, createdFile: false, createdFolder: false, containers: { enabledPlugins: true, skillOverrides: false }, installed: [],
      entries: { [`toolchain@${M}`]: { before: false, after: true } }, skillOverrides: {},
    },
  });
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [`Skipped ${committed}: reset writes only .claude/settings.local.json files and user settings; record kept.`]);
  assert.equal(readFileSync(committed, "utf8"), before);
  assert.deepEqual(w.records(), ["committed.json"]);
});

test("#17354: the reset preview names each entry edited since the apply, and the yes puts it back at its earlier value", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const doc = JSON.parse(w.read());
  doc.enabledPlugins[`implementation@${M}`] = false;
  writeFileSync(w.localFile, `${JSON.stringify(doc, null, 2)}\n`);
  const [row] = resetJson(w).folders;
  assert.deepEqual(row.overwrites, [{ name: `implementation@${M}`, current: false, before: "absent" }]);
  assert.ok(row.lines.includes(`  Overwrites a change made since the apply: implementation@${M} is false, the profile wrote true; reset puts back absent.`), row.lines.join("\n"));
  assert.equal(reset(w, ["--yes"]).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("#17354: the reset preview names a folder whose switch is unfinished in another session, and after reset that session's finish write leaves the folder restored", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes", "--defer-off"]).status, 0);
  const [row] = resetJson(w).folders;
  assert.equal(row.unfinished, true);
  assert.ok(row.lines.some((line) => /switch to build is unfinished in another session/.test(line)), row.lines.join("\n"));
  assert.equal(reset(w, ["--yes"]).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.match(w.run(["apply", "build", "--for", "folder", "--finish-pending"]).stdout, /^Nothing to finish/m);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("#17354: a worktree's own file and a subdirectory's own file with their own records are listed and restored", () => {
  const w = world();
  gitInit(w);
  const t = linkedWorktree(w, LOCAL_BEFORE);
  const sub = join(w.project, "src");
  writeTree(sub, { ".claude/settings.local.json": LOCAL_BEFORE });
  const subFile = join(sub, ".claude", "settings.local.json");
  for (const file of [t.file, subFile]) {
    const after = { ...JSON.parse(LOCAL_BEFORE), enabledPlugins: { [`songwriting@${M}`]: false, [`review@${M}`]: false } };
    writeFileSync(file, `${JSON.stringify(after, null, 2)}\n`);
    writeTree(dataRecordsDir(w), {
      [`${sha(realpathSync(file))}.json`]: {
        schema: 1, profile: "songs", target: "folder", settingsFile: file, appliedAt: "2026-01-01T00:00:00.000Z", pluginVersion: "0.1.0",
        phase: "applied", pending: {}, createdFile: false, containers: { enabledPlugins: true, skillOverrides: false }, installed: [],
        entries: { [`songwriting@${M}`]: { before: true, after: false } }, skillOverrides: {},
      },
    });
  }
  assert.deepEqual(recordedFiles(resetJson(w)), [t.file, subFile].sort());
  assert.equal(reset(w, ["--yes"]).status, 0);
  assert.equal(readFileSync(t.file, "utf8"), LOCAL_BEFORE);
  assert.equal(readFileSync(subFile, "utf8"), LOCAL_BEFORE);
  assert.deepEqual(w.records(), []);
});

test("#17354: a worktree copy adopted from the root's record is restored by reset before the root's record is removed", () => {
  const w = world();
  gitInit(w);
  const before = w.read();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const t = linkedWorktree(w, JSON.parse(w.read()));
  knowFolders(w, t.wt);
  const rows = resetJson(w).folders;
  assert.deepEqual(rows.filter((f) => f.adopted).map((f) => f.file), [t.file]);
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(readFileSync(t.file, "utf8"), before);
  assert.equal(w.read(), before);
  assert.deepEqual(gitRecords(w), []);
});

test("#17354: a reset cut off after one file's write leaves it restored and the rest untouched, and the next reset finishes the rest", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const p2 = secondFolder(w);
  const untouched = readFileSync(p2.file, "utf8");
  cutOff(w, w.localFile, { written: true });
  assert.notEqual(untouched, LOCAL_BEFORE);
  const rows = resetJson(w).folders;
  assert.deepEqual(rows.map((f) => [f.file, f.action]), [[w.localFile, "finish-restore"], [p2.file, "restore"]]);
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.ok(resultLines(r.stdout).includes(`Finished an earlier reset of ${w.localFile}: its record is removed.`), r.stdout);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.equal(readFileSync(p2.file, "utf8"), LOCAL_BEFORE);
  assert.deepEqual(w.records(), []);
});

test("#17354: a reset cut off before a file's write leaves its record restoring, and the next reset restores the file", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  cutOff(w, w.localFile, { written: false });
  assert.equal(resetJson(w).folders[0].action, "restore");
  assert.equal(reset(w, ["--yes"]).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual(w.records(), []);
});

const CUT_OFF_SKIP = (file) => `Skipped ${file}: an earlier reset of it was cut off and it changed since; reset puts back its entries still at the profile's values only after a yes for this file, so the file and its record are kept.`;
/** Codex's case: a reset cut off before the file's write, then songwriting put back to its value before the profile by hand. */
function cutOffThenPutBack(w) {
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  cutOff(w, w.localFile, { written: false });
  const doc = JSON.parse(w.read());
  doc.enabledPlugins[`songwriting@${M}`] = true;
  writeFileSync(w.localFile, `${JSON.stringify(doc, null, 2)}\n`);
  return w.read();
}

test("#17354: a file changed after a reset was cut off, with an entry still at the profile's value, is not reverted without a yes for it, and its restoring record is kept", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  cutOff(w, w.localFile, { written: true });
  const edited = { ...JSON.parse(LOCAL_BEFORE), enabledPlugins: { ...JSON.parse(LOCAL_BEFORE).enabledPlugins, [`songwriting@${M}`]: false } };
  writeFileSync(w.localFile, `${JSON.stringify(edited, null, 2)}\n`);
  const kept = w.read();
  const [row] = resetJson(w).folders;
  assert.deepEqual([row.action, row.ask?.file, row.entries], ["finish-cut-off", w.localFile, [`songwriting@${M}`]]);
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [CUT_OFF_SKIP(w.localFile)]);
  assert.equal(w.read(), kept);
  assert.equal(JSON.parse(readFileSync(dataRecordOf(w, w.localFile), "utf8")).phase, "restoring");
});

test("#17354: a reset cut off before a file's write, then an entry put back by hand, keeps the record and asks; the yes puts back the entries still at the profile's values and removes the record", () => {
  const w = world();
  cutOffThenPutBack(w);
  const preview = resetJson(w);
  const [row] = preview.folders;
  const still = Object.keys(JSON.parse(readFileSync(dataRecordOf(w, w.localFile), "utf8")).entries).filter((id) => id !== `songwriting@${M}`);
  assert.deepEqual([row.action, row.recorded, row.entries], ["finish-cut-off", true, still]);
  const few = `${still.slice(0, 3).join(", ")}${still.length > 3 ? ` and ${still.length - 3} more` : ""}`;
  assert.deepEqual(row.ask, {
    file: w.localFile,
    question: `An earlier reset of ${w.localFile} was cut off and the file changed since. Put back the ${still.length} entries still at the values profile build wrote (${few}) to their values from before the profile? Entries changed by hand since stay as they are; no keeps the file and its record.`,
    yes: { label: "Put back", flag: "--finish-cut-off" },
    no: { label: "Keep", flag: "--keep-cut-off" },
    recommend: { answer: "yes", reason: "Each entry profile build wrote is still at that value or back at its value from before, so a yes changes only what that profile wrote." },
  });
  assert.deepEqual(row.lines, [
    `${w.localFile}: an earlier reset of this file was cut off and the file changed since. ${still.length} entries still hold the values profile build wrote: ${few}.`,
    `  A yes for this file puts those back to their values from before the profile and leaves the 1 entry changed by hand since as it is (songwriting@${M}); a no keeps the file and its record.`,
  ]);
  assert.equal(preview.question, null, "the one question covers no file here");
  const r = reset(w, ["--yes", "--finish-cut-off", w.localFile]);
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.deepEqual(resultLines(r.stdout), [`Restored ${w.localFile}: put back the ${still.length} entries still at the values profile build wrote, and left the entries changed by hand since as they are.`]);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual(w.records(), []);
  assert.deepEqual(resetJson(w).folders, [], "the restored note keeps it off the next preview");
});

test("#17354: a cut-off reset's changed file answered no, or given --yes alone, or with nobody to answer, writes nothing and keeps its record", () => {
  const w = world();
  const changed = cutOffThenPutBack(w);
  const record = readFileSync(dataRecordOf(w, w.localFile), "utf8");
  const no = reset(w, ["--yes", "--keep-cut-off", w.localFile]);
  assert.equal(no.status, 0, no.stderr);
  assert.deepEqual(resultLines(no.stdout), [`Skipped ${w.localFile}: you answered no, so it is left as it is, and its record is kept.`]);
  const plain = reset(w, ["--yes"]);
  assert.equal(plain.status, 0, plain.stderr);
  assert.deepEqual(resultLines(plain.stdout), [CUT_OFF_SKIP(w.localFile)]);
  const nobody = reset(w);
  assert.equal(nobody.status, 1, nobody.stdout);
  assert.match(nobody.stderr, /^not reset: nobody to confirm, so nothing was written; a file whose earlier reset was cut off changes only after a yes for it: run reset in a terminal, or pass --yes with --finish-cut-off <file> for each file to put back$/m);
  assert.deepEqual(resultLines(nobody.stdout), []);
  assert.equal(reset(w, ["--yes", "--remove-unrecorded", w.localFile]).status, 1, "the unrecorded flags do not answer this file");
  assert.equal(w.read(), changed);
  assert.equal(readFileSync(dataRecordOf(w, w.localFile), "utf8"), record);
});

test("#17354: a file whose cut-off reset finished and which was then edited, with no entry left at the profile's value, keeps the edit and loses its record", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  cutOff(w, w.localFile, { written: true });
  const doc = JSON.parse(w.read());
  doc.enabledPlugins[`implementation@${M}`] = false;
  writeFileSync(w.localFile, `${JSON.stringify(doc, null, 2)}\n`);
  const kept = w.read();
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [`Skipped ${w.localFile}: edited since an earlier reset restored it; left as it is, and its record is removed.`]);
  assert.equal(w.read(), kept);
  assert.deepEqual(w.records(), []);
});

test("#17354: the preview id changes when a cut-off reset's changed file changes again, and a write given the old id refuses", () => {
  const w = world();
  cutOffThenPutBack(w);
  const shown = resetJson(w).previewId;
  const doc = JSON.parse(w.read());
  doc.enabledPlugins[`review@${M}`] = false;
  writeFileSync(w.localFile, `${JSON.stringify(doc, null, 2)}\n`);
  const changed = w.read();
  assert.notEqual(resetJson(w).previewId, shown);
  const r = reset(w, ["--yes", "--finish-cut-off", w.localFile, "--preview-id", shown]);
  assert.equal(r.status, 1, r.stdout);
  assert.match(r.stderr, /^not reset: what reset would write changed since that preview /m);
  assert.equal(w.read(), changed);
});

test("#17354: a reset cut off before a file's write, then a hand edit of one profile entry to a third value, keeps the record and asks; the yes puts back the other entries and leaves the edit", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  cutOff(w, w.localFile, { written: false });
  const doc = JSON.parse(w.read());
  doc.enabledPlugins[`implementation@${M}`] = false;
  writeFileSync(w.localFile, `${JSON.stringify(doc, null, 2)}\n`);
  const edited = w.read();
  const record = readFileSync(dataRecordOf(w, w.localFile), "utf8");
  const [row] = resetJson(w).folders;
  assert.equal(row.action, "finish-cut-off");
  assert.equal(row.ask.file, w.localFile);
  assert.deepEqual(row.ask.yes, { label: "Put back", flag: "--finish-cut-off" });
  assert.deepEqual(row.overwrites, [], "the hand edit is never overwritten, so none is named");
  assert.ok(!row.entries.includes(`implementation@${M}`) && row.entries.length > 0, JSON.stringify(row.entries));
  const plain = reset(w, ["--yes"]);
  assert.equal(plain.status, 0, plain.stderr);
  assert.deepEqual(resultLines(plain.stdout), [CUT_OFF_SKIP(w.localFile)]);
  assert.equal(w.read(), edited);
  assert.equal(readFileSync(dataRecordOf(w, w.localFile), "utf8"), record);
  assert.equal(JSON.parse(record).phase, "restoring");
  const r = reset(w, ["--yes", "--finish-cut-off", w.localFile]);
  assert.equal(r.status, 0, r.stderr);
  const before = JSON.parse(LOCAL_BEFORE);
  assert.deepEqual(JSON.parse(w.read()), { ...before, enabledPlugins: { ...before.enabledPlugins, [`implementation@${M}`]: false } });
  assert.deepEqual(w.records(), []);
});

test("#17354: a reset of an unfinished switch cut off before its write, then an entry put back by hand, keeps the record while an entry the switch still owes holds an earlier profile's value, and the yes puts those back too", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.equal(w.run(["apply", "native", "--for", "folder", "--yes", "--defer-off"]).status, 0);
  const rec = JSON.parse(readFileSync(dataRecordOf(w, w.localFile), "utf8"));
  const owed = Object.keys(rec.pending);
  assert.ok(rec.phase === "off-pending" && owed.length > 0 && rec.entries[`songwriting@${M}`] && !owed.includes(`songwriting@${M}`), JSON.stringify(rec));
  cutOff(w, w.localFile, { written: false });
  const doc = JSON.parse(w.read());
  doc.enabledPlugins[`songwriting@${M}`] = true;
  writeFileSync(w.localFile, `${JSON.stringify(doc, null, 2)}\n`);
  const [row] = resetJson(w).folders;
  assert.equal(row.action, "finish-cut-off");
  for (const id of owed) assert.ok(row.entries.includes(id), `${id} still holds build's value: ${row.entries}`);
  const r = reset(w, ["--yes", "--finish-cut-off", w.localFile]);
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual(w.records(), []);
});

test("#17354: a stray temp file beside an untouched file is ignored", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  writeTree(w.project, { ".claude/.settings.local.json.4242.1.tmp": "{\"enabledPlugins\": {" });
  writeTree(dataRecordsDir(w), { [`.${w.records()[0]}.4242.1.tmp`]: "{" });
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [`Restored ${w.localFile} (profile build).`]);
  assert.equal(w.read(), LOCAL_BEFORE);
});

test("#17354: with records in two homes, reset restores the file once and removes both records", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const [name] = gitRecords(w);
  mkdirSync(dataRecordsDir(w), { recursive: true });
  cpSync(join(w.project, ".git", "plugin-profiles", "records", name), join(dataRecordsDir(w), name));
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [`Restored ${rootLocal(w.project)} (profile build).`]);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual([gitRecords(w), w.records()], [[], []]);
});

test("#17354: a file another writer changes during reset is skipped as changed, left as written, and the next reset restores it", async () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const p2 = secondFolder(w);
  let other = null;
  const r = await resetDuring(w, ["--yes"], (line) => {
    other = [w.localFile, p2.file].find((f) => !line.includes(f));
    const doc = JSON.parse(readFileSync(other, "utf8"));
    doc.permissions.allow.push("Bash(other-writer)");
    writeFileSync(other, `${JSON.stringify(doc, null, 2)}\n`);
  });
  assert.equal(r.status, 3, r.stdout);
  assert.ok(resultLines(r.stdout).includes(`Skipped ${other}: it changed during the reset and is left as the other writer left it; run reset again.`), r.stdout);
  const left = JSON.parse(readFileSync(other, "utf8"));
  assert.equal(left.enabledPlugins[`songwriting@${M}`], false, "the profile's entries are still there");
  const again = reset(w, ["--yes"]);
  assert.equal(again.status, 0, again.stderr);
  const restored = JSON.parse(readFileSync(other, "utf8"));
  assert.deepEqual(restored.enabledPlugins, JSON.parse(LOCAL_BEFORE).enabledPlugins);
  assert.deepEqual(restored.permissions.allow, ["Bash(npm test)", "Bash(other-writer)"]);
  assert.deepEqual(w.records(), []);
});

test("#17354: a record an apply re-saves during reset is reported and reset exits 3", async () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const p2 = secondFolder(w);
  let reapplied = null;
  const r = await resetDuring(w, ["--yes"], (line) => {
    const done = [w.project, p2.dir].find((d) => line.includes(join(d, ".claude")));
    reapplied = join(done, ".claude", "settings.local.json");
    assert.equal(runIn(w, done, ["apply", "review", "--for", "folder", "--yes"]).status, 0);
  });
  assert.equal(r.status, 3, r.stdout);
  assert.match(r.stdout, new RegExp(`^Another terminal applied a profile to ${esc(reapplied)} during the reset; run reset again\\.$`, "m"));
  assert.equal(recordedFiles(resetJson(w)).includes(reapplied), true, "the re-saved record is still there for the next reset");
});

test("#17354: a file another reset already restored is reported as already restored", async () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const p2 = secondFolder(w);
  let other = null;
  const r = await resetDuring(w, ["--yes"], (line) => {
    other = [w.project, p2.dir].find((d) => !line.includes(join(d, ".claude")));
    assert.equal(runIn(w, other, ["clear", "--yes"]).status, 0);
  });
  assert.equal(r.status, 0, r.stdout);
  assert.ok(resultLines(r.stdout).includes(`Already restored by another reset: ${join(other, ".claude", "settings.local.json")}.`), r.stdout);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.equal(readFileSync(p2.file, "utf8"), LOCAL_BEFORE);
  assert.deepEqual(w.records(), []);
});

/** Each plugin and skill entry in force for a session started with sessionFile, read in Claude Code's order: --settings over local over project over user. */
function inForce(w, sessionFile) {
  const docs = [sessionFile, w.localFile, join(w.project, ".claude", "settings.json"), join(w.home, ".claude", "settings.json")].map((f) => (existsSync(f) ? JSON.parse(readFileSync(f, "utf8")) : {}));
  const of = (key) => {
    const names = [...new Set(docs.flatMap((d) => Object.keys(d[key] ?? {})))].sort();
    return Object.fromEntries(names.map((n) => [n, docs.map((d) => d[key]?.[n]).find((v) => v !== undefined)]));
  };
  return { plugins: of("enabledPlugins"), skills: of("skillOverrides") };
}
/** A user profile of another marketplace than the shipped ones, so profiles govern two marketplaces. */
const vendorProfile = (w) => writeTree(w.home, { ".claude/plugin-profiles/gadgets.yaml": "description: Vendor gadgets.\nplugins: [widget@vendor]\nhide_skills: [gadget-skill]\n" });
const setUserPlugin = (w, id, value) => {
  const file = join(w.home, ".claude", "settings.json");
  const doc = JSON.parse(readFileSync(file, "utf8"));
  doc.enabledPlugins[id] = value;
  writeFileSync(file, `${JSON.stringify(doc, null, 2)}\n`);
};

test("#17354: a one-session file keeps every plugin and skill entry in force after a reset of the folder and the initial profile, and is left byte for byte", () => {
  const w = world();
  vendorProfile(w);
  setUserPlugin(w, "widget@vendor", false);
  const session = launchJson(w, ["review"]).file;
  const bytes = readFileSync(session, "utf8");
  assert.equal(w.run(["apply", "gadgets", "--for", "folder", "--yes"]).status, 0);
  assert.equal(runIn(w, elsewhere(w), ["apply", "build", "--for", "initial", "--yes"]).status, 0);
  const before = inForce(w, session);
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(w.read(), LOCAL_BEFORE, "the folder was reset");
  assert.deepEqual(inForce(w, session), before);
  assert.equal(readFileSync(session, "utf8"), bytes);
});

test("#17354: a one-session file names every plugin of every marketplace any profile governs, so a user-settings toggle of such a plugin made after launch does not reach that session", () => {
  const w = world();
  vendorProfile(w);
  setUserPlugin(w, "widget@vendor", true);
  const session = launchJson(w, ["review"]).file;
  const doc = JSON.parse(readFileSync(session, "utf8"));
  assert.equal(doc.enabledPlugins["widget@vendor"], true, "frozen at its value at launch");
  assert.equal(doc.skillOverrides["gadget-skill"], "on");
  setUserPlugin(w, "widget@vendor", false);
  assert.equal(inForce(w, session).plugins["widget@vendor"], true, "the later toggle in user settings does not reach the running session");
  const plain = world();
  const untouched = JSON.parse(readFileSync(launchJson(plain, ["review"]).file, "utf8"));
  assert.equal("widget@vendor" in untouched.enabledPlugins, false, "a marketplace no profile governs stays unnamed");
});

test("#17354: every reset row in scenarios.md names a test that exists", () => {
  const read = (rel) => readFileSync(join(HERE, "..", rel), "utf8");
  const scenarios = read("reference/scenarios.md");
  const section = scenarios.slice(scenarios.indexOf("## Reset the whole machine"), scenarios.indexOf("## Dotfiles"));
  const rows = section.split("\n").filter((line) => /^\| \d+ \|/.test(line));
  assert.ok(rows.length >= 8, `${rows.length} reset rows`);
  const names = (rel) => new Set([...read(rel).matchAll(/\btest\((["'])((?:\\.|(?!\1).)*)\1/g)].map((m) => m[2]));
  const suites = { "scripts/profiles.test.mjs": names("scripts/profiles.test.mjs"), "lib/machine-records.test.mjs": names("lib/machine-records.test.mjs"), "hooks/plugin-profile.test.ts": names("hooks/plugin-profile.test.ts") };
  for (const row of rows) {
    const proof = row.split(" | ").at(-1);
    const quoted = [...proof.matchAll(/(?:`([^`]+\.test\.[a-z]+)` )?"([^"]+)"/g)];
    assert.ok(quoted.length, `row names no test: ${row.slice(0, 60)}`);
    let suite = "scripts/profiles.test.mjs";
    for (const [, file, name] of quoted) {
      if (file) suite = file;
      assert.ok(suites[suite]?.has(name), `${suite} has no test "${name}"`);
    }
  }
});

const NO_RECORD_SKIP = (file) => `Skipped ${file}: no record; reset removes its entries only after a yes for this folder.`;

test("#17354: a folder with plugin entries and no record is listed with each entry and changed only after its own yes", () => {
  const w = world();
  knowFolders(w, w.project);
  const [row] = resetJson(w).folders;
  assert.deepEqual([row.file, row.recorded, row.action, row.entries], [w.localFile, false, "remove-entries", [`songwriting@${M}`, `review@${M}`]]);
  assert.equal(row.ask.file, w.localFile);
  assert.ok(row.lines[0].includes(`songwriting@${M}, review@${M}`), row.lines[0]);
  const plain = reset(w, ["--yes"]);
  assert.equal(plain.status, 0, plain.stderr);
  assert.deepEqual(resultLines(plain.stdout), [NO_RECORD_SKIP(w.localFile)]);
  assert.equal(w.read(), LOCAL_BEFORE, "--yes alone never covers a folder without a record");
  const wrong = reset(w, ["--yes", "--remove-unrecorded", join(w.root, "elsewhere", ".claude", "settings.local.json")]);
  assert.equal(wrong.status, 1);
  assert.match(wrong.stderr, /not reset: .* is not a file the preview asks about; it asks about .*; nothing was written/);
  assert.equal(w.read(), LOCAL_BEFORE);
  const r = reset(w, ["--yes", "--remove-unrecorded", w.localFile]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [`Removed the 2 plugin and skill entries of ${w.localFile}, which had no record.`]);
  const after = JSON.parse(w.read());
  assert.equal("enabledPlugins" in after, false);
  assert.deepEqual(after, withoutProfileKeys(LOCAL_BEFORE));
});

test("#17354: the reset preview's questions say what each yes covers, and stay short for a folder with many entries", () => {
  const w = world();
  const p2 = secondFolder(w);
  const many = Object.fromEntries(Array.from({ length: 10 }, (_, i) => [`p${i}@${M}`, true]));
  writeFileSync(w.localFile, `${JSON.stringify({ enabledPlugins: many }, null, 2)}\n`);
  knowFolders(w, w.project, p2.dir);
  const preview = resetJson(w);
  assert.equal(preview.question, "Reset the 1 file above that a profile record covers? Folders without a record are not covered: each gets its own question.");
  const loose = preview.folders.find((f) => f.file === w.localFile);
  assert.equal(loose.ask.question, `${w.localFile} has no profile record. Remove its 10 plugin and skill entries (p0@${M}, p1@${M}, p2@${M} and 7 more, listed above)?`);
  assert.equal(loose.lines[0], `${w.localFile}: no profile record, and its 10 plugin and skill entries may be your own: ${Object.keys(many).join(", ")}. Reset removes them only after a yes for this folder.`);
  assert.match(preview.lines[0], /this folder, 1 data folder, 0 repository pointers, 2 folders Claude Code has opened, 0 one-session records and 0 live sessions\.$/);
  knowFolders(w, p2.dir);
  assert.equal(resetJson(w).question, "Reset the 1 file above that a profile record covers?");
});

test("#17354: a folder without a record holding one entry is named as one entry in its preview line, its question and its result", () => {
  const w = world();
  writeFileSync(w.localFile, `${JSON.stringify({ enabledPlugins: { [`p0@${M}`]: true } }, null, 2)}\n`);
  knowFolders(w, w.project);
  const [row] = resetJson(w).folders;
  assert.equal(row.ask.question, `${w.localFile} has no profile record. Remove its 1 plugin and skill entry (p0@${M})?`);
  assert.equal(row.lines[0], `${w.localFile}: no profile record, and its 1 plugin and skill entry may be your own: p0@${M}. Reset removes it only after a yes for this folder.`);
  const r = reset(w, ["--yes", "--remove-unrecorded", w.localFile]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [`Removed the 1 plugin and skill entry of ${w.localFile}, which had no record.`]);
});

test("#17354: the one question says once that folders without a record and files whose earlier reset was cut off each get their own question", () => {
  const w = world();
  cutOffThenPutBack(w);
  secondFolder(w);
  const loose = join(w.root, "loose");
  writeTree(loose, { ".claude/settings.local.json": LOCAL_BEFORE });
  knowFolders(w, loose);
  const preview = resetJson(w);
  assert.deepEqual(preview.folders.map((f) => f.action).sort(), ["finish-cut-off", "remove-entries", "restore"]);
  assert.equal(preview.question, "Reset the 1 file above that a profile record covers? Folders without a record and files whose earlier reset was cut off are not covered: each gets its own question.");
});

test("#17354: the reset preview gives each apply's time in the machine's time zone", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const [name] = w.records();
  const path = join(dataRecordsDir(w), name);
  writeFileSync(path, `${JSON.stringify({ ...JSON.parse(readFileSync(path, "utf8")), appliedAt: "2026-11-01T00:00:00.000Z" }, null, 2)}\n`);
  const [row] = resetJson(w, { TZ: "America/New_York" }).folders;
  assert.match(row.lines[0], /: profile build applied Oct 31, 2026, 8:00\sPM EDT; reset puts back /);
});

test("#17354: a folder answered no is reported as kept at that answer, not as waiting for a yes", () => {
  const w = world();
  knowFolders(w, w.project);
  const r = reset(w, ["--yes", "--keep-unrecorded", w.localFile]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [`Skipped ${w.localFile}: you answered no, so it is left as it is.`]);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.equal(reset(w, ["--yes", "--keep-unrecorded", join(w.root, "x.json")]).status, 1, "a kept file the preview does not ask about is refused too");
});

test("#17354: askPerFolder removes only the folders answered yes", async () => {
  const input = new PassThrough();
  const output = new PassThrough();
  let shown = "";
  output.on("data", (chunk) => {
    shown += chunk;
  });
  const rows = ["/a", "/b", "/c"].map((file) => ({ file, question: `Remove ${file}?` }));
  const answered = askPerFolder(rows, { input, output });
  input.write("y\n");
  input.write("no\n");
  input.end();
  assert.deepEqual([...(await answered)], ["/a"]);
  assert.match(shown, /Remove \/a\? \[y\/N\] .*Remove \/b\? \[y\/N\] /s);
  assert.deepEqual([...(await askPerFolder([], { input: new PassThrough(), output }))], []);
});

test("#17354: with --yes and nobody answering, reset restores every recorded folder and skips each unrecorded one, saying why", () => {
  const w = world();
  const p2 = secondFolder(w);
  knowFolders(w, w.project, p2.dir);
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [NO_RECORD_SKIP(w.localFile), `Restored ${p2.file} (profile build).`]);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.equal(readFileSync(p2.file, "utf8"), LOCAL_BEFORE);
});

test("#17354: a record whose folder is missing is kept, listed as not found, and a git-home record names the moved file it would restore", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const old = rootLocal(w.project);
  const moved = join(w.root, "moved");
  renameSync(w.project, moved);
  knowFolders(w, moved);
  const movedFile = rootLocal(moved);
  const rows = resetJson(w).folders;
  assert.deepEqual(rows.map((f) => [f.file, f.action, f.movedTo ?? null]), [[old, "skip", movedFile]], "the moved file is offered once, through the record");
  assert.equal(rows[0].ask.file, movedFile);
  assert.match(rows[0].lines[0], /folder not found; record kept\. The repository is now at /);
  const kept = reset(w, ["--yes"]);
  assert.equal(kept.status, 0, kept.stderr);
  assert.deepEqual(resultLines(kept.stdout), [`Skipped ${old}: folder not found; record kept.`]);
  assert.notEqual(readFileSync(movedFile, "utf8"), LOCAL_BEFORE);
  assert.equal(readdirSync(join(moved, ".git", "plugin-profiles", "records")).length, 1);
  const r = reset(w, ["--yes", "--put-back-moved", movedFile]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [`Restored ${movedFile} from the record of ${old} (profile build).`]);
  assert.equal(readFileSync(movedFile, "utf8"), LOCAL_BEFORE);
  assert.deepEqual(readdirSync(join(moved, ".git", "plugin-profiles", "records")), []);
});

test("#17354: a moved repository's file gets its own kind of question: Keep, then Put back, its own flags, its own words in the one question and its own recommendation", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const old = rootLocal(w.project);
  const moved = join(w.root, "moved");
  renameSync(w.project, moved);
  const p2 = secondFolder(w);
  knowFolders(w, moved, p2.dir);
  const movedFile = rootLocal(moved);
  const applied = [readFileSync(movedFile, "utf8"), readFileSync(p2.file, "utf8")];
  const preview = resetJson(w);
  const { ask } = preview.folders.find((f) => f.file === old);
  assert.deepEqual([ask.file, ask.no, ask.yes], [movedFile, { label: "Keep", flag: "--keep-moved" }, { label: "Put back", flag: "--put-back-moved" }]);
  assert.deepEqual(ask.recommend, { answer: "yes", reason: `Each entry profile build wrote at ${old}, before the repository moved, is still at that value or back at its value from before, so a yes changes only what that profile wrote.` });
  assert.equal(preview.question, "Reset the 1 file above that a profile record covers? A file in a repository that moved is not covered: each gets its own question.");
  for (const flag of ["--remove-unrecorded", "--keep-unrecorded", "--finish-cut-off"]) {
    const r = reset(w, ["--yes", flag, movedFile]);
    assert.equal(r.status, 1, `${flag}: ${r.stdout}`);
    assert.match(r.stderr, new RegExp(`^not reset: ${esc(movedFile)} is answered with --put-back-moved or --keep-moved, not ${flag}; nothing was written$`, "m"));
  }
  const loose = reset(w, ["--yes", "--put-back-moved", join(w.root, "elsewhere", ".claude", "settings.local.json")]);
  assert.equal(loose.status, 1);
  assert.match(loose.stderr, new RegExp(`is not a file the preview asks about; it asks about ${esc(movedFile)} `));
  assert.deepEqual([readFileSync(movedFile, "utf8"), readFileSync(p2.file, "utf8")], applied);
  const r = reset(w, ["--yes", "--put-back-moved", movedFile]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout).sort(), [`Restored ${movedFile} from the record of ${old} (profile build).`, `Restored ${p2.file} (profile build).`].sort());
  assert.equal(readFileSync(movedFile, "utf8"), LOCAL_BEFORE);

  const alone = world();
  gitInit(alone);
  assert.equal(alone.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const there = join(alone.root, "moved");
  renameSync(alone.project, there);
  knowFolders(alone, there);
  const nobody = reset(alone);
  assert.equal(nobody.status, 1, nobody.stdout);
  assert.match(nobody.stderr, /^not reset: nobody to confirm, so nothing was written; a file in a repository that moved changes only after a yes for it: run reset in a terminal, or pass --yes with --put-back-moved <file> for each file to put back$/m);
});

/** The settings file each applied-profile record on the test machine names, sorted. */
const recordFiles = (w) => allRecords(w).map((rel) => JSON.parse(readFileSync(join(w.root, rel), "utf8")).settingsFile).sort();
const WAITS_SKIP = (file) => `Skipped ${file}: folder not found; record kept until reset puts back the later record of its repository's file.`;
const WAITS_DONE = (file) => `Skipped ${file}: folder not found; record kept. This reset put back a later record of its repository's file; run reset again to be offered the next record, newest first.`;
const WAITS_LINE = (n) => `${n} ${n === 1 ? "record waits" : "records wait"} behind a file this reset put back; run reset again to offer ${n === 1 ? "it" : "them"}.`;
const waitsRow = (old, file) => `${old}: folder not found; record kept. The repository is now at ${dirname(dirname(file))}, and ${file} has a later record that reset handles first; running reset again afterwards offers this one.`;

/**
 * Runs reset until no record is left (at most max runs), each run answering yes to the one question and to each file's own, and
 * checks every run: no file is asked about twice, each listed file gets one result line, and a record goes only with its own
 * file's restore. Returns each run's exit status.
 */
function resetLayers(w, max = 4) {
  const statuses = [];
  while (recordFiles(w).length && statuses.length < max) {
    const run = `run ${statuses.length + 1}`;
    const preview = resetJson(w);
    const asks = preview.folders.filter((f) => f.ask).map((f) => f.ask);
    const covered = preview.question ? preview.folders.filter((f) => ["restore", "remove-file", "finish-restore"].includes(f.action)).map((f) => f.file) : [];
    const asked = [...covered, ...asks.map((a) => a.file)];
    assert.equal(new Set(asked).size, asked.length, `${run}: one question per file: ${asked.join(", ")}`);
    const before = recordFiles(w);
    const r = reset(w, ["--yes", ...asks.flatMap((a) => [a.yes.flag, a.file])]);
    const lines = resultLines(r.stdout);
    for (const f of preview.folders) assert.equal(lines.filter((l) => l.includes(f.file)).length, 1, `${run}: one result line names ${f.file}\n${r.stdout}`);
    const put = preview.folders.filter((f) => lines.some((l) => /^(Restored|Removed|Finished) /.test(l) && l.includes(f.file))).map((f) => f.file);
    const left = recordFiles(w);
    for (const gone of before.filter((file) => !left.includes(file))) assert.ok(put.includes(gone), `${run}: the record of ${gone} goes only with its own restore\n${r.stdout}`);
    statuses.push(r.status);
  }
  return statuses;
}

/** A repository given profile build, then moved to repo-now and given each profile of then there in turn; left holds the file before each of those. */
function movedRepository(w, then = ["review"]) {
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const old = rootLocal(w.project);
  const moved = join(w.root, "repo-now");
  renameSync(w.project, moved);
  knowFolders(w, moved);
  const file = rootLocal(moved);
  const left = then.map((profile) => {
    const text = readFileSync(file, "utf8");
    assert.equal(runIn(w, moved, ["apply", profile, "--for", "folder", "--yes"]).status, 0);
    return text;
  });
  return { old, file, left, records: join(moved, ".git", "plugin-profiles", "records") };
}

/** A repository given build, moved and given review, then moved again and given newest: its three files and the file after each apply before the last. */
function movedTwice(w, newest = "build") {
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const first = rootLocal(w.project);
  const afterBuild = readFileSync(first, "utf8");
  const between = join(w.root, "repo-between");
  renameSync(w.project, between);
  assert.equal(runIn(w, between, ["apply", "review", "--for", "folder", "--yes"]).status, 0);
  const second = rootLocal(between);
  const now = join(w.root, "repo-now");
  renameSync(between, now);
  knowFolders(w, now);
  const file = rootLocal(now);
  const afterReview = readFileSync(file, "utf8");
  assert.equal(runIn(w, now, ["apply", newest, "--for", "folder", "--yes"]).status, 0);
  return { first, second, file, afterBuild, afterReview, records: join(now, ".git", "plugin-profiles", "records") };
}

test("#17354: a moved repository with a profile applied at its new place is put back one layer per reset, newest first, one question per file each run", async () => {
  const w = world();
  const m = movedRepository(w);
  const rows = resetJson(w).folders;
  assert.deepEqual(rows.map((f) => [f.file, f.action, f.movedTo ?? null, f.ask?.file ?? null, f.waitsFor ?? null]).sort(), [[m.file, "restore", null, null, null], [m.old, "skip", null, null, m.file]].sort());
  assert.deepEqual(rows.find((f) => f.file === m.old).lines, [waitsRow(m.old, m.file)]);
  const first = await resetAtTerminal(w, () => "y");
  assert.equal(first.status, 3, first.stdout + first.stderr);
  assert.deepEqual(first.prompts.map((p) => FIRST.test(p)), [true], "one question, covering the newer record's file");
  assert.deepEqual(resultLines(first.stdout).sort(), [`Restored ${m.file} (profile review).`, WAITS_DONE(m.old)].sort());
  assert.equal(first.stdout.split("\n").at(-1), WAITS_LINE(1));
  assert.equal(readFileSync(m.file, "utf8"), m.left[0]);
  assert.deepEqual(recordFiles(w), [m.old]);
  const second = await resetAtTerminal(w, () => "y");
  assert.equal(second.status, 0, second.stdout + second.stderr);
  assert.deepEqual(second.prompts, [`The folder of ${m.old} is gone, and its repository is now at ${dirname(dirname(m.file))}. Put back ${m.file} from that record?`]);
  assert.deepEqual(resultLines(second.stdout), [`Restored ${m.file} from the record of ${m.old} (profile build).`]);
  assert.equal(readFileSync(m.file, "utf8"), LOCAL_BEFORE);
  assert.deepEqual(recordFiles(w), []);

  const again = world();
  const n = movedRepository(again);
  assert.deepEqual(resetLayers(again), [3, 0]);
  assert.equal(readFileSync(n.file, "utf8"), LOCAL_BEFORE);
});

test("#17354: apply's preview in a moved repository with a record from before the move says in one line that reset puts the file back one layer per run, newest first", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const plainLines = JSON.parse(w.run(["apply", "review", "--for", "folder", "--dry-run", "--json"]).stdout).lines;
  assert.ok(!plainLines.some((l) => l.includes("before this repository moved")), "a repository that did not move gets no such line");
  const old = rootLocal(w.project);
  const moved = join(w.root, "repo-now");
  renameSync(w.project, moved);
  const line = `Reset keeps the record of ${old} (profile build) from before this repository moved; after this apply, reset puts this file back one layer per run, newest first.`;
  const dry = runIn(w, moved, ["apply", "review", "--for", "folder", "--dry-run"]);
  assert.equal(dry.status, 0, dry.stderr);
  assert.equal(dry.stdout.split("\n").filter((l) => l === line).length, 1, dry.stdout);
  const json = JSON.parse(runIn(w, moved, ["apply", "review", "--for", "folder", "--dry-run", "--json"]).stdout);
  assert.equal(json.lines.filter((l) => l === line).length, 1, json.lines.join("\n"));
});

test("#17354: the newest layer's row says it puts entries back to before that layer's profile while an older record waits, and to before the first apply only when none waits", () => {
  const w = world();
  const m = movedRepository(w);
  const row = resetJson(w).folders.find((f) => f.file === m.file);
  assert.match(row.lines[0], /; reset puts back \d+ plugin entr(y|ies) and \d+ skill entr(y|ies) to their values before profile review was applied\.$/, row.lines[0]);
  const plain = world();
  assert.equal(plain.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const [only] = resetJson(plain).folders;
  assert.match(only.lines[0], /; reset puts back \d+ plugin entr(y|ies) and \d+ skill entr(y|ies) to their values before the first apply\.$/, only.lines[0]);
});

test("#17354: a moved repository with a profile applied at its new place, given --yes alone, puts back the newer layer, keeps the older record until a yes for its file, and a reset cut off before or after the newer layer's write is finished first", () => {
  for (const cut of [null, "before the write", "after the write"]) {
    const w = world();
    const m = movedRepository(w);
    const newerPath = join(m.records, `${sha(m.file)}.json`);
    if (cut) {
      const rec = JSON.parse(readFileSync(newerPath, "utf8"));
      writeFileSync(newerPath, `${JSON.stringify({ ...rec, phase: "restoring", restoredHash: sha(m.left[0]), fromHash: sha(readFileSync(m.file, "utf8")) }, null, 2)}\n`);
      if (cut === "after the write") writeFileSync(m.file, m.left[0]);
    }
    assert.equal(resetJson(w).question, "Reset the 1 file above that a profile record covers?", `cut ${cut}`);
    const r = reset(w, ["--yes"]);
    assert.equal(r.status, 3, r.stdout + r.stderr);
    const done = cut === "after the write" ? `Finished an earlier reset of ${m.file}: its record is removed.` : `Restored ${m.file} (profile review).`;
    assert.deepEqual(resultLines(r.stdout).sort(), [done, WAITS_DONE(m.old)].sort(), `cut ${cut}`);
    assert.equal(r.stdout.trim().split("\n").at(-1), WAITS_LINE(1));
    assert.equal(readFileSync(m.file, "utf8"), m.left[0], `cut ${cut}`);
    assert.deepEqual(recordFiles(w), [m.old], `cut ${cut}`);
    const plain = reset(w, ["--yes"]);
    assert.equal(plain.status, 0, plain.stdout + plain.stderr);
    assert.deepEqual(resultLines(plain.stdout), [`Skipped ${m.old}: folder not found; record kept.`]);
    assert.equal(readFileSync(m.file, "utf8"), m.left[0], `cut ${cut}`);
    assert.deepEqual(resetLayers(w), [0], `cut ${cut}`);
    assert.equal(readFileSync(m.file, "utf8"), LOCAL_BEFORE, `cut ${cut}`);
  }
});

/** Leaves file's own record as a reset cut off before its write, then puts its first entry back to its value before that profile by hand. */
function cutOffOwnThenPutBack(records, file, restoredText) {
  const path = join(records, `${sha(file)}.json`);
  const rec = JSON.parse(readFileSync(path, "utf8"));
  assert.ok(Object.keys(rec.entries).length > 1, "an entry is left at the newer profile's value after the edit");
  writeFileSync(path, `${JSON.stringify({ ...rec, phase: "restoring", restoredHash: sha(restoredText), fromHash: sha("not the file") }, null, 2)}\n`);
  const [[name, { before }]] = Object.entries(rec.entries);
  const doc = JSON.parse(readFileSync(file, "utf8"));
  if (before === "absent") delete doc.enabledPlugins[name];
  else doc.enabledPlugins[name] = before;
  writeFileSync(file, `${JSON.stringify(doc, null, 2)}\n`);
  return readFileSync(file, "utf8");
}

test("#17354: a moved repository whose newer record the one yes cannot restore lists that file on its own, keeps the older record waiting behind it, and puts back each layer after a yes for it", () => {
  const w = world();
  const m = movedRepository(w, ["native"]);
  const edited = cutOffOwnThenPutBack(m.records, m.file, m.left[0]);
  const rows = resetJson(w).folders;
  assert.deepEqual(rows.map((f) => [f.file, f.action, f.movedTo ?? null, f.waitsFor ?? null]).sort(), [[m.file, "finish-cut-off", null, null], [m.old, "skip", null, m.file]].sort());
  assert.deepEqual(rows.find((f) => f.file === m.old).lines, [waitsRow(m.old, m.file)]);
  for (const args of [["--yes"], ["--yes", "--keep-cut-off", m.file]]) {
    const r = reset(w, args);
    assert.equal(r.status, 0, r.stdout + r.stderr);
    const own = args.length > 1 ? `Skipped ${m.file}: you answered no, so it is left as it is, and its record is kept.` : CUT_OFF_SKIP(m.file);
    assert.deepEqual(resultLines(r.stdout).sort(), [own, WAITS_SKIP(m.old)].sort(), args.join(" "));
    assert.ok(!r.stdout.includes(WAITS_LINE(1)), "nothing unblocked, so no line says to run again");
    assert.equal(readFileSync(m.file, "utf8"), edited);
    assert.equal(recordFiles(w).length, 2);
  }
  assert.deepEqual(resetLayers(w), [3, 0]);
  assert.equal(readFileSync(m.file, "utf8"), LOCAL_BEFORE);
});

test("#17354: a repository moved twice, with a profile applied at each place, is put back one layer per reset, newest first, and the last layer leaves the file as before the first apply", () => {
  const w = world();
  const m = movedTwice(w);
  const rows = resetJson(w).folders;
  assert.deepEqual(rows.map((f) => [f.file, f.action, f.movedTo ?? null, f.waitsFor ?? null]).sort(), [[m.file, "restore", null, null], [m.first, "skip", null, m.file], [m.second, "skip", null, m.file]].sort());
  const one = reset(w, ["--yes"]);
  assert.equal(one.status, 3, one.stdout + one.stderr);
  assert.deepEqual(resultLines(one.stdout).sort(), [`Restored ${m.file} (profile build).`, WAITS_DONE(m.first), WAITS_DONE(m.second)].sort());
  assert.equal(one.stdout.trim().split("\n").at(-1), WAITS_LINE(2));
  assert.equal(readFileSync(m.file, "utf8"), m.afterReview);
  const next = resetJson(w).folders;
  assert.deepEqual(next.map((f) => [f.file, f.movedTo ?? null, f.waitsFor ?? null]).sort(), [[m.first, null, m.file], [m.second, m.file, null]].sort(), "the record applied latest is offered, the earlier one waits");
  const two = reset(w, ["--yes", "--put-back-moved", m.file]);
  assert.equal(two.status, 3, two.stdout + two.stderr);
  assert.deepEqual(resultLines(two.stdout).sort(), [`Restored ${m.file} from the record of ${m.second} (profile review).`, WAITS_DONE(m.first)].sort());
  assert.equal(readFileSync(m.file, "utf8"), m.afterBuild);
  assert.deepEqual(resetLayers(w), [0]);
  assert.equal(readFileSync(m.file, "utf8"), LOCAL_BEFORE);

  const again = world();
  const n = movedTwice(again);
  assert.deepEqual(resetLayers(again), [3, 3, 0]);
  assert.equal(readFileSync(n.file, "utf8"), LOCAL_BEFORE);
});

test("#17354: a repository moved twice whose newest record is a cut-off file gets one question for that file, and a no to it keeps the file and every record", async () => {
  const w = world();
  const m = movedTwice(w, "native");
  const edited = cutOffOwnThenPutBack(m.records, m.file, m.afterReview);
  const preview = resetJson(w);
  assert.equal(preview.question, null);
  assert.deepEqual(preview.folders.filter((f) => f.ask).map((f) => f.ask.file), [m.file], "one question, about the cut-off file");
  const no = await resetAtTerminal(w, () => "n");
  assert.equal(no.status, 0, no.stdout + no.stderr);
  assert.equal(no.prompts.length, 1);
  assert.deepEqual(resultLines(no.stdout).sort(), [`Skipped ${m.file}: you answered no, so it is left as it is, and its record is kept.`, WAITS_SKIP(m.first), WAITS_SKIP(m.second)].sort());
  assert.equal(readFileSync(m.file, "utf8"), edited);
  assert.equal(recordFiles(w).length, 3);
  assert.deepEqual(resetLayers(w), [3, 3, 0]);
  assert.equal(readFileSync(m.file, "utf8"), LOCAL_BEFORE);
});

test("#17354: a moved record's reset cut off after its write is finished by the next reset", () => {
  const w = world();
  const m = movedRepository(w);
  rmSync(join(m.records, `${sha(m.file)}.json`));
  writeFileSync(m.file, LOCAL_BEFORE);
  assert.deepEqual(resetLayers(w), [0]);
  assert.equal(readFileSync(m.file, "utf8"), LOCAL_BEFORE);
});

test("#17354: a moved repository with a profile applied at its new place, answered no at each layer, keeps its file and every record", async () => {
  const w = world();
  const m = movedRepository(w);
  const applied = readFileSync(m.file, "utf8");
  const no = await resetAtTerminal(w, () => "n");
  assert.equal(no.status, 1, no.stdout);
  assert.equal(readFileSync(m.file, "utf8"), applied);
  assert.equal(recordFiles(w).length, 2);
  assert.equal(reset(w, ["--yes"]).status, 3);
  const r = reset(w, ["--yes", "--keep-moved", m.file]);
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.deepEqual(resultLines(r.stdout), [`Skipped ${m.file}: you answered no, so it is left as it is, and the record of ${m.old} (profile build) is kept.`]);
  assert.equal(readFileSync(m.file, "utf8"), m.left[0]);
  assert.deepEqual(recordFiles(w), [m.old]);
});

test("#17354: a write given the preview's id refuses, writing nothing, once what reset would write differs from that preview", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const shown = resetJson(w).previewId;
  assert.match(shown, /^[0-9a-f]{64}$/);
  assert.equal(resetJson(w).previewId, shown, "the same machine gives the same id");
  const p2 = secondFolder(w);
  const applied = [w.read(), readFileSync(p2.file, "utf8")];
  const r = reset(w, ["--yes", "--preview-id", shown]);
  assert.equal(r.status, 1, r.stdout);
  assert.match(r.stderr, /^not reset: what reset would write changed since that preview .*nothing was written\. Look at the new preview: reset --dry-run$/m);
  assert.deepEqual([w.read(), readFileSync(p2.file, "utf8")], applied);
  const beforeEdit = resetJson(w).previewId;
  const edited = JSON.parse(w.read());
  edited.permissions.allow.push("Bash(edited)");
  writeFileSync(w.localFile, `${JSON.stringify(edited, null, 2)}\n`);
  const next = resetJson(w).previewId;
  assert.notEqual(next, beforeEdit, "a hand edit of a listed file changes the id");
  const ok = reset(w, ["--yes", "--preview-id", next]);
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(readFileSync(p2.file, "utf8"), LOCAL_BEFORE);
});

test("#17354: a file the preview does not ask about is refused, naming the files it does ask about", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const old = rootLocal(w.project);
  const moved = join(w.root, "moved");
  renameSync(w.project, moved);
  knowFolders(w, moved);
  const r = reset(w, ["--yes", "--put-back-moved", old]);
  assert.equal(r.status, 1);
  assert.match(r.stderr, new RegExp(`^not reset: ${esc(old)} is not a file the preview asks about; it asks about ${esc(rootLocal(moved))} \\(each row's ask\\.file in reset --dry-run --json\\); nothing was written$`, "m"));
});

/** A record as apply writes it, naming settingsFile: songwriting switched on, so restoring it would switch songwriting off. */
const handRecord = (settingsFile, target = "folder") => ({
  schema: 1, profile: "songs", target, settingsFile, appliedAt: "2026-01-01T00:00:00.000Z", pluginVersion: "0.1.0",
  phase: "applied", pending: {}, createdFile: false, containers: { enabledPlugins: true, skillOverrides: false }, installed: [],
  entries: { [`songwriting@${M}`]: { before: false, after: true } }, skillOverrides: {},
});

test("#17354: a git-home record of a deleted subfolder or linked worktree is kept and never offered for the repository's root file", () => {
  const w = world();
  gitInit(w);
  const t = linkedWorktree(w, LOCAL_BEFORE);
  const sub = join(w.project, "sub", ".claude", "settings.local.json");
  writeTree(join(w.project, ".git", "plugin-profiles", "records"), { "sub.json": handRecord(sub), "wt.json": handRecord(t.file) });
  rmSync(t.wt, { recursive: true });
  const r = w.run(["reset", "--dry-run", "--json"]);
  assert.equal(r.status, 0, r.stderr);
  const rows = JSON.parse(r.stdout).folders.filter((f) => [sub, t.file].includes(f.file));
  assert.deepEqual(rows.map((f) => [f.file, f.action, f.movedTo ?? null, f.ask ?? null]).sort(), [[sub, "skip", null, null], [t.file, "skip", null, null]].sort());
  for (const f of rows) assert.ok(f.lines[0].endsWith("folder not found; record kept."), f.lines[0]);
});

test("#17354: a record kept in a folder that cannot hold it is listed as ignored and never written from", () => {
  const w = world();
  gitInit(w);
  const userFile = join(w.home, ".claude", "settings.json");
  const userBefore = readFileSync(userFile, "utf8");
  const p2 = join(w.root, "project2");
  writeTree(p2, { ".claude/settings.local.json": LOCAL_BEFORE });
  const p2File = join(p2, ".claude", "settings.local.json");
  const planted = join(w.project, ".git", "plugin-profiles", "records");
  writeTree(planted, { "user.json": handRecord(userFile, "initial"), "other.json": handRecord(p2File) });
  const stateRecords = join(w.home, ".claude", "plugin-profiles-state", "records");
  writeTree(stateRecords, { "folder.json": handRecord(p2File) });
  const dry = w.run(["reset", "--dry-run", "--json"]);
  assert.equal(dry.status, 0, dry.stderr);
  const ignored = JSON.parse(dry.stdout).folders.filter((f) => f.reason === "ignored");
  const paths = [join(planted, "user.json"), join(planted, "other.json"), join(stateRecords, "folder.json")];
  assert.deepEqual(ignored.map((f) => f.record).sort(), paths.sort());
  for (const f of ignored) assert.match(f.lines[0], new RegExp(`^Ignored the record ${esc(f.record)}: `));
  const r = w.run(["reset", "--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(readFileSync(userFile, "utf8"), userBefore);
  assert.equal(readFileSync(p2File, "utf8"), LOCAL_BEFORE);
  for (const path of paths) assert.ok(existsSync(path), path);
});

/** Where reset notes a file of a folder outside git that it restored: the data folder's restored/, keyed as records are. */
const noteOf = (w, file, home = join(w.home, ".claude", "plugins", "data", "plugin-profiles-inline")) => join(home, "restored", `${sha(realpathSync(file))}.json`);
/** The preview line counting the files reset left unchanged since, naming the first three and how many more. */
const UNCHANGED_LINE = (files) =>
  `${files.length} ${files.length === 1 ? "file that reset already handled is" : "files that reset already handled are"} unchanged since; reset leaves ${files.length === 1 ? "it" : "them"}: ${files.length > 3 ? `${files.slice(0, 3).join(", ")} and ${files.length - 3} more` : files.join(", ")}.`;

test("#17354: the preview line counting files unchanged since reset names the first three and how many more", () => {
  const w = world();
  const dirs = ["p1", "p2", "p3", "p4"].map((name) => {
    const dir = join(w.root, name);
    writeTree(dir, { ".claude/settings.local.json": LOCAL_BEFORE });
    assert.equal(runIn(w, dir, ["apply", "build", "--for", "folder", "--yes"]).status, 0);
    return dir;
  });
  knowFolders(w, ...dirs);
  assert.equal(reset(w, ["--yes"]).status, 0);
  const preview = resetJson(w);
  assert.equal(preview.unchangedSinceReset.length, 4);
  assert.ok(preview.lines.includes(UNCHANGED_LINE(preview.unchangedSinceReset)), preview.lines.join("\n"));
  assert.match(preview.lines.at(-1), / and 1 more\.$/);
});

test("#17354: a cut-off file reset finished with a yes while keeping a hand edit is counted among files reset already handled, in words true for it", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  cutOff(w, w.localFile, { written: false });
  const doc = JSON.parse(w.read());
  doc.enabledPlugins[`implementation@${M}`] = false;
  writeFileSync(w.localFile, `${JSON.stringify(doc, null, 2)}\n`);
  const r = reset(w, ["--yes", "--finish-cut-off", w.localFile]);
  assert.equal(r.status, 0, r.stderr);
  assert.notEqual(w.read(), LOCAL_BEFORE, "the hand edit stays, so the file is not back at its original");
  knowFolders(w, w.project);
  const preview = resetJson(w);
  assert.deepEqual(preview.unchangedSinceReset, [w.localFile]);
  assert.ok(preview.lines.includes(UNCHANGED_LINE([w.localFile])), preview.lines.join("\n"));
  assert.ok(!preview.lines.some((l) => l.includes("restored earlier")), "the file was handled, not restored to its original");
});

test("#17354: after a reset, the files it restored that hold hand-written entries are not listed again and no question is asked", () => {
  const w = world();
  const p2 = secondFolder(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  knowFolders(w, w.project, p2.dir);
  assert.equal(reset(w, ["--yes"]).status, 0);
  assert.equal(w.read(), LOCAL_BEFORE);
  const preview = resetJson(w);
  assert.deepEqual(preview.folders, []);
  assert.equal(preview.question, null);
  assert.deepEqual([...preview.unchangedSinceReset].sort(), [w.localFile, p2.file].sort());
  assert.ok(preview.lines.includes(UNCHANGED_LINE(preview.unchangedSinceReset)), preview.lines.join("\n"));
  assert.doesNotMatch(preview.lines.join("\n"), /may be your own/);
  const again = reset(w);
  assert.equal(again.status, 0, again.stderr);
  assert.deepEqual(resultLines(again.stdout), []);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.equal(readFileSync(p2.file, "utf8"), LOCAL_BEFORE);
});

test("#17354: reset notes a file it restores by every path: a finished earlier reset, a worktree copy adopted from the root's record and a moved repository's file", () => {
  const cut = world();
  assert.equal(cut.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  knowFolders(cut, cut.project);
  cutOff(cut, cut.localFile, { written: true });
  assert.equal(reset(cut, ["--yes"]).status, 0);
  assert.deepEqual(resetJson(cut).folders, [], "a finished earlier reset");

  const wt = world();
  gitInit(wt);
  assert.equal(wt.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const t = linkedWorktree(wt, JSON.parse(wt.read()));
  knowFolders(wt, t.wt);
  assert.equal(reset(wt, ["--yes"]).status, 0);
  assert.deepEqual(resetJson(wt).unchangedSinceReset.sort(), [rootLocal(wt.project), t.file].sort(), "the adopted copy and the root file");

  const mv = world();
  gitInit(mv);
  assert.equal(mv.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const moved = join(mv.root, "moved");
  renameSync(mv.project, moved);
  knowFolders(mv, moved);
  assert.equal(reset(mv, ["--yes", "--put-back-moved", rootLocal(moved)]).status, 0);
  assert.equal(readFileSync(rootLocal(moved), "utf8"), LOCAL_BEFORE);
  assert.deepEqual(resetJson(mv).folders, [], "a moved repository's file");
});

test("#17354: a file reset restored and then edited by hand is listed again as having no record, and the next reset removes the stale note", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  knowFolders(w, w.project);
  assert.equal(reset(w, ["--yes"]).status, 0);
  assert.deepEqual(resetJson(w).folders, []);
  const edited = JSON.parse(w.read());
  edited.enabledPlugins["widget@vendor"] = true;
  writeFileSync(w.localFile, `${JSON.stringify(edited, null, 2)}\n`);
  const preview = resetJson(w);
  assert.deepEqual(preview.folders.map((f) => [f.file, f.action, f.ask?.file]), [[w.localFile, "remove-entries", w.localFile]]);
  assert.match(preview.folders[0].lines[0], /may be your own/);
  assert.deepEqual(preview.unchangedSinceReset, []);
  assert.ok(existsSync(noteOf(w, w.localFile)), "a preview writes nothing");
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [NO_RECORD_SKIP(w.localFile)]);
  assert.equal(existsSync(noteOf(w, w.localFile)), false, "the next reset that writes removes the stale note");
});

test("#17354: an apply to a file reset restored removes its note, a record always wins over a note, and the next reset restores the file as usual", () => {
  const w = world();
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  knowFolders(w, w.project);
  assert.equal(reset(w, ["--yes"]).status, 0);
  const note = JSON.parse(readFileSync(noteOf(w, w.localFile), "utf8"));
  assert.deepEqual(note, { schema: 1, settingsFile: w.localFile, restoredHash: sha(LOCAL_BEFORE) });
  assert.equal(w.run(["apply", "review", "--for", "folder", "--yes"]).status, 0);
  assert.equal(existsSync(noteOf(w, w.localFile)), false, "an apply removes the note");
  writeTree(dirname(noteOf(w, w.localFile)), { [basename(noteOf(w, w.localFile))]: { ...note, restoredHash: sha(w.read()) } });
  assert.deepEqual(resetJson(w).folders.map((f) => [f.file, f.action]), [[w.localFile, "restore"]], "a note matching a recorded file's bytes never hides it");
  const r = reset(w, ["--yes"]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [`Restored ${w.localFile} (profile review).`]);
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.equal(JSON.parse(readFileSync(noteOf(w, w.localFile), "utf8")).restoredHash, sha(LOCAL_BEFORE));
});

test("#17354: a restored note in a home that cannot hold its file is ignored", () => {
  const w = world();
  gitInit(w);
  const p2 = secondRepository(w);
  knowFolders(w, w.project, p2);
  const file = rootLocal(w.project);
  const note = { schema: 1, settingsFile: file, restoredHash: sha(LOCAL_BEFORE) };
  const name = basename(noteOf(w, file));
  for (const home of [join(p2, ".git", "plugin-profiles"), join(w.home, ".claude", "plugin-profiles-state")]) writeTree(join(home, "restored"), { [name]: note });
  const own = (preview) => preview.folders.filter((f) => f.file === file).map((f) => f.action);
  assert.deepEqual(own(resetJson(w)), ["remove-entries"], "notes in another repository's home and the user-settings home are ignored");
  writeTree(join(w.project, ".git", "plugin-profiles", "restored"), { [name]: note });
  assert.deepEqual(own(resetJson(w)), [], "the same note in the repository's own home is read");
});

test("#17354: a folder with entries and no record that reset never restored is still listed and needs its own yes, beside one it restored", () => {
  const w = world();
  const p2 = secondFolder(w);
  knowFolders(w, w.project, p2.dir);
  assert.equal(reset(w, ["--yes"]).status, 0);
  assert.equal(readFileSync(p2.file, "utf8"), LOCAL_BEFORE);
  const preview = resetJson(w);
  assert.deepEqual(preview.folders.map((f) => [f.file, f.action, f.ask?.file]), [[w.localFile, "remove-entries", w.localFile]]);
  assert.deepEqual(preview.unchangedSinceReset, [p2.file]);
  const plain = reset(w, ["--yes"]);
  assert.deepEqual(resultLines(plain.stdout), [NO_RECORD_SKIP(w.localFile)]);
  assert.equal(w.read(), LOCAL_BEFORE);
  const r = reset(w, ["--yes", "--remove-unrecorded", w.localFile]);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(resultLines(r.stdout), [`Removed the 2 plugin and skill entries of ${w.localFile}, which had no record.`]);
});

test("#17354: with nobody to answer and no --yes, a folder without a record makes reset write nothing and exit 1, saying so", () => {
  const w = world();
  knowFolders(w, w.project);
  const r = reset(w);
  assert.equal(r.status, 1, r.stdout);
  assert.match(r.stderr, /^not reset: nobody to confirm, so nothing was written; a folder without a record changes only after a yes for it: run reset in a terminal, or pass --yes with --remove-unrecorded <file> for each folder to change$/m);
  assert.deepEqual(resultLines(r.stdout), []);
  assert.equal(w.read(), LOCAL_BEFORE);
  const kept = reset(w, ["--keep-unrecorded", w.localFile]);
  assert.equal(kept.status, 0, "a folder already answered no leaves nothing to confirm");
  assert.deepEqual(resultLines(kept.stdout), [`Skipped ${w.localFile}: you answered no, so it is left as it is.`]);
});

test("#17354: the one question counts a worktree copy adopted from the root's record in words true for it", () => {
  const w = world();
  gitInit(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const t = linkedWorktree(w, JSON.parse(w.read()));
  knowFolders(w, t.wt);
  const preview = resetJson(w);
  assert.deepEqual(preview.folders.map((f) => [f.recorded, f.adopted]).sort(), [[false, true], [true, false]]);
  assert.equal(preview.question, "Reset the 2 files above that a profile record covers?");
});

/**
 * Each reset row kind on one machine: its files by key, named states a cell's content refers to, the file its own question
 * is about (or the main file, whose own flag reset refuses), and the files a result line has to name.
 */
const KINDS = {
  restore: () => {
    const w = world();
    assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
    return { w, files: { F: w.localFile }, own: w.localFile };
  },
  removeFile: () => {
    const w = world({ local: null });
    assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
    return { w, files: { F: w.localFile }, own: w.localFile };
  },
  finishRestore: () => {
    const w = world();
    assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
    cutOff(w, w.localFile, { written: true });
    return { w, files: { F: w.localFile }, own: w.localFile };
  },
  adopted: () => {
    const w = world();
    gitInit(w);
    assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
    const t = linkedWorktree(w, JSON.parse(w.read()));
    knowFolders(w, t.wt);
    return { w, files: { R: rootLocal(w.project), W: t.file }, own: t.file };
  },
  noRecord: () => {
    const w = world();
    knowFolders(w, w.project);
    return { w, files: { F: w.localFile }, own: w.localFile, flags: ASK_FLAGS.unrecorded };
  },
  missing: () => {
    const w = world();
    const gone = join(w.root, "gone", ".claude", "settings.local.json");
    writeTree(dataRecordsDir(w), { "gone.json": handRecord(gone) });
    return { w, files: { G: gone }, own: gone };
  },
  movedNoNewer: () => {
    const w = world();
    gitInit(w);
    assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
    const old = rootLocal(w.project);
    const now = join(w.root, "repo-now");
    renameSync(w.project, now);
    knowFolders(w, now);
    return { w, files: { O: old, M: rootLocal(now) }, own: rootLocal(now), flags: ASK_FLAGS.moved };
  },
  movedNewer: () => {
    const w = world();
    gitInit(w);
    assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
    const old = rootLocal(w.project);
    const now = join(w.root, "repo-now");
    renameSync(w.project, now);
    knowFolders(w, now);
    const left = readFileSync(rootLocal(now), "utf8");
    assert.equal(runIn(w, now, ["apply", "review", "--for", "folder", "--yes"]).status, 0);
    return { w, files: { O: old, M: rootLocal(now) }, left: { M: left }, own: rootLocal(now), flags: ASK_FLAGS.moved };
  },
  movedTwice: () => {
    const w = world();
    gitInit(w);
    assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
    const first = rootLocal(w.project);
    const between = join(w.root, "repo-between");
    renameSync(w.project, between);
    assert.equal(runIn(w, between, ["apply", "review", "--for", "folder", "--yes"]).status, 0);
    const second = rootLocal(between);
    const now = join(w.root, "repo-now");
    renameSync(between, now);
    knowFolders(w, now);
    const left = readFileSync(rootLocal(now), "utf8");
    assert.equal(runIn(w, now, ["apply", "build", "--for", "folder", "--yes"]).status, 0);
    return { w, files: { O: first, S: second, M: rootLocal(now) }, left: { M: left }, own: rootLocal(now), flags: ASK_FLAGS.moved };
  },
  cutOffChanged: () => {
    const w = world();
    cutOffThenPutBack(w);
    const n = Object.keys(JSON.parse(readFileSync(dataRecordOf(w, w.localFile), "utf8")).entries).length - 1;
    return { w, files: { F: w.localFile }, vars: { N: String(n) }, own: w.localFile, flags: ASK_FLAGS.cutOff };
  },
  ignored: () => {
    const w = world();
    const folder = join(w.root, "project2");
    writeTree(folder, { ".claude/settings.local.json": LOCAL_BEFORE });
    const file = join(folder, ".claude", "settings.local.json");
    const planted = join(w.home, ".claude", "plugin-profiles-state", "records", "folder.json");
    writeTree(dirname(planted), { "folder.json": handRecord(file) });
    return { w, files: { U: file }, vars: { P: planted }, own: file };
  },
  unchanged: () => {
    const w = world();
    assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
    knowFolders(w, w.project);
    assert.equal(reset(w, ["--yes"]).status, 0);
    return { w, files: {}, unnamed: { F: w.localFile }, own: w.localFile };
  },
};
const ASK_FLAGS = { unrecorded: ["--remove-unrecorded", "--keep-unrecorded"], cutOff: ["--finish-cut-off", "--keep-cut-off"], moved: ["--put-back-moved", "--keep-moved"] };

/** How a cell answers: at a terminal (y or n to the one question, then to each file's own), by flags, or with nobody there. */
const MODES = {
  "t:yy": { terminal: ["y", "y"] },
  "t:yn": { terminal: ["y", "n"] },
  "t:ny": { terminal: ["n", "y"] },
  "t:nn": { terminal: ["n", "n"] },
  "--yes": { args: () => ["--yes"] },
  "--yes own-yes": { args: (k) => ["--yes", (k.flags ?? ASK_FLAGS.unrecorded)[0], k.own] },
  "--yes own-no": { args: (k) => ["--yes", (k.flags ?? ASK_FLAGS.unrecorded)[1], k.own] },
  nobody: { args: () => [] },
};

/** Every file of a test machine that is an applied-profile record. */
const allRecords = (w) => readdirSync(w.root, { recursive: true }).filter((rel) => /(^|[\\/])records[\\/][^\\/]+\.json$/.test(rel));
const CELL_RESULT = /^(Restored|Removed|Skipped|Finished|Already restored|Ignored) /;
const fill = (text, vars) => text.replace(/\{(\w+)\}/g, (_, key) => vars[key]);
const RESTORED = "Restored {F} (profile build).";
const NOTHING = [];
const ANSWERED_NO = "Skipped {F}: you answered no, so it is left as it is, and its record is kept.";
const WAITS = WAITS_DONE("{O}");

/**
 * One row per cell: row kind, way of answering, each file's content after the run (same: as before the run; before: as before
 * any profile; gone; noEntries: no plugin or skill entries left; left: what the older profiles left), records left on the
 * machine, the result lines, and the exit status. A cell with exit 1 wrote nothing and prints no result line.
 */
const CELLS = [
  ["restore", "t:yy", "F=before", 0, [RESTORED], 0],
  ["restore", "t:yn", "F=before", 0, [RESTORED], 0],
  ["restore", "t:ny", "F=same", 1, NOTHING, 1],
  ["restore", "t:nn", "F=same", 1, NOTHING, 1],
  ["restore", "--yes", "F=before", 0, [RESTORED], 0],
  ["restore", "--yes own-yes", "F=same", 1, NOTHING, 1],
  ["restore", "--yes own-no", "F=same", 1, NOTHING, 1],
  ["restore", "nobody", "F=same", 1, NOTHING, 1],
  ["removeFile", "t:yy", "F=gone", 0, ["Removed {F}, which the first apply created (profile build)."], 0],
  ["removeFile", "t:yn", "F=gone", 0, ["Removed {F}, which the first apply created (profile build)."], 0],
  ["removeFile", "t:ny", "F=same", 1, NOTHING, 1],
  ["removeFile", "t:nn", "F=same", 1, NOTHING, 1],
  ["removeFile", "--yes", "F=gone", 0, ["Removed {F}, which the first apply created (profile build)."], 0],
  ["removeFile", "--yes own-yes", "F=same", 1, NOTHING, 1],
  ["removeFile", "--yes own-no", "F=same", 1, NOTHING, 1],
  ["removeFile", "nobody", "F=same", 1, NOTHING, 1],
  ["finishRestore", "t:yy", "F=before", 0, ["Finished an earlier reset of {F}: its record is removed."], 0],
  ["finishRestore", "t:yn", "F=before", 0, ["Finished an earlier reset of {F}: its record is removed."], 0],
  ["finishRestore", "t:ny", "F=before", 1, NOTHING, 1],
  ["finishRestore", "t:nn", "F=before", 1, NOTHING, 1],
  ["finishRestore", "--yes", "F=before", 0, ["Finished an earlier reset of {F}: its record is removed."], 0],
  ["finishRestore", "--yes own-yes", "F=before", 1, NOTHING, 1],
  ["finishRestore", "--yes own-no", "F=before", 1, NOTHING, 1],
  ["finishRestore", "nobody", "F=before", 1, NOTHING, 1],
  ["adopted", "t:yy", "R=before W=before", 0, ["Restored {W} (profile build).", "Restored {R} (profile build)."], 0],
  ["adopted", "t:yn", "R=before W=before", 0, ["Restored {W} (profile build).", "Restored {R} (profile build)."], 0],
  ["adopted", "t:ny", "R=same W=same", 1, NOTHING, 1],
  ["adopted", "t:nn", "R=same W=same", 1, NOTHING, 1],
  ["adopted", "--yes", "R=before W=before", 0, ["Restored {W} (profile build).", "Restored {R} (profile build)."], 0],
  ["adopted", "--yes own-yes", "R=same W=same", 1, NOTHING, 1],
  ["adopted", "--yes own-no", "R=same W=same", 1, NOTHING, 1],
  ["adopted", "nobody", "R=same W=same", 1, NOTHING, 1],
  ["noRecord", "t:yy", "F=noEntries", 0, ["Removed the 2 plugin and skill entries of {F}, which had no record."], 0],
  ["noRecord", "t:yn", "F=same", 0, ["Skipped {F}: you answered no, so it is left as it is."], 0],
  ["noRecord", "t:ny", "F=noEntries", 0, ["Removed the 2 plugin and skill entries of {F}, which had no record."], 0],
  ["noRecord", "t:nn", "F=same", 0, ["Skipped {F}: you answered no, so it is left as it is."], 0],
  ["noRecord", "--yes", "F=same", 0, ["Skipped {F}: no record; reset removes its entries only after a yes for this folder."], 0],
  ["noRecord", "--yes own-yes", "F=noEntries", 0, ["Removed the 2 plugin and skill entries of {F}, which had no record."], 0],
  ["noRecord", "--yes own-no", "F=same", 0, ["Skipped {F}: you answered no, so it is left as it is."], 0],
  ["noRecord", "nobody", "F=same", 0, NOTHING, 1],
  ["missing", "t:yy", "G=gone", 1, ["Skipped {G}: folder not found; record kept."], 0],
  ["missing", "t:yn", "G=gone", 1, ["Skipped {G}: folder not found; record kept."], 0],
  ["missing", "t:ny", "G=gone", 1, ["Skipped {G}: folder not found; record kept."], 0],
  ["missing", "t:nn", "G=gone", 1, ["Skipped {G}: folder not found; record kept."], 0],
  ["missing", "--yes", "G=gone", 1, ["Skipped {G}: folder not found; record kept."], 0],
  ["missing", "--yes own-yes", "G=gone", 1, NOTHING, 1],
  ["missing", "--yes own-no", "G=gone", 1, NOTHING, 1],
  ["missing", "nobody", "G=gone", 1, ["Skipped {G}: folder not found; record kept."], 0],
  ["movedNoNewer", "t:yy", "M=before", 0, ["Restored {M} from the record of {O} (profile build)."], 0],
  ["movedNoNewer", "t:yn", "M=same", 1, ["Skipped {M}: you answered no, so it is left as it is, and the record of {O} (profile build) is kept."], 0],
  ["movedNoNewer", "t:ny", "M=before", 0, ["Restored {M} from the record of {O} (profile build)."], 0],
  ["movedNoNewer", "t:nn", "M=same", 1, ["Skipped {M}: you answered no, so it is left as it is, and the record of {O} (profile build) is kept."], 0],
  ["movedNoNewer", "--yes", "M=same", 1, ["Skipped {O}: folder not found; record kept."], 0, "M"],
  ["movedNoNewer", "--yes own-yes", "M=before", 0, ["Restored {M} from the record of {O} (profile build)."], 0],
  ["movedNoNewer", "--yes own-no", "M=same", 1, ["Skipped {M}: you answered no, so it is left as it is, and the record of {O} (profile build) is kept."], 0],
  ["movedNoNewer", "nobody", "M=same", 1, NOTHING, 1],
  ["movedNewer", "t:yy", "M=left", 1, ["Restored {M} (profile review).", WAITS], 3],
  ["movedNewer", "t:yn", "M=left", 1, ["Restored {M} (profile review).", WAITS], 3],
  ["movedNewer", "t:ny", "M=same", 2, NOTHING, 1],
  ["movedNewer", "t:nn", "M=same", 2, NOTHING, 1],
  ["movedNewer", "--yes", "M=left", 1, ["Restored {M} (profile review).", WAITS], 3],
  ["movedNewer", "--yes own-yes", "M=same", 2, NOTHING, 1],
  ["movedNewer", "--yes own-no", "M=same", 2, NOTHING, 1],
  ["movedNewer", "nobody", "M=same", 2, NOTHING, 1],
  ["movedTwice", "t:yy", "M=left", 2, ["Restored {M} (profile build).", WAITS, WAITS.replace("{O}", "{S}")], 3],
  ["movedTwice", "t:yn", "M=left", 2, ["Restored {M} (profile build).", WAITS, WAITS.replace("{O}", "{S}")], 3],
  ["movedTwice", "t:ny", "M=same", 3, NOTHING, 1],
  ["movedTwice", "t:nn", "M=same", 3, NOTHING, 1],
  ["movedTwice", "--yes", "M=left", 2, ["Restored {M} (profile build).", WAITS, WAITS.replace("{O}", "{S}")], 3],
  ["movedTwice", "--yes own-yes", "M=same", 3, NOTHING, 1],
  ["movedTwice", "--yes own-no", "M=same", 3, NOTHING, 1],
  ["movedTwice", "nobody", "M=same", 3, NOTHING, 1],
  ["cutOffChanged", "t:yy", "F=before", 0, ["Restored {F}: put back the {N} entries still at the values profile build wrote, and left the entries changed by hand since as they are."], 0],
  ["cutOffChanged", "t:yn", "F=same", 1, [ANSWERED_NO], 0],
  ["cutOffChanged", "t:ny", "F=before", 0, ["Restored {F}: put back the {N} entries still at the values profile build wrote, and left the entries changed by hand since as they are."], 0],
  ["cutOffChanged", "t:nn", "F=same", 1, [ANSWERED_NO], 0],
  ["cutOffChanged", "--yes", "F=same", 1, ["Skipped {F}: an earlier reset of it was cut off and it changed since; reset puts back its entries still at the profile's values only after a yes for this file, so the file and its record are kept."], 0],
  ["cutOffChanged", "--yes own-yes", "F=before", 0, ["Restored {F}: put back the {N} entries still at the values profile build wrote, and left the entries changed by hand since as they are."], 0],
  ["cutOffChanged", "--yes own-no", "F=same", 1, [ANSWERED_NO], 0],
  ["cutOffChanged", "nobody", "F=same", 1, NOTHING, 1],
  ["ignored", "t:yy", "U=same", 1, ["Ignored the record {P}: {U} is not written from it."], 0],
  ["ignored", "t:yn", "U=same", 1, ["Ignored the record {P}: {U} is not written from it."], 0],
  ["ignored", "t:ny", "U=same", 1, ["Ignored the record {P}: {U} is not written from it."], 0],
  ["ignored", "t:nn", "U=same", 1, ["Ignored the record {P}: {U} is not written from it."], 0],
  ["ignored", "--yes", "U=same", 1, ["Ignored the record {P}: {U} is not written from it."], 0],
  ["ignored", "--yes own-yes", "U=same", 1, NOTHING, 1],
  ["ignored", "--yes own-no", "U=same", 1, NOTHING, 1],
  ["ignored", "nobody", "U=same", 1, ["Ignored the record {P}: {U} is not written from it."], 0],
  ["unchanged", "t:yy", "", 0, NOTHING, 0],
  ["unchanged", "t:yn", "", 0, NOTHING, 0],
  ["unchanged", "t:ny", "", 0, NOTHING, 0],
  ["unchanged", "t:nn", "", 0, NOTHING, 0],
  ["unchanged", "--yes", "", 0, NOTHING, 0],
  ["unchanged", "--yes own-yes", "", 0, NOTHING, 1],
  ["unchanged", "--yes own-no", "", 0, NOTHING, 1],
  ["unchanged", "nobody", "", 0, NOTHING, 0],
];

test("#17354: every reset row kind crossed with every way of answering writes, keeps records, names each file once and exits as the table says", async () => {
  assert.deepEqual([...new Set(CELLS.map(([kind]) => kind))], Object.keys(KINDS), "every kind has its cells");
  for (const kind of Object.keys(KINDS)) assert.deepEqual(CELLS.filter(([k]) => k === kind).map(([, mode]) => mode), Object.keys(MODES), `${kind} has one cell per way of answering`);
  for (const [kind, mode, content, records, lines, exit, unnamed] of CELLS) {
    const cell = `${kind} x ${mode}`;
    const k = KINDS[kind]();
    const same = Object.fromEntries(Object.entries({ ...k.files, ...k.unnamed }).map(([key, file]) => [key, existsSync(file) ? readFileSync(file, "utf8") : null]));
    const shown = new Set(resetJson(k.w).lines);
    const how = MODES[mode];
    const r = how.terminal
      ? await resetAtTerminal(k.w, (prompt) => (FIRST.test(prompt) ? how.terminal[0] : how.terminal[1]))
      : reset(k.w, how.args(k));
    const vars = { ...k.files, ...k.vars };
    assert.equal(r.status, exit, `${cell}: ${r.stdout}\n${r.stderr}`);
    const got = r.stdout.split("\n").filter((line) => CELL_RESULT.test(line) && !shown.has(line));
    assert.deepEqual(got.sort(), lines.map((line) => fill(line, vars)).sort(), cell);
    if (exit !== 1) {
      for (const [key, file] of Object.entries(k.files)) {
        if (key === unnamed) continue;
        assert.equal(got.filter((line) => line.includes(file)).length, 1, `${cell}: one result line names ${file}`);
      }
    }
    for (const spec of content.split(" ").filter(Boolean)) {
      const [key, state] = spec.split("=");
      const file = k.files[key];
      const now = existsSync(file) ? readFileSync(file, "utf8") : null;
      const want = { same: same[key], before: LOCAL_BEFORE, gone: null, left: k.left?.[key] }[state];
      if (state === "noEntries") assert.deepEqual(JSON.parse(now), withoutProfileKeys(LOCAL_BEFORE), `${cell}: ${key}`);
      else assert.equal(now, want, `${cell}: ${key} ${state}`);
    }
    for (const [key, file] of Object.entries(k.unnamed ?? {})) assert.equal(readFileSync(file, "utf8"), same[key], `${cell}: ${key} same`);
    assert.equal(allRecords(k.w).length, records, `${cell}: records ${allRecords(k.w).join(", ")}`);
  }
});

test("#17354: at a terminal, an empty answer or any answer but y or yes writes nothing, for every kind of question reset asks", async () => {
  for (const kind of ["restore", "noRecord", "cutOffChanged", "movedNoNewer"]) {
    for (const typed of ["", "maybe", "n", "yess"]) {
      const k = KINDS[kind]();
      const files = Object.values(k.files);
      const before = files.map((file) => (existsSync(file) ? readFileSync(file, "utf8") : null));
      const records = allRecords(k.w).length;
      const r = await resetAtTerminal(k.w, () => typed);
      const cell = `${kind} answered ${JSON.stringify(typed)}`;
      assert.ok(r.prompts.length > 0, `${cell}: asked`);
      assert.deepEqual(files.map((file) => (existsSync(file) ? readFileSync(file, "utf8") : null)), before, cell);
      assert.equal(allRecords(k.w).length, records, cell);
      assert.ok(!resultLines(r.stdout).some((line) => /^(Restored|Removed|Finished) /.test(line)), `${cell}: ${r.stdout}`);
    }
  }
});

/** Sets one entry profile build wrote in file to a value neither the profile nor the file before it held. */
function editByHand(file) {
  const doc = JSON.parse(readFileSync(file, "utf8"));
  doc.enabledPlugins[`implementation@${M}`] = false;
  writeFileSync(file, `${JSON.stringify(doc, null, 2)}\n`);
}

test("#17354: the reset preview recommends one answer per question with a one-sentence reason from the row's facts, and keeps when those facts do not settle it", () => {
  const SAFE = (profile, at = "") => ({ answer: "yes", reason: `Each entry profile ${profile} wrote${at && `${at},`} is still at that value or back at its value from before, so a yes changes only what that profile wrote.` });
  const EDITED = (at = "") => ({ answer: "no", reason: `1 entry (implementation@${M}) changed by hand since profile build was applied${at}, so the file may hold changes you want; a no changes nothing.` });
  const movedAt = (k) => ` at ${k.files.O}, before the repository moved`;
  const recommendOf = (k) => resetJson(k.w).folders.find((f) => f.ask).ask.recommend;

  assert.deepEqual(recommendOf(KINDS.noRecord()), { answer: "no", reason: "Reset did not write these entries, so they may be your own." });
  const one = world();
  writeFileSync(one.localFile, `${JSON.stringify({ enabledPlugins: { [`p0@${M}`]: true } }, null, 2)}\n`);
  knowFolders(one, one.project);
  assert.deepEqual(recommendOf({ w: one }), { answer: "no", reason: "Reset did not write this entry, so it may be your own." });

  assert.deepEqual(recommendOf(KINDS.cutOffChanged()), SAFE("build"), "the entry changed since is back at its value from before, as a reset leaves it");
  const cut = world();
  assert.equal(cut.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  cutOff(cut, cut.localFile, { written: false });
  editByHand(cut.localFile);
  assert.deepEqual(recommendOf({ w: cut }), EDITED());

  const safe = KINDS.movedNoNewer();
  assert.deepEqual(recommendOf(safe), SAFE("build", movedAt(safe)));
  const moved = KINDS.movedNoNewer();
  editByHand(moved.files.M);
  assert.deepEqual(recommendOf(moved), EDITED(movedAt(moved)));

  const preview = resetJson(KINDS.restore().w);
  assert.deepEqual(preview.questionRecommend, {
    asked: { answer: "yes", reason: "You asked for a reset: a yes puts back the 1 file above as its lines say, and applying a profile again undoes it." },
    unasked: { answer: "no", reason: "Nobody asked for a reset, so a no keeps every profile as it is." },
  });
  assert.equal(resetJson(KINDS.noRecord().w).questionRecommend, null, "no question, no recommendation for it");
});
