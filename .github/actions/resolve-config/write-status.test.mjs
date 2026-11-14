// The Work status writer over the live models.issue-status: one POST of the
// state's option name, checked against the mapped option id; a write that
// does not land throws, so the caller's run fails rather than leave the field
// wrong. Option ids are written by hand from the org field.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse } from "yaml";

import { postOptionNames, RESTART_GAP_MS, StatusWriteError, statusWriter, writeState } from "./write-status.mjs";

const CONFIG = parse(readFileSync(new URL("../../../docs/conventions/pr-pipeline.yaml", import.meta.url), "utf8")).models[
  "issue-status"
];
const FIELD = 48484079;

// A fake client recording calls, answering a POST with `option` held.
function fake(answer = (body) => [{ issue_field_id: FIELD, single_select_option: { id: 84879220, name: body.issue_field_values[0].value } }]) {
  const calls = [];
  const github = async (method, path, body, headers, options) => {
    calls.push({ method, path, body, headers, options });
    if (answer instanceof Error) {
      throw answer;
    }
    return answer(body);
  };
  return { calls, github };
}

const ROOT = new URL("../../..", import.meta.url).pathname;
const held = (option) => (body) => [{ issue_field_id: FIELD, single_select_option: { id: option, name: body.issue_field_values[0].value } }];

test("writeState POSTs the state's option name once and checks the option GitHub kept", async () => {
  const { calls, github } = fake(held(84879216));
  assert.deepEqual(await writeState({ github, repository: "o/r", number: 7, state: "needs-triage", config: CONFIG }), {
    outcome: "written",
    state: "needs-triage",
    option: 84879216,
  });
  assert.deepEqual(calls.map(({ method, path, body }) => [method, path, body]), [
    ["POST", "/repos/o/r/issues/7/issue-field-values", { issue_field_values: [{ field_id: FIELD, value: "needs-triage" }] }],
  ]);
  assert.equal(calls[0].headers["X-GitHub-Api-Version"], "2026-03-10");
  assert.deepEqual(calls[0].options, { resendOnce: true }, "setting one option is safe to send twice, so a 5xx is resent once");
});

test("writeState skips the write when the field already holds the option", async () => {
  const { calls, github } = fake();
  assert.equal((await writeState({ github, repository: "o/r", number: 7, state: "needs-human", config: CONFIG, current: 86380005 })).outcome, "unchanged");
  assert.equal(calls.length, 0);
});

for (const [why, answer, state, config, text] of [
  ["a failed POST", new Error("HTTP 500"), "needs-triage", CONFIG, "HTTP 500"],
  ["GitHub keeping another option", held(84879220), "needs-triage", CONFIG, "kept option 84879220, not 84879216"],
  ["a state no option maps", held(84879216), "blocked", CONFIG, "maps no option to `blocked`"],
  ["no models.issue-status", held(84879216), "needs-triage", null, "is not set"],
]) {
  test(`writeState throws StatusWriteError on ${why}`, async () => {
    const { github } = fake(answer);
    await assert.rejects(
      () => writeState({ github, repository: "o/r", number: 7, state, config }),
      (error) => error instanceof StatusWriteError && error.message.startsWith("#7's Work status field was not set") && error.message.includes(text),
    );
  });
}

// A fake whose field reads `option`, last set by `setter`, and whose POSTs
// answer with the posted state's option and set the field to it, by the lanes
// App. The issue carries `labels`, which a label DELETE removes.
// `put(option, setter)` sets the field as a person would between writes.
function fieldWorld(option, setter, labels = []) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push([method, path, body]);
    if (method === "GET" && path.endsWith("/issue-field-values")) return option === null ? [] : [{ issue_field_id: FIELD, single_select_option: { id: option } }];
    const labelPath = path.match(/^\/repos\/o\/r\/issues\/\d+\/labels(?:\?per_page=100&page=(\d+)|\/(.+))$/);
    if (method === "GET" && labelPath?.[1]) return labelPath[1] === "1" ? labels.map((name) => ({ name })) : [];
    if (method === "DELETE" && labelPath?.[2]) {
      labels = labels.filter((name) => name !== decodeURIComponent(labelPath[2]));
      return labels.map((name) => ({ name }));
    }
    if (method === "POST" && path === "/repos/o/r/issues/7/labels") {
      labels = [...labels, ...body.labels];
      return labels.map((name) => ({ name }));
    }
    if (method === "DELETE" && path === `/repos/o/r/issues/7/issue-field-values/${FIELD}`) {
      option = null;
      return null;
    }
    if (method === "POST" && path === "/graphql") {
      const nodes = option === null ? [] : [{ __typename: "IssueFieldAddedEvent", value: CONFIG.options[String(option)], actor: { databaseId: setter }, issueField: { fullDatabaseId: String(FIELD) } }];
      return { data: { repository: { issue: { timelineItems: { nodes } } } } };
    }
    if (method === "POST" && path.endsWith("/issue-field-values")) {
      const state = body.issue_field_values[0].value;
      option = Number(Object.keys(CONFIG.options).find((id) => CONFIG.options[id] === state));
      setter = 337595936;
      return [{ issue_field_id: FIELD, single_select_option: { id: option } }];
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  const posts = () => calls.filter(([method, path]) => method === "POST" && path.endsWith("/issue-field-values"));
  // Each label read, label removal and field write, in order.
  const steps = () =>
    calls
      .filter(([method, path]) => path.includes("/labels") || (method !== "GET" && path.includes("/issue-field-values")))
      .map(([method, path, body]) => (body?.issue_field_values ? `${method} ${body.issue_field_values[0].value}` : `${method} ${path.replace(/^\/repos\/o\/r\/issues\/\d+/, "")}`));
  const put = (next, by) => {
    option = next;
    setter = by;
  };
  return { github, posts, put, steps, labels: () => labels };
}
const writerOver = (github, env = { BASE_PATH: ROOT }, sleep = async () => {}) => statusWriter({ env, github, repository: "o/r", sleep });

test("statusWriter set writes a state once per issue in a process, and skips one `fields` shows", async () => {
  const w = fieldWorld(null);
  const { set } = await writerOver(w.github);
  assert.equal((await set(7, "needs-triage")).outcome, "written");
  assert.equal((await set(7, "needs-triage")).outcome, "unchanged");
  assert.equal((await set(8, "needs-triage", { fields: { [FIELD]: { option: 84879216 } } })).outcome, "unchanged");
  assert.equal((await set(7, "confirmed")).outcome, "written");
  assert.deepEqual(w.posts().map(([, , body]) => body.issue_field_values[0].value), ["needs-triage", "confirmed"]);
});

test("statusWriter restart clears the field and sets agent-ready even after this process wrote it", async () => {
  const w = fieldWorld(null);
  const deletes = [];
  const github = async (method, path, body, headers) => {
    if (method === "DELETE") {
      deletes.push([path, headers?.["X-GitHub-Api-Version"]]);
      w.put(null, 337595936);
      return null;
    }
    return w.github(method, path, body);
  };
  const { set, restart } = await writerOver(github);
  assert.equal((await set(7, "agent-ready")).outcome, "written");
  assert.equal((await restart(7)).outcome, "written");
  assert.deepEqual(deletes, [["/repos/o/r/issues/7/issue-field-values/48484079", "2026-03-10"]]);
  assert.deepEqual(w.posts().map(([, , body]) => body.issue_field_values[0].value), ["agent-ready", "agent-ready"]);
});

test("statusWriter restart waits between the clear and the set, and not after a 404 clear", async () => {
  const run = async (clear) => {
    const w = fieldWorld(null);
    const order = [];
    const github = async (method, path, body) => {
      if (method === "DELETE") {
        order.push("clear");
        return clear();
      }
      if (method === "POST" && path.endsWith("/issue-field-values")) order.push("set");
      return w.github(method, path, body);
    };
    await (await writerOver(github, undefined, async (ms) => order.push(ms))).restart(7);
    return order;
  };
  assert.deepEqual(await run(() => null), ["clear", RESTART_GAP_MS, "set"]);
  assert.deepEqual(
    await run(() => {
      throw new Error("GitHub answered status 404");
    }),
    ["clear", "set"],
  );
});

test("statusWriter restart treats a 404 clear as nothing set, and stops on a person's hold", async () => {
  const w = fieldWorld(null);
  const github = async (method, path, body) => {
    if (method === "DELETE") {
      throw new Error("GitHub answered status 404");
    }
    return w.github(method, path, body);
  };
  assert.equal((await (await writerOver(github)).restart(7)).outcome, "written");
  const hold = fieldWorld(86380005, 153232337);
  assert.deepEqual(await (await writerOver(hold.github)).restart(7), { outcome: "held", state: "needs-human" });
  assert.equal(hold.posts().length, 0);
});

test("statusWriter restart from agent-ready leaves a field a person moved elsewhere", async () => {
  // A listed human moved the issue to confirmed after the caller's listing.
  const moved = fieldWorld(Number(Object.keys(CONFIG.options).find((id) => CONFIG.options[id] === "confirmed")), 153232337);
  const calls = [];
  const github = async (method, path, body) => {
    calls.push(method);
    return moved.github(method, path, body);
  };
  assert.deepEqual(await (await writerOver(github)).restart(7, { from: ["agent-ready"] }), { outcome: "moved", state: "confirmed" });
  assert.ok(!calls.includes("DELETE"));
  assert.equal(moved.posts().length, 0);
});

// The lanes token broker refuses the issue lane's token while the issue
// carries a status label other than agent-ready (#16149): an issue form's
// needs-triage stayed on #16000 and #16001 after admission set the field.
test("statusWriter set to agent-ready removes the issue's other status labels before the write, and keeps every other label", async () => {
  const app = 337595936;
  const formLeftover = fieldWorld(86380003, app, ["needs-triage", "area: security"]);
  assert.equal((await (await writerOver(formLeftover.github)).set(7, "agent-ready", { keepHold: true })).outcome, "written");
  assert.deepEqual(formLeftover.steps(), ["GET /labels?per_page=100&page=1", "DELETE /labels/needs-triage", "POST agent-ready"]);
  assert.deepEqual(formLeftover.labels(), ["area: security"]);
  const legacy = fieldWorld(86380004, app, ["status: ready", "Needs-Triage", "admission-deferred", "agent-ready", "area: security"]);
  assert.equal((await (await writerOver(legacy.github)).set(7, "agent-ready", { keepHold: true })).outcome, "written");
  assert.deepEqual(legacy.labels(), ["agent-ready", "area: security"], "every queue-state label but agent-ready comes off, in any case");
  assert.ok(legacy.steps().includes("DELETE /labels/status%3A%20ready"), legacy.steps().join("\n"));
  assert.equal(legacy.steps().at(-1), "POST agent-ready", "the field is written last");
});

test("statusWriter set to agent-ready over a hold label writes nothing and answers held", async () => {
  for (const [hold, state] of [
    ["needs-human", "needs-human"],
    ["needs-owner-decision", "needs-owner-decision"],
    ["needs-reporter-info", "needs-reporter-info"],
    ["needs-spec", "needs-spec"],
  ]) {
    const w = fieldWorld(86380003, 337595936, ["needs-triage", hold]);
    assert.deepEqual(await (await writerOver(w.github)).set(7, "agent-ready", { keepHold: true }), { outcome: "held", state }, hold);
    assert.deepEqual(w.steps(), ["GET /labels?per_page=100&page=1"], `${hold}: no label removed and no field write`);
    assert.deepEqual(w.labels(), ["needs-triage", hold], hold);
  }
});

test("statusWriter set to agent-ready throws and writes nothing when a status label cannot be read or removed; a 404 removal counts as removed", async () => {
  const over = (fail) => {
    const w = fieldWorld(86380003, 337595936, ["needs-triage"]);
    const github = async (method, path, body) => {
      if (fail(method, path)) {
        throw Object.assign(new Error(`${method} ${path} failed with status ${fail(method, path)}`), { status: fail(method, path) });
      }
      return w.github(method, path, body);
    };
    return { w, github };
  };
  for (const [why, fail, text] of [
    ["a failed removal", (method, path) => method === "DELETE" && path.includes("/labels/") && 500, "status label `needs-triage` was not removed"],
    ["a failed label read", (method, path) => method === "GET" && path.includes("/labels") && 502, "labels could not be read"],
  ]) {
    const { w, github } = over(fail);
    await assert.rejects(
      () => writerOver(github).then(({ set }) => set(7, "agent-ready", { keepHold: true })),
      (error) => error instanceof StatusWriteError && error.message.includes(text),
      why,
    );
    assert.equal(w.posts().length, 0, `${why}: agent-ready is not set over the label`);
  }
  const { w, github } = over((method, path) => method === "DELETE" && path.includes("/labels/") && 404);
  assert.equal((await (await writerOver(github)).set(7, "agent-ready", { keepHold: true })).outcome, "written", "a label already gone");
  assert.equal(w.posts().length, 1);
});

// With no trusted field state the labels alone carry the issue's state, so a
// failed agent-ready write must not leave the issue with neither.
test("statusWriter set to agent-ready puts the removed labels back when the field write fails", async () => {
  const failing = (w, failPutBack = false) => async (method, path, body) => {
    if (method === "POST" && path.endsWith("/issue-field-values")) throw new Error("HTTP 500");
    if (failPutBack && method === "POST" && path.endsWith("/labels")) throw new Error("HTTP 502");
    return w.github(method, path, body);
  };
  const w = fieldWorld(null, undefined, ["status: ready", "area: security"]);
  await assert.rejects(
    () => writerOver(failing(w)).then(({ set }) => set(7, "agent-ready", { keepHold: true })),
    (error) => error instanceof StatusWriteError && error.message === "#7's Work status field was not set to `agent-ready`: HTTP 500",
  );
  assert.deepEqual(w.labels(), ["area: security", "status: ready"], "status: ready is back on");
  assert.deepEqual(w.steps().slice(-1), ["POST /labels"]);
  const lost = fieldWorld(null, undefined, ["status: ready"]);
  await assert.rejects(
    () => writerOver(failing(lost, true)).then(({ set }) => set(7, "agent-ready", { keepHold: true })),
    (error) => error instanceof StatusWriteError && error.message.includes("HTTP 500") && error.message.includes("(status: ready) were not put back: HTTP 502"),
  );
});

test("statusWriter restart removes the other status labels before it clears the field, and stops on a hold label", async () => {
  const app = 337595936;
  const w = fieldWorld(84879220, app, ["needs-triage", "area: security"]);
  assert.equal((await (await writerOver(w.github)).restart(7, { from: ["agent-ready"] })).outcome, "written");
  assert.deepEqual(w.steps(), ["GET /labels?per_page=100&page=1", "DELETE /labels/needs-triage", `DELETE /issue-field-values/${FIELD}`, "POST agent-ready"]);
  const hold = fieldWorld(84879220, app, ["needs-owner-decision"]);
  assert.deepEqual(await (await writerOver(hold.github)).restart(7, { from: ["agent-ready"] }), { outcome: "held", state: "needs-owner-decision" });
  assert.deepEqual(hold.steps(), ["GET /labels?per_page=100&page=1"], "the field is not cleared");
});

test("statusWriter writes of any other state read and remove no label", async () => {
  const w = fieldWorld(null, undefined, ["needs-triage"]);
  const { set } = await writerOver(w.github);
  assert.equal((await set(7, "ready", { keepHold: true })).outcome, "written");
  assert.equal((await set(7, "confirmed")).outcome, "written");
  assert.deepEqual(w.steps(), ["POST ready", "POST confirmed"]);
});

test("statusWriter leaveAgentReady writes only while the trusted field reads agent-ready", async () => {
  const human = 153232337;
  const ready = fieldWorld(84879220, human);
  assert.equal((await (await writerOver(ready.github)).leaveAgentReady(7, "needs-triage")).outcome, "written");
  assert.equal(ready.posts().length, 1);
  // The field holds a person's hold: taking agent-ready off writes nothing.
  for (const [why, w] of [
    ["needs-human", fieldWorld(86380005, human)],
    ["unset", fieldWorld(null)],
    ["agent-ready from an untrusted bot", fieldWorld(84879220, 209825114)],
    ["agent-ready from github-actions[bot]", fieldWorld(84879220, 41898282)],
  ]) {
    assert.equal((await (await writerOver(w.github)).leaveAgentReady(7, "needs-triage")).outcome, "unchanged", why);
    assert.equal(w.posts().length, 0, why);
  }
});

test("statusWriter leaveAgentReady with orUnset also writes while no trusted state is set, and leaves any other state", async () => {
  const human = 153232337;
  for (const [why, w] of [
    ["agent-ready", fieldWorld(84879220, human)],
    ["unset", fieldWorld(null)],
    ["agent-ready from an untrusted bot", fieldWorld(84879220, 209825114)],
  ]) {
    assert.equal((await (await writerOver(w.github)).leaveAgentReady(7, "needs-triage", { orUnset: true })).outcome, "written", why);
    assert.deepEqual(w.posts().map(([, , body]) => body.issue_field_values[0].value), ["needs-triage"], why);
  }
  for (const [why, w, state] of [
    ["a person's needs-owner-decision", fieldWorld(84879218, human), "needs-owner-decision"],
    ["a person's confirmed", fieldWorld(86380002, human), "confirmed"],
  ]) {
    assert.deepEqual(await (await writerOver(w.github)).leaveAgentReady(7, "needs-triage", { orUnset: true }), { outcome: "unchanged", state }, why);
    assert.equal(w.posts().length, 0, why);
  }
});

test("statusWriter leaveAgentReady with orUnset throws when the write does not land", async () => {
  const w = fieldWorld(null);
  const github = async (method, path, body) => {
    if (method === "POST" && path.endsWith("/issue-field-values")) throw new Error("HTTP 500");
    return w.github(method, path, body);
  };
  await assert.rejects(
    () => writerOver(github).then(({ leaveAgentReady }) => leaveAgentReady(7, "needs-triage", { orUnset: true })),
    (error) => error instanceof StatusWriteError && error.message === "#7's Work status field was not set to `needs-triage`: HTTP 500",
  );
});

test("statusWriter set with keepHold leaves a listed human's hold and replaces any other state", async () => {
  const human = 153232337;
  const app = 337595936;
  const actionsBot = 41898282;
  const person = fieldWorld(86380005, human);
  assert.deepEqual(await (await writerOver(person.github)).set(7, "needs-triage", { keepHold: true }), { outcome: "held", state: "needs-human" });
  assert.equal(person.posts().length, 0, "a person's needs-human is never replaced");
  for (const [why, w] of [
    ["needs-owner-decision the lanes App set", fieldWorld(84879218, app)],
    ["needs-human a bot-setter set", fieldWorld(86380005, actionsBot)],
    ["a person's confirmed, no hold", fieldWorld(86380002, human)],
    ["unset", fieldWorld(null)],
  ]) {
    assert.equal((await (await writerOver(w.github)).set(7, "needs-triage", { keepHold: true })).outcome, "written", why);
    assert.equal(w.posts().length, 1, why);
  }
  const written = fieldWorld(86380005, human);
  const { set } = await writerOver(written.github);
  assert.equal((await set(8, "ready")).outcome, "written", "without keepHold the field is not read");
  written.put(86380005, human);
  assert.deepEqual(await set(8, "deferred", { keepHold: true }), { outcome: "held", state: "needs-human" }, "an issue this process wrote is read again");
  assert.deepEqual(written.posts().map(([, path]) => path), ["/repos/o/r/issues/8/issue-field-values"]);
});

test("statusWriter set with keepHold sees a person's hold set after this process's own keepHold write", async () => {
  const w = fieldWorld(null);
  const { set } = await writerOver(w.github);
  assert.equal((await set(7, "ready", { keepHold: true })).outcome, "written");
  w.put(86380005, 153232337);
  assert.deepEqual(await set(7, "agent-ready", { keepHold: true }), { outcome: "held", state: "needs-human" });
  assert.deepEqual(w.posts().map(([, , body]) => body.issue_field_values[0].value), ["ready"]);
});

test("statusWriter set with keepHold writes a state again after another account changed the field", async () => {
  const w = fieldWorld(null);
  const { set } = await writerOver(w.github);
  await set(7, "ready", { keepHold: true });
  w.put(86380002, 153232337);
  assert.equal((await set(7, "ready", { keepHold: true })).outcome, "written", "the field no longer reads ready");
  assert.equal((await set(7, "ready", { keepHold: true })).outcome, "unchanged", "the field reads ready");
  assert.deepEqual(w.posts().map(([, , body]) => body.issue_field_values[0].value), ["ready", "ready"]);
});

test("statusWriter set with keepHold and releases replaces only the person's hold it releases", async () => {
  const human = 153232337;
  const answered = fieldWorld(84879218, human);
  assert.equal((await (await writerOver(answered.github)).set(7, "needs-triage", { keepHold: true, releases: "needs-owner-decision" })).outcome, "written", "the answered needs-owner-decision is released");
  assert.equal(answered.posts().length, 1);
  const other = fieldWorld(86380005, human);
  assert.deepEqual(await (await writerOver(other.github)).set(7, "needs-triage", { keepHold: true, releases: "needs-owner-decision" }), { outcome: "held", state: "needs-human" });
  assert.equal(other.posts().length, 0, "a different person's hold set meanwhile stands");
});

test("statusWriter set with from reads the field fresh and leaves a state outside from, even when this process wrote the issue", async () => {
  const app = 337595936;
  const from = [null, "needs-triage", "ready"];
  for (const [why, option, outcome] of [
    ["the lanes App's agent-ready", 84879220, { outcome: "moved", state: "agent-ready" }],
    ["the lanes App's deferred", 86380004, { outcome: "moved", state: "deferred" }],
    ["the lanes App's confirmed", 86380002, { outcome: "moved", state: "confirmed" }],
  ]) {
    const w = fieldWorld(option, app);
    assert.deepEqual(await (await writerOver(w.github)).set(7, "needs-triage", { keepHold: true, from }), outcome, why);
    assert.equal(w.posts().length, 0, `${why} is never replaced`);
  }
  for (const [why, option, outcome] of [
    ["unset", null, "written"],
    ["the lanes App's ready", 86380003, "written"],
    ["the lanes App's needs-triage", 84879216, "unchanged"],
  ]) {
    const w = fieldWorld(option, app);
    assert.equal((await (await writerOver(w.github)).set(7, "needs-triage", { keepHold: true, from })).outcome, outcome, why);
    assert.equal(w.posts().length, outcome === "written" ? 1 : 0, why);
  }
  const later = fieldWorld(null);
  const { set } = await writerOver(later.github);
  assert.equal((await set(8, "ready")).outcome, "written");
  later.put(84879220, app);
  assert.deepEqual(await set(8, "needs-triage", { from }), { outcome: "moved", state: "agent-ready" }, "from alone reads the field again");
  assert.deepEqual(later.posts().map(([, , body]) => body.issue_field_values[0].value), ["ready"]);
});

test("statusWriter set with keepHold throws and writes nothing when the field cannot be read", async () => {
  const calls = [];
  const github = async (method, path) => {
    calls.push([method, path]);
    return { message: "Not Found" };
  };
  const { set } = await writerOver(github);
  await assert.rejects(() => set(7, "needs-triage", { keepHold: true }), (error) => error instanceof StatusWriteError && /could not be read/.test(error.message));
  assert.ok(!calls.some(([method, path]) => method === "POST" && path.endsWith("/issue-field-values")));
});

test("statusWriter with an unreadable trusted-actor list still writes a plain set, and throws on every field read", async () => {
  const w = fieldWorld(null);
  const { set, leaveAgentReady } = await writerOver(w.github, { BASE_PATH: ROOT, TRUSTED_ACTORS_PATH: "/nonexistent-trusted-actors.json" });
  assert.equal((await set(7, "needs-human")).outcome, "written", "a plain set needs only the config");
  await assert.rejects(() => set(8, "needs-triage", { keepHold: true }), (error) => error instanceof StatusWriteError && /could not be read/.test(error.message));
  await assert.rejects(() => leaveAgentReady(9, "needs-triage"), StatusWriteError);
  assert.deepEqual(w.posts().map(([, path]) => path), ["/repos/o/r/issues/7/issue-field-values"]);
});

test("statusWriter with no readable config throws on every call and writes nothing", async () => {
  const w = fieldWorld(null);
  const { set, leaveAgentReady } = await writerOver(w.github, { BASE_PATH: "/nonexistent-base" });
  await assert.rejects(() => set(7, "needs-triage"), (error) => error instanceof StatusWriteError && /could not be read/.test(error.message));
  await assert.rejects(() => leaveAgentReady(7, "needs-triage"), StatusWriteError);
  assert.equal(w.posts().length, 0);
});

test("statusWriter leaveAgentReady throws when the field cannot be read", async () => {
  const github = async () => ({ message: "Not Found" });
  const { leaveAgentReady } = await writerOver(github);
  await assert.rejects(() => leaveAgentReady(7, "needs-triage"), (error) => error instanceof StatusWriteError && /could not be read/.test(error.message));
});

// A POST that takes a batch only when GitHub's options, in `spelled`, hold every name.
function optionPoster(spelled) {
  const posts = [];
  const post = async (batch) => {
    posts.push(batch.map(({ value }) => value));
    if (!batch.every(({ value }) => spelled.has(value))) {
      throw Object.assign(new Error("refused"), { status: 422, detail: "no such option" });
    }
    return batch.map(({ field_id }) => ({ issue_field_id: field_id }));
  };
  return { post, posts };
}
const OPTION_VALUES = [
  { field_id: 1, value: "needs-triage" },
  { field_id: 2, value: "small" },
  { field_id: 3, value: "low" },
];
const TITLED = new Set([2, 3]);
const quietly = () => {};

test("postOptionNames sends the lowercase names once when GitHub takes them", async () => {
  const { post, posts } = optionPoster(new Set(["needs-triage", "small", "low"]));
  assert.deepEqual(await postOptionNames(post, OPTION_VALUES, TITLED, quietly), [{ issue_field_id: 1 }, { issue_field_id: 2 }, { issue_field_id: 3 }]);
  assert.deepEqual(posts, [["needs-triage", "small", "low"]]);
});

test("postOptionNames Title-cases only the titled fields when GitHub refuses the lowercase names", async () => {
  const { post, posts } = optionPoster(new Set(["needs-triage", "Small", "Low"]));
  await postOptionNames(post, OPTION_VALUES, TITLED, quietly);
  assert.deepEqual(posts, [
    ["needs-triage", "small", "low"],
    ["needs-triage", "Small", "Low"],
  ]);
});

test("postOptionNames sends each field on its own, in either casing, while part of a rename has landed", async () => {
  const { post, posts } = optionPoster(new Set(["needs-triage", "small", "Low"]));
  const rows = await postOptionNames(post, OPTION_VALUES, TITLED, quietly);
  assert.deepEqual(rows, [{ issue_field_id: 1 }, { issue_field_id: 2 }, { issue_field_id: 3 }]);
  assert.deepEqual(posts.slice(2), [["needs-triage"], ["small"], ["low"], ["Low"]]);
});

test("postOptionNames throws when a field takes neither casing", async () => {
  const { post } = optionPoster(new Set(["needs-triage", "small"]));
  await assert.rejects(() => postOptionNames(post, OPTION_VALUES, TITLED, quietly), { status: 422 });
});

test("postOptionNames throws any other refusal without another write", async () => {
  const posts = [];
  const post = async (batch) => {
    posts.push(batch);
    throw Object.assign(new Error("forbidden"), { status: 403 });
  };
  await assert.rejects(() => postOptionNames(post, OPTION_VALUES, TITLED, quietly), { status: 403 });
  assert.equal(posts.length, 1);
});
