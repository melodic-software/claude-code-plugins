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
    border_px: { hairline: 0.5, standard: 1, strong: 2 },
    edge_fade: { length: "2rem", stops_percent: [10, 90] },
    focus_ring: { offset_px: 2, width: "max(2px, 0.08em)" },
    image_outline: { opacity: 0.1 },
  },
  animation: {
    easing: {
      out: [0.32, 0.72, 0, 1],
      in: [0.3, 0, 1, 1],
      in_out: [0.77, 0, 0.175, 1],
      drawer: [0.32, 0.72, 0, 1],
      spring_stand_in: [0.25, 0.1, 0, 1],
    },
    easing_library: {
      out: { quad: [0.25, 0.46, 0.45, 0.94], cubic: [0.215, 0.61, 0.355, 1], quart: [0.165, 0.84, 0.44, 1], quint: [0.23, 1, 0.32, 1], expo: [0.19, 1, 0.22, 1], circ: [0.075, 0.82, 0.165, 1] },
      in_out: { quad: [0.455, 0.03, 0.515, 0.955], cubic: [0.645, 0.045, 0.355, 1], quart: [0.77, 0, 0.175, 1], quint: [0.86, 0, 0.07, 1], expo: [1, 0, 0, 1], circ: [0.785, 0.135, 0.15, 0.86] },
    },
    duration_ms: { press: 160, hover: 150, small: 200, medium: 250, large: 300, page: 400, exit_factor: 0.8 },
    delay_ms: { group_warm: 300, tooltip: 200, indicator: 150 },
    scale: { press: 0.97, press_min: 0.95, enter: 0.95, enter_small: 0.97, hover_max: 1.02, swap_start: 0.3 },
    stagger_ms: { interval: 40, max_total: 400, section: 100, word: 80 },
    travel_px: { small: 4, medium: 8, large: 16 },
    blur_max_px: 20,
    blur_px: { soften: 2 },
    spring: { bounce: { default: 0, playful_max: 0.3 }, duration_s: { default: 0.5, small: 0.35 }, response_s: [0.3, 0.4] },
    gesture: { velocity_threshold: 0.11, distance_threshold: 0.4, deceleration_rate: 0.998, rubberband_constant: 0.55, slop_px: 10 },
    inspect_playback_rate: 0.1,
    skip_frequency: 100,
    cleanup_order: ["removal", "review", "performance"],
  },
  color: {
    border: { dark_solid_l: 0.285, light_alpha: 0.08 },
    dark_mode: { brand_desaturation_percent: [20, 30] },
    hover_mix_percent: 15,
    illustration_max_colors: 3,
    overlay_alpha: 0.2,
    ramp: { chroma_percent: [30, 85], endpoints_l: [0.97, 0.22], hue_spread_max_deg: 10 },
    subtle_mix_percent: 12,
    triage: { light_surface_min_l: 0.6, near_black_l: [0.25, 0.75, 0.3], near_white_l: [0.85, 0.45] },
  },
  components: { primitives_default: "base-ui" },
  icon: { filled_below_px: 12, label_gap_em: 0.5, label_gap_px: [6, 8], size_em: 1, size_px: [12, 16, 20, 24, 48] },
  layout: {
    breakout_width: "80rem",
    content_width: "1200px",
    grid_track_min_width: "16rem",
    media_aspect_ratio: "16 / 9",
    media_small: "3.5rem",
    panel_max_height: "80dvh",
    sidebar_width: ["20rem", "50%"],
    simple_page_columns: 8,
    terminal_min_columns: 80,
    z_index_stray_above: 100,
  },
  performance: { image_max_kb: 300, search_debounce_ms: 300, virtualize_min_items: 50 },
  radius: { s: "4px", l: "1.25rem" },
  spacing: {
    xs: "0.5rem",
    s: "1rem",
    m: "1.5rem",
    l: "2rem",
    control_padding: ["0.75rem", "1.25rem"],
    flow: ["1lh", "2em", "0.5em"],
    optical_icon_px: 2,
    section: ["clamp(3rem, 1rem + 6vw, 8rem)", "6rem"],
  },
  states: { copy_confirm_ms: 1500, toast_reading_wpm: [200, 250], wait_indicator_ms: 400 },
  typography: {
    long_form_body_px: 18,
    fluid_body: { min_rem: 1, preferred_rem: 0.75, preferred_vw: 1, max_rem: 1.75 },
    fluid_scale: { narrow_rem: 20, wide_rem: 77.5, size_narrow_rem: 1.125, size_wide_rem: 1.25, ratio_narrow: 1.2, ratio_wide: 1.25, space_m_factor: 1.5, space_l_factor: 2 },
    fluid_max_ratio: 2.5,
    line_height: { body: [1.5, 1.6], display: 1.1 },
    measure_ch: 65,
    small_text_px: { caption: 13, control: 14, min: 12 },
  },
  touch: { both_axes_activation: "tap-to-activate", check_width_px: 375, fixed_width_hunt_px: 340, target_desktop_px: 40 },
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

// Expected values: the key's contract, an integer of at least 16 (the body floor) with default 18.
test("the long-form reading size takes an integer of at least 16 and keeps 18 otherwise", () => {
  assert.equal(schema.properties.typography.properties.long_form_body_px.minimum, 16);
  const sizeWith = (raw) => {
    const { values, layers } = resolve({ plugin: "user-interface", projectRoot: PLUGIN, home: "no-such-home", schema, defaults, userConfig: { typography_long_form_body_px: raw }, teamOnly: ["routing"], userHome: join(PLUGIN, "no-such-user") });
    return { size: values.typography.long_form_body_px, error_keys: layers[1].error_keys };
  };
  assert.deepEqual(sizeWith("20"), { size: 20, error_keys: [] });
  assert.deepEqual(sizeWith("16"), { size: 16, error_keys: [] });
  assert.deepEqual(sizeWith("15"), { size: 18, error_keys: ["typography.long_form_body_px"] });
  assert.deepEqual(sizeWith("18.5"), { size: 18, error_keys: ["typography.long_form_body_px"] });
});

// Expected values: the key's contract, the two approach values with default tap-to-activate.
test("the both-axes activation takes one of its two approaches and keeps tap-to-activate otherwise", () => {
  const activationWith = (raw) => {
    const { values, layers } = resolve({ plugin: "user-interface", projectRoot: PLUGIN, home: "no-such-home", schema, defaults, userConfig: { touch_both_axes_activation: raw }, teamOnly: ["routing"], userHome: join(PLUGIN, "no-such-user") });
    return { activation: values.touch.both_axes_activation, error_keys: layers[1].error_keys };
  };
  assert.deepEqual(activationWith("always-active"), { activation: "always-active", error_keys: [] });
  assert.deepEqual(activationWith("tap-to-activate"), { activation: "tap-to-activate", error_keys: [] });
  assert.deepEqual(activationWith("tap to activate"), { activation: "tap-to-activate", error_keys: ["touch.both_axes_activation"] });
  assert.deepEqual(activationWith("never"), { activation: "tap-to-activate", error_keys: ["touch.both_axes_activation"] });
});

// Expected values: the key's contract, a list of 1 to 4 of the motion lane's four pass names.
test("the cleanup order takes a list of the four pass names and refuses anything else", () => {
  const errorKeysWith = (order) => {
    const { layers } = resolve({ plugin: "user-interface", projectRoot: PLUGIN, home: "no-such-home", schema, defaults: { ...defaults, animation: { ...defaults.animation, cleanup_order: order } }, teamOnly: ["routing"], userHome: join(PLUGIN, "no-such-user") });
    return layers[0].error_keys;
  };
  assert.deepEqual(errorKeysWith(["performance", "opportunities", "review", "removal"]), []);
  assert.deepEqual(errorKeysWith(["review"]), []);
  assert.deepEqual(errorKeysWith([]), ["animation.cleanup_order"]);
  assert.deepEqual(errorKeysWith(["removal", "polish"]), ["animation.cleanup_order"]);
  assert.deepEqual(errorKeysWith("removal"), ["animation.cleanup_order"]);
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

// Expected values: the press scale's contract, a fraction from 0 to 1 with default 0.97.
test("the press scale takes a fraction from 0 to 1 and keeps 0.97 otherwise", () => {
  const scaleWith = (raw) => {
    const { values, layers } = resolve({ plugin: "user-interface", projectRoot: PLUGIN, home: "no-such-home", schema, defaults, userConfig: { animation_scale_press: raw }, teamOnly: ["routing"], userHome: join(PLUGIN, "no-such-user") });
    return { scale: values.animation.scale.press, error_keys: layers[1].error_keys };
  };
  assert.deepEqual(scaleWith("0.9"), { scale: 0.9, error_keys: [] });
  assert.deepEqual(scaleWith("1"), { scale: 1, error_keys: [] });
  assert.deepEqual(scaleWith("1.05"), { scale: 0.97, error_keys: ["animation.scale.press"] });
  assert.deepEqual(scaleWith("-0.1"), { scale: 0.97, error_keys: ["animation.scale.press"] });
});

// Expected values: the control padding's contract, a list of exactly two CSS lengths (block, inline).
test("the control padding takes two CSS length strings and refuses any other list", () => {
  const errorKeysWith = (padding) => {
    const { layers } = resolve({ plugin: "user-interface", projectRoot: PLUGIN, home: "no-such-home", schema, defaults: { ...defaults, spacing: { ...defaults.spacing, control_padding: padding } }, teamOnly: ["routing"], userHome: join(PLUGIN, "no-such-user") });
    return layers[0].error_keys;
  };
  assert.deepEqual(errorKeysWith(["0.5rem", "1rem"]), []);
  assert.deepEqual(errorKeysWith(["0.5rem"]), ["spacing.control_padding"]);
  assert.deepEqual(errorKeysWith(["0.5rem", "1rem", "2rem"]), ["spacing.control_padding"]);
  assert.deepEqual(errorKeysWith([8, 16]), ["spacing.control_padding"]);
});

// Expected values: the floors these keys are bounded by, as the plan's key set states them: the
// 24px WCAG 2.2 AA target size (SC 2.5.8) for the desktop hit area, and the 16px body floor (1rem)
// for the smallest fluid body size and the narrow end of the fluid scale.
test("a floor-bounded key refuses a value below its floor and keeps its default", () => {
  const withValue = (name, raw, path) => {
    const { values, layers } = resolve({ plugin: "user-interface", projectRoot: PLUGIN, home: "no-such-home", schema, defaults, userConfig: { [name]: raw }, teamOnly: ["routing"], userHome: join(PLUGIN, "no-such-user") });
    return { value: path.split(".").reduce((o, k) => o[k], values), error_keys: layers[1].error_keys };
  };
  assert.deepEqual(withValue("touch_target_desktop_px", "24", "touch.target_desktop_px"), { value: 24, error_keys: [] });
  assert.deepEqual(withValue("touch_target_desktop_px", "23", "touch.target_desktop_px"), { value: 40, error_keys: ["touch.target_desktop_px"] });
  assert.deepEqual(withValue("typography_fluid_body_min_rem", "1", "typography.fluid_body.min_rem"), { value: 1, error_keys: [] });
  assert.deepEqual(withValue("typography_fluid_body_min_rem", "0.9", "typography.fluid_body.min_rem"), { value: 1, error_keys: ["typography.fluid_body.min_rem"] });
  assert.deepEqual(withValue("typography_fluid_scale_size_narrow_rem", "1", "typography.fluid_scale.size_narrow_rem"), { value: 1, error_keys: [] });
  assert.deepEqual(withValue("typography_fluid_scale_size_narrow_rem", "0.9", "typography.fluid_scale.size_narrow_rem"), { value: 1.125, error_keys: ["typography.fluid_scale.size_narrow_rem"] });
});

// Expected values: the owner's decision of 2026-11-09, a press-scale lower limit of 0.95 taken as a
// fraction from 0 to 1.
test("the press-scale lower limit takes a fraction from 0 to 1 and keeps 0.95 otherwise", () => {
  const limitWith = (raw) => {
    const { values, layers } = resolve({ plugin: "user-interface", projectRoot: PLUGIN, home: "no-such-home", schema, defaults, userConfig: { animation_scale_press_min: raw }, teamOnly: ["routing"], userHome: join(PLUGIN, "no-such-user") });
    return { limit: values.animation.scale.press_min, error_keys: layers[1].error_keys };
  };
  assert.deepEqual(limitWith("0.9"), { limit: 0.9, error_keys: [] });
  assert.deepEqual(limitWith("1.1"), { limit: 0.95, error_keys: ["animation.scale.press_min"] });
  assert.deepEqual(limitWith("-0.1"), { limit: 0.95, error_keys: ["animation.scale.press_min"] });
});
