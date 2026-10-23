// The lanes token broker (azure-iac src/lanes-token-broker) loads resolve.mjs
// from this repository's main tip, whichever repository calls: its
// resolve-config-loader.mjs walks the sibling modules resolve.mjs imports with
// the `relative_import` pattern, imports them beside a node_modules holding only
// its own `packages`, and calls only loadConfig and resolveGrant on the
// trust-root files binding.mjs reads from the caller's main tip (TRUST_FILES); its tests read the `test_files` list instead. A module the
// pattern misses, a file read beside a module, a package the broker does not
// provide, or a file loadConfig needs that TRUST_FILES lacks fails every
// broker request. fixtures/broker-vendored-lists.json copies those lists from
// the commit it names; the azure-iac pull request that changes them updates it.
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { posix } from "node:path";
import { test } from "node:test";

import { loadConfig, resolveGrant } from "./resolve.mjs";

const here = (relative) => new URL(relative, import.meta.url);
const read = (relative) => readFileSync(here(relative), "utf8");
const LISTS = JSON.parse(read("./fixtures/broker-vendored-lists.json"));

// Relative modules a module imports, and files it reads beside itself through
// new URL(..., import.meta.url), as paths relative to this directory; bare
// specifiers, which resolve through package.json.
function references(name) {
  const text = read(`./${name}`);
  const specifiers = [
    ...text.matchAll(/^\s*(?:import|export)\s[^;]*?from\s+["']([^"']+)["']/gms),
    ...text.matchAll(/^\s*import\s+["']([^"']+)["']/gm),
    ...text.matchAll(/\bimport\(\s*["']([^"']+)["']\s*\)/g),
  ].map((match) => match[1]);
  const reads = [...text.matchAll(/new URL\(\s*["'](\.[^"']+)["']\s*,\s*import\.meta\.url\s*\)/g)].map((match) => match[1]);
  const local = (specifier) => posix.normalize(posix.join(posix.dirname(name), specifier));
  return {
    local: [...specifiers.filter((s) => s.startsWith(".")), ...reads].map(local),
    bare: specifiers.filter((s) => !s.startsWith(".") && !s.startsWith("node:")),
  };
}

// Every file resolve.mjs loads, itself included, and the packages they import.
function closure() {
  const files = new Set();
  const packages = new Set();
  const visit = (name) => {
    if (files.has(name)) {
      return;
    }
    files.add(name);
    const { local, bare } = references(name);
    for (const specifier of bare) {
      packages.add(specifier.startsWith("@") ? specifier.split("/").slice(0, 2).join("/") : specifier.split("/")[0]);
    }
    for (const file of local) {
      if (file.endsWith(".mjs") || file.endsWith(".js")) {
        visit(file);
      } else {
        files.add(file);
      }
    }
  };
  visit("resolve.mjs");
  return { files: [...files], packages: [...packages] };
}

const ROOT = "../../../";
const fileAt = (path) => (path.endsWith(".json") ? JSON.parse(read(`${ROOT}${path}`)) : read(`${ROOT}${path}`));

// What the broker passes: the config and each TRUST_FILES entry, read from this tree.
const brokerFiles = () => ({
  config: read(`${ROOT}${LISTS.binding.config}`),
  ...Object.fromEntries(Object.entries(LISTS.binding.trust_files).map(([key, path]) => [key, fileAt(path)])),
});

test("the copied lists name the azure-iac files and the commit they were read from", () => {
  assert.equal(LISTS.repository, "melodic-software/azure-iac");
  assert.match(LISTS.commit, /^[0-9a-f]{40}$/);
  assert.equal(LISTS.fetch.path, "scripts/deploy/fetch-resolve-config.sh");
  assert.equal(LISTS.loader.path, "src/lanes-token-broker/src/resolve-config-loader.mjs");
  assert.equal(LISTS.loader.entry, "resolve.mjs");
  assert.deepEqual(LISTS.calls.exports, ["loadConfig", "resolveGrant"]);
});

// The modules the broker's loader reaches from resolve.mjs with its pattern.
function loaderClosure() {
  const pattern = new RegExp(LISTS.loader.relative_import, "g");
  const seen = new Set();
  const queue = [LISTS.loader.entry];
  while (queue.length > 0) {
    const name = queue.shift();
    if (!seen.has(name)) {
      seen.add(name);
      queue.push(...[...read(`./${name}`).matchAll(pattern)].map((match) => match[1]));
    }
  }
  return [...seen].sort();
}

test("the broker's loader reaches every file resolve.mjs loads, and each is a sibling module", () => {
  const files = closure().files.sort();
  assert.deepEqual(files.filter((file) => !/^[A-Za-z0-9_.-]+\.mjs$/.test(file)), [], "the broker loads only sibling .mjs modules");
  assert.deepEqual(loaderClosure(), files, "resolve-config-loader.mjs's import pattern must reach every module resolve.mjs loads");
});

test("every package resolve.mjs loads is one the broker provides and package.json names", () => {
  const { dependencies = {} } = JSON.parse(read("./package.json"));
  const { packages } = closure();
  assert.deepEqual(packages.filter((name) => !LISTS.loader.packages.includes(name)), [], "the broker's loader links only its own ajv and yaml");
  assert.deepEqual(packages.filter((name) => !Object.hasOwn(dependencies, name)), [], "package.json dependencies must name every package");
});

test("the broker's calls resolve this tree's config from the TRUST_FILES it reads, and nothing more", () => {
  const files = brokerFiles();
  const doc = loadConfig(files, { configPath: LISTS.binding.config });
  assert.deepEqual(resolveGrant(files, { lane: "pr-unblock", activity: "apply-patch", configPath: LISTS.binding.config }).effect, "mutate-branch");
  assert.ok(Object.keys(doc.lanes).length > 0);
});

// Every file a lane run hands resolve.mjs (resolve-config.mjs filesUnderBase),
// as read from this tree, whatever the fixture lists.
const TREE_FILES = Object.freeze({
  schema: "docs/conventions/pr-pipeline/pr-pipeline.schema.json",
  vocabulary: ".github/standards/github-actions-conventions/vocabulary.json",
  codeowners: ".github/CODEOWNERS",
  trustedActors: ".github/standards/trusted-actors/trusted-actors.json",
  laneRules: ".github/actions/resolve-config/lane-rules.json",
  effectGrants: ".github/actions/resolve-config/effect-grants.json",
  activityRules: ".github/actions/resolve-config/activity-rules.json",
  patchRules: ".github/actions/resolve-config/patch-rules.json",
  patchRulesSchema: ".github/actions/resolve-config/patch-rules.schema.json",
});

// Each key loadConfig cannot do without, found by leaving it out of the full set.
const neededKeys = () => {
  const all = {
    config: read(`${ROOT}${LISTS.binding.config}`),
    ...Object.fromEntries(Object.entries(TREE_FILES).map(([key, path]) => [key, fileAt(path)])),
  };
  loadConfig(all, { configPath: LISTS.binding.config });
  return Object.keys(all).filter((key) => {
    const { [key]: _dropped, ...rest } = all;
    try {
      loadConfig(rest, { configPath: LISTS.binding.config });
      return false;
    } catch {
      return true;
    }
  });
};

// What the broker would lack: each needed key its TRUST_FILES does not list,
// and each needed file its tests are not served.
function brokerGaps(needed, { trust_files: trustFiles, test_data: testData }, testFiles) {
  return needed
    .filter((key) => key !== "config")
    .flatMap((key) => {
      if (!Object.hasOwn(trustFiles, key)) {
        return [`binding.mjs TRUST_FILES must add ${key} (${TREE_FILES[key]}), or every broker request fails`];
      }
      const served = testData[key] ?? trustFiles[key];
      return testFiles.includes(served) ? [] : [`fetch-resolve-config.sh's test_files list must add ${served}`];
    });
}

test("every file loadConfig needs is one the broker reads from main's tip and serves its tests", () => {
  assert.deepEqual(brokerGaps(neededKeys(), LISTS.binding, LISTS.fetch.test_files), []);
});

test("a needed file the broker does not read is named by its key", () => {
  const { activityRules: _dropped, ...trustFiles } = LISTS.binding.trust_files;
  assert.deepEqual(brokerGaps(neededKeys(), { ...LISTS.binding, trust_files: trustFiles }, LISTS.fetch.test_files), [
    "binding.mjs TRUST_FILES must add activityRules (.github/actions/resolve-config/activity-rules.json), or every broker request fails",
  ]);
  const testFiles = LISTS.fetch.test_files.filter((file) => !file.endsWith("lane-rules.json"));
  assert.deepEqual(brokerGaps(neededKeys(), LISTS.binding, testFiles), [
    "fetch-resolve-config.sh's test_files list must add .github/actions/resolve-config/lane-rules.json",
  ]);
});

test("the patch rules are read by lane runs only, never by the broker's loadConfig", () => {
  const needed = neededKeys();
  assert.equal(needed.includes("patchRules") || needed.includes("patchRulesSchema"), false);
});

test("every listed file exists", () => {
  for (const file of [LISTS.loader.entry, ...LISTS.loader.dependency_files]) {
    assert.ok(existsSync(here(`./${file}`)), `the loader names ${file}, which does not exist`);
  }
  for (const file of [...LISTS.fetch.test_files, ...Object.values(LISTS.binding.trust_files)]) {
    assert.ok(existsSync(here(`${ROOT}${file}`)), `the lists name ${file}, which does not exist`);
  }
});
