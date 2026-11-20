import { writeFileSync } from "node:fs";

import { LANE_WORKFLOWS, settledRun, zipEntry } from "../lib/lane-binding.mjs";

export const LANE_RECORD_CACHE = "pr-feedback-lane-records";
export const CACHE_FILE = "feedback-lane-records.json";
const VERSION = 1;
const IDLE_MS = 86_400_000;
const KEY = /^([1-9][0-9]{0,15})\/([1-9][0-9]{0,3})$/;
const RUN_FIELDS = ["id", "path", "head_sha", "head_branch", "status", "run_attempt", "created_at", "updated_at"];
const ENTRY_FIELDS = ["lane", "pr", "head", "kind", "id", "sha256"];

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const pick = (from, fields) => Object.fromEntries(fields.filter((field) => field in from).map((field) => [field, from[field]]));

const fresh = (entry, now) => {
  const idle = now - Date.parse(entry.seen);
  return Date.parse(entry.expires) > now && idle >= 0 && idle <= IDLE_MS;
};

function valid(key, entry, now) {
  const match = KEY.exec(key);
  return (
    match !== null &&
    isObject(entry) &&
    isObject(entry.run) &&
    entry.run.id === Number(match[1]) &&
    entry.run.run_attempt === Number(match[2]) &&
    typeof entry.seen === "string" &&
    typeof entry.expires === "string" &&
    fresh(entry, now) &&
    Array.isArray(entry.entries) &&
    entry.entries.every(isObject) &&
    Array.isArray(entry.recorded) &&
    entry.recorded.every((name) => typeof name === "string") &&
    settledRun({ run: entry.run, recorded: new Set(entry.recorded) }, LANE_WORKFLOWS)
  );
}

export function laneRecordStore({ workflow, repository, listArtifactsNamed, getRun, download, log, now = Date.now() }) {
  const runs = new Map();
  const seen = new Date(now).toISOString();
  const keep = (key, entry) => {
    const id = String(entry.run.id);
    if ((runs.get(id)?.entry.run.run_attempt ?? 0) < entry.run.run_attempt) {
      runs.set(id, { key, entry });
    }
  };
  const read = async () => {
    try {
      const [artifact] = (await listArtifactsNamed(LANE_RECORD_CACHE))
        .filter((row) => row?.name === LANE_RECORD_CACHE && row.expired === false)
        .sort((a, b) => b.id - a.id);
      if (!artifact) {
        log(`no unexpired ${LANE_RECORD_CACHE} artifact; lane runs are read live`);
        return;
      }
      const uploader = artifact.workflow_run?.id;
      const run = await getRun(uploader);
      const trusted =
        Number.isSafeInteger(uploader) &&
        run?.id === uploader &&
        run.path === workflow &&
        run.head_branch === "main" &&
        run.event === "workflow_run" &&
        run.head_repository?.full_name === repository;
      if (!trusted) {
        log(`::warning::${LANE_RECORD_CACHE} artifact ${artifact.id} is not from a workflow_run run of ${workflow} on main; lane runs are read live`);
        return;
      }
      const text = zipEntry(await download(artifact.id), CACHE_FILE)?.toString("utf8");
      if (text === undefined) {
        throw new Error(`it holds no ${CACHE_FILE}`);
      }
      const data = JSON.parse(text);
      if (!isObject(data) || data.version !== VERSION || data.repo !== repository || !isObject(data.runs)) {
        throw new Error("it has an unexpected shape");
      }
      for (const [key, entry] of Object.entries(data.runs)) {
        if (valid(key, entry, now)) {
          keep(key, entry);
        }
      }
      log(`lane record cache: ${runs.size} settled runs from run ${uploader}`);
    } catch (error) {
      log(`::warning::the ${LANE_RECORD_CACHE} artifact was not read (${error.message}); lane runs are read live`);
    }
  };
  let loading;
  const load = () => (loading ??= read());
  return {
    async get(runId) {
      await load();
      const kept = runs.get(String(runId));
      if (!kept) {
        return undefined;
      }
      kept.entry.seen = seen;
      const { run, entries, recorded } = kept.entry;
      return { run, entries, recorded: new Set(recorded) };
    },
    async put(runId, { run, entries, recorded, expiresAt }) {
      await load();
      if (String(run?.id) !== String(runId) || !Number.isFinite(expiresAt)) {
        return;
      }
      const key = `${run.id}/${run.run_attempt}`;
      const entry = {
        seen,
        expires: new Date(expiresAt).toISOString(),
        run: { ...pick(run, RUN_FIELDS), head_repository: { full_name: run.head_repository?.full_name } },
        entries: entries.filter((e) => isObject(e) && typeof e.sha256 === "string").map((e) => pick(e, ENTRY_FIELDS)),
        recorded: [...recorded],
      };
      if (valid(key, entry, now)) {
        keep(key, entry);
      }
    },
    save(path) {
      if (loading === undefined) {
        return false;
      }
      try {
        const kept = Object.fromEntries([...runs.values()].filter(({ entry }) => fresh(entry, now)).map(({ key, entry }) => [key, entry]));
        writeFileSync(path, JSON.stringify({ version: VERSION, repo: repository, runs: kept }));
        log(`lane record cache: saved ${Object.keys(kept).length} settled runs`);
        return true;
      } catch (error) {
        log(`::warning::the lane record cache was not saved (${error.message})`);
        return false;
      }
    },
  };
}
