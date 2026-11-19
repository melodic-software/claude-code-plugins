// SYNC-MANAGED FILE — DO NOT EDIT IN THE CONSUMING REPOSITORY.
// Source of truth: melodic-software/standards,
// components/runner-policy/policy-input.mjs (the `runner-policy`
// component in distribution/sync-manifest.yml). Downstream edits are
// overwritten by the next sync PR; change the component upstream, or move the
// component to `locally-owned` in the manifest to customize.
//
// Strict JSON input and schema-error helpers shared by the runner, concurrency,
// dependabot and pr-convention policy analyzers. It lives beside
// runner-policy.mjs because that analyzer is synced and runs on its own at the
// consumer: this file travels with it and resolves `yaml` from the same
// component-local dependency root.

import { readFile } from "node:fs/promises";

import { parseDocument } from "yaml";

export class ConfigurationError extends Error {
  constructor(message) {
    super(message);
    this.name = "ConfigurationError";
  }
}

export function parseUniqueJson(source, location) {
  const document = parseDocument(source, {
    maxAliasCount: 0,
    merge: false,
    prettyErrors: true,
    schema: "json",
    strict: true,
    uniqueKeys: true,
  });
  if (document.errors.length > 0) {
    throw new ConfigurationError(
      `${location} has duplicate object members or ambiguous structure: ${document.errors[0].message}`,
    );
  }
  try {
    return JSON.parse(source);
  } catch (error) {
    throw new ConfigurationError(`${location} is not valid JSON: ${error.message}`);
  }
}

// The shared object-shape check behind every "must be a mapping" decision. It
// admits any non-null, non-array object, which under the core schema means a
// decoded YAML mapping — but an explicit `!!set`/`!!omap`/`!!timestamp`/
// `!!binary` tag or a `%YAML 1.1` directive also decodes to an object this
// admits. Tag-shape rejection is deliberately not performed here; it belongs
// at the parse boundary, not at each individual gate.
export function isMapping(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function jsonPointerLocation(location, instancePath) {
  return `${location}${instancePath
    .split("/")
    .slice(1)
    .map((segment) => `.${segment.replaceAll("~1", "/").replaceAll("~0", "~")}`)
    .join("")}`;
}

// Returns the value when the compiled Ajv validator accepts it; otherwise
// throws a ConfigurationError naming the first failing location.
export function validateAgainstSchema(value, validator, location) {
  if (validator(value)) {
    return value;
  }
  const [error] = validator.errors;
  let errorLocation = jsonPointerLocation(location, error.instancePath);
  if (error.keyword === "additionalProperties") {
    errorLocation += `.${error.params.additionalProperty}`;
  } else if (error.keyword === "propertyNames") {
    errorLocation += `.${error.params.propertyName}`;
  }
  throw new ConfigurationError(`${errorLocation} ${error.message}`);
}

// A missing file reads as undefined; any other read failure is a
// ConfigurationError.
export async function readOptionalJson(filePath, location) {
  let source;
  try {
    source = await readFile(filePath, "utf8");
  } catch (error) {
    if (error.code === "ENOENT") {
      return undefined;
    }
    throw new ConfigurationError(`${location} could not be read at ${filePath}: ${error.message}`);
  }
  return parseUniqueJson(source, `${location} at ${filePath}`);
}
