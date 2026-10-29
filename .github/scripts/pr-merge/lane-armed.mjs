#!/usr/bin/env node
// lane-armed.mjs: posts pr-merge's `pr-merge/lane-armed` attestation (owner
// decision Q5) on the first candidate whose gate passed its lane-armed paths,
// from the sweep's pr-merge-summary.json, and names the artifact the next
// step uploads; `rerun` then re-runs that head's red ci-status job so
// ci-status reads both (merge-holds.mjs laneArmedHold). No model.
//
// The check run alone proves nothing: any workflow with checks: write posts
// as the same app and can copy this run's id. The artifact
// laneArmedArtifact(pr, head), which only this run's own steps can upload, is
// the proof, so one head is attested a run (an upload step names one
// artifact); a later passing head waits for the next run.
//
// A row attests only when the gate recorded `laneArmed` with no refusal (both
// review lanes bound to a clean main-run review of the head, no open review
// thread, a risk score and verdict that pass: babysit_risk.lane_arm_record),
// the row's head is its pull request's head, and its change leaves the hold
// floor whole (floorChange). The head's text is never parsed: a decoy marker
// pair in a docstring or block comment, or a row inside an expression that
// drops it, would fool any text parse short of the language's own. The
// change is judged instead, against the base's marked regions (main's copy,
// so trusted): in each floor-definition file a patch line may name a floor
// marker or a hold identifier only as an added row of the exact generated
// shape inside a base region, and an added line holds no non-ASCII
// character. babysit_risk.py's head and base copies are also parsed, never
// run, by floor-ast.py, which refuses a new reflective reference and any
// rebinding of a floor table or a set derived from one. The base copy is read at the merge base the patch is
// measured from. A removed row is a shrink. Any read that fails, a missing
// patch, or a cut-short file list refuses.
//
// Each attestation is one countable record: the line `lane-armed {...}` in
// the check run's summary, printed again as a `::notice::`. Each refusal
// prints a `::notice::lane-armed refused` line naming the failed condition.
//
// Environment:
//   GH_TOKEN            the job's own token: checks: write, actions: write,
//                       pull-requests: read, contents: read
//   GITHUB_REPOSITORY   owner/repo
//   SUMMARY_PATH        pr-merge-summary.json (attest)
//   LANE_ARMED_OUT      the directory the record file is written to (attest)
//   GITHUB_OUTPUT       gets `artifact` and `head` for the upload (attest)
//   LANE_ARMED_HEAD     the attested head (rerun)
//   GITHUB_RUN_ID, GITHUB_SERVER_URL, GITHUB_API_URL
import { Buffer } from "node:buffer";
import { execFileSync } from "node:child_process";
import { appendFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import process from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { LANE_ARMED_CHECK, laneArmedArtifact } from "./merge-holds.mjs";

const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]*$/;
const RISK = "plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py";
const HOLDS = ".github/scripts/pr-merge/merge-holds.mjs";
const LANE_ARMED_MJS = ".github/scripts/pr-merge/lane-armed.mjs";
// The files that define the floor or how it is read; every other file holding
// a generated floor block (the review callers, pr-require-checks.yml,
// scripts/sync-hold-floor.py) is person-held, so the gate never attests it.
const FLOOR_AST = ".github/scripts/pr-merge/floor-ast.py";
export const FLOOR_FILES = Object.freeze([RISK, HOLDS, LANE_ARMED_MJS, FLOOR_AST]);
const MARKER = /\b(?:BEGIN|END) (?:floor-rows|hold-floor|js-dynamic)\b/;
// A non-ASCII character in an added line: Python folds a fullwidth or other
// NFKC-equivalent identifier to ASCII, so a fullwidth `FLOOR_CLASSES = ()`
// rebinds it past IDENTIFIER. Reflection and aliasing in babysit_risk.py are
// floor-ast.py's to judge, on the parsed trees.
const NON_ASCII = /[^\x00-\x7f]/;
// The names that hold the floor tables and the sets derived from them.
const IDENTIFIER =
  /\b(?:FLOOR|FLOOR_CLASSES|HOLD_PATH_CLASSES|HOLD_PATH_FLOOR|HIGH_FLOOR|REVIEW_FLOOR|AUTHOR_REVIEW_FLOOR|AUTHOR_REVIEW_CLASSES|PERSON_CLASSES|PERSON_HELD|_NO_AUTHOR_LIFT|GATE_WORKFLOWS|COST_PATHS|LANE_ARM\w*)\b/;
const LANES = ["claude-review", "claude-security-review"];
const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");

// The marker pairs that bound each file's floor rows and its generated
// LANE_ARMED list, and the one shape each line between them may take: a
// comment, or exactly what the generator writes. Any other line (a spread, a
// slice, a block comment, a string spanning lines) could evaluate to a list
// that differs from its text, so it refuses.
const GLOB = String.raw`"([^"\\]+)"`;
const KIND = String.raw`"(trust|gate|enforcement)"`;
const SHAPES = {
  [RISK]: {
    rows: "floor-rows FLOOR_CLASSES",
    comment: /^\s*#(?: .*)?$/,
    row: new RegExp(String.raw`^    \(${GLOB}, ${KIND}\),$`),
    armed: [/^LANE_ARM_GATE = (?:True|False)$/, /^LANE_ARMED: tuple\[str, \.\.\.\] = \($/, /^PERSON_HELD: tuple\[str, \.\.\.\] = \($/, /^\)$/],
  },
  [HOLDS]: {
    rows: "hold-floor HOLD_PATH_CLASSES",
    comment: /^\s*\/\/(?: .*)?$/,
    row: new RegExp(String.raw`^  \[${GLOB}, ${KIND}\],$`),
    armed: [/^export const LANE_ARM_GATE = (?:true|false);$/, /^export const LANE_ARMED = Object\.freeze\(\[$/, /^export const PERSON_HELD = Object\.freeze\(\[$/, /^\]\);$/],
  },
};
const ARMED_MARKER = "hold-floor LANE_ARM";
const ENTRY = { [RISK]: new RegExp(String.raw`^    ${GLOB},$`), [HOLDS]: new RegExp(String.raw`^  ${GLOB},$`) };

// The 1-based line numbers of the one `BEGIN <name>` and the one
// `END <name>` comment line, or null when either is missing or repeated, or
// END comes first.
export function bounds(lines, name) {
  const at = (word) => lines.flatMap((line, i) => (new RegExp(`^\\s*(?:#|//) ${word} ${name}(?::.*)?$`).test(line) ? [i + 1] : []));
  const [begin, end] = [at("BEGIN"), at("END")];
  return begin.length === 1 && end.length === 1 && begin[0] < end[0] ? { begin: begin[0], end: end[0] } : null;
}

// The base copy of `path` (a floor table file) read exactly: its rows region
// and LANE_ARM region, each line between the markers a comment or the shape
// the generator writes, and which LANE_ARM list each base line sits in. Null
// on any other line, a marker missing, repeated or out of order, or no row.
export function floorOf(text, path) {
  const shape = SHAPES[path];
  const lines = String(text).split("\n");
  const rows = shape && bounds(lines, shape.rows);
  const armed = shape && bounds(lines, ARMED_MARKER);
  if (!rows || !armed) {
    return null;
  }
  const kinds = new Map();
  for (const line of lines.slice(rows.begin, rows.end - 1)) {
    const row = shape.row.exec(line);
    if (row) kinds.set(row[1], row[2]);
    else if (!shape.comment.test(line)) return null;
  }
  const lists = new Map([[armed.begin, null]]);
  let list = null;
  for (let n = armed.begin + 1; n < armed.end; n += 1) {
    const line = lines[n - 1];
    if (ENTRY[path].test(line)) {
      if (list === null) return null;
    } else if (shape.armed[1].test(line)) list = "LANE_ARMED";
    else if (shape.armed[2].test(line)) list = "PERSON_HELD";
    else if (shape.armed[3].test(line)) list = null;
    else if (!shape.armed[0].test(line) && !shape.comment.test(line)) return null;
    lists.set(n, list);
  }
  return kinds.size === 0 ? null : { shape, rows, armed, kinds, lists };
}

// Each changed line of a unified-diff `patch`: { sign, text, at }, where `at`
// is the base line a removed line was, or the base line an added line
// follows. Null for a patch that is not a well-formed diff.
export function patchLines(patch) {
  if (typeof patch !== "string" || !patch.startsWith("@@")) return null;
  const out = [];
  let old = null;
  for (const line of patch.split("\n")) {
    const hunk = /^@@ -(\d+)(,\d+)? \+\d+(?:,\d+)? @@/.exec(line);
    if (hunk) {
      // A pure insertion's header names the line it follows.
      old = Number(hunk[1]) + (hunk[2] === ",0" ? 1 : 0);
      continue;
    }
    if (old === null) return null;
    const [sign, text] = [line[0], line.slice(1)];
    if (sign === " ") old += 1;
    else if (sign === "-") out.push({ sign, text, at: old++ });
    else if (sign === "+") out.push({ sign, text, at: old - 1 });
    else if (sign !== "\\" && line !== "") return null;
  }
  return out;
}

// Why the change `patch` to floor-definition file `path` could weaken the
// floor, or null. `base` is floorOf of the base copy, required for a floor
// table file.
export function floorChange(path, patch, base, locked = null) {
  const changes = patchLines(patch);
  if (changes === null) return `${path} has no readable patch`;
  // Only babysit_risk.py and merge-holds.mjs hold floor tables; the judge
  // code (lane-armed.mjs, floor-ast.py) is checked for markers and names.
  const table = Object.hasOwn(SHAPES, path);
  if (table && !base) return `the base copy of ${path} cannot be read exactly`;
  for (const { sign, text, at } of changes) {
    const what = `${sign === "+" ? "an added" : "a removed"} line of ${path}`;
    if (MARKER.test(text)) return `${what} names a floor marker`;
    if (locked && (sign === "-" ? locked.begin < at && at < locked.end : locked.begin <= at && at < locked.end)) return `${what} is inside the JS_DYNAMIC list`;
    if (sign === "+" && NON_ASCII.test(text)) return `${what} holds a non-ASCII character`;
    // A removed line sits strictly between the markers; an added one follows
    // BEGIN or a line before END.
    const inside = (r) => (sign === "-" ? r.begin < at && at < r.end : r.begin <= at && at < r.end);
    if (table && inside(base.rows)) {
      const row = base.shape.row.exec(text);
      if (sign === "-" && row) return `it removes the floor row ${row[1]}`;
      if (sign === "-" ? !base.shape.comment.test(text) : !row) return `${what} inside the floor rows is not a row of the generated shape`;
      continue;
    }
    if (table && inside(base.armed)) {
      if (sign === "+" && ENTRY[path].test(text) && base.lists.get(at) === "PERSON_HELD") continue;
      return `${what} changes the generated LANE_ARM block other than by a person-held entry`;
    }
    const named = IDENTIFIER.exec(text);
    if (named) return `${what} names ${named[0]} outside the floor rows`;
  }
  return null;
}

// The JS ways to run or reach code by a name no line spells: a head copy of
// merge-holds.mjs or lane-armed.mjs may hold none of these more often than
// its base copy. Counted over the whole text but this list, so splitting a
// string around a table name does not help: the token itself must appear.
// Each is call-shaped or otherwise not a path segment, so a floor row such
// as `.github/workflows/eval-browser-dispatch.yml` counts as nothing. The
// list sits in its own marker block: its literals are not counted, and a
// patch line inside the block refuses, so deleting one literal cannot make
// room for a real call.
const JS_DYNAMIC = Object.freeze([
  // BEGIN js-dynamic JS_DYNAMIC
  ["eval(", /\beval\s*\(/g],
  ["Function(", /\bFunction\s*\(/g],
  ["new Function", /\bnew\s+Function\b/g],
  ["globalThis", /\bglobalThis\b/g],
  ["Reflect.", /\bReflect\s*\./g],
  ["Object.defineProperty", /\bObject\s*\.\s*defineProperty\b/g],
  ["__proto__", /__proto__/g],
  ["import(", /\bimport\s*\(/g],
  ["require(", /\brequire\s*\(/g],
  ["vm.", /\bvm\s*\./g],
  ["process.binding", /\bprocess\s*\.\s*binding\b/g],
  // END js-dynamic JS_DYNAMIC
]);
const DYNAMIC_BLOCK = "js-dynamic JS_DYNAMIC";

// Why the head copy of a JS floor file reaches code more dynamically than
// its base copy, or null.
export function jsRefusal(baseText, headText) {
  // The text less the one JS_DYNAMIC block, when a copy has exactly one.
  const outside = (text) => {
    const lines = String(text).split("\n");
    const block = bounds(lines, DYNAMIC_BLOCK);
    return block ? [...lines.slice(0, block.begin - 1), ...lines.slice(block.end)].join("\n") : lines.join("\n");
  };
  const [base, head] = [outside(baseText), outside(headText)];
  for (const [name, pattern] of JS_DYNAMIC) {
    const count = (text) => (text.match(pattern) ?? []).length;
    if (count(head) > count(base)) return `it adds ${name}`;
  }
  return null;
}

// floor-ast.py from this checkout (the base's, never the head's) on the base
// and head copies of babysit_risk.py: its one line of output, "" when it
// accepts the head, or why it refused.
export function astRefusal(baseText, headText, run = execFileSync) {
  const dir = mkdtempSync(join(tmpdir(), "lane-armed-ast-"));
  try {
    writeFileSync(join(dir, "base.py"), baseText);
    writeFileSync(join(dir, "head.py"), headText);
    try {
      run("python3", ["-I", fileURLToPath(new URL("./floor-ast.py", import.meta.url)), join(dir, "base.py"), join(dir, "head.py")], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
      return "";
    } catch (error) {
      return String(error?.stdout ?? "").trim() || "floor-ast.py could not judge it";
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// Why the pull request's change could weaken the floor, or null. The base
// copy and the patches come from one compare of the base branch with the
// head: GitHub measures a pull request's patch from the merge base, not the
// base branch's current tip, so the base copy is read at that merge base.
// The compare lists at most 300 files, fewer than the pull request's
// `changed_files` refuses.
async function floorRefusal(github, repo, pull) {
  const compare = await github("GET", `/repos/${repo}/compare/${pull.base.sha}...${pull.head.sha}`);
  const mergeBase = compare?.merge_base_commit?.sha;
  if (!SHA.test(String(mergeBase))) return "its merge base cannot be read";
  const files = compare.files;
  if (!Array.isArray(files) || !Number.isSafeInteger(pull.changed_files) || files.length < pull.changed_files) return "its file list is cut short";
  for (const file of files) {
    const touched = [file.filename, file.previous_filename].filter((name) => FLOOR_FILES.includes(name));
    if (touched.length === 0) continue;
    if (file.status !== "modified" || file.previous_filename) return `it ${file.status} ${touched[0]}`;
    const baseText = await text(github, repo, file.filename, mergeBase);
    const base = Object.hasOwn(SHAPES, file.filename) ? floorOf(baseText, file.filename) : null;
    let locked = null;
    if (file.filename === LANE_ARMED_MJS) {
      locked = bounds(baseText.split("\n"), DYNAMIC_BLOCK);
      if (!locked) return `the base copy of ${LANE_ARMED_MJS} has no single JS_DYNAMIC block`;
    }
    const why = floorChange(file.filename, file.patch, base, locked);
    if (why) return why;
    if (file.filename === RISK) {
      const parsed = astRefusal(await text(github, repo, RISK, mergeBase), await text(github, repo, RISK, pull.head.sha));
      if (parsed) return `its ${RISK}: ${parsed}`;
    }
    if (file.filename.endsWith(".mjs")) {
      const dynamic = jsRefusal(await text(github, repo, file.filename, mergeBase), await text(github, repo, file.filename, pull.head.sha));
      if (dynamic) return `its ${file.filename}: ${dynamic}`;
    }
  }
  return null;
}

// The record an attestation carries, from a summary row and this run.
export const recordOf = (row, run) => ({
  v: 1,
  pr: row.pr,
  head: row.head,
  paths: row.laneArmed.paths,
  lanes: Object.fromEntries(LANES.map((lane) => [lane, row.laneArmed.lanes?.[lane] ?? null])),
  threads: row.laneArmed.threads,
  run: Number(run),
});

// Why `row` does not attest before any read, or null.
export function rowRefusal(row) {
  const armed = row?.laneArmed;
  if (!armed || typeof armed !== "object") return "the gate recorded no lane-armed paths";
  if (armed.refused) return String(armed.refused);
  if (!Array.isArray(armed.paths) || armed.paths.length === 0 || !armed.paths.every((path) => typeof path === "string")) return "the gate recorded no lane-armed paths";
  if (armed.threads !== 0) return "the open review threads are not zero";
  if (!LANES.every((lane) => armed.lanes?.[lane] === 0)) return "a review lane has an open finding";
  return null;
}

async function text(github, repo, path, ref) {
  const file = await github("GET", `/repos/${repo}/contents/${path}?ref=${ref}`);
  if (file?.encoding !== "base64" || typeof file.content !== "string") throw new Error(`${path} at ${ref} is not a file`);
  return Buffer.from(file.content, "base64").toString("utf8");
}

// Re-run the ci-status job of the head's newest pull_request run of
// pr-require-checks.yml when it finished red; a running one reads the
// attestation itself.
async function rerunCiStatus(github, repo, head) {
  const runs = (await github("GET", `/repos/${repo}/actions/workflows/pr-require-checks.yml/runs?head_sha=${head}&event=pull_request&per_page=20`))?.workflow_runs;
  const run = (Array.isArray(runs) ? runs : []).reduce((a, b) => (a === null || b.id > a.id ? b : a), null);
  if (!run || run.status !== "completed") return "no finished ci-status run to re-run";
  const jobs = (await github("GET", `/repos/${repo}/actions/runs/${run.id}/jobs?per_page=100`))?.jobs;
  const job = (Array.isArray(jobs) ? jobs : []).find((each) => each?.name === "ci-status");
  if (!job || job.conclusion === "success") return "ci-status is not red";
  await github("POST", `/repos/${repo}/actions/jobs/${job.id}/rerun`);
  return `re-ran ci-status job ${job.id}`;
}

export async function main({ env = process.env, github, fetchImpl, mode = process.argv[2] ?? "attest" } = {}) {
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) throw new Error("GITHUB_REPOSITORY is not owner/repo");
    if (!RUN_ID.test(env.GITHUB_RUN_ID ?? "")) throw new Error("GITHUB_RUN_ID is not a run id");
    const repo = env.GITHUB_REPOSITORY;
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, fetchImpl });
    if (mode === "rerun") {
      if (!SHA.test(env.LANE_ARMED_HEAD ?? "")) throw new Error("LANE_ARMED_HEAD is not a commit SHA");
      console.log(`lane-armed: ${await rerunCiStatus(github, repo, env.LANE_ARMED_HEAD)}`);
      return 0;
    }
    let rows;
    try {
      rows = JSON.parse(readFileSync(env.SUMMARY_PATH, "utf8"));
    } catch {
      rows = [];
    }
    const details = `${env.GITHUB_SERVER_URL || "https://github.com"}/${repo}/actions/runs/${env.GITHUB_RUN_ID}`;
    let failed = 0;
    let attested = null;
    for (const row of Array.isArray(rows) ? rows : []) {
      if (!row?.laneArmed || !Number.isSafeInteger(row.pr) || !SHA.test(String(row.head)) || Object.hasOwn(row, "carried")) continue;
      const refuse = (why) => console.log(`::notice::lane-armed refused ${JSON.stringify({ v: 1, pr: row.pr, head: row.head, reason: why })}`);
      const early = rowRefusal(row) ?? (attested ? `this run attested #${attested.pr}; the next run attests this head` : null);
      if (early) {
        refuse(early);
        continue;
      }
      try {
        const pull = await github("GET", `/repos/${repo}/pulls/${row.pr}`);
        if (pull?.head?.sha !== row.head || !SHA.test(String(pull?.base?.sha))) {
          refuse("the head the gate judged is not the pull request's head");
          continue;
        }
        const shrunk = await floorRefusal(github, repo, pull);
        if (shrunk) {
          refuse(`its change could weaken the hold floor: ${shrunk}`);
          continue;
        }
        const record = recordOf(row, env.GITHUB_RUN_ID);
        const line = `lane-armed ${JSON.stringify(record)}`;
        await github("POST", `/repos/${repo}/check-runs`, {
          name: LANE_ARMED_CHECK,
          head_sha: row.head,
          external_id: env.GITHUB_RUN_ID,
          details_url: details,
          status: "completed",
          conclusion: "success",
          output: {
            title: `pr-merge's gate passed ${record.paths.length} lane-armed path(s) on clean main-run reviews`,
            summary: [
              `Both review lanes are bound to a main-run review of \`${row.head}\` with no open finding, no review thread is open, the risk score and verdict pass, and the hold floor is not shrunk against the base. ci-status trusts this only with this run's artifact \`${laneArmedArtifact(row.pr, row.head)}\`.`,
              "",
              "```text",
              line,
              "```",
            ].join("\n"),
          },
        });
        console.log(`::notice::${line}`);
        attested = record;
      } catch (error) {
        failed += 1;
        refuse(`a read or write failed: ${escapeCommand(error?.message ?? error)}`);
      }
    }
    if (attested) {
      mkdirSync(env.LANE_ARMED_OUT, { recursive: true });
      writeFileSync(join(env.LANE_ARMED_OUT, "lane-armed.json"), `${JSON.stringify(attested)}\n`);
      appendFileSync(env.GITHUB_OUTPUT, `artifact=${laneArmedArtifact(attested.pr, attested.head)}\nhead=${attested.head}\n`);
    }
    return failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=lane-armed::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
