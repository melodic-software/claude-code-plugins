import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import { BORN_TRIAGED_MARKER, checkBornTriaged, humanIds, routingLabels, run } from "./check-born-triaged.mjs";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { mirroredStatusOf, STATUS_CONFIG, STRANGER_ID, TRUSTED_ACTORS, withFields } from "../resolve-config/read-status.fixtures.mjs";
import { statusReader } from "../resolve-config/read-status.mjs";

const SCRIPT = fileURLToPath(new URL("./check-born-triaged.mjs", import.meta.url));

const HUMAN = { id: 153232337, login: "kyle-sexton", kind: "human" };
const LISTED_BOT = { id: 49699333, login: "dependabot[bot]", kind: "bot" };
const LANES_APP = { id: 337595936, login: "melodic-automation-lanes[bot]", kind: "bot" };
const LIST = { version: 1, actors: [HUMAN, LISTED_BOT, LANES_APP] };
const LANES_APP_ID = "337595936";

function issue({ author = HUMAN, body = `## Outcome\n\nx\n\n${BORN_TRIAGED_MARKER}\n`, type = "Feature", labels = ["needs-human"] } = {}) {
  return {
    number: 7,
    user: { id: author.id, login: author.login },
    body,
    type: type ? { name: type } : null,
    labels: labels.map((name) => ({ name })),
  };
}

const check = (overrides, list = LIST, appId = LANES_APP_ID) =>
  checkBornTriaged({ issue: issue(overrides), list, lanesAppId: appId });

test("skips a trusted human's issue that carries the marker, an Issue Type and a status label", () => {
  assert.deepEqual(check({}), { skip: "true", reason: "born-triaged" });
});

test("skips the same issue filed by the lanes App", () => {
  assert.deepEqual(check({ author: LANES_APP }), { skip: "true", reason: "born-triaged" });
});

test("accepts agent-ready and any status: label as the status label", () => {
  assert.equal(check({ labels: ["agent-ready"] }).skip, "true");
  assert.equal(check({ labels: ["area: x", "status: ready"] }).skip, "true");
});

test("triages the marker from an author not on the list", () => {
  assert.deepEqual(check({ author: { id: 1, login: "stranger" } }), { skip: "false", reason: "untrusted-author" });
});

test("triages the marker from a listed bot that is not the lanes App", () => {
  assert.deepEqual(check({ author: LISTED_BOT }), { skip: "false", reason: "untrusted-author" });
});

test("triages a stranger who copies a listed human's login", () => {
  assert.equal(check({ author: { id: 2, login: "kyle-sexton" } }).reason, "untrusted-author");
});

test("does not trust the lanes App when its id is not configured", () => {
  for (const appId of ["", null, "abc", "0"]) {
    assert.equal(check({ author: LANES_APP }, LIST, appId).reason, "untrusted-author");
  }
});

test("triages a hand-opened issue with no marker", () => {
  assert.deepEqual(check({ body: "I found a bug" }), { skip: "false", reason: "no-marker" });
  assert.deepEqual(check({ body: null }), { skip: "false", reason: "no-marker" });
});

test("triages a marker that is not the body's last line", () => {
  assert.deepEqual(check({ body: `> quoted ${BORN_TRIAGED_MARKER}\n\nmore text` }), { skip: "false", reason: "no-marker" });
});

test("triages a marked trusted issue with no Issue Type", () => {
  assert.deepEqual(check({ type: null }), { skip: "false", reason: "no-type" });
});

test("triages a marked trusted issue with no status label", () => {
  assert.deepEqual(check({ labels: ["area: x", "priority: high"] }), { skip: "false", reason: "no-status" });
});

test("triages when the trusted-actor list is unreadable or the wrong version", () => {
  assert.equal(check({}, null).reason, "list-unreadable");
  assert.equal(check({}, { version: 2, actors: [HUMAN] }).reason, "list-unreadable");
  assert.equal(check({}, { version: 1 }).reason, "list-unreadable");
});

const noSleep = async () => {};

test("run re-reads the issue while only the type or status is still missing", async () => {
  const reads = [issue({ type: null }), issue({ labels: [] }), issue({})];
  let calls = 0;
  const result = await run({
    fetchIssue: async () => reads[calls++],
    list: LIST,
    lanesAppId: LANES_APP_ID,
    sleep: noSleep,
    attempts: 5,
  });
  assert.deepEqual(result, { skip: "true", reason: "born-triaged" });
  assert.equal(calls, 3);
});

test("run gives up after its attempts and triages", async () => {
  let calls = 0;
  const result = await run({
    fetchIssue: async () => {
      calls += 1;
      return issue({ type: null });
    },
    list: LIST,
    lanesAppId: LANES_APP_ID,
    sleep: noSleep,
    attempts: 3,
  });
  assert.deepEqual(result, { skip: "false", reason: "no-type" });
  assert.equal(calls, 3);
});

test("run reads once when the marker or the author already rules a skip out", async () => {
  for (const overrides of [{ body: "x" }, { author: { id: 1, login: "stranger" } }]) {
    let calls = 0;
    await run({
      fetchIssue: async () => {
        calls += 1;
        return issue({ ...overrides, type: null });
      },
      list: LIST,
      lanesAppId: LANES_APP_ID,
      sleep: noSleep,
      attempts: 5,
    });
    assert.equal(calls, 1);
  }
});

// The Work status field a trusted account set (read-status.mjs): with a status
// label on the issue it only adds a hold; with none it decides; unset, the labels decide.
const fieldRun = (labels, fields) =>
  run({
    fetchIssue: async () => issue({ labels }),
    list: LIST,
    lanesAppId: LANES_APP_ID,
    statusOf: statusReader({ github: withFields(async () => [], fields), repository: "o/r", config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, log: () => {} }),
    sleep: noSleep,
    attempts: 1,
  });

test("a field that mirrors the labels changes no answer", async () => {
  const sets = [["needs-human"], ["agent-ready"], ["status: ready"], ["needs-owner-decision"], [], ["needs-triage"], ["needs-spec"], ["admission-deferred"], ["priority: high"]];
  for (const labels of sets) {
    const byLabels = await run({ fetchIssue: async () => issue({ labels }), list: LIST, lanesAppId: LANES_APP_ID, sleep: noSleep, attempts: 1 });
    const mirrored = await run({ fetchIssue: async () => issue({ labels }), list: LIST, lanesAppId: LANES_APP_ID, statusOf: mirroredStatusOf, sleep: noSleep, attempts: 1 });
    assert.deepEqual(mirrored, byLabels, JSON.stringify(labels));
  }
});

test("the two hold labels count as a status under their new names", async () => {
  for (const labels of [["needs-owner-decision"], ["needs-reporter-info"]]) {
    assert.deepEqual(await run({ fetchIssue: async () => issue({ labels }), list: LIST, lanesAppId: LANES_APP_ID, sleep: noSleep, attempts: 1 }), { skip: "true", reason: "born-triaged" }, labels[0]);
  }
});

// A field-only agent-ready, with no label, is a status: the label is going away.
test("run lets the Work status field decide an issue's status, agent-ready included", async () => {
  assert.deepEqual(await fieldRun([], { 7: { state: "ready" } }), { skip: "true", reason: "born-triaged" });
  assert.deepEqual(await fieldRun(["needs-triage"], { 7: { state: "confirmed" } }), { skip: "true", reason: "born-triaged" });
  assert.deepEqual(await fieldRun(["status: ready"], { 7: { state: "needs-triage" } }), { skip: "false", reason: "no-status" });
  assert.deepEqual(await fieldRun([], { 7: { state: "agent-ready" } }), { skip: "true", reason: "born-triaged" });
});

test("every set Work status but needs-triage counts, with no status label", async () => {
  for (const state of ["needs-spec", "deferred", "needs-reporter-info", "needs-owner-decision", "needs-human", "agent-ready", "ready", "confirmed"]) {
    assert.deepEqual(await fieldRun([], { 7: { state } }), { skip: "true", reason: "born-triaged" }, state);
  }
  assert.deepEqual(await fieldRun([], { 7: { state: "needs-triage" } }), { skip: "false", reason: "no-status" });
});

test("a hold the Work status field adds still counts as the status", async () => {
  assert.deepEqual(await fieldRun(["status: ready"], { 7: { state: "needs-human" } }), { skip: "true", reason: "born-triaged" });
});

test("run judges by the labels when the Work status field is unset or set by another account", async () => {
  assert.deepEqual(await fieldRun(["needs-human"], {}), { skip: "true", reason: "born-triaged" });
  assert.deepEqual(await fieldRun([], { 7: { state: "agent-ready", setter: STRANGER_ID } }), { skip: "false", reason: "no-status" });
});

test("run reads the Work status field again on each attempt", async () => {
  const fields = { 7: { state: "needs-triage" } };
  let calls = 0;
  const github = withFields(async () => [], fields);
  const result = await run({
    fetchIssue: async () => {
      calls += 1;
      if (calls === 2) fields[7] = { state: "ready" };
      return issue({ labels: [] });
    },
    list: LIST,
    lanesAppId: LANES_APP_ID,
    statusOf: statusReader({ github, repository: "o/r", config: STATUS_CONFIG, trustedActors: TRUSTED_ACTORS, log: () => {} }),
    sleep: noSleep,
    attempts: 3,
  });
  assert.deepEqual(result, { skip: "true", reason: "born-triaged" });
  assert.equal(calls, 2);
});

test("run triages when the issue cannot be read", async () => {
  const result = await run({
    fetchIssue: async () => {
      throw new Error("HTTP 500");
    },
    list: LIST,
    lanesAppId: LANES_APP_ID,
    sleep: noSleep,
    attempts: 3,
  });
  assert.deepEqual(result, { skip: "false", reason: "issue-unreadable" });
});

const once = async (overrides, options = {}) => {
  let calls = 0;
  const result = await run({
    fetchIssue: async () => {
      calls += 1;
      return issue(overrides);
    },
    list: LIST,
    lanesAppId: LANES_APP_ID,
    sleep: noSleep,
    attempts: 5,
    ...options,
  });
  return { result, calls };
};

test("run skips a wayfind decision item on its routing label alone, in one read", async () => {
  const { result, calls } = await once({ body: "Which store?", type: null, labels: ["wayfind: interview", "needs-human"] });
  assert.deepEqual(result, { skip: "true", reason: "routing-label", label: "wayfind: interview" });
  assert.equal(calls, 1);
});

test("run skips a spec container on the default container label", async () => {
  const { result } = await once({ body: "## Destination", labels: ["spec-container"] });
  assert.deepEqual(result, { skip: "true", reason: "routing-label", label: "spec-container" });
});

test("run matches the wayfind prefix only at the start of a label", async () => {
  for (const labels of [["not-wayfind: x"], ["wayfinding"], ["spec-container-old"], ["work-map"]]) {
    assert.deepEqual((await once({ body: "x", labels })).result, { skip: "false", reason: "no-marker" }, labels[0]);
  }
});

test("run uses the binding's remapped routing labels instead of the defaults", async () => {
  const routing = { container: "decision-map", prefix: "route: " };
  assert.deepEqual((await once({ body: "x", labels: ["decision-map"] }, { routing })).result, { skip: "true", reason: "routing-label", label: "decision-map" });
  assert.deepEqual((await once({ body: "x", labels: ["route: design"] }, { routing })).result, { skip: "true", reason: "routing-label", label: "route: design" });
  for (const labels of [["spec-container"], ["wayfind: task"]]) {
    assert.deepEqual((await once({ body: "x", labels }, { routing })).result, { skip: "false", reason: "no-marker" }, labels[0]);
  }
});

test("run without the born-triaged rule skips only a routing label, in one read", async () => {
  const bornTriaged = await once({}, { bornTriaged: false });
  assert.deepEqual(bornTriaged.result, { skip: "false", reason: "born-triaged-off" });
  assert.equal(bornTriaged.calls, 1);
  const routed = await once({ labels: ["wayfind: design"] }, { bornTriaged: false });
  assert.deepEqual(routed.result, { skip: "true", reason: "routing-label", label: "wayfind: design" });
});

test("routingLabels reads the binding's keys and keeps each default when absent or empty", () => {
  assert.deepEqual(routingLabels(null), { container: "spec-container", prefix: "wayfind:" });
  assert.deepEqual(routingLabels({ config: { lease_ttl_hours: 24 } }), { container: "spec-container", prefix: "wayfind:" });
  assert.deepEqual(routingLabels({ config: { container_label: "", wayfind_label_prefix: "" } }), { container: "spec-container", prefix: "wayfind:" });
  assert.deepEqual(routingLabels({ config: { container_label: "epic", wayfind_label_prefix: "wf/" } }), { container: "epic", prefix: "wf/" });
  assert.throws(() => routingLabels({ config: { container_label: ["a"] } }), /container_label is not a string/);
  assert.throws(() => routingLabels({ config: { wayfind_label_prefix: 3 } }), /wayfind_label_prefix is not a string/);
});

test("checkBornTriaged does not match an author with no id against a list entry with no id", () => {
  const list = { version: 1, actors: [{ login: "x", kind: "human" }] };
  assert.equal(check({ author: { login: "x" } }, list).reason, "untrusted-author");
});

function runCli(env) {
  const dir = tempDir("born-triaged-");
  try {
    const outputPath = path.join(dir, "output");
    writeFileSync(outputPath, "");
    const result = spawnSync(process.execPath, [SCRIPT], {
      env: { PATH: process.env.PATH, GITHUB_OUTPUT: outputPath, ...env },
      encoding: "utf8",
    });
    const outputs = Object.fromEntries(
      [...readFileSync(outputPath, "utf8").matchAll(/^([\w-]+)<<(\S+)\n([^\n]*)\n\2$/gm)].map((m) => [m[1], m[3]]),
    );
    return { status: result.status, outputs };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("CLI triages a non-numeric issue number and exits 0", () => {
  const { status, outputs } = runCli({ ISSUE_NUMBER: "7; echo", TRUSTED_ACTORS_PATH: "/nonexistent" });
  assert.equal(status, 0);
  assert.deepEqual(outputs, { skip: "false", reason: "issue-unreadable", label: "", "human-ids": "", "rate-limited": "false" });
});

test("CLI triages an unreadable trusted-actor list and exits 0", () => {
  const { status, outputs } = runCli({
    ISSUE_NUMBER: "7",
    TRUSTED_ACTORS_PATH: "/nonexistent",
    GITHUB_API_URL: "http://127.0.0.1:9",
  });
  assert.equal(status, 0);
  assert.deepEqual(outputs, { skip: "false", reason: "list-unreadable", label: "", "human-ids": "", "rate-limited": "false" });
});

test("CLI emits the listed human ids even when the issue is unreadable", () => {
  const dir = tempDir("born-triaged-list-");
  try {
    const listPath = path.join(dir, "trusted-actors.json");
    writeFileSync(listPath, JSON.stringify(LIST));
    const { status, outputs } = runCli({
      ISSUE_NUMBER: "7",
      TRUSTED_ACTORS_PATH: listPath,
      GITHUB_API_URL: "http://127.0.0.1:9",
    });
    assert.equal(status, 0);
    assert.deepEqual(outputs, { skip: "false", reason: "issue-unreadable", label: "", "human-ids": "153232337", "rate-limited": "false" });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// A rate-guard stop the job already holds: no request, rate-limited=true for
// the callers to stop their API jobs on, and the step still exits 0.
test("CLI reports rate-limited=true and sends nothing while the job's rate guard holds a stop", () => {
  const dir = tempDir("born-triaged-stop-");
  try {
    const listPath = path.join(dir, "trusted-actors.json");
    writeFileSync(listPath, JSON.stringify(LIST));
    mkdirSync(path.join(dir, "api-budget"));
    writeFileSync(path.join(dir, "api-budget", "stop"), `core ${Math.floor(Date.now() / 1000) + 3600}\n`);
    const { status, outputs } = runCli({
      ISSUE_NUMBER: "7",
      TRUSTED_ACTORS_PATH: listPath,
      GITHUB_API_URL: "http://127.0.0.1:9",
      RUNNER_TEMP: dir,
    });
    assert.equal(status, 0);
    assert.deepEqual(outputs, { skip: "false", reason: "issue-unreadable", label: "", "human-ids": "153232337", "rate-limited": "true" });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// The CLI against a local API that serves `served` as the issue it reads,
// with the tracker binding at TRACKER_CONFIG written from `binding`.
async function runCliServed(served, binding, env = {}) {
  const dir = tempDir("born-triaged-served-");
  const server = createServer((request, response) => {
    response.setHeader("content-type", "application/json");
    response.end(JSON.stringify(request.url === "/repos/o/r/issues/7" ? served : {}));
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const listPath = path.join(dir, "trusted-actors.json");
    const outputPath = path.join(dir, "output");
    const bindingPath = path.join(dir, "work-items.yaml");
    writeFileSync(listPath, JSON.stringify(LIST));
    writeFileSync(outputPath, "");
    writeFileSync(bindingPath, binding);
    const child = spawn(process.execPath, [SCRIPT], {
      env: {
        PATH: process.env.PATH,
        GITHUB_OUTPUT: outputPath,
        RUNNER_TEMP: dir,
        GITHUB_API_URL: `http://127.0.0.1:${server.address().port}`,
        GITHUB_TOKEN: "t",
        REPOSITORY: "o/r",
        ISSUE_NUMBER: "7",
        TRUSTED_ACTORS_PATH: listPath,
        LANES_APP_ID: LANES_APP_ID,
        TRACKER_CONFIG: bindingPath,
        ...env,
      },
    });
    let stdout = "";
    child.stdout.on("data", (chunk) => (stdout += chunk));
    const status = await new Promise((resolve) => child.on("close", resolve));
    const outputs = Object.fromEntries(
      [...readFileSync(outputPath, "utf8").matchAll(/^([\w-]+)<<(\S+)\n([^\n]*)\n\2$/gm)].map((m) => [m[1], m[3]]),
    );
    return { status, outputs, stdout };
  } finally {
    server.close();
    rmSync(dir, { recursive: true, force: true });
  }
}

test("CLI skips an issue on the binding's container label and names the label in a notice", async () => {
  const { status, outputs, stdout } = await runCliServed(issue({ body: "## Destination", labels: ["decision-map"] }), "tracker:\n  config:\n    container_label: decision-map\n");
  assert.equal(status, 0);
  assert.deepEqual(outputs, { skip: "true", reason: "routing-label", label: "decision-map", "human-ids": "153232337", "rate-limited": "false" });
  assert.match(stdout, /^::notice::intake skips #7: it carries 'decision-map'/m);
});

test("CLI warns and keeps the default labels when the binding's value is malformed", async () => {
  const { outputs, stdout } = await runCliServed(issue({ body: "x", labels: ["wayfind: task"] }), "tracker:\n  config:\n    container_label: [a, b]\n");
  assert.equal(outputs.label, "wayfind: task");
  assert.match(stdout, /^::warning::check-born-triaged: cannot read the routing labels from .*container_label is not a string/m);
});

test("CLI with BORN_TRIAGED=false triages a born-triaged issue and prints no notice", async () => {
  const { outputs, stdout } = await runCliServed(issue({}), "tracker:\n  provider: github\n", { BORN_TRIAGED: "false" });
  assert.deepEqual(outputs, { skip: "false", reason: "born-triaged-off", label: "", "human-ids": "153232337", "rate-limited": "false" });
  assert.doesNotMatch(stdout, /::notice::/);
});

// The agent-ready label starts no lane run and admission writes the Work
// status, so a born-triaged issue whose only status is that label, with the
// field configured and unset, has no status: intake triages it, in one read.
const labelOnlyRun = (labels, fields, { author, config = STATUS_CONFIG, attempts = 3 } = {}) => {
  let reads = 0;
  const result = run({
    fetchIssue: async () => {
      reads += 1;
      return issue({ labels, ...(author && { author }) });
    },
    list: LIST,
    lanesAppId: LANES_APP_ID,
    statusOf: statusReader({ github: withFields(async () => [], fields), repository: "o/r", config, trustedActors: TRUSTED_ACTORS, log: () => {} }),
    sleep: noSleep,
    attempts,
  });
  return result.then((answer) => ({ ...answer, reads }));
};

test("run triages a born-triaged issue whose only status is the agent-ready label while its Work status is unset", async () => {
  assert.deepEqual(await labelOnlyRun(["agent-ready"], {}), { skip: "false", reason: "label-only", reads: 1 });
  assert.deepEqual(await labelOnlyRun(["agent-ready", "area: x"], { 7: { state: "agent-ready", setter: STRANGER_ID } }), { skip: "false", reason: "label-only", reads: 1 });
});

test("run still skips an agent-ready label beside a set Work status or another status label", async () => {
  assert.deepEqual(await labelOnlyRun(["agent-ready"], { 7: { state: "agent-ready" } }), { skip: "true", reason: "born-triaged", reads: 1 });
  assert.deepEqual(await labelOnlyRun(["agent-ready"], { 7: { state: "ready" } }), { skip: "true", reason: "born-triaged", reads: 1 });
  assert.deepEqual(await labelOnlyRun(["agent-ready", "status: ready"], {}), { skip: "true", reason: "born-triaged", reads: 1 });
  assert.deepEqual(await labelOnlyRun(["agent-ready", "needs-human"], {}), { skip: "true", reason: "born-triaged", reads: 1 });
});

test("with no Work status configured the agent-ready label is still the status", async () => {
  assert.deepEqual(await labelOnlyRun(["agent-ready"], {}, { config: null }), { skip: "true", reason: "born-triaged", reads: 1 });
});

test("a label-only issue keeps the author check: a stranger's is untrusted-author, not label-only", async () => {
  assert.deepEqual(await labelOnlyRun(["agent-ready"], {}, { author: { id: 1, login: "stranger" } }), { skip: "false", reason: "untrusted-author", reads: 1 });
  assert.deepEqual(await labelOnlyRun(["agent-ready"], {}, { author: LISTED_BOT }), { skip: "false", reason: "untrusted-author", reads: 1 });
});

test("humanIds lists only the human actors' ids", () => {
  const second = { id: 42, login: "other", kind: "human" };
  assert.equal(humanIds({ version: 1, actors: [HUMAN, LISTED_BOT, LANES_APP, second] }), "153232337,42");
  assert.equal(humanIds({ version: 1, actors: [LISTED_BOT] }), "");
  assert.equal(humanIds({ version: 1, actors: [{ id: "153232337", login: "x", kind: "human" }, { id: 0, login: "y", kind: "human" }] }), "");
  assert.equal(humanIds(null), "");
  assert.equal(humanIds({ version: 2, actors: [HUMAN] }), "", "a wrong-version list yields no ids");
});
