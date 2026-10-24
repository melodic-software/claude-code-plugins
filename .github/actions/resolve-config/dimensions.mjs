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

// {size, complexity, uncertainty}, each the config's key for the issue's
// option, or UNSET's when no trusted account set the field. `facts.fieldValues` is the REST
// issue-field-values rows as {field, option} ids; `facts.fieldSetters` maps a
// field id to the account id that last set it (GraphQL field events), or null.
// A value counts only when its setter is trusted; a trusted option the config
// does not map stops the run.
export function issueDimensions(facts, config, trustedActors) {
  const trusted = trustedSetters(trustedActors);
  const result = {};
  for (const name of DIMENSIONS) {
    const { "field-id": fieldId, options } = config.fields[name];
    const row = facts.fieldValues.find((value) => value.field === fieldId);
    // An untrusted setter's value is ignored, mapped or not, so it cannot
    // fail the resolve.
    if (row === undefined || !trusted.has(facts.fieldSetters[String(fieldId)])) {
      result[name] = UNSET[name];
      continue;
    }
    const option = String(row.option);
    if (!Object.hasOwn(options, option)) {
      throw new Rejection(
        "unmapped-dimension",
        `issue field ${fieldId} (${name}) holds option ${option}, which models.issue-dimensions does not map`,
      );
    }
    result[name] = options[option];
  }
  return result;
}

// Minutes of a run job's timeout kept back from its model step, so the steps
// after it (collect the patch, record the stop, upload both) finish before
// the job timeout and a stopped run's work reaches its lane branch.
export const SAVE_MINUTES = 20;

// The shortest run timeout any size sets, for a run that skips.
const skipTimeout = (config) =>
  Math.min(...Object.values(config.sizes).filter((size) => size !== "split").map((size) => size["timeout-minutes"]));

// The run budget: {skip, pin, timeout-minutes} plus max-turns and run-minutes
// (the model step's timeout) when it runs.
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
    "run-minutes": Math.max(1, size["timeout-minutes"] - SAVE_MINUTES),
    pin,
  };
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
  if (config.sizes[UNSET.size] === "split") {
    throw new Rejection("undefined-dimension", `models.issue-dimensions.sizes.${UNSET.size}, which an unset size reads as, does not run`);
  }
}
