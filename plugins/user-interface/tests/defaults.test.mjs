import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { resolve } from "../scripts/lib/config-cascade.mjs";
import { parse } from "../scripts/lib/yaml-subset.mjs";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..");
const read = (path) => readFileSync(join(PLUGIN, path), "utf8");
const schema = JSON.parse(read("reference/team.schema.json"));
const defaults = parse(read("reference/defaults.yaml"));

// The layer-1 values the settings schema in the design contract fixes.
const CONTRACT = {
  version: 1,
  css: {
    browser_target: "baseline widely available",
    techniques: { disable: [] },
    rules: { disable: [] },
    important: "avoid",
    layer: null,
    token_fallback: "ask",
  },
};

test("the shipped defaults hold the contract's layer-1 values", () => {
  assert.deepEqual(defaults, CONTRACT);
});

test("the shipped defaults validate against team.schema.json with no error", () => {
  const { values, layers } = resolve({ plugin: "user-interface", projectRoot: PLUGIN, home: "no-such-home", schema, defaults, teamOnly: ["routing"], userHome: join(PLUGIN, "no-such-user") });
  assert.deepEqual(layers[0], { name: "defaults", path: null, state: "loaded", errors: [] });
  assert.deepEqual(values, CONTRACT);
});
