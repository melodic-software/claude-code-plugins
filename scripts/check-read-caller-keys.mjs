import { readdirSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const WORKFLOWS = ".github/workflows";
const READ_WORKFLOW = `${WORKFLOWS}/pr-run-activity-read.yml`;
const CHECK_JOB = "check-broker";
const TIP_REF = "${{ github.event.repository.default_branch }}";
const TIP_STEP_REF = "${{ steps.tip.outputs.sha }}";
const TIP_BRANCHES = new Set(["main", TIP_REF]);
const TIP_USES =
  /^melodic-software\/ci-workflows\/\.github\/actions\/resolve-branch-tip@main$/;
const REPOSITORY = "melodic-software/claude-code-plugins";
const WORKFLOW_USES = new RegExp(
  `^(?:\\./|${REPOSITORY}/)\\.github/workflows/([^/@\\s]+\\.ya?ml)(?:@\\S+)?$`,
  "i",
);
const APP_KEY = /automation_lanes_app_private_key|app-private-key/i;
const APP_KEY_INPUTS = new Set(["app-private-key", "private-key"]);
const SHARED_SECRETS = new Set([
  "fallback_claude_code_oauth_token",
  "claude_code_oauth_token",
  "claude_api_key",
  "github_token",
]);
const PR_UNBLOCK_SECRETS = new Set([
  "pr_unblock_claude_code_oauth_token",
  "pr_unblock_claude_api_key",
]);
const ISSUE_LANE_SECRETS = new Set([
  "issue_lane_claude_code_oauth_token",
  "issue_lane_claude_api_key",
]);
const INTAKE_SECRETS = new Set([
  "intake_claude_code_oauth_token",
  "intake_claude_api_key",
]);
const CALLER_SECRETS = new Map([
  ["pr-refine.yml", PR_UNBLOCK_SECRETS],
  ["pr-unblock.yml", PR_UNBLOCK_SECRETS],
  ["work-resolve-issue.yml", ISSUE_LANE_SECRETS],
  ["intake-triage.yml", INTAKE_SECRETS],
]);
const ROLE_SECRETS = new Set(
  [...CALLER_SECRETS.values()].flatMap((names) => [...names]),
);
const KEY = "references the App key";
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
    path.join(root, "scripts/ci-deps/package.json"),
  );
  yaml = await import(pathToFileURL(requireFrom.resolve("yaml")).href);
} catch {
  environmentError(
    "the yaml package is not installed; run npm ci --prefix scripts/ci-deps",
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
  callers = walk(READ_WORKFLOW, callersOf);
  callers.delete(READ_WORKFLOW);
  for (const file of callers) {
    if (!CALLER_SECRETS.has(path.basename(file))) {
      offenders.push(
        `${file}: its run reaches ${READ_WORKFLOW}, but CALLER_SECRETS in scripts/check-read-caller-keys.mjs has no entry for it`,
      );
    }
  }
  for (const file of [READ_WORKFLOW, ...callers]) {
    for (const reached of walk(file, (f) => files.get(f)?.callees ?? [])) {
      runFiles.add(reached);
    }
  }
}

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

function secretFindings(expression, scope, carrier = false) {
  const code = expression.replace(/'(?:[^']|'')*'/g, "''");
  const findings = [];
  for (const match of code.matchAll(/(?<![\w.-])secrets\b/gi)) {
    const rest = code.slice(match.index + match[0].length);
    const before = code.slice(0, match.index);
    const named = /^\s*\.\s*([A-Za-z_][\w-]*)/.exec(rest);
    if (named) {
      const name = named[1];
      const normalized = name.toLowerCase().replaceAll("-", "_");
      if (APP_KEY.test(name)) {
        findings.push(KEY);
      } else if (normalized === CARRIER_SECRET) {
        if (!carrier) {
          findings.push(
            `reads secrets.${name} outside the read workflow's ${CARRIER_JOB}-job open-lane-output private-key input and the ${CARRIER_INPUT} entry a read-workflow call passes`,
          );
        }
      } else if (ROLE_SECRETS.has(normalized)) {
        if (!scope.own.has(normalized)) {
          findings.push(`reads secrets.${name}, ${scope.outside}`);
        }
      } else if (!SHARED_SECRETS.has(normalized)) {
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

function checkJobOf(file, doc) {
  if (file !== READ_WORKFLOW) {
    return null;
  }
  const node = doc.getIn(["jobs", CHECK_JOB], true);
  return yaml.isMap(node) ? node : null;
}

const pairsOf = (node) => (yaml.isMap(node) ? node.items : []);

const exactPairs = (map, key, value) =>
  pairsOf(map).filter(
    (pair) =>
      yaml.isScalar(pair.key) &&
      pair.key.value === key &&
      yaml.isScalar(pair.value) &&
      pair.value.value === value,
  );

function carrierPairOf(file, doc) {
  if (file !== READ_WORKFLOW) {
    return null;
  }
  const steps = doc.getIn(["jobs", CARRIER_JOB, "steps"], true);
  const pairs = (yaml.isSeq(steps) ? steps.items : [])
    .filter(
      (step) =>
        yaml.isMap(step) &&
        String(step.get("uses") ?? "").trim() === CARRIER_ACTION,
    )
    .flatMap((step) =>
      exactPairs(step.get("with", true), "private-key", CARRIER_VALUE),
    );
  return pairs.length === 1 ? pairs[0] : null;
}

function carrierPassesOf(doc) {
  return new Set(
    pairsOf(doc.get("jobs", true))
      .filter(
        (job) =>
          yaml.isMap(job.value) &&
          callee(job.value.get("uses")) === READ_WORKFLOW,
      )
      .flatMap((job) =>
        exactPairs(job.value.get("secrets", true), CARRIER_INPUT, CARRIER_PASS),
      )
      .map((pair) => pair.value),
  );
}

const CHECKOUT_WITH = new Set(["ref", "path", "persist-credentials"]);

function isTipCheckout(values, index) {
  const checkout = values[index];
  const tipIndex = values.findIndex((value) => value?.id === "tip");
  const tip = values[tipIndex];
  return (
    checkout.with?.ref === TIP_STEP_REF &&
    tipIndex !== -1 &&
    tipIndex < index &&
    TIP_USES.test(String(tip.uses ?? "")) &&
    tip.run === undefined &&
    tip.env === undefined &&
    Object.keys(tip.with ?? {}).join() === "branch" &&
    TIP_BRANCHES.has(tip.with.branch) &&
    [tip, checkout].every(
      (step) => step.if === undefined && step["continue-on-error"] === undefined,
    )
  );
}

function checkReadShape(file, doc, lineCounter) {
  const lineOf = (node) =>
    node?.range ? lineCounter.linePos(node.range[0]).line : 1;
  const top = doc.get("permissions", true);
  if (!yaml.isMap(top) || top.items.length > 0) {
    offenders.push(
      `${file}:${lineOf(top)}: the read workflow's top-level permissions is not {}`,
    );
  }
  for (const pair of pairsOf(doc.get("jobs", true))) {
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
  const items = yaml.isSeq(steps) ? steps.items : [];
  const values = items.map((step) => step?.toJSON?.());
  for (const [index, step] of items.entries()) {
    const value = values[index];
    if (
      typeof value?.uses !== "string" ||
      !/^actions\/checkout@/i.test(value.uses.trim())
    ) {
      continue;
    }
    const withKeys = Object.keys(value.with ?? {});
    if (
      (value.with?.ref !== TIP_REF && !isTipCheckout(values, index)) ||
      withKeys.some((key) => !CHECKOUT_WITH.has(key))
    ) {
      offenders.push(
        `${file}:${lineOf(step)}: the ${CHECK_JOB} job checks out something other than this repository's default branch tip`,
      );
    }
  }
}

function isCarrierEnvironment(node) {
  return (
    yaml.isMap(node) &&
    node.items.length === 2 &&
    node.get("name") === CARRIER_ENVIRONMENT &&
    node.get("deployment") === false
  );
}

function check(file) {
  const { doc, lineCounter } = files.get(file);
  const checkJob = checkJobOf(file, doc);
  const carrierPair = carrierPairOf(file, doc);
  const carrierPasses = carrierPassesOf(doc);
  const name = path.basename(file);
  const scope = callers.has(file)
    ? {
        own: CALLER_SECRETS.get(name) ?? new Set(),
        outside: `which is in neither the shared read-run set nor ${name}'s CALLER_SECRETS entry`,
      }
    : {
        own: new Set(),
        outside:
          "a role secret, which only a caller with that role in CALLER_SECRETS may name",
      };
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
  const valueIs = (pair, word) =>
    yaml.isScalar(pair.value) &&
    String(pair.value.value).trim().toLowerCase() === word;
  yaml.visit(doc, {
    Pair(_, pair) {
      const key = yaml.isScalar(pair.key) ? String(pair.key.value).trim() : "";
      const keyLine = pair.key?.range
        ? lineCounter.linePos(pair.key.range[0]).line
        : 0;
      const valueLine = () => lineCounter.linePos(pair.value.range[0]).line;
      if (APP_KEY_INPUTS.has(key.toLowerCase()) && pair !== carrierPair) {
        report(keyLine, KEY);
      }
      if (
        key === "environment" &&
        !(
          pair.value === carrierEnvironment &&
          isCarrierEnvironment(pair.value)
        )
      ) {
        report(
          keyLine,
          `names an environment other than ${CARRIER_ENVIRONMENT} with deployment: false on the read workflow's ${CARRIER_JOB} job`,
        );
      }
      if (key === "secrets" && valueIs(pair, "inherit")) {
        report(valueLine(), "passes secrets: inherit");
      }
      if (key === "permissions" && valueIs(pair, "write-all")) {
        report(valueLine(), "grants permissions: write-all");
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
      const carrier =
        (node === carrierPair?.value && text === CARRIER_VALUE) ||
        carrierPasses.has(node);
      for (const [at, expression] of expressions(text)) {
        for (const what of secretFindings(expression, scope, carrier)) {
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
  `check-read-caller-keys: ${unique.length} offender(s); a run that reaches the read workflow references no App key and passes no secret it cannot name, and a lane mixing read and write activities waits for the token broker (see docs/conventions/pr-pipeline/pr-run-activity.md, "Secrets and the two files").\n`,
);
process.exit(1);
