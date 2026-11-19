// The rule and exit contract: https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#claude-secrets
import { readdirSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const WORKFLOWS = ".github/workflows";
const ENVIRONMENT = "claude-lanes";
const CLAUDE_SECRET = /claude|oauth/i;
const LOCAL_USES = /^\.\/\.github\/workflows\/([^/@\s]+\.ya?ml)$/i;
// Runs the environment's branch policy checks against a ref other than main:
// https://github.blog/changelog/2025-11-07-actions-pull_request_target-and-environment-branch-protections-changes/
const HEAD_TRIGGERS = new Set([
  "pull_request",
  "pull_request_review",
  "pull_request_review_comment",
  "merge_group",
]);
// A calling job cannot set `environment`, so a remote reusable takes it as its
// `environment` input; these callers cannot pass it yet, and an entry that
// stops matching fails:
// https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows
const PENDING_REMOTE = new Map([
  [
    `${WORKFLOWS}/pr-review-hosted.yml#pr-review`,
    "starts on pull_request, which claude-lanes refuses, until #17537 moves it to workflow_run",
  ],
  [
    `${WORKFLOWS}/pr-review-security-hosted.yml#pr-review-security`,
    "starts on pull_request, which claude-lanes refuses, until #17537 moves it to workflow_run",
  ],
]);

const root = path.resolve(import.meta.dirname, "..");

function environmentError(message) {
  process.stderr.write(`check-claude-secrets-environment: ${message}\n`);
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
    found.push(text.slice(at + 3, i));
    at = text.indexOf("${{", i + 2);
  }
  return found;
}

const ALL = Symbol("all secrets");
function secretReads(node) {
  const reads = new Set();
  yaml.visit(node, {
    Scalar(_, scalar) {
      if (typeof scalar.value !== "string") {
        return;
      }
      for (const body of expressions(scalar.value)) {
        const code = body.replace(/'(?:[^']|'')*'/g, "''");
        for (const match of code.matchAll(/(?<![\w.-])secrets\b/gi)) {
          const named = /^\s*\.\s*([A-Za-z_][\w-]*)/.exec(
            code.slice(match.index + match[0].length),
          );
          reads.add(named ? named[1].toLowerCase() : ALL);
        }
      }
    },
  });
  return reads;
}

function triggersOf(on) {
  if (typeof on === "string") {
    return new Map([[on, null]]);
  }
  if (Array.isArray(on)) {
    return new Map(on.map((name) => [String(name), null]));
  }
  return new Map(Object.entries(on && typeof on === "object" ? on : {}));
}

function pushesOffMain(filter) {
  if (!filter || typeof filter !== "object") {
    return true;
  }
  const keys = Object.keys(filter);
  if (keys.some((key) => /^(tags|tags-ignore|branches-ignore)$/.test(key))) {
    return true;
  }
  const branches = filter.branches;
  return (
    !Array.isArray(branches) ||
    branches.length === 0 ||
    branches.some((branch) => branch !== "main")
  );
}

function environmentName(value) {
  if (typeof value === "string") {
    return value;
  }
  return value && typeof value === "object" ? value.name : undefined;
}

const offenders = [];
const files = new Map();
let names = [];
try {
  names = readdirSync(path.join(root, WORKFLOWS)).filter((name) =>
    /\.ya?ml$/.test(name),
  );
} catch {
  environmentError(`${WORKFLOWS} is not readable`);
}
const byLowerName = new Map(names.map((name) => [name.toLowerCase(), name]));

for (const name of names.sort()) {
  const file = `${WORKFLOWS}/${name}`;
  const lineCounter = new yaml.LineCounter();
  const doc = yaml.parseDocument(readFileSync(path.join(root, file), "utf8"), {
    lineCounter,
  });
  if (doc.errors.length > 0) {
    offenders.push(`${file}: does not parse as YAML, so its jobs cannot be checked`);
    continue;
  }
  const js = doc.toJS() ?? {};
  const triggers = triggersOf(js.on);
  const workflowReads = secretReads(doc.get("env", true) ?? null);
  const jobs = [];
  const jobsNode = doc.get("jobs", true);
  for (const pair of yaml.isMap(jobsNode) ? jobsNode.items : []) {
    const id = String(pair.key?.value);
    const value = js.jobs?.[id] ?? {};
    const uses = typeof value.uses === "string" ? value.uses.trim() : null;
    const local = uses ? LOCAL_USES.exec(uses) : null;
    const reads = secretReads(pair.value);
    for (const read of workflowReads) {
      reads.add(read);
    }
    const passes = new Map();
    const secretsNode = yaml.isMap(pair.value) ? pair.value.get("secrets", true) : null;
    if (yaml.isMap(secretsNode)) {
      for (const item of secretsNode.items) {
        passes.set(String(item.key?.value).toLowerCase(), secretReads(item.value));
      }
    }
    jobs.push({
      id,
      line: lineCounter.linePos(pair.key.range[0]).line,
      uses,
      callee: local ? byLowerName.get(local[1].toLowerCase()) : null,
      inherit: value.secrets === "inherit",
      environment: local || !uses ? value.environment : value.with?.environment,
      reads,
      passes,
    });
  }
  files.set(file, { triggers, jobs });
}

const passedClaude = new Map();
const readsClaude = (file, reads) =>
  [...reads].some(
    (read) =>
      read === ALL ||
      CLAUDE_SECRET.test(read) ||
      passedClaude.get(file)?.has(read),
  );

for (let changed = true; changed; ) {
  changed = false;
  for (const [file, { jobs }] of files) {
    for (const job of jobs) {
      if (!job.callee) {
        continue;
      }
      const target = `${WORKFLOWS}/${job.callee}`;
      const known = passedClaude.get(target) ?? new Set();
      for (const [name, reads] of job.passes) {
        if (!known.has(name) && readsClaude(file, reads)) {
          known.add(name);
          changed = true;
        }
      }
      passedClaude.set(target, known);
    }
  }
}

function effectiveTriggers(file, seen = new Set()) {
  const own = [...(files.get(file)?.triggers ?? new Map())];
  const result = own.filter(([name]) => name !== "workflow_call");
  if (!own.some(([name]) => name === "workflow_call") || seen.has(file)) {
    return result;
  }
  seen.add(file);
  for (const [caller, { jobs }] of files) {
    if (jobs.some((job) => job.callee && `${WORKFLOWS}/${job.callee}` === file)) {
      result.push(...effectiveTriggers(caller, seen));
    }
  }
  return result;
}

const matchedPending = new Set();
for (const [file, { jobs }] of files) {
  const triggers = effectiveTriggers(file);
  const headTriggers = triggers
    .filter(([name, filter]) => HEAD_TRIGGERS.has(name) || (name === "push" && pushesOffMain(filter)))
    .map(([name]) => (name === "push" ? "push to a branch other than main" : name))
    .filter((name, index, all) => all.indexOf(name) === index);
  for (const job of jobs) {
    const where = `${file}:${job.line}: job ${job.id}`;
    const claude = job.inherit || readsClaude(file, job.reads);
    const named = environmentName(job.environment) === ENVIRONMENT;
    if (job.uses) {
      const key = `${file}#${job.id}`;
      if (claude && !job.callee && !named) {
        if (PENDING_REMOTE.has(key)) {
          matchedPending.add(key);
        } else {
          offenders.push(
            `${where} passes a Claude secret to ${job.uses}, a reusable workflow outside this repository, without with: environment: ${ENVIRONMENT}; a calling job cannot set environment, so the called jobs must name it`,
          );
        }
      }
    } else if (claude && !named) {
      offenders.push(`${where} reads a Claude secret without environment ${ENVIRONMENT}`);
    }
    if (named && headTriggers.length > 0) {
      offenders.push(
        `${where} names environment ${ENVIRONMENT} in a run started by ${headTriggers.join(", ")}, which the environment's main-only branch policy refuses`,
      );
    }
  }
}
for (const key of PENDING_REMOTE.keys()) {
  if (!matchedPending.has(key)) {
    offenders.push(
      `${key.replace("#", ": job ")}: PENDING_REMOTE in scripts/check-claude-secrets-environment.mjs names it, but it no longer passes a Claude secret to a reusable workflow outside this repository without with: environment: ${ENVIRONMENT}; remove the entry`,
    );
  }
}

const jobCount = [...files.values()].reduce((sum, { jobs }) => sum + jobs.length, 0);
if (offenders.length === 0) {
  process.stdout.write(
    `check-claude-secrets-environment: every job that reads a Claude secret names environment ${ENVIRONMENT}, and none runs from a head ref (${jobCount} job(s), ${PENDING_REMOTE.size} pending ci-workflows call(s)).\n`,
  );
  process.exit(0);
}
const unique = [...new Set(offenders)].sort();
process.stderr.write(`${unique.join("\n")}\n`);
process.stderr.write(
  `check-claude-secrets-environment: ${unique.length} offender(s); a job reads a Claude secret only in environment ${ENVIRONMENT}, whose branch policy admits main alone (docs/conventions/pr-pipeline/README.md, "Claude secrets").\n`,
);
process.exit(1);
