// GENERATED from lib/ui-feedback/note-model.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// The host page's note validator. It checks a value against note.schema.json, which the caller
// loads and passes in, so no limit or enum lives here. The subset honored is what that schema
// uses: $ref to #/$defs, type (object, string, integer, number: finite only), enum, properties, required,
// additionalProperties false, minLength and maxLength (in code points, as JSON Schema counts),
// pattern (anchored ^...$, matched with the u flag), minimum and maximum. A keyword outside the
// subset throws, so a schema edit the validator does not honor fails loudly. notes_bridge.py
// holds the same subset for the bridge; both run fixtures/notes.json.

const KNOWN = new Set([
  "$schema", "$id", "$ref", "$defs", "title", "description", "x-version", "x-maxNotesPerRun",
  "type", "enum", "properties", "required", "additionalProperties", "minLength", "maxLength",
  "pattern", "minimum", "maximum",
]);
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const fits = {
  object: isObject,
  string: (v) => typeof v === "string",
  integer: Number.isInteger,
  number: Number.isFinite,
};

/** Why `value` does not fit `node` of `schema`, as a list of messages; empty when it fits. */
export function problems(value, schema, node = schema, at = "note") {
  for (const key of Object.keys(node)) if (!KNOWN.has(key)) throw new Error(`note-model: schema keyword ${key} is not honored`);
  if (node.$ref) {
    const m = /^#\/\$defs\/([A-Za-z0-9_-]+)$/.exec(node.$ref);
    if (!m || !isObject(schema.$defs?.[m[1]])) throw new Error(`note-model: unresolvable $ref ${node.$ref}`);
    return problems(value, schema, schema.$defs[m[1]], at);
  }
  if (node.type && !fits[node.type]?.(value)) return [`${at}: expected ${node.type}`];
  if (Array.isArray(node.enum) && !node.enum.includes(value)) return [`${at}: not one of ${node.enum.join(", ")}`];
  if (typeof value === "string") {
    const n = [...value].length;
    if (typeof node.minLength === "number" && n < node.minLength) return [`${at}: shorter than ${node.minLength}`];
    if (typeof node.maxLength === "number" && n > node.maxLength) return [`${at}: longer than ${node.maxLength}`];
    if (typeof node.pattern === "string" && !new RegExp(node.pattern, "u").test(value)) return [`${at}: does not match its pattern`];
  }
  if (typeof value === "number") {
    if (typeof node.minimum === "number" && value < node.minimum) return [`${at}: below ${node.minimum}`];
    if (typeof node.maximum === "number" && value > node.maximum) return [`${at}: above ${node.maximum}`];
  }
  if (!isObject(value)) return [];
  const props = isObject(node.properties) ? node.properties : {};
  const out = (node.required || []).filter((k) => !Object.hasOwn(value, k)).map((k) => `${at}.${k}: required`);
  for (const [k, v] of Object.entries(value)) {
    if (Object.hasOwn(props, k)) out.push(...problems(v, schema, props[k], `${at}.${k}`));
    else if (node.additionalProperties === false) out.push(`${at}.${k}: unknown field`);
  }
  return out;
}

/** True when `value` is a note `schema` accepts. */
export const valid = (value, schema) => problems(value, schema).length === 0;
