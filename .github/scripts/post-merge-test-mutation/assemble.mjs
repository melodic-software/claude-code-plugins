#!/usr/bin/env node
// post-merge-test-mutation.yml's report job: the audit's result from the mutate
// job's executed mutants and the triage leg's verdicts, in result.schema.json's
// shape. Every state comes from the executor; triage adds only a survivor's
// disposition and cause, by index, and a survivor it gave none is
// `unclassified`. Both inputs are checked against their schemas. No model
// runs here.
//
//   assemble.mjs <executed.json> [<triage.json>]
//
// Prints the result as JSON; exits 1 when the executed file is missing or
// malformed, or a survivor exists and the triage file does not.
import { existsSync, readFileSync } from "node:fs";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { SCHEMA, violations } from "./report.mjs";

const TRIAGE_SCHEMA = JSON.parse(readFileSync(new URL("./triage.schema.json", import.meta.url), "utf8"));
const EXECUTED_SCHEMA = structuredClone(SCHEMA);
Object.assign(EXECUTED_SCHEMA.properties.mutants.items, {
  required: ["path", "line", "operator", "state", "old_string", "new_string"],
  properties: {
    ...Object.fromEntries(Object.entries(SCHEMA.properties.mutants.items.properties).filter(([k]) => !["disposition", "cause"].includes(k))),
    old_string: { type: "string", maxLength: 2000 },
    new_string: { type: "string", maxLength: 2000 },
  },
});

export function assemble(executed, triage) {
  const bad = violations(executed, EXECUTED_SCHEMA);
  if (bad.length) throw new Error(`the executed mutants do not match their schema (${bad[0]})`);
  const survivors = executed.mutants.some((m) => m.state === "survived");
  if (survivors && triage === null) throw new Error("survivors ran but no triage result was kept");
  const verdicts = new Map();
  if (triage !== null) {
    const badTriage = violations(triage, TRIAGE_SCHEMA);
    if (badTriage.length) throw new Error(`the triage result does not match its schema (${badTriage[0]})`);
    for (const v of triage.verdicts) if (!verdicts.has(v.index)) verdicts.set(v.index, v);
  }
  return {
    outcome: executed.outcome,
    detail: executed.detail,
    mutants: executed.mutants.map(({ path, line, operator, state }, index) => {
      if (state !== "survived") return { path, line, operator, state, disposition: "none", cause: "none" };
      const v = verdicts.get(index);
      if (!v) return { path, line, operator, state, disposition: "unclassified", cause: "unclassified" };
      return { path, line, operator, state, disposition: v.disposition, cause: v.disposition === "productive" ? v.cause : "none" };
    }),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [executedFile, triageFile] = process.argv.slice(2);
  try {
    const executed = JSON.parse(readFileSync(executedFile, "utf8"));
    const triage = triageFile && existsSync(triageFile) ? JSON.parse(readFileSync(triageFile, "utf8")) : null;
    console.log(JSON.stringify(assemble(executed, triage)));
  } catch (error) {
    console.error(`assemble: ${error.message}`);
    process.exit(1);
  }
}
