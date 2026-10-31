#!/usr/bin/env node
// Prints the radius a rounded child needs inside a rounded parent, as JSON:
//   {"inner_px": n, "gap_px": n, "max_gap_px": n, "past_max_gap": bool}
// inner_px is the outer radius minus the parent's border width minus the padding, floored at zero;
// at zero the child's corner is square and the two curves no longer share a center. gap_px is the
// border width plus the padding. past_max_gap is true when gap_px exceeds max_gap_px: past it the
// two surfaces read as independent, and each radius is picked on its own merits.
// Usage: nested-radius.mjs --outer PX --border PX --padding PX [--max-gap-px PX]
// Without --max-gap-px it reads css.concentric_radius.max_gap_px from reference/defaults.yaml;
// pass the project's resolved value (detect.mjs --config) when a team layer sets it.
import { readFileSync, realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { parse } from "./lib/yaml-subset.mjs";

/**
 * The child's radius for one corner; every length is in px and must be a finite number of at least 0.
 * maxGapPx must also be whole, as team.schema.json types the config key.
 */
export function innerRadius({ outerPx, borderPx, paddingPx, maxGapPx }) {
  for (const [name, value] of Object.entries({ outerPx, borderPx, paddingPx, maxGapPx })) {
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0) throw new RangeError(`${name} must be a number of at least 0, got ${value}`);
  }
  if (!Number.isInteger(maxGapPx)) throw new RangeError(`maxGapPx must be a whole number of px, got ${maxGapPx}`);
  const gap = borderPx + paddingPx;
  return { inner_px: Math.max(0, outerPx - gap), gap_px: gap, max_gap_px: maxGapPx, past_max_gap: gap > maxGapPx };
}

/** css.concentric_radius.max_gap_px from the plugin's bundled defaults. */
function bundledMaxGap() {
  const defaults = parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), "../reference/defaults.yaml"), "utf8"));
  const value = defaults?.css?.concentric_radius?.max_gap_px;
  if (value === undefined) throw new Error("reference/defaults.yaml has no css.concentric_radius.max_gap_px; pass --max-gap-px");
  return value;
}

/** A flag's text as a number, or NaN when it is not one. */
const number = (text) => (text === undefined || text.trim() === "" ? Number.NaN : Number(text));

function main() {
  const { values } = parseArgs({
    options: { outer: { type: "string" }, border: { type: "string" }, padding: { type: "string" }, "max-gap-px": { type: "string" } },
    strict: true,
  });
  const maxGap = values["max-gap-px"] === undefined ? bundledMaxGap() : number(values["max-gap-px"]);
  const result = innerRadius({ outerPx: number(values.outer), borderPx: number(values.border), paddingPx: number(values.padding), maxGapPx: maxGap });
  console.log(JSON.stringify(result));
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  try {
    main();
  } catch (error) {
    console.error(`nested-radius: ${error.message}`);
    process.exit(2);
  }
}
