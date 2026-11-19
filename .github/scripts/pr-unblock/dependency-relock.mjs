/**
 * The directories of one .github/dependabot.yml entry that a `group-by:
 * dependency-name` group names pin each of its packages at one version.
 * Dependabot can open such a group's pull request with one directory bumped
 * and another left behind (its pip-compile could not relock that one). The
 * pr-unblock lane relocks the lagging directory to the bumped directory's pin
 * across three jobs, so uv, which may build a package's metadata and so run
 * its code, never runs beside a token: review-dependency.mjs select writes the
 * request (relockRequest), review-dependency-relock runs
 * relock-requirements.sh on it with no permissions, and
 * review-dependency-relock-patch, base code alone, checks the result and
 * writes the patch (`patch`) that apply-dependency-relock pushes under
 * patch-rules.json's dependency-relock row. `check` exits 1 while a group's
 * directories disagree, a group directory's requirements.in cannot be read, or
 * no pip group reads at all, for pr-require-checks.yml.
 *
 *   node dependency-relock.mjs check [root]
 *   node dependency-relock.mjs patch <request.json> <relocked requirements.txt> <patch.diff>
 */

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

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

export const COMPILE_COMMAND = "uv pip compile requirements.in --universal --generate-hashes --python-version 3.12 -o requirements.txt";

/**
 * What review-dependency-relock runs uv on, read from the head as data: the
 * moved requirements.in and the head's requirements.txt. Refused here, before
 * any job runs uv, when a file is missing, the pin does not move or the lock
 * was not compiled by COMPILE_COMMAND, so the model reviews such a pull request.
 */
export async function relockRequest(target, { readText }) {
  const inBefore = await readText(fileIn(target.directory, "requirements.in"));
  const txtBefore = await readText(fileIn(target.directory, "requirements.txt"));
  if (inBefore === null || txtBefore === null) throw new Error(`${target.directory || "the root"} has no requirements.in and requirements.txt`);
  if (txtBefore.replace(/\r\n/g, "\n").split("\n")[1] !== `#    ${COMPILE_COMMAND}`) {
    throw new Error(`${fileIn(target.directory, "requirements.txt")} was not compiled by \`${COMPILE_COMMAND}\``);
  }
  return { ...target, in_before: inBefore, in_after: movePipPin(inBefore, target), txt_before: txtBefore };
}

/** Held to the push job's own rule (fixContentRefusal), so a relock that would be refused never leaves the patch job. */
export function relockPatch(request, txtAfter) {
  const inPath = fileIn(request.directory, "requirements.in");
  const txtPath = fileIn(request.directory, "requirements.txt");
  if (pinsOf(txtAfter.replace(/ \\$/gm, "").replace(/ ;[^\n]*$/gm, "")).get(normalize(request.name))?.version !== request.to) {
    throw new Error(`the relocked requirements.txt does not pin ${request.name}==${request.to}`);
  }
  for (const [path, before, after] of [[inPath, request.in_before, request.in_after], [txtPath, request.txt_before, txtAfter]]) {
    const why = fixContentRefusal(path, before, after);
    if (why) throw new Error(`the relock of ${path} is refused: ${why}`);
  }
  return `${unifiedDiff(inPath, request.in_before, request.in_after)}${unifiedDiff(txtPath, request.txt_before, txtAfter)}`;
}

export function main(argv, { log = (line) => console.log(line) } = {}) {
  if (argv[0] === "patch" && argv.length === 4) {
    const request = JSON.parse(readFileSync(argv[1], "utf8"));
    writeFileSync(argv[3], relockPatch(request, readFileSync(argv[2], "utf8")));
    log(`${request.directory} relocked to ${request.name}==${request.to} from ${request.from}`);
    return 0;
  }
  if (argv[0] !== "check") throw new Error("usage: dependency-relock.mjs check [root] | patch <request.json> <requirements.txt> <patch.diff>");
  const root = argv[1] ?? ".";
  const read = (path) => {
    try {
      return readFileSync(join(root, path), "utf8");
    } catch {
      return null;
    }
  };
  const groups = parseGroups(read(".github/dependabot.yml")).filter((group) => group.ecosystem === "pip");
  if (groups.length === 0) {
    log("::error file=.github/dependabot.yml::no pip group-by dependency-name group reads, so nothing holds its directories to one pin");
    return 1;
  }
  let code = 0;
  for (const group of groups) {
    const pinned = [];
    for (const directory of group.directories) {
      const text = read(fileIn(directory, "requirements.in"));
      if (text === null) {
        log(`::error file=.github/dependabot.yml::the ${group.name} group's ${fileIn(directory, "requirements.in")} cannot be read`);
        code = 1;
      } else {
        pinned.push([directory, pinsOf(text)]);
      }
    }
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
