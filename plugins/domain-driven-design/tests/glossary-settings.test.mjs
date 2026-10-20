import { strict as assert } from "node:assert";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..");
const SCRIPT = join(PLUGIN, "scripts/glossary-settings.mjs");
const scratch = mkdtempSync(join(tmpdir(), "ddd-glossary-settings-"));
after(() => rmSync(scratch, { recursive: true, force: true }));
const HOME = join(scratch, "home");
mkdirSync(HOME);

// The defaults the issue fixes: one GLOSSARY.md per context, one GLOSSARY-MAP.md at the root.
const DEFAULTS = { glossary_file: "GLOSSARY.md", glossary_map_file: "GLOSSARY-MAP.md" };
let count = 0;

/** A scratch git repository holding `files` (path to text), so the convention home applies. */
function repo(files = {}, { git = true } = {}) {
  const dir = join(scratch, `repo-${++count}`);
  mkdirSync(dir);
  if (git) assert.equal(spawnSync("git", ["init", "-q", dir]).status, 0);
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  return dir;
}

function settings(args, { userConfig, cwd } = {}) {
  const extra = [];
  if (userConfig) {
    const file = join(scratch, `user-config-${++count}.json`);
    writeFileSync(file, JSON.stringify(userConfig));
    extra.push("--user-config", file);
  }
  const r = spawnSync(process.execPath, [SCRIPT, "--home", HOME, ...args, ...extra], { encoding: "utf8", cwd });
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
}
const layer = (out, name) => out.layers.find((l) => l.name === name);
const TEAM = "docs/conventions/domain-driven-design.yaml";
const LOCAL = "docs/conventions/domain-driven-design.local.yaml";

test("with no layer set, both names are the plugin defaults, reported from layer default", () => {
  const out = settings(["--project", repo()]);
  assert.deepEqual(out.values, DEFAULTS);
  assert.deepEqual(out.provenance, { glossary_file: "default", glossary_map_file: "default" });
  assert.deepEqual(out.layers.map((l) => l.name), ["defaults", "userConfig", "team", "local"]);
});

test("userConfig wins over the default, and an unrendered placeholder counts as unset", () => {
  const out = settings(["--project", repo()], { userConfig: { glossary_file: "TERMS.md", glossary_map_file: "${user_config.glossary_map_file}" } });
  assert.deepEqual(out.values, { glossary_file: "TERMS.md", glossary_map_file: "GLOSSARY-MAP.md" });
  assert.deepEqual(out.provenance, { glossary_file: "userConfig", glossary_map_file: "default" });
});

test("the team file wins over userConfig, and the personal overlay over the team file", () => {
  const dir = repo({ [TEAM]: "glossary_file: TEAM.md\nglossary_map_file: TEAM-MAP.md\n", [LOCAL]: "glossary_map_file: MINE-MAP.md\n" });
  const out = settings(["--project", dir], { userConfig: { glossary_file: "USER.md", glossary_map_file: "USER-MAP.md" } });
  assert.deepEqual(out.values, { glossary_file: "TEAM.md", glossary_map_file: "MINE-MAP.md" });
  assert.deepEqual(out.provenance, { glossary_file: "team", glossary_map_file: "local" });
});

test("a team path is dropped with its file, key and value named, and the default applies, not userConfig", () => {
  const dir = repo({ [TEAM]: "glossary_file: docs/GLOSSARY.md\n" });
  const out = settings(["--project", dir], { userConfig: { glossary_file: "USER.md" } });
  assert.equal(out.values.glossary_file, "GLOSSARY.md");
  assert.equal(out.provenance.glossary_file, "default");
  const team = layer(out, "team");
  assert.equal(team.state, "invalid");
  assert.match(team.errors.join("\n"), /domain-driven-design\.yaml.*"glossary_file": "docs\/GLOSSARY\.md"/);
});

test("an invalid personal value leaves the team value standing", () => {
  const dir = repo({ [TEAM]: "glossary_file: TEAM.md\n", [LOCAL]: "glossary_file: ../GLOSSARY.md\n" });
  const out = settings(["--project", dir]);
  assert.equal(out.values.glossary_file, "TEAM.md");
  assert.equal(out.provenance.glossary_file, "team");
  assert.match(layer(out, "local").errors.join("\n"), /"glossary_file": "\.\.\/GLOSSARY\.md"/);
});

test("an invalid team value is reported even when a valid personal value wins", () => {
  const dir = repo({ [TEAM]: "glossary_file: a\\b.md\n", [LOCAL]: "glossary_file: MINE.md\n" });
  const out = settings(["--project", dir]);
  assert.equal(out.values.glossary_file, "MINE.md");
  assert.equal(layer(out, "team").state, "invalid");
});

test("a userConfig path or dot entry is dropped and named, and the default applies", () => {
  const out = settings(["--project", repo()], { userConfig: { glossary_file: "glossary/GLOSSARY.md", glossary_map_file: ".." } });
  assert.deepEqual(out.values, DEFAULTS);
  const user = layer(out, "userConfig");
  assert.equal(user.state, "invalid");
  assert.equal(user.errors.length, 2);
});

test("a value of the wrong type is dropped by the cascade and the default applies", () => {
  const dir = repo({ [TEAM]: "glossary_file: 42\n" });
  const out = settings(["--project", dir]);
  assert.equal(out.values.glossary_file, "GLOSSARY.md");
  assert.match(layer(out, "team").errors.join("\n"), /glossary_file/);
});

test("outside a git work tree the team and personal files are not read", () => {
  const dir = repo({ [TEAM]: "glossary_file: TEAM.md\n" }, { git: false });
  const out = settings(["--project", dir]);
  assert.equal(out.values.glossary_file, "GLOSSARY.md");
  assert.equal(out.home, null);
  assert.match(out.home_skipped, /not applicable/);
  assert.equal(layer(out, "team").path, null);
});

test("the team file is read from the home the pointer line binds", () => {
  const pointer = "<!-- BEGIN GENERATED: convention-home -->\nTeam conventions live in `conventions`.\n<!-- END GENERATED: convention-home -->\n";
  const dir = repo({ "AGENTS.md": pointer, "conventions/domain-driven-design.yaml": "glossary_map_file: CONTEXTS.md\n" });
  const out = settings(["--project", dir]);
  assert.equal(out.home, "conventions");
  assert.equal(out.values.glossary_map_file, "CONTEXTS.md");
  assert.equal(out.provenance.glossary_map_file, "team");
});

test("without --project, settings anchor at the git root, not the current subdirectory", () => {
  const dir = repo({ [TEAM]: "glossary_file: TEAM.md\n", "src/billing/.keep": "" });
  const out = settings([], { cwd: join(dir, "src/billing") });
  assert.equal(out.values.glossary_file, "TEAM.md");
});
