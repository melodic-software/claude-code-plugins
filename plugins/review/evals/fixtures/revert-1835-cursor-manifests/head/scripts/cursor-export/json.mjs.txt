import { readFileSync } from "node:fs";

export function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

export function stableStringify(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

export function pick(source, keys) {
  const out = {};
  for (const key of keys) {
    if (source[key] !== undefined) out[key] = source[key];
  }
  return out;
}
