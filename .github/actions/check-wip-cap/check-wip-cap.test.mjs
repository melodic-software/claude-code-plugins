// Expected values come from the WIP cap rule: work-resolve-issue starts no
// run while the lanes App has limits.wip-cap (60 by default, the base
// pr-pipeline.yaml's value otherwise) or more pull requests open, counted by
// one search; a count that cannot be read never caps.
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { atCap, main, openLanePrs } from "./check-wip-cap.mjs";

const REPO = "melodic-software/claude-code-plugins";
const LIMITS = { "wip-cap": 60 };

// A search that answers `answer`, or throws when it is an Error; it records each path.
function search(answer) {
  const paths = [];
  const github = async (method, path) => {
    paths.push(`${method} ${path}`);
    if (answer instanceof Error) {
      throw answer;
    }
    return answer;
  };
  return { github, paths };
}

test("the count is one search for the lanes App's open pull requests in this repository", async () => {
  const { github, paths } = search({ total_count: 12, items: [] });
  assert.equal(await openLanePrs(github, { repo: REPO }), 12);
  assert.equal(paths.length, 1);
  const url = new URL(paths[0].slice("GET ".length), "https://api.github.com");
  assert.equal(url.pathname, "/search/issues");
  assert.equal(url.searchParams.get("q"), `repo:${REPO} is:pr is:open author:app/melodic-automation-lanes`);
});

test("at the cap or over it caps; under it does not", () => {
  assert.equal(atCap(60, LIMITS), true);
  assert.equal(atCap(61, LIMITS), true);
  assert.equal(atCap(59, LIMITS), false);
  assert.equal(atCap(0, LIMITS), false);
});

test("a search that fails or answers no count reads as unknown, which never caps", async () => {
  for (const answer of [new Error("GET /search/issues failed with status 403"), {}, { total_count: -1 }, { total_count: "60" }, null]) {
    const { github } = search(answer);
    const count = await openLanePrs(github, { repo: REPO });
    assert.equal(count, null, JSON.stringify(answer));
    assert.equal(atCap(count, LIMITS), false);
  }
});

// main against a base checkout with no config, so the default cap of 60
// applies, writing the capped output.
function runMain(answer) {
  const dir = mkdtempSync(join(tmpdir(), "check-wip-cap-"));
  const base = join(dir, "base");
  mkdirSync(base);
  const output = join(dir, "output");
  writeFileSync(output, "");
  const { github } = search(answer);
  return main({ env: { GITHUB_REPOSITORY: REPO, BASE_PATH: base, GITHUB_OUTPUT: output }, github }).then(() =>
    /capped<<\S+\n(true|false)\n/.exec(readFileSync(output, "utf8"))?.[1],
  );
}

test("main writes capped=true at the cap and false under it or on a failed read", async (t) => {
  t.mock.method(console, "log", () => {});
  assert.equal(await runMain({ total_count: 60 }), "true");
  assert.equal(await runMain({ total_count: 59 }), "false");
  assert.equal(await runMain(new Error("GET /search/issues failed with status 502")), "false");
});
