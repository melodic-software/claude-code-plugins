import { createHash } from "node:crypto";
import { inflateRawSync } from "node:zlib";

export class LaneRunPending extends Error {}

export const LANE_WORKFLOWS = Object.freeze({
  "claude-review": ".github/workflows/pr-review-hosted.yml",
  "claude-security-review": ".github/workflows/pr-review-security-hosted.yml",
});
export const RECORD_PREFIX = "claude-lane-comments-";
export const RECORD_FILE = "comments.jsonl";
export const MAX_RECORD_BYTES = 4 << 20;
export const LEGACY_CUTOFF = "2026-11-13T22:24:32Z";
const EDIT_SLACK_MS = 60_000;

export const FOOTER = /^`?claude-lane: (claude-review|claude-security-review)`?$/;
export const BINDING = /^<!-- claude-lane-run id=([1-9][0-9]{0,19}) sha=([0-9a-f]{40}) -->$/;

const lines = (body) => String(body ?? "").replace(/\r\n/g, "\n").split("\n");
const nonBlankIndexes = (all) => all.flatMap((line, i) => (line.trim() === "" ? [] : [i]));

export function laneFooter(body) {
  const all = lines(body);
  const last = nonBlankIndexes(all).at(-1);
  return last === undefined ? null : (FOOTER.exec(all[last].trim())?.[1] ?? null);
}

export function bindingOf(body) {
  const all = lines(body);
  const at = nonBlankIndexes(all);
  if (at.length < 2 || !FOOTER.test(all[at.at(-1)].trim())) {
    return null;
  }
  const match = BINDING.exec(all[at.at(-2)].trim());
  return match ? { runId: match[1], sha: match[2] } : null;
}

export function withoutBinding(body) {
  const text = String(body ?? "");
  if (bindingOf(text) === null) {
    return text;
  }
  const all = text.split("\n");
  const at = nonBlankIndexes(all.map((line) => line.replace(/\r$/, "")));
  all.splice(at.at(-2), 1);
  return all.join("\n");
}

export function withoutLaneFooters(body) {
  const all = String(body ?? "").split("\n");
  for (;;) {
    const last = all.findLastIndex((line) => line.trim() !== "");
    const line = last === -1 ? "" : all[last].trim();
    if (!FOOTER.test(line) && !BINDING.test(line)) {
      return all.slice(0, last + 1).join("\n");
    }
    all.splice(last);
  }
}

export const bodyDigest = (body) => createHash("sha256").update(String(body ?? ""), "utf8").digest("hex");

export function wasEdited({ createdAt, updatedAt, lastEditedAt } = {}) {
  if (lastEditedAt !== undefined) {
    return lastEditedAt !== null;
  }
  const gap = Date.parse(updatedAt ?? "") - Date.parse(createdAt ?? "");
  return Number.isFinite(gap) && gap > EDIT_SLACK_MS;
}

export function legacyCounts(comment, cutoff = LEGACY_CUTOFF) {
  return cutoff === null || (Date.parse(comment.createdAt ?? "") <= Date.parse(cutoff) && !wasEdited(comment));
}

export function zipEntry(zip, name) {
  const buf = Buffer.from(zip);
  let end = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65_557); i -= 1) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
      end = i;
      break;
    }
  }
  if (end < 0) {
    throw new Error("not a zip archive");
  }
  let at = buf.readUInt32LE(end + 16);
  for (let n = buf.readUInt16LE(end + 10); n > 0; n -= 1) {
    if (buf.readUInt32LE(at) !== 0x02014b50) {
      throw new Error("a malformed zip directory");
    }
    const method = buf.readUInt16LE(at + 10);
    const size = buf.readUInt32LE(at + 20);
    const nameLength = buf.readUInt16LE(at + 28);
    const skip = nameLength + buf.readUInt16LE(at + 30) + buf.readUInt16LE(at + 32);
    const local = buf.readUInt32LE(at + 42);
    if (buf.toString("utf8", at + 46, at + 46 + nameLength) === name) {
      const start = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
      const data = buf.subarray(start, start + size);
      if (buf.readUInt32LE(at + 24) > MAX_RECORD_BYTES) {
        throw new Error(`${name} is over ${MAX_RECORD_BYTES} bytes`);
      }
      if (method === 0) {
        return data;
      }
      if (method === 8) {
        return inflateRawSync(data, { maxOutputLength: MAX_RECORD_BYTES });
      }
      throw new Error(`zip method ${method} is not read`);
    }
    at += 46 + skip;
  }
  return null;
}

export function recordEntries(text) {
  return String(text ?? "")
    .split("\n")
    .flatMap((line) => {
      try {
        const entry = JSON.parse(line);
        return entry && typeof entry === "object" && !Array.isArray(entry) ? [entry] : [];
      } catch {
        return [];
      }
    });
}

const attemptRecords = (run, lane) => {
  const attempts = Number.isSafeInteger(run.run_attempt) && run.run_attempt > 0 ? run.run_attempt : 1;
  return Array.from({ length: attempts }, (_, i) => `${RECORD_PREFIX}${lane}-${i + 1}`);
};

export function settledRun({ run, recorded }, workflows = LANE_WORKFLOWS) {
  const lane = Object.keys(workflows).find((name) => workflows[name] === run?.path);
  return lane !== undefined && run.status === "completed" && attemptRecords(run, lane).every((name) => recorded.has(name));
}

export function laneChecker({ pr, getPull, getRun, listArtifacts, download, workflows = LANE_WORKFLOWS, cutoff = LEGACY_CUTOFF, store }) {
  const runs = new Map();
  let pull;
  const readPull = () => (pull ??= getPull(Number(pr)));
  const loadRun = async (runId) => {
    const run = await getRun(runId);
    const live = (await listArtifacts(runId)).filter((a) => String(a?.name ?? "").startsWith(RECORD_PREFIX) && a.expired !== true);
    const entries = [];
    const recorded = new Set();
    for (const artifact of live) {
      const record = recordEntries(zipEntry(await download(artifact.id), RECORD_FILE)?.toString("utf8"));
      entries.push(...record);
      if (record.some((e) => e.complete === true)) {
        recorded.add(artifact.name);
      }
    }
    const expiresAt = Math.min(...live.map((a) => Date.parse(a.expires_at ?? "")));
    const loaded = { run, entries, recorded, expiresAt };
    if (store && settledRun(loaded, workflows)) {
      await store.put(runId, loaded);
    }
    return loaded;
  };
  const readRun = (runId) => {
    if (!runs.has(runId)) {
      runs.set(
        runId,
        (async () => {
          const stored = await store?.get(runId);
          return stored ? { ...stored, stored: true } : loadRun(runId);
        })(),
      );
    }
    return runs.get(runId);
  };
  return async function check(comment) {
    const lane = laneFooter(comment.body);
    if (lane === null) {
      return false;
    }
    const binding = bindingOf(comment.body);
    if (binding === null) {
      return legacyCounts(comment, cutoff);
    }
    let loaded = await readRun(binding.runId);
    const head = (await readPull())?.head;
    const digest = bodyDigest(comment.body);
    const ranOnHead = ({ run }) =>
      String(run?.id) === binding.runId &&
      run?.path === workflows[lane] &&
      run?.head_sha === binding.sha &&
      typeof run?.head_branch === "string" &&
      run.head_branch === head?.ref &&
      run.head_repository?.full_name === head?.repo?.full_name;
    const lists = ({ entries }) =>
      entries.some(
        (e) =>
          e.lane === lane &&
          e.pr === Number(pr) &&
          e.head === binding.sha &&
          e.kind === comment.kind &&
          e.id === Number(comment.id) &&
          e.sha256 === digest,
      );
    if (loaded.stored && ranOnHead(loaded) && !lists(loaded)) {
      runs.set(binding.runId, loadRun(binding.runId));
      loaded = await runs.get(binding.runId);
    }
    const { run, recorded } = loaded;
    if (!ranOnHead(loaded)) {
      return false;
    }
    if (lists(loaded)) {
      return true;
    }
    if (run.status !== "completed") {
      throw new LaneRunPending(`lane run ${binding.runId} is still running, so its comment record may not be uploaded yet`);
    }
    if (attemptRecords(run, lane).every((name) => recorded.has(name))) {
      return false;
    }
    const at = Date.parse(comment.createdAt ?? "");
    return Date.parse(run.created_at) <= at && at <= Date.parse(run.updated_at) && !wasEdited(comment);
  };
}
