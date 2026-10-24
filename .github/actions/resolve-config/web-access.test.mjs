// A skill leaf's web-access, validated by the real schema and passed through
// to the selected activity for collect-base-activity. Contract:
// docs/conventions/pr-pipeline/README.md, "Activities", web-access.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { parse, stringify } from "yaml";

import { Rejection, resolve } from "./resolve.mjs";

const read = (relative) => readFileSync(new URL(relative, import.meta.url), "utf8");
const json = (relative) => JSON.parse(read(relative));

const run = (fixDocs) => {
  const doc = parse(read("./fixtures/valid.yaml"));
  Object.assign(doc.activities["fix-prose"], fixDocs);
  return resolve(
    {
      config: stringify(doc),
      schema: json("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json"),
      vocabulary: json("./fixtures/vocabulary.json"),
      laneRules: json("./lane-rules.json"),
      effectGrants: json("./effect-grants.json"),
      activityRules: json("./activity-rules.json"),
    },
    {
      lane: "pr-refine",
      activity: "fix-prose",
      configPath: "docs/conventions/pr-pipeline.yaml",
      basePath: ".base",
      facts: { event: "synchronize", changedPaths: ["README.md"], labels: [] },
    },
  );
};
const selected = (fixDocs) => run(fixDocs).selected;
const rejected = (fixDocs) =>
  assert.throws(
    () => run(fixDocs),
    (error) => {
      assert.ok(error instanceof Rejection, `expected a Rejection, got ${error}`);
      assert.equal(error.code, "invalid-config", error.message);
      return true;
    },
  );

test("an activity without web-access selects none", () => {
  assert.equal(selected({})["web-access"], undefined);
});

test("web-access with any domain passes through", () => {
  const webAccess = { enabled: true, domains: "any" };
  assert.deepEqual(selected({ "reads-untrusted": true, "web-access": webAccess })["web-access"], webAccess);
});

test("web-access with a domain list passes through", () => {
  const webAccess = { enabled: true, domains: ["code.claude.com", "*.github.com"] };
  assert.deepEqual(selected({ "reads-untrusted": true, "web-access": webAccess })["web-access"], webAccess);
});

test("web-access turned off validates with or without domains", () => {
  assert.doesNotThrow(() => selected({ "web-access": { enabled: false } }));
  assert.doesNotThrow(() => selected({ "web-access": { enabled: false, domains: "any" } }));
});

// Web pages are text anyone can write.
test("web-access on with reads-untrusted false fails the schema", () => {
  rejected({ "reads-untrusted": false, "web-access": { enabled: true, domains: "any" } });
});

test("web-access on without domains fails the schema", () => {
  rejected({ "reads-untrusted": true, "web-access": { enabled: true } });
});

for (const domains of ["all", [], ["*"], ["any"], ["code.claude.com,x"], ["Code.Claude.com"], ["localhost"], ["a..b"]]) {
  test(`web-access domains ${JSON.stringify(domains)} fail the schema`, () => {
    rejected({ "reads-untrusted": true, "web-access": { enabled: true, domains } });
  });
}

// Only the runner that stages edit tools grants the web, so a read skill that
// hands on no patch cannot ask for it (README.md, Activities, web-access).
test("web-access on with effect read and no applied-by.patch fails the schema", () => {
  rejected({ effect: "read", "reads-untrusted": true, "web-access": { enabled: true, domains: "any" } });
});

test("web-access off with effect read validates", () => {
  assert.doesNotThrow(() => selected({ effect: "read", "web-access": { enabled: false } }));
});

test("web-access with an unknown key fails the schema", () => {
  rejected({ "reads-untrusted": true, "web-access": { enabled: true, domains: "any", bash: true } });
});

test("web-access on a script activity fails the schema", () => {
  const doc = parse(read("./fixtures/valid.yaml"));
  doc.activities["run-tests"]["web-access"] = { enabled: false };
  assert.throws(
    () =>
      resolve(
        {
          config: stringify(doc),
          schema: json("../../../docs/conventions/pr-pipeline/pr-pipeline.schema.json"),
          vocabulary: json("./fixtures/vocabulary.json"),
          laneRules: json("./lane-rules.json"),
          effectGrants: json("./effect-grants.json"),
          activityRules: json("./activity-rules.json"),
        },
        {
          lane: "pr-run-checks",
          configPath: "docs/conventions/pr-pipeline.yaml",
          basePath: ".base",
          facts: { event: "synchronize", changedPaths: ["src/app.js"], labels: [] },
        },
      ),
    (error) => error instanceof Rejection && error.code === "invalid-config",
  );
});
