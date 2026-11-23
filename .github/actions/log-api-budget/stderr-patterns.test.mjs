// test-scope: .github/*.bash .github/*.sh .github/*.yml
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { SIGNALS } from "./rate-guard.mjs";

const VECTORS = JSON.parse(readFileSync(new URL("./rate-guard.vectors.json", import.meta.url), "utf8"));
const FAMILIES = VECTORS.stderr_patterns;
const GITHUB_DIR = fileURLToPath(new URL("../..", import.meta.url));
const RELEVANT = /rate limit|RATE_LIMITED|429|was not sent|no call to it|HTTP 5/i;

function* sources(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== "node_modules") yield* sources(path);
    } else if (/\.(?:bash|sh|ya?ml)$/.test(entry.name) && !/\.test\./.test(entry.name)) {
      yield path;
    }
  }
}

const SITES = [...sources(GITHUB_DIR)].flatMap((path) =>
  [...readFileSync(path, "utf8").matchAll(/grep -q(i?)E '([^']*)'/g)]
    .filter(([, , pattern]) => RELEVANT.test(pattern))
    .map(([, i, pattern]) => ({ file: relative(GITHUB_DIR, path), ignoreCase: i === "i", pattern })),
);

const grepMatches = ({ pattern, ignore_case }, text) => {
  const run = spawnSync("grep", [ignore_case ? "-qiE" : "-qE", pattern], { input: text });
  assert.ok(run.status === 0 || run.status === 1, `grep failed on ${pattern}: ${run.stderr}`);
  return run.status === 0;
};

test("every stderr grep under .github for a rate limit, a guard line or a 5xx is one of rate-guard.vectors.json's stderr_patterns, flags included", () => {
  for (const file of ["actions/log-api-budget/api-budget.bash", "scripts/pr-merge/rate-stop.bash", "scripts/pr-unblock/read-pr-head.bash", "workflows/pr-merge.yml", "workflows/pr-require-checks.yml"]) {
    assert.ok(
      SITES.some((site) => site.file === file),
      `no stderr pattern found in ${file}`,
    );
  }
  for (const site of SITES) {
    const family = Object.entries(FAMILIES).find(([, f]) => f.pattern === site.pattern && f.ignore_case === site.ignoreCase);
    assert.ok(family, `${site.file}: '${site.pattern}' (ignore case ${site.ignoreCase}) is no stderr_patterns family; add it and each stderr vector's answer`);
  }
  for (const [name, { pattern }] of Object.entries(FAMILIES)) {
    assert.ok(
      SITES.some((site) => site.pattern === pattern),
      `stderr_patterns.${name} is read by no site`,
    );
  }
});

test("each stderr_patterns family matches exactly the stderr vectors that list it", () => {
  assert.ok(VECTORS.stderr.length > 0);
  const known = new Set([...Object.keys(FAMILIES), "message"]);
  for (const { name, text, matches } of VECTORS.stderr) {
    for (const family of matches) assert.ok(known.has(family), `${name}: unknown family ${family}`);
    for (const [family, spec] of Object.entries(FAMILIES)) {
      assert.equal(grepMatches(spec, text), matches.includes(family), `${name}: ${family}`);
    }
  }
});

test("rate-guard.mjs's SIGNALS read each stderr vector as its message and secondary families say", () => {
  for (const { name, text, matches } of VECTORS.stderr) {
    assert.equal(SIGNALS.message.test(text), matches.includes("message"), `${name}: SIGNALS.message`);
    assert.equal(SIGNALS.secondary.test(text), matches.includes("secondary"), `${name}: SIGNALS.secondary`);
  }
});
