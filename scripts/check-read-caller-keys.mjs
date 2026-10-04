// The check behind scripts/check-read-caller-keys.sh, which states the rule
// and the exit contract. Parses every workflow under .github/workflows/, builds
// the repository-local call graph, and checks every file of every run that can
// reach the read workflow.
import { readdirSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import process from "node:process";

const WORKFLOWS = ".github/workflows";
const READ_WORKFLOW = `${WORKFLOWS}/pr-run-activity-read.yml`;
const LOCAL_USES = /^\.\/\.github\/workflows\/([^/@\s]+\.ya?ml)$/;
// A run holding any of these may deliver the App key to its read job.
const FORBIDDEN = [
  [
    /AUTOMATION_LANES_APP_PRIVATE_KEY|app-private-key|private-key:/,
    "references the App key",
  ],
  [/secrets\s*:\s*inherit\b/, "passes secrets: inherit"],
  [/toJSON\s*\(\s*secrets\s*\)/i, "reads every secret through toJSON(secrets)"],
  [/secrets\s*\[/, "reads a secret by a computed name"],
];

const root = path.resolve(import.meta.dirname, "..");

function environmentError(message) {
  process.stderr.write(`check-read-caller-keys: ${message}\n`);
  process.exit(2);
}

let parse;
try {
  const requireFrom = createRequire(
    path.join(root, ".github/standards/runner-policy/package.json"),
  );
  ({ parse } = await import(requireFrom.resolve("yaml")));
} catch {
  environmentError(
    "the yaml package is not installed; run npm ci --prefix .github/standards/runner-policy",
  );
}

const offenders = [];
const files = new Map();
let names = [];
try {
  names = readdirSync(path.join(root, WORKFLOWS)).filter((name) =>
    /\.ya?ml$/.test(name),
  );
} catch {
  names = [];
}
for (const name of names.sort()) {
  const file = `${WORKFLOWS}/${name}`;
  const text = readFileSync(path.join(root, file), "utf8");
  let callees = [];
  try {
    const jobs = parse(text)?.jobs ?? {};
    callees = Object.values(jobs)
      .map((job) =>
        typeof job?.uses === "string" ? LOCAL_USES.exec(job.uses.trim()) : null,
      )
      .filter(Boolean)
      .map((match) => `${WORKFLOWS}/${match[1]}`);
  } catch {
    offenders.push(
      `${file}: does not parse as YAML, so its calls cannot be checked`,
    );
  }
  files.set(file, { text, callees });
}

const callersOf = (target) =>
  [...files]
    .filter(([, { callees }]) => callees.includes(target))
    .map(([file]) => file);

function walk(start, next) {
  const seen = new Set([start]);
  const queue = [start];
  while (queue.length > 0) {
    for (const file of next(queue.shift())) {
      if (!seen.has(file)) {
        seen.add(file);
        queue.push(file);
      }
    }
  }
  return seen;
}

const runFiles = new Set();
let callers = new Set();
if (!files.has(READ_WORKFLOW)) {
  offenders.push(
    `${READ_WORKFLOW}: missing; the read-caller key check has nothing to anchor on`,
  );
} else {
  // Up to every workflow whose run reaches the read workflow, then down
  // through every reusable workflow those runs call.
  callers = walk(READ_WORKFLOW, callersOf);
  callers.delete(READ_WORKFLOW);
  for (const file of [READ_WORKFLOW, ...callers]) {
    for (const reached of walk(file, (f) => files.get(f)?.callees ?? [])) {
      runFiles.add(reached);
    }
  }
}

const lines = (file) =>
  files
    .get(file)
    .text.split("\n")
    .map((line, index) => [index + 1, line])
    .filter(([, line]) => !/^\s*#/.test(line));

for (const file of [...runFiles].sort()) {
  if (!files.has(file)) {
    continue;
  }
  for (const [number, line] of lines(file)) {
    for (const [pattern, what] of FORBIDDEN) {
      if (pattern.test(line)) {
        offenders.push(
          `${file}:${number}: ${what} in a run that reaches ${READ_WORKFLOW}`,
        );
      }
    }
    if (file === READ_WORKFLOW && /id-token/.test(line)) {
      offenders.push(`${file}:${number}: the read workflow names id-token`);
    }
  }
}

if (offenders.length === 0) {
  process.stdout.write(
    `check-read-caller-keys: no run that reaches ${READ_WORKFLOW} references the App key (${callers.size} caller(s)).\n`,
  );
  process.exit(0);
}
process.stderr.write(`${[...new Set(offenders)].sort().join("\n")}\n`);
process.stderr.write(
  `check-read-caller-keys: ${offenders.length} offender(s); a run that reaches the read workflow references no App key and passes no secret it cannot name, and a lane mixing read and write activities waits for the token broker (see the header of scripts/check-read-caller-keys.sh).\n`,
);
process.exit(1);
