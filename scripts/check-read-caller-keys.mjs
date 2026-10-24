// The check behind scripts/check-read-caller-keys.sh, which states the rule
// and the exit contract. Parses every workflow under .github/workflows/, builds
// the call graph of this repository's workflows, and checks every parsed key and
// string value of every file of every run that can reach the read workflow.
import { readdirSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const WORKFLOWS = ".github/workflows";
const READ_WORKFLOW = `${WORKFLOWS}/pr-run-activity-read.yml`;
// The one job of the read workflow that may name id-token. It runs no PR head
// code, so it may only check out the default branch tip.
const CHECK_JOB = "broker-check";
const TIP_REF = "${{ github.event.repository.default_branch }}";
const REPOSITORY = "melodic-software/claude-code-plugins";
// A job-level `uses:` naming one of this repository's workflows, in local
// (`./`) or remote (`owner/repo/...@ref`) form.
const WORKFLOW_USES = new RegExp(
  `^(?:\\./|${REPOSITORY}/)\\.github/workflows/([^/@\\s]+\\.ya?ml)(?:@\\S+)?$`,
  "i",
);
const APP_KEY = /automation_lanes_app_private_key|app-private-key/i;
const APP_KEY_INPUTS = new Set(["app-private-key", "private-key"]);
// Secrets a read run may name, compared lower-cased with `-` read as `_`.
// pr_unblock_claude_code_oauth_token is the pr-unblock role's Claude Code OAuth
// token, the same kind of credential as claude_code_oauth_token under the
// role's name; pr-unblock.yml's fix-ci-subscription read job runs on it.
// claude_api_key and pr_unblock_claude_api_key are the role's Claude Console
// API key, which fix-ci's first read job runs on.
const ALLOWED_SECRETS = new Set([
  "claude_code_oauth_token",
  "pr_unblock_claude_code_oauth_token",
  "issue_lane_claude_code_oauth_token",
  "claude_api_key",
  "pr_unblock_claude_api_key",
  "github_token",
]);
const KEY = "references the App key";
// The one other secret a read run may name: the scan-carrier private key. In
// the read workflow, only as the private-key input of the scan job's step that
// uses open-lane-output (and its workflow_call declaration, a key); in a
// caller, only as the scan-carrier-private-key entry of the secrets map of a
// job that calls the read workflow. The one environment, only on that job.
const CARRIER_JOB = "scan";
const CARRIER_SECRET = "scan_carrier_private_key";
const CARRIER_VALUE = "${{ secrets.scan-carrier-private-key }}";
const CARRIER_INPUT = "scan-carrier-private-key";
const CARRIER_PASS = "${{ secrets.SCAN_CARRIER_PRIVATE_KEY }}";
const CARRIER_ACTION = "./.base/.github/actions/open-lane-output";
const CARRIER_ENVIRONMENT = "pr-pipeline-scan-carrier";

const root = path.resolve(import.meta.dirname, "..");

function environmentError(message) {
  process.stderr.write(`check-read-caller-keys: ${message}\n`);
  process.exit(2);
}

let yaml;
try {
  const requireFrom = createRequire(
    path.join(root, ".github/standards/runner-policy/package.json"),
  );
  yaml = await import(pathToFileURL(requireFrom.resolve("yaml")).href);
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
const byLowerName = new Map(names.map((name) => [name.toLowerCase(), name]));

function callee(uses) {
  const match =
    typeof uses === "string" ? WORKFLOW_USES.exec(uses.trim()) : null;
  const name = match && byLowerName.get(match[1].toLowerCase());
  return name ? `${WORKFLOWS}/${name}` : null;
}

for (const name of names.sort()) {
  const file = `${WORKFLOWS}/${name}`;
  const lineCounter = new yaml.LineCounter();
  const doc = yaml.parseDocument(readFileSync(path.join(root, file), "utf8"), {
    lineCounter,
    uniqueKeys: false,
  });
  let callees = [];
  if (doc.errors.length > 0) {
    offenders.push(
      `${file}: does not parse as YAML, so its calls cannot be checked`,
    );
  } else {
    const jobs = doc.toJS()?.jobs;
    callees = Object.values(jobs && typeof jobs === "object" ? jobs : {})
      .map((job) => callee(job?.uses))
      .filter(Boolean);
  }
  files.set(file, { doc, lineCounter, callees });
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

// Every `${{ ... }}` in a string, with its start offset. A `}}` inside a
// quoted string literal does not close the expression; an unclosed one runs
// to the end of the string.
function expressions(text) {
  const found = [];
  let at = text.indexOf("${{");
  while (at !== -1) {
    let i = at + 3;
    let quoted = false;
    while (i < text.length && (quoted || !text.startsWith("}}", i))) {
      if (text[i] === "'") {
        quoted = !quoted;
      }
      i += 1;
    }
    found.push([at, text.slice(at + 3, i)]);
    at = text.indexOf("${{", i + 2);
  }
  return found;
}

// What an expression does with the secrets context that a read run may not.
// carrier: the expression is the scan-carrier input's whole value.
function secretFindings(expression, carrier = false) {
  const code = expression.replace(/'(?:[^']|'')*'/g, "''");
  const findings = [];
  for (const match of code.matchAll(/(?<![\w.-])secrets\b/gi)) {
    const rest = code.slice(match.index + match[0].length);
    const before = code.slice(0, match.index);
    const named = /^\s*\.\s*([A-Za-z_][\w-]*)/.exec(rest);
    if (named) {
      const name = named[1];
      if (APP_KEY.test(name)) {
        findings.push(KEY);
      } else if (name.toLowerCase().replaceAll("-", "_") === CARRIER_SECRET) {
        if (!carrier) {
          findings.push(
            `reads secrets.${name} outside the read workflow's ${CARRIER_JOB}-job open-lane-output private-key input and the ${CARRIER_INPUT} entry a read-workflow call passes`,
          );
        }
      } else if (
        !ALLOWED_SECRETS.has(name.toLowerCase().replaceAll("-", "_"))
      ) {
        findings.push(
          `reads secrets.${name}, which is not on the read-run allowlist`,
        );
      }
    } else if (/^\s*\[/.test(rest)) {
      findings.push("reads a secret by a computed name");
    } else if (/tojson\s*\(\s*$/i.test(before) && /^\s*\)/.test(rest)) {
      findings.push("reads every secret through toJSON(secrets)");
    } else {
      findings.push("reads the secrets context as a whole");
    }
  }
  return findings;
}

// The read workflow's check job node, or null. Only offsets inside its range
// may name id-token.
function checkJobOf(file, doc) {
  if (file !== READ_WORKFLOW) {
    return null;
  }
  const node = doc.getIn(["jobs", CHECK_JOB], true);
  return yaml.isMap(node) ? node : null;
}

// The read workflow's scan-job open step's private-key pair, when there is
// exactly one such step and its value is exactly the carrier secret.
function carrierPairOf(file, doc) {
  if (file !== READ_WORKFLOW) {
    return null;
  }
  const steps = doc.getIn(["jobs", CARRIER_JOB, "steps"], true);
  const pairs = [];
  for (const step of yaml.isSeq(steps) ? steps.items : []) {
    if (
      !yaml.isMap(step) ||
      String(step.get("uses") ?? "").trim() !== CARRIER_ACTION
    ) {
      continue;
    }
    const inputs = step.get("with", true);
    for (const pair of yaml.isMap(inputs) ? inputs.items : []) {
      if (
        yaml.isScalar(pair.key) &&
        pair.key.value === "private-key" &&
        yaml.isScalar(pair.value) &&
        pair.value.value === CARRIER_VALUE
      ) {
        pairs.push(pair);
      }
    }
  }
  return pairs.length === 1 ? pairs[0] : null;
}

// In any file, the scan-carrier-private-key pairs of the secrets map of a job
// that calls the read workflow, valued exactly CARRIER_PASS.
function carrierPassesOf(doc) {
  const passes = new Set();
  const jobs = doc.get("jobs", true);
  for (const job of yaml.isMap(jobs) ? jobs.items : []) {
    if (!yaml.isMap(job.value) || callee(job.value.get("uses")) !== READ_WORKFLOW) {
      continue;
    }
    const secrets = job.value.get("secrets", true);
    for (const pair of yaml.isMap(secrets) ? secrets.items : []) {
      if (
        yaml.isScalar(pair.key) &&
        pair.key.value === CARRIER_INPUT &&
        yaml.isScalar(pair.value) &&
        pair.value.value === CARRIER_PASS
      ) {
        passes.add(pair.value);
      }
    }
  }
  return passes;
}

const CHECKOUT_WITH = new Set(["ref", "path", "persist-credentials"]);

// The read workflow's shape: an empty top-level grant, an explicit
// permissions map on every job, and a broker-check job made of steps whose
// checkouts can only fetch this repository's default branch tip.
function checkReadShape(file, doc, lineCounter) {
  const lineOf = (node) =>
    node?.range ? lineCounter.linePos(node.range[0]).line : 1;
  const top = doc.get("permissions", true);
  if (!yaml.isMap(top) || top.items.length > 0) {
    offenders.push(
      `${file}:${lineOf(top)}: the read workflow's top-level permissions is not {}`,
    );
  }
  const jobs = doc.get("jobs", true);
  for (const pair of yaml.isMap(jobs) ? jobs.items : []) {
    if (
      !yaml.isMap(pair.value) ||
      !yaml.isMap(pair.value.get("permissions", true))
    ) {
      offenders.push(
        `${file}:${lineOf(pair.key)}: job ${pair.key?.value} has no explicit permissions map`,
      );
    }
  }
  const job = checkJobOf(file, doc);
  if (!job) {
    return;
  }
  const steps = job.get("steps", true);
  if (job.has("uses") || !yaml.isSeq(steps)) {
    offenders.push(
      `${file}:${lineOf(job)}: the ${CHECK_JOB} job must be steps, not a reusable-workflow call`,
    );
  }
  for (const step of yaml.isSeq(steps) ? steps.items : []) {
    const value = step?.toJSON?.();
    if (
      typeof value?.uses !== "string" ||
      !/^actions\/checkout@/i.test(value.uses.trim())
    ) {
      continue;
    }
    const withKeys = Object.keys(value.with ?? {});
    if (
      value.with?.ref !== TIP_REF ||
      withKeys.some((key) => !CHECKOUT_WITH.has(key))
    ) {
      offenders.push(
        `${file}:${lineOf(step)}: the ${CHECK_JOB} job checks out something other than this repository's default branch tip`,
      );
    }
  }
}

function check(file) {
  const { doc, lineCounter } = files.get(file);
  const checkJob = checkJobOf(file, doc);
  const carrierPair = carrierPairOf(file, doc);
  const carrierPasses = carrierPassesOf(doc);
  const carrierEnvironment =
    file === READ_WORKFLOW
      ? doc.getIn(["jobs", CARRIER_JOB], true)?.get?.("environment", true)
      : null;
  if (file === READ_WORKFLOW) {
    checkReadShape(file, doc, lineCounter);
  }
  const inCheckJob = (offset) =>
    checkJob !== null &&
    offset >= checkJob.range[0] &&
    offset < checkJob.range[2];
  const idTokenFinding = `the read workflow names id-token outside its ${CHECK_JOB} job`;
  const lineAt = (node, value, index) => {
    const start = lineCounter.linePos(node.range[0]).line;
    const block = node.type === "BLOCK_LITERAL" || node.type === "BLOCK_FOLDED";
    return (
      start +
      (block ? 1 : 0) +
      (value.slice(0, index).match(/\n/g)?.length ?? 0)
    );
  };
  const report = (line, what) =>
    offenders.push(
      `${file}:${line}: ${what} in a run that reaches ${READ_WORKFLOW}`,
    );
  yaml.visit(doc, {
    Pair(_, pair) {
      const key = yaml.isScalar(pair.key) ? String(pair.key.value).trim() : "";
      const keyLine = pair.key?.range
        ? lineCounter.linePos(pair.key.range[0]).line
        : 0;
      if (APP_KEY_INPUTS.has(key.toLowerCase()) && pair !== carrierPair) {
        report(keyLine, KEY);
      }
      if (
        key === "environment" &&
        !(
          pair.value === carrierEnvironment &&
          yaml.isScalar(pair.value) &&
          pair.value.value === CARRIER_ENVIRONMENT
        )
      ) {
        report(
          keyLine,
          `names an environment other than ${CARRIER_ENVIRONMENT} on the read workflow's ${CARRIER_JOB} job`,
        );
      }
      if (
        key === "secrets" &&
        yaml.isScalar(pair.value) &&
        String(pair.value.value).trim().toLowerCase() === "inherit"
      ) {
        report(
          lineCounter.linePos(pair.value.range[0]).line,
          "passes secrets: inherit",
        );
      }
      if (
        key === "permissions" &&
        yaml.isScalar(pair.value) &&
        String(pair.value.value).trim().toLowerCase() === "write-all"
      ) {
        report(
          lineCounter.linePos(pair.value.range[0]).line,
          "grants permissions: write-all",
        );
      }
      if (
        file === READ_WORKFLOW &&
        /id-token/i.test(key) &&
        !inCheckJob(pair.key.range[0])
      ) {
        offenders.push(`${file}:${keyLine}: ${idTokenFinding}`);
      }
    },
    Scalar(_, node) {
      if (typeof node.value !== "string" || !node.range) {
        return;
      }
      const text = node.value;
      const keyHit = APP_KEY.exec(text);
      if (keyHit) {
        report(lineAt(node, text, keyHit.index), KEY);
      }
      for (const [at, expression] of expressions(text)) {
        const carrier =
          (node === carrierPair?.value && text === CARRIER_VALUE) ||
          carrierPasses.has(node);
        for (const what of secretFindings(expression, carrier)) {
          report(lineAt(node, text, at), what);
        }
      }
      const idToken = /id-token/i.exec(text);
      if (file === READ_WORKFLOW && idToken && !inCheckJob(node.range[0])) {
        offenders.push(
          `${file}:${lineAt(node, text, idToken.index)}: ${idTokenFinding}`,
        );
      }
    },
  });
}

for (const file of [...runFiles].sort()) {
  if (files.has(file)) {
    check(file);
  }
}

if (offenders.length === 0) {
  process.stdout.write(
    `check-read-caller-keys: no run that reaches ${READ_WORKFLOW} references the App key (${callers.size} caller(s)).\n`,
  );
  process.exit(0);
}
const unique = [...new Set(offenders)].sort();
process.stderr.write(`${unique.join("\n")}\n`);
process.stderr.write(
  `check-read-caller-keys: ${unique.length} offender(s); a run that reaches the read workflow references no App key and passes no secret it cannot name, and a lane mixing read and write activities waits for the token broker (see the header of scripts/check-read-caller-keys.sh).\n`,
);
process.exit(1);
