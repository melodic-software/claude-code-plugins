// test-scope: .github/*.bash .github/*.sh .github/workflows/*.yml .github/actions/*/action.yml
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
    } else if ((/\.(?:bash|sh)$/.test(entry.name) && !/\.test\./.test(entry.name)) || (entry.name.endsWith(".yml") && /(?:^|\/)workflows$/.test(dir)) || entry.name === "action.yml") {
      yield path;
    }
  }
}

const GREP = /\bgrep((?:[ \t]+-[A-Za-z]+)+)(?:[ \t]+--)?[ \t]+(?:'([^']*)'|"((?:[^"\\]|\\.)*)"|(\S+))/g;
const EXPANSION = /\$(?:\{[^}]*\}|\([^)]*\)|\w+)|`[^`]*`/g;

function quietGreps(text) {
  return [...text.matchAll(GREP)].flatMap(([raw, options, single, double, bare]) => {
    const letters = options.replace(/[\s-]/g, "");
    if (!/^[qiE]+$/.test(letters) || !letters.includes("q") || !letters.includes("E")) return [];
    const ignoreCase = letters.includes("i");
    if (single !== undefined) return RELEVANT.test(single) ? [{ raw, ignoreCase, pattern: single }] : [];
    const quoted = double ?? bare;
    const literal = quoted.replace(EXPANSION, "");
    if (literal === quoted) {
      const pattern = double === undefined ? quoted : quoted.replace(/\\([$`"\\])/g, "$1");
      return RELEVANT.test(pattern) ? [{ raw, ignoreCase, pattern }] : [];
    }
    return RELEVANT.test(literal) || !/[A-Za-z]/.test(literal) ? [{ raw, ignoreCase, pattern: null }] : [];
  });
}

const SITES = [...sources(GITHUB_DIR)].flatMap((path) => quietGreps(readFileSync(path, "utf8")).map((site) => ({ file: relative(GITHUB_DIR, path), ...site })));

test("quietGreps finds a quiet ERE grep whatever its flag order or quoting, and refuses one whose pattern an expansion hides", () => {
  const found = (line) => quietGreps(line).map(({ ignoreCase, pattern }) => [ignoreCase, pattern]);
  for (const [line, expected] of [
    ["grep -qiE 'rate limit' f", [[true, "rate limit"]]],
    ["grep -Eqi 'rate limit' f", [[true, "rate limit"]]],
    ["grep -iqE 'rate limit' f", [[true, "rate limit"]]],
    ["grep -E -q 'HTTP 429' f", [[false, "HTTP 429"]]],
    ["grep -q -i -E -- \"was not sent: \\\"x\\\"\" f", [[true, 'was not sent: "x"']]],
    ['grep -qE "$pattern" f', [[false, null]]],
    ['grep -qiE "rate limit|$more" f', [[true, null]]],
    ['grep -qE "^#$pr: no verifier hold: " f', []],
    ["grep -qE 'no such thing' f", []],
    ["grep -qvE 'rate limit' f", []],
    ["grep -oE 'rate limit' f", []],
  ]) {
    assert.deepEqual(found(line), expected, line);
  }
});

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
    assert.notEqual(site.pattern, null, `${site.file}: \`${site.raw}\` hides its pattern behind an expansion, so no vector can check it; write it as a literal`);
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
