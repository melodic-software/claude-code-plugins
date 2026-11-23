import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { tempDir, writeTree } from "../tests/temp.mjs";
import { CheckError, checkProfiles, readMarketplace } from "./check.mjs";
import { readProfileFiles } from "./profile-files.mjs";
import { readSkillLinks, readTreePlugins } from "./skill-links.mjs";

const M = "melodic-software";
const CATALOG = { name: M, plugins: new Set(["guard", "flow", "plan", "design", "ui", "impl", "toy"]) };
const PASSING = {
  "shipped/always-on.yaml": `description: Every session.\nplugins: [flow@${M}, guard@${M}]\n`,
  "shipped/planning.yaml": `description: Plan.\nplugins: [design@${M}, plan@${M}]\n`,
  "shipped/interface-design.yaml": `description: Plan with screens.\nplugins: [design@${M}, plan@${M}, ui@${M}]\n`,
  "shipped/build.yaml": `description: Build.\nplugins: [impl@${M}]\nexclude: [toy@${M}]\n`,
};

function run(files, { installed = [] } = {}) {
  const root = writeTree(tempDir(), { ...PASSING, ...files });
  const levels = ["shipped", "user", "repository"].map((level) => ({ level, dir: join(root, level) }));
  return checkProfiles({ files: readProfileFiles(levels), catalog: CATALOG, installed: new Set(installed) });
}

test("AC5: shipped profiles that name only catalogued plugins of the catalog's marketplace pass", () => {
  assert.deepEqual(run({}), { failures: [], reports: [] });
});

test("tree links use profile membership, report each kind, and leave failures unchanged", () => {
  const root = writeTree(tempDir(), {
    ...PASSING,
    "shipped/build.yaml": `description: Build.\nplugins: [impl@${M}]\noptional: [ui@${M}]\nexclude: [toy@${M}]\nhide_skills: [hidden, local]\n`,
    "shipped/native.yaml": `description: Bare.\nalways_on: false\nplugins: [impl@${M}]\nexclude: [guard@${M}]\n`,
    "plugins/impl/.claude-plugin/plugin.json": { dependencies: ["design", "toy"] },
    "plugins/design/.claude-plugin/plugin.json": { dependencies: [{ name: `plan@${M}` }] },
    "plugins/impl/skills/start/SKILL.md": [
      "## Next", "/design:go /plan:go /ui:go /guard:go /toy:go /flow:hidden /gone:go /impl:local.",
      "````md", "## Related", "/bad:fenced", "```", "/bad:still-fenced", "````",
      "~~~", "/bad:tilde", "~~~", "## Other", "/bad:other", "## Related", "/toy:go",
    ].join("\n"),
    "plugins/impl/skills/local/SKILL.md": "",
    "plugins/design/skills/go/SKILL.md": "",
    "plugins/plan/skills/go/SKILL.md": "",
    "plugins/ui/skills/go/SKILL.md": "",
    "plugins/guard/skills/go/SKILL.md": "",
    "plugins/flow/skills/hidden/SKILL.md": "",
    "plugins/toy/skills/go/SKILL.md": "",
    "plugins/off/skills/start/SKILL.md": "## Next\n/gone:off\n",
  });
  const files = readProfileFiles([{ level: "shipped", dir: join(root, "shipped") }]);
  const plugins = readTreePlugins(join(root, "plugins"), M);
  const source = join(root, "plugins", "impl", "skills", "start", "SKILL.md");
  const inputs = { files, catalog: CATALOG, installed: new Set() };
  const skills = readSkillLinks(plugins, { tree: true, changed: new Set([join(root, "shipped", "native.yaml")]) });
  const { links, failures, unresolved, unnamed, skillReports } = checkProfiles({ ...inputs, skills });
  assert.deepEqual(failures, checkProfiles(inputs).failures);
  assert.deepEqual(failures, []);
  const next = (target, profile) => `links.next: ${source} -> /${target} is off in profile ${profile}`;
  assert.deepEqual(links.next, [
    next("ui:go", "native"), next("guard:go", "native"), next("flow:hidden", "native"),
    next("toy:go", "build"), next("flow:hidden", "build"), next("impl:local", "build"),
  ]);
  assert.deepEqual(links.related, [`links.related: ${source} -> /toy:go is off in profile build`]);
  const offSource = join(root, "plugins", "off", "skills", "start", "SKILL.md");
  assert.deepEqual(unresolved, [
    `links.unresolved: ${source} (links.next) -> /gone:go has no skill`,
    `links.unresolved: ${offSource} (links.next) -> /gone:off has no skill`,
  ]);
  assert.deepEqual(unnamed, [`Catalog plugin no shipped profile names: toy@${M}`]);
  assert.deepEqual(skillReports.changed, [...links.next.slice(0, 3), unresolved[0]]);
});

test("links to another marketplace's plugin, to a changed target, and from an unreadable skill", () => {
  const root = writeTree(tempDir(), {
    ...PASSING,
    "shipped/build.yaml": `description: Build.\nplugins: [impl@${M}]\n`,
    "plugins/impl/skills/start/SKILL.md": "## Next\n/vendor:go /ui:go /ui:moved\n",
    "plugins/ui/skills/go/SKILL.md": "",
    "plugins/impl/skills/broken/SKILL.md/.keep": "",
    "other/vendor/skills/go/SKILL.md": "",
    "user/vendorish.yaml": "plugins: [vendor@elsewhere]\n",
  });
  const plugins = new Map([...readTreePlugins(join(root, "plugins"), M), ...readTreePlugins(join(root, "other"), "elsewhere")]);
  const source = join(root, "plugins", "impl", "skills", "start", "SKILL.md");
  const moved = join(root, "plugins", "ui", "skills", "moved", "SKILL.md");
  const files = readProfileFiles([{ level: "shipped", dir: join(root, "shipped") }, { level: "user", dir: join(root, "user") }]);
  const skills = readSkillLinks(plugins, { tree: true, changed: new Set([moved]) });
  const { links, unresolved, unreadable, failures, skillReports } = checkProfiles({ files, catalog: CATALOG, installed: new Set(), skills });
  assert.deepEqual(failures, []);
  assert.deepEqual(links.next, [`links.next: ${source} -> /ui:go is off in profile build`]);
  assert.deepEqual(unresolved, [`links.unresolved: ${source} (links.next) -> /ui:moved has no skill`]);
  assert.match(unreadable[0], /links\.unreadable: .*broken.*SKILL\.md cannot be read \(EISDIR\)/);
  assert.deepEqual(skillReports.changed, unresolved);
});

test("AC5: a shipped profile naming a plugin the catalog lacks fails, naming the profile and the plugin", () => {
  const { failures } = run({ "shipped/build.yaml": `description: Build.\nplugins: [impl@${M}, nope@${M}]\n` });
  assert.equal(failures.length, 1);
  assert.match(failures[0], /build\.yaml.*nope@melodic-software.*not in the catalog/);
});

test("AC5: a shipped id whose marketplace is not the catalog's fails and names the fix", () => {
  const { failures } = run({ "shipped/build.yaml": "description: Build.\nplugins: [impl@melodic]\n" });
  assert.equal(failures.length, 1);
  assert.match(failures[0], /impl@melodic.*write impl@melodic-software/);
});

test("AC5, design round 3: interface-design lacking a planning member fails, naming the member", () => {
  const { failures } = run({ "shipped/interface-design.yaml": `description: Plan with screens.\nplugins: [plan@${M}, ui@${M}]\n` });
  assert.equal(failures.length, 1);
  assert.match(failures[0], /interface-design.*design@melodic-software/);
});

test("AC24: a shipped profile that excludes an always-on member fails", () => {
  const { failures } = run({ "shipped/build.yaml": `description: Build.\nplugins: [impl@${M}]\nexclude: [guard@${M}]\n` });
  assert.equal(failures.length, 1);
  assert.match(failures[0], /build.*excludes always-on member guard@melodic-software/);
});

test("#17038: a shipped profile with always_on false may exclude an always-on member", () => {
  assert.deepEqual(run({ "shipped/native.yaml": `description: Bare.\nalways_on: false\nplugins: [flow@${M}]\nexclude: [guard@${M}]\n` }), { failures: [], reports: [] });
});

test("#17038: a repository always_on false is reported as ignored, not failed", () => {
  const { failures, reports } = run({ "repository/notes.yaml": "always_on: false\n" });
  assert.deepEqual(failures, []);
  assert.ok(reports.some((line) => line.includes("notes.yaml: always_on: false. A repository profile cannot")), reports.join("\n"));
});

test("a shipped list out of alphabetical order fails, naming the first name out of place; a user one passes", () => {
  const { failures } = run({ "shipped/build.yaml": `description: Build.\nplugins: [impl@${M}]\nhide_skills: [zeta, alpha]\n`, "user/build.yaml": `plugins: [toy@${M}, impl@${M}]\n` });
  assert.deepEqual(failures.map((line) => line.replace(/^.*\/shipped\//, "")), ["build.yaml: hide_skills is not in alphabetical order: alpha goes before zeta"]);
});

test("a shipped profile with no description line fails", () => {
  const { failures } = run({ "shipped/build.yaml": `plugins: [impl@${M}]\n` });
  assert.equal(failures.length, 1);
  assert.match(failures[0], /build\.yaml.*description/);
});

test("AC5: installed plugins of a governed marketplace that no profile names are reported, not failed", () => {
  const result = run({}, { installed: [`impl@${M}`, `songs@${M}`, "widget@vendor"] });
  assert.deepEqual(result.failures, []);
  assert.deepEqual(result.reports, [`Installed, and no profile names it (an apply switches it off unless the repository enables it): songs@${M}`]);
});

test("AC5, AC4: a user or repository profile's plugin from another marketplace is checked against the installed list and reported missing", () => {
  const result = run(
    {
      "user/build.yaml": "plugins: [widget@vendor, gadget@vendor]\n",
      "repository/notes.yaml": `plugins: [typo@${M}]\n`,
    },
    { installed: ["widget@vendor"] },
  );
  assert.deepEqual(result.failures, [], "user and repository profiles never fail the check");
  assert.equal(result.reports.length, 2);
  assert.match(result.reports.find((r) => r.includes("gadget")), /gadget@vendor is not installed\. Install it with: claude plugin install gadget@vendor/);
  assert.match(result.reports.find((r) => r.includes("typo")), /typo@melodic-software.*not in the catalog/);
});

test("AC24: a user profile that excludes an always-on member is reported", () => {
  const result = run({ "user/build.yaml": `exclude: [flow@${M}]\n` });
  assert.deepEqual(result.failures, []);
  assert.equal(result.reports.length, 1);
  assert.match(result.reports[0], /build.*excludes always-on member flow@melodic-software/);
});

test("a repository profile's remove or exclude of an always-on member is reported as ignored, not failed", () => {
  const result = run({ "repository/always-on.yaml": `remove: [guard@${M}]\n`, "repository/build.yaml": `exclude: [flow@${M}]\n` });
  assert.deepEqual(result.failures, []);
  assert.equal(result.reports.length, 2, result.reports.join("\n"));
  assert.match(result.reports[0], /^Ignored, from .*always-on\.yaml: remove guard@melodic-software\. A repository profile cannot switch off an always-on member; a user-level profile can\.$/);
  assert.match(result.reports[1], /^Ignored, from .*build\.yaml: exclude flow@melodic-software\./);
});

test("readMarketplace returns the catalog's own name and plugin names, and refuses a file without them", () => {
  const root = writeTree(tempDir(), {
    "good.json": { name: M, plugins: [{ name: "guard" }, { name: "flow" }] },
    "bad.json": { plugins: [] },
  });
  assert.deepEqual(readMarketplace(join(root, "good.json")), { name: M, plugins: new Set(["guard", "flow"]) });
  assert.throws(() => readMarketplace(join(root, "bad.json")), CheckError);
  assert.throws(() => readMarketplace(join(root, "absent.json")), CheckError);
});
