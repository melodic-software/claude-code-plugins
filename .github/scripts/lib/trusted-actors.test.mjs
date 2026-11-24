import assert from "node:assert/strict";
import { copyFileSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import process from "node:process";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

import { tempDir } from "../../../lib/test-tmp.mjs";

import { loadTrustedActors as statusList } from "../../actions/resolve-config/read-status.mjs";
import { loadTrustedActors, loadTrustedList as triggerList } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { reviewerIdFrom, trustedHumansFrom } from "../pr-unblock/address-feedback.mjs";
import { dependabotIdFrom } from "../pr-unblock/review-dependency.mjs";
import { readHumans } from "../work-resolve-issue/report-outcome.mjs";
import { LIST_FIXTURE, listCommits } from "./trusted-actors.fixtures.mjs";
import { listBlob, listChangedAt, loadTrustedList, readRawTrustedActors, STANDARDS_LIST_PATH, trustedListPath } from "./trusted-actors.mjs";

const ROOT = fileURLToPath(new URL("../../../", import.meta.url));
const SCRIPTS = join(ROOT, ".github/scripts");
const SAME_TREE_COPY = ".github/standards/trusted-actors/trusted-actors.json";

test("the list is read from the standards checkout STANDARDS_DIR names, else the path the workflow gives; with neither it throws", () => {
  assert.equal(STANDARDS_LIST_PATH, "components/trusted-actors/trusted-actors.json");
  assert.equal(trustedListPath({ STANDARDS_DIR: "/s" }, "/given"), "/s/components/trusted-actors/trusted-actors.json");
  assert.equal(trustedListPath({}, "/given"), "/given");
  for (const [env, given] of [[{}, undefined], [{ STANDARDS_DIR: "" }, ""], [{ BASE_PATH: "/b" }, undefined]]) {
    assert.throws(() => trustedListPath(env, given), /STANDARDS_DIR is unset/, JSON.stringify(env));
  }
});

test("read-status reads the list from STANDARDS_DIR, else TRUSTED_ACTORS_PATH, and never the BASE_PATH copy", () => {
  const standards = tempDir("trusted-actors-standards-");
  mkdirSync(dirname(join(standards, STANDARDS_LIST_PATH)), { recursive: true });
  writeFileSync(join(standards, STANDARDS_LIST_PATH), '{"marker":2}');
  assert.deepEqual(statusList({ STANDARDS_DIR: standards, TRUSTED_ACTORS_PATH: "/missing", BASE_PATH: "/missing" }), { marker: 2 });
  assert.deepEqual(statusList({ TRUSTED_ACTORS_PATH: join(standards, STANDARDS_LIST_PATH), BASE_PATH: "/missing" }), { marker: 2 });
  const copy = tempDir("trusted-actors-copy-");
  const legacy = join(copy, ".github/standards/trusted-actors/trusted-actors.json");
  mkdirSync(dirname(legacy), { recursive: true });
  writeFileSync(legacy, '{"marker":1}');
  assert.throws(() => statusList({ BASE_PATH: copy }), /STANDARDS_DIR is unset/);
  assert.throws(() => statusList({}), /STANDARDS_DIR is unset/, "the default .base copy is not read either");
});

test("resolve-config, which imports nothing from scripts/lib, names the same standards path", () => {
  const source = readFileSync(join(ROOT, ".github/actions/resolve-config/resolve-config.mjs"), "utf8");
  assert.match(source, new RegExp(`\\nconst STANDARDS_TRUSTED_ACTORS_PATH = "${STANDARDS_LIST_PATH.replaceAll(".", "\\.")}";\\n`));
});

test("check-trusted-trigger hands out this module's validated list", () => {
  assert.equal(triggerList, loadTrustedList);
});

const h = { id: 7, login: "Owner", kind: "human" };
const b = { id: 8, login: "claude[bot]", kind: "bot" };
const d = { id: 9, login: "dependabot[bot]", kind: "bot" };
const doc = (actors, extra = {}) => JSON.stringify({ version: 1, actors, ...extra });
const FIXTURES = {
  missing: null,
  "not-json": "{",
  null: "null",
  array: "[]",
  "empty-object": "{}",
  "no-actors": JSON.stringify({ version: 1 }),
  "actors-object": JSON.stringify({ version: 1, actors: {} }),
  "no-version": JSON.stringify({ actors: [h, b, d] }),
  "version-2": JSON.stringify({ version: 2, actors: [h, b, d] }),
  "extra-top-key": doc([h, b, d], { note: "x" }),
  empty: doc([]),
  "actor-extra-key": doc([{ ...h, note: "x" }, b, d]),
  "actor-null": doc([null, h]),
  "id-zero": doc([{ ...h, id: 0 }]),
  "id-negative": doc([{ ...h, id: -3 }]),
  "id-string": doc([{ ...h, id: "7" }, { ...b, id: "8" }, { ...d, id: "9" }]),
  "id-float": doc([{ ...h, id: 1.5 }]),
  "id-unsafe": doc([{ ...h, id: 2 ** 60 }]),
  "kind-unknown": doc([{ ...h, kind: "robot" }]),
  "login-number": doc([{ ...h, login: 5 }]),
  "login-case": doc([h, { id: 10, login: "OWNER", kind: "human" }]),
  "bot-as-human": doc([{ ...b, kind: "human" }, { ...d, kind: "human" }]),
  "no-bots": doc([h]),
};

const COLUMNS = ["loadTrustedList", "loadTrustedActors", "read-status loadTrustedActors", "trustedHumansFrom", "reviewerIdFrom", "dependabotIdFrom", "report-outcome readHumans", "gate-source trustedHumans"];
const RAW = "raw";
const U = 2 ** 60;
const RECORDED_ON_MAIN = {
  missing: ["!Error", "!Error", "!Error", "!Error", "!Error", "!Error", "!Error", []],
  "not-json": ["!SyntaxError", "!SyntaxError", "!SyntaxError", "!SyntaxError", "!SyntaxError", "!SyntaxError", "!SyntaxError", []],
  null: ["!Error", "!Error", RAW, "!TypeError", "!TypeError", "!TypeError", "!Error", []],
  array: ["!Error", "!Error", RAW, [], "!Error", "!Error", "!Error", []],
  "empty-object": ["!Error", "!Error", RAW, [], "!Error", "!Error", "!Error", []],
  "no-actors": ["!Error", "!Error", RAW, [], "!Error", "!Error", "!Error", []],
  "actors-object": ["!Error", "!Error", RAW, "!TypeError", "!TypeError", "!TypeError", "!Error", []],
  "no-version": ["!Error", "!Error", RAW, [7], 8, 9, "!Error", [7]],
  "version-2": ["!Error", "!Error", RAW, [7], 8, 9, "!Error", [7]],
  "extra-top-key": ["!Error", "!Error", RAW, [7], 8, 9, [7], [7]],
  empty: [{ ids: [], humans: [], logins: [] }, [], RAW, [], "!Error", "!Error", [], []],
  "actor-extra-key": ["!Error", "!Error", RAW, [7], 8, 9, [7], [7]],
  "actor-null": ["!Error", "!Error", RAW, "!TypeError", "!TypeError", "!TypeError", [7], [7]],
  "id-zero": ["!Error", "!Error", RAW, "!Error", "!Error", "!Error", [0], [0]],
  "id-negative": ["!Error", "!Error", RAW, "!Error", "!Error", "!Error", [-3], [-3]],
  "id-string": ["!Error", "!Error", RAW, [7], 8, 9, [], []],
  "id-float": ["!Error", "!Error", RAW, "!Error", "!Error", "!Error", [], []],
  "id-unsafe": [{ ids: [U], humans: [U], logins: [["owner", U]] }, [U], RAW, "!Error", "!Error", "!Error", [U], []],
  "kind-unknown": ["!Error", "!Error", RAW, [], "!Error", "!Error", [], []],
  "login-number": ["!Error", "!Error", RAW, [7], "!Error", "!Error", [7], [7]],
  "login-case": [{ ids: [7, 10], humans: [7, 10], logins: [["owner", 10]] }, [7, 10], RAW, [7, 10], "!Error", "!Error", [7, 10], [7, 10]],
  "bot-as-human": [{ ids: [8, 9], humans: [8, 9], logins: [["claude[bot]", 8], ["dependabot[bot]", 9]] }, [8, 9], RAW, [8, 9], "!Error", "!Error", [8, 9], [8, 9]],
  "no-bots": [{ ids: [7], humans: [7], logins: [["owner", 7]] }, [7], RAW, [7], "!Error", "!Error", [7], [7]],
};

const cell = (fn) => {
  try {
    const value = fn();
    return value instanceof Set ? [...value] : value;
  } catch (error) {
    return `!${error.constructor.name}`;
  }
};
const view = (list) => ({ ids: [...list.ids], humans: [...list.humans], logins: [...list.logins] });

function gateSourceCopyBesideFixture() {
  const tree = tempDir("trusted-actors-gate-");
  for (const rel of ["pr-unblock/gate-source.mjs", "pr-unblock/escalation-routes.mjs", "pr-unblock/escalation-routes.json", "lib/lane-binding.mjs", "lib/trusted-actors.mjs"]) {
    mkdirSync(dirname(join(tree, ".github/scripts", rel)), { recursive: true });
    copyFileSync(join(SCRIPTS, rel), join(tree, ".github/scripts", rel));
  }
  mkdirSync(dirname(join(tree, SAME_TREE_COPY)), { recursive: true });
  mkdirSync(dirname(join(tree, STANDARDS_LIST_PATH)), { recursive: true });
  return tree;
}

async function readers(path, text, tree, n) {
  if (text === null) {
    rmSync(join(tree, STANDARDS_LIST_PATH), { force: true });
  } else {
    writeFileSync(join(tree, STANDARDS_LIST_PATH), text);
  }
  const gate = await import(`${pathToFileURL(join(tree, ".github/scripts/pr-unblock/gate-source.mjs")).href}?case=${n}`);
  const saved = process.env.STANDARDS_DIR;
  process.env.STANDARDS_DIR = tree;
  try {
    return [
      cell(() => view(loadTrustedList(path))),
      cell(() => loadTrustedActors(path)),
      cell(() => statusList({ STANDARDS_DIR: tree })),
      cell(() => trustedHumansFrom(path)),
      cell(() => reviewerIdFrom(path)),
      cell(() => dependabotIdFrom(path)),
      cell(() => readHumans(path)),
      cell(() => gate.trustedHumans()),
    ];
  } finally {
    if (saved === undefined) {
      delete process.env.STANDARDS_DIR;
    } else {
      process.env.STANDARDS_DIR = saved;
    }
  }
}

test("every reader, permissive ones included, returns what main returned on each malformed list", async () => {
  const dir = tempDir("trusted-actors-fixtures-");
  const tree = gateSourceCopyBesideFixture();
  let n = 0;
  for (const [name, text] of Object.entries(FIXTURES)) {
    const path = join(dir, `${name}.json`);
    if (text !== null) {
      writeFileSync(path, text);
    }
    const got = await readers(path, text, tree, n++);
    RECORDED_ON_MAIN[name].forEach((want, i) => {
      assert.deepEqual(got[i], want === RAW ? JSON.parse(text) : want, `${COLUMNS[i]} on the ${name} list returns what main returned ("!Name" is a throw)`);
    });
  }
});

test("gate-source reads the standards checkout STANDARDS_DIR names, and with none trusts no one over its same-tree list", async () => {
  const tree = gateSourceCopyBesideFixture();
  writeFileSync(join(tree, SAME_TREE_COPY), doc([h]));
  const standards = tempDir("trusted-actors-gate-standards-");
  mkdirSync(dirname(join(standards, STANDARDS_LIST_PATH)), { recursive: true });
  writeFileSync(join(standards, STANDARDS_LIST_PATH), doc([{ id: 11, login: "Other", kind: "human" }]));
  const saved = process.env.STANDARDS_DIR;
  try {
    process.env.STANDARDS_DIR = standards;
    const gate = await import(`${pathToFileURL(join(tree, ".github/scripts/pr-unblock/gate-source.mjs")).href}?case=standards`);
    assert.deepEqual([...gate.trustedHumans()], [11]);
    delete process.env.STANDARDS_DIR;
    const bare = await import(`${pathToFileURL(join(tree, ".github/scripts/pr-unblock/gate-source.mjs")).href}?case=no-standards`);
    assert.deepEqual([...bare.trustedHumans()], [], "the same-tree copy names 7, and is never read");
  } finally {
    if (saved === undefined) {
      delete process.env.STANDARDS_DIR;
    } else {
      process.env.STANDARDS_DIR = saved;
    }
  }
});

test("on the captured standards list every reader agrees with the validated view", async () => {
  const path = LIST_FIXTURE;
  const text = readFileSync(path, "utf8");
  const tree = gateSourceCopyBesideFixture();
  const list = loadTrustedList(path);
  const humans = [...list.humans];
  assert.ok(humans.length > 0, "the list names a person");
  assert.deepEqual(await readers(path, text, tree, "real"), [
    view(list),
    [...list.ids],
    readRawTrustedActors(path),
    humans,
    list.logins.get("claude[bot]"),
    list.logins.get("dependabot[bot]"),
    humans,
    humans,
  ]);
});

test("listBlob is git's blob id of the bytes", () => {
  assert.equal(listBlob(Buffer.from("")), "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391");
  assert.equal(listBlob(Buffer.from("hello\n")), "ce013625030ba8dba906f756967f9e9ca394464a");
});

test("listChangedAt reads the newest commit touching the list at the standards commit", async () => {
  const sha = "5".repeat(40);
  const reads = [];
  const answering = (answer) => async (method, apiPath) => {
    reads.push(`${method} ${apiPath}`);
    return answer;
  };
  assert.equal(await listChangedAt(answering(listCommits()), sha), "2026-11-21T21:52:10Z");
  assert.deepEqual(reads, [`GET /repos/melodic-software/standards/commits?path=${STANDARDS_LIST_PATH}&sha=${sha}&per_page=1`]);
  assert.equal(await listChangedAt(answering([]), sha), "", "no commit touches the list");
  for (const answer of [null, {}, [{ commit: {} }], listCommits("not a time")]) {
    await assert.rejects(listChangedAt(answering(answer), sha), undefined, JSON.stringify(answer));
  }
  for (const bad of [undefined, "", "5".repeat(39), "main"]) {
    await assert.rejects(listChangedAt(answering([]), bad), /full SHA/, String(bad));
  }
});
