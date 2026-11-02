// The issue dimensions (models.issue-dimensions): one reader of an issue's
// Size, Complexity and Uncertainty org issue fields, keyed on field and option
// ids, and the run budget they set. Pure: the caller fetches the facts.
import { Rejection } from "./resolve.mjs";

export const DIMENSIONS = ["size", "complexity", "uncertainty"];
// What a field no trusted account set reads as, so the run proceeds.
export const UNSET = { size: "small", complexity: "medium", uncertainty: "known" };
const NOT_ASSESSED = "not-assessed";
// The only bot whose field values count; any listed human's count too.
const LANES_APP_LOGIN = "melodic-automation-lanes[bot]";

// The account ids whose field values count: the listed humans and the lanes App.
function trustedSetters(trustedActors) {
  const actors = Array.isArray(trustedActors?.actors) ? trustedActors.actors : [];
  return new Set(
    actors
      .filter((actor) => actor?.kind === "human" || actor?.login === LANES_APP_LOGIN)
      .map((actor) => actor.id)
      .filter(Number.isInteger),
  );
}

// The config's key for the option a single-select field holds, or null when
// no trusted account set it. `facts.fieldValues` is the REST issue-field-values
// rows as {field, option} ids; `facts.fieldSetters` maps a field id to the
// account id that last set it (GraphQL field events), or null. An untrusted
// setter's value is ignored, mapped or not, so it cannot fail the read; a
// trusted option `field.options` does not map throws `unmapped(option)`.
export function trustedOption(facts, field, trustedActors, unmapped) {
  const fieldId = field["field-id"];
  const row = facts.fieldValues.find((value) => value.field === fieldId);
  if (row === undefined || !trustedSetters(trustedActors).has(facts.fieldSetters[String(fieldId)])) {
    return null;
  }
  const option = String(row.option);
  if (!Object.hasOwn(field.options, option)) {
    throw unmapped(option);
  }
  return field.options[option];
}

// {size, complexity, uncertainty}, each the config's key for the issue's
// option (trustedOption), or UNSET's when no trusted account set the field.
export function issueDimensions(facts, config, trustedActors) {
  const result = {};
  for (const name of DIMENSIONS) {
    const field = config.fields[name];
    result[name] =
      trustedOption(facts, field, trustedActors, (option) =>
        new Rejection(
          "unmapped-dimension",
          `issue field ${field["field-id"]} (${name}) holds option ${option}, which models.issue-dimensions does not map`,
        ),
      ) ?? UNSET[name];
  }
  return result;
}

// The shortest run timeout any size sets, for a run that skips.
const skipTimeout = (config) =>
  Math.min(...Object.values(config.sizes).filter((size) => size !== "split").map((size) => size["timeout-minutes"]));

// The run budget: {skip, pin, timeout-minutes} plus max-turns when it runs.
// Not assessed (a slot whose fields were not read), then uncertainty, then a
// split size skip in that order.
export function dimensionBudget(dims, config) {
  if (DIMENSIONS.some((name) => dims[name] === null)) {
    return { skip: NOT_ASSESSED, "timeout-minutes": skipTimeout(config), pin: NOT_ASSESSED };
  }
  const pin = DIMENSIONS.map((name) => dims[name]).join("/");
  const mode = config.uncertainty[dims.uncertainty];
  const size = config.sizes[dims.size];
  const skip = mode !== "run" ? mode : size === "split" ? "split-required" : null;
  if (skip !== null) {
    return { skip, "timeout-minutes": skipTimeout(config), pin };
  }
  return {
    skip: null,
    "max-turns": Math.ceil(size["base-turns"] * config.complexity[dims.complexity]),
    "timeout-minutes": size["timeout-minutes"],
    pin,
  };
}

// `dims` for a trusted size-split sub-issue (`splitChild`): a size that
// splits becomes `split-child-size`, since admission takes such a child
// whatever its Size (owner Q93). Anything else is returned as is. Pure.
export function splitChildDims(dims, config, splitChild) {
  const size = config["split-child-size"];
  return splitChild === true && size !== undefined && config.sizes[dims.size] === "split" ? { ...dims, size } : dims;
}

// The dimensions a pin (dimensionBudget's `pin`) names.
export function parsePin(pin, config) {
  if (pin === NOT_ASSESSED) {
    return Object.fromEntries(DIMENSIONS.map((name) => [name, null]));
  }
  const parts = String(pin).split("/");
  const tables = { size: config.sizes, complexity: config.complexity, uncertainty: config.uncertainty };
  if (parts.length !== DIMENSIONS.length || DIMENSIONS.some((name, i) => !Object.hasOwn(tables[name], parts[i]))) {
    throw new Rejection("undefined-dimension", `issue-dimensions \`${pin}\` names no dimensions in models.issue-dimensions`);
  }
  return Object.fromEntries(DIMENSIONS.map((name, i) => [name, parts[i]]));
}

// What the schema cannot check: every mapped key and UNSET's names an entry of
// its table, the three field ids differ, UNSET's size runs, and so at least
// one size runs.
export function checkDimensions(config) {
  const tables = { size: config.sizes, complexity: config.complexity, uncertainty: config.uncertainty };
  for (const name of DIMENSIONS) {
    for (const [option, key] of Object.entries(config.fields[name].options)) {
      if (!Object.hasOwn(tables[name], key)) {
        throw new Rejection(
          "undefined-dimension",
          `models.issue-dimensions.fields.${name} maps option ${option} to \`${key}\`, which is not a key of its table`,
        );
      }
    }
    if (!Object.hasOwn(tables[name], UNSET[name])) {
      throw new Rejection(
        "undefined-dimension",
        `models.issue-dimensions has no ${name} \`${UNSET[name]}\`, which an unset ${name} field reads as`,
      );
    }
  }
  if (new Set(DIMENSIONS.map((name) => config.fields[name]["field-id"])).size !== DIMENSIONS.length) {
    throw new Rejection("undefined-dimension", "models.issue-dimensions names one field id for two dimensions");
  }
  const child = config["split-child-size"];
  if (child !== undefined && (!Object.hasOwn(config.sizes, child) || config.sizes[child] === "split")) {
    throw new Rejection("undefined-dimension", `models.issue-dimensions.split-child-size \`${child}\` names no size that runs`);
  }
  if (config.sizes[UNSET.size] === "split") {
    throw new Rejection("undefined-dimension", `models.issue-dimensions.sizes.${UNSET.size}, which an unset size reads as, does not run`);
  }
}
