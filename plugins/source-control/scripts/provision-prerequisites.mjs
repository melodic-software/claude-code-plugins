#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { parse } from "../lib/yaml-subset.mjs";

export const RECORD_DIRS = [".claude/ecosystems", "docs/conventions/ecosystems"];
const LOCKFILES = new Set(["package-lock.json", "npm-shrinkwrap.json"]);

const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

export function installError(install) {
  if (!isObject(install)) return "install must be an object";
  const extra = Object.keys(install).filter((k) => k !== "manager" && k !== "lockfile");
  if (extra.length) return `install holds an unknown key: ${extra.join(", ")}`;
  if (install.manager !== "npm") return "install.manager must be npm";
  const lock = install.lockfile;
  if (typeof lock !== "string" || lock === "") return "install.lockfile is required";
  if (path.posix.isAbsolute(lock) || lock.includes("\\") || lock.split("/").includes("..")) {
    return `install.lockfile "${lock}" must be a repo-relative path`;
  }
  if (!LOCKFILES.has(path.posix.basename(lock))) return `install.lockfile "${lock}" is not an npm lockfile`;
  return "";
}

function entriesOf(record) {
  const out = [];
  if (isObject(record?.requires)) {
    for (const list of Object.values(record.requires)) if (Array.isArray(list)) out.push(...list);
  }
  if (Array.isArray(record?.gates)) {
    for (const gate of record.gates) if (Array.isArray(gate?.requires)) out.push(...gate.requires);
  }
  return out.filter(isObject);
}

export function listInstalls(root, warn = () => {}) {
  const byDir = new Map();
  for (const rel of RECORD_DIRS) {
    const dir = path.join(root, rel);
    if (!existsSync(dir) || !statSync(dir).isDirectory()) continue;
    for (const file of readdirSync(dir).filter((f) => f.endsWith(".yaml")).sort()) {
      const where = `${rel}/${file}`;
      const text = readFileSync(path.join(dir, file), "utf8");
      if (!/^\s*(- )?install:/m.test(text)) continue;
      let record;
      try {
        record = parse(text);
      } catch (err) {
        warn(`${where}: not read (${err.message}); its install entries are skipped`);
        continue;
      }
      for (const entry of entriesOf(record)) {
        if (!("install" in entry)) continue;
        const name = typeof entry.name === "string" ? entry.name : "(unnamed)";
        const error = installError(entry.install);
        if (error) {
          warn(`${where}: ${name}: ${error}; skipped`);
          continue;
        }
        const lockfile = entry.install.lockfile;
        if (!existsSync(path.join(root, lockfile))) {
          warn(`${where}: ${name}: ${lockfile} does not exist; skipped`);
          continue;
        }
        const lockDir = path.posix.dirname(lockfile);
        const seen = byDir.get(lockDir);
        if (seen) {
          if (!seen.names.includes(name)) seen.names.push(name);
        } else {
          byDir.set(lockDir, { dir: lockDir, names: [name], lockfile });
        }
      }
    }
  }
  return [...byDir.values()];
}

export function main(argv, out = {}) {
  const stdout = out.stdout ?? ((s) => process.stdout.write(`${s}\n`));
  const stderr = out.stderr ?? ((s) => process.stderr.write(`${s}\n`));
  const [mode, root, ...rest] = argv;
  if (mode !== "list" || !root || rest.length || !existsSync(root)) {
    stderr("usage: provision-prerequisites.mjs list <repo-root>");
    return 2;
  }
  for (const { dir, names, lockfile } of listInstalls(root, (m) => stderr(`provision-prerequisites: ${m}`))) {
    stdout([dir, names.join(", "), lockfile].join("\t"));
  }
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
