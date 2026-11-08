// The reach probe: run as a Bash child of a Claude Code leg holding a key or
// a subscription token. In pr-verify-capture.yml that is where the app under
// test and its hooks will run, before any pull request code is checked out;
// upstream-apply-changelog.yml runs it on each new Claude Code release to
// check the subprocess scrub. It reports whether a process in that position
// can read a credential or the job's runtime token: in its own environment,
// in any process environment /proc lets it read, or in a git, gh or Claude
// Code credential file. It writes RESULT_FILE
// (default capture-probe.json in the working directory) with names and places
// only, never a value, and exits 0 clean, 1 on any hit, 2 when the scan cannot
// show it works: a canary child it starts must turn up in the scan, so a
// scanner that reads nothing never passes.
import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

// Every variable that carries a credential pr-verify's capture holds or the
// runner hands a step: the role's three Claude secrets, the names
// run-claude-cli passes or sets them under (lane.cjs CREDENTIAL_VARIABLES),
// the job token and the runtime and OIDC request tokens. A job holding another
// role's secret names it in CAPTURE_PROBE_EXTRA_NAMES, space separated; the
// result lists every name probed, so its caller can see the names arrived.
export const CREDENTIAL_NAMES = Object.freeze([
  "PR_VERIFY_CLAUDE_API_KEY",
  "PR_VERIFY_CLAUDE_CODE_OAUTH_TOKEN",
  "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN",
  "ANTHROPIC_API_KEY",
  "ANTHROPIC_AUTH_TOKEN",
  "CLAUDE_CODE_OAUTH_TOKEN",
  "LANE_API_KEY",
  "LANE_SUBSCRIPTION_TOKEN",
  "LANE_FALLBACK_TOKEN",
  "GITHUB_TOKEN",
  "GH_TOKEN",
  "ACTIONS_RUNTIME_TOKEN",
  "ACTIONS_ID_TOKEN_REQUEST_TOKEN",
]);
// Credential values whatever their variable's name: an Anthropic key or
// OAuth token, and GitHub's token formats.
const VALUE_SHAPES = [/sk-ant-[A-Za-z0-9_-]{8,}/, /\bgh[opsu]_[A-Za-z0-9]{20,}/, /\bgithub_pat_[A-Za-z0-9_]{20,}/];
const credentialShaped = (text) => VALUE_SHAPES.some((shape) => shape.test(text));
const CANARY = "PR_VERIFY_PROBE_CANARY";
// Files that hold a credential git or gh would send.
const AUTH_LINE = /extraheader|authorization:/i;

export const probedNames = (extra = "") => [...CREDENTIAL_NAMES, ...extra.split(/\s+/).filter(Boolean)];

// The credential names set non-empty, and whether any value has a credential
// shape, in one environment as `NAME=value` entries.
export function envHits(entries, names = CREDENTIAL_NAMES) {
  const hits = new Set();
  for (const entry of entries) {
    const at = entry.indexOf("=");
    const name = at < 0 ? entry : entry.slice(0, at);
    const value = at < 0 ? "" : entry.slice(at + 1);
    if (value !== "" && names.includes(name)) hits.add(name);
    if (credentialShaped(value)) hits.add(`a credential-shaped value in ${name}`);
  }
  return [...hits];
}

// Every process environment readable under procRoot: the hits per process,
// how many it read, and whether one held the canary.
export function scanProc(procRoot, canary, names = CREDENTIAL_NAMES) {
  const scan = { hits: [], read: 0, canarySeen: false };
  let pids;
  try {
    pids = readdirSync(procRoot).filter((name) => /^[0-9]+$/.test(name));
  } catch {
    return scan;
  }
  for (const pid of pids) {
    let entries;
    try {
      entries = readFileSync(path.join(procRoot, pid, "environ"), "latin1").split("\0").filter(Boolean);
    } catch {
      continue;
    }
    scan.read += 1;
    if (canary && entries.includes(`${CANARY}=${canary}`)) scan.canarySeen = true;
    for (const name of envHits(entries, names)) scan.hits.push({ where: `process ${pid}`, name });
  }
  return scan;
}

// The credential files a process here could read.
export function scanFiles(files) {
  const hits = [];
  for (const file of files) {
    let text;
    try {
      text = readFileSync(file, "utf8");
    } catch {
      continue;
    }
    if (AUTH_LINE.test(text) || credentialShaped(text)) hits.push({ where: file, name: "a stored credential" });
  }
  return hits;
}

// git's and gh's stores, and Claude Code's own, where a subscription login
// keeps its OAuth token.
export function credentialFiles(cwd, home) {
  return [
    path.join(cwd, ".git/config"),
    path.join(cwd, ".base/.git/config"),
    path.join(home, ".git-credentials"),
    path.join(home, ".config/gh/hosts.yml"),
    path.join(home, ".claude/.credentials.json"),
  ].filter((file) => existsSync(file));
}

// The probe's verdict from its parts: a canary the scan missed outranks a
// clean result, since such a scan proves nothing.
export function verdict({ ownHits, procScan, fileHits }) {
  const hits = [...ownHits.map((name) => ({ where: "own environment", name })), ...procScan.hits, ...fileHits];
  const clean = hits.length === 0 && procScan.canarySeen;
  return { clean, canary: procScan.canarySeen, read: procScan.read, hits, exit: !procScan.canarySeen ? 2 : hits.length ? 1 : 0 };
}

// The file-tool half of the probe, from the probe leg's execution file (the
// CLI's stream-json messages, run-claude-cli's execution-file output): for
// each target path, whether a Read call on it was `refused` (its tool result
// is an error, or the result message lists it in permission_denials),
// `read` (a result that is no error), `unknown` (no result at all) or
// `not tried`. Only every target refused is clean.
export function fileReach(messages, targets) {
  const paths = new Map();
  const errors = new Map();
  const denied = new Set();
  for (const message of Array.isArray(messages) ? messages : []) {
    const content = message?.message?.content;
    for (const block of Array.isArray(content) ? content : []) {
      if (block?.type === "tool_use" && block.name === "Read") paths.set(block.id, block.input?.file_path);
      if (block?.type === "tool_result") errors.set(block.tool_use_id, block.is_error === true);
    }
    if (message?.type === "result" && Array.isArray(message.permission_denials)) {
      for (const denial of message.permission_denials) denied.add(denial?.tool_use_id);
    }
  }
  const reach = targets.map((target) => {
    const ids = [...paths].filter(([, file]) => file === target).map(([id]) => id);
    const each = ids.map((id) => (denied.has(id) || errors.get(id) === true ? "refused" : errors.has(id) ? "read" : "unknown"));
    const status = ids.length === 0 ? "not tried" : ["read", "unknown"].find((s) => each.includes(s)) ?? "refused";
    return { target, status };
  });
  return { clean: reach.length > 0 && reach.every(({ status }) => status === "refused"), reach };
}

// `reads <execution file> <path>...`: exits 0 only when every path's Read was
// refused; 1 when any Read came back or went unanswered, whatever else went
// untried; 3 when none did but a path was never tried, so the session left
// the fence untested rather than showing it open. Prints each path's status,
// never a file's content.
function reads(argv) {
  let messages;
  try {
    messages = JSON.parse(readFileSync(argv[3], "utf8"));
  } catch {
    console.log("capture-probe: the probe leg's execution file is missing or not JSON");
    return 1;
  }
  const { clean, reach } = fileReach(messages, argv.slice(4));
  console.log(`capture-probe: driver file tools: ${reach.map(({ target, status }) => `${target} ${status}`).join(", ")}`);
  if (clean) return 0;
  if (reach.some(({ status }) => status === "read" || status === "unknown")) return 1;
  if (reach.some(({ status }) => status === "not tried")) {
    console.log("capture-probe: the session made no Read call on a path above, so the fence was not tested there");
    return 3;
  }
  return 1;
}

export async function main({ env = process.env, cwd = process.cwd(), procRoot = "/proc", argv = process.argv } = {}) {
  if (argv[2] === "reads") return reads(argv);
  const resultFile = argv[2] || path.join(cwd, "capture-probe.json");
  const names = probedNames(env.CAPTURE_PROBE_EXTRA_NAMES);
  const canary = randomBytes(16).toString("hex");
  const child = spawn("sleep", ["30"], { env: { PATH: env.PATH ?? "/usr/bin:/bin", [CANARY]: canary }, stdio: "ignore" });
  await new Promise((resolve) => setTimeout(resolve, 200));
  let result;
  try {
    result = {
      ...verdict({
        ownHits: envHits(Object.entries(env).map(([name, value]) => `${name}=${value}`), names),
        procScan: scanProc(procRoot, canary, names),
        fileHits: scanFiles(credentialFiles(cwd, env.HOME ?? os.homedir())),
      }),
      names,
    };
  } finally {
    child.kill("SIGKILL");
  }
  writeFileSync(resultFile, `${JSON.stringify(result, null, 2)}\n`);
  const named = result.hits.map((hit) => `${hit.name} (${hit.where})`).join(", ");
  console.log(`capture-probe: read ${result.read} process environments; canary ${result.canary ? "seen" : "not seen"}; ${result.hits.length ? `reachable: ${named}` : "nothing reachable"}`);
  return result.exit;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main();
}
