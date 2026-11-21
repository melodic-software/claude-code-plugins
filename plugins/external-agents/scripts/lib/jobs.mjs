import { execFileSync } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, realpathSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import { pluginRoot } from "./config.mjs";

const ID = /^[A-Za-z0-9][A-Za-z0-9-]*$/;

const checkKey = (key) => {
  if (!ID.test(key ?? "")) throw new Error(`invalid repo key: ${JSON.stringify(key)}`);
};
const checkId = (id) => {
  if (!ID.test(id ?? "")) throw new Error(`invalid job id: ${JSON.stringify(id)}`);
};
const jobsDir = (dataDir, key) => {
  checkKey(key);
  return join(dataDir, "jobs", key);
};

export function repoKey(cwd) {
  let common;
  try {
    common = execFileSync("git", ["-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], cwd: pluginRoot }).trim();
  } catch {
    return "no-repo";
  }
  const absolute = isAbsolute(common) ? common : join(cwd, common);
  const real = realpathSync.native(absolute);
  return createHash("sha256").update(process.platform === "win32" ? real.toLowerCase() : real).digest("hex").slice(0, 16);
}

export const newJobId = (now = Date.now()) =>
  `${new Date(now).toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "Z")}-${randomBytes(3).toString("hex")}`;

export function writeJob(dataDir, key, job) {
  checkId(job.id);
  const dir = jobsDir(dataDir, key);
  mkdirSync(dir, { recursive: true });
  const file = join(dir, `${job.id}.json`);
  const tmp = `${file}.${process.pid}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(job, null, 2)}\n`);
  renameSync(tmp, file);
  return file;
}

export function jobFolder(dataDir, key, id) {
  checkId(id);
  const dir = join(jobsDir(dataDir, key), id);
  mkdirSync(dir, { recursive: true });
  return dir;
}

export function readJob(dataDir, key, id) {
  checkId(id);
  try {
    return JSON.parse(readFileSync(join(jobsDir(dataDir, key), `${id}.json`), "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
}

export function listJobs(dataDir, key) {
  let names;
  try {
    names = readdirSync(jobsDir(dataDir, key)).filter((n) => n.endsWith(".json"));
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
  return names
    .map((n) => readJob(dataDir, key, n.slice(0, -5)))
    .filter(Boolean)
    .sort((a, b) => String(b.started_at).localeCompare(String(a.started_at)) || String(b.id).localeCompare(String(a.id)));
}

export function pruneJobs(dataDir, key, keep) {
  const dir = jobsDir(dataDir, key);
  const old = listJobs(dataDir, key).filter((job) => job.status !== "running").slice(keep);
  if (!old.length) return [];
  const files = readdirSync(dir);
  for (const job of old) {
    for (const name of files.filter((f) => f === job.id || f.startsWith(`${job.id}.`))) rmSync(join(dir, name), { recursive: true, force: true });
  }
  return old.map((job) => job.id);
}
