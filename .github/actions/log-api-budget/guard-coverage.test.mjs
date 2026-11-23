// test-scope: .github/*.mjs
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

function rawFetches(source) {
  const code = source
    .split("\n")
    .filter((line) => !/^\s*(\/\/|\*)/.test(line))
    .join("\n")
    .replace(/\.guard\(\s*(globalThis\.)?fetch\b/g, ".guard(");
  const found = [];
  const sinks = new Set();
  for (const [, name] of code.matchAll(/(?:\.guard|\bretryServerErrors)\(\s*(\w+)/g)) {
    sinks.add(name);
    const body = new RegExp(`function ${name}\\([^)]*\\)\\s*\\{([\\s\\S]*?)\\n\\s*\\}\\n`).exec(code)?.[1] ?? "";
    for (const [, called] of body.matchAll(/(?<![\w.])(\w+)\(/g)) sinks.add(called);
  }
  const intoCreateGitHub = (name) =>
    new RegExp(`\\bcreateGitHub\\(\\{[^)]*\\bfetchImpl${name === "fetchImpl" ? "\\b(?!\\s*:)" : `:\\s*${name}\\b`}`).test(code);
  const defaults = /(\w+)\s*(?<![=!<>]\s*)=\s*(?:globalThis\.)?fetch\b(?!\s*\()/g;
  for (const [, name] of code.matchAll(defaults)) {
    if (!sinks.has(name) && !intoCreateGitHub(name)) found.push(`${name} defaults to the global fetch`);
  }
  const rest = code.replace(defaults, "");
  if (/globalThis\.fetch\b/.test(rest)) found.push("globalThis.fetch");
  const local = /\b(const|let|var)\s+fetch\b|[{,(]\s*fetch\s*[=,})]/.test(code);
  if (!local && /(^|[^\w.$])fetch\(/m.test(rest)) found.push("a global fetch( call");
  if (!local && /\w\s*:\s*fetch\b(?!\s*[(\w])/.test(rest)) found.push("the global fetch passed on");
  return found;
}

test("rawFetches finds a fetch that never reaches the guard however the file imports it, and clears one handed to .guard(), retryServerErrors() or createGitHub", () => {
  const imports = 'import { countRequests, rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";\n';
  for (const [source, expected] of [
    [`${imports}const get = (url) => fetch(url);\n`, ["a global fetch( call"]],
    [`${imports}export function api({ fetch: rawFetch = globalThis.fetch }) {\n  const fetch = countRequests(rawFetch);\n}\n`, ["rawFetch defaults to the global fetch"]],
    [`export function api({ fetch: rawFetch = globalThis.fetch }) {\n  const fetch = retryFetch(rawFetch);\n}\n`, ["rawFetch defaults to the global fetch"]],
    ["export async function main({ fetch = globalThis.fetch } = {}) {\n  return retryApi({ fetch });\n}\n", ["fetch defaults to the global fetch"]],
    ["const api = createGitHubApi({ token, fetch: globalThis.fetch });\n", ["globalThis.fetch"]],
    [`${imports}export function api({ fetch: rawFetch = rateLimitLatch.guard(globalThis.fetch) }) {\n  const fetch = countRequests(rawFetch);\n}\n`, []],
    [`${imports}export function reader({ fetchImpl = fetch, latch = rateLimitLatch }) {\n  const send = latch.guard(fetchImpl);\n}\n`, []],
    ["export function client({ fetchImpl = fetch }) {\n  return createGitHub({ token, fetchImpl, log });\n}\n", []],
    ["export function budgeted({ fetch: rawFetch = globalThis.fetch } = {}) {\n  async function observed(url, init) {\n    return rawFetch(url, init);\n  }\n  const fetch = retryServerErrors(observed, {});\n}\n", []],
  ]) {
    assert.deepEqual(rawFetches(source), expected, source);
  }
});

const CALL = "a global fetch( call";
const UNGUARDED = {
  ".github/scripts/pr-unblock/dependency-classify.mjs": { reason: "package registries, not the API", found: [CALL] },
  ".github/scripts/maintenance-reconcile-lost-runs/component-status.mjs": { reason: "the status pages, not the API", found: [CALL] },
  ".github/scripts/maintenance-monitor-signals/monitor.mjs": { reason: "githubstatus.com reads; its API calls go through lib/github-rest.mjs", found: [CALL] },
  ".github/actions/check-kill-switch/check-kill-switch.mjs": {
    reason: "reads only /rate_limit, which no pool counts (https://docs.github.com/en/rest/rate-limit/rate-limit), to decide the start gate",
    found: ["fetchImpl defaults to the global fetch", "fetchImpl defaults to the global fetch"],
  },
  ".github/scripts/maintenance-reconcile-lost-runs/reset-tick.mjs": {
    reason: "reads only /rate_limit, which no pool counts (https://docs.github.com/en/rest/rate-limit/rate-limit), to pick the tick after the reset",
    found: ["fetchImpl defaults to the global fetch"],
  },
  ".github/scripts/apply-patch/apply-patch.mjs": { reason: "its main runs from a directory copy after the head checkout replaced .base", found: ["globalThis.fetch"] },
  ".github/scripts/pr-unblock/address-feedback.mjs": {
    reason: "createGitHubApi's default fetch is for importers run from a directory copy; its base-checkout mains pass guardedFetch",
    found: ["rawFetch defaults to the global fetch"],
  },
  ".github/scripts/pr-merge/merge-holds.mjs": { reason: "ci-status runs it alone, a single-file copy of the base's", found: [CALL] },
  ".github/scripts/work-resolve-issue/report-outcome.mjs": {
    reason: "main runs from collect-base-activity's directory copy; --find-prior reads through the guard",
    found: ["fetch defaults to the global fetch"],
  },
  ".github/actions/log-api-budget/pace.mjs": {
    reason: "open: the guard would end the step red on a refusal where a failed read is paced=false today, and hold or fail is undecided",
    found: ["fetchImpl defaults to the global fetch"],
  },
};

test("every lane script that reaches GitHub gets its fetch from the rate guard, or is listed with its reason and exactly its raw fetches", () => {
  const root = new URL("../../../", import.meta.url).pathname;
  const files = spawnSync("git", ["-C", root, "ls-files", ".github/*.mjs", ".github/*.js"], { encoding: "utf8" })
    .stdout.split("\n")
    .filter((file) => file && !/\.test\.[cm]?js$/.test(file) && !file.includes("/node_modules/") && !file.includes("/fixtures/") && !file.includes("/probe/"));
  const raw = Object.fromEntries(
    files
      .filter((file) => !file.endsWith("log-api-budget/rate-guard.mjs"))
      .map((file) => [file, rawFetches(readFileSync(join(root, file), "utf8"))])
      .filter(([, found]) => found.length > 0),
  );
  assert.deepEqual(raw, Object.fromEntries(Object.entries(UNGUARDED).map(([file, { found }]) => [file, found])), "a raw fetch a listed file does not name, or a listed one that is gone");
});

test("modules copied without .github/actions load the rate guard only at run time", () => {
  const root = new URL("../../../", import.meta.url).pathname;
  for (const file of [".github/scripts/pr-unblock/address-feedback.mjs"]) {
    const source = readFileSync(join(root, file), "utf8");
    assert.doesNotMatch(source, /^import\s[^;]*["'][^"']*actions\/log-api-budget\//m, `${file} is imported from a copy of its directory alone, so a static import of the rate guard cannot resolve there`);
    assert.match(source, /await import\(["']\.\.\/\.\.\/actions\/log-api-budget\/rate-guard\.mjs["']\)/, `${file} keeps its run-time import of the rate guard`);
  }
});
