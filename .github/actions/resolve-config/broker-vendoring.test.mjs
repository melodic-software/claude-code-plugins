// The lanes token broker (azure-iac src/lanes-token-broker) imports
// resolve.mjs from the files scripts/deploy/fetch-resolve-config.sh fetches at
// its pinned commit (the `runtime` list), and calls only loadConfig and
// resolveGrant (src/ports.mjs) on the trust-root files binding.mjs reads from
// main's tip (TRUST_FILES); its tests read the `test_files` list instead. A
// module resolve.mjs loads that `runtime` lacks, or a file loadConfig needs
// that TRUST_FILES lacks, fails every broker request.
// fixtures/broker-vendored-lists.json copies those lists from the commit it
// names; the azure-iac pin pull request updates both together.
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
  assert.deepEqual(LISTS.calls.exports, ["loadConfig", "resolveGrant"]);
});

test("every file resolve.mjs loads is on the broker's runtime list", () => {
  const runtime = new Set(LISTS.fetch.runtime);
  const missing = closure().files.filter((file) => !runtime.has(file));
  assert.deepEqual(missing, [], `fetch-resolve-config.sh's runtime list must add ${missing.join(", ")}`);
});

test("every package resolve.mjs loads installs from the vendored package files", () => {
  assert.ok(LISTS.fetch.runtime.includes("package.json") && LISTS.fetch.runtime.includes("package-lock.json"));
  const { dependencies = {} } = JSON.parse(read("./package.json"));
  const missing = closure().packages.filter((name) => !Object.hasOwn(dependencies, name));
  assert.deepEqual(missing, [], `package.json dependencies must name ${missing.join(", ")}`);
});

test("the broker's calls resolve this tree's config from the TRUST_FILES it reads, and nothing more", () => {
  const files = brokerFiles();
  const doc = loadConfig(files, { configPath: LISTS.binding.config });
  assert.deepEqual(resolveGrant(files, { lane: "pr-unblock", activity: "apply-ci-fix", configPath: LISTS.binding.config }).effect, "mutate-branch");
  assert.ok(Object.keys(doc.lanes).length > 0);
});

// Each key loadConfig cannot do without, found by leaving it out.
const neededKeys = () => {
  const all = { ...brokerFiles(), patchRules: JSON.parse(read("./patch-rules.json")), patchRulesSchema: JSON.parse(read("./patch-rules.schema.json")) };
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

test("every file loadConfig needs is one the broker reads from main's tip and serves its tests", () => {
  const testFiles = new Set(LISTS.fetch.test_files);
  for (const key of neededKeys().filter((name) => name !== "config")) {
    const path = LISTS.binding.trust_files[key];
    assert.ok(path, `binding.mjs TRUST_FILES must add ${key}, or every broker request fails`);
    const served = LISTS.binding.test_data[key] ?? path;
    assert.ok(testFiles.has(served), `fetch-resolve-config.sh's test_files list must add ${served}`);
  }
});

test("the patch rules are read by lane runs only, never by the broker's loadConfig", () => {
  const needed = neededKeys();
  assert.equal(needed.includes("patchRules") || needed.includes("patchRulesSchema"), false);
});

test("every listed file exists", () => {
  for (const file of LISTS.fetch.runtime) {
    assert.ok(existsSync(here(`./${file}`)), `runtime names ${file}, which does not exist`);
  }
  for (const file of [...LISTS.fetch.test_files, ...Object.values(LISTS.binding.trust_files)]) {
    assert.ok(existsSync(here(`${ROOT}${file}`)), `the lists name ${file}, which does not exist`);
  }
});
