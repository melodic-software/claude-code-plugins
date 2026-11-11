// Test fixtures for lane-binding.mjs consumers: a zip writer, a record entry
// and a fake Actions API serving runs and their comment records.
import { crc32, deflateRawSync } from "node:zlib";

import { bodyDigest, LANE_WORKFLOWS, RECORD_FILE, RECORD_PREFIX } from "./lane-binding.mjs";

export const HEAD = "a".repeat(40);
export const RUN = 4242;
// The pull request's head branch and repository the fake runs ran on.
export const BRANCH = "feature/x";
export const REPOSITORY = "o/r";

// A body as the lane posts it: text, the binding, a blank line, the footer.
export const bound = (text, { run = RUN, sha = HEAD, lane = "claude-review" } = {}) =>
  `${text}\n<!-- claude-lane-run id=${run} sha=${sha} -->\n\nclaude-lane: ${lane}`;

// One comments.jsonl line for `body`.
export const recordEntry = (body, overrides = {}) => ({
  lane: "claude-review",
  pr: 7,
  head: HEAD,
  kind: "review_comment",
  id: 11,
  sha256: bodyDigest(body),
  ...overrides,
});

// A run of `lane`'s caller workflow whose one record lists `entries`.
export const laneRun = (entries, { lane = "claude-review", attempt = 1, ...rest } = {}) => ({
  path: LANE_WORKFLOWS[lane],
  artifacts: [{ name: `${RECORD_PREFIX}${lane}-${attempt}`, entries }],
  ...rest,
});

// A zip holding `files` ({ name: text }), deflated, as upload-artifact writes one.
export function zipOf(files) {
  const locals = [];
  const central = [];
  let offset = 0;
  for (const [name, text] of Object.entries(files)) {
    const raw = Buffer.from(text, "utf8");
    const data = deflateRawSync(raw);
    const nameBytes = Buffer.from(name, "utf8");
    const header = Buffer.alloc(30);
    header.writeUInt32LE(0x04034b50, 0);
    header.writeUInt16LE(20, 4);
    header.writeUInt16LE(8, 8);
    header.writeUInt32LE(crc32(raw), 14);
    header.writeUInt32LE(data.length, 18);
    header.writeUInt32LE(raw.length, 22);
    header.writeUInt16LE(nameBytes.length, 26);
    locals.push(header, nameBytes, data);
    const entry = Buffer.alloc(46);
    entry.writeUInt32LE(0x02014b50, 0);
    entry.writeUInt16LE(20, 4);
    entry.writeUInt16LE(20, 6);
    entry.writeUInt16LE(8, 10);
    entry.writeUInt32LE(crc32(raw), 16);
    entry.writeUInt32LE(data.length, 20);
    entry.writeUInt32LE(raw.length, 24);
    entry.writeUInt16LE(nameBytes.length, 28);
    entry.writeUInt32LE(offset, 42);
    central.push(entry, nameBytes);
    offset += 30 + nameBytes.length + data.length;
  }
  const dir = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(central.length / 2, 8);
  end.writeUInt16LE(central.length / 2, 10);
  end.writeUInt32LE(dir.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, dir, end]);
}

// A fake Actions API: runs by id, each with artifacts { name, expired, entries };
// the pull request's head is BRANCH in REPOSITORY unless `pull` says otherwise.
export function fakeActions(runs, pull = { head: { ref: BRANCH, repo: { full_name: REPOSITORY } } }) {
  const calls = [];
  const blobs = new Map();
  let next = 1;
  for (const run of Object.values(runs)) {
    for (const artifact of run.artifacts ?? []) {
      artifact.id = next++;
      // A record the lane closed, unless the fake says it was cut off.
      const lines = [...artifact.entries, ...(artifact.complete === false ? [] : [{ complete: true }])];
      blobs.set(artifact.id, zipOf({ [RECORD_FILE]: lines.map((e) => JSON.stringify(e)).join("\n") }));
    }
  }
  return {
    calls,
    getPull: async (pr) => {
      calls.push(["pull", pr]);
      return pull;
    },
    getRun: async (id) => {
      calls.push(["run", id]);
      const run = runs[id];
      if (!run) throw Object.assign(new Error("Not Found"), { status: 404 });
      return {
        id: Number(id),
        path: run.path,
        head_sha: run.head_sha ?? HEAD,
        head_branch: run.head_branch ?? BRANCH,
        head_repository: { full_name: run.head_repository ?? REPOSITORY },
        status: run.status ?? "completed",
        run_attempt: run.run_attempt ?? 1,
        created_at: run.created_at,
        updated_at: run.updated_at,
      };
    },
    listArtifacts: async (id) => {
      calls.push(["artifacts", id]);
      return (runs[id]?.artifacts ?? []).map(({ id: artifactId, name, expired }) => ({ id: artifactId, name, expired: expired === true }));
    },
    download: async (id) => {
      calls.push(["download", id]);
      return blobs.get(id);
    },
  };
}

