import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { main } from "./lookup.mjs";

const FIXTURES = join(fileURLToPath(new URL(".", import.meta.url)), "fixtures", "data");

async function run(args, deps = {}) {
  const out = [];
  const err = [];
  const code = await main(["--data-dir", deps.dataDir ?? FIXTURES, ...args], {
    fetch: deps.fetch,
    out: (line) => out.push(line),
    err: (line) => err.push(line),
  });
  return { code, records: out.map((line) => JSON.parse(line)), errors: err.map((line) => JSON.parse(line)) };
}
const ids = (records) => records.map((r) => r.id).sort();
const SOLO = {
  id: "example-solo",
  name: "Example Solo",
  aliases: [],
  concern: "quality",
  kind: "practice",
  stage: "review",
  reversibility: "two-way",
  source_url: "https://example.com/solo",
  owner: "/fixture:solo",
  counterweights: [],
  conflicts_with: [],
};

test("an exact id finds its record", async () => {
  const { code, records } = await run(["example-big-design"]);
  assert.equal(code, 0);
  assert.deepEqual(ids(records), ["example-big-design"]);
});

test("a name matches whatever its case", async () => {
  const { records } = await run(["example small steps"]);
  assert.deepEqual(ids(records), ["example-small-steps"]);
});

test("an alias redirects to the record that carries it", async () => {
  const { records } = await run(["baby steps EXAMPLE"]);
  assert.deepEqual(ids(records), ["example-small-steps"]);
});

test("a merged id kept as an alias redirects to the surviving record", async () => {
  const { records } = await run(["example-old-gate"]);
  assert.deepEqual(ids(records), ["example-review-gate"]);
});

test("each tag filter keeps only the records carrying that tag", async () => {
  assert.deepEqual(ids((await run(["--concern", "change-size"])).records), ["example-big-design", "example-small-steps"]);
  assert.deepEqual(ids((await run(["--kind", "principle"])).records), ["example-big-design"]);
  assert.deepEqual(ids((await run(["--reversibility", "one-way"])).records), ["example-big-design"]);
  assert.deepEqual(ids((await run(["--topic", "beta"])).records), ["example-review-gate"]);
});

test("a stage filter also keeps records whose stage is any", async () => {
  const { records } = await run(["--stage", "build"]);
  assert.deepEqual(ids(records), ["example-review-gate", "example-small-steps"]);
});

test("a stage outside the contract's values is refused with exit 2", async () => {
  const { code, errors } = await run(["--stage", "deploy"]);
  assert.equal(code, 2);
  assert.equal(errors[0].option, "stage");
});

test("exclude drops records by id and by topic, unioned across repeats", async () => {
  const { records } = await run(["--exclude", "example-small-steps", "--exclude", "beta"]);
  assert.deepEqual(ids(records), ["example-big-design"]);
});

test("an excluded record is not found by its name either", async () => {
  const { code } = await run(["Example Small Steps", "--exclude", "example-small-steps"]);
  assert.equal(code, 1);
});

test("source_bar official keeps every record and official-plus-confirming keeps only confirmed ones", async () => {
  assert.equal((await run(["--source-bar", "official"])).records.length, 3);
  assert.deepEqual(ids((await run(["--source-bar", "official-plus-confirming"])).records), ["example-small-steps"]);
});

test("counterweights and conflicts come out as id and name, an alias resolved to its record", async () => {
  const [record] = (await run(["example-big-design"])).records;
  assert.deepEqual(record.counterweights, [{ id: "example-small-steps", name: "Example Small Steps" }]);
  assert.deepEqual(record.conflicts_with, [{ id: "example-review-gate", name: "Example Review Gate" }]);
});

test("a counterweight naming no record keeps its id with a null name", async () => {
  const dataDir = mkdtempSync(join(tmpdir(), "ec-lookup-"));
  try {
    writeFileSync(join(dataDir, "solo.jsonl"), `${JSON.stringify({ ...SOLO, counterweights: ["example-missing"] })}\n`);
    const [record] = (await run(["example-solo"], { dataDir })).records;
    assert.deepEqual(record.counterweights, [{ id: "example-missing", name: null }]);
  } finally {
    rmSync(dataDir, { recursive: true, force: true });
  }
});

test("check-sources marks an unreachable source for re-sourcing and keeps the record", async () => {
  const fetched = [];
  const fetch = async (url) => {
    fetched.push(url);
    if (url === "https://example.com/big-design") return { ok: false, status: 404 };
    if (url === "https://example.com/review-gate") throw new Error("getaddrinfo ENOTFOUND");
    return { ok: true, status: 200 };
  };
  const { code, records } = await run(["--check-sources"], { fetch });
  assert.equal(code, 0);
  assert.deepEqual(fetched.sort(), ["https://example.com/big-design", "https://example.com/review-gate", "https://example.com/small-steps"]);
  const byId = Object.fromEntries(records.map((r) => [r.id, r]));
  assert.deepEqual(byId["example-small-steps"].source_check, { reachable: true, status: 200 });
  assert.deepEqual(byId["example-big-design"].source_check, { reachable: false, status: 404, needs_resourcing: true });
  assert.equal(byId["example-review-gate"].source_check.reachable, false);
  assert.equal(byId["example-review-gate"].source_check.needs_resourcing, true);
  assert.match(byId["example-review-gate"].source_check.error, /ENOTFOUND/u);
});

test("a malformed line is reported with file:line on stderr while the other records load", async () => {
  const dataDir = mkdtempSync(join(tmpdir(), "ec-lookup-"));
  try {
    writeFileSync(join(dataDir, "broken.jsonl"), `${JSON.stringify(SOLO)}\n{"id": "half-written"\n${JSON.stringify({ ...SOLO, id: "example-stageless", name: "Stageless", stage: "deploy" })}\n`);
    const { code, records, errors } = await run([], { dataDir });
    assert.equal(code, 0);
    assert.deepEqual(ids(records), ["example-solo"]);
    assert.deepEqual(errors.map((e) => e.at), [`${join(dataDir, "broken.jsonl")}:2`, `${join(dataDir, "broken.jsonl")}:3`]);
  } finally {
    rmSync(dataDir, { recursive: true, force: true });
  }
});

test("run as a command, it prints JSON lines and sets the exit code", () => {
  const script = fileURLToPath(new URL("./lookup.mjs", import.meta.url));
  const hit = spawnSync(process.execPath, [script, "tiny-steps", "--data-dir", FIXTURES], { encoding: "utf8" });
  assert.equal(hit.status, 0);
  assert.equal(JSON.parse(hit.stdout.trim()).id, "example-small-steps");
  const miss = spawnSync(process.execPath, [script, "nothing-here", "--data-dir", FIXTURES], { encoding: "utf8" });
  assert.equal(miss.status, 1);
});

test("a term that names no record exits 1 with nothing on stdout", async () => {
  const { code, records } = await run(["no-such-concept"]);
  assert.equal(code, 1);
  assert.deepEqual(records, []);
});
