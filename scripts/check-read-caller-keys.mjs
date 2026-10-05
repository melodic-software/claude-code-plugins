// The check behind scripts/check-read-caller-keys.sh, which states the rule
// and the exit contract. Parses every workflow under .github/workflows/, builds
// the call graph of this repository's workflows, and checks every parsed key and
// string value of every file of every run that can reach the read workflow.
import { readdirSync, readFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import process from "node:process";

const WORKFLOWS = ".github/workflows";
const READ_WORKFLOW = `${WORKFLOWS}/pr-run-activity-read.yml`;
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
const ALLOWED_SECRETS = new Set(["claude_code_oauth_token", "github_token"]);
const KEY = "references the App key";

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
  yaml = await import(requireFrom.resolve("yaml"));
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
function secretFindings(expression) {
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

function check(file) {
  const { doc, lineCounter } = files.get(file);
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
      if (APP_KEY_INPUTS.has(key.toLowerCase())) {
        report(keyLine, KEY);
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
      if (file === READ_WORKFLOW && /id-token/i.test(key)) {
        offenders.push(`${file}:${keyLine}: the read workflow names id-token`);
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
        for (const what of secretFindings(expression)) {
          report(lineAt(node, text, at), what);
        }
      }
      const idToken = /id-token/i.exec(text);
      if (file === READ_WORKFLOW && idToken) {
        offenders.push(
          `${file}:${lineAt(node, text, idToken.index)}: the read workflow names id-token`,
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
