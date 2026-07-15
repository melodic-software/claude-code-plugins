// Single entrypoint orchestrator: emit → build pptx → build html → build pdf → validate.
//
// Usage:
//   node run.js                     # full chain
//   node run.js --skip-emit         # rebuild from existing slides-data.js
//   node run.js --skip-validate     # skip quality gates (e.g. for fast preview)
//   node run.js --meeting-n 21      # forwarded to emit-slides-data.js
//   node run.js --briefing path     # forwarded to emit-slides-data.js
//   node run.js --date 2026-05-08   # forwarded to emit-slides-data.js
//
// Exit codes: 0 = all green, 1 = validation failed, 2 = build error.
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function step(label, script, args = []) {
  const start = Date.now();
  console.log(`\n${"=".repeat(70)}\n${label}\n${"=".repeat(70)}`);
  const r = spawnSync(process.execPath, [path.join(__dirname, script), ...args], {
    stdio: "inherit",
    cwd: __dirname,
  });
  const ms = Date.now() - start;
  console.log(`  → ${label} done in ${ms}ms (exit ${r.status})`);
  return r.status === 0;
}

function parseFlags(argv) {
  const flags = { skipEmit: false, skipValidate: false };
  const passthrough = [];
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--skip-emit") flags.skipEmit = true;
    else if (a === "--skip-validate") flags.skipValidate = true;
    else passthrough.push(a);
    // Some flags need their value argument too — handled by passing through
    if (a === "--meeting-n" || a === "--briefing" || a === "--date" || a === "--out") {
      passthrough.push(argv[++i]);
    }
  }
  return { flags, passthrough };
}

const { flags, passthrough } = parseFlags(process.argv);

const tasks = [];
if (!flags.skipEmit)     tasks.push(["EMIT slides-data.js",      "emit-slides-data.js", passthrough]);
tasks.push(["BUILD pptx",                                          "build-pptx.js",       []]);
tasks.push(["BUILD html",                                          "build-html.js",       []]);
tasks.push(["BUILD pdf",                                           "build-pdf.js",        []]);
if (!flags.skipValidate) tasks.push(["VALIDATE deck (quality gates)","validate.js",       []]);

let allOk = true;
for (const [label, script, args] of tasks) {
  const ok = step(label, script, args);
  if (!ok) {
    console.error(`\n${label} FAILED. Aborting.`);
    allOk = false;
    break;
  }
}

if (!allOk) process.exit(1);

console.log("\n" + "=".repeat(70));
console.log("PIPELINE GREEN — deck ready.");
console.log("=".repeat(70));
