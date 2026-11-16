import assert from "node:assert/strict";
import { test } from "node:test";
import { PlanError, plan } from "./plan.mjs";

const profile = (name, { plugins = [], optional = [], exclude = [], hideSkills = [] } = {}) => ({
  name,
  description: `${name} profile`,
  plugins: new Set(plugins),
  optional: new Set(optional),
  exclude: new Set(exclude),
  hideSkills: new Set(hideSkills),
});

const NONE = { hooks: false, mod: false, mcp: false, lsp: false };
const installed = (...entries) =>
  new Map(
    entries.map((e) => (typeof e === "string" ? [e, { id: e, dependsOn: [], ships: NONE }] : [e.id, { dependsOn: [], ships: NONE, ...e }])),
  );

const catalog = (alwaysOn, ...profiles) => ({ alwaysOn, profiles: new Map(profiles.map((p) => [p.name, p])) });

const run = ({ always = profile("always-on"), build = profile("build"), inventory, layers = {}, target = "folder" }) =>
  plan({ catalog: catalog(always, build), profile: "build", inventory, layers, target });

test("AC1: the desired set is always-on plus members plus installed optional members, and every other governed plugin is written off", () => {
  const result = run({
    always: profile("always-on", { plugins: ["guard@m"], optional: ["fmt@m", "lint@m"] }),
    build: profile("build", { plugins: ["impl@m"] }),
    inventory: installed("guard@m", "impl@m", "fmt@m", "extra@m"),
  });
  assert.deepEqual(result.writes, { "guard@m": true, "impl@m": true, "fmt@m": true, "extra@m": false });
  assert.deepEqual(result.missing, [{ id: "lint@m", optional: true, install: "claude plugin install lint@m" }]);
});

test("AC1: a member that is not installed is named with its install command and not written", () => {
  const result = run({ build: profile("build", { plugins: ["impl@m", "gone@m"] }), inventory: installed("impl@m") });
  assert.deepEqual(result.writes, { "impl@m": true });
  assert.deepEqual(result.missing, [{ id: "gone@m", optional: false, install: "claude plugin install gone@m" }]);
});

test("AC1: a dependency of a desired plugin is desired too, through every level of dependency", () => {
  const result = run({
    build: profile("build", { plugins: ["impl@m"] }),
    inventory: installed({ id: "impl@m", dependsOn: ["lib@m"] }, { id: "lib@m", dependsOn: ["base@m"] }, "base@m", "other@m"),
  });
  assert.deepEqual(result.writes, { "impl@m": true, "lib@m": true, "base@m": true, "other@m": false });
});

test("AC16: plugins of a marketplace the profile does not name are listed untouched and never written", () => {
  const result = run({ build: profile("build", { plugins: ["impl@m"] }), inventory: installed("impl@m", "third@vendor") });
  assert.deepEqual(result.writes, { "impl@m": true });
  assert.deepEqual(result.untouched, ["third@vendor"]);
});

test("AC17: a plugin the repository enables stays on and unmentioned; one the profile excludes is written off", () => {
  const result = run({
    build: profile("build", { plugins: ["impl@m"], exclude: ["toy@m"] }),
    inventory: installed("impl@m", "repo@m", "toy@m"),
    layers: { project: { enabledPlugins: { "repo@m": true, "toy@m": true } } },
  });
  assert.deepEqual(result.writes, { "impl@m": true, "toy@m": false });
});

test("a committed false wins over a member and is reported", () => {
  const result = run({
    build: profile("build", { plugins: ["impl@m", "held@m"] }),
    inventory: installed("impl@m", "held@m"),
    layers: { project: { enabledPlugins: { "held@m": false } } },
  });
  assert.deepEqual(result.writes, { "impl@m": true });
  assert.deepEqual(result.pinned, [{ id: "held@m", by: "repository", value: false }]);
});

test("AC18: a managed entry pins its plugin, which is reported and left alone", () => {
  const result = run({
    build: profile("build", { plugins: ["impl@m"] }),
    inventory: installed("impl@m", "forced@m"),
    layers: { managed: { enabledPlugins: { "forced@m": true } } },
  });
  assert.deepEqual(result.writes, { "impl@m": true });
  assert.deepEqual(result.pinned, [{ id: "forced@m", by: "managed", value: true }]);
});

test("AC18: for the initial profile the folder's own entries pin their plugins", () => {
  const result = run({
    target: "initial",
    build: profile("build", { plugins: ["impl@m"] }),
    inventory: installed("impl@m", "local@m"),
    layers: { local: { enabledPlugins: { "local@m": true } } },
  });
  assert.deepEqual(result.writes, { "impl@m": true });
  assert.deepEqual(result.pinned, [{ id: "local@m", by: "folder", value: true }]);
});

test("AC18: a folder entry is no pin when the target is the folder itself", () => {
  const result = run({
    build: profile("build", { plugins: ["impl@m"] }),
    inventory: installed("impl@m", "old@m"),
    layers: { local: { enabledPlugins: { "old@m": true } } },
  });
  assert.deepEqual(result.writes, { "impl@m": true, "old@m": false });
  assert.deepEqual(result.pinned, []);
});

test("AC23: hidden skills from always-on and the profile are written as skillOverrides off", () => {
  const result = run({
    always: profile("always-on", { hideSkills: ["legacy"] }),
    build: profile("build", { hideSkills: ["deploy"] }),
    inventory: installed(),
  });
  assert.deepEqual(result.skillWrites, { legacy: "off", deploy: "off" });
});

test("AC24: a profile that excludes an always-on member is rejected", () => {
  assert.throws(
    () =>
      run({
        always: profile("always-on", { plugins: ["guard@m"] }),
        build: profile("build", { exclude: ["guard@m"] }),
        inventory: installed("guard@m"),
      }),
    PlanError,
  );
});

test("an unknown profile name is rejected", () => {
  assert.throws(() => plan({ catalog: catalog(profile("always-on")), profile: "nope", inventory: installed(), layers: {}, target: "folder" }), PlanError);
});

test("enabled and disabled name only the plugins whose effective state changes, with the hook and server plugins among them", () => {
  const result = run({
    build: profile("build", { plugins: ["impl@m", "srv@m", "on@m"] }),
    inventory: installed(
      "impl@m",
      { id: "srv@m", ships: { ...NONE, mcp: true } },
      "on@m",
      { id: "hooky@m", ships: { ...NONE, hooks: true } },
      "idle@m",
    ),
    layers: { user: { enabledPlugins: { "on@m": true, "hooky@m": true } } },
  });
  assert.deepEqual(result.enabled, ["impl@m", "srv@m"]);
  assert.deepEqual(result.disabled, ["hooky@m"]);
  assert.deepEqual(result.mcpOrLspOn, ["srv@m"]);
  assert.deepEqual(result.hookPluginsOff, ["hooky@m"]);
});
