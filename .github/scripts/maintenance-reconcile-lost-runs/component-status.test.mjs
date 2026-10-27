// Expected values come from the reader's spec: each service's verdict is its
// own component's status, operational or degraded, or unknown when the page or
// component cannot be read; the page's rollup, status.indicator, is never
// read. fixtures/components.json and fixtures/claude-components.json carry the
// component names githubstatus.com and status.claude.com list, trimmed.
// fixtures/npm-install-outage.json is built in the Statuspage summary shape,
// rollup and components together: its page and rollup are the recorded
// npm-status.json (indicator minor), its components the names
// status.npmjs.org lists, with Package installation in major_outage.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { ACTIONS, CLAUDE_CODE, COMPONENTS, NPM_INSTALL, readComponents } from "./component-status.mjs";

const fixture = (name) => JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8"));
const GITHUB = fixture("components.json");
const CLAUDE = fixture("claude-components.json");
const NPM_OUTAGE = fixture("npm-install-outage.json");
const NPM_OK = { ...NPM_OUTAGE, components: NPM_OUTAGE.components.map((c) => ({ ...c, status: "operational" })) };

// A page whose rollup throws when read, so a reader that reads it fails.
const sealed = (page) =>
  Object.defineProperty({ ...page }, "status", {
    enumerable: true,
    get() {
      throw new Error("status.indicator was read");
    },
  });
const withStatus = (page, name, status) => ({ ...page, components: page.components.map((c) => (c.name === name ? { ...c, status } : c)) });

async function read(pages) {
  const urls = [];
  const verdicts = await readComponents({
    fetchStatus: async (url) => {
      urls.push(url);
      const page = pages[url];
      if (page instanceof Error) {
        throw page;
      }
      return page;
    },
  });
  return { urls, byKey: Object.fromEntries(verdicts.map((v) => [v.key, v])), verdicts };
}

const ALL_OK = { [ACTIONS.url]: GITHUB, [NPM_INSTALL.url]: NPM_OK, [CLAUDE_CODE.url]: CLAUDE };

test("a major incident is degraded though the page's rollup reads minor", async () => {
  assert.equal(NPM_OUTAGE.status.indicator, "minor");
  const { byKey } = await read({ ...ALL_OK, [NPM_INSTALL.url]: sealed(NPM_OUTAGE) });
  assert.deepEqual(byKey["npm-install"], {
    key: "npm-install",
    host: "status.npmjs.org",
    component: "Package installation",
    status: "major_outage",
    verdict: "degraded",
    reason: "",
  });
  assert.equal(byKey.actions.verdict, "operational");
  assert.equal(byKey["claude-code"].verdict, "operational");
});

test("an operational component is operational though the page's rollup reads critical", async () => {
  const loud = { ...NPM_OK, status: { indicator: "critical", description: "Major System Outage" } };
  const { byKey } = await read({ ...ALL_OK, [NPM_INSTALL.url]: loud });
  assert.equal(byKey["npm-install"].verdict, "operational");
});

test("each service is read from its own component page, never the rollup", async () => {
  const sealedAll = Object.fromEntries(Object.entries(ALL_OK).map(([url, page]) => [url, sealed(page)]));
  const { urls, verdicts } = await read(sealedAll);
  assert.deepEqual(urls, [
    "https://www.githubstatus.com/api/v2/components.json",
    "https://status.npmjs.org/api/v2/components.json",
    "https://status.claude.com/api/v2/components.json",
  ]);
  assert.deepEqual(
    verdicts.map((v) => [v.host, v.component, v.verdict]),
    [
      ["www.githubstatus.com", "Actions", "operational"],
      ["status.npmjs.org", "Package installation", "operational"],
      ["status.claude.com", "Claude Code", "operational"],
    ],
  );
  assert.equal(COMPONENTS.length, 3);
});

test("any status but operational is degraded", async () => {
  for (const status of ["degraded_performance", "partial_outage", "major_outage", "under_maintenance"]) {
    const { byKey } = await read({ ...ALL_OK, [CLAUDE_CODE.url]: withStatus(CLAUDE, "Claude Code", status), [ACTIONS.url]: withStatus(GITHUB, "Actions", status) });
    assert.equal(byKey["claude-code"].verdict, "degraded", status);
    assert.equal(byKey.actions.verdict, "degraded", status);
  }
});

test("an unreadable page, or one with no such component, is unknown and leaves the others read", async () => {
  const groupOnly = { ...CLAUDE, components: CLAUDE.components.map((c) => (c.name === "Claude Code" ? { ...c, group: true } : c)) };
  for (const page of [new Error("fetch failed"), null, {}, { components: "x" }, groupOnly, withStatus(CLAUDE, "Claude Code", 3)]) {
    const { byKey } = await read({ ...ALL_OK, [CLAUDE_CODE.url]: page });
    assert.equal(byKey["claude-code"].verdict, "unknown");
    assert.equal(byKey["claude-code"].status, null);
    assert.match(byKey["claude-code"].reason, /^status\.claude\.com /);
    assert.equal(byKey.actions.verdict, "operational");
    assert.equal(byKey["npm-install"].verdict, "operational");
  }
});
