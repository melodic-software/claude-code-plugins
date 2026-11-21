import { closeSync, mkdirSync, openSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

export const DAY_MS = 24 * 60 * 60 * 1000;
const NAME = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const NPM = /^npm:((?:@[a-z0-9][a-z0-9._-]*\/)?[a-z0-9][a-z0-9._-]*)$/;
const GITHUB = /^github:([A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*)$/;

const USAGE = `usage:
  node cli-version-check.mjs check --state-dir DIR --cli NAME --installed TEXT --source npm:<package>|github:<owner>/<repo> [--hint TEXT] [--json]
  node cli-version-check.mjs claim --state-dir DIR --name NAME   (exit 0 when due, 1 when already run today)`;

function machineStateFile(stateDir, name) {
  if (!stateDir) throw new Error("stateDir is required");
  if (typeof name !== "string" || !NAME.test(name)) throw new Error(`invalid name: ${name}`);
  return join(stateDir, "cli-version-check", `${name}.json`);
}

function lastClaim(file) {
  try {
    return Date.parse(JSON.parse(readFileSync(file, "utf8")).checked_at);
  } catch {
    return NaN;
  }
}

export const STALE_LOCK_MS = 30_000;

function exclusively(file, claim) {
  const lock = `${file}.lock`;
  mkdirSync(dirname(file), { recursive: true });
  for (const mayBreakStaleLock of [true, false]) {
    try {
      closeSync(openSync(lock, "wx"));
    } catch (err) {
      if (err.code !== "EEXIST") throw err;
      const heldSince = statSync(lock, { throwIfNoEntry: false })?.mtimeMs ?? 0;
      if (mayBreakStaleLock && Date.now() - heldSince > STALE_LOCK_MS) {
        rmSync(lock, { force: true });
        continue;
      }
      return false;
    }
    try {
      return claim();
    } finally {
      rmSync(lock, { force: true });
    }
  }
  return false;
}

export function claimDaily({ stateDir, name, now = Date.now() }) {
  const file = machineStateFile(stateDir, name);
  return exclusively(file, () => {
    const last = lastClaim(file);
    if (last <= now && now - last < DAY_MS) return false;
    const tmp = `${file}.${process.pid}.tmp`;
    writeFileSync(tmp, `${JSON.stringify({ checked_at: new Date(now).toISOString() })}\n`);
    renameSync(tmp, file);
    return true;
  });
}

export function parseVersion(text) {
  return /\d+(?:\.\d+)+/.exec(String(text ?? ""))?.[0] ?? null;
}

export function compareVersions(a, b) {
  const x = a.split(".").map(Number);
  const y = b.split(".").map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] ?? 0) - (y[i] ?? 0);
    if (d) return Math.sign(d);
  }
  return 0;
}

function release(source) {
  let m = NPM.exec(source);
  if (m) return { url: `https://registry.npmjs.org/${m[1]}/latest`, field: "version" };
  m = GITHUB.exec(source);
  if (m) return { url: `https://api.github.com/repos/${m[1]}/releases/latest`, field: "tag_name" };
  throw new Error(`invalid source: ${source} (expected npm:<package> or github:<owner>/<repo>)`);
}

export async function checkVersion({ stateDir, cli, installed, source, hint = "", now = Date.now(), fetch = globalThis.fetch, timeoutMs = 3000 }) {
  const { url, field } = release(source);
  // Claimed before the lookup so a failed one also waits a day: unauthenticated api.github.com allows 60 requests an hour per IP, https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
  if (!claimDaily({ stateDir, name: cli, now })) return { status: "skipped" };
  const tail = String(hint).replace(/\s+/g, " ").trim();
  const withHint = (text) => (tail ? `${text} ${tail}` : text);
  const have = parseVersion(installed);
  if (!have) return { status: "not-installed", message: withHint(`${cli} is not installed or printed no version.`) };
  let latest = null;
  let reason = "no version in the response";
  try {
    const res = await fetch(url, { headers: { accept: "application/json", "user-agent": "cli-version-check" }, signal: AbortSignal.timeout(timeoutMs) });
    if (res.ok) latest = parseVersion((await res.json())?.[field]);
    else reason = `HTTP ${res.status}`;
  } catch (err) {
    reason = err?.name === "TimeoutError" ? `no answer in ${timeoutMs} ms` : String(err?.message ?? err);
  }
  if (!latest) return { status: "unverified", installed: have, message: `${cli}: could not read the latest release from ${url} (${reason}); next check in 24 hours.` };
  if (compareVersions(have, latest) < 0) return { status: "behind", installed: have, latest, message: withHint(`${cli} ${have} is behind ${latest}.`) };
  return { status: "current", installed: have, latest };
}

async function main(argv) {
  const [command, ...rest] = argv;
  const { values } = parseArgs({
    args: rest,
    options: {
      "state-dir": { type: "string" },
      cli: { type: "string" },
      name: { type: "string" },
      installed: { type: "string", default: "" },
      source: { type: "string" },
      hint: { type: "string", default: "" },
      json: { type: "boolean", default: false },
    },
  });
  if (command === "claim") return claimDaily({ stateDir: values["state-dir"], name: values.name }) ? 0 : 1;
  if (command !== "check") throw new Error(`unknown command: ${command ?? "(none)"}\n${USAGE}`);
  const result = await checkVersion({ stateDir: values["state-dir"], cli: values.cli, installed: values.installed, source: values.source, hint: values.hint });
  if (values.json) process.stdout.write(`${JSON.stringify(result)}\n`);
  else if (result.message) process.stdout.write(`${result.message}\n`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (err) => {
      process.stderr.write(`cli-version-check: ${err.message}\n`);
      process.exit(2);
    },
  );
}
