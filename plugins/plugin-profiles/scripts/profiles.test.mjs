import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { delimiter, dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { parseProfile } from "../lib/profile-files.mjs";
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
  assert.equal(session.enabledPlugins[`songwriting@${M}`], false);
  assert.match(r.stdout, /A resumed session does not keep --settings/);
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
  assert.match(JSON.parse(sessionStart(w)).systemMessage, /Profile build \(folder\) applied/);
});

test("Q69: in cloud and Desktop WSL sessions the session-start notice prints nothing and writes nothing, even where a profile is applied", () => {
  const w = world();
  installOnDisk(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  assert.match(JSON.parse(sessionStart(w)).systemMessage, /Profile build \(folder\) applied/, "on the CLI the notice speaks");
  const before = snapshot(settingsFiles(w));
  const records = w.records();
  for (const env of [CLOUD, DESKTOP_WSL]) assert.equal(sessionStart(w, env), "", env.CLAUDE_CODE_ENTRYPOINT);
  assert.deepEqual(snapshot(settingsFiles(w)), before);
  assert.deepEqual(w.records(), records);
});

test("B8: the session-start notice names the folder's profile and the surface", () => {
  const w = world();
  installOnDisk(w);
  assert.equal(w.run(["apply", "build", "--for", "folder", "--yes"]).status, 0);
  const message = JSON.parse(sessionStart(w)).systemMessage;
  assert.match(message, /Profile build \(folder\)/);
  assert.match(message, /Surface: the Claude Code CLI/);
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
  assert.match(message, /This session runs in profile build from a one-session settings file/);
  assert.ok(message.includes(`--settings "${file}"`), message);
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
  assert.ok(preview.lines.includes(`Left on until the next apply (1): songwriting@${M}`), preview.lines.join("\n"));
  assert.ok(preview.lines.includes(`Switches on plugins with an MCP or language server: implementation@${M}`), preview.lines.join("\n"));
  assert.equal(w.read(), LOCAL_BEFORE);
  assert.deepEqual(w.records(), []);
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
