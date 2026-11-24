import { readFileSync } from "node:fs";
import { join } from "node:path";

const HERE = "lib/cdn-pins";
const EXACT = /^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$/;
const regexEscaped = (text) => text.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
const readJson = (root, path) => JSON.parse(readFileSync(join(root, path), "utf8"));
const urlOf = (cdn, name, pin) => `${cdn}${name}@${pin.version}/${pin.file}`;

/** The exact version package.json pins for each package pins.json lists. */
export function manifestVersions(manifest, packages) {
  const versions = {};
  for (const name of Object.keys(packages)) {
    const version = manifest.dependencies?.[name];
    if (typeof version !== "string" || !EXACT.test(version)) {
      throw new Error(`${HERE}/package.json must pin ${name} at an exact version, not ${JSON.stringify(version)}`);
    }
    versions[name] = version;
  }
  return versions;
}

/** What is wrong with one file's text against the current pins, as messages. */
export function problems(text, target, cdn, pins) {
  const plain = text.replace(/\\/g, "");
  const out = [];
  for (const name of target.packages) {
    const pin = pins[name];
    if (!plain.includes(urlOf(cdn, name, pin))) out.push(`${target.path} lacks ${urlOf(cdn, name, pin)}`);
    if (target.integrity && !plain.includes(pin.integrity)) out.push(`${target.path} lacks ${name}'s hash ${pin.integrity}`);
    const other = new RegExp(`${regexEscaped(`${cdn}${name}@`)}([^/\\s"'\`]+)/`, "g");
    for (const match of plain.matchAll(other)) {
      if (match[1] !== pin.version) out.push(`${target.path} names ${name}@${match[1]}, not ${pin.version}`);
    }
  }
  return out;
}

/** Offline: the messages that make `check` fail, empty when the tree agrees with package.json. */
export function check(root) {
  const record = readJson(root, `${HERE}/pins.json`);
  const versions = manifestVersions(readJson(root, `${HERE}/package.json`), record.packages);
  const out = [];
  for (const [name, version] of Object.entries(versions)) {
    if (record.packages[name].version !== version) {
      out.push(`${HERE}/package.json pins ${name} ${version} but the views carry ${record.packages[name].version}; run node ${HERE}/sync.mjs sync`);
    }
  }
  for (const target of record.targets) {
    out.push(...problems(readFileSync(join(root, target.path), "utf8"), target, record.cdn, record.packages));
  }
  return out;
}
