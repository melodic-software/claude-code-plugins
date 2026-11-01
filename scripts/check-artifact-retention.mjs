// The check behind scripts/check-artifact-retention.sh, which states the
// matching rule and the exit contract.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const TABLE = ".github/artifact-retention.json";
const SCHEMA = ".github/artifact-retention.schema.json";
const MAX_DAYS = 90;
const UPLOAD = /^actions\/upload-artifact@/;
const HOW =
  "add or fix its row in .github/artifact-retention.json (key, retention-days, readers, reason) and set the same retention-days on the step";

const root = path.resolve(import.meta.dirname, "..");

function environmentError(message) {
  process.stderr.write(`check-artifact-retention: ${message}\n`);
  process.exit(2);
}

let yaml;
let Ajv2020;
try {
  const requireFrom = createRequire(
    path.join(root, ".github/standards/runner-policy/package.json"),
  );
  yaml = await import(pathToFileURL(requireFrom.resolve("yaml")).href);
  Ajv2020 = requireFrom("ajv/dist/2020").default;
} catch {
  environmentError(
    "the yaml and ajv packages are not installed; run npm ci --prefix .github/standards/runner-policy",
  );
}

let table;
let schema;
try {
  table = JSON.parse(readFileSync(path.join(root, TABLE), "utf8"));
  schema = JSON.parse(readFileSync(path.join(root, SCHEMA), "utf8"));
} catch (error) {
  environmentError(`cannot read ${TABLE} or ${SCHEMA}: ${error.message}`);
}

const findings = [];
const validate = new Ajv2020({ allErrors: true, strict: true }).compile(schema);
if (!validate(table)) {
  for (const error of validate.errors) {
    findings.push(`${TABLE}: schema: ${error.instancePath || "/"} ${error.message}`);
  }
  report();
}

const families = table.families;
const COMPUTED = /^\$\{\{\s*steps\.[A-Za-z0-9_-]+\.outputs\.retention-days\s*\}\}$/;
const days = (value) => (value === "max" ? MAX_DAYS : value);
const said = (value) => (value === "max" ? `max (${MAX_DAYS})` : String(value));
const pathOf = (reader) => reader.split(/\s/, 1)[0].replace(/:\d+(-\d+)?$/, "");

for (const [key, row] of Object.entries(families)) {
  const readerPaths = row.readers.map(pathOf);
  for (const reader of readerPaths) {
    if (!existsSync(path.join(root, reader))) {
      findings.push(`${TABLE}: family \`${key}\` reader ${reader} names no file`);
    }
  }
  if (row["computed-by"] !== undefined && !existsSync(path.join(root, row["computed-by"]))) {
    findings.push(`${TABLE}: family \`${key}\` computed-by ${row["computed-by"]} names no file`);
  }
  if (row["retention-days"] === "max") {
    const maxReader = row["max-reader"];
    if (maxReader === undefined) {
      findings.push(`${TABLE}: family \`${key}\` says max with no max-reader, the reader that needs ${MAX_DAYS} days`);
    } else if (!readerPaths.includes(pathOf(maxReader))) {
      findings.push(`${TABLE}: family \`${key}\` max-reader ${maxReader} is none of its readers`);
    }
  }
}

// A leak-scan step earlier in the same steps: { id, path } for a
// .github/actions/scan-upload step or a run step calling its script, with the
// path it scans; { id: "leak-scan" } for the read runner's own scan.
const SCAN_ACTION = /(?:^|\/)\.github\/actions\/scan-upload$/;
function scanOf(step) {
  const id = step.get("id");
  if (typeof id !== "string") return null;
  if (id === "leak-scan") return { id };
  if (SCAN_ACTION.test(String(step.get("uses") ?? ""))) return { id, path: step.get("with", true)?.get?.("path") };
  if (/scan-upload\/scan-upload\.mjs/.test(String(step.get("run") ?? ""))) return { id, path: step.get("env", true)?.get?.("SCAN_PATHS") };
  return null;
}

// Every upload step: { file, line, job, name, retention, path, condition, scans }.
const steps = [];
const lineCounterFor = new Map();
function collect(file, stepSeqs) {
  for (const [job, seq] of stepSeqs) {
    if (!yaml.isSeq(seq)) continue;
    for (const step of seq.items) {
      if (!yaml.isMap(step)) continue;
      const uses = step.get("uses");
      if (typeof uses !== "string" || !UPLOAD.test(uses)) continue;
      const withMap = step.get("with", true);
      const input = (key) => (yaml.isMap(withMap) ? withMap.get(key) : undefined);
      const index = seq.items.indexOf(step);
      steps.push({
        file,
        line: lineCounterFor.get(file).linePos(step.range[0]).line,
        job,
        name: input("name"),
        retention: input("retention-days"),
        path: input("path"),
        condition: String(step.get("if") ?? ""),
        scans: seq.items.slice(0, index).filter(yaml.isMap).map(scanOf).filter(Boolean),
      });
    }
  }
}

const files = [];
for (const dir of [".github/workflows"]) {
  for (const name of readdirSync(path.join(root, dir)).sort()) {
    if (/\.ya?ml$/.test(name)) files.push({ file: `${dir}/${name}`, kind: "workflow" });
  }
}
const actionsDir = path.join(root, ".github/actions");
if (existsSync(actionsDir)) {
  for (const name of readdirSync(actionsDir).sort()) {
    for (const leaf of ["action.yml", "action.yaml"]) {
      if (existsSync(path.join(actionsDir, name, leaf))) {
        files.push({ file: `.github/actions/${name}/${leaf}`, kind: "action" });
      }
    }
  }
}

for (const { file, kind } of files) {
  const lineCounter = new yaml.LineCounter();
  lineCounterFor.set(file, lineCounter);
  const doc = yaml.parseDocument(readFileSync(path.join(root, file), "utf8"), { lineCounter });
  if (doc.errors.length > 0) {
    findings.push(`${file}:${doc.errors[0].linePos?.[0]?.line ?? 1}: does not parse, so its uploads cannot be checked`);
    continue;
  }
  if (kind === "workflow") {
    const jobs = doc.get("jobs");
    if (yaml.isMap(jobs)) {
      collect(file, jobs.items.map((pair) => [String(pair.key?.value ?? pair.key), yaml.isMap(pair.value) ? pair.value.get("steps") : undefined]));
    }
  } else {
    collect(file, [["runs", doc.getIn(["runs", "steps"])]]);
  }
}

const computedJobs = new Set();
const used = new Set();
for (const step of steps) {
  const at = `${step.file}:${step.line}: upload`;
  if (typeof step.name !== "string" || step.name === "") {
    findings.push(`${at} sets no name, so no family can claim it; ${HOW}`);
    continue;
  }
  const label = `${at} \`${step.name}\``;
  const expression = step.name.indexOf("${{");
  let claimed = [];
  if (expression === -1) {
    if (Object.hasOwn(families, step.name)) claimed = [step.name];
  } else if (expression > 0) {
    const key = `${step.name.slice(0, expression)}*`;
    if (Object.hasOwn(families, key)) claimed = [key];
  } else {
    const job = `${step.file}#${step.job}`;
    computedJobs.add(job);
    claimed = Object.keys(families).filter((key) => (families[key].uploads ?? []).includes(job));
  }
  if (claimed.length === 0) {
    findings.push(`${label} matches no family in ${TABLE}; ${HOW}`);
    continue;
  }
  if (claimed.length > 1) {
    findings.push(`${label} is claimed by ${claimed.map((k) => `\`${k}\``).join(" and ")} in ${TABLE}`);
    continue;
  }
  const [key] = claimed;
  used.add(key);
  const scan = families[key].scan;
  const gated = (id) => step.condition.includes(`steps.${id}.outputs.clean == 'true'`);
  if (scan === "upload") {
    const viaLeakScan = step.scans.some((s) => s.id === "leak-scan") && String(step.path ?? "").includes("steps.leak-scan.outputs.dir") && gated("leak-scan");
    const viaScanStep = step.scans.some((s) => s.path !== undefined && String(s.path) === String(step.path ?? "") && gated(s.id));
    if (!viaLeakScan && !viaScanStep) {
      findings.push(
        `${label} has no scan before it; ${TABLE} family \`${key}\` says scan: upload, so a .github/actions/scan-upload step over the same path must come first and the upload's if: must require its clean output`,
      );
    }
  } else if (scan === "plaintext" && step.scans.length === 0) {
    findings.push(`${label} has no scan step before it; ${TABLE} family \`${key}\` says scan: plaintext`);
  }
  const want = families[key]["retention-days"];
  const raw = step.retention;
  if (raw === undefined || raw === null || raw === "") {
    findings.push(`${label} sets no retention-days; ${TABLE} family \`${key}\` says ${said(want)}`);
    continue;
  }
  if (families[key]["computed-by"] !== undefined && COMPUTED.test(String(raw))) {
    continue;
  }
  const value = typeof raw === "number" ? raw : /^\d+$/.test(String(raw)) ? Number(raw) : Number.NaN;
  if (!Number.isInteger(value)) {
    findings.push(`${label} retention-days is not a whole number of days: ${raw}; ${TABLE} family \`${key}\` says ${said(want)}`);
    continue;
  }
  if (value !== days(want)) {
    findings.push(`${label} keeps ${value} days; ${TABLE} family \`${key}\` says ${said(want)}`);
  }
}

for (const [key, row] of Object.entries(families)) {
  for (const job of row.uploads ?? []) {
    if (!computedJobs.has(job)) {
      findings.push(`${TABLE}: family \`${key}\` lists upload ${job}, which uploads no computed name`);
    }
  }
  if (!used.has(key)) {
    findings.push(`${TABLE}: family \`${key}\` matches no upload step; remove the row with the upload`);
  }
}

report();

function report() {
  if (findings.length === 0) {
    process.stdout.write(
      `check-artifact-retention: ${steps.length} upload step(s) match ${TABLE} (${Object.keys(families).length} families).\n`,
    );
    process.exit(0);
  }
  process.stderr.write(`${findings.join("\n")}\n`);
  process.stderr.write(
    `check-artifact-retention: ${findings.length} finding(s); every upload-artifact step sets the retention-days its family's row in ${TABLE} names (see the header of scripts/check-artifact-retention.sh).\n`,
  );
  process.exit(1);
}
