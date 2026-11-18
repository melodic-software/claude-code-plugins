/**
 * The directories of one .github/dependabot.yml entry that a `group-by:
 * dependency-name` group names pin each of its packages at one version.
 * Dependabot can open such a group's pull request with one directory bumped
 * and another left behind (its pip-compile could not relock that one); this
 * relocks the lagging directory with uv to the bumped directory's pin.
 * review-dependency.mjs select writes its patch, which apply-dependency-pin
 * pushes under patch-rules.json's dependency-relock row. `check` exits 1
 * while a group's directories disagree, for pr-require-checks.yml.
 *
 *   node dependency-relock.mjs check [root]
 */

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { fixContentRefusal } from "./dependency-classify.mjs";
import { unifiedDiff } from "./install-script-pin.mjs";

const ENTRY = /^(\s*)-\s+package-ecosystem:\s*["']?([A-Za-z0-9_-]+)/;
const KEY = /^\s*([A-Za-z0-9_-]+):\s*(.*)$/;
const ITEM = /^\s*-\s+(.+)$/;
const PIN = /^([A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)(\[[A-Za-z0-9._,-]+\])?==([0-9][0-9A-Za-z.+!-]*)(\s*#.*)?$/;
const EXACT_VERSION = /^[0-9][0-9A-Za-z.+!-]*$/;

const unquote = (value) => value.trim().replace(/^(["'])(.*)\1$/, "$2");
const normalize = (name) => name.toLowerCase().replace(/[-_.]+/g, "-");
const indentOf = (line) => line.length - line.trimStart().length;
const fileIn = (directory, name) => (directory ? `${directory}/${name}` : name);
const parentOf = (path) => (path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : "");

/** Each `group-by: dependency-name` group of a dependabot.yml, its entry's directories without their slashes. */
export function parseGroups(text) {
  const entries = [];
  let entry = null;
  let section = null;
  let group = null;
  let field = null;
  for (const raw of String(text ?? "").replace(/\r\n/g, "\n").split("\n")) {
    const line = raw.replace(/\s+#.*$/, "");
    if (!line.trim() || line.trimStart().startsWith("#")) continue;
    const indent = indentOf(line);
    const start = ENTRY.exec(line);
    if (start) {
      entry = { ecosystem: start[2], keys: start[1].length + 2, directories: [], groups: [] };
      entries.push(entry);
      section = null;
      continue;
    }
    if (!entry || indent < entry.keys) {
      entry = null;
      continue;
    }
    const key = KEY.exec(line);
    const item = ITEM.exec(line);
    if (indent === entry.keys && !item) {
      section = key?.[1] ?? null;
      group = null;
      if (section === "directory") entry.directories.push(unquote(key[2]));
    } else if (section === "directories" && item) {
      entry.directories.push(unquote(item[1]));
    } else if (section === "groups") {
      if (item && group && field === "patterns") {
        group.patterns.push(unquote(item[1]));
      } else if (key && !item && (group === null || indent <= group.indent)) {
        group = { name: key[1], indent, groupBy: null, patterns: [] };
        field = null;
        entry.groups.push(group);
      } else if (key && !item && group) {
        field = key[1];
        if (field === "group-by") group.groupBy = unquote(key[2]);
      }
    }
  }
  return entries.flatMap((one) =>
    one.groups
      .filter((g) => g.groupBy === "dependency-name" && g.patterns.length > 0)
      .map((g) => ({ name: g.name, ecosystem: one.ecosystem, directories: one.directories.map((d) => d.replace(/^\/+|\/+$/g, "")), patterns: g.patterns })),
  );
}

const matches = (pattern, name) =>
  new RegExp(`^${pattern.split("*").map((part) => normalize(part).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*")}$`).test(normalize(name));

function pinsOf(text) {
  const pins = new Map();
  for (const line of String(text ?? "").split("\n")) {
    const pin = PIN.exec(line.replace(/\r$/, ""));
    if (pin) pins.set(normalize(pin[1]), { name: pin[1], version: pin[3] });
  }
  return pins;
}

/**
 * The first directory of a pip group the pull request left alone whose
 * requirements.in pins a group package at another version than the one every
 * directory it bumped agrees on, or null when none lags.
 */
export async function relockTarget({ files, groups, readText }) {
  const paths = new Set(files.flatMap((file) => [file.filename, file.previous_filename]).filter(Boolean).map(String));
  const touched = new Set([...paths].map(parentOf));
  for (const group of groups) {
    if (group.ecosystem !== "pip") continue;
    const directories = group.directories.filter((directory) => !/[*?]/.test(directory));
    const bumped = directories.filter((directory) => paths.has(fileIn(directory, "requirements.in")));
    const behind = directories.filter((directory) => !touched.has(directory));
    if (bumped.length === 0 || behind.length === 0) continue;
    const wanted = new Map();
    for (const directory of bumped) {
      for (const [key, pin] of pinsOf(await readText(fileIn(directory, "requirements.in")))) {
        if (group.patterns.some((pattern) => matches(pattern, key))) wanted.set(key, [...(wanted.get(key) ?? []), pin.version]);
      }
    }
    for (const directory of behind) {
      const pins = pinsOf(await readText(fileIn(directory, "requirements.in")));
      for (const [key, versions] of wanted) {
        const have = pins.get(key);
        if (have && new Set(versions).size === 1 && have.version !== versions[0]) {
          return { directory, name: have.name, from: have.version, to: versions[0] };
        }
      }
    }
  }
  return null;
}

export function movePipPin(text, { name, from, to }) {
  if (!EXACT_VERSION.test(String(to))) throw new Error(`${to} is not an exact version`);
  const lines = text.split("\n");
  const at = lines.flatMap((line, i) => {
    const pin = PIN.exec(line.replace(/\r$/, ""));
    return pin && normalize(pin[1]) === normalize(name) && pin[3] === from ? [i] : [];
  });
  if (at.length !== 1) throw new Error(`requirements.in pins ${name}==${from} ${at.length} times, not exactly one`);
  lines[at[0]] = lines[at[0]].replace(`==${from}`, `==${to}`);
  return lines.join("\n");
}

const SCRIPT = fileURLToPath(new URL("./relock-requirements.sh", import.meta.url));

/** Its environment carries no token: the uv resolve may build a package's metadata, which runs that package's code. */
export async function runRelock({ requirementsIn, requirementsTxt }, env = process.env) {
  const dir = mkdtempSync(join(env.RUNNER_TEMP || tmpdir(), "relock-"));
  try {
    writeFileSync(join(dir, "requirements.in"), requirementsIn);
    writeFileSync(join(dir, "requirements.txt"), requirementsTxt);
    const keep = Object.fromEntries(["PATH", "HOME", "RUNNER_TEMP", "TMPDIR"].filter((key) => env[key]).map((key) => [key, env[key]]));
    execFileSync("bash", [SCRIPT, dir], { env: keep, stdio: ["ignore", "inherit", "inherit"], timeout: 300_000 });
    return readFileSync(join(dir, "requirements.txt"), "utf8");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/** Held to the push job's own rule (fixContentRefusal) before it is handed on, so a relock that would be refused never leaves here. */
export async function relockPatch(target, { readText, run = runRelock }) {
  const inPath = fileIn(target.directory, "requirements.in");
  const txtPath = fileIn(target.directory, "requirements.txt");
  const inBefore = await readText(inPath);
  const txtBefore = await readText(txtPath);
  if (inBefore === null || txtBefore === null) throw new Error(`${target.directory || "the root"} has no requirements.in and requirements.txt`);
  const inAfter = movePipPin(inBefore, target);
  const txtAfter = await run({ requirementsIn: inAfter, requirementsTxt: txtBefore });
  if (pinsOf(txtAfter.replace(/ \\$/gm, "").replace(/ ;[^\n]*$/gm, "")).get(normalize(target.name))?.version !== target.to) {
    throw new Error(`the relocked requirements.txt does not pin ${target.name}==${target.to}`);
  }
  for (const [path, before, after] of [[inPath, inBefore, inAfter], [txtPath, txtBefore, txtAfter]]) {
    const why = fixContentRefusal(path, before, after);
    if (why) throw new Error(`the relock of ${path} is refused: ${why}`);
  }
  return { ...target, patch: `${unifiedDiff(inPath, inBefore, inAfter)}${unifiedDiff(txtPath, txtBefore, txtAfter)}` };
}

export function main(argv, { log = (line) => console.log(line) } = {}) {
  if (argv[0] !== "check") throw new Error("usage: dependency-relock.mjs check [root]");
  const root = argv[1] ?? ".";
  const read = (path) => {
    try {
      return readFileSync(join(root, path), "utf8");
    } catch {
      return null;
    }
  };
  let code = 0;
  for (const group of parseGroups(read(".github/dependabot.yml"))) {
    if (group.ecosystem !== "pip") continue;
    const pinned = group.directories.map((directory) => [directory, pinsOf(read(fileIn(directory, "requirements.in")))]);
    const keys = new Set(pinned.flatMap(([, pins]) => [...pins.keys()]).filter((key) => group.patterns.some((pattern) => matches(pattern, key))));
    for (const key of keys) {
      const held = pinned.filter(([, pins]) => pins.has(key)).map(([directory, pins]) => [directory, pins.get(key)]);
      if (new Set(held.map(([, pin]) => pin.version)).size > 1) {
        log(`::error file=.github/dependabot.yml::the ${group.name} group pins ${held[0][1].name} at different versions: ${held.map(([directory, pin]) => `${directory} ${pin.version}`).join(", ")}; relock the directory that lags`);
        code = 1;
      } else {
        log(`${held[0][1].name}: ${held.map(([directory]) => directory).join(" and ")} pin ${held[0][1].version}`);
      }
    }
  }
  return code;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main(process.argv.slice(2));
  } catch (error) {
    console.log(`::error::dependency-relock failed: ${error.message}`);
    process.exitCode = 1;
  }
}
