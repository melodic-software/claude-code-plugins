import { strict as assert } from "node:assert";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "./test-tmp.mjs";
process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const HERE = dirname(fileURLToPath(import.meta.url));
const CLI = join(HERE, "view-settings.mjs");
const { resolveMedium, resolveBranding, contrastRatio, validateSvgLogo, gateExplicit } = await import("./view-settings.mjs");
const { BRANDING_USER_CONFIG_OPTION, PALETTE_ROLES, PRODUCERS, SHIPPED_TOKENS, TYPE_STACKS, reportLines } = await import("./view-registry.mjs");
const { styleRefused } = await import("./html-escape.mjs");
const { buildView, validateView } = await import("./view-builder.mjs");

const TEAM = "docs/conventions/rendered-views.yaml";
const PERSONAL = "docs/conventions/rendered-views.local.yaml";

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
const resolve = (request, options = {}) => resolveMedium({ producer: "planning", ...request }, { userHome: EMPTY_HOME, dataDir: null, ...options });
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
    assert.deepEqual(pick(resolve({ producer: "review:explain-change", userConfig: "hosted", projectRoot: dir })), { medium: "file", decidedBy: "team" });
  });
  test("precedence among local values: personal override, then team, then userConfig", () => {
    const { dir } = repo({ [TEAM]: ["medium: file\n", true], [PERSONAL]: ["medium: terminal\n", false] }, ["*.local.yaml"]);
    assert.deepEqual(pick(resolve({ userConfig: "file", projectRoot: dir })), { medium: "terminal", decidedBy: "personal override" });
    const teamOnly = repo({ [TEAM]: ["medium: file\n", true] });
    assert.deepEqual(pick(resolve({ userConfig: "terminal", projectRoot: teamOnly.dir })), { medium: "file", decidedBy: "team" });
  });
  test("a tracked personal override's local value still keeps the view local", () => {
    const { dir } = repo({ [PERSONAL]: ["medium: terminal\n", true] });
    assert.deepEqual(pick(resolve({ producer: "review:explain-change", userConfig: "artifact", projectRoot: dir })), { medium: "terminal", decidedBy: "personal override" });
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
  test("team artifact alone never publishes: the producer's own default applies", () => {
    const { dir } = repo({ [TEAM]: ["medium: artifact\n", true] });
    const result = resolve({ projectRoot: dir });
    assert.deepEqual(pick(result), { medium: "artifact", decidedBy: "plugin default" });
    assert.equal(gateExplicit(result), false);
    assert.ok(result.notices.some((n) => n.kind === "ignored" && /a team file never publishes/.test(n.text)));
  });
  test("team hosted on the digest producer falls to the plugin default, which the content gate still checks", () => {
    const { dir } = repo({ [TEAM]: ["medium: hosted\n", true] });
    const result = resolve({ producer: "review:explain-change", projectRoot: dir });
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
    assert.deepEqual(pick(resolve({ producer: "review:explain-change", userConfig: "artifact", projectRoot: dir })), { medium: "hosted", decidedBy: "personal override" });
  });
  test("plugin default artifact publishes when no scope decides", () => {
    const result = resolve({ producer: "review:explain-change" });
    assert.deepEqual(pick(result), { medium: "artifact", decidedBy: "plugin default" });
    assert.equal(gateExplicit(result), false);
  });
  test("review resolves hosted from userConfig", () => {
    const result = resolve({ producer: "review:explain-change", userConfig: "hosted" });
    assert.deepEqual(pick(result), { medium: "hosted", decidedBy: "userConfig" });
    assert.equal(gateExplicit(result), true);
  });
  test("hosted is read as artifact on a producer that sends no page to a page host", () => {
    assert.deepEqual(pick(resolve({ producer: "visualization:present", userConfig: "hosted" })), { medium: "artifact", decidedBy: "userConfig" });
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
  test("a producer with no default leaves the choice to the skill", () => {
    assert.deepEqual(pick(resolve({ producer: "visualization:visualize" })), { medium: null, decidedBy: "plugin default" });
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
    const result = resolve({ producer: "review:explain-change", projectRoot: project.dir }, { userHome: home });
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
  test("the retired user file's notice names the plugin's medium option only when the plugin ships one", () => {
    const home = userHome({ ".claude/rendered-views.md": "medium: file\n" });
    const userNotice = (producer) => resolve({ producer }, { userHome: home }).notices.find((n) => n.path === "~/.claude/rendered-views.md").text;
    assert.ok(userNotice("planning").endsWith("; per user, the planning plugin's medium option also works"));
    assert.doesNotMatch(userNotice("overengineering:audit"), /per user/);
  });
  test("each producer's hasMediumOption matches whether its plugin ships a medium option", () => {
    for (const producer of Object.values(PRODUCERS)) {
      const manifest = JSON.parse(readFileSync(join(HERE, "..", "plugins", producer.producerId.split(":")[0], ".claude-plugin", "plugin.json"), "utf8"));
      assert.equal(producer.hasMediumOption, Object.hasOwn(manifest.userConfig ?? {}, "medium"), producer.producerId);
    }
  });
});

describe("a retired file's terminal or file value keeps the view local", () => {
  const USER_FILE = ".claude/rendered-views.md";
  test("a retired user file's file value decides with no other scope, names the file, and notices once", () => {
    const home = userHome({ [USER_FILE]: "medium: file\n" });
    const dataDir = tempDir("view-settings-data-");
    const first = resolve({ producer: "review:explain-change" }, { userHome: home, dataDir });
    assert.deepEqual(pick(first), { medium: "file", decidedBy: "retired ~/.claude/rendered-views.md" });
    assert.deepEqual(first.notices.filter((n) => n.kind === "retired").map((n) => n.path), ["~/.claude/rendered-views.md"]);
    assert.equal(reportLines(first)[0], "view: file (retired ~/.claude/rendered-views.md)");
    const again = resolve({ producer: "review:explain-change" }, { userHome: home, dataDir });
    assert.deepEqual(pick(again), { medium: "file", decidedBy: "retired ~/.claude/rendered-views.md" }, "the value still applies once the notice is no longer shown");
    assert.deepEqual(again.notices, []);
  });
  test("a retired repo file's terminal value beats a publishing plugin default", () => {
    const { dir } = repo({ [USER_FILE]: ["medium: terminal\n", true] });
    const result = resolve({ producer: "review:explain-change", projectRoot: dir });
    assert.deepEqual(pick(result), { medium: "terminal", decidedBy: "retired .claude/rendered-views.md" });
    assert.equal(gateExplicit(result), false);
  });
  for (const medium of ["file", "terminal"]) {
    test(`the planning producer's artifact default yields to a retired user file's ${medium} value`, () => {
      const home = userHome({ [USER_FILE]: `medium: ${medium}\n` });
      assert.deepEqual(pick(resolve({ producer: "planning" }, { userHome: home })), { medium, decidedBy: "retired ~/.claude/rendered-views.md" });
    });
  }
  test("a retired file's publishing value is never applied: the plugin default decides", () => {
    const home = userHome({ [USER_FILE]: "medium: artifact\n" });
    const { dir } = repo({ ".claude/rendered-views.local.md": ["medium: hosted\n", false] });
    const result = resolve({ producer: "architecture", projectRoot: dir }, { userHome: home });
    assert.deepEqual(pick(result), { medium: "file", decidedBy: "plugin default" });
    assert.equal(gateExplicit(result), false);
  });
  test("userConfig artifact and a retired file value give file", () => {
    const home = userHome({ [USER_FILE]: "medium: file\n" });
    const result = resolve({ producer: "review:explain-change", userConfig: "artifact" }, { userHome: home });
    assert.deepEqual(pick(result), { medium: "file", decidedBy: "retired ~/.claude/rendered-views.md" });
    assert.equal(gateExplicit(result), false);
  });
  test("a local value from a real scope names that scope over a retired one", () => {
    const home = userHome({ [USER_FILE]: "medium: file\n" });
    assert.deepEqual(pick(resolve({ producer: "review:explain-change", userConfig: "terminal" }, { userHome: home })), { medium: "terminal", decidedBy: "userConfig" });
  });
  test("among retired local values, the repo's personal file, then its shared file, then the user file", () => {
    const home = userHome({ [USER_FILE]: "medium: file\n" });
    const { dir } = repo({ [USER_FILE]: ["medium: file\n", true], ".claude/rendered-views.local.md": ["medium: terminal\n", false] });
    assert.deepEqual(pick(resolve({ producer: "review:explain-change", projectRoot: dir }, { userHome: home })), { medium: "terminal", decidedBy: "retired .claude/rendered-views.local.md" });
    const shared = repo({ [USER_FILE]: ["medium: terminal\n", true] });
    assert.deepEqual(pick(resolve({ producer: "review:explain-change", projectRoot: shared.dir }, { userHome: home })), { medium: "terminal", decidedBy: "retired .claude/rendered-views.md" });
  });
  test("the user file's notice names the personal override first, then the plugin's medium option", () => {
    const home = userHome({ [USER_FILE]: "medium: file\n" });
    const notice = resolve({ producer: "review:explain-change" }, { userHome: home }).notices.find((n) => n.kind === "retired");
    assert.equal(notice.destination, PERSONAL);
    assert.match(notice.text, /^~\/\.claude\/rendered-views\.md .*\(it sets medium: file\).*docs\/conventions\/rendered-views\.local\.yaml.*the review plugin's medium option/);
    assert.doesNotMatch(notice.text, /no longer read/, "a value still applied is not described as unread");
  });
  test("a fenced config block in the team .md keeps a local value local and ignores a publishing one", () => {
    const block = (medium) => `# Rendered views\n\n\`\`\`yaml config\nmedium: ${medium}\n\`\`\`\n`;
    const local = repo({ "docs/conventions/rendered-views.md": [block("terminal"), true] });
    const result = resolve({ producer: "review:explain-change", projectRoot: local.dir });
    assert.deepEqual(pick(result), { medium: "terminal", decidedBy: "retired docs/conventions/rendered-views.md" });
    assert.deepEqual(result.notices.filter((n) => n.kind === "retired").map(({ path, destination }) => ({ path, destination })), [{ path: "docs/conventions/rendered-views.md", destination: TEAM }]);
    const publishing = repo({ "docs/conventions/rendered-views.md": [block("artifact"), true] });
    assert.deepEqual(pick(resolve({ producer: "architecture", projectRoot: publishing.dir })), { medium: "file", decidedBy: "plugin default" });
  });
  describe("only the config block's own medium counts, not an example fence before it", () => {
    const TEAM_MD = "docs/conventions/rendered-views.md";
    const doc = (example, config) => `# Rendered views\n\n\`\`\`yaml\nmedium: ${example}\n\`\`\`\n\n\`\`\`yaml config\n${config}\`\`\`\n`;
    const fenced = (result) => result.notices.find((n) => n.kind === "retired" && n.path === TEAM_MD);
    test("an example terminal before a config block that sets no medium gives the plugin default", () => {
      const project = repo({ [TEAM_MD]: [doc("terminal", "other: 1\n"), true] });
      const result = resolve({ producer: "architecture", projectRoot: project.dir });
      assert.deepEqual(pick(result), { medium: "file", decidedBy: "plugin default" }, "the example fence's terminal must not decide the medium");
      assert.equal(fenced(result).value, null, "the notice reports no medium for a block that sets none");
      assert.match(fenced(result).text, /is no longer read/);
    });
    test("an example terminal before a config block setting artifact gives the plugin default", () => {
      const project = repo({ [TEAM_MD]: [doc("terminal", "medium: artifact\n"), true] });
      const result = resolve({ producer: "architecture", projectRoot: project.dir });
      assert.deepEqual(pick(result), { medium: "file", decidedBy: "plugin default" }, "the block's publishing value is ignored and the example's terminal is not used");
      assert.equal(fenced(result).value, "artifact", "the notice reports the block's own medium");
    });
    test("a config block setting file after an example artifact keeps the view local, naming the team .md", () => {
      const project = repo({ [TEAM_MD]: [doc("artifact", "medium: file\n"), true] });
      const result = resolve({ producer: "review:explain-change", projectRoot: project.dir });
      assert.deepEqual(pick(result), { medium: "file", decidedBy: `retired ${TEAM_MD}` }, "the block's file value decides over the producer's artifact default");
      assert.equal(fenced(result).value, "file", "the notice reports the block's own medium");
      assert.match(fenced(result).text, /still keeps the view local/);
    });
  });
});

describe("the fallback chain and the report line", () => {
  test("a non-interactive run falls to the terminal and names why", () => {
    const result = resolve({ producer: "review:explain-change", userConfig: "artifact" }, { interactive: false });
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
    const withOption = run(["resolve", "--producer", "planning", "--option", "file"], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(withOption.status, 0, withOption.stderr);
    const [json, ...report] = withOption.stdout.trimEnd().split("\n");
    assert.deepEqual(pick(JSON.parse(json)), { medium: "file", decidedBy: "userConfig" });
    assert.equal(report[0], "view: file (userConfig)");
    const without = run(["resolve", "--producer", "planning", "--option", "${user_config.medium}"], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(without.stdout.split("\n")[1], "view: artifact (plugin default)");
  });
  test("--team-ref and --argument reach the resolver", () => {
    const { dir, git, commit } = repo({ [TEAM]: ["medium: terminal\n", true] });
    commit();
    writeFileSync(join(dir, TEAM), "medium: file\n");
    const ref = run(["resolve", "--producer", "planning", "--option", "", "--team-ref", git("rev-parse", "HEAD").trim()], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(ref.stdout.split("\n")[1], "view: terminal (team)");
    const arg = run(["resolve", "--producer", "planning", "--option", "", "--argument", "artifact"], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(arg.stdout.split("\n")[1], "view: artifact (argument)");
  });
  test("the JSON says whether the medium shows a page and whether it publishes", () => {
    const fields = (option) => {
      const { page, publishes } = JSON.parse(run(["resolve", "--producer", "planning", "--option", option], { CLAUDE_PROJECT_DIR: EMPTY_HOME }).stdout.split("\n")[0]);
      return { page, publishes };
    };
    assert.deepEqual(fields("terminal"), { page: false, publishes: false });
    assert.deepEqual(fields("file"), { page: true, publishes: false });
    assert.deepEqual(fields("artifact"), { page: true, publishes: true });
    const unset = JSON.parse(run(["resolve", "--producer", "visualization:visualize", "--option", ""], { CLAUDE_PROJECT_DIR: EMPTY_HOME }).stdout.split("\n")[0]);
    assert.equal("page" in unset, false, "no medium resolved, so the producer's own rule decides");
  });
  test("every registered copy imports its sibling modules and resolves", () => {
    const manifest = readFileSync(join(HERE, "..", "scripts", "shared-copies.txt"), "utf8");
    const copies = [...manifest.matchAll(/^lib\/view-settings\.mjs (\S+)$/gm)].map(([, copy]) => copy);
    assert.ok(copies.length > 0, "no view-settings copy registered");
    for (const copy of copies) {
      const out = spawnSync(process.execPath, [join(HERE, "..", copy), "resolve", "--producer", "planning", "--option", ""], { encoding: "utf8", env: { ...process.env, HOME: EMPTY_HOME, USERPROFILE: EMPTY_HOME, CI: "", CLAUDE_PLUGIN_DATA: "", CLAUDE_PROJECT_DIR: EMPTY_HOME } });
      assert.equal(out.status, 0, `${copy}: ${out.stderr}`);
      assert.match(out.stdout.split("\n")[1] ?? "", /^view: /, copy);
    }
  });
  test("a CI run falls back to the terminal", () => {
    const out = run(["resolve", "--producer", "review:explain-change", "--option", "artifact"], { CI: "true", CLAUDE_PROJECT_DIR: EMPTY_HOME });
    assert.equal(out.stdout.split("\n")[1], "view: terminal (fell back: artifact unreachable: non-interactive run)");
  });
  test("every registered view producer resolves to its shipped default with no scope set", () => {
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
    for (const [producer, medium] of Object.entries(expected)) {
      const out = run(["resolve", "--producer", producer, "--option", ""], { CLAUDE_PROJECT_DIR: EMPTY_HOME });
      assert.equal(out.status, 0, `${producer}: ${out.stderr}`);
      assert.equal(out.stdout.split("\n")[1], `view: ${medium} (plugin default)`, producer);
    }
  });
  test("refuses an unknown producer, a missing option, an unknown medium or flag", () => {
    for (const args of [
      ["resolve", "--producer", "nope", "--option", ""],
      ["resolve", "--producer", "planning"],
      ["resolve", "--producer", "planning", "--option", "", "--argument", "banner"],
      ["resolve", "--producer", "planning", "--option", "", "--force"],
      ["lookup"],
    ]) {
      assert.equal(run(args).status, 2, args.join(" "));
    }
  });
  test("refuses an inherited object key as a medium or a producer", () => {
    for (const args of [
      ["resolve", "--producer", "planning", "--option", "", "--argument", "toString"],
      ["resolve", "--producer", "planning", "--option", "", "--argument", "__proto__"],
      ["resolve", "--producer", "constructor", "--option", ""],
    ]) {
      const out = run(args);
      assert.equal(out.status, 2, `${args.join(" ")}: ${out.stderr}`);
      assert.match(out.stderr, /^usage: /, args.join(" "));
    }
  });
});

describe("inherited object keys are not mediums or producers", () => {
  test("an inherited key as the argument does not decide", () => {
    for (const argument of ["toString", "__proto__"]) {
      assert.deepEqual(pick(resolve({ argument, userConfig: "terminal" })), { medium: "terminal", decidedBy: "userConfig" }, argument);
    }
  });
  test("an inherited key as the producer is an unknown producer", () => {
    assert.throws(() => resolveMedium({ producer: "constructor" }, { userHome: EMPTY_HOME }), /unknown producer/);
  });
});

const PNG_BYTES = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52]);
const JPEG_BYTES = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
const WOFF2_BYTES = Buffer.from([0x77, 0x4f, 0x46, 0x32, 0x00, 0x01, 0x00, 0x00]);
const WOFF_BYTES = Buffer.from([0x77, 0x4f, 0x46, 0x46, 0x00, 0x01, 0x00, 0x00]);
const TTF_BYTES = Buffer.from([0x00, 0x01, 0x00, 0x00, 0x00, 0x0c, 0x00, 0x80]);
const TTF_TRUE_BYTES = Buffer.from([0x74, 0x72, 0x75, 0x65, 0x00, 0x0c, 0x00, 0x80]);
const OTF_BYTES = Buffer.from([0x4f, 0x54, 0x54, 0x4f, 0x00, 0x0c, 0x00, 0x80]);
const VALID_SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" role="img" aria-label="Acme"><defs><linearGradient id="g"><stop offset="0" stop-color="#111111"/></linearGradient></defs><path d="M2 2L22 22" fill="url(#g)"/><text x="4" y="12">Acme</text></svg>';

const brand = (request = {}, options = {}) => resolveBranding(request, { userHome: EMPTY_HOME, ...options });

describe("branding defaults, tokens parity and userConfig option shape", () => {
  test("SHIPPED_TOKENS matches lib/html-tokens.css verbatim", () => {
    const css = readFileSync(join(HERE, "html-tokens.css"), "utf8").replace(/\r\n?/g, "\n");
    const lightBlock = /^:root \{([^}]*)\}/m.exec(css)[1];
    const darkBlock = /^:root\[data-theme=dark\] \{([^}]*)\}/m.exec(css)[1];
    const readVar = (body, name) => new RegExp(`(?:^|\\n)[ \\t]*--${name}:[ \\t]*([^;]+);`).exec(body)?.[1];
    const resolveHex = (body, name) => {
      let v = readVar(body, name);
      for (let i = 0; v?.startsWith("var(--") && i < 5; i += 1) v = readVar(lightBlock, v.slice(6, -1));
      return v?.toUpperCase();
    };
    for (const role of PALETTE_ROLES) {
      assert.equal(SHIPPED_TOKENS.palette.light[role], resolveHex(lightBlock, role), `light.${role}`);
      assert.equal(SHIPPED_TOKENS.palette.dark[role], resolveHex(darkBlock, role), `dark.${role}`);
    }
    for (const stack of TYPE_STACKS) {
      assert.equal(SHIPPED_TOKENS.type[stack], readVar(lightBlock, stack), `type.${stack}`);
    }
  });

  test("BRANDING_USER_CONFIG_OPTION conforms to docs/contracts/plugin-option-naming", () => {
    const { key, type, title, description, default: def } = BRANDING_USER_CONFIG_OPTION;
    assert.match(key, /^[a-z][a-z0-9_]*$/);
    assert.equal(type, "string");
    assert.equal(def, "");
    assert.ok([...title].length <= 40, `title length ${title.length}`);
    assert.match(title, /^[A-Z0-9]/);
    const words = title.split(/[\s-]+/).map((w) => w.replace(/^[^A-Za-z0-9]+|[^A-Za-z0-9]+$/g, ""));
    assert.equal(words.some((w) => /^[A-Z]{6,}$/.test(w)), false);
    assert.equal(words.slice(1).some((w) => /^[A-Z][a-z]+$/.test(w)), false);
    assert.ok([...description].length <= 300, `description length ${description.length}`);
    assert.equal(description.includes("`"), false);
    assert.equal(description.includes("*"), false);
    assert.equal(/\[[^\]]*\]\([^)]*\)/.test(description), false);
    assert.equal(description.includes("\u2014"), false);
  });

  test("with no layer configured, shipped defaults apply with empty CSS and default attribution", () => {
    const res = brand();
    assert.deepEqual(res.palette, SHIPPED_TOKENS.palette);
    assert.deepEqual(res.type, { ...SHIPPED_TOKENS.type, fonts: [] });
    assert.deepEqual(res.logo, { kind: null, svg: null, dataUrl: null, mediaType: null, label: null });
    assert.equal(res.css, "");
    assert.deepEqual(res.notices, []);
    assert.equal(Object.values(res.sources).every((s) => s === "default"), true);
  });
});

describe("branding resolution order (plain ADR 0075: personal override > team > userConfig > default)", () => {
  test("personal override beats team, team beats userConfig, and unmentioned keys merge per key", () => {
    const { dir } = repo(
      {
        [TEAM]: [
          [
            "branding:",
            "  palette:",
            "    light:",
            '      accent: "#1D4ED8"',
            '      link: "#1E40AF"',
            "  type:",
            '    sans: "Inter, system-ui, sans-serif"',
            "  logo:",
            '    label: "Team Brand"',
            "",
          ].join("\n"),
          true,
        ],
        [PERSONAL]: [
          [
            "branding:",
            "  palette:",
            "    light:",
            '      accent: "#0F766E"',
            "  logo:",
            '    label: "Personal Label"',
            "",
          ].join("\n"),
          false,
        ],
      },
      ["*.local.yaml"],
    );
    const userCfg = JSON.stringify({
      palette: { light: { accent: "#B91C1C", focus: "#1D4ED8" }, dark: { accent: "#60A5FA" } },
      type: { mono: "JetBrains Mono, ui-monospace, monospace", sans: "Roboto, sans-serif" },
      logo: { label: "User Label" },
    });
    const res = brand({ userConfig: userCfg, projectRoot: dir });
    assert.deepEqual(res.notices, []);
    assert.equal(res.palette.light.accent, "#0F766E");
    assert.equal(res.sources["palette.light.accent"], "personal override");
    assert.equal(res.palette.light.link, "#1E40AF");
    assert.equal(res.sources["palette.light.link"], "team");
    assert.equal(res.palette.light.focus, "#1D4ED8");
    assert.equal(res.sources["palette.light.focus"], "userConfig");
    assert.equal(res.palette.dark.accent, "#60A5FA");
    assert.equal(res.sources["palette.dark.accent"], "userConfig");
    assert.equal(res.palette.light.bg, SHIPPED_TOKENS.palette.light.bg);
    assert.equal(res.sources["palette.light.bg"], "default");
    assert.equal(res.type.sans, "Inter, system-ui, sans-serif");
    assert.equal(res.sources["type.sans"], "team");
    assert.equal(res.type.mono, "JetBrains Mono, ui-monospace, monospace");
    assert.equal(res.sources["type.mono"], "userConfig");
    assert.equal(res.logo.label, "Personal Label");
    assert.equal(res.sources["logo.label"], "personal override");
    assert.equal(styleRefused(res.css), false, res.css);
  });

  test("unsubstituted userConfig placeholder and empty string act as unset", () => {
    for (const userConfig of ["", "${user_config.branding}", null, undefined]) {
      const res = brand({ userConfig });
      assert.deepEqual(res.notices, []);
      assert.equal(res.css, "");
    }
  });

  test("a tracked team branding value applies without the publish trust walk", () => {
    const { dir } = repo({
      [TEAM]: [["medium: artifact", "branding:", "  palette:", "    light:", '      accent: "#2563EB"', ""].join("\n"), true],
    });
    const res = brand({ projectRoot: dir });
    assert.equal(res.palette.light.accent, "#2563EB");
    assert.equal(res.sources["palette.light.accent"], "team");
    assert.deepEqual(res.notices, []);
  });
});

describe("branding validation refusals keep other layers and valid siblings", () => {
  test("refuses non-six-digit hex colors while preserving lower layer and valid siblings", () => {
    const { dir } = repo(
      {
        [TEAM]: [["branding:", "  palette:", "    light:", '      accent: "#1D4ED8"', '      link: "#1E40AF"', ""].join("\n"), true],
        [PERSONAL]: [
          [
            "branding:",
            "  palette:",
            "    light:",
            '      accent: "#fff"',
            '      link: "red"',
            '      focus: "#11223344"',
            "    dark:",
            '      accent: "rgb(1, 2, 3)"',
            '      link: "#93C5FD; color: red"',
            "",
          ].join("\n"),
          false,
        ],
      },
      ["*.local.yaml"],
    );
    const res = brand({ projectRoot: dir });
    assert.equal(res.palette.light.accent, "#1D4ED8");
    assert.equal(res.sources["palette.light.accent"], "team");
    assert.equal(res.palette.light.link, "#1E40AF");
    assert.equal(res.sources["palette.light.link"], "team");
    assert.equal(res.palette.light.focus, SHIPPED_TOKENS.palette.light.focus);
    assert.equal(res.notices.filter((n) => n.kind === "invalid").length, 5);
  });

  test("refuses font families outside the closed character set while preserving valid stacks", () => {
    const badStacks = [
      "Inter; background: url(https://evil.example/x)",
      "Inter</style><script>alert(1)</script>",
      "Inter\\003b color:red",
      'Inter, "Quoted Double"',
      "Inter'unclosed",
      ", sans-serif",
      "",
      "A".repeat(260),
    ];
    for (const sans of badStacks) {
      const res = brand({ userConfig: JSON.stringify({ type: { sans, serif: "Georgia, serif" } }) });
      assert.equal(res.type.sans, SHIPPED_TOKENS.type.sans, sans);
      assert.equal(res.type.serif, "Georgia, serif", sans);
      assert.ok(res.notices.some((n) => n.kind === "invalid" && n.text.includes("branding.type.sans")), sans);
    }
    const quoted = brand({ userConfig: JSON.stringify({ type: { mono: "ui-monospace, 'SF Mono', Menlo, monospace" } }) });
    assert.deepEqual(quoted.notices, []);
    assert.equal(quoted.type.mono, "ui-monospace, 'SF Mono', Menlo, monospace");
  });

  test("SVG allowlist accepts safe SVG matching builder rules and refuses every dangerous construct", () => {
    assert.equal(validateSvgLogo(VALID_SVG).ok, true);
    const res = brand({ userConfig: JSON.stringify({ logo: { svg: VALID_SVG, label: "Acme" } }) });
    assert.deepEqual(res.notices, []);
    assert.equal(res.logo.kind, "svg");
    assert.equal(res.logo.svg, VALID_SVG);
    const page = buildView({
      profile: "interactive",
      template: `<!doctype html><html><head><meta charset="utf-8"><title>T</title><style>body{margin:0}</style></head><body><div class="rv-bar">${res.logo.svg}</div></body></html>`,
      data: {},
    });
    assert.equal(validateView(page).ok, true);

    const hostileSvgs = [
      "<svg><script>alert(1)</script></svg>",
      "<svg><style>body{background:url(https://evil.example)}</style></svg>",
      '<svg><image href="https://evil.example/a.png"/></svg>',
      '<svg><use href="https://evil.example/a.svg#x"/></svg>',
      "<svg><foreignObject><div>hi</div></foreignObject></svg>",
      '<svg><a href="https://evil.example"><rect width="10" height="10"/></a></svg>',
      '<svg><animate attributeName="href" to="javascript:alert(1)"/></svg>',
      '<svg><set attributeName="x" to="1"/></svg>',
      '<svg><rect onload="alert(1)" width="10" height="10"/></svg>',
      '<svg><rect style="fill:red" width="10" height="10"/></svg>',
      '<svg xml:base="https://evil.example/"><rect width="10" height="10"/></svg>',
      '<svg><path href="https://evil.example/x" d="M0 0"/></svg>',
      '<svg><path xlink:href="javascript:alert(1)" d="M0 0"/></svg>',
      '<svg><rect fill="url(https://evil.example/a)" width="10" height="10"/></svg>',
      '<svg xmlns="http://www.w3.org/1999/xhtml"><rect width="10" height="10"/></svg>',
      "<!-- comment --><svg><rect width=\"10\" height=\"10\"/></svg>",
      '<?xml version="1.0"?><svg><rect width="10" height="10"/></svg>',
      '<!DOCTYPE svg><svg><rect width="10" height="10"/></svg>',
      "<svg><rect width=\"10\" height=\"10\"></svg>",
      "<div>not svg</div>",
      "<svg><text>A & B</text></svg>",
    ];
    for (const svg of hostileSvgs) {
      const check = validateSvgLogo(svg);
      assert.equal(check.ok, false, `expected refusal for ${svg}`);
      const out = brand({ userConfig: JSON.stringify({ logo: { svg } }) });
      assert.equal(out.logo.kind, null, svg);
      assert.ok(out.notices.some((n) => n.kind === "invalid" && n.text.includes("SVG allowlist")), svg);
    }
  });

  test("embeds PNG, JPEG and SVG logo files via magic bytes and refuses spoofed extensions, traversal and symlinks", () => {
    const { dir } = repo({
      [TEAM]: [["branding:", "  logo:", '    file: "docs/brand/logo.bin"', '    label: "Acme"', ""].join("\n"), true],
    });
    mkdirSync(join(dir, "docs/brand"), { recursive: true });
    writeFileSync(join(dir, "docs/brand/logo.bin"), PNG_BYTES);
    const pngRes = brand({ projectRoot: dir });
    assert.deepEqual(pngRes.notices, []);
    assert.equal(pngRes.logo.kind, "image");
    assert.equal(pngRes.logo.mediaType, "image/png");
    assert.equal(pngRes.logo.dataUrl, `data:image/png;base64,${PNG_BYTES.toString("base64")}`);
    assert.match(pngRes.css, /^\.rv-logo \{ background-image: url\(data:image\/png;base64,/);
    assert.equal(styleRefused(pngRes.css), false, pngRes.css);

    writeFileSync(join(dir, "docs/brand/logo.bin"), JPEG_BYTES);
    const jpgRes = brand({ projectRoot: dir });
    assert.deepEqual(jpgRes.notices, []);
    assert.equal(jpgRes.logo.mediaType, "image/jpeg");
    assert.equal(styleRefused(jpgRes.css), false);

    writeFileSync(join(dir, "docs/brand/logo.bin"), VALID_SVG);
    const svgFileRes = brand({ projectRoot: dir });
    assert.deepEqual(svgFileRes.notices, []);
    assert.equal(svgFileRes.logo.kind, "svg");
    assert.equal(svgFileRes.logo.svg, VALID_SVG);

    writeFileSync(join(dir, "docs/brand/fake.png"), Buffer.from("GIF89a\x01\x00\x01\x00"));
    writeFileSync(join(dir, TEAM), ["branding:", "  logo:", "    file: \"docs/brand/fake.png\"", ""].join("\n"));
    const spoofed = brand({ projectRoot: dir });
    assert.equal(spoofed.logo.kind, null);
    assert.ok(spoofed.notices.some((n) => n.kind === "invalid" && /magic bytes/.test(n.text)));

    for (const badPath of ["../escape.png", "/etc/passwd", "~/logo.png"]) {
      writeFileSync(join(dir, TEAM), ["branding:", "  logo:", `    file: ${JSON.stringify(badPath)}`, ""].join("\n"));
      const escaped = brand({ projectRoot: dir });
      assert.equal(escaped.logo.kind, null, badPath);
      assert.ok(escaped.notices.some((n) => n.kind === "invalid"), badPath);
    }

    if (process.platform !== "win32") {
      const outside = tempDir("view-settings-outside-");
      writeFileSync(join(outside, "ext.png"), PNG_BYTES);
      execFileSync("ln", ["-s", join(outside, "ext.png"), join(dir, "docs/brand/link.png")]);
      writeFileSync(join(dir, TEAM), ["branding:", "  logo:", "    file: \"docs/brand/link.png\"", ""].join("\n"));
      const linked = brand({ projectRoot: dir });
      assert.equal(linked.logo.kind, null);
      assert.ok(linked.notices.some((n) => n.kind === "invalid" && /symlink/.test(n.text)));
    }
  });

  test("refuses both logo.svg and logo.file in one layer without dropping a lower layer's logo", () => {
    const { dir } = repo(
      {
        [TEAM]: [["branding:", "  logo:", `    svg: ${JSON.stringify(VALID_SVG)}`, ""].join("\n"), true],
        [PERSONAL]: [
          ["branding:", "  logo:", `    svg: ${JSON.stringify(VALID_SVG)}`, '    file: "docs/brand/logo.png"', '    label: "Keep Label"', ""].join("\n"),
          false,
        ],
      },
      ["*.local.yaml"],
    );
    const res = brand({ projectRoot: dir });
    assert.equal(res.logo.kind, "svg");
    assert.equal(res.sources["logo.graphic"], "team");
    assert.equal(res.logo.label, "Keep Label");
    assert.equal(res.sources["logo.label"], "personal override");
    assert.ok(res.notices.some((n) => n.kind === "invalid" && /both svg and file/.test(n.text)));
  });

  test("embeds WOFF2, WOFF, TTF and OTF font files via magic bytes and refuses spoofed fonts", () => {
    const cases = [
      ["a.woff2", WOFF2_BYTES, "font/woff2", "woff2"],
      ["b.woff", WOFF_BYTES, "font/woff", "woff"],
      ["c.ttf", TTF_BYTES, "font/ttf", "truetype"],
      ["d.ttf", TTF_TRUE_BYTES, "font/ttf", "truetype"],
      ["e.otf", OTF_BYTES, "font/otf", "opentype"],
    ];
    const { dir } = repo();
    mkdirSync(join(dir, "docs/fonts"), { recursive: true });
    for (const [name, bytes] of cases) writeFileSync(join(dir, "docs/fonts", name), bytes);
    writeFileSync(join(dir, "docs/fonts/spoof.woff2"), PNG_BYTES);
    mkdirSync(join(dir, "docs/conventions"), { recursive: true });
    writeFileSync(
      join(dir, TEAM),
      [
        "branding:",
        "  type:",
        "    fonts:",
        ...cases.flatMap(([name], i) => [`      - family: "Brand ${i}"`, `        file: "docs/fonts/${name}"`, "        weight: 600", "        style: italic"]),
        '      - family: "Spoof"',
        '        file: "docs/fonts/spoof.woff2"',
        "",
      ].join("\n"),
    );
    const res = brand({ projectRoot: dir });
    assert.equal(res.type.fonts.length, cases.length);
    cases.forEach(([, bytes, mediaType, format], i) => {
      assert.equal(res.type.fonts[i].family, `Brand ${i}`);
      assert.equal(res.type.fonts[i].mediaType, mediaType);
      assert.equal(res.type.fonts[i].format, format);
      assert.equal(res.type.fonts[i].weight, "600");
      assert.equal(res.type.fonts[i].style, "italic");
      assert.equal(res.type.fonts[i].dataUrl, `data:${mediaType};base64,${bytes.toString("base64")}`);
    });
    assert.equal(res.notices.length, 1);
    assert.match(res.notices[0].text, /magic bytes/);
    assert.equal(styleRefused(res.css), false, res.css);
  });

  test("userConfig handles invalid JSON, non-object JSON, unknown keys, reserved keys and home-relative files", () => {
    const home = userHome();
    mkdirSync(join(home, "brand"), { recursive: true });
    writeFileSync(join(home, "brand/logo.png"), PNG_BYTES);
    const ok = brand({ userConfig: JSON.stringify({ logo: { file: "~/brand/logo.png", label: "Home" } }) }, { userHome: home });
    assert.deepEqual(ok.notices, []);
    assert.equal(ok.logo.mediaType, "image/png");

    const badJson = brand({ userConfig: "{not json" });
    assert.ok(badJson.notices.some((n) => n.kind === "invalid" && /invalid JSON/.test(n.text)));
    const nonObj = brand({ userConfig: "[]" });
    assert.ok(nonObj.notices.some((n) => n.kind === "invalid" && /expected a JSON object/.test(n.text)));
    const reserved = brand({ userConfig: '{"__proto__":{"x":1},"unknown":1,"palette":{"light":{"accent":"#2563EB"}}}' });
    assert.equal(reserved.palette.light.accent, "#2563EB");
    assert.equal(reserved.notices.filter((n) => n.kind === "invalid").length, 2);
    const badLabel = brand({ userConfig: JSON.stringify({ logo: { label: "Bad\u202eBidi" } }) });
    assert.equal(badLabel.logo.label, null);
    assert.ok(badLabel.notices.some((n) => n.kind === "invalid" && /branding\.logo\.label/.test(n.text)));
  });
});

describe("branding --team-ref reads config and team assets from the named commit", () => {
  test("reads branding values and logo/font blobs from the commit, ignoring working-tree edits", () => {
    const { dir, git, commit } = repo({
      [TEAM]: [
        [
          "branding:",
          "  palette:",
          "    light:",
          '      accent: "#1D4ED8"',
          "  type:",
          "    fonts:",
          '      - family: "Committed Font"',
          '        file: "docs/brand/font.woff2"',
          "  logo:",
          '    file: "docs/brand/logo.png"',
          '    label: "Committed"',
          "",
        ].join("\n"),
        true,
      ],
    });
    mkdirSync(join(dir, "docs/brand"), { recursive: true });
    writeFileSync(join(dir, "docs/brand/logo.png"), PNG_BYTES);
    writeFileSync(join(dir, "docs/brand/font.woff2"), WOFF2_BYTES);
    git("add", "-f", "--", "docs/brand/logo.png", "docs/brand/font.woff2");
    commit();
    const base = git("rev-parse", "HEAD").trim();

    writeFileSync(join(dir, TEAM), ["branding:", "  palette:", "    light:", "      accent: \"#DC2626\"", "  logo:", "    label: \"Dirty\"", ""].join("\n"));
    writeFileSync(join(dir, "docs/brand/logo.png"), JPEG_BYTES);

    const atRef = brand({ projectRoot: dir, teamRef: base });
    assert.deepEqual(atRef.notices, []);
    assert.equal(atRef.palette.light.accent, "#1D4ED8");
    assert.equal(atRef.logo.mediaType, "image/png");
    assert.equal(atRef.logo.label, "Committed");
    assert.equal(atRef.type.fonts[0].mediaType, "font/woff2");

    const atWork = brand({ projectRoot: dir });
    assert.equal(atWork.palette.light.accent, "#DC2626");
    assert.equal(atWork.logo.label, "Dirty");

    const badRef = brand({ projectRoot: dir, teamRef: "no-such-ref" });
    assert.equal(badRef.palette.light.accent, SHIPPED_TOKENS.palette.light.accent);
    assert.ok(badRef.notices.some((n) => n.kind === "team-ref"));
  });

  test("refuses a symlinked asset committed at --team-ref", { skip: process.platform === "win32" && "symlinks need a privilege on Windows" }, () => {
    const { dir, git, commit } = repo({
      [TEAM]: [["branding:", "  logo:", '    file: "docs/brand/sym.png"', ""].join("\n"), true],
    });
    mkdirSync(join(dir, "docs/brand"), { recursive: true });
    writeFileSync(join(dir, "docs/brand/real.png"), PNG_BYTES);
    execFileSync("ln", ["-s", "real.png", join(dir, "docs/brand/sym.png")]);
    git("add", "-f", "--", "docs/brand/real.png", "docs/brand/sym.png");
    commit();
    const base = git("rev-parse", "HEAD").trim();
    const res = brand({ projectRoot: dir, teamRef: base });
    assert.equal(res.logo.kind, null);
    assert.ok(res.notices.some((n) => n.kind === "invalid" && /symlink/.test(n.text)));
  });
});

describe("branding WCAG 2.1 contrast floor in both schemes", () => {
  test("contrastRatio computes exact WCAG 2.1 ratios", () => {
    assert.equal(Number(contrastRatio("#000000", "#FFFFFF").toFixed(2)), 21);
    assert.equal(Number(contrastRatio("#A0512E", "#FAF9F5").toFixed(2)), 5.37);
    assert.equal(Number(contrastRatio("#E89B7E", "#3D3D3A").toFixed(2)), 4.89);
  });

  test("drops low-contrast fg, muted, link (< 4.5:1) and focus (< 3:1) in both schemes, naming role, scheme, pair and ratio", () => {
    const lightFail = brand({
      userConfig: JSON.stringify({
        palette: {
          light: { fg: "#CCCCCC", muted: "#AAAAAA", link: "#D97757", focus: "#E3DACC", accent: "#0066CC" },
          dark: { fg: "#222222", muted: "#444444", link: "#555555", focus: "#4A4A47", accent: "#38BDF8" },
        },
      }),
    });
    for (const scheme of ["light", "dark"]) {
      for (const role of ["fg", "muted", "link", "focus"]) {
        assert.equal(lightFail.palette[scheme][role], SHIPPED_TOKENS.palette[scheme][role], `${scheme}.${role}`);
        assert.equal(lightFail.sources[`palette.${scheme}.${role}`], "default");
        const notice = lightFail.notices.find((n) => n.kind === "contrast" && n.scheme === scheme && n.role === role);
        assert.ok(notice, `missing contrast notice for ${scheme}.${role}`);
        assert.match(notice.text, new RegExp(`${scheme} ${role}: pair ${role} on (?:bg|panel) has contrast \\d+\\.\\d{2}:1`));
      }
    }
    assert.equal(lightFail.palette.light.accent, "#0066CC");
    assert.equal(lightFail.palette.dark.accent, "#38BDF8");
  });

  test("enforces 3:1 on focus while enforcing 4.5:1 on link (3.5:1 color passes focus and fails link)", () => {
    const mid = "#87867F";
    const res = brand({ userConfig: JSON.stringify({ palette: { light: { focus: mid, link: mid } } }) });
    assert.equal(res.palette.light.focus, mid);
    assert.equal(res.sources["palette.light.focus"], "userConfig");
    assert.equal(res.palette.light.link, SHIPPED_TOKENS.palette.light.link);
    assert.equal(res.sources["palette.light.link"], "default");
    assert.ok(res.notices.some((n) => n.kind === "contrast" && n.role === "link" && n.scheme === "light"));
  });

  test("drops bad dark foreground without dropping valid dark bg/panel, and accepts full high-contrast light bg+muted pair", () => {
    const dark = brand({
      userConfig: JSON.stringify({
        palette: { dark: { bg: "#0B0D12", panel: "#1A1D24", muted: "#222222" } },
      }),
    });
    assert.equal(dark.palette.dark.bg, "#0B0D12");
    assert.equal(dark.palette.dark.panel, "#1A1D24");
    assert.equal(dark.palette.dark.muted, SHIPPED_TOKENS.palette.dark.muted);
    assert.equal(dark.notices.length, 1);

    const lightPair = brand({
      userConfig: JSON.stringify({
        palette: { light: { bg: "#FFFFFF", panel: "#F8FAFC", muted: "#595954" } },
      }),
    });
    assert.deepEqual(lightPair.notices, []);
    assert.equal(lightPair.palette.light.bg, "#FFFFFF");
    assert.equal(lightPair.palette.light.panel, "#F8FAFC");
    assert.equal(lightPair.palette.light.muted, "#595954");

    const lightBgOnly = brand({ userConfig: JSON.stringify({ palette: { light: { bg: "#FFFFFF" } } }) });
    assert.equal(lightBgOnly.palette.light.bg, SHIPPED_TOKENS.palette.light.bg);
    assert.ok(lightBgOnly.notices.some((n) => n.kind === "contrast" && n.role === "bg" && n.pair === "muted on bg"));
  });
});

describe("branding CLI", () => {
  const run = (args, env = {}) => spawnSync(process.execPath, [CLI, ...args], { encoding: "utf8", env: { ...process.env, HOME: EMPTY_HOME, USERPROFILE: EMPTY_HOME, CI: "", CLAUDE_PLUGIN_DATA: "", ...env } });

  test("branding subcommand prints JSON and layer attribution lines", () => {
    const { dir } = repo({ [TEAM]: [["branding:", "  palette:", "    light:", '      accent: "#1D4ED8"', ""].join("\n"), true] });
    const out = run(["branding"], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(out.status, 0, out.stderr);
    const [json, ...lines] = out.stdout.trimEnd().split("\n");
    const parsed = JSON.parse(json);
    assert.equal(parsed.palette.light.accent, "#1D4ED8");
    assert.equal(parsed.sources["palette.light.accent"], "team");
    assert.deepEqual(lines, ["branding: palette.light.accent (team)"]);
  });

  test("resolve --branding-option includes branding and deduplicates shared notices", () => {
    const { dir, commit } = repo({ [TEAM]: [["medium: file", "branding:", "  palette:", "    light:", '      accent: "#1D4ED8"', ""].join("\n"), true] });
    commit();
    const out = run(["resolve", "--producer", "planning", "--option", "auto", "--branding-option", "", "--team-ref", "no-such-ref"], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(out.status, 0, out.stderr);
    const [json, ...lines] = out.stdout.trimEnd().split("\n");
    const parsed = JSON.parse(json);
    assert.equal(parsed.medium, "artifact");
    assert.equal(parsed.branding.palette.light.accent, SHIPPED_TOKENS.palette.light.accent);
    assert.equal(lines.filter((l) => l.includes("no-such-ref")).length, 1);
  });

  test("every registered copy resolves branding cleanly", () => {
    const manifest = readFileSync(join(HERE, "..", "scripts", "shared-copies.txt"), "utf8");
    const copies = [...manifest.matchAll(/^lib\/view-settings\.mjs (\S+)$/gm)].map(([, copy]) => copy);
    assert.ok(copies.length > 0, "no view-settings copy registered");
    for (const copy of copies) {
      const out = spawnSync(process.execPath, [join(HERE, "..", copy), "branding"], { encoding: "utf8", env: { ...process.env, HOME: EMPTY_HOME, USERPROFILE: EMPTY_HOME, CI: "", CLAUDE_PROJECT_DIR: EMPTY_HOME } });
      assert.equal(out.status, 0, `${copy}: ${out.stderr}`);
      assert.equal(out.stdout.split("\n")[1], "branding: default (shipped tokens)", copy);
    }
  });
});
