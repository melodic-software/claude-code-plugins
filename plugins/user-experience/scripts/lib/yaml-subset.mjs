// GENERATED from lib/yaml-subset.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// A parser for the YAML subset the team file is written in: a port of
// plugins/code-metrics/scripts/yaml_subset.py, kept to the same grammar.
//
//   parse(text) -> the document (null when empty), or throws YamlSubsetError {line, message}
//
// The subset: block mappings (nested by indentation of two or more spaces); block sequences
// (scalar or mapping items, a mapping item may start on the dash line); flow sequences of scalars
// (`[a, "b", 3]`, `[]`); scalars: quoted and plain strings, integers, floats, true/false,
// null/~, and an empty value meaning null; `#` comments outside quotes; blank lines.
// Everything else is reported with its line rather than parsed partially: flow mappings (`{`),
// anchors and aliases, tags, block scalars, document markers, tab indentation, duplicate keys,
// nesting deeper than MAX_DEPTH.
// Keys become own data properties, so a `__proto__` key never reaches an object's prototype.
// Error messages quote file text as JSON strings cut to 60 characters: they describe data.

export class YamlSubsetError extends Error {
  constructor(line, message) {
    super(`line ${line}: ${message}`);
    this.name = "YamlSubsetError";
    this.line = line;
  }
}

// Every descent below the top level passes through nested(), so this bounds the recursion.
const MAX_DEPTH = 64;
const INT = /^[-+]?\d+$/;
const FLOAT = /^[-+]?(\d+\.\d*|\.\d+|\d+)([eE][-+]?\d+)?$/;
const quote = (text) => JSON.stringify(text.length > 60 ? `${text.slice(0, 60)}...` : text);
const isItem = (content) => content === "-" || content.startsWith("- ");
const put = (object, key, value) => Object.defineProperty(object, key, { value, enumerable: true, writable: true, configurable: true });

/** The text before `#` as a comment ends it. A quote opens only where a value starts (line start,
 * after `: `, `- `, `[` or `,`), so an apostrophe inside a plain value is just a character. */
function stripComment(text) {
  let q = null;
  let last = -1; // index of the last non-whitespace character before i, so each test is O(1)
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (q) {
      if (q === '"' && ch === "\\") i++;
      else if (q === "'" && ch === "'" && text[i + 1] === "'") i++;
      else if (ch === q) q = null;
    } else if ((ch === "'" || ch === '"') && valueStarts(text, last, i)) {
      q = ch;
    } else if (ch === "#" && (i === 0 || text[i - 1] === " " || text[i - 1] === "\t")) {
      return text.slice(0, i).trimEnd();
    }
    if (i < text.length && !/\s/.test(text[i])) last = i;
  }
  return text.trimEnd();
}

/** True when a value starts at i: only whitespace follows line start, `: `, `- `, `[` or `,`. */
function valueStarts(text, last, i) {
  if (last < 0) return true;
  const c = text[last];
  const spaced = i - last > 1;
  return c === "[" || c === "," || (spaced && c === ":") || (spaced && c === "-" && (last === 0 || /\s/.test(text[last - 1])));
}

const ESCAPES = { n: "\n", t: "\t", '"': '"', "\\": "\\", "/": "/" };

function unquote(text, line) {
  const q = text[0];
  if (text.length < 2 || text.at(-1) !== q) throw new YamlSubsetError(line, "unterminated quoted string");
  const body = text.slice(1, -1);
  if (q === "'") return body.replaceAll("''", "'");
  let out = "";
  for (let i = 0; i < body.length; i++) {
    const ch = body[i];
    if (ch === "\\" && i + 1 < body.length) {
      const next = body[i + 1];
      if (!Object.hasOwn(ESCAPES, next)) throw new YamlSubsetError(line, `unsupported escape \\${next} in double-quoted string`);
      out += ESCAPES[next];
      i++;
      continue;
    }
    out += ch;
  }
  return out;
}

function scalar(raw, line) {
  const text = raw.trim();
  if (text === "") return null;
  if (text[0] === "'" || text[0] === '"') return unquote(text, line);
  if (text[0] === "{") throw new YamlSubsetError(line, "flow mapping ({...}) is outside the subset; use block style");
  if (text[0] === "&" || text[0] === "*") throw new YamlSubsetError(line, "anchors and aliases are outside the subset");
  if (text[0] === "!") throw new YamlSubsetError(line, "tags are outside the subset");
  if (["|", ">", "|-", ">-", "|+", ">+"].includes(text)) throw new YamlSubsetError(line, "block scalars (| and >) are outside the subset");
  if (text[0] === "[") return flowSequence(text, line);
  if (["null", "Null", "NULL", "~"].includes(text)) return null;
  if (["true", "True", "TRUE"].includes(text)) return true;
  if (["false", "False", "FALSE"].includes(text)) return false;
  if (INT.test(text) || FLOAT.test(text)) return Number(text);
  return text;
}

function flowSequence(text, line) {
  if (!text.endsWith("]")) throw new YamlSubsetError(line, "unterminated flow sequence");
  const body = text.slice(1, -1).trim();
  if (body === "") return [];
  const items = [];
  let current = "";
  let q = null;
  let depth = 0;
  for (const ch of body) {
    if (q) {
      current += ch;
      if (ch === q) q = null;
      continue;
    }
    if (ch === "'" || ch === '"') q = ch;
    else if (ch === "[") depth++;
    else if (ch === "]") depth--;
    else if (ch === "," && depth === 0) {
      items.push(current);
      current = "";
      continue;
    }
    current += ch;
  }
  items.push(current);
  return items.map((raw) => {
    const item = raw.trim();
    if (item.startsWith("[")) throw new YamlSubsetError(line, "nested flow sequences are outside the subset");
    return scalar(item, line);
  });
}

/** [key, rest] when the content is a mapping entry, else null. */
function splitKey(content, line) {
  if (content[0] === "'" || content[0] === '"') {
    const close = content.indexOf(content[0], 1);
    if (close === -1) throw new YamlSubsetError(line, "unterminated quoted key");
    const key = unquote(content.slice(0, close + 1), line);
    const rest = content.slice(close + 1);
    if (rest.startsWith(":") && (rest.length === 1 || rest[1] === " " || rest[1] === "\t")) return [key, rest.slice(1).trim()];
    return null;
  }
  return plainKey(content) ?? (content.endsWith(":") ? [content.slice(0, -1).trim(), ""] : null);
}

/** The Python grammar `^([^\s:[\]{}#][^:#]*?):(?:\s+(.*))?$` in one linear scan: the key runs to
 * the first `:`, holds no `#`, and the `:` ends the line or is followed by whitespace and a rest
 * with no line terminator after its leading whitespace. */
function plainKey(content) {
  if (content === "" || /[\s:[\]{}#]/.test(content[0])) return null;
  const colon = content.indexOf(":");
  if (colon === -1 || content.slice(0, colon).includes("#")) return null;
  const key = content.slice(0, colon).trim();
  const after = content.slice(colon + 1);
  if (after === "") return [key, ""];
  if (!/^\s/.test(after)) return null;
  const rest = after.trimStart();
  if (/[\n\r\u2028\u2029]/.test(rest)) return null;
  return [key, rest.trim()];
}

class Parser {
  constructor(text) {
    this.lines = []; // [indent, lineNumber, content]
    text
      .replace(/^﻿/, "")
      .split(/\r\n|\r|\n/)
      .forEach((raw, i) => {
        const number = i + 1;
        if (raw.startsWith("---") || raw.startsWith("...")) throw new YamlSubsetError(number, "document markers are outside the subset");
        const stripped = stripComment(raw);
        if (!stripped.trim()) return;
        const indent = stripped.length - stripped.replace(/^ +/, "").length;
        if (stripped[indent] === "\t") throw new YamlSubsetError(number, "tab indentation is outside the subset");
        this.lines.push([indent, number, stripped.slice(indent)]);
      });
    this.pos = 0;
    this.depth = 0;
  }

  parse() {
    if (!this.lines.length) return null;
    const value = this.block(this.lines[0][0]);
    if (this.pos < this.lines.length) {
      const [indent, number, content] = this.lines[this.pos];
      throw new YamlSubsetError(number, `unexpected content at indent ${indent}: ${quote(content)}`);
    }
    return value;
  }

  block(indent) {
    const [, number, content] = this.lines[this.pos];
    if (isItem(content)) return this.sequence(indent);
    if (splitKey(content, number) === null) throw new YamlSubsetError(number, `expected a mapping entry or sequence item, got ${quote(content)}`);
    return this.mapping(indent);
  }

  /** The block mapping at `indent`, its entries put into `result` (a sequence item's dash-line entry
   * arrives already in it, so a duplicate is reported on its own line). */
  mapping(indent, result = {}) {
    while (this.pos < this.lines.length) {
      const [lineIndent, number, content] = this.lines[this.pos];
      if (lineIndent < indent) break;
      if (lineIndent > indent) throw new YamlSubsetError(number, `unexpected indent ${lineIndent} (expected ${indent})`);
      const split = splitKey(content, number);
      if (split === null) throw new YamlSubsetError(number, `expected a mapping entry, got ${quote(content)}`);
      const [key, rest] = split;
      if (Object.hasOwn(result, key)) throw new YamlSubsetError(number, `duplicate key ${quote(key)}`);
      this.pos++;
      put(result, key, rest === "" ? this.nested(indent) : scalar(rest, number));
    }
    return result;
  }

  nested(parentIndent) {
    if (this.pos < this.lines.length) {
      const [childIndent, number, content] = this.lines[this.pos];
      if (childIndent < parentIndent || (childIndent === parentIndent && !isItem(content))) return null;
      if (this.depth === MAX_DEPTH) throw new YamlSubsetError(number, `nesting deeper than ${MAX_DEPTH} levels is outside the subset`);
      this.depth++;
      try {
        // A sequence may sit at the parent's indent (`key:` then `- item`).
        return childIndent > parentIndent ? this.block(childIndent) : this.sequence(childIndent);
      } finally {
        this.depth--;
      }
    }
    return null;
  }

  sequence(indent) {
    const result = [];
    while (this.pos < this.lines.length) {
      const [lineIndent, number, content] = this.lines[this.pos];
      if (lineIndent < indent || !isItem(content)) break;
      if (lineIndent > indent) throw new YamlSubsetError(number, `unexpected indent ${lineIndent} (expected ${indent})`);
      const item = content.slice(1).trim();
      this.pos++;
      if (item === "") {
        result.push(this.nested(indent));
        continue;
      }
      const split = splitKey(item, number);
      if (split === null) {
        result.push(scalar(item, number));
        continue;
      }
      // A mapping whose first entry sits on the dash line; the rest of its entries are indented
      // to the item column.
      const itemIndent = indent + 2;
      const [key, rest] = split;
      const mapping = put({}, key, rest === "" ? this.nested(itemIndent) : scalar(rest, number));
      if (this.pos < this.lines.length && this.lines[this.pos][0] === itemIndent) this.mapping(itemIndent, mapping);
      result.push(mapping);
    }
    return result;
  }
}

/** Parse a document written in the subset; throw YamlSubsetError otherwise. */
export const parse = (text) => new Parser(text).parse();
