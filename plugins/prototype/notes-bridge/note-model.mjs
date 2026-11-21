// GENERATED from lib/ui-feedback/note-model.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
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

/** One run's drafts in a host tab's storage (sessionStorage): a single entry naming the run, so another run's
 *  drafts read back as none. What the storage gives back is untrusted: a malformed entry reads as no drafts, and
 *  only the drafts `schema` admits are kept. A storage that throws keeps nothing. */
export function draftStore(storage, run, schema, key = "ui-feedback-drafts") {
  return {
    load() {
      let saved;
      try { saved = JSON.parse(storage.getItem(key)); } catch { return []; }
      if (!isObject(saved) || saved.run !== run || !Array.isArray(saved.drafts)) return [];
      return saved.drafts.filter((n) => isObject(n) && valid(n, schema)).slice(0, schema["x-maxNotesPerRun"]);
    },
    save(drafts) {
      try { storage.setItem(key, JSON.stringify({ run, drafts })); } catch (err) { console.warn("ui-feedback: drafts not kept for a reload", err); }
    },
  };
}

/** What an element is, in a reader's words, by its role attribute first and its tag second. */
const ROLES = {
  button: "Button", link: "Link", img: "Image", table: "Table", grid: "Table", row: "Table row", cell: "Table cell",
  list: "List", listitem: "List item", navigation: "Navigation", dialog: "Dialog", tab: "Tab", heading: "Heading",
  region: "Section", checkbox: "Checkbox", textbox: "Field", menu: "Menu",
};
const TAGS = {
  img: "Image", picture: "Image", svg: "Graphic", canvas: "Graphic", figure: "Figure", table: "Table", tr: "Table row",
  td: "Table cell", th: "Table header", ul: "List", ol: "List", li: "List item", button: "Button", a: "Link",
  input: "Field", textarea: "Field", select: "Menu", form: "Form", nav: "Navigation", header: "Header", footer: "Footer",
  section: "Section", article: "Card", aside: "Side panel", main: "Main area", p: "Paragraph", label: "Label",
  h1: "Heading", h2: "Heading", h3: "Heading", h4: "Heading", h5: "Heading", h6: "Heading",
};
/** Visible text longer than this names an element by what it is instead. */
const OWN_MAX = 40;
const QUOTE_MAX = 60;

const what = (a) => ROLES[a?.role] || TAGS[a?.tag] || "Element";
const clean = (s) => (typeof s === "string" ? s.replace(/\s+/g, " ").trim() : "");
function cut(s, max) {
  const cps = [...s];
  return cps.length > max ? `${cps.slice(0, max).join("")}…` : s;
}
function named(anchor, text, card) {
  const own = clean(text), heading = clean(card);
  const first = own && [...own].length <= OWN_MAX ? own : what(anchor);
  return heading && heading !== first ? `${first}, ${heading}` : first;
}

/**
 * A note's name in the reader's words: its element's visible text (or, when that is long or missing, what the element is)
 * and the heading of the card around it, as the framed page reported them in `parts`
 * ({text, card, toText, toCard}); null `parts` names the element by what it is. The test id and path stay in the note.
 */
export function readerName(note, parts) {
  const p = parts || {};
  if (note.kind === "text") return `Text: “${cut(clean(note.anchor.textQuote?.exact), QUOTE_MAX)}”`;
  const self = named(note.anchor, p.text, p.card);
  if (note.kind === "region") return `Region over ${self}`;
  if (note.kind === "move") return `Move ${self} to ${note.to?.anchor ? named(note.to.anchor, p.toText, p.toCard) : "a point on the page"}`;
  return self;
}
