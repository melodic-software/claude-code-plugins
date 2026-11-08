// The lanes App filing step: one issue per planned incident, type and fields
// set, a re-run files nothing a marker shows already open, and a bad plan
// files nothing.
import assert from "node:assert/strict";
import { test } from "node:test";

import { fileIncidents, planProblem } from "./file-incidents.mjs";
import { renderBody } from "./issues.mjs";

const incident = (signal, title) => ({
  signal,
  title,
  body: renderBody({ signal, findings: [{ key: "k", area: "a", summary: "s", facts: [] }] }, "https://example.test/run/1"),
  type: "Bug",
  labels: ["source: factory-monitor"],
  fields: [{ field_id: 48484079, value: "needs-triage" }, { field_id: 49622037, value: "critical" }],
});
const plan = { version: 1, repository: "o/r", incidents: [incident("1 main red", "Restore main"), incident("2 ceiling", "Fix ceiling")] };

function github(openIssues = []) {
  const calls = [];
  const fields = [];
  let next = 200;
  const call = async (method, path, body) => {
    calls.push([method, path, body]);
    if (method === "GET") return openIssues;
    return { number: next++, type: { name: body.type } };
  };
  const setFields = async (number, values) => fields.push([number, values]);
  return { call, setFields, calls, fields };
}
const run = (gh, over = {}) => fileIncidents({ plan, call: gh.call, setFields: gh.setFields, repo: "o/r", agentIdentity: "bot[bot]", log: () => {}, wait: async () => {}, ...over });

test("each planned incident is filed with its type and fields, by POST, as the lanes App's call", async () => {
  const gh = github();
  const done = await run(gh);
  assert.deepEqual(done, { filed: [200, 201], skipped: [], failed: [] });
  const posts = gh.calls.filter(([m]) => m === "POST");
  assert.deepEqual(posts[0].slice(0, 2), ["POST", "/repos/o/r/issues"]);
  assert.equal(posts[0][2].title, "Restore main");
  assert.equal(posts[0][2].type, "Bug");
  assert.deepEqual(posts[0][2].labels, ["source: factory-monitor"]);
  assert.deepEqual(gh.fields[0], [200, plan.incidents[0].fields]);
});

test("a re-run files nothing whose marker is already open", async () => {
  const gh = github([{ number: 150, body: plan.incidents[0].body }]);
  const done = await run(gh);
  assert.deepEqual(done.filed, [200]);
  assert.deepEqual(done.skipped, ["incident:main-red"]);
  assert.equal(gh.calls.filter(([m, , b]) => m === "POST" && b?.title).length, 1);
});

test("a failed POST is reported and the next incident still files; a failed field write only warns", async () => {
  const gh = github();
  const failing = async (method, path, body) => {
    if (body?.title === "Restore main") throw new Error("HTTP 422");
    return gh.call(method, path, body);
  };
  const logged = [];
  const fieldFail = async () => {
    throw new Error("HTTP 500");
  };
  const done = await run({ ...gh, call: failing, setFields: fieldFail }, { log: (l) => logged.push(l) });
  assert.deepEqual(done.filed, [200]);
  assert.deepEqual(done.failed, [{ target: "incident:main-red", error: "HTTP 422" }]);
  assert.match(logged[0], /#200's field values were not set: HTTP 500/);
});

test("a type GitHub dropped is warned about", async () => {
  const logged = [];
  const gh = github();
  const call = async (method, path, body) => (method === "GET" ? [] : { number: 300 });
  await run({ ...gh, call }, { log: (l) => logged.push(l) });
  assert.match(logged[0], /came back without Issue Type Bug/);
});

test("a plan of the wrong shape or for another repository is refused", () => {
  assert.equal(planProblem(plan, "o/r"), null);
  assert.match(planProblem({ ...plan, repository: "x/y" }, "o/r"), /another repository/);
  assert.match(planProblem({ ...plan, version: 2 }, "o/r"), /unexpected shape/);
  assert.match(planProblem({ ...plan, incidents: [{ ...plan.incidents[0], body: "no marker" }] }, "o/r"), /unexpected shape/);
  assert.match(planProblem({ ...plan, incidents: [{ ...plan.incidents[0], body: "<!-- factory-monitor key=family:x fp=0123456789abcdef -->" }] }, "o/r"), /unexpected shape/);
});
