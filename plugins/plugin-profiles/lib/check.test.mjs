import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { tempDir, writeTree } from "../tests/temp.mjs";
import { CheckError, checkProfiles, readMarketplace } from "./check.mjs";
import { readProfileFiles } from "./profile-files.mjs";

const M = "melodic-software";
const CATALOG = { name: M, plugins: new Set(["guard", "flow", "plan", "design", "ui", "impl", "toy"]) };
const PASSING = {
  "shipped/always-on.yaml": `description: Every session.\nplugins: [guard@${M}, flow@${M}]\n`,
  "shipped/planning.yaml": `description: Plan.\nplugins: [plan@${M}, design@${M}]\n`,
  "shipped/interface-design.yaml": `description: Plan with screens.\nplugins: [plan@${M}, design@${M}, ui@${M}]\n`,
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
