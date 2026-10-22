import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import {
  checkActors,
  MARKER,
  NEEDS_DECISION,
  NEW_BASIS,
  NEW_FOOTER,
  OLD_BASIS,
  OLD_FOOTER,
  parseVerdict,
  planWrites,
  READY,
  run,
} from "./apply-verdict.mjs";

const TRUSTED = fileURLToPath(new URL("../work-unblock/fixtures/trusted-actors.json", import.meta.url));
const HUMAN = 153232337;
const LANES_APP = 337595936;
const CLASSES = new Set(["work-class: scoped", "work-class: structural", "work-class: mechanical", "work-class: untrusted-provenance"]);
const OUTSIDER = 4242;
const humans = new Set([HUMAN]);
const logins = new Map([
  ["kyle-sexton", HUMAN],
  ["claude[bot]", 209825114],
]);

// The live models.issue-dimensions leaf's fields.
const DIMS = {
  fields: {
    size: {
      "field-id": 15462270,
      options: { 27053568: "small", 27053567: "medium", 27053566: "large" },
    },
    complexity: {
      "field-id": 48625720,
      options: { 85127651: "low", 85127652: "medium", 85127653: "high" },
    },
    uncertainty: {
      "field-id": 48625721,
      options: { 85127654: "known", 85127655: "knowable", 85127656: "unknown" },
    },
  },
};

const laneBody = ({ cls = "work-class: scoped", lines = ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none"] } = {}) =>
  [`${MARKER}\nProposed work class: ${cls}\n${OLD_BASIS}`, ["Priority medium: a docs fix.", ...lines].join("\n"), OLD_FOOTER].join("\n\n");
const ESCALATED_BODY = `${MARKER}\nProposed work class: none\n\nThanks for the report. Automated triage handed this issue to a maintainer.\n\n${OLD_FOOTER}`;

describe("parseVerdict", () => {
  test("reads the class, the three dimensions and no flags", () => {
    const verdict = parseVerdict(laneBody(), DIMS, CLASSES);
    assert.deepEqual(verdict, {
      escalated: false,
      workClass: "work-class: scoped",
      dimensions: { size: "small", complexity: "low", uncertainty: "known" },
      flags: [],
      problems: [],
    });
  });

  test("reads a flag list", () => {
    const verdict = parseVerdict(
      laneBody({
        lines: ["Size: Medium", "Complexity: High", "Uncertainty: Knowable", "Flags: cost, intent"],
      }),
      DIMS,
      CLASSES,
    );
    assert.deepEqual(verdict.flags, ["cost", "intent"]);
    assert.deepEqual(verdict.dimensions, {
      size: "medium",
      complexity: "high",
      uncertainty: "knowable",
    });
  });

  test("ignores quoted and indented lines, so a quoted decision steers nothing", () => {
    const verdict = parseVerdict(
      laneBody({
        lines: ["> Size: Small", "  Complexity: Low", "> Uncertainty: Known", "> Flags: none"],
      }),
      DIMS,
      CLASSES,
    );
    assert.equal(verdict.dimensions, null);
    assert.equal(verdict.flags, null);
    assert.equal(verdict.problems.length, 4);
  });

  test("a duplicated line counts as none", () => {
    const verdict = parseVerdict(
      laneBody({
        lines: ["Size: Small", "Size: Large", "Complexity: Low", "Uncertainty: Known", "Flags: none"],
      }),
      DIMS,
      CLASSES,
    );
    assert.equal(verdict.dimensions, null);
    assert.match(verdict.problems.join(), /more than one `Size:`/);
  });

  for (const [name, line] of [
    ["a lowercase option", "Size: small"],
    ["an option the config does not map", "Size: Huge"],
  ]) {
    test(`${name} writes no fields`, () => {
      const verdict = parseVerdict(
        laneBody({
          lines: [line, "Complexity: Low", "Uncertainty: Known", "Flags: none"],
        }),
        DIMS,
        CLASSES,
      );
      assert.equal(verdict.dimensions, null);
    });
  }

  for (const flags of ["Flags: intent, intent", "Flags: urgent", "Flags: none, cost"]) {
    test(`${flags} is unreadable`, () => {
      assert.equal(
        parseVerdict(
          laneBody({
            lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", flags],
          }),
          DIMS,
          CLASSES,
        ).flags,
        null,
      );
    });
  }

  test("takes the class only from the second line", () => {
    const body = `${MARKER}\nThanks.\nProposed work class: work-class: scoped\nSize: Small`;
    const verdict = parseVerdict(body, DIMS, CLASSES);
    assert.equal(verdict.workClass, null);
    assert.match(verdict.problems.join(), /second line/);
  });

  test("an escalated run carries no class", () => {
    const verdict = parseVerdict(ESCALATED_BODY, DIMS, CLASSES);
    assert.equal(verdict.escalated, true);
    assert.equal(verdict.workClass, null);
  });
});

describe("planWrites", () => {
  const plan = (body, { labels = [], fields = {}, classSetters = {} } = {}) =>
    planWrites(parseVerdict(body, DIMS, CLASSES), {
      labels,
      fields,
      dimensionsConfig: DIMS,
      appId: LANES_APP,
      humans,
      classSetters,
    });

  test("a clean verdict adds the class and status: ready and writes the three fields", () => {
    const result = plan(laneBody());
    assert.equal(result.ready, true);
    assert.deepEqual(result.add, ["work-class: scoped", READY]);
    assert.deepEqual(result.remove, []);
    assert.deepEqual(
      result.fieldWrites.map(({ fieldId, optionId, name }) => [fieldId, optionId, name]),
      [
        [15462270, 27053568, "Small"],
        [48625720, 85127651, "Low"],
        [48625721, 85127654, "Known"],
      ],
    );
  });

  test("a flag sends it to needs-decision but still writes the class and fields", () => {
    const result = plan(
      laneBody({
        lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: security"],
      }),
    );
    assert.equal(result.ready, false);
    assert.deepEqual(result.add, ["work-class: scoped", NEEDS_DECISION]);
    assert.equal(result.fieldWrites.length, 3);
  });

  test("an escalated run adds only needs-decision and takes status: ready off", () => {
    const result = plan(ESCALATED_BODY, { labels: [READY, "needs-human"] });
    assert.deepEqual(result.add, [NEEDS_DECISION]);
    assert.deepEqual(result.remove, [READY]);
    assert.deepEqual(result.fieldWrites, []);
    assert.equal(result.classApplied, false);
  });

  for (const hold of ["needs-human", "status: needs-info", NEEDS_DECISION]) {
    test(`${hold} on the issue keeps it from ready`, () => {
      const result = plan(laneBody(), { labels: [hold] });
      assert.equal(result.ready, false);
      assert.ok(!result.add.includes(READY));
      assert.equal(result.add.includes(NEEDS_DECISION), hold === "needs-human");
    });
  }

  test("another work class a listed human added is kept and holds the issue", () => {
    const result = plan(laneBody(), {
      labels: ["work-class: structural"],
      classSetters: { "work-class: structural": HUMAN },
    });
    assert.equal(result.classApplied, false);
    assert.deepEqual(result.add, [NEEDS_DECISION]);
    assert.deepEqual(result.remove, []);
  });

  test("another work class the lanes App added gives way to the new verdict", () => {
    const result = plan(laneBody(), {
      labels: ["work-class: mechanical"],
      classSetters: { "work-class: mechanical": LANES_APP },
    });
    assert.equal(result.ready, true);
    assert.deepEqual(result.remove, ["work-class: mechanical"]);
    assert.deepEqual(result.add, ["work-class: scoped", READY]);
  });

  for (const [name, setter] of [
    ["an unlisted account added", OUTSIDER],
    ["no event names (a renamed label)", undefined],
    ["a null actor added", null],
  ]) {
    test(`another work class ${name} is kept: an unknown setter counts as a person`, () => {
      const result = plan(laneBody(), {
        labels: ["work-class: mechanical"],
        classSetters: setter === undefined ? {} : { "work-class: mechanical": setter },
      });
      assert.equal(result.classApplied, false);
      assert.deepEqual(result.remove, []);
      assert.deepEqual(result.add, [NEEDS_DECISION]);
    });
  }

  for (const hold of ["work-class: structural", "work-class: untrusted-provenance"]) {
    test(`${hold} is never taken off, even when the lanes App added it`, () => {
      const result = plan(laneBody(), {
        labels: [hold],
        classSetters: { [hold]: LANES_APP },
      });
      assert.equal(result.classApplied, false);
      assert.deepEqual(result.remove, []);
      assert.deepEqual(result.add, [NEEDS_DECISION]);
    });
  }

  for (const [name, setter] of [
    ["an unlisted account", OUTSIDER],
    ["an unreadable setter", null],
  ]) {
    test(`a field ${name} set to another value is kept`, () => {
      const result = plan(laneBody(), {
        fields: { 15462270: { option: 27053566, setter } },
      });
      assert.equal(result.ready, false);
      assert.deepEqual(
        result.fieldWrites.map(({ key }) => key),
        ["complexity", "uncertainty"],
      );
    });
  }

  for (const [name, setter, ready] of [
    ["the lanes App", LANES_APP, true],
    ["a listed human", HUMAN, true],
    ["an unlisted account", OUTSIDER, false],
    ["an unreadable setter", null, false],
  ]) {
    test(`a field already holding the verdict's value, set by ${name}, ${ready ? "counts" : "holds the issue"}`, () => {
      const result = plan(laneBody(), { fields: { 15462270: { option: 27053568, setter } } });
      assert.equal(result.ready, ready);
      assert.ok(!result.fieldWrites.some(({ key }) => key === "size"), "a matching value is not rewritten");
    });
  }

  test("a class that is not one of the repository's work-class labels is not applied", () => {
    const verdict = parseVerdict(laneBody({ cls: "work-class: anything-goes" }), DIMS, CLASSES);
    assert.equal(verdict.workClass, null);
    const result = plan(laneBody({ cls: "work-class: anything-goes" }));
    assert.equal(result.ready, false);
    assert.ok(!result.add.includes("work-class: anything-goes"));
    assert.ok(result.add.includes(NEEDS_DECISION));
  });

  test("two work classes on the issue hold it", () => {
    const result = plan(laneBody(), {
      labels: ["work-class: structural", "work-class: mechanical"],
    });
    assert.equal(result.classApplied, false);
    assert.deepEqual(result.add, [NEEDS_DECISION]);
  });

  for (const label of ["area: security", "needs-triage"]) {
    test(`${label} keeps a clean verdict from ready and adds needs-decision`, () => {
      const result = plan(laneBody(), { labels: [label] });
      assert.equal(result.ready, false);
      assert.deepEqual(result.add, ["work-class: scoped", NEEDS_DECISION]);
    });
  }

  test("the same work class already on the issue counts as applied", () => {
    const result = plan(laneBody(), { labels: ["work-class: scoped"] });
    assert.equal(result.ready, true);
    assert.deepEqual(result.add, [READY]);
  });

  test("a field a listed human set to another value is kept and holds the issue", () => {
    const result = plan(laneBody(), {
      fields: { 15462270: { option: 27053566, setter: HUMAN } },
    });
    assert.equal(result.ready, false);
    assert.deepEqual(
      result.fieldWrites.map(({ key }) => key),
      ["complexity", "uncertainty"],
    );
  });

  test("a field the lanes App or nobody listed set is overwritten; one already right is not rewritten", () => {
    const result = plan(laneBody(), {
      fields: {
        15462270: { option: 27053566, setter: LANES_APP },
        48625720: { option: 85127651, setter: HUMAN },
      },
    });
    assert.equal(result.ready, true);
    assert.deepEqual(
      result.fieldWrites.map(({ key }) => key),
      ["size", "uncertainty"],
    );
  });
});

describe("checkActors", () => {
  const env = (overrides) => ({
    EVENT_NAME: "issues",
    ACTOR_ID: String(HUMAN),
    TRIGGERING_ACTOR: "kyle-sexton",
    RUN_ATTEMPT: "1",
    ...overrides,
  });
  const cases = [
    ["a listed human opened the issue", env({}), true],
    [
      "github-actions[bot] dispatched",
      env({
        EVENT_NAME: "workflow_dispatch",
        ACTOR_ID: "41898282",
        TRIGGERING_ACTOR: "github-actions[bot]",
      }),
      true,
    ],
    [
      "a listed human re-ran github-actions[bot]'s dispatch",
      env({
        EVENT_NAME: "workflow_dispatch",
        ACTOR_ID: "41898282",
        RUN_ATTEMPT: "2",
      }),
      true,
    ],
    ["github-actions[bot] on an issues event", env({ ACTOR_ID: "41898282" }), false],
    ["the lanes App opened the issue", env({ ACTOR_ID: String(LANES_APP) }), false],
    ["an outsider opened the issue", env({ ACTOR_ID: String(OUTSIDER) }), false],
    ["a listed bot re-ran it", env({ RUN_ATTEMPT: "2", TRIGGERING_ACTOR: "claude[bot]" }), false],
    [
      "github-actions[bot] re-ran its dispatch",
      env({
        EVENT_NAME: "workflow_dispatch",
        ACTOR_ID: "41898282",
        RUN_ATTEMPT: "2",
        TRIGGERING_ACTOR: "github-actions[bot]",
      }),
      false,
    ],
    ["a malformed actor id", env({ ACTOR_ID: "1; x" }), false],
  ];
  for (const [name, input, expected] of cases) {
    test(`${expected ? "proceeds" : "stops"} when ${name}`, () => {
      assert.equal(checkActors(input, humans, logins), expected);
    });
  }
});

// A fake GitHub: the issue, its comments and field values, recording every call.
function fakeGitHub({ issue = {}, comments, fieldRows = [], answerRows, events = [] } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (method === "GET" && path.startsWith("/repos/o/r/labels")) {
      return [...CLASSES, READY, NEEDS_DECISION].map((name) => ({ name }));
    }
    if (method === "GET" && path.startsWith("/repos/o/r/issues/7/events")) {
      return events;
    }
    if (method === "GET" && path === "/repos/o/r/issues/7") {
      return {
        number: 7,
        state: "open",
        user: { id: HUMAN },
        labels: [],
        ...issue,
      };
    }
    if (method === "GET" && path.startsWith("/repos/o/r/issues/7/comments")) {
      return comments;
    }
    if (method === "GET" && path === "/repos/o/r/issues/7/issue-field-values") {
      return fieldRows;
    }
    if (method === "POST" && path === "/repos/o/r/issues/7/issue-field-values") {
      return (
        answerRows ??
        body.issue_field_values.map(({ field_id, value }) => {
          const key = Object.keys(DIMS.fields).find((name) => DIMS.fields[name]["field-id"] === field_id);
          const id = Object.keys(DIMS.fields[key].options).find(
            (option) => DIMS.fields[key].options[option].toLowerCase() === value.toLowerCase(),
          );
          return {
            issue_field_id: field_id,
            single_select_option: { id: Number(id), name: value },
          };
        })
      );
    }
    if (method === "DELETE") {
      throw new GitHubError(404, "DELETE");
    }
    return null;
  };
  return { github, calls };
}
const laneComment = (body = laneBody(), overrides = {}) => ({
  id: 99,
  body,
  updated_at: "2026-10-22T12:05:00Z",
  user: { login: "github-actions[bot]", type: "Bot" },
  ...overrides,
});
const ENV = {
  KILL_SWITCH: "proceed",
  GITHUB_REPOSITORY: "o/r",
  ISSUE_NUMBER: "7",
  STARTED_AT: "2026-10-22T12:00:00Z",
  TRUSTED_ACTORS_PATH: TRUSTED,
};
const noSetters = async () => ({});
const go = (fake, env = ENV) =>
  run({
    env,
    github: fake.github,
    dimensionsConfig: DIMS,
    fieldSetters: noSetters,
    log: () => {},
  });
const writes = (calls) => calls.filter((call) => call.method !== "GET");

describe("run", () => {
  test("writes the fields, the class and status: ready, then rewords the comment", async () => {
    const fake = fakeGitHub({ comments: [laneComment()] });
    const result = await go(fake);
    assert.equal(result.outcome, "ready");
    const done = writes(fake.calls);
    assert.deepEqual(
      done.map(({ method, path }) => `${method} ${path}`),
      ["POST /repos/o/r/issues/7/issue-field-values", "POST /repos/o/r/issues/7/labels", "PATCH /repos/o/r/issues/comments/99"],
    );
    assert.deepEqual(done[0].body.issue_field_values, [
      { field_id: 15462270, value: "Small" },
      { field_id: 48625720, value: "Low" },
      { field_id: 48625721, value: "Known" },
    ]);
    assert.deepEqual(done[1].body.labels, ["work-class: scoped", READY]);
    assert.ok(done[2].body.body.includes(NEW_BASIS) && done[2].body.body.includes(NEW_FOOTER));
    assert.ok(!/maintainer/.test(done[2].body.body));
  });

  test("an escalated run writes only needs-decision and keeps the comment", async () => {
    const fake = fakeGitHub({ comments: [laneComment(ESCALATED_BODY)] });
    const result = await go(fake);
    assert.equal(result.outcome, "needs-decision");
    assert.deepEqual(
      writes(fake.calls).map(({ method, path, body }) => `${method} ${path} ${JSON.stringify(body)}`),
      [`POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [NEEDS_DECISION] })}`],
    );
  });

  test("an older lane comment is refused: this run's triage wrote none", async () => {
    const fake = fakeGitHub({
      comments: [laneComment(laneBody(), { updated_at: "2026-10-22T11:59:59Z" })],
    });
    await assert.rejects(go(fake), /before this run started/);
    assert.deepEqual(writes(fake.calls), []);
  });

  test("a marker comment from anyone but github-actions[bot] is not the lane's", async () => {
    const fake = fakeGitHub({
      comments: [
        laneComment(laneBody(), {
          user: { login: "kyle-sexton", type: "User" },
        }),
      ],
    });
    await assert.rejects(go(fake), /0 intake-triage lane comments/);
    assert.deepEqual(writes(fake.calls), []);
  });

  for (const [name, issue] of [
    ["an outsider's issue", { user: { id: OUTSIDER } }],
    ["a closed issue", { state: "closed" }],
    ["a pull request", { pull_request: {} }],
  ]) {
    test(`${name} gets nothing`, async () => {
      const fake = fakeGitHub({ issue, comments: [laneComment()] });
      assert.equal((await go(fake)).outcome, "skipped");
      assert.deepEqual(writes(fake.calls), []);
    });
  }

  test("an issue the lanes App opened gets the verdict", async () => {
    const fake = fakeGitHub({
      issue: { user: { id: LANES_APP } },
      comments: [laneComment()],
    });
    assert.equal((await go(fake)).outcome, "ready");
  });

  test("the kill switch stops it before any call", async () => {
    const fake = fakeGitHub({ comments: [laneComment()] });
    assert.equal((await go(fake, { ...ENV, KILL_SWITCH: "" })).outcome, "stopped");
    assert.deepEqual(fake.calls, []);
  });

  test("an option GitHub keeps under another id sets needs-decision and fails", async () => {
    const fake = fakeGitHub({
      comments: [laneComment()],
      answerRows: [
        {
          issue_field_id: 15462270,
          single_select_option: { id: 1, name: "Small" },
        },
      ],
    });
    await assert.rejects(go(fake), /GitHub kept other options/);
    const labelWrites = writes(fake.calls).filter(({ path }) => path.endsWith("/labels"));
    assert.deepEqual(
      labelWrites.map(({ body }) => body.labels),
      [[NEEDS_DECISION]],
    );
  });

  test("swaps a class the lanes App added, read from the issue's events, before adding the new one", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "work-class: mechanical" }] },
      comments: [laneComment()],
      events: [
        {
          event: "labeled",
          label: { name: "work-class: mechanical" },
          actor: { id: HUMAN },
        },
        {
          event: "unlabeled",
          label: { name: "work-class: mechanical" },
          actor: { id: HUMAN },
        },
        {
          event: "labeled",
          label: { name: "work-class: mechanical" },
          actor: { id: LANES_APP },
        },
      ],
    });
    const result = await go(fake);
    assert.equal(result.outcome, "ready");
    const done = writes(fake.calls).map(({ method, path }) => `${method} ${path}`);
    const removal = done.indexOf(`DELETE /repos/o/r/issues/7/labels/${encodeURIComponent("work-class: mechanical")}`);
    assert.ok(removal >= 0 && removal < done.indexOf("POST /repos/o/r/issues/7/labels"), done.join("\n"));
  });

  test("replaces the lanes App's own earlier class and field values given real-shaped ids", async () => {
    // The REST events API answers actor.id as a number; GraphQL answers
    // databaseId as a number, here passed as a string to prove the type
    // does not matter.
    const fake = fakeGitHub({
      issue: { labels: [{ name: "work-class: mechanical" }] },
      comments: [laneComment()],
      events: [
        {
          event: "labeled",
          label: { name: "work-class: mechanical" },
          actor: {
            id: 337595936,
            login: "melodic-automation-lanes[bot]",
            type: "Bot",
          },
        },
      ],
      fieldRows: [
        {
          issue_field_id: 15462270,
          data_type: "single_select",
          single_select_option: { id: 27053566, name: "Large", color: "red" },
        },
      ],
    });
    const result = await run({
      env: ENV,
      github: fake.github,
      dimensionsConfig: DIMS,
      fieldSetters: async () => ({ 15462270: "337595936" }),
      log: () => {},
    });
    assert.equal(result.outcome, "ready");
    const done = writes(fake.calls);
    assert.ok(
      done.some(
        ({ method, path }) => method === "DELETE" && path === `/repos/o/r/issues/7/labels/${encodeURIComponent("work-class: mechanical")}`,
      ),
    );
    const post = done.find(({ path }) => path.endsWith("/issue-field-values"));
    assert.deepEqual(post.body.issue_field_values[0], {
      field_id: 15462270,
      value: "Small",
    });
  });

  test("keeps a class a listed human added last", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "work-class: structural" }] },
      comments: [laneComment()],
      events: [
        {
          event: "labeled",
          label: { name: "work-class: structural" },
          actor: { id: LANES_APP },
        },
        {
          event: "labeled",
          label: { name: "work-class: structural" },
          actor: { id: HUMAN },
        },
      ],
    });
    assert.equal((await go(fake)).outcome, "needs-decision");
    assert.ok(!writes(fake.calls).some(({ method }) => method === "DELETE"));
  });

  test("status: ready is taken off when the verdict no longer holds", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: READY }] },
      comments: [laneComment(ESCALATED_BODY)],
    });
    await go(fake);
    assert.ok(
      writes(fake.calls).some(
        ({ method, path }) => method === "DELETE" && path === `/repos/o/r/issues/7/labels/${encodeURIComponent(READY)}`,
      ),
    );
  });

  test("a current human-set field is read through the setters and kept", async () => {
    const fake = fakeGitHub({
      comments: [laneComment()],
      fieldRows: [{ issue_field_id: 15462270, single_select_option: { id: 27053566 } }],
    });
    const result = await run({
      env: ENV,
      github: fake.github,
      dimensionsConfig: DIMS,
      fieldSetters: async () => ({ 15462270: HUMAN }),
      log: () => {},
    });
    assert.equal(result.outcome, "needs-decision");
    const post = writes(fake.calls).find(({ path }) => path.endsWith("/issue-field-values"));
    assert.deepEqual(
      post.body.issue_field_values.map(({ field_id }) => field_id),
      [48625720, 48625721],
    );
  });
});
