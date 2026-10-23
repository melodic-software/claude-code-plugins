#!/usr/bin/env node
// conflict-scan-refusal.mjs: resolve-conflicts's escalation when the read
// runner's scan refused the model call's output (a leak-scan block or an
// oversize patch). Such a scan hands no patch state on, so apply-conflict-patch
// never runs; this script, with no model and no head code, reads the
// scan-refusal job's markers (address-feedback.mjs scanRefusal) and writes
// escalation-reason=unresolved-conflict when any marker, or a failed download,
// says the scan refused. It reads no leg output: a forged marker only hands
// the round to a person. Head code on the run job's runner that takes the
// marker's artifact name first can suppress the escalation, a power it
// already holds by forging that job's handed-off output.
//
// Environment: GITHUB_OUTPUT, SCAN_REFUSED_DIR (every attempt's marker for
// the resolve-conflicts call), SCAN_REFUSED_READ (that download's outcome).

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
