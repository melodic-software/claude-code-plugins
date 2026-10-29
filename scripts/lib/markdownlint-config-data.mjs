// Decide whether a branch's markdownlint config is data, so the pre-push copy
// of scripts/check-affected.sh may lint with it without running branch code.
//
//   node scripts/lib/markdownlint-config-data.mjs options|config < file
//
// `options` is a .markdownlint-cli2.jsonc file, `config` a .markdownlint.jsonc
// or .markdownlint.json file. Exit 0 prints the parsed object as JSON, which the
// caller writes in place of the original, so markdownlint-cli2 reads exactly
// what was checked here. Exit 1 prints why the file is refused.
//
// Options keys come from the markdownlint-cli2 README's `.markdownlint-cli2.jsonc`
// section. Allowed are the ones that only hold data; customRules,
// markdownItPlugins, outputFormatters and modulePaths load modules, `extends`
// in a config reads another file that may be a module, and `fix` rewrites the
// files under check, so a finding would pass. overrides and any key the README
// adds later are refused until listed here. A __proto__ key at any depth is
// refused: markdownlint-cli2's JSONC parser assigns keys, so it would set the
// object's prototype and hide an inherited customRules or extends from a key check.
import { readFileSync } from "node:fs";

const OPTIONS_KEYS = new Set([
  "$schema", "config", "frontMatter", "gitignore", "globs", "ignores",
  "noBanner", "noInlineConfig", "noProgress", "showFound",
]);
const CODE_KEYS = new Set(["customRules", "markdownItPlugins", "outputFormatters", "modulePaths"]);

// rewrite(text, step): copies strings whole and hands every other position to
// step(i), which returns [text to emit, next position].
const rewrite = (text, step) => {
  let out = "";
  let i = 0;
  while (i < text.length) {
    if (text[i] === '"') {
      const start = i++;
      while (i < text.length && text[i] !== '"') i += text[i] === "\\" ? 2 : 1;
      out += text.slice(start, ++i);
    } else {
      const [emit, next] = step(i);
      out += emit;
      i = next;
    }
  }
  return out;
};

// JSONC to JSON: drop comments, then trailing commas, outside strings.
const stripJsonc = (text) => {
  const bare = rewrite(text, (i) => {
    if (text.startsWith("//", i)) {
      const end = text.indexOf("\n", i);
      return ["", end < 0 ? text.length : end];
    }
    if (text.startsWith("/*", i)) {
      const end = text.indexOf("*/", i + 2);
      if (end < 0) throw new Error("unterminated comment");
      return [" ", end + 2];
    }
    return [text[i], i + 1];
  });
  return rewrite(bare, (i) => {
    if (bare[i] !== ",") return [bare[i], i + 1];
    const rest = bare.slice(i + 1).trimStart();
    return [rest.startsWith("}") || rest.startsWith("]") ? "" : ",", i + 1];
  });
};

const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

const protoPath = (v, path) => {
  if (v === null || typeof v !== "object") return null;
  for (const k of Object.keys(v)) {
    if (k === "__proto__") return `${path}.__proto__`;
    const found = protoPath(v[k], `${path}.${k}`);
    if (found) return found;
  }
  return null;
};

const refusal = (kind, value) => {
  if (!isObject(value)) return "it is not a JSON object";
  const proto = protoPath(value, "");
  if (proto) return `it sets ${proto.slice(1)}`;
  const config = kind === "options" ? value.config : value;
  if (kind === "options") {
    for (const k of Object.keys(value)) {
      if (CODE_KEYS.has(k)) return `${k} loads a module`;
      if (!OPTIONS_KEYS.has(k)) return `${k} is not a data-only option`;
    }
    if (config !== undefined && !isObject(config)) return "config is not an object";
  }
  if (config && Object.hasOwn(config, "extends")) return "extends reads another file, which may be a module";
  return null;
};

const kind = process.argv[2];
if (kind !== "options" && kind !== "config") {
  console.log("usage: markdownlint-config-data.mjs options|config < file");
  process.exit(2);
}
let value;
try {
  value = JSON.parse(stripJsonc(readFileSync(0, "utf8").replace(/^﻿/, "")));
} catch (err) {
  console.log(`it does not parse as JSONC: ${err.message}`);
  process.exit(1);
}
const why = refusal(kind, value);
if (why) {
  console.log(why);
  process.exit(1);
}
console.log(JSON.stringify(value));
