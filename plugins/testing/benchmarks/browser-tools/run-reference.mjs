#!/usr/bin/env node
// Proves every case is solvable and its grader is wired, using plain CDP (lib/cdp.mjs) rather than
// either tool under test. Run before scoring any tool: a case whose reference fails is broken.
//
//   node run-reference.mjs [--base http://127.0.0.1:4400] [--delay 1500]

import { mkdtempSync, writeFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { launch } from "./lib/cdp.mjs";
import { fixtures, tasks } from "./lib/cases.mjs";

const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i > 0 ? process.argv[i + 1] : d; };
const base = arg("base", "http://127.0.0.1:4400");
const delay = Number(arg("delay", 1500));
const work = mkdtempSync(join(tmpdir(), "bt-refrun-"));
const uploadFile = join(work, "receipt.txt");
writeFileSync(uploadFile, "receipt for benchmark upload\n");
const uploadSize = statSync(uploadFile).size;

const state = async (run) => (await fetch(`${base}/__state?run=${run}`)).json();
const results = [];

async function one(kind, id, variant, fn, grade) {
  const run = `ref-${id}${variant ? `-${variant}` : ""}-${Date.now().toString(36)}`;
  const ctx = { base, run, delay, variant, uploadFile, uploadSize, nonce: run.slice(-4), out: work };
  const b = await launch({ downloadDir: work });
  let answer = "", error;
  try {
    answer = (await fn(b, ctx)) ?? "";
    await new Promise((r) => setTimeout(r, 500));
  } catch (e) {
    error = e.message;
  } finally {
    await b.close();
  }
  const g = grade(await state(run), String(answer), ctx);
  const pass = typeof g === "object" ? g.pass : g;
  results.push({ kind, id, variant, pass, error });
  console.log(`${pass ? "PASS" : "FAIL"} ${kind} ${id}${variant ? ` ${variant}` : ""}${error ? `  (${error})` : ""}`);
}

for (const f of fixtures) {
  for (const v of f.variants ?? [undefined]) {
    await one("L1", f.id, v, (b, c) => f.reference(b.page, { ...c, url: `${base}/f/${f.path}?run=${c.run}&delay=${delay}${v ? `&variant=${v}` : ""}` }, b), f.grade);
  }
}
for (const t of tasks.filter((t) => t.reference)) await one("L2", t.id, undefined, (b, c) => t.reference(b, c), (s, a, c) => t.grade(s, a, c, []));

const failed = results.filter((r) => !r.pass);
console.log(`\n${results.length - failed.length}/${results.length} reference solutions pass`);
process.exit(failed.length ? 1 : 0);
