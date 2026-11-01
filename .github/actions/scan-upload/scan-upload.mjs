#!/usr/bin/env node
// The pre-upload leak scan for lane and eval artifacts: scanLeak from
// lib/publish-gate.mjs, the rule set the read runner's leak-scan step uses,
// over every file an upload is about to send, its relative name included.
// A credential format or a hidden assignment withholds the upload; the broad
// assignment label only warns. A link, a non-regular file, a glob or `!`
// entry, a compressed file (whose bytes the scan cannot read) or an
// unreadable path is a fault, which withholds it too. Nothing it prints
// carries a matched value or a file name.
//
//   SCAN_PATHS=<the upload's path input> scan-upload.mjs
// Writes clean=true to GITHUB_OUTPUT only when every file was judged clean.
// Exit 0 clean, 1 withheld.

import { appendFileSync, lstatSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { scanLeak, WARN_ONLY } from "../../../lib/publish-gate.mjs";

const COMPRESSED = [Buffer.from([0x1f, 0x8b]), Buffer.from("PK\x03\x04", "latin1"), Buffer.from("(\xb5/\xfd", "latin1")];

/**
 * Every file under each of `entries` (the upload's path lines), judged by
 * scanLeak. Returns `{ withheld: {label, credential} | null, warned, files }`.
 */
export function scanPaths(entries) {
  let warned = false;
  let files = 0;
  const withhold = (label, credential = false) => ({ withheld: { label, credential }, warned, files });
  const judge = (bytes) => {
    const { block, credential, warn } = scanLeak(bytes);
    if (block) return { label: block, credential };
    warned ||= Boolean(warn);
    return null;
  };
  const walk = (at, name) => {
    let stat;
    try {
      stat = lstatSync(at);
    } catch {
      return { label: "a path the scan cannot read" };
    }
    if (stat.isSymbolicLink()) return { label: "a link, which the upload would follow" };
    if (stat.isDirectory()) {
      for (const child of readdirSync(at).sort()) {
        const hit = walk(path.join(at, child), name ? `${name}/${child}` : child);
        if (hit) return hit;
      }
      return null;
    }
    if (!stat.isFile()) return { label: "a file that is not a regular file" };
    files += 1;
    const bytes = readFileSync(at);
    if (COMPRESSED.some((magic) => bytes.subarray(0, magic.length).equals(magic))) {
      return { label: "a compressed file, whose bytes the scan cannot read" };
    }
    return judge(Buffer.from(name, "utf8")) ?? judge(bytes);
  };
  for (const line of entries) {
    const entry = line.trim();
    if (entry === "") continue;
    if (entry.startsWith("!") || /[*?[\]{}]/.test(entry)) return withhold("a glob or exclude pattern, which the scan cannot follow");
    let exists = true;
    try {
      lstatSync(entry);
    } catch {
      exists = false;
    }
    // A missing path uploads nothing; the upload's if-no-files-found decides it.
    if (!exists) continue;
    const hit = walk(entry, lstatSync(entry).isDirectory() ? "" : path.basename(entry));
    if (hit) return { withheld: hit, warned, files };
  }
  return { withheld: null, warned, files };
}

export function main(env = process.env) {
  const entries = String(env.SCAN_PATHS ?? "").split(/\r?\n/);
  let result;
  try {
    result = scanPaths(entries);
  } catch (error) {
    result = { withheld: { label: `no finished scan (${error.name})`, credential: false }, warned: false, files: 0 };
  }
  const { withheld, warned, files } = result;
  if (withheld) {
    process.stdout.write(
      `::error::scan-upload: ${withheld.label}; nothing is uploaded${withheld.credential ? ". Rotate this credential" : ""}\n`,
    );
    return 1;
  }
  if (warned) process.stdout.write(`::warning::scan-upload: ${WARN_ONLY} in an upload file; not blocking, check it is no real credential\n`);
  if (env.GITHUB_OUTPUT) appendFileSync(env.GITHUB_OUTPUT, "clean=true\n");
  process.stdout.write(`scan-upload: ${files} file(s) clean\n`);
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main();
}
