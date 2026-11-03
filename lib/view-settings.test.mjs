// The medium resolver: each case is a rule of the medium-resolution contract (the argument decides
// alone; terminal or file from any scope keeps the view local; a publishing value counts only from
// an untracked, gitignored personal override or userConfig; the plugin default applies when no scope
// decides; a team file never publishes; an invalid value is ignored without dropping another scope;
// auto is unset; the retired rendered-views files give notices, never values).
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
    assert.deepEqual(pick(result), { medium: "file", decidedBy: "plugin default" });
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
    assert.deepEqual(pick(result), { medium: "file", decidedBy: "plugin default" });
    assert.ok(result.notices.some((n) => /tracked in git/.test(n.text)));
  });
  test("an untracked personal override that is not gitignored never publishes", () => {
    const { dir } = repo({ [PERSONAL]: ["medium: artifact\n", false] });
    const result = resolve({ projectRoot: dir });
    assert.deepEqual(pick(result), { medium: "file", decidedBy: "plugin default" });
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
    assert.deepEqual(pick(resolve({ projectRoot: dir })), { medium: "file", decidedBy: "plugin default" });
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
    assert.deepEqual(pick(resolve({ argument: "auto", userConfig: "auto" })), { medium: "file", decidedBy: "plugin default" });
    assert.deepEqual(pick(resolve({ userConfig: "${user_config.medium}" })), { medium: "file", decidedBy: "plugin default" });
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
      assert.deepEqual(pick(result), { medium: "file", decidedBy: "plugin default" }, teamRef);
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
    assert.deepEqual(pick(result), { medium: "file", decidedBy: "plugin default" });
    assert.deepEqual(result.notices, []);
  });
});

describe("retired rendered-views files", () => {
  const retired = () => {
    const home = userHome({ ".claude/rendered-views.md": "medium: artifact\n" });
    const project = repo({ ".claude/rendered-views.md": ["medium: hosted\n", true], ".claude/rendered-views.local.md": ["medium: terminal\n", false] });
    return { home, project };
  };
  test("each yields one notice naming its value and where it moves, and is never applied", () => {
    const { home, project } = retired();
    const result = resolve({ lane: "review:explain-change", projectRoot: project.dir }, { userHome: home });
    assert.deepEqual(pick(result), { medium: "artifact", decidedBy: "plugin default" });
    const notices = result.notices.filter((n) => n.kind === "retired").map(({ path, value, destination }) => ({ path, value, destination }));
    assert.deepEqual(notices, [
      { path: "~/.claude/rendered-views.md", value: "artifact", destination: "the review plugin's medium option" },
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
  const run = (args, env = {}, cli = CLI) => spawnSync(process.execPath, [cli, ...args], { encoding: "utf8", env: { ...process.env, HOME: EMPTY_HOME, USERPROFILE: EMPTY_HOME, CI: "", CLAUDE_PLUGIN_DATA: "", ...env } });
  test("team artifact and userConfig file print file and name userConfig; without userConfig, the plugin default", () => {
    const { dir } = repo({ [TEAM]: ["medium: artifact\n", true] });
    const withOption = run(["resolve", "--lane", "planning", "--option", "file"], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(withOption.status, 0, withOption.stderr);
    const [json, ...report] = withOption.stdout.trimEnd().split("\n");
    assert.deepEqual(pick(JSON.parse(json)), { medium: "file", decidedBy: "userConfig" });
    assert.equal(report[0], "view: file (userConfig)");
    const without = run(["resolve", "--lane", "planning", "--option", "${user_config.medium}"], { CLAUDE_PROJECT_DIR: dir });
    assert.equal(without.stdout.split("\n")[1], "view: file (plugin default)");
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
  test("every carrier's own copy imports its sibling modules and resolves", () => {
    for (const plugin of ["architecture", "discovery", "debugging", "adhd", "education", "prototype", "codebase-health", "overengineering", "ai-briefing"]) {
      const cli = join(HERE, "..", "plugins", plugin, "lib", "view-settings.mjs");
      const out = run(["resolve", "--lane", "planning", "--option", ""], { CLAUDE_PROJECT_DIR: EMPTY_HOME }, cli);
      assert.equal(out.status, 0, `${plugin}: ${out.stderr}`);
      assert.equal(out.stdout.split("\n")[1], "view: file (plugin default)", plugin);
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
