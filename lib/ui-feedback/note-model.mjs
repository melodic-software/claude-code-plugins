// The host page's note and controls-manifest validator. It checks a value against note.schema.json
// or controls.schema.json, which the caller loads and passes in, so no limit or enum lives here.
// The subset honored is what those schemas use: $ref to #/$defs of the same schema or, as
// <$id>#/$defs/<name>, of a schema registered with use(); type (object, array, string, integer,
// number: finite only, boolean), enum, properties, required, additionalProperties (false, or a
// schema each other value must fit), propertyNames, maxProperties, items, maxItems, minLength and
// maxLength (in code points, as JSON Schema counts), pattern (anchored ^...$, matched with the u
// flag), minimum and maximum. A keyword outside the subset throws, so a schema edit the validator
// does not honor fails loudly. notes_bridge.py holds the same subset for the bridge; both run
// fixtures/notes.json and fixtures/controls.json.

const KNOWN = new Set([
  "$schema", "$id", "$ref", "$defs", "title", "description", "x-version", "x-maxNotesPerRun",
  "type", "enum", "properties", "required", "additionalProperties", "propertyNames", "maxProperties",
  "items", "maxItems", "minLength", "maxLength", "pattern", "minimum", "maximum",
]);
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const fits = {
  object: isObject,
  array: Array.isArray,
  string: (v) => typeof v === "string",
  integer: Number.isInteger,
  number: Number.isFinite,
  boolean: (v) => typeof v === "boolean",
};
const docs = new Map();

/** Register schemas by $id, so a $ref of another schema resolves. */
export function use(...schemas) {
  for (const s of schemas) docs.set(s.$id, s);
}

/** Why `value` does not fit `node` of `schema`, as a list of messages; empty when it fits. */
export function problems(value, schema, node = schema, at = "note") {
  for (const key of Object.keys(node)) if (!KNOWN.has(key)) throw new Error(`note-model: schema keyword ${key} is not honored`);
  if (node.$ref) {
    const m = /^([A-Za-z0-9_.-]*)#\/\$defs\/([A-Za-z0-9_-]+)$/.exec(node.$ref);
    const doc = m && (m[1] ? docs.get(m[1]) : schema);
    if (!doc || !isObject(doc.$defs?.[m[2]])) throw new Error(`note-model: unresolvable $ref ${node.$ref}`);
    return problems(value, doc, doc.$defs[m[2]], at);
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
  if (Array.isArray(value)) {
    if (typeof node.maxItems === "number" && value.length > node.maxItems) return [`${at}: more than ${node.maxItems} items`];
    return isObject(node.items) ? value.flatMap((v, i) => problems(v, schema, node.items, `${at}[${i}]`)) : [];
  }
  if (!isObject(value)) return [];
  if (typeof node.maxProperties === "number" && Object.keys(value).length > node.maxProperties) return [`${at}: more than ${node.maxProperties} fields`];
  const props = isObject(node.properties) ? node.properties : {};
  const out = (node.required || []).filter((k) => !Object.hasOwn(value, k)).map((k) => `${at}.${k}: required`);
  for (const [k, v] of Object.entries(value)) {
    if (isObject(node.propertyNames)) out.push(...problems(k, schema, node.propertyNames, `${at} field name ${JSON.stringify(k)}`));
    if (Object.hasOwn(props, k)) out.push(...problems(v, schema, props[k], `${at}.${k}`));
    else if (node.additionalProperties === false) out.push(`${at}.${k}: unknown field`);
    else if (isObject(node.additionalProperties)) out.push(...problems(v, schema, node.additionalProperties, `${at}.${k}`));
  }
  return out;
}

/** True when `value` is a note `schema` accepts. */
export const valid = (value, schema) => problems(value, schema).length === 0;
