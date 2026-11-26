#!/usr/bin/env node
import { existsSync } from "node:fs";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { dataFiles, parseRecord, recordLines } from "../plugins/engineering-concepts/scripts/lookup.mjs";

const SKILL_OWNER = /^\/?([a-z0-9-]+):([a-z0-9-]+)$/u;

let values;
try {
  ({ values } = parseArgs({ options: { "data-dir": { type: "string" }, "plugins-dir": { type: "string" } } }));
} catch (e) {
  console.error(`check-engineering-concepts: ${e.message}`);
  process.exit(2);
}
const dataDir = values["data-dir"];
const pluginsDir = values["plugins-dir"];

let files = [];
try {
  files = dataFiles(dataDir);
} catch (e) {
  if (e.code !== "ENOENT") {
    console.error(`check-engineering-concepts: data directory unreadable: ${dataDir} (${e.code})`);
    process.exit(2);
  }
}

const findings = [];
const accepted = [];
for (const file of files) {
  const path = join(dataDir, file);
  for (const { line, text } of recordLines(path)) {
    const at = `${path}:${line}`;
    const { record, reason } = parseRecord(text);
    if (reason) findings.push(`${at}: ${reason}`);
    else accepted.push({ record, at });
  }
}

const idAt = new Map();
const claims = [];
for (const { record, at } of accepted) {
  const key = record.id.toLowerCase();
  if (idAt.has(key)) findings.push(`${at}: id "${record.id}" already has a record at ${idAt.get(key)}`);
  else idAt.set(key, at);
  claims.push({ kind: "name", at, owner: key, text: record.name });
  for (const alias of record.aliases ?? []) claims.push({ kind: "alias", at, owner: key, text: alias });

  const skill = SKILL_OWNER.exec(record.owner);
  if (skill) {
    const path = join(pluginsDir, skill[1], "skills", skill[2], "SKILL.md");
    if (!existsSync(path)) findings.push(`${at}: owner "${record.owner}" of "${record.id}" names no skill: ${path} does not exist`);
  }
}

const claimedBy = new Map();
for (const { kind, at, owner, text } of claims) {
  const key = text.toLowerCase();
  if (idAt.has(key) && owner !== key) findings.push(`${at}: ${kind} "${text}" is the id of another record`);
  const first = claimedBy.get(key);
  if (first === undefined) claimedBy.set(key, { owner, at });
  else if (first.owner !== owner) findings.push(`${at}: ${kind} "${text}" is also claimed by record "${first.owner}" at ${first.at}`);
}

for (const finding of findings) console.error(finding);
if (findings.length > 0) process.exit(1);
console.log(accepted.length);
