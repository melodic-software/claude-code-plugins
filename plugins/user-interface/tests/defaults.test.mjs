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
    concentric_radius: { max_gap_px: 24 },
  },
  animation: {
    easing: {
      out: [0.23, 1, 0.32, 1],
      in_out: [0.77, 0, 0.175, 1],
      drawer: [0.32, 0.72, 0, 1],
    },
    duration_ms: { press: 160, small: 200, medium: 250, large: 500 },
    gesture: { velocity_threshold: 0.11 },
  },
  design: { concern_spoke_cap: 2 },
  components: { primitives_default: "base-ui" },
};

test("the shipped defaults hold the contract's layer-1 values", () => {
  assert.deepEqual(defaults, CONTRACT);
});

test("every css_* userConfig default equals the shipped default it mirrors", () => {
  const userConfig = JSON.parse(read(".claude-plugin/plugin.json")).userConfig;
  const mirrored = Object.entries(userConfig).filter(([key, option]) => key.startsWith("css_") && "default" in option);
  assert.ok(mirrored.length > 0);
  for (const [key, option] of mirrored) assert.equal(option.default, defaults.css[key.slice("css_".length)], key);
});

test("the shipped defaults validate against team.schema.json with no error", () => {
  const { values, layers } = resolve({ plugin: "user-interface", projectRoot: PLUGIN, home: "no-such-home", schema, defaults, teamOnly: ["routing"], userHome: join(PLUGIN, "no-such-user") });
  assert.deepEqual(layers[0], { name: "defaults", path: null, state: "loaded", errors: [], error_keys: [] });
  assert.deepEqual(values, CONTRACT);
});

// Expected values: the cap's contract, an integer of at least 1 with default 2.
test("the concern-spoke cap takes an integer of at least 1 and keeps 2 otherwise", () => {
  const capWith = (raw) => {
    const { values, layers } = resolve({ plugin: "user-interface", projectRoot: PLUGIN, home: "no-such-home", schema, defaults, userConfig: { design_concern_spoke_cap: raw }, teamOnly: ["routing"], userHome: join(PLUGIN, "no-such-user") });
    return { cap: values.design.concern_spoke_cap, error_keys: layers[1].error_keys };
  };
  assert.deepEqual(capWith("3"), { cap: 3, error_keys: [] });
  assert.deepEqual(capWith("1"), { cap: 1, error_keys: [] });
  assert.deepEqual(capWith("0"), { cap: 2, error_keys: ["design.concern_spoke_cap"] });
  assert.deepEqual(capWith("1.5"), { cap: 2, error_keys: ["design.concern_spoke_cap"] });
});

// Expected values: the owner's decision that base-ui is the default, and the setting's three
// library values.
test("the primitives default takes a library key and keeps base-ui otherwise", () => {
  const primitivesWith = (raw) => {
    const { values, layers } = resolve({ plugin: "user-interface", projectRoot: PLUGIN, home: "no-such-home", schema, defaults, userConfig: { components_primitives_default: raw }, teamOnly: ["routing"], userHome: join(PLUGIN, "no-such-user") });
    return { primitives: values.components.primitives_default, error_keys: layers[1].error_keys };
  };
  assert.deepEqual(primitivesWith("radix"), { primitives: "radix", error_keys: [] });
  assert.deepEqual(primitivesWith("react-aria"), { primitives: "react-aria", error_keys: [] });
  assert.deepEqual(primitivesWith("Base UI"), { primitives: "base-ui", error_keys: ["components.primitives_default"] });
  assert.deepEqual(primitivesWith("shadcn"), { primitives: "base-ui", error_keys: ["components.primitives_default"] });
});

// Expected values: the key's contract, an integer of at least 0 with default 24 (the gap past
// which nested surfaces read as independent).
test("the nested-radius gap limit takes an integer of at least 0 and keeps 24 otherwise", () => {
  const gapWith = (raw) => {
    const { values, layers } = resolve({ plugin: "user-interface", projectRoot: PLUGIN, home: "no-such-home", schema, defaults, userConfig: { css_concentric_radius_max_gap_px: raw }, teamOnly: ["routing"], userHome: join(PLUGIN, "no-such-user") });
    return { gap: values.css.concentric_radius.max_gap_px, error_keys: layers[1].error_keys };
  };
  assert.deepEqual(gapWith("30"), { gap: 30, error_keys: [] });
  assert.deepEqual(gapWith("0"), { gap: 0, error_keys: [] });
  assert.deepEqual(gapWith("-1"), { gap: 24, error_keys: ["css.concentric_radius.max_gap_px"] });
  assert.deepEqual(gapWith("1.5"), { gap: 24, error_keys: ["css.concentric_radius.max_gap_px"] });
});
