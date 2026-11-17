import fs from "node:fs";
import path from "node:path";
import { moduleName, referencedModules, shadowsStandard, usesGeneratedName } from "./guard.ts";

const MAX_ENTRIES = 10_000;

export function checkSpecName(specFile: string) {
  if (!specFile.endsWith(".tla") || path.basename(specFile) === ".tla")
    throw new Error(`${specFile} is not a TLA+ spec. Give a file whose name ends in .tla.`);
}

function refuseCode(folder: string) {
  const pending = [folder];
  let seen = 0;
  while (pending.length) {
    const dir = pending.pop() as string;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (++seen > MAX_ENTRIES)
        throw new Error(
          `${folder} holds more than ${MAX_ENTRIES} entries. Put the spec in a folder of its own.`,
        );
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) pending.push(full);
      else if (/\.(class|jar)$/i.test(entry.name))
        throw new Error(
          `${full} is Java code beside the spec, and TLC would load it. Move the spec to a folder with no .class or .jar file.`,
        );
    }
  }
}

export function stageSpec(specFile: string, into: string, allowed: string[]) {
  checkSpecName(specFile);
  const folder = path.dirname(path.resolve(specFile));
  refuseCode(folder);
  fs.mkdirSync(into, { recursive: true });
  if (into.includes(path.delimiter))
    throw new Error(`The staging folder ${into} holds ${path.delimiter}. Set TMPDIR to a plain path.`);
  const own = new Map<string, string>();
  for (const entry of fs.readdirSync(folder, { withFileTypes: true })) {
    if (!entry.isFile() || !entry.name.endsWith(".tla")) continue;
    const text = fs.readFileSync(path.join(folder, entry.name), "utf8");
    const name = moduleName(text) ?? entry.name.slice(0, -4);
    for (const n of [name, entry.name.slice(0, -4)])
      if (shadowsStandard(n))
        throw new Error(
          `${entry.name} defines the module ${n}, which shadows a standard or generated module. Rename it.`,
        );
    const generated = usesGeneratedName(text);
    if (generated)
      throw new Error(
        `${entry.name} uses the name ${generated}, which the command generates. Rename it.`,
      );
    own.set(entry.name.slice(0, -4), text);
    fs.writeFileSync(path.join(into, entry.name), text, { flag: "wx" });
  }
  const spec = path.basename(specFile);
  if (!fs.existsSync(path.join(into, spec)))
    throw new Error(`${specFile} is not a regular file. Give the spec itself, not a link.`);
  for (const [name, text] of own)
    for (const used of referencedModules(text))
      if (!own.has(used) && !allowed.includes(used))
        throw new Error(
          `The module ${name} uses ${used}, which is not in the allowed modules (${allowed.join(", ")}). Modules such as Json read and write files on this machine; pass one with --modules only when you trust the spec.`,
        );
  return path.join(into, spec);
}

const KEPT = ["PATH", "LANG", "LC_ALL"];
const TEST_FAKE_JAVA_PREFIX = "STATECHART_";

export function childEnv(home: string, extra: { [name: string]: string } = {}) {
  const env: { [name: string]: string } = {};
  for (const name of KEPT) if (process.env[name] !== undefined) env[name] = process.env[name] as string;
  for (const [name, value] of Object.entries(process.env))
    if (name.startsWith(TEST_FAKE_JAVA_PREFIX) && value !== undefined) env[name] = value;
  return { ...env, HOME: home, TMPDIR: home, ...extra };
}

export function freshOut(out: string) {
  const dest = path.resolve(out);
  const stat = fs.lstatSync(dest, { throwIfNoEntry: false });
  if (stat?.isSymbolicLink())
    throw new Error(
      fs.existsSync(dest)
        ? `${out} cannot be the output folder. It is a symbolic link. Pass --out with a new folder.`
        : `${out} cannot be the output folder. It is a broken link. Pass --out with a new folder.`,
    );
  if (stat && !stat.isDirectory())
    throw new Error(`${out} cannot be the output folder. It is not a folder. Pass --out with a new folder.`);
  const entries = stat ? fs.readdirSync(dest) : [];
  if (entries.length)
    throw new Error(
      `${out} is not empty. It has ${entries.sort()[0]}. The command writes only to a new or empty folder. Pass --out with a new folder.`,
    );
  return dest;
}
