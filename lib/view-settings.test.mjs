// The medium resolver: each case is a rule of the medium-resolution contract (the argument decides
// alone; terminal or file from any scope keeps the view local; a publishing value counts only from
// an untracked, gitignored personal override or userConfig; the plugin default applies when no scope
// decides; a team file never publishes; an invalid value is ignored without dropping another scope;
// auto is unset; the retired rendered-views files give notices, and only a terminal or file value,
// which keeps the view local when no scope sets one).
import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "./test-tmp.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, "view-settings.mjs");
const { resolveMedium, gateExplicit } = await import("./view-settings.mjs");
const { reportLines } = await import("./view-registry.mjs");

const TEAM = "docs/conventions/rendered-views.yaml";
const PERSONAL = "docs/conventions/rendered-views.local.yaml";

/** A git repository holding `files` as {path: [text, tracked]}, with `ignore` in .gitignore. */
function repo(files = {}, ignore = []) {
  const dir = tempDir("view-settings-repo-");
  const git = (...args) => execFileSync("git", ["-C", dir, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  git("init", "-q", "-b", "main");
  if (ignore.length) writeFileSync(join(dir, ".gitignore"), `${ignore.join("\n")}\n`);
  for (const [path, [text, tracked]] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
    if (tracked) git("add", "-f", "--", path);
  }
  const commit = () => git("-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "x");
  return { dir, git, commit };
}
const userHome = (files = {}) => {
  const dir = tempDir("view-settings-home-");
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  return dir;
};
const EMPTY_HOME = userHome();
const resolve = (request, options = {}) => resolveMedium({ lane: "planning", ...request }, { userHome: EMPTY_HOME, dataDir: null, ...options });
const pick = ({ medium, decidedBy }) => ({ medium, decidedBy });

describe("the argument decides alone", () => {
  test("over a team file and userConfig", () => {
    const { dir } = repo({ [TEAM]: ["medium: file\n", true] });
    assert.deepEqual(pick(resolve({ argument: "artifact", userConfig: "terminal", projectRoot: dir })), { medium: "artifact", decidedBy: "argument" });
  });
});

describe("terminal or file from any scope keeps the view local", () => {
  test("team artifact + userConfig file gives file, which the publish gate never sees as explicit", () => {
    const { dir } = repo({ [TEAM]: ["medium: artifact\n", true] });
    const result = resolve({ userConfig: "file", projectRoot: dir });
    assert.deepEqual(pick(result), { medium: "file", decidedBy: "userConfig" });
    assert.equal(gateExplicit(result), false);
  });
  test("team file over userConfig hosted", () => {
    const { dir } = repo({ [TEAM]: ["medium: file\n", true] });
    assert.deepEqual(pick(resolve({ lane: "review:explain-change", userConfig: "hosted", projectRoot: dir })), { medium: "file", decidedBy: "team" });
  });
  test("precedence among local values: personal override, then team, then userConfig", () => {
    const { dir } = repo({ [TEAM]: ["medium: file\n", true], [PERSONAL]: ["medium: terminal\n", false] }, ["*.local.yaml"]);
    assert.deepEqual(pick(resolve({ userConfig: "file", projectRoot: dir })), { medium: "terminal", decidedBy: "personal override" });
    const teamOnly = repo({ [TEAM]: ["medium: file\n", true] });
    assert.deepEqual(pick(resolve({ userConfig: "terminal", projectRoot: teamOnly.dir })), { medium: "file", decidedBy: "team" });
  });
  test("a tracked personal override's local value still keeps the view local", () => {
    const { dir } = repo({ [PERSONAL]: ["medium: terminal\n", true] });
    assert.deepEqual(pick(resolve({ lane: "review:explain-change", userConfig: "artifact", projectRoot: dir })), { medium: "terminal", decidedBy: "personal override" });
  });
});

describe("an invalid value is ignored without dropping another scope's value", () => {
  test("team invalid + userConfig file gives file, with a notice naming the team file", () => {
    const { dir } = repo({ [TEAM]: ["medium: banner\n", true] });
    const result = resolve({ userConfig: "file", projectRoot: dir });
    assert.deepEqual(pick(result), { medium: "file", decidedBy: "userConfig" });
    assert.ok(result.notices.some((n) => n.kind === "invalid" && n.text.startsWith(`team ${TEAM}:`)), JSON.stringify(result.notices));
  });
  test("an invalid userConfig value leaves the team value standing", () => {
    const { dir } = repo({ [TEAM]: ["medium: terminal\n", true] });
    assert.deepEqual(pick(resolve({ userConfig: "banner", projectRoot: dir })), { medium: "terminal", decidedBy: "team" });
  });
});

describe("a publishing value counts only from a trusted scope", () => {
  test("team artifact alone never publishes: the lane's own default applies", () => {
    const { dir } = repo({ [TEAM]: ["medium: artifact\n", true] });
    const result = resolve({ projectRoot: dir });
    assert.deepEqual(pick(result), { medium: "artifact", decidedBy: "plugin default" });
    assert.equal(gateExplicit(result), false);
    assert.ok(result.notices.some((n) => n.kind === "ignored" && /a team file never publishes/.test(n.text)));
  });
  test("team hosted on the digest lane falls to the plugin default, which the content gate still checks", () => {
    const { dir } = repo({ [TEAM]: ["medium: hosted\n", true] });
    const result = resolve({ lane: "review:explain-change", projectRoot: dir });
    assert.deepEqual(pick(result), { medium: "artifact", decidedBy: "plugin default" });
    assert.equal(gateExplicit(result), false);
  });
  test("a tracked personal override artifact never publishes", () => {
    const { dir } = repo({ [PERSONAL]: ["medium: artifact\n", true] }, ["*.local.yaml"]);
    const result = resolve({ projectRoot: dir });
    assert.deepEqual(pick(result), { medium: "artifact", decidedBy: "plugin default" });
    assert.equal(gateExplicit(result), false);
    assert.ok(result.notices.some((n) => /tracked in git/.test(n.text)));
  });
  test("an untracked personal override that is not gitignored never publishes", () => {
    const { dir } = repo({ [PERSONAL]: ["medium: artifact\n", false] });
    const result = resolve({ projectRoot: dir });
    assert.deepEqual(pick(result), { medium: "artifact", decidedBy: "plugin default" });
    assert.equal(gateExplicit(result), false);
    assert.ok(result.notices.some((n) => /not gitignored/.test(n.text)));
  });
  test("an untracked, gitignored personal override publishes", () => {
    const { dir } = repo({ [PERSONAL]: ["medium: artifact\n", false] }, ["*.local.yaml"]);
    const result = resolve({ projectRoot: dir });
    assert.deepEqual(pick(result), { medium: "artifact", decidedBy: "personal override" });
    assert.equal(gateExplicit(result), true);
  });
  test("a personal override reached through a symlinked directory never publishes", { skip: process.platform === "win32" && "symlinks need a privilege on Windows" }, () => {
    const elsewhere = userHome({ "conventions/rendered-views.local.yaml": "medium: artifact\n" });
    const { dir } = repo({}, ["*.local.yaml", "docs/conventions"]);
    mkdirSync(join(dir, "docs"));
    execFileSync("ln", ["-s", join(elsewhere, "conventions"), join(dir, "docs/conventions")]);
    const result = resolve({ projectRoot: dir });
    assert.deepEqual(pick(result), { medium: "artifact", decidedBy: "plugin default" });
    assert.equal(gateExplicit(result), false);
  });
  test("the personal override wins over userConfig among publishing values", () => {
    const { dir } = repo({ [PERSONAL]: ["medium: hosted\n", false] }, ["*.local.yaml"]);
    assert.deepEqual(pick(resolve({ lane: "review:explain-change", userConfig: "artifact", projectRoot: dir })), { medium: "hosted", decidedBy: "personal override" });
  });
  test("plugin default artifact publishes when no scope decides", () => {
    const result = resolve({ lane: "review:explain-change" });
    assert.deepEqual(pick(result), { medium: "artifact", decidedBy: "plugin default" });
    assert.equal(gateExplicit(result), false);
  });
  test("review resolves hosted from userConfig", () => {
    const result = resolve({ lane: "review:explain-change", userConfig: "hosted" });
    assert.deepEqual(pick(result), { medium: "hosted", decidedBy: "userConfig" });
    assert.equal(gateExplicit(result), true);
  });
  test("hosted is read as artifact on a lane that sends no page to a page host", () => {
    assert.deepEqual(pick(resolve({ lane: "visualization:present", userConfig: "hosted" })), { medium: "artifact", decidedBy: "userConfig" });
  });
});

describe("auto equals unset", () => {
  test("auto in userConfig and the personal override leaves the team value", () => {
    const { dir } = repo({ [TEAM]: ["medium: terminal\n", true], [PERSONAL]: ["medium: auto\n", false] }, ["*.local.yaml"]);
    assert.deepEqual(pick(resolve({ userConfig: "auto", projectRoot: dir })), { medium: "terminal", decidedBy: "team" });
  });
  test("auto everywhere is the plugin default, and an unrendered option is unset", () => {
    assert.deepEqual(pick(resolve({ argument: "auto", userConfig: "auto" })), { medium: "artifact", decidedBy: "plugin default" });
    assert.deepEqual(pick(resolve({ userConfig: "${user_config.medium}" })), { medium: "artifact", decidedBy: "plugin default" });
  });
  test("a lane with no default leaves the choice to the skill", () => {
    assert.deepEqual(pick(resolve({ lane: "visualization:visualize" })), { medium: null, decidedBy: "plugin default" });
  });
});

describe("the team file read from a git ref", () => {
  test("the ref's file decides, never the working tree's", () => {
    const { dir, git, commit } = repo({ [TEAM]: ["medium: file\n", true] });
    commit();
    const base = git("rev-parse", "HEAD").trim();
    writeFileSync(join(dir, TEAM), "medium: terminal\n");
    assert.deepEqual(pick(resolve({ projectRoot: dir, teamRef: base })), { medium: "file", decidedBy: "team" });
    assert.deepEqual(pick(resolve({ projectRoot: dir })), { medium: "terminal", decidedBy: "team" });
  });
  test("a ref that names no commit reads no team file and says so", () => {
    const { dir, commit } = repo({ [TEAM]: ["medium: terminal\n", true] });
    commit();
    for (const teamRef of ["", "-n", "no-such-branch"]) {
      const result = resolve({ projectRoot: dir, teamRef });
      assert.deepEqual(pick(result), { medium: "artifact", decidedBy: "plugin default" }, teamRef);
      assert.ok(result.notices.some((n) => n.kind === "team-ref"), teamRef);
    }
  });
  test("a team file absent at the ref is absent", () => {
    const { dir, git, commit } = repo();
    commit();
    const base = git("rev-parse", "HEAD").trim();
    mkdirSync(join(dir, "docs/conventions"), { recursive: true });
    writeFileSync(join(dir, TEAM), "medium: terminal\n");
    const result = resolve({ projectRoot: dir, teamRef: base });
    assert.deepEqual(pick(result), { medium: "artifact", decidedBy: "plugin default" });
    assert.deepEqual(result.notices, []);
  });
});

describe("retired rendered-views files", () => {
  const retired = () => {
    const home = userHome({ ".claude/rendered-views.md": "medium: artifact\n" });
    const project = repo({ ".claude/rendered-views.md": ["medium: hosted\n", true], ".claude/rendered-views.local.md": ["medium: terminal\n", false] });
    return { home, project };
  };
  test("each yields one notice naming its value and where it moves; only the local value applies", () => {
    const { home, project } = retired();
    const result = resolve({ lane: "review:explain-change", projectRoot: project.dir }, { userHome: home });
    assert.deepEqual(pick(result), { medium: "terminal", decidedBy: "retired .claude/rendered-views.local.md" });
    const notices = result.notices.filter((n) => n.kind === "retired").map(({ path, value, destination }) => ({ path, value, destination }));
    assert.deepEqual(notices, [
      { path: "~/.claude/rendered-views.md", value: "artifact", destination: PERSONAL },
      { path: ".claude/rendered-views.md", value: "hosted", destination: TEAM },
      { path: ".claude/rendered-views.local.md", value: "terminal", destination: PERSONAL },
    ]);
    assert.match(result.notices.find((n) => n.path === ".claude/rendered-views.md").text, /a team file never publishes/);
  });
  test("an unchanged file does not notice twice; a changed one, or another plugin, does", () => {
    const { home, project } = retired();
    const dataDir = tempDir("view-settings-data-");
    const run = (data = dataDir) => resolve({ projectRoot: project.dir }, { userHome: home, dataDir: data }).notices.filter((n) => n.kind === "retired").map((n) => n.path);
    assert.equal(run().length, 3);
    assert.deepEqual(run(), []);
    writeFileSync(join(home, ".claude/rendered-views.md"), "medium: file\n");
    assert.deepEqual(run(), ["~/.claude/rendered-views.md"]);
    assert.equal(run(tempDir("view-settings-other-plugin-")).length, 3);
    assert.ok(readdirSync(join(dataDir, "view-settings")).length > 0, "state is keyed under the plugin data directory");
  });
});

describe("a retired file's terminal or file value keeps the view local", () => {
  const USER_FILE = ".claude/rendered-views.md";
  test("a retired user file's file value decides with no other scope, names the file, and notices once", () => {
    const home = userHome({ [USER_FILE]: "medium: file\n" });
    const dataDir = tempDir("view-settings-data-");
    const first = resolve({ lane: "review:explain-change" }, { userHome: home, dataDir });
    assert.deepEqual(pick(first), { medium: "file", decidedBy: "retired ~/.claude/rendered-views.md" });
    assert.deepEqual(first.notices.filter((n) => n.kind === "retired").map((n) => n.path), ["~/.claude/rendered-views.md"]);
    assert.equal(reportLines(first)[0], "view: file (retired ~/.claude/rendered-views.md)");
    const again = resolve({ lane: "review:explain-change" }, { userHome: home, dataDir });
    assert.deepEqual(pick(again), { medium: "file", decidedBy: "retired ~/.claude/rendered-views.md" }, "the value still applies once the notice is no longer shown");
    assert.deepEqual(again.notices, []);
  });
  test("a retired repo file's terminal value beats a publishing plugin default", () => {
    const { dir } = repo({ [USER_FILE]: ["medium: terminal\n", true] });
    const result = resolve({ lane: "review:explain-change", projectRoot: dir });
    assert.deepEqual(pick(result), { medium: "terminal", decidedBy: "retired .claude/rendered-views.md" });
    assert.equal(gateExplicit(result), false);
  });
  for (const medium of ["file", "terminal"]) {
    test(`the planning lane's artifact default yields to a retired user file's ${medium} value`, () => {
      const home = userHome({ [USER_FILE]: `medium: ${medium}\n` });
      assert.deepEqual(pick(resolve({ lane: "planning" }, { userHome: home })), { medium, decidedBy: "retired ~/.claude/rendered-views.md" });
    });
  }
  test("a retired file's publishing value is never applied: the plugin default decides", () => {
    const home = userHome({ [USER_FILE]: "medium: artifact\n" });
    const { dir } = repo({ ".claude/rendered-views.local.md": ["medium: hosted\n", false] });
    const result = resolve({ lane: "architecture", projectRoot: dir }, { userHome: home });
    assert.deepEqual(pick(result), { medium: "file", decidedBy: "plugin default" });
    assert.equal(gateExplicit(result), false);
  });
  test("userConfig artifact and a retired file value give file", () => {
    const home = userHome({ [USER_FILE]: "medium: file\n" });
    const result = resolve({ lane: "review:explain-change", userConfig: "artifact" }, { userHome: home });
    assert.deepEqual(pick(result), { medium: "file", decidedBy: "retired ~/.claude/rendered-views.md" });
    assert.equal(gateExplicit(result), false);
  });
  test("a local value from a real scope names that scope over a retired one", () => {
    const home = userHome({ [USER_FILE]: "medium: file\n" });
    assert.deepEqual(pick(resolve({ lane: "review:explain-change", userConfig: "terminal" }, { userHome: home })), { medium: "terminal", decidedBy: "userConfig" });
  });
  test("among retired local values, the repo's personal file, then its shared file, then the user file", () => {
    const home = userHome({ [USER_FILE]: "medium: file\n" });
    const { dir } = repo({ [USER_FILE]: ["medium: file\n", true], ".claude/rendered-views.local.md": ["medium: terminal\n", false] });
    assert.deepEqual(pick(resolve({ lane: "review:explain-change", projectRoot: dir }, { userHome: home })), { medium: "terminal", decidedBy: "retired .claude/rendered-views.local.md" });
    const shared = repo({ [USER_FILE]: ["medium: terminal\n", true] });
    assert.deepEqual(pick(resolve({ lane: "review:explain-change", projectRoot: shared.dir }, { userHome: home })), { medium: "terminal", decidedBy: "retired .claude/rendered-views.md" });
  });
  test("the user file's notice names the personal override first, then the plugin's medium option", () => {
    const home = userHome({ [USER_FILE]: "medium: file\n" });
    const notice = resolve({ lane: "review:explain-change" }, { userHome: home }).notices.find((n) => n.kind === "retired");
    assert.equal(notice.destination, PERSONAL);
    assert.match(notice.text, /^~\/\.claude\/rendered-views\.md .*\(it sets medium: file\).*docs\/conventions\/rendered-views\.local\.yaml.*the review plugin's medium option/);
    assert.doesNotMatch(notice.text, /no longer read/, "a value still applied is not described as unread");
  });
  test("a fenced config block in the team .md keeps a local value local and ignores a publishing one", () => {
    const block = (medium) => `# Rendered views\n\n\`\`\`yaml config\nmedium: ${medium}\n\`\`\`\n`;
    const local = repo({ "docs/conventions/rendered-views.md": [block("terminal"), true] });
    const result = resolve({ lane: "review:explain-change", projectRoot: local.dir });
    assert.deepEqual(pick(result), { medium: "terminal", decidedBy: "retired docs/conventions/rendered-views.md" });
    assert.deepEqual(result.notices.filter((n) => n.kind === "retired").map(({ path, destination }) => ({ path, destination })), [{ path: "docs/conventions/rendered-views.md", destination: TEAM }]);
    const publishing = repo({ "docs/conventions/rendered-views.md": [block("artifact"), true] });
    assert.deepEqual(pick(resolve({ lane: "architecture", projectRoot: publishing.dir })), { medium: "file", decidedBy: "plugin default" });
  });
  describe("only the config block's own medium counts, not an example fence before it", () => {
    const TEAM_MD = "docs/conventions/rendered-views.md";
    const doc = (example, config) => `# Rendered views\n\n\`\`\`yaml\nmedium: ${example}\n\`\`\`\n\n\`\`\`yaml config\n${config}\`\`\`\n`;
    const fenced = (result) => result.notices.find((n) => n.kind === "retired" && n.path === TEAM_MD);
    test("an example terminal before a config block that sets no medium gives the plugin default", () => {
      const project = repo({ [TEAM_MD]: [doc("terminal", "other: 1\n"), true] });
      const result = resolve({ lane: "architecture", projectRoot: project.dir });
      assert.deepEqual(pick(result), { medium: "file", decidedBy: "plugin default" }, "the example fence's terminal must not decide the medium");
      assert.equal(fenced(result).value, null, "the notice reports no medium for a block that sets none");
      assert.match(fenced(result).text, /is no longer read/);
    });
    test("an example terminal before a config block setting artifact gives the plugin default", () => {
      const project = repo({ [TEAM_MD]: [doc("terminal", "medium: artifact\n"), true] });
      const result = resolve({ lane: "architecture", projectRoot: project.dir });
      assert.deepEqual(pick(result), { medium: "file", decidedBy: "plugin default" }, "the block's publishing value is ignored and the example's terminal is not used");
      assert.equal(fenced(result).value, "artifact", "the notice reports the block's own medium");
    });
    test("a config block setting file after an example artifact keeps the view local, naming the team .md", () => {
      const project = repo({ [TEAM_MD]: [doc("artifact", "medium: file\n"), true] });
      const result = resolve({ lane: "review:explain-change", projectRoot: project.dir });
      assert.deepEqual(pick(result), { medium: "file", decidedBy: `retired ${TEAM_MD}` }, "the block's file value decides over the lane's artifact default");
      assert.equal(fenced(result).value, "file", "the notice reports the block's own medium");
      assert.match(fenced(result).text, /still keeps the view local/);
    });
  });
});

describe("the fallback chain and the report line", () => {
  test("a non-interactive run falls to the terminal and names why", () => {
    const result = resolve({ lane: "review:explain-change", userConfig: "artifact" }, { interactive: false });
    assert.deepEqual(pick(result), { medium: "terminal", decidedBy: "fell back: artifact unreachable: non-interactive run" });
    assert.equal(result.preferred, "artifact");
  });
  test("the report line names the medium and what decided it, then each notice", () => {
    assert.deepEqual(reportLines({ medium: "file", decidedBy: "userConfig", notices: [{ text: "x is no longer read" }] }), ["view: file (userConfig)", "notice: x is no longer read"]);
  });
});

describe("CLI", () => {
  const run = (args, env = {}) => spawnSync(process.execPath, [CLI, ...args], { encoding: "utf8", env: { ...process.env, HOME: EMPTY_HOME, USERPROFILE: EMPTY_HOME, CI: "", CLAUDE_PLUGIN_DATA: "", ...env } });
  test("team artifact and userConfig file print file and name userConfig; without userConfig, the plugin default", () => {
    const { dir } = repo({ [TEAM]: ["medium: artifact\n", true] });
    const withOption = run(["resolve", "--lane", "planning", "--option", "file"], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(withOption.status, 0, withOption.stderr);
    const [json, ...report] = withOption.stdout.trimEnd().split("\n");
    assert.deepEqual(pick(JSON.parse(json)), { medium: "file", decidedBy: "userConfig" });
    assert.equal(report[0], "view: file (userConfig)");
    const without = run(["resolve", "--lane", "planning", "--option", "${user_config.medium}"], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(without.stdout.split("\n")[1], "view: artifact (plugin default)");
  });
  test("--team-ref and --argument reach the resolver", () => {
    const { dir, git, commit } = repo({ [TEAM]: ["medium: terminal\n", true] });
    commit();
    writeFileSync(join(dir, TEAM), "medium: file\n");
    const ref = run(["resolve", "--lane", "planning", "--option", "", "--team-ref", git("rev-parse", "HEAD").trim()], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(ref.stdout.split("\n")[1], "view: terminal (team)");
    const arg = run(["resolve", "--lane", "planning", "--option", "", "--argument", "artifact"], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(arg.stdout.split("\n")[1], "view: artifact (argument)");
  });
  test("the JSON says whether the medium shows a page and whether it publishes", () => {
    const fields = (option) => {
      const { page, publishes } = JSON.parse(run(["resolve", "--lane", "planning", "--option", option], { CLAUDE_PROJECT_DIR: EMPTY_HOME }).stdout.split("\n")[0]);
      return { page, publishes };
    };
    assert.deepEqual(fields("terminal"), { page: false, publishes: false });
    assert.deepEqual(fields("file"), { page: true, publishes: false });
    assert.deepEqual(fields("artifact"), { page: true, publishes: true });
    const unset = JSON.parse(run(["resolve", "--lane", "visualization:visualize", "--option", ""], { CLAUDE_PROJECT_DIR: EMPTY_HOME }).stdout.split("\n")[0]);
    assert.equal("page" in unset, false, "no medium resolved, so the lane's own rule decides");
  });
  test("every registered copy imports its sibling modules and resolves", () => {
    const manifest = readFileSync(join(HERE, "..", "scripts", "shared-copies.txt"), "utf8");
    const copies = [...manifest.matchAll(/^lib\/view-settings\.mjs (\S+)$/gm)].map(([, copy]) => copy);
    assert.ok(copies.length > 0, "no view-settings copy registered");
    for (const copy of copies) {
      const out = spawnSync(process.execPath, [join(HERE, "..", copy), "resolve", "--lane", "planning", "--option", ""], { encoding: "utf8", env: { ...process.env, HOME: EMPTY_HOME, USERPROFILE: EMPTY_HOME, CI: "", CLAUDE_PLUGIN_DATA: "", CLAUDE_PROJECT_DIR: EMPTY_HOME } });
      assert.equal(out.status, 0, `${copy}: ${out.stderr}`);
      assert.match(out.stdout.split("\n")[1] ?? "", /^view: /, copy);
    }
  });
  test("a CI run falls back to the terminal", () => {
    const out = run(["resolve", "--lane", "review:explain-change", "--option", "artifact"], { CI: "true", CLAUDE_PROJECT_DIR: EMPTY_HOME });
    assert.equal(out.stdout.split("\n")[1], "view: terminal (fell back: artifact unreachable: non-interactive run)");
  });
  test("every registered view lane resolves to its shipped default with no scope set", () => {
    // Expected defaults come from each skill's own medium rule: unset means `file` for the map
    // records, blindspot, the post-mortem, illustrate and the work-items pages; the rest leave the
    // choice to the skill's content rule, which prints as auto.
    const expected = {
      architecture: "file",
      "discovery:blindspot": "file",
      "debugging:debug": "file",
      "education:illustrate": "file",
      "work-items:morning-brief": "file",
      "work-items:triage": "file",
      "adhd:clarify": "auto",
      "codebase-health:audit": "auto",
      "overengineering:audit": "auto",
      "education:teach": "auto",
      "prototype:explore-directions": "auto",
      "prototype:pressure-test": "auto",
      "ai-briefing:generate": "auto",
    };
    for (const [lane, medium] of Object.entries(expected)) {
      const out = run(["resolve", "--lane", lane, "--option", ""], { CLAUDE_PROJECT_DIR: EMPTY_HOME });
      assert.equal(out.status, 0, `${lane}: ${out.stderr}`);
      assert.equal(out.stdout.split("\n")[1], `view: ${medium} (plugin default)`, lane);
    }
  });
  test("refuses an unknown lane, a missing option, an unknown medium or flag", () => {
    for (const args of [
      ["resolve", "--lane", "nope", "--option", ""],
      ["resolve", "--lane", "planning"],
      ["resolve", "--lane", "planning", "--option", "", "--argument", "banner"],
      ["resolve", "--lane", "planning", "--option", "", "--force"],
      ["lookup"],
    ]) {
      assert.equal(run(args).status, 2, args.join(" "));
    }
  });
  test("refuses an inherited object key as a medium or a lane", () => {
    for (const args of [
      ["resolve", "--lane", "planning", "--option", "", "--argument", "toString"],
      ["resolve", "--lane", "planning", "--option", "", "--argument", "__proto__"],
      ["resolve", "--lane", "constructor", "--option", ""],
    ]) {
      const out = run(args);
      assert.equal(out.status, 2, `${args.join(" ")}: ${out.stderr}`);
      assert.match(out.stderr, /^usage: /, args.join(" "));
    }
  });
});

describe("inherited object keys are not mediums or lanes", () => {
  test("an inherited key as the argument does not decide", () => {
    for (const argument of ["toString", "__proto__"]) {
      assert.deepEqual(pick(resolve({ argument, userConfig: "terminal" })), { medium: "terminal", decidedBy: "userConfig" }, argument);
    }
  });
  test("an inherited key as the lane is an unknown lane", () => {
    assert.throws(() => resolveMedium({ lane: "constructor" }, { userHome: EMPTY_HOME }), /unknown lane/);
  });
});
