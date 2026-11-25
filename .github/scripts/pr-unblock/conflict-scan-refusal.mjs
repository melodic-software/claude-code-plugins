#!/usr/bin/env node

import { appendFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import { need, scanRefusal } from "./address-feedback.mjs";

export function main(env, { log = (line) => console.log(line) } = {}) {
  need(env, ["GITHUB_OUTPUT"]);
  const refused = scanRefusal({ dir: env.SCAN_REFUSED_DIR ?? "", read: env.SCAN_REFUSED_READ ?? "" });
  const reason = refused === "" ? "" : "unresolved-conflict";
  appendFileSync(env.GITHUB_OUTPUT, `escalation-reason=${reason}\n`);
  log(refused === "" ? "the scan refused nothing" : `the scan refused the model call's ${refused}: ${reason}`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    process.exitCode = main(process.env);
  } catch (error) {
    console.log(`::error::conflict-scan-refusal failed: ${error.message}`);
    process.exitCode = 1;
  }
}
