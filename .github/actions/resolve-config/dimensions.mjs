import { Rejection } from "./resolve.mjs";

export const DIMENSIONS = ["size", "complexity", "uncertainty"];
export const UNSET = { size: "small", complexity: "medium", uncertainty: "known" };
const NOT_ASSESSED = "not-assessed";
const LANES_APP_LOGIN = "melodic-automation-lanes[bot]";

export function trustedSetters(trustedActors) {
  const actors = Array.isArray(trustedActors?.actors) ? trustedActors.actors : [];
  return new Set(
    actors
      .filter((actor) => actor?.kind === "human" || actor?.login === LANES_APP_LOGIN)
      .map((actor) => actor.id)
      .filter(Number.isInteger),
  );
}

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

const skipTimeout = (config) =>
  Math.min(...Object.values(config.sizes).filter((size) => size !== "split").map((size) => size["timeout-minutes"]));

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

export function splitChildDims(dims, config, splitChild) {
  const size = config["split-child-size"];
  return splitChild === true && size !== undefined && config.sizes[dims.size] === "split" ? { ...dims, size } : dims;
}

const tablesOf = (config) => ({ size: config.sizes, complexity: config.complexity, uncertainty: config.uncertainty });

export function parsePin(pin, config) {
  if (pin === NOT_ASSESSED) {
    return Object.fromEntries(DIMENSIONS.map((name) => [name, null]));
  }
  const parts = String(pin).split("/");
  const tables = tablesOf(config);
  if (parts.length !== DIMENSIONS.length || DIMENSIONS.some((name, i) => !Object.hasOwn(tables[name], parts[i]))) {
    throw new Rejection("undefined-dimension", `issue-dimensions \`${pin}\` names no dimensions in models.issue-dimensions`);
  }
  return Object.fromEntries(DIMENSIONS.map((name, i) => [name, parts[i]]));
}

export function checkDimensions(config) {
  const tables = tablesOf(config);
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
