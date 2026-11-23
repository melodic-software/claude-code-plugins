/**
 * Keeps the rendered views' jsDelivr pins on the versions package.json names.
 * Dependabot bumps package.json; pins.json records the version, file and SRI
 * hash each view carries now, and lists the files that carry them.
 *
 *   node lib/cdn-pins/sync.mjs sync [root]    fetch each pinned file, hash it, and rewrite
 *                                             every URL, hash and CSP source, then pins.json
 *   node lib/cdn-pins/sync.mjs check [root]   offline: exit 1 when package.json and pins.json
 *                                             disagree, or a listed file lacks a current URL,
 *                                             hash or prose version, names another version, or
 *                                             holds a regex hash that is not a current one escaped
 *
 * A view file carries a pin as written (`https://cdn.jsdelivr.net/npm/<name>@<version>/<file>`),
 * in a JavaScript regular-expression literal (each `/ . +` escaped), and as "`<name>` <version>"
 * in prose (a target with `prose: true` must carry it); sync rewrites each form. A line holding
 * the escaped CDN prefix is a regular-expression line, and its hashes are written escaped. The
 * hash keeps the algorithm pins.json records.
 */

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

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

/** The URL and hash pairs, and the prose pairs, that move one package from its recorded pin to the next. */
function replacements(cdn, name, from, to) {
  return {
    values: [
      [urlOf(cdn, name, from), urlOf(cdn, name, to)],
      [from.integrity, to.integrity],
    ],
    prose: [[`\`${name}\` ${from.version}`, `\`${name}\` ${to.version}`]],
  };
}

const swap = (text, from, to) => text.split(from).join(to);
const isRegexLine = (line, cdn) => line.includes(regexEscaped(cdn));

/**
 * Rewrite one file line by line. A value whose escaped form differs from its
 * plain one is found in either form; one that reads the same escaped (a hash
 * with no + or /) takes the escaped new value on a regex line.
 */
function rewrite(text, cdn, { values, prose }) {
  return text
    .split("\n")
    .map((line) => {
      let out = line;
      for (const [from, to] of values) {
        const escaped = regexEscaped(from);
        if (escaped !== from) out = swap(swap(out, escaped, regexEscaped(to)), from, to);
        else out = swap(out, from, isRegexLine(line, cdn) ? regexEscaped(to) : to);
      }
      return prose.reduce((acc, [from, to]) => swap(acc, from, to), out);
    })
    .join("\n");
}

const B64 = "(?:\\\\?[A-Za-z0-9+/=])";
const SRI_TOKEN = new RegExp(`sha256-${B64}{44}|sha384-${B64}{64}|sha512-${B64}{88}`, "g");
const VERSION = "[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?";

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
    if (target.prose && !text.includes(`\`${name}\` ${pin.version}`)) out.push(`${target.path} lacks the prose "\`${name}\` ${pin.version}"`);
    for (const match of text.matchAll(new RegExp(`\`${regexEscaped(name)}\` v?(${VERSION})`, "g"))) {
      if (match[1] !== pin.version) out.push(`${target.path} names \`${name}\` ${match[1]}, not ${pin.version}`);
    }
  }
  if (target.integrity) {
    const current = new Set(target.packages.map((name) => regexEscaped(pins[name].integrity)));
    text.split("\n").forEach((line, index) => {
      if (!isRegexLine(line, cdn)) return;
      for (const [token] of line.matchAll(SRI_TOKEN)) {
        if (!current.has(token)) out.push(`${target.path}:${index + 1} has hash ${token} in a regular expression, not a current hash escaped`);
      }
    });
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

/** Hash the exact bytes the URL serves, with the algorithm `like` names. */
export async function integrityOf(url, like, fetchImpl = fetch) {
  const algorithm = like.slice(0, like.indexOf("-"));
  if (!["sha256", "sha384", "sha512"].includes(algorithm)) throw new Error(`unknown SRI algorithm in ${like}`);
  const response = await fetchImpl(url, { redirect: "error" });
  if (!response.ok) throw new Error(`GET ${url} answered ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  return `${algorithm}-${createHash(algorithm).update(bytes).digest("base64")}`;
}

/** Fetch, hash and rewrite; returns the paths it changed. */
export async function sync(root, { fetchImpl = fetch } = {}) {
  const record = readJson(root, `${HERE}/pins.json`);
  const versions = manifestVersions(readJson(root, `${HERE}/package.json`), record.packages);
  const next = {};
  const pairs = { values: [], prose: [] };
  for (const [name, from] of Object.entries(record.packages)) {
    const to = { ...from, version: versions[name] };
    to.integrity = await integrityOf(urlOf(record.cdn, name, to), from.integrity, fetchImpl);
    next[name] = to;
    const step = replacements(record.cdn, name, from, to);
    pairs.values.push(...step.values);
    pairs.prose.push(...step.prose);
  }
  const changed = [];
  const writes = [];
  for (const target of record.targets) {
    const path = join(root, target.path);
    const before = readFileSync(path, "utf8");
    const after = rewrite(before, record.cdn, pairs);
    const left = problems(after, target, record.cdn, next);
    if (left.length) throw new Error(`sync could not bring every pin current, so it wrote nothing:\n${left.join("\n")}`);
    if (after !== before) writes.push([path, after, target.path]);
  }
  for (const [path, text, rel] of writes) {
    writeFileSync(path, text);
    changed.push(rel);
  }
  if (JSON.stringify(next) !== JSON.stringify(record.packages)) {
    writeFileSync(join(root, `${HERE}/pins.json`), `${JSON.stringify({ ...record, packages: next }, null, 2)}\n`);
    changed.push(`${HERE}/pins.json`);
  }
  return changed;
}

export async function main(argv, { log = console.log, fetchImpl = fetch } = {}) {
  const [mode, root = "."] = argv;
  if (mode === "check") {
    const out = check(root);
    for (const line of out) log(`::error::${line}`);
    if (!out.length) log("cdn-pins: every view carries the versions and hashes package.json and pins.json name");
    return out.length ? 1 : 0;
  }
  if (mode === "sync") {
    const changed = await sync(root, { fetchImpl });
    log(changed.length ? changed.map((path) => `cdn-pins: wrote ${path}`).join("\n") : "cdn-pins: nothing to change");
    return 0;
  }
  log("usage: node lib/cdn-pins/sync.mjs sync|check [root]");
  return 2;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = await main(process.argv.slice(2));
  } catch (error) {
    console.log(`::error::cdn-pins: ${error.message}`);
    process.exitCode = 1;
  }
}
