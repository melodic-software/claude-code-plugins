/**
 * Stand-in for the `playwright` package in CLI tests. Without a fixture,
 * chromium.launch rejects so no browser can start. With
 * PLAYWRIGHT_STUB_FIXTURE=<json path>, it returns a scripted browser whose
 * page.evaluate answers from `{ "evaluate": [{ "when": "<substring of the
 * callback source>", "value": <result> }] }`, first match wins; an evaluate
 * no rule matches rejects so a new code path fails loudly.
 */
import { readFileSync } from "node:fs";

function loadRules() {
  const fixture = process.env.PLAYWRIGHT_STUB_FIXTURE;
  if (!fixture) return null;
  return JSON.parse(readFileSync(fixture, "utf8")).evaluate ?? [];
}

function createPage(rules) {
  return {
    goto: async () => null,
    waitForTimeout: async () => {},
    waitForLoadState: async () => {},
    on: () => {},
    close: async () => {},
    evaluate: async (fn) => {
      const source = String(fn);
      const rule = rules.find((r) => source.includes(r.when));
      if (!rule) throw new Error(`playwright stub: no evaluate rule matches ${source.slice(0, 80)}`);
      return rule.value;
    },
  };
}

export const chromium = {
  launch: async () => {
    const rules = loadRules();
    if (!rules) throw new Error("playwright stub: chromium.launch blocked in tests");
    return {
      newContext: async () => ({
        newPage: async () => createPage(rules),
        addCookies: async () => {},
        storageState: async () => ({ cookies: [], origins: [] }),
        close: async () => {},
      }),
      close: async () => {},
    };
  },
};
