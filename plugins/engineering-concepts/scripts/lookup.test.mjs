import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { main } from "./lookup.mjs";

process.env.GIT_CONFIG_GLOBAL ??= "/dev/null";
process.env.GIT_CONFIG_NOSYSTEM = "1";

const FIXTURES = join(fileURLToPath(new URL(".", import.meta.url)), "fixtures", "data");
const scratch = mkdtempSync(join(tmpdir(), "ec-lookup-settings-"));
after(() => rmSync(scratch, { recursive: true, force: true }));
const HOME = join(scratch, "home");
mkdirSync(HOME);
let count = 0;

function repo(files = {}) {
  const dir = join(scratch, `repo-${++count}`);
  mkdirSync(dir);
  assert.equal(spawnSync("git", ["init", "-q", dir]).status, 0);
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  return dir;
}
const EMPTY_REPO = repo();
const TEAM = "docs/conventions/engineering-concepts.yaml";

function userConfigFile(values) {
  const file = join(scratch, `user-config-${++count}.json`);
  writeFileSync(file, JSON.stringify(values));
  return file;
}

async function run(args, deps = {}) {
  const out = [];
  const err = [];
  const base = [...(deps.shippedDataDir ? [] : ["--data-dir", deps.dataDir ?? FIXTURES]), "--project", deps.project ?? EMPTY_REPO, "--home", HOME];
  if (deps.userConfig) base.push("--user-config", userConfigFile(deps.userConfig));
  const code = await main([...base, ...args], {
    fetch: deps.fetch,
    shippedDataDir: deps.shippedDataDir,
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

test("an owner that is neither an https URL nor a plugin:skill name is rejected with file:line while the others load", async () => {
  const dataDir = mkdtempSync(join(tmpdir(), "ec-lookup-"));
  const owners = ["fixture:solo", "/fixture:solo", "https://example.com/owner", "http://example.com/x", "just some text", "fixture:", "/fixture", "Fixture:Solo"];
  try {
    const lines = owners.map((owner, i) => JSON.stringify({ ...SOLO, id: `example-owner-${i}`, name: `Owner ${i}`, owner }));
    writeFileSync(join(dataDir, "owners.jsonl"), `${lines.join("\n")}\n`);
    const { code, records, errors } = await run([], { dataDir });
    assert.equal(code, 0);
    assert.deepEqual(ids(records), ["example-owner-0", "example-owner-1", "example-owner-2"]);
    assert.deepEqual(
      errors.map((e) => [e.at, e.reason]),
      [3, 4, 5, 6, 7].map((n) => [`${join(dataDir, "owners.jsonl")}:${n + 1}`, "owner is neither an https URL nor a plugin:skill name"]),
    );
  } finally {
    rmSync(dataDir, { recursive: true, force: true });
  }
});

test("run as a command, it prints JSON lines and sets the exit code", () => {
  const script = fileURLToPath(new URL("./lookup.mjs", import.meta.url));
  const common = ["--data-dir", FIXTURES, "--project", EMPTY_REPO, "--home", HOME];
  const hit = spawnSync(process.execPath, [script, "tiny-steps", ...common], { encoding: "utf8" });
  assert.equal(hit.status, 0);
  assert.equal(JSON.parse(hit.stdout.trim()).id, "example-small-steps");
  const miss = spawnSync(process.execPath, [script, "nothing-here", ...common], { encoding: "utf8" });
  assert.equal(miss.status, 1);
});

test("--user-config - reads name=value lines from stdin and treats an unrendered placeholder as unset", () => {
  const script = fileURLToPath(new URL("./lookup.mjs", import.meta.url));
  const r = spawnSync(process.execPath, [script, "--data-dir", FIXTURES, "--project", EMPTY_REPO, "--home", HOME, "--user-config", "-"], {
    encoding: "utf8",
    input: "source_bar=${user_config.source_bar}\nexclude=beta,example-big-design\n",
  });
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(r.stdout.trim().split("\n").map((line) => JSON.parse(line).id), ["example-small-steps"]);
});

test("a legacy config file under --home is reported on stderr and not read", () => {
  const script = fileURLToPath(new URL("./lookup.mjs", import.meta.url));
  const home = join(scratch, "legacy-home");
  mkdirSync(join(home, ".claude"), { recursive: true });
  const legacy = join(home, ".claude", "engineering-concepts.yaml");
  writeFileSync(legacy, "exclude: [example-small-steps]\n");
  const r = spawnSync(process.execPath, [script, "tiny-steps", "--data-dir", FIXTURES, "--project", EMPTY_REPO, "--home", home], { encoding: "utf8" });
  assert.equal(r.status, 0, r.stderr);
  assert.equal(JSON.parse(r.stdout.trim()).id, "example-small-steps");
  assert.deepEqual(r.stderr.trim().split("\n").map((line) => JSON.parse(line)), [{ level: "warn", event: "legacy config", path: legacy, kind: "claude-user" }]);
});

test("with no setting in any layer, source_bar is official and nothing is excluded", async () => {
  const { records, errors } = await run([]);
  assert.equal(records.length, 3);
  assert.deepEqual(errors, []);
});

test("the user's source_bar option applies when no repository layer sets it", async () => {
  const { records } = await run([], { userConfig: { source_bar: "official-plus-confirming" } });
  assert.deepEqual(ids(records), ["example-small-steps"]);
});

test("the repository team file's source_bar wins over the user's option", async () => {
  const project = repo({ [TEAM]: "source_bar: official-plus-confirming\n" });
  const { records } = await run([], { project, userConfig: { source_bar: "official" } });
  assert.deepEqual(ids(records), ["example-small-steps"]);
});

test("exclude is the union of the user option, the team file, the personal file and the flag", async () => {
  const project = repo({
    [TEAM]: "exclude:\n  - beta\n",
    "docs/conventions/engineering-concepts.local.yaml": "exclude:\n  - example-big-design\n",
  });
  const all = await run([], { project, userConfig: { exclude: "example-small-steps" } });
  assert.deepEqual(ids(all.records), []);
  const teamOnly = repo({ [TEAM]: "exclude:\n  - beta\n" });
  const withoutLocal = await run([], { project: teamOnly, userConfig: { exclude: "example-small-steps" } });
  assert.deepEqual(ids(withoutLocal.records), ["example-big-design"]);
  const withFlag = await run(["--exclude", "example-big-design"], { project: teamOnly, userConfig: { exclude: "example-small-steps" } });
  assert.deepEqual(ids(withFlag.records), []);
});

test("an invalid team source_bar is reported and falls back to the default, not to the user's option", async () => {
  const project = repo({ [TEAM]: "source_bar: loose\n" });
  const { records, errors } = await run([], { project, userConfig: { source_bar: "official-plus-confirming" } });
  assert.equal(records.length, 3);
  const rejected = errors.filter((e) => e.event === "setting rejected");
  assert.equal(rejected.length, 1);
  assert.equal(rejected[0].layer, "team");
});

test("the --source-bar flag overrides every settings layer for one run", async () => {
  const project = repo({ [TEAM]: "source_bar: official-plus-confirming\n" });
  const { records } = await run(["--source-bar", "official"], { project });
  assert.equal(records.length, 3);
});

test("a missing shipped data directory is an empty catalog: exit 1, one info note, no error", async () => {
  const { code, records, errors } = await run(["anything"], { shippedDataDir: join(scratch, "no-such-data") });
  assert.equal(code, 1);
  assert.deepEqual(records, []);
  assert.deepEqual(errors.map((e) => [e.level, e.event]), [["info", "catalog empty"]]);
});

test("an empty shipped data directory reads the same as a missing one", async () => {
  const empty = join(scratch, "empty-data");
  mkdirSync(empty);
  const { code, errors } = await run([], { shippedDataDir: empty });
  assert.equal(code, 1);
  assert.deepEqual(errors.map((e) => [e.level, e.event]), [["info", "catalog empty"]]);
});

test("an unreadable --data-dir the caller passed is still an error", async () => {
  const { code, errors } = await run(["anything"], { dataDir: join(scratch, "typo-data") });
  assert.equal(code, 1);
  assert.deepEqual(errors.map((e) => [e.level, e.event]), [["error", "data directory unreadable"]]);
});

test("a term that names no record exits 1 with nothing on stdout", async () => {
  const { code, records } = await run(["no-such-concept"]);
  assert.equal(code, 1);
  assert.deepEqual(records, []);
});
