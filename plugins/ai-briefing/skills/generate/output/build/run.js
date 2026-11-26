import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const RULE = "=".repeat(70);

function step(label, script, args = []) {
  const start = Date.now();
  console.log(`\n${RULE}\n${label}\n${RULE}`);
  const r = spawnSync(process.execPath, [path.join(__dirname, script), ...args], {
    stdio: "inherit",
    cwd: __dirname,
  });
  const ms = Date.now() - start;
  console.log(`  → ${label} done in ${ms}ms (exit ${r.status})`);
  return r.status === 0;
}

const VALUE_FLAGS = new Set(["--meeting-n", "--briefing", "--date", "--out"]);

function parseFlags(argv) {
  const flags = { skipEmit: false, skipValidate: false };
  const passthrough = [];
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--skip-emit") flags.skipEmit = true;
    else if (a === "--skip-validate") flags.skipValidate = true;
    else {
      passthrough.push(a);
      if (VALUE_FLAGS.has(a)) passthrough.push(argv[++i]);
    }
  }
  return { flags, passthrough };
}

const { flags, passthrough } = parseFlags(process.argv);

const tasks = [
  !flags.skipEmit && ["EMIT slides-data.js", "emit-slides-data.js", passthrough],
  ["BUILD pptx", "build-pptx.js"],
  ["BUILD html", "build-html.js"],
  ["BUILD pdf", "build-pdf.js"],
  !flags.skipValidate && ["VALIDATE deck (quality gates)", "validate.js"],
].filter(Boolean);

for (const [label, script, args] of tasks) {
  if (!step(label, script, args)) {
    console.error(`\n${label} FAILED. Aborting.`);
    process.exit(1);
  }
}

console.log(`\n${RULE}`);
console.log("PIPELINE GREEN — deck ready.");
console.log(RULE);
