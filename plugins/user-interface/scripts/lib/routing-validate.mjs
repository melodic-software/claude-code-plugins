// Validates a value against the JSON Schema keywords reference/routing.schema.json uses.
//
//   validate(schema, value, at = "$") -> ["<path>: <message>", ...], empty when the value fits
//
// Honored: const, enum, type (object, array, string, integer), required, properties,
// additionalProperties: false, minItems, uniqueItems, items, minLength, pattern, minimum, allOf,
// if/then/else and not. Object, array and string keywords apply to any value of that shape, whether
// or not the sub-schema states `type`.

/** Errors for `value` against the schema keywords routing.schema.json uses. Object, array and string
 * keywords apply to any value of that shape, whether or not the sub-schema states `type`. */
export function validate(s, value, at = "$") {
  const errors = [];
  const fail = (msg) => errors.push(`${at}: ${msg}`);
  const isObject = typeof value === "object" && value !== null && !Array.isArray(value);
  if ("const" in s && value !== s.const) fail(`must be ${s.const}`);
  if (s.enum && !s.enum.includes(value)) fail(`must be one of ${s.enum.join(", ")}`);
  if (s.type === "object" && !isObject) return [`${at}: must be an object`];
  if (s.type === "array" && !Array.isArray(value)) return [`${at}: must be an array`];
  if (s.type === "string" && typeof value !== "string") return [`${at}: must be a string`];
  if (isObject) {
    for (const k of s.required ?? []) if (!(k in value)) fail(`missing ${k}`);
    for (const [k, v] of Object.entries(value)) {
      if (s.properties?.[k]) errors.push(...validate(s.properties[k], v, `${at}.${k}`));
      else if (s.additionalProperties === false) fail(`unknown key ${k}`);
    }
  }
  if (Array.isArray(value)) {
    if (value.length < (s.minItems ?? 0)) fail(`needs at least ${s.minItems} items`);
    if (s.uniqueItems && new Set(value).size !== value.length) fail("items must be unique");
    if (s.items) value.forEach((v, i) => errors.push(...validate(s.items, v, `${at}[${i}]`)));
  }
  if (typeof value === "string") {
    if (value.length < (s.minLength ?? 0)) fail("too short");
    if (s.pattern && !new RegExp(s.pattern).test(value)) fail(`must match ${s.pattern}`);
  }
  if (s.type === "integer" && (!Number.isInteger(value) || value < (s.minimum ?? -Infinity))) fail(`must be an integer >= ${s.minimum}`);
  for (const sub of s.allOf ?? []) errors.push(...validate(sub, value, at));
  if (s.if) {
    const branch = validate(s.if, value, at).length === 0 ? s.then : s.else;
    if (branch) errors.push(...validate(branch, value, at));
  }
  if (s.not && validate(s.not, value, at).length === 0) fail("must not match a forbidden shape");
  return errors;
}
