// The reach probe of pr-verify-capture.yml: run as a Bash child of the
// capture's Claude Code driver, where the app under test and its hooks will
// run, before any pull request code is checked out. It reports whether a
// process in that position can read a credential or the job's runtime token:
// in its own environment, in any process environment /proc lets it read, or
// in a git or gh credential file. It writes RESULT_FILE (default
// capture-probe.json in the working directory) with names and places only,
// never a value, and exits 0 clean, 1 on any hit, 2 when the scan cannot show
// it works: a canary child it starts must turn up in the scan, so a scanner
// that reads nothing never passes.
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
// the job token and the runtime and OIDC request tokens.
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
const CANARY = "PR_VERIFY_PROBE_CANARY";
// Files that hold a credential git or gh would send.
const AUTH_LINE = /extraheader|authorization:/i;

// The credential names set non-empty, and whether any value has a credential
// shape, in one environment as `NAME=value` entries.
export function envHits(entries) {
  const hits = new Set();
  for (const entry of entries) {
    const at = entry.indexOf("=");
    const name = at < 0 ? entry : entry.slice(0, at);
    const value = at < 0 ? "" : entry.slice(at + 1);
    if (value !== "" && CREDENTIAL_NAMES.includes(name)) hits.add(name);
    if (VALUE_SHAPES.some((shape) => shape.test(value))) hits.add(`a credential-shaped value in ${name}`);
  }
  return [...hits];
}

// Every process environment readable under procRoot: the hits per process,
// how many it read, and whether one held the canary.
export function scanProc(procRoot, canary) {
  const hits = [];
  let read = 0;
  let canarySeen = false;
  let pids = [];
  try {
    pids = readdirSync(procRoot).filter((name) => /^[0-9]+$/.test(name));
  } catch {
    return { hits, read, canarySeen };
  }
  for (const pid of pids) {
    let entries;
    try {
      entries = readFileSync(path.join(procRoot, pid, "environ"), "latin1").split("\0").filter(Boolean);
    } catch {
      continue;
    }
    read += 1;
    if (canary && entries.includes(`${CANARY}=${canary}`)) canarySeen = true;
    for (const name of envHits(entries)) hits.push({ where: `process ${pid}`, name });
  }
  return { hits, read, canarySeen };
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
    if (AUTH_LINE.test(text) || VALUE_SHAPES.some((shape) => shape.test(text))) hits.push({ where: file, name: "a stored credential" });
  }
  return hits;
}

export function credentialFiles(cwd, home) {
  return [
    path.join(cwd, ".git/config"),
    path.join(cwd, ".base/.git/config"),
    path.join(home, ".git-credentials"),
    path.join(home, ".config/gh/hosts.yml"),
  ].filter((file) => existsSync(file));
}

// The probe's verdict from its parts: a canary the scan missed outranks a
// clean result, since such a scan proves nothing.
export function verdict({ ownHits, procScan, fileHits }) {
  const hits = [...ownHits.map((name) => ({ where: "own environment", name })), ...procScan.hits, ...fileHits];
  const clean = hits.length === 0 && procScan.canarySeen;
  return { clean, canary: procScan.canarySeen, read: procScan.read, hits, exit: !procScan.canarySeen ? 2 : hits.length ? 1 : 0 };
}

export async function main({ env = process.env, cwd = process.cwd(), procRoot = "/proc", argv = process.argv } = {}) {
  const resultFile = argv[2] || path.join(cwd, "capture-probe.json");
  const canary = randomBytes(16).toString("hex");
  const child = spawn("sleep", ["30"], { env: { PATH: env.PATH ?? "/usr/bin:/bin", [CANARY]: canary }, stdio: "ignore" });
  await new Promise((resolve) => setTimeout(resolve, 200));
  let result;
  try {
    result = verdict({
      ownHits: envHits(Object.entries(env).map(([name, value]) => `${name}=${value}`)),
      procScan: scanProc(procRoot, canary),
      fileHits: scanFiles(credentialFiles(cwd, env.HOME ?? os.homedir())),
    });
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
