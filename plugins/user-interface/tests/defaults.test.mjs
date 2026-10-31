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
      in: [0.3, 0, 1, 1],
      in_out: [0.77, 0, 0.175, 1],
      drawer: [0.32, 0.72, 0, 1],
    },
    easing_library: {
      out: { quad: [0.25, 0.46, 0.45, 0.94], cubic: [0.215, 0.61, 0.355, 1], quart: [0.165, 0.84, 0.44, 1], quint: [0.23, 1, 0.32, 1], expo: [0.19, 1, 0.22, 1], circ: [0.075, 0.82, 0.165, 1] },
      in_out: { quad: [0.455, 0.03, 0.515, 0.955], cubic: [0.645, 0.045, 0.355, 1], quart: [0.77, 0, 0.175, 1], quint: [0.86, 0, 0.07, 1], expo: [1, 0, 0, 1], circ: [0.785, 0.135, 0.15, 0.86] },
    },
    duration_ms: { press: 160, small: 200, medium: 250, large: 300, page: 400, exit_factor: 0.8 },
    stagger_ms: { interval: 40, max_total: 400 },
    blur_max_px: 20,
    gesture: { velocity_threshold: 0.11 },
  },
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

// Expected values: the exit factor's contract, a fraction from 0 to 1 with default 0.8.
test("the exit factor takes a fraction from 0 to 1 and keeps 0.8 otherwise", () => {
  const factorWith = (raw) => {
    const { values, layers } = resolve({ plugin: "user-interface", projectRoot: PLUGIN, home: "no-such-home", schema, defaults, userConfig: { animation_duration_ms_exit_factor: raw }, teamOnly: ["routing"], userHome: join(PLUGIN, "no-such-user") });
    return { factor: values.animation.duration_ms.exit_factor, error_keys: layers[1].error_keys };
  };
  assert.deepEqual(factorWith("0.5"), { factor: 0.5, error_keys: [] });
  assert.deepEqual(factorWith("0"), { factor: 0, error_keys: [] });
  assert.deepEqual(factorWith("1"), { factor: 1, error_keys: [] });
  assert.deepEqual(factorWith("1.5"), { factor: 0.8, error_keys: ["animation.duration_ms.exit_factor"] });
  assert.deepEqual(factorWith("-0.1"), { factor: 0.8, error_keys: ["animation.duration_ms.exit_factor"] });
});
