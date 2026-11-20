// Builds the intake re-entry eval suite (#8491) as a `claude plugin eval`
// plugin directory outside the repository. The prompt is never kept here: the
// builder runs the ci-workflows reusable's own compose script, read from the
// reusable at the commit given, with this repository's allowed-labels and
// instructions from the caller workflow, and fills each case with the prompt
// it writes. The schema step runs with the caller's verdict-schema, as the
// reusable does. `--no-instructions` builds the baseline with the instructions
// input empty; `--no-verdict-schema` empties verdict-schema, for the
// byte-identical comparison against a build from before ci-workflows febb1ed.
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(HERE, "../../../..");
const CALLER = join(REPO_ROOT, ".github/workflows/intake-triage.yml");
const WORKDIR = ".intake-triage-eval";
const REPOSITORY = "melodic-software/claude-code-plugins";
// Labels the stubbed label listing reports besides the caller's allowed set.
const REPO_LABELS = [
  "needs-triage",
  "agent-ready",
  "provenance: untrusted",
];
const ISSUE_TYPES = ["Bug", "Task", "Feature"];
// The one line not taken from the reusable: plugin eval has no --json-schema,
// so the run is asked for the schema's object as its final reply.
export const OUTPUT_LINE =
  "Reply with only the structured output: one JSON object that matches this JSON Schema.";

// The literal block scalar (`key: |`) at the first line matching `keyLine`
// after line `from`, dedented as YAML does, with the line it ends on.
export function blockScalar(lines, keyLine, from = 0) {
  const start = lines.findIndex((line, i) => i >= from && keyLine.test(line));
  if (start < 0) throw new Error(`no block scalar matching ${keyLine}`);
  const keyIndent = lines[start].search(/\S/u);
  const body = [];
  let end = start + 1;
  for (; end < lines.length; end += 1) {
    const line = lines[end];
    if (line.trim() !== "" && line.search(/\S/u) <= keyIndent) break;
    body.push(line);
  }
  while (body.length > 0 && body.at(-1).trim() === "") body.pop();
  const indent = Math.min(
    ...body
      .filter((line) => line.trim() !== "")
      .map((line) => line.search(/\S/u)),
  );
  return {
    text: `${body.map((line) => line.slice(indent)).join("\n")}\n`,
    end,
  };
}

// Every compose step's script in the reusable. The legs must carry one script,
// or the suite would measure only one of them.
export function composeScript(reusable) {
  const lines = reusable.split("\n");
  const scripts = [];
  for (let i = 0; i < lines.length; i += 1) {
    if (!/^\s+id: compose\s*$/u.test(lines[i])) continue;
    const { text, end } = blockScalar(lines, /^\s+script: \|\s*$/u, i);
    scripts.push(text);
    i = end - 1;
  }
  if (scripts.length === 0) throw new Error("the reusable has no compose step");
  if (new Set(scripts).size !== 1)
    throw new Error(`the reusable's ${scripts.length} compose scripts differ`);
  if (scripts[0].includes("${{"))
    throw new Error(
      "the compose script holds a workflow expression the builder cannot fill",
    );
  return scripts[0];
}

// A one-line `key: value` scalar, plain or single-quoted, as YAML reads it.
// Any other style fails closed rather than pass the schema step a wrong value.
export function lineScalar(line) {
  const value = line.slice(line.indexOf(":") + 1).trim();
  if (value.includes("${{"))
    throw new Error(
      `the caller's ${line.trim().split(":")[0]} holds a workflow expression the builder cannot fill`,
    );
  if (value.startsWith("'")) {
    if (value.length < 2 || !value.endsWith("'"))
      throw new Error(`unterminated single-quoted scalar: ${line.trim()}`);
    return value.slice(1, -1).replaceAll("''", "'");
  }
  if (/^["|>&*!]/u.test(value))
    throw new Error(`unsupported scalar style: ${line.trim()}`);
  return value;
}

// The caller job's `with:` inputs the compose and schema steps read.
export function callerInputs(caller, job = "intake-triage") {
  const lines = caller.split("\n");
  const at = lines.findIndex((line) => line === `  ${job}:`);
  if (at < 0) throw new Error(`the caller has no ${job} job`);
  const next = lines.findIndex((line, i) => i > at && /^ {2}\S/u.test(line));
  const verdictSchema = lines
    .slice(at, next < 0 ? lines.length : next)
    .find((line) => /^\s+verdict-schema:/u.test(line));
  const uses = lines
    .slice(at)
    .find((line) =>
      /^\s+uses: melodic-software\/ci-workflows\/\.github\/workflows\/intake-triage\.yml@/u.test(
        line,
      ),
    );
  return {
    ref: uses?.split("@")[1]?.split(/\s/u)[0] ?? "",
    allowedLabels: blockScalar(lines, /^\s+allowed-labels: \|\s*$/u, at).text,
    instructions: blockScalar(lines, /^\s+instructions: \|\s*$/u, at).text,
    verdictSchema: verdictSchema ? lineScalar(verdictSchema) : "",
  };
}

export function verdictModule(source) {
  const module = { exports: {} };
  new Function("require", "module", "exports", source)(
    createRequire(import.meta.url),
    module,
    module.exports,
  );
  if (typeof module.exports.main !== "function")
    throw new Error("the verdict script exports no main");
  return module.exports;
}

// Runs the reusable's schema step. With a non-empty verdict-schema it also
// appends the verdict-fields block to the prompt file, so read the prompt
// only after this returns.
export function schema(verdict, outputs, verdictSchema = "") {
  for (const name of ["allowed", "type-names", "prompt-file"])
    if (typeof outputs[name] !== "string")
      throw new Error(`compose set no ${name} output for the schema step`);
  const file = verdict.main({
    INPUT_MODE: "schema",
    INPUT_VERDICT_SCHEMA: verdictSchema,
    INPUT_ALLOWED: outputs.allowed,
    INPUT_TYPE_NAMES: outputs["type-names"],
    INPUT_PROMPT_FILE: outputs["prompt-file"],
  })?.outputs?.["schema-file"];
  if (!file) throw new Error("the schema step set no schema-file output");
  return readFileSync(file, "utf8");
}

export async function compose(script, env) {
  const outputs = {};
  const core = {
    setOutput: (name, value) =>
      (outputs[name] =
        value == null
          ? ""
          : typeof value === "string"
            ? value
            : JSON.stringify(value)),
    setFailed: (message) => {
      throw new Error(`compose failed: ${message}`);
    },
    warning: () => {},
    info: () => {},
  };
  const labels = [
    ...new Set([
      ...env.ALLOWED_LABELS.split("\n")
        .map((l) => l.trim())
        .filter(Boolean),
      ...REPO_LABELS,
    ]),
  ];
  const github = {
    // The script meters API budget through request hooks; the stub makes no requests.
    hook: { after: () => {}, error: () => {} },
    rest: { issues: { listLabelsForRepo: "listLabelsForRepo" } },
    paginate: async () => labels.map((name) => ({ name })),
    graphql: async () => ({
      repository: {
        issueTypes: {
          nodes: ISSUE_TYPES.map((name, i) => ({
            id: `T${i}`,
            name,
            isEnabled: true,
          })),
        },
      },
    }),
  };
  const [owner, repo] = REPOSITORY.split("/");
  const saved = process.env;
  process.env = { ...env };
  try {
    const AsyncFunction = (async () => {}).constructor;
    await new AsyncFunction("require", "github", "context", "core", script)(
      createRequire(import.meta.url),
      github,
      { repo: { owner, repo } },
      core,
    );
  } finally {
    process.env = saved;
  }
  return outputs;
}

// One case's workspace: the issue files the reusable's fetch step writes, in
// its shape, under WORKDIR, and AGENTS.md at the root the prompt points to.
// The body is the case's own body.md when it has one, else the shared one.
function workspace(caseDir, out) {
  const meta = JSON.parse(readFileSync(join(caseDir, "issue.json"), "utf8"));
  const dir = join(out, WORKDIR);
  mkdirSync(dir, { recursive: true });
  const ownBody = join(caseDir, "body.md");
  cpSync(
    existsSync(ownBody) ? ownBody : join(caseDir, "..", "_issue", "body.md"),
    join(dir, "body.md"),
  );
  const comments = meta.comments.map((comment, i) => {
    cpSync(join(caseDir, comment.file), join(dir, `comment-${i + 1}.md`));
    return {
      author: comment.author,
      url: comment.url,
      body: `${WORKDIR}/comment-${i + 1}.md`,
    };
  });
  const issue = {
    number: meta.number,
    title: meta.title,
    author: meta.author,
    labels: meta.labels,
    body: `${WORKDIR}/body.md`,
    comments,
  };
  writeFileSync(join(dir, "issue.json"), JSON.stringify(issue, null, 2));
  writeFileSync(
    join(dir, "open-issues.json"),
    JSON.stringify(meta.open, null, 2),
  );
  writeFileSync(
    join(dir, "merged-pulls.json"),
    JSON.stringify(meta.merged ?? [], null, 2),
  );
  cpSync(join(REPO_ROOT, "AGENTS.md"), join(out, "AGENTS.md"));
  return meta.number;
}

export async function build({
  reusable,
  verdictSource,
  sha,
  out,
  instructions = true,
  verdictSchema = true,
  casesDir = join(HERE, "cases"),
  callerText = readFileSync(CALLER, "utf8"),
}) {
  const script = composeScript(reusable);
  const verdict = verdictModule(verdictSource);
  const inputs = callerInputs(callerText);
  const evals = join(out, "evals");
  mkdirSync(join(out, ".claude-plugin"), { recursive: true });
  writeFileSync(
    join(out, ".claude-plugin", "plugin.json"),
    JSON.stringify(
      {
        name: "intake-reentry-eval",
        version: "0.0.0",
        description: `Built from ci-workflows ${sha} (caller ref ${inputs.ref}); instructions ${instructions ? "on" : "off"}; verdict-schema ${verdictSchema && inputs.verdictSchema ? "on" : "off"}.`,
      },
      null,
      2,
    ),
  );
  const runnerTemp = mkdtempSync(join(tmpdir(), "reentry-eval-"));
  const names = readdirSync(casesDir, { withFileTypes: true })
    .filter((e) => e.isDirectory() && !e.name.startsWith("_"))
    .map((e) => e.name);
  try {
    for (const name of names) {
      const src = join(casesDir, name);
      const dst = join(evals, name);
      cpSync(src, dst, { recursive: true });
      const number = workspace(src, join(dst, "workspace"));
      const outputs = await compose(script, {
        RUNNER_TEMP: runnerTemp,
        ALLOWED_LABELS: inputs.allowedLabels,
        ESCALATION_LABEL: "needs-human",
        FLOOR_LABEL: "needs-triage",
        BASE_ARGS: "",
        CLI_VERSION: "latest",
        REPOSITORY,
        ISSUE_NUMBER: String(number),
        ISSUE_FILE: `${WORKDIR}/issue.json`,
        OPEN_ISSUES_FILE: `${WORKDIR}/open-issues.json`,
        DUPLICATE_LIMIT: "200",
        MERGED_PULLS_FILE: `${WORKDIR}/merged-pulls.json`,
        MERGED_LIMIT: "100",
        INSTRUCTIONS: instructions ? inputs.instructions : "",
      });
      // The schema step runs first: it appends the verdict-fields block to
      // the prompt file the case's prompt is read from.
      const schemaText = schema(
        verdict,
        outputs,
        verdictSchema ? inputs.verdictSchema : "",
      );
      const prompt = readFileSync(outputs["prompt-file"], "utf8");
      const full = `${prompt}\n${OUTPUT_LINE}\n\n${schemaText}\n`;
      const caseFile = join(dst, "case.yaml");
      writeFileSync(
        caseFile,
        readFileSync(caseFile, "utf8").replace(
          /^ {2}prompt: .*$/mu,
          () => `  prompt: ${JSON.stringify(full)}`,
        ),
      );
      writeFileSync(
        join(dst, "scaffold.sh"),
        `#!/usr/bin/env bash\nset -euo pipefail\ncp -R "$(dirname "\${BASH_SOURCE[0]}")/workspace/." .\n`,
        { mode: 0o755 },
      );
    }
  } finally {
    rmSync(runnerTemp, { recursive: true, force: true });
  }
  return { ref: inputs.ref, cases: names };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { values } = parseArgs({
    options: {
      reusable: { type: "string" },
      verdict: { type: "string" },
      sha: { type: "string" },
      out: { type: "string" },
      "no-instructions": { type: "boolean" },
      "no-verdict-schema": { type: "boolean" },
    },
  });
  if (
    !values.reusable ||
    !values.verdict ||
    !/^[0-9a-f]{40}$/u.test(values.sha ?? "") ||
    !values.out
  ) {
    console.error(
      "usage: build-suite.mjs --reusable <intake-triage.yml> --verdict <verdict.cjs> --sha <40-hex commit> --out <dir> [--no-instructions] [--no-verdict-schema]",
    );
    process.exit(2);
  }
  const result = await build({
    reusable: readFileSync(values.reusable, "utf8"),
    verdictSource: readFileSync(values.verdict, "utf8"),
    sha: values.sha,
    out: values.out,
    instructions: !values["no-instructions"],
    verdictSchema: !values["no-verdict-schema"],
  });
  console.log(
    `built ${result.cases.length} cases at ${values.out} from ci-workflows ${values.sha} (caller ref ${result.ref})`,
  );
}
