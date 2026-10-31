// A JSON Schema (draft 2020-12) validator for the keyword subset the plugin's
// own schemas use. A schema holding any other keyword is refused at compile
// time, so the schema cannot grow a rule this code would silently skip.

const ANNOTATIONS = new Set(['$schema', '$id', 'title', 'description']);
const KEYWORDS = new Set([
  'type',
  'const',
  'enum',
  'required',
  'properties',
  'additionalProperties',
  'propertyNames',
  'minProperties',
  'items',
  'minItems',
  'uniqueItems',
  'minLength',
  'maxLength',
  'pattern',
  'minimum',
  'maximum',
  'oneOf',
  '$ref',
  '$defs',
]);

export function compileSchema(root) {
  checkKeywords(root, '#');
  return (value) => {
    const errors = [];
    validate(root, root, value, '', errors);
    return errors;
  };
}

function checkKeywords(schema, at) {
  if (typeof schema !== 'object' || schema === null) {
    if (typeof schema === 'boolean') return;
    throw new Error(`schema at ${at} is not an object or boolean`);
  }
  for (const [key, sub] of Object.entries(schema)) {
    if (ANNOTATIONS.has(key)) continue;
    if (!KEYWORDS.has(key)) throw new Error(`schema keyword ${key} at ${at} is not supported`);
    if (key === 'properties' || key === '$defs') {
      for (const [name, child] of Object.entries(sub)) checkKeywords(child, `${at}/${key}/${name}`);
    } else if (key === 'oneOf') {
      sub.forEach((child, i) => checkKeywords(child, `${at}/oneOf/${i}`));
    } else if (['additionalProperties', 'propertyNames', 'items'].includes(key)) {
      checkKeywords(sub, `${at}/${key}`);
    }
  }
}

function resolveRef(root, ref) {
  if (!ref.startsWith('#/')) throw new Error(`only local $ref is supported: ${ref}`);
  let node = root;
  for (const part of ref.slice(2).split('/')) {
    node = node?.[part.replaceAll('~1', '/').replaceAll('~0', '~')];
  }
  if (node === undefined) throw new Error(`unresolved $ref ${ref}`);
  return node;
}

function typeOf(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return 'array';
  if (Number.isInteger(value)) return 'integer';
  return typeof value;
}

function typeMatches(expected, value) {
  const actual = typeOf(value);
  return actual === expected || (expected === 'number' && actual === 'integer');
}

function equal(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

function validate(root, schema, value, path, errors) {
  if (schema === true) return;
  if (schema === false) {
    errors.push(`${path || '/'}: not allowed`);
    return;
  }
  const at = path || '/';
  if (schema.$ref) validate(root, resolveRef(root, schema.$ref), value, path, errors);
  if (schema.type && !typeMatches(schema.type, value)) {
    errors.push(`${at}: must be ${schema.type}`);
    return;
  }
  if ('const' in schema && !equal(schema.const, value)) {
    errors.push(`${at}: must be ${JSON.stringify(schema.const)}`);
  }
  if (schema.enum && !schema.enum.some((v) => equal(v, value))) {
    errors.push(`${at}: must be one of ${schema.enum.map((v) => JSON.stringify(v)).join(', ')}`);
  }
  if (typeof value === 'string') {
    const length = [...value].length;
    if (schema.minLength !== undefined && length < schema.minLength) {
      errors.push(`${at}: must be at least ${schema.minLength} characters`);
    }
    if (schema.maxLength !== undefined && length > schema.maxLength) {
      errors.push(`${at}: must be at most ${schema.maxLength} characters`);
    }
    if (schema.pattern && !new RegExp(schema.pattern, 'u').test(value)) {
      errors.push(`${at}: must match ${schema.pattern}`);
    }
  }
  if (typeof value === 'number') {
    if (schema.minimum !== undefined && value < schema.minimum) errors.push(`${at}: must be >= ${schema.minimum}`);
    if (schema.maximum !== undefined && value > schema.maximum) errors.push(`${at}: must be <= ${schema.maximum}`);
  }
  if (Array.isArray(value)) {
    if (schema.minItems !== undefined && value.length < schema.minItems) {
      errors.push(`${at}: must hold at least ${schema.minItems} item(s)`);
    }
    if (schema.uniqueItems && new Set(value.map((v) => JSON.stringify(v))).size !== value.length) {
      errors.push(`${at}: items must be unique`);
    }
    if (schema.items !== undefined) {
      value.forEach((item, i) => validate(root, schema.items, item, `${path}/${i}`, errors));
    }
  }
  if (typeOf(value) === 'object') validateObject(root, schema, value, path, errors);
  if (schema.oneOf) {
    const passing = schema.oneOf.filter((sub) => {
      const subErrors = [];
      validate(root, sub, value, path, subErrors);
      return subErrors.length === 0;
    });
    if (passing.length !== 1) errors.push(`${at}: must match exactly one allowed shape`);
  }
}

function validateObject(root, schema, value, path, errors) {
  const at = path || '/';
  const keys = Object.keys(value);
  if (schema.minProperties !== undefined && keys.length < schema.minProperties) {
    errors.push(`${at}: must hold at least ${schema.minProperties} entr${schema.minProperties === 1 ? 'y' : 'ies'}`);
  }
  for (const name of schema.required ?? []) {
    if (!Object.hasOwn(value, name)) errors.push(`${at}: missing required property ${name}`);
  }
  for (const key of keys) {
    const child = `${path}/${key}`;
    if (schema.propertyNames) {
      const nameErrors = [];
      validate(root, schema.propertyNames, key, child, nameErrors);
      if (nameErrors.length) errors.push(`${child}: property name is not allowed`);
    }
    if (schema.properties && Object.hasOwn(schema.properties, key)) {
      validate(root, schema.properties[key], value[key], child, errors);
    } else if (schema.additionalProperties === false) {
      errors.push(`${child}: unknown property`);
    } else if (schema.additionalProperties !== undefined) {
      validate(root, schema.additionalProperties, value[key], child, errors);
    }
  }
}
