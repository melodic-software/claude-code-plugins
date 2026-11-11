// GENERATED from .github/scripts/lib/lane-binding.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:
// edit the canonical source, then rerun the script.
// Whether a github-actions[bot] comment footed `claude-lane: <lane>` is that
// review lane's own. Any workflow's job token posts as github-actions[bot], so
// the footer alone proves nothing. The lane (ci-workflows pr-review-cli.yml,
// publish-review and apply-review-hold) writes a binding line above the
// footer, `<!-- claude-lane-run id=<run> sha=<head> -->`, and its status job
// uploads an artifact, `claude-lane-comments-<lane>-<attempt>`, whose
// comments.jsonl lists each comment it posted: lane, pull request, head, kind
// (review_comment, issue_comment or review), id and the sha256 of the body as
// GitHub stored it. Only a run's own steps upload its artifacts, so a comment
// counts only when the run its binding names is the lane's caller workflow in
// this repository, ran on the head the binding names, and one of that run's
// records lists the comment's kind, id and body digest for the same lane,
// pull request and head. Every attempt's record counts, so a re-run's
// comments stay bound. A record covers its attempt only when it ends with
// the `{"complete":true}` line the lane writes once its publish and hold
// steps did not fail; an attempt without one is treated as one that left no
// record.
//
// A comment without a binding was posted before the lanes wrote one: it counts
// while LEGACY_CUTOFF is null, then only when posted at or before it and never
// edited. A comment no live record lists, of a finished run one of whose
// attempts left no live record of the lane (expired by artifact retention, or
// a job lost before its upload step), is proved by time instead: posted
// between the run's creation and its last update, and never edited. A comment
// no record lists yet, of a run still going, throws, so the caller reads
// again later. Reads that fail throw, so a caller fails closed and re-runs
// rather than dropping a comment it could not check.
//
// Node builtins only: ci-workflows' settled-threads step loads the review
// plugin's copy (plugins/review/lib/lane-binding.mjs) from a clone of this
// repository's default branch.

import { createHash } from "node:crypto";
import { inflateRawSync } from "node:zlib";

// Each lane's caller workflow, the only workflow whose runs bind its comments
// (babysit_review_evidence.py LANES holds the same table).
export const LANE_WORKFLOWS = Object.freeze({
  "claude-review": ".github/workflows/pr-review-hosted.yml",
  "claude-security-review": ".github/workflows/pr-review-security-hosted.yml",
});
export const RECORD_PREFIX = "claude-lane-comments-";
export const RECORD_FILE = "comments.jsonl";
// The largest record read: far above one run's comments, small enough that a
// crafted archive cannot exhaust memory.
export const MAX_RECORD_BYTES = 4 << 20;
// The last time a comment with no binding can be the lane's (ISO 8601): 48
// hours after the lanes began writing bindings, so a run that started before
// then, and a re-run of one within the lost-run reconciler's 24-hour
// lookback, still posts comments that count.
export const LEGACY_CUTOFF = "2026-11-13T22:24:32Z";
// A REST comment carries no edit time, only updated_at, which a review's
// batch sets up to a second after created_at; a gap past this counts as an
// edit (GraphQL's lastEditedAt is exact and wins when present).
const EDIT_SLACK_MS = 60_000;

// A lane footer line, trimmed: the one pattern every reader matches it with.
export const FOOTER = /^`?claude-lane: (claude-review|claude-security-review)`?$/;
export const BINDING = /^<!-- claude-lane-run id=([1-9][0-9]{0,19}) sha=([0-9a-f]{40}) -->$/;

const lines = (body) => String(body ?? "").replace(/\r\n/g, "\n").split("\n");
const nonBlankIndexes = (all) => all.flatMap((line, i) => (line.trim() === "" ? [] : [i]));

// The lane a body's last non-blank line names as its footer, or null.
export function laneFooter(body) {
  const all = lines(body);
  const last = nonBlankIndexes(all).at(-1);
  return last === undefined ? null : (FOOTER.exec(all[last].trim())?.[1] ?? null);
}

// { runId, sha } from the binding on the last non-blank line above a footed
// body's footer, or null.
export function bindingOf(body) {
  const all = lines(body);
  const at = nonBlankIndexes(all);
  if (at.length < 2 || laneFooter(body) === null) {
    return null;
  }
  const match = BINDING.exec(all[at.at(-2)].trim());
  return match ? { runId: match[1], sha: match[2] } : null;
}

// The body without its binding line, the shape every reader parsed before the
// lanes wrote one.
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

// The body with its binding line and every trailing lane footer removed: a
// comment its lane's run did not post, read as one with no footer.
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

// Whether a comment was edited after it was posted: GraphQL's lastEditedAt
// when the reader has it, else REST updated_at past created_at by more than
// EDIT_SLACK_MS.
export function wasEdited({ createdAt, updatedAt, lastEditedAt } = {}) {
  if (lastEditedAt !== undefined) {
    return lastEditedAt !== null;
  }
  const gap = Date.parse(updatedAt ?? "") - Date.parse(createdAt ?? "");
  return Number.isFinite(gap) && gap > EDIT_SLACK_MS;
}

// Whether a comment with no binding still counts.
export function legacyCounts(comment, cutoff = LEGACY_CUTOFF) {
  if (cutoff === null) {
    return true;
  }
  return Date.parse(comment.createdAt ?? "") <= Date.parse(cutoff) && !wasEdited(comment);
}

// One file's bytes from a zip archive (stored or deflated), or null when the
// archive does not hold it.
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

// The entries of one record's comments.jsonl; a line that is not an object is
// skipped.
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

// A checker for one pull request's lane comments. `getPull(pr)` reads
// /pulls/<pr>, `getRun(id)` /actions/runs/<id>, `listArtifacts(id)` that
// run's artifacts (every page), `download(artifactId)` an artifact's zip
// bytes. The pull request and each run are read once, and only for a comment
// that carries a binding. A run counts only when it ran on the pull request's
// own head branch: a pull_request run takes its workflow from the head, so a
// run of another branch could have written any record.
// `check({ kind, id, body, createdAt, updatedAt, lastEditedAt })` resolves
// true when the comment is its footer lane's own. A comment with no lane
// footer is not a lane comment: false.
export function laneChecker({ pr, getPull, getRun, listArtifacts, download, workflows = LANE_WORKFLOWS, cutoff = LEGACY_CUTOFF }) {
  const runs = new Map();
  let pull;
  const readPull = () => {
    pull ??= getPull(Number(pr));
    return pull;
  };
  const readRun = (runId) => {
    if (!runs.has(runId)) {
      runs.set(
        runId,
        (async () => {
          const run = await getRun(runId);
          const records = (await listArtifacts(runId)).filter((a) => String(a?.name ?? "").startsWith(RECORD_PREFIX));
          const live = records.filter((a) => a.expired !== true);
          const entries = [];
          const recorded = new Set();
          for (const artifact of live) {
            const lines = recordEntries(zipEntry(await download(artifact.id), RECORD_FILE)?.toString("utf8"));
            entries.push(...lines);
            if (lines.some((e) => e.complete === true)) {
              recorded.add(artifact.name);
            }
          }
          return { run, entries, recorded };
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
    const { run, entries, recorded } = await readRun(binding.runId);
    const head = (await readPull())?.head;
    if (
      String(run?.id) !== binding.runId ||
      run?.path !== workflows[lane] ||
      run?.head_sha !== binding.sha ||
      typeof run?.head_branch !== "string" ||
      run.head_branch !== head?.ref ||
      run.head_repository?.full_name !== head?.repo?.full_name
    ) {
      return false;
    }
    const digest = bodyDigest(comment.body);
    const listed = entries.some(
      (e) =>
        e.lane === lane &&
        e.pr === Number(pr) &&
        e.head === binding.sha &&
        e.kind === comment.kind &&
        e.id === Number(comment.id) &&
        e.sha256 === digest,
    );
    if (listed) {
      return true;
    }
    // A run still going may not have uploaded the record of the attempt that
    // posted this comment yet.
    if (run.status !== "completed") {
      throw new Error(`lane run ${binding.runId} is still running, so its comment record may not be uploaded yet`);
    }
    // Every attempt left a live record of this lane, and none lists it.
    const attempts = Number.isSafeInteger(run.run_attempt) && run.run_attempt > 0 ? run.run_attempt : 1;
    if (Array.from({ length: attempts }, (_, i) => `${RECORD_PREFIX}${lane}-${i + 1}`).every((name) => recorded.has(name))) {
      return false;
    }
    const at = Date.parse(comment.createdAt ?? "");
    return Date.parse(run.created_at) <= at && at <= Date.parse(run.updated_at) && !wasEdited(comment);
  };
}
