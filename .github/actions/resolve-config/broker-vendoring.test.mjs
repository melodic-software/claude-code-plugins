// The lanes token broker imports resolve.mjs from the files azure-iac's
// scripts/deploy/fetch-resolve-config.sh fetches at its pinned commit: its
// `runtime` list, and for the broker's tests its `test_files` list, the
// trust-root JSON it serves as the default-branch tip. A module resolve.mjs
// loads that `runtime` lacks fails every broker request; a rule file
// `test_files` lacks leaves the broker's tests reading no copy of it.
// fixtures/broker-vendored-lists.json is a copy of both lists, read from the
// commit it names; `pending` holds what the paired azure-iac pull request
// still has to add, and that pull request moves it into the lists.
import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { posix } from "node:path";
import { test } from "node:test";

const DIR = ".github/actions/resolve-config";
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

const listed = (key) => new Set([...LISTS[key], ...LISTS.pending[key]]);

test("the copied lists name the azure-iac file and the commit they were read from", () => {
  assert.equal(LISTS.repository, "melodic-software/azure-iac");
  assert.equal(LISTS.path, "scripts/deploy/fetch-resolve-config.sh");
  assert.match(LISTS.commit, /^[0-9a-f]{40}$/);
});

test("every file resolve.mjs loads is on the broker's runtime list", () => {
  const runtime = listed("runtime");
  const missing = closure().files.filter((file) => !runtime.has(file));
  assert.deepEqual(missing, [], `fetch-resolve-config.sh's runtime list must add ${missing.join(", ")}`);
});

test("every package resolve.mjs loads installs from the vendored package files", () => {
  const runtime = listed("runtime");
  assert.ok(runtime.has("package.json") && runtime.has("package-lock.json"));
  const { dependencies = {} } = JSON.parse(read("./package.json"));
  const missing = closure().packages.filter((name) => !Object.hasOwn(dependencies, name));
  assert.deepEqual(missing, [], `package.json dependencies must name ${missing.join(", ")}`);
});

test("every trust-root rule file and the convention schema are on the broker's test_files list", () => {
  const ownJson = readdirSync(here("./"), { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".json") && !entry.name.startsWith("package"))
    .map((entry) => `${DIR}/${entry.name}`);
  const shell = read("./resolve-config.mjs");
  const readOwn = [...shell.matchAll(/readOwn\(\s*["']\.\/([^"']+)["']\s*\)/g)].map((match) => `${DIR}/${match[1]}`);
  const schema = shell.match(/const SCHEMA_PATH = ["']([^"']+)["']/)[1];
  const testFiles = listed("test_files");
  const missing = [...new Set([...ownJson, ...readOwn, schema])].filter((file) => !testFiles.has(file));
  assert.deepEqual(missing, [], `fetch-resolve-config.sh's test_files list must add ${missing.join(", ")}`);
});

test("every listed and pending file exists, and nothing pending is already listed", () => {
  for (const key of ["runtime", "test_files"]) {
    for (const file of [...LISTS[key], ...LISTS.pending[key]]) {
      const path = key === "runtime" ? `./${file}` : `../../../${file}`;
      assert.ok(existsSync(here(path)), `${key} names ${file}, which does not exist`);
    }
    const both = LISTS.pending[key].filter((file) => LISTS[key].includes(file));
    assert.deepEqual(both, [], `${key}: move ${both.join(", ")} out of pending once the pin pull request lists it`);
  }
});
