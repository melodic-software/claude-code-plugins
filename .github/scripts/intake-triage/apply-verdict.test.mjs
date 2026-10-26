import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import {
  checkActors,
  earlierFlags,
  MARKER,
  missedAnnotation,
  NEEDS_DECISION,
  NEW_BASIS,
  NEW_FOOTER,
  OLD_BASIS,
  OLD_FOOTER,
  parseVerdict,
  planWrites,
  READY,
  run,
  UNRECORDED,
  VERDICT_MARKER,
} from "./apply-verdict.mjs";

const TRUSTED = fileURLToPath(new URL("../work-unblock/fixtures/trusted-actors.json", import.meta.url));
const HUMAN = 153232337;
const LANES_APP = 337595936;
const CLASSES = new Set(["work-class: scoped", "work-class: structural", "work-class: mechanical", "work-class: untrusted-provenance"]);
const OUTSIDER = 4242;
const ACTIONS_BOT = 41898282;
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
      untrusted: false,
      dimensions: { size: "small", complexity: "low", uncertainty: "known" },
      flags: [],
      blockedBy: [],
      blockedByProblem: null,
      problems: [],
    });
  });

  test("reads the Blocked by line, ignoring a quoted one", () => {
    const lines = ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none"];
    assert.deepEqual(parseVerdict(laneBody({ lines: [...lines, "Blocked by: #12, #13"] }), DIMS, CLASSES).blockedBy, [12, 13]);
    assert.deepEqual(parseVerdict(laneBody({ lines: [...lines, "> Blocked by: #12"] }), DIMS, CLASSES).blockedBy, []);
  });

  test("an unreadable Blocked by line names no blocker and holds nothing", () => {
    const verdict = parseVerdict(
      laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", "Blocked by: 12"] }),
      DIMS,
      CLASSES,
    );
    assert.deepEqual(verdict.blockedBy, []);
    assert.match(verdict.blockedByProblem, /not none or a list of #<number>/);
    assert.deepEqual(verdict.problems, []);
  });

  test("model text quoted in a problem keeps no mention, backtick or markup", () => {
    const verdict = parseVerdict(
      laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: @owner `x` <b>"] }),
      DIMS,
      CLASSES,
    );
    assert.equal(verdict.flags, null);
    assert.equal(verdict.problems.length, 1);
    const quoted = /^`Flags: (.*)` is not none/.exec(verdict.problems[0]);
    assert.ok(quoted, verdict.problems[0]);
    assert.doesNotMatch(quoted[1], /[@`<>]/);
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

  test("takes the class only from the second line, and a missing one is no problem", () => {
    const body = `${MARKER}\nThanks.\nProposed work class: work-class: scoped\nSize: Small`;
    const verdict = parseVerdict(body, DIMS, CLASSES);
    assert.equal(verdict.workClass, null);
    assert.doesNotMatch(verdict.problems.join(), /class/);
  });

  test("an escalated run carries no class", () => {
    const verdict = parseVerdict(ESCALATED_BODY, DIMS, CLASSES);
    assert.equal(verdict.escalated, true);
    assert.equal(verdict.workClass, null);
  });
});

describe("planWrites", () => {
  const plan = (body, { labels = [], fields = {}, classSetters = {}, holdSetters = {}, earlierFlags = [] } = {}) =>
    planWrites(parseVerdict(body, DIMS, CLASSES), {
      labels,
      fields,
      dimensionsConfig: DIMS,
      appId: LANES_APP,
      humans,
      classSetters,
      holdSetters,
      earlierFlags,
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

  // Admission criteria 1 (intent), 5 (very-high security) and 6 (cost) rest on these.
  for (const flag of ["intent", "security", "cost"]) {
    test(`a ${flag} flag sends it to needs-decision but still writes the class and fields`, () => {
      const result = plan(
        laneBody({
          lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", `Flags: ${flag}`],
        }),
      );
      assert.equal(result.ready, false);
      assert.deepEqual(result.add, ["work-class: scoped", NEEDS_DECISION]);
      assert.equal(result.fieldWrites.length, 3);
    });
  }

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

    if (hold !== "needs-human") {
      test(`${hold} the lanes App set gives way to a clean verdict and is taken off`, () => {
        const result = plan(laneBody(), { labels: [hold], holdSetters: { [hold]: LANES_APP } });
        assert.equal(result.ready, true);
        assert.deepEqual(result.add, ["work-class: scoped", READY]);
        assert.deepEqual(result.remove, [hold]);
      });

      // Owner decision on #9799's review: a flagged hold is not lifted by a later clean verdict.
      test(`${hold} the lanes App set after an earlier flagged verdict stays on a clean verdict`, () => {
        const result = plan(laneBody(), { labels: [hold], holdSetters: { [hold]: LANES_APP }, earlierFlags: ["security"] });
        assert.equal(result.ready, false);
        assert.deepEqual(result.remove, []);
        assert.ok(!result.add.includes(READY));
        assert.ok(result.reasons.includes(`held by ${hold}`), result.reasons.join("; "));
        // Carried forward, so the next clean verdict still reads the flag.
        assert.ok(result.reasons.includes("flagged: security (an earlier verdict)"), result.reasons.join("; "));
      });
    }

    for (const [name, setter] of [
      ["the triage run (github-actions[bot])", ACTIONS_BOT],
      ["a listed human", HUMAN],
      ["an unlisted account", OUTSIDER],
      ["a null actor", null],
    ]) {
      test(`${hold} ${name} set still holds`, () => {
        const result = plan(laneBody(), { labels: [hold], holdSetters: { [hold]: setter } });
        assert.equal(result.ready, false);
        assert.deepEqual(result.remove, []);
        assert.ok(result.reasons.includes(`held by ${hold}`), result.reasons.join("; "));
      });
    }
  }

  // Owner decision on #9799's review, fail-closed: with no readable earlier
  // verdict, the earlier run may have flagged, so the hold stays and says so.
  for (const hold of ["status: needs-info", NEEDS_DECISION]) {
    test(`${hold} the lanes App set with no readable earlier verdict stays on a clean verdict`, () => {
      const result = plan(laneBody(), { labels: [hold], holdSetters: { [hold]: LANES_APP }, earlierFlags: null });
      assert.equal(result.ready, false);
      assert.deepEqual(result.remove, []);
      assert.ok(!result.add.includes(READY));
      assert.ok(result.reasons.includes(`held by ${hold}`), result.reasons.join("; "));
      assert.ok(result.reasons.includes(UNRECORDED), result.reasons.join("; "));
    });
  }

  test("no readable earlier verdict on an issue with no hold reaches ready", () => {
    const result = plan(laneBody(), { earlierFlags: null });
    assert.equal(result.ready, true);
    assert.deepEqual(result.reasons, []);
  });

  // Owner decision on #9799's review: a clean verdict never lifts needs-human, whoever set it.
  test("needs-human the lanes App set stays on a clean verdict", () => {
    const result = plan(laneBody(), { labels: ["needs-human"], holdSetters: { "needs-human": LANES_APP } });
    assert.equal(result.ready, false);
    assert.deepEqual(result.remove, []);
    assert.ok(!result.add.includes(READY));
    assert.ok(result.reasons.includes("held by needs-human"), result.reasons.join("; "));
  });

  test("an earlier flag the current verdict repeats is not listed twice", () => {
    const result = plan(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: security"] }), {
      labels: [NEEDS_DECISION],
      holdSetters: { [NEEDS_DECISION]: LANES_APP },
      earlierFlags: ["security", "intent"],
    });
    assert.deepEqual(result.reasons, ["flagged: security", `held by ${NEEDS_DECISION}`, "flagged: intent (an earlier verdict)"]);
  });

  test("a lanes App hold stays on a verdict that is not ready", () => {
    const result = plan(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: intent"] }), {
      labels: [NEEDS_DECISION],
      holdSetters: { [NEEDS_DECISION]: LANES_APP },
    });
    assert.equal(result.ready, false);
    assert.deepEqual(result.remove, []);
    assert.deepEqual(result.reasons, ["flagged: intent"]);
  });

  // Owner decision Q85 (#9668): the work class gates nothing.
  test("another work class a listed human added is kept and does not hold the issue", () => {
    const result = plan(laneBody(), {
      labels: ["work-class: structural"],
      classSetters: { "work-class: structural": HUMAN },
    });
    assert.equal(result.classApplied, false);
    assert.equal(result.ready, true);
    assert.deepEqual(result.add, [READY]);
    assert.deepEqual(result.remove, []);
  });

  for (const cls of ["none", "work-class: structural"]) {
    test(`a verdict proposing ${cls} reaches ready`, () => {
      const result = plan(laneBody({ cls }));
      assert.equal(result.ready, true);
      assert.ok(result.add.includes(READY));
      assert.ok(!result.add.includes(NEEDS_DECISION));
    });
  }

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
      assert.deepEqual(result.add, [READY]);
    });
  }

  test("work-class: untrusted-provenance is never taken off and holds the issue, even when the lanes App added it", () => {
    const hold = "work-class: untrusted-provenance";
    const result = plan(laneBody(), {
      labels: [hold],
      classSetters: { [hold]: LANES_APP },
    });
    assert.equal(result.classApplied, false);
    assert.deepEqual(result.remove, []);
    assert.deepEqual(result.add, [NEEDS_DECISION]);
  });

  test("a verdict proposing work-class: untrusted-provenance applies it and holds the issue", () => {
    const result = plan(laneBody({ cls: "work-class: untrusted-provenance" }));
    assert.equal(result.ready, false);
    assert.deepEqual(result.add, ["work-class: untrusted-provenance", NEEDS_DECISION]);
  });

  test("an untrusted-provenance verdict holds even when the repository lacks the label", () => {
    const verdict = parseVerdict(laneBody({ cls: "work-class: untrusted-provenance" }), DIMS, new Set(["work-class: scoped"]));
    const result = planWrites(verdict, { labels: [], fields: {}, dimensionsConfig: DIMS, appId: LANES_APP, humans });
    assert.equal(result.ready, false);
    assert.ok(result.add.includes(NEEDS_DECISION));
  });

  test("an untrusted-provenance verdict adds the label beside a class a person set", () => {
    const result = plan(laneBody({ cls: "work-class: untrusted-provenance" }), {
      labels: ["work-class: mechanical"],
      classSetters: { "work-class: mechanical": HUMAN },
    });
    assert.equal(result.ready, false);
    assert.deepEqual(result.remove, []);
    assert.deepEqual(result.add, ["work-class: untrusted-provenance", NEEDS_DECISION]);
  });

  test("work-class: structural the lanes App added gives way to the new verdict", () => {
    const result = plan(laneBody(), {
      labels: ["work-class: structural"],
      classSetters: { "work-class: structural": LANES_APP },
    });
    assert.equal(result.ready, true);
    assert.deepEqual(result.remove, ["work-class: structural"]);
    assert.deepEqual(result.add, ["work-class: scoped", READY]);
  });

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

  test("a class that is not one of the repository's work-class labels is not applied and does not hold", () => {
    const verdict = parseVerdict(laneBody({ cls: "work-class: anything-goes" }), DIMS, CLASSES);
    assert.equal(verdict.workClass, null);
    assert.deepEqual(verdict.problems, []);
    const result = plan(laneBody({ cls: "work-class: anything-goes" }));
    assert.equal(result.ready, true);
    assert.deepEqual(result.add, [READY]);
  });

  test("two work classes on the issue are kept and do not hold it", () => {
    const result = plan(laneBody(), {
      labels: ["work-class: structural", "work-class: mechanical"],
    });
    assert.equal(result.classApplied, false);
    assert.deepEqual(result.add, [READY]);
  });

  test("needs-triage the triage left does not keep a clean verdict from ready, and is taken off", () => {
    const result = plan(laneBody(), { labels: ["needs-triage"] });
    assert.equal(result.ready, true);
    assert.deepEqual(result.add, ["work-class: scoped", READY]);
    assert.deepEqual(result.remove, ["needs-triage"]);
  });

  test("needs-triage is taken off a held verdict too", () => {
    const result = plan(ESCALATED_BODY, { labels: ["needs-triage"] });
    assert.equal(result.ready, false);
    assert.deepEqual(result.remove, ["needs-triage"]);
  });

  test("area: security alone does not hold a clean verdict; only the security flag does", () => {
    const result = plan(laneBody(), { labels: ["area: security"] });
    assert.equal(result.ready, true);
    assert.deepEqual(result.add, ["work-class: scoped", READY]);
  });

  test("the same work class already on the issue counts as applied", () => {
    const result = plan(laneBody(), { labels: ["work-class: scoped"] });
    assert.equal(result.ready, true);
    assert.deepEqual(result.add, [READY]);
  });

  test("a field a listed human set to another value is kept, counts for admission, and does not hold", () => {
    const result = plan(laneBody(), {
      fields: { 15462270: { option: 27053566, setter: HUMAN } },
    });
    assert.equal(result.ready, true);
    assert.deepEqual(result.reasons, []);
    assert.deepEqual(
      result.fieldWrites.map(({ key }) => key),
      ["complexity", "uncertainty"],
    );
    assert.deepEqual(result.dimensions, { size: "large", complexity: "low", uncertainty: "known" });
  });

  test("a listed human's field option the config does not map holds the issue", () => {
    const result = plan(laneBody(), {
      fields: { 15462270: { option: 1, setter: HUMAN } },
    });
    assert.equal(result.ready, false);
    assert.ok(result.reasons.includes("Size holds an option models.issue-dimensions does not map"), result.reasons.join("; "));
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

describe("earlierFlags", () => {
  const own = (body) => [{ id: 51, body: `${VERDICT_MARKER}\n${body}`, user: { id: LANES_APP, type: "Bot" } }];
  test("reads the flags the lanes App's verdict comment listed, an earlier verdict's too", () => {
    assert.deepEqual(earlierFlags(own("x:\n\n- flagged: security\n- flagged: intent (an earlier verdict)"), LANES_APP), ["security", "intent"]);
  });
  test("an unflagged verdict comment lists none", () => {
    assert.deepEqual(earlierFlags(own("x:\n\n- no `Size:` line"), LANES_APP), []);
  });
  test("no lanes App verdict comment, or one carrying the unrecorded line, is unknown", () => {
    assert.equal(earlierFlags([], LANES_APP), null);
    assert.equal(earlierFlags([{ id: 50, body: `${VERDICT_MARKER}\n- no \`Size:\` line`, user: { id: HUMAN, type: "User" } }], LANES_APP), null);
    assert.equal(earlierFlags(own(`x:\n\n- ${UNRECORDED}`), LANES_APP), null);
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
function fakeGitHub({ issue = {}, comments, fieldRows = [], answerRows, events = [], blockers = {} } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (method === "GET" && path.startsWith("/repos/o/r/issues/7/dependencies/blocked_by")) {
      return [];
    }
    const other = /^\/repos\/o\/r\/issues\/([0-9]+)$/.exec(path);
    if (method === "GET" && other && other[1] !== "7") {
      if (!blockers[other[1]]) {
        throw new GitHubError(404, path);
      }
      return blockers[other[1]];
    }
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
// The lanes App's earlier verdict comment, listing no flag.
const unflagged = (text = "The latest triage verdict holds nothing: admission did not finish, so the issue's status is not settled.") => ({
  id: 51,
  body: `${VERDICT_MARKER}\n${text}`,
  user: { id: LANES_APP, type: "Bot" },
});
const APP_HOLD = [{ event: "labeled", label: { name: NEEDS_DECISION }, actor: { id: LANES_APP } }];

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

  test("an escalated run writes only needs-decision and its reasons, and keeps the lane comment", async () => {
    const fake = fakeGitHub({ comments: [laneComment(ESCALATED_BODY)] });
    const result = await go(fake);
    assert.equal(result.outcome, "needs-decision");
    assert.deepEqual(
      writes(fake.calls).map(({ method, path }) => `${method} ${path}`),
      ["POST /repos/o/r/issues/7/comments", "POST /repos/o/r/issues/7/labels"],
    );
    assert.deepEqual(writes(fake.calls)[1].body, { labels: [NEEDS_DECISION] });
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

  test("an option GitHub keeps under another id fails the run and adds no label", async () => {
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
    assert.deepEqual(
      writes(fake.calls).map(({ method, path }) => `${method} ${path}`),
      ["POST /repos/o/r/issues/7/issue-field-values"],
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
    // Owner decision Q85 (#9668): the kept class no longer holds the issue.
    assert.equal((await go(fake)).outcome, "ready");
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

  test("a current human-set field is read through the setters, kept, and handed to admission", async () => {
    const fake = fakeGitHub({
      comments: [laneComment()],
      fieldRows: [{ issue_field_id: 15462270, single_select_option: { id: 27053566 } }],
    });
    const seen = [];
    const result = await run({
      env: ENV,
      github: fake.github,
      dimensionsConfig: DIMS,
      fieldSetters: async () => ({ 15462270: HUMAN }),
      admitIssue: async (verdict) => {
        seen.push(verdict.dimensions);
        return { outcome: "refused", reasons: [] };
      },
      log: () => {},
    });
    assert.equal(result.outcome, "ready");
    assert.deepEqual(seen, [{ size: "large", complexity: "low", uncertainty: "known" }]);
    const post = writes(fake.calls).find(({ path }) => path.endsWith("/issue-field-values"));
    assert.deepEqual(
      post.body.issue_field_values.map(({ field_id }) => field_id),
      [48625720, 48625721],
    );
  });

  test("hands a ready verdict to admission, and nothing else", async () => {
    const seen = [];
    const admitIssue = async (verdict) => {
      seen.push(verdict);
      return { outcome: "admitted", reasons: [] };
    };
    const ready = await run({
      env: ENV,
      github: fakeGitHub({ comments: [laneComment()] }).github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue,
      log: () => {},
    });
    assert.equal(ready.outcome, "ready");
    assert.equal(ready.admission.outcome, "admitted");
    assert.equal(seen.length, 1);
    assert.equal(seen[0].workClass, "work-class: scoped");
    assert.deepEqual(seen[0].dimensions, {
      size: "small",
      complexity: "low",
      uncertainty: "known",
    });
    const held = await run({
      env: ENV,
      github: fakeGitHub({ comments: [laneComment(ESCALATED_BODY)] }).github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue,
      log: () => {},
    });
    assert.equal(held.outcome, "needs-decision");
    assert.equal(seen.length, 1);
  });

  test("an escalated or flagged verdict hands the issue to the split note; a ready one does not", async () => {
    const seen = [];
    const noteSplit = async (issue) => {
      seen.push(issue.number);
      return { outcome: "noted", reasons: ["its done-when asks for what an unattended lane run cannot perform"] };
    };
    const held = await run({
      env: ENV,
      github: fakeGitHub({ comments: [laneComment(ESCALATED_BODY)] }).github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue: async () => assert.fail("a held verdict is not admitted"),
      noteSplit,
      log: () => {},
    });
    assert.equal(held.outcome, "needs-decision");
    assert.equal(held.admission.outcome, "noted");
    assert.match(held.summary, /- Admission: noted/);
    const ready = await run({
      env: ENV,
      github: fakeGitHub({ comments: [laneComment()] }).github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue: async () => ({ outcome: "refused", reasons: [] }),
      noteSplit,
      log: () => {},
    });
    assert.equal(ready.outcome, "ready");
    assert.equal(seen.length, 1);
  });

  test("admits before rewording, so a refused comment edit does not stop admission", async () => {
    const seen = [];
    const fake = fakeGitHub({ comments: [laneComment()] });
    const github = async (method, path, body) => {
      if (method === "PATCH") {
        throw new GitHubError(403, "PATCH");
      }
      return fake.github(method, path, body);
    };
    await assert.rejects(
      run({
        env: ENV,
        github,
        dimensionsConfig: DIMS,
        fieldSetters: noSetters,
        admitIssue: async (verdict) => {
          seen.push(verdict);
          return { outcome: "admitted", reasons: [] };
        },
        log: () => {},
      }),
    );
    assert.equal(seen.length, 1);
  });

  test("an admission error still rewords the comment and reports the verdict", async () => {
    const fake = fakeGitHub({ comments: [laneComment()] });
    const result = await run({
      env: ENV,
      github: fake.github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue: async () => {
        throw new Error("admission-rules.json: `types` must be a list of strings");
      },
      log: () => {},
    });
    assert.equal(result.outcome, "ready");
    assert.deepEqual(result.admission, { outcome: "error", reasons: ["admission-rules.json: `types` must be a list of strings"] });
    assert.ok(writes(fake.calls).some(({ method }) => method === "PATCH"));
    assert.match(result.summary, /- Admission: error \(admission-rules\.json/);
  });

  test("a needs-decision the lanes App set earlier, read from the events, is lifted by a clean verdict", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: NEEDS_DECISION }] },
      comments: [laneComment(), unflagged()],
      events: APP_HOLD,
    });
    assert.equal((await go(fake)).outcome, "ready");
    assert.ok(
      writes(fake.calls).some(
        ({ method, path }) => method === "DELETE" && path === `/repos/o/r/issues/7/labels/${encodeURIComponent(NEEDS_DECISION)}`,
      ),
    );
  });

  test("a needs-human the triage run's escalation set last, read from the events, keeps the hold", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [
        { event: "labeled", label: { name: "needs-human" }, actor: { id: LANES_APP } },
        { event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT } },
      ],
    });
    assert.equal((await go(fake)).outcome, "needs-decision");
    assert.ok(!writes(fake.calls).some(({ method }) => method === "DELETE"));
  });

  test("a hold the lanes App set after its earlier verdict comment listed a flag stays on a clean verdict", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: NEEDS_DECISION }] },
      comments: [
        laneComment(),
        { id: 51, body: `${VERDICT_MARKER}\nThe triage verdict left this issue at \`${NEEDS_DECISION}\`:\n\n- flagged: security`, user: { id: LANES_APP, type: "Bot" } },
      ],
      events: [{ event: "labeled", label: { name: NEEDS_DECISION }, actor: { id: LANES_APP } }],
    });
    assert.equal((await go(fake)).outcome, "needs-decision");
    assert.ok(!writes(fake.calls).some(({ method }) => method === "DELETE"));
    const patch = writes(fake.calls).find(({ path }) => path === "/repos/o/r/issues/comments/51");
    assert.match(patch.body.body, /- flagged: security \(an earlier verdict\)/);
  });

  test("a hold the lanes App set after an earlier verdict with no flag is lifted on a clean verdict", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: NEEDS_DECISION }] },
      comments: [
        laneComment(),
        { id: 51, body: `${VERDICT_MARKER}\nThe triage verdict left this issue at \`${NEEDS_DECISION}\`:\n\n- no \`Size:\` line`, user: { id: LANES_APP, type: "Bot" } },
      ],
      events: [{ event: "labeled", label: { name: NEEDS_DECISION }, actor: { id: LANES_APP } }],
    });
    assert.equal((await go(fake)).outcome, "ready");
    assert.ok(writes(fake.calls).some(({ method, path }) => method === "DELETE" && path === `/repos/o/r/issues/7/labels/${encodeURIComponent(NEEDS_DECISION)}`));
  });

  test("a flagged look-alike verdict comment from anyone but the lanes App does not keep the hold", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: NEEDS_DECISION }] },
      comments: [
        laneComment(),
        { id: 50, body: `${VERDICT_MARKER}\n- flagged: security`, user: { id: HUMAN, login: "kyle-sexton", type: "User" } },
        unflagged(),
      ],
      events: APP_HOLD,
    });
    assert.equal((await go(fake)).outcome, "ready");
  });

  // Issues the App held before verdict comments existed have none to read.
  test("a needs-decision the lanes App set with no verdict comment stays on two clean verdicts in a row", async () => {
    const first = fakeGitHub({ issue: { labels: [{ name: NEEDS_DECISION }] }, comments: [laneComment()], events: APP_HOLD });
    assert.equal((await go(first)).outcome, "needs-decision");
    assert.ok(!writes(first.calls).some(({ method }) => method === "DELETE"));
    const posted = writes(first.calls).find(({ method, path }) => method === "POST" && path === "/repos/o/r/issues/7/comments");
    assert.ok(posted?.body.body.includes(`- ${UNRECORDED}`), posted?.body.body);
    // The second run reads the comment the first posted, which must not read as unflagged.
    const second = fakeGitHub({
      issue: { labels: [{ name: NEEDS_DECISION }] },
      comments: [laneComment(), { id: 52, body: posted.body.body, user: { id: LANES_APP, type: "Bot" } }],
      events: APP_HOLD,
    });
    assert.equal((await go(second)).outcome, "needs-decision");
    assert.ok(!writes(second.calls).some(({ method }) => method === "DELETE"));
  });

  // The record goes before the hold: a hold never lands without the comment
  // that says whether it was flagged.
  for (const [name, comments, failing] of [
    ["no earlier verdict comment and a failed post", [], "POST /repos/o/r/issues/7/comments"],
    ["an earlier unflagged verdict comment and a failed edit", [unflagged("The triage verdict left this issue at `status: needs-decision`:\n\n- no `Size:` line")], "PATCH /repos/o/r/issues/comments/51"],
  ]) {
    test(`a flagged verdict with ${name} writes no label, reports the failure, and fails the run`, async () => {
      const fake = fakeGitHub({ comments: [laneComment(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: security"] })), ...comments] });
      const github = async (method, path, body) => {
        if (`${method} ${path}` === failing) {
          fake.calls.push({ method, path, body });
          throw new GitHubError(403, failing);
        }
        return fake.github(method, path, body);
      };
      const result = await run({ env: ENV, github, dimensionsConfig: DIMS, fieldSetters: noSetters, log: () => {} });
      assert.ok(result.plan.classApplied);
      assert.ok(result.reasonsError, "the failure is on the result");
      assert.match(result.summary, /- Reasons comment: not written \(/);
      const labelWrites = writes(fake.calls).filter(({ path }) => path.startsWith("/repos/o/r/issues/7/labels"));
      assert.deepEqual(labelWrites, [], "no hold lands without its record");
      assert.ok(!writes(fake.calls).some(({ path }) => path === "/repos/o/r/issues/comments/99"), "no class, so no reword");
    });
  }

  // Taking status: ready off adds no hold, so it needs no record and never waits on one.
  for (const [name, comments, failing] of [
    ["a failed post", [], "POST /repos/o/r/issues/7/comments"],
    ["a failed edit", [unflagged()], "PATCH /repos/o/r/issues/comments/51"],
  ]) {
    test(`a flagged re-triage of an issue at status: ready with ${name} still takes status: ready off and adds no hold`, async () => {
      const fake = fakeGitHub({
        issue: { labels: [{ name: READY }] },
        comments: [laneComment(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: security"] })), ...comments],
      });
      const github = async (method, path, body) => {
        if (`${method} ${path}` === failing) {
          fake.calls.push({ method, path, body });
          throw new GitHubError(403, failing);
        }
        return fake.github(method, path, body);
      };
      const result = await run({ env: ENV, github, dimensionsConfig: DIMS, fieldSetters: noSetters, log: () => {} });
      assert.ok(result.reasonsError, "the run fails");
      const labelWrites = writes(fake.calls).filter(({ path }) => path.startsWith("/repos/o/r/issues/7/labels"));
      assert.deepEqual(
        labelWrites.map(({ method, path }) => `${method} ${path}`),
        [`DELETE /repos/o/r/issues/7/labels/${encodeURIComponent(READY)}`],
      );
      assert.match(result.summary, /removed: status: ready/);
    });
  }

  test("a failed edit of the reasons comment on a ready verdict still rewords the lane comment and reports the failure", async () => {
    const fake = fakeGitHub({ comments: [laneComment(), unflagged()] });
    const github = async (method, path, body) => {
      if (method === "PATCH" && path === "/repos/o/r/issues/comments/51") {
        fake.calls.push({ method, path, body });
        throw new GitHubError(403, "PATCH comments");
      }
      return fake.github(method, path, body);
    };
    const result = await run({ env: ENV, github, dimensionsConfig: DIMS, fieldSetters: noSetters, log: () => {} });
    assert.equal(result.outcome, "ready");
    assert.ok(writes(fake.calls).some(({ method, path }) => method === "PATCH" && path === "/repos/o/r/issues/comments/99"));
    assert.ok(result.reasonsError, "the failure is on the result");
    assert.match(result.summary, /- Reasons comment: not written \(/);
  });

  test("an admission refusal on a ready verdict leaves an unflagged verdict record, so a later clean verdict can lift it", async () => {
    const fake = fakeGitHub({ comments: [laneComment()] });
    await run({
      env: ENV,
      github: fake.github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue: async () => ({ outcome: "refused", reasons: ["no acceptance criteria"] }),
      log: () => {},
    });
    const posted = writes(fake.calls).find(({ method, path }) => method === "POST" && path === "/repos/o/r/issues/7/comments");
    assert.ok(posted?.body.body.startsWith(`${VERDICT_MARKER}\n`), posted?.body.body);
    assert.deepEqual(earlierFlags([{ ...posted.body, id: 53, user: { id: LANES_APP } }], LANES_APP), []);
  });

  test("takes needs-triage off after the verdict's labels", async () => {
    const fake = fakeGitHub({ issue: { labels: [{ name: "needs-triage" }] }, comments: [laneComment()] });
    assert.equal((await go(fake)).outcome, "ready");
    const done = writes(fake.calls).map(({ method, path }) => `${method} ${path}`);
    const removal = done.indexOf("DELETE /repos/o/r/issues/7/labels/needs-triage");
    assert.ok(removal > done.indexOf("POST /repos/o/r/issues/7/labels"), done.join("\n"));
  });

  test("posts the reasons on the issue when it sets needs-decision", async () => {
    const fake = fakeGitHub({ comments: [laneComment(ESCALATED_BODY)] });
    await go(fake);
    const posted = writes(fake.calls).filter(({ method, path }) => method === "POST" && path === "/repos/o/r/issues/7/comments");
    assert.equal(posted.length, 1);
    assert.ok(posted[0].body.body.startsWith(`${VERDICT_MARKER}\n`));
    assert.match(posted[0].body.body, /the triage run escalated/);
  });

  test("edits its own earlier reasons comment in place, and leaves a look-alike from anyone else", async () => {
    const fake = fakeGitHub({
      comments: [
        laneComment(ESCALATED_BODY),
        { id: 50, body: `${VERDICT_MARKER}\nold`, user: { id: HUMAN, login: "kyle-sexton", type: "User" } },
        { id: 51, body: `${VERDICT_MARKER}\nold`, user: { id: LANES_APP, login: "melodic-automation-lanes[bot]", type: "Bot" } },
      ],
    });
    await go(fake);
    const done = writes(fake.calls).filter(({ path }) => path.includes("/comments"));
    assert.deepEqual(
      done.map(({ method, path }) => `${method} ${path}`),
      ["PATCH /repos/o/r/issues/comments/51"],
    );
    assert.match(done[0].body.body, /the triage run escalated/);
  });

  test("a ready verdict posts no reasons comment, and marks an earlier one settled", async () => {
    const fresh = fakeGitHub({ comments: [laneComment()] });
    await go(fresh);
    assert.ok(!writes(fresh.calls).some(({ path }) => path === "/repos/o/r/issues/7/comments"));
    const earlier = fakeGitHub({
      comments: [laneComment(), { id: 51, body: `${VERDICT_MARKER}\nold`, user: { id: LANES_APP, type: "Bot" } }],
    });
    await go(earlier);
    const patch = writes(earlier.calls).find(({ path }) => path === "/repos/o/r/issues/comments/51");
    assert.ok(patch, "the earlier comment is edited");
    assert.ok(patch.body.body.includes(READY), patch.body.body);
  });

  test("a ready verdict that admission refuses or errors on does not mark the earlier comment ready", async () => {
    for (const outcome of ["refused", "error"]) {
      const fake = fakeGitHub({
        comments: [laneComment(), { id: 51, body: `${VERDICT_MARKER}\nold`, user: { id: LANES_APP, type: "Bot" } }],
      });
      const result = await run({
        env: ENV,
        github: fake.github,
        dimensionsConfig: DIMS,
        fieldSetters: noSetters,
        admitIssue: async () => {
          if (outcome === "error") throw new Error("boom");
          return { outcome, reasons: ["no acceptance criteria"] };
        },
        log: () => {},
      });
      const patch = writes(fake.calls).find(({ path }) => path === "/repos/o/r/issues/comments/51");
      assert.ok(patch, `${outcome}: the earlier comment is edited`);
      assert.ok(!patch.body.body.includes(READY), `${outcome}: ${patch.body.body}`);
      assert.ok(!result.summary.includes(`- Status: ${READY}`), `${outcome}: ${result.summary}`);
    }
  });

  test("writes a blocked-by edge for each open issue the verdict names, before admission", async () => {
    const order = [];
    const fake = fakeGitHub({
      comments: [
        laneComment(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", "Blocked by: #12, #13"] })),
      ],
      blockers: {
        12: { id: 9012, number: 12, state: "open", repository_url: "https://api.github.com/repos/o/r" },
        13: { id: 9013, number: 13, state: "closed", repository_url: "https://api.github.com/repos/o/r" },
      },
    });
    const github = async (method, path, body) => {
      if (method === "POST" && path.endsWith("/dependencies/blocked_by")) {
        order.push(`edge ${body.issue_id}`);
      }
      return fake.github(method, path, body);
    };
    const result = await run({
      env: ENV,
      github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue: async () => {
        order.push("admit");
        return { outcome: "waiting", reasons: [] };
      },
      log: () => {},
    });
    assert.deepEqual(order, ["edge 9012", "admit"]);
    assert.ok(result.summary.includes("- Blocked by: #12 written; #13 skipped (not open)"), result.summary);
  });

  describe("blockers the issue body names", () => {
    const REPO = "https://api.github.com/repos/o/r";
    const blockers = {
      12: { id: 9012, number: 12, state: "open", repository_url: REPO },
      13: { id: 9013, number: 13, state: "open", repository_url: REPO },
      14: { id: 9014, number: 14, state: "closed", repository_url: REPO },
    };
    const edgePosts = (calls) => calls.filter(({ method, path }) => method === "POST" && path.endsWith("/dependencies/blocked_by")).map(({ body }) => body.issue_id);
    // #8994's shape: the model's verdict names none, the body names one.
    const body = "## Problem\n\n#13 is related.\n\nBlocked by: #12\n\n## Depends on\n- #14\n\n<!-- work-items:born-triaged -->\n";

    test("get an edge before admission when the verdict's line names none", async () => {
      const order = [];
      const fake = fakeGitHub({ issue: { body }, comments: [laneComment()], blockers });
      const github = async (method, path, payload) => {
        if (method === "POST" && path.endsWith("/dependencies/blocked_by")) {
          order.push(`edge ${payload.issue_id}`);
        }
        return fake.github(method, path, payload);
      };
      const result = await run({
        env: ENV,
        github,
        dimensionsConfig: DIMS,
        fieldSetters: noSetters,
        admitIssue: async () => {
          order.push("admit");
          return { outcome: "waiting", reasons: [] };
        },
        log: () => {},
      });
      assert.deepEqual(order, ["edge 9012", "admit"]);
      assert.ok(result.summary.includes("- Blocked by: #12 written; #14 skipped (not open)"), result.summary);
    });

    test("join the verdict's, each number once", async () => {
      const fake = fakeGitHub({
        issue: { body: "Blocked by: #12, #13" },
        comments: [laneComment(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", "Blocked by: #12"] }))],
        blockers,
      });
      await go(fake);
      assert.deepEqual(edgePosts(fake.calls), [9012, 9013]);
    });

    test("get an edge on an escalated verdict, which admits nothing", async () => {
      const fake = fakeGitHub({ issue: { body }, comments: [laneComment(ESCALATED_BODY)], blockers });
      const result = await go(fake);
      assert.equal(result.outcome, "needs-decision");
      assert.deepEqual(edgePosts(fake.calls), [9012]);
    });

    test("get no edge on an untrusted-provenance verdict", async () => {
      const fake = fakeGitHub({
        issue: { body },
        comments: [laneComment(laneBody({ cls: "work-class: untrusted-provenance" }))],
        blockers,
      });
      await go(fake);
      assert.deepEqual(edgePosts(fake.calls), []);
    });

    test("past the cap, a warning names how many got no edge", async () => {
      const lines = [];
      const many = Array.from({ length: 12 }, (_, index) => `#${index + 100}`).join(", ");
      const fake = fakeGitHub({ issue: { body: `Blocked by: ${many}` }, comments: [laneComment()] });
      await run({ env: ENV, github: fake.github, dimensionsConfig: DIMS, fieldSetters: noSetters, log: (line) => lines.push(line) });
      assert.ok(lines.some((line) => line.startsWith("::warning") && line.includes("names 2 blocker(s) past the first 10")), lines.join("\n"));
      assert.equal(fake.calls.filter(({ method, path }) => method === "GET" && /^\/repos\/o\/r\/issues\/1[0-9]{2}$/.test(path)).length, 10);
    });
  });

  for (const [status, labels, own] of [
    [403, [], []],
    [429, [], []],
    [500, [], []],
    [500, [{ name: READY }], [{ id: 51, body: `${VERDICT_MARKER}\nold`, user: { id: LANES_APP, type: "Bot" } }]],
  ]) {
    test(`a ${status} on an edge write misses the edge: the other labels land, but not ${READY}, and no admission runs${labels.length ? " (it was already ready)" : ""}`, async () => {
      const fake = fakeGitHub({
        issue: { labels },
        comments: [
          laneComment(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", "Blocked by: #12"] })),
          ...own,
        ],
        blockers: { 12: { id: 9012, number: 12, state: "open", repository_url: "https://api.github.com/repos/o/r" } },
      });
      const github = async (method, path, body) => {
        if (method === "POST" && path.endsWith("/dependencies/blocked_by")) {
          throw new GitHubError(status, "POST");
        }
        return fake.github(method, path, body);
      };
      let admitted = false;
      const result = await run({
        env: ENV,
        github,
        dimensionsConfig: DIMS,
        fieldSetters: noSetters,
        admitIssue: async () => {
          admitted = true;
          return { outcome: "admitted", reasons: [] };
        },
        log: () => {},
      });
      assert.deepEqual(result.missed, [{ number: 12, status }]);
      assert.ok(!admitted, "admission reads blockers from native edges only, so it waits");
      const added = fake.calls.filter(({ method, path }) => method === "POST" && path.endsWith("/labels")).flatMap(({ body }) => body.labels);
      assert.ok(added.includes("work-class: scoped"), added.join(", "));
      assert.ok(!added.includes(READY), added.join(", "));
      assert.ok(fake.calls.some(({ method, path }) => method === "DELETE" && path.endsWith(`/labels/${encodeURIComponent(READY)}`)));
      assert.ok(result.summary.includes(`- Blocked by: #12 not written (GitHub answered ${status})`), result.summary);
      assert.match(result.summary, /- Status: none: admission waits for intake to run again, since a blocked-by edge is missing/);
      const said = fake.calls.find(({ method, path }) => (method === "POST" && path.endsWith("/comments")) || (method === "PATCH" && path.endsWith("/comments/51")));
      assert.ok(said?.body.body.startsWith(`${VERDICT_MARKER}\n`), said?.body.body);
      assert.ok(!said.body.body.includes(`is at \`${READY}\``), said.body.body);
      assert.match(said.body.body, /blocked-by edge is missing/);
    });
  }

  test("a missed edge is an error that fails the job on a 403, else a warning", () => {
    assert.equal(missedAnnotation([]), null);
    assert.equal(missedAnnotation(undefined), null, "a skipped or stopped run carries no missed list");
    assert.deepEqual(missedAnnotation([{ number: 12, status: 502 }]), {
      fail: false,
      line: "::warning title=apply-verdict::blocked-by edges not written: #12 not written (GitHub answered 502); the verdict's labels are written without status: ready, and admission waits until the hourly triage sweep runs intake again, which writes them",
    });
    const forbidden = missedAnnotation([
      { number: 12, status: 502 },
      { number: 13, status: 403 },
    ]);
    assert.equal(forbidden.fail, true);
    assert.match(forbidden.line, /^::error title=apply-verdict::blocked-by edges not written: #12 not written \(GitHub answered 502\); #13 not written \(GitHub answered 403\);/);
  });

  for (const status of [403, 429]) {
    test(`a ${status} on an escalated verdict's edge warns without failing the job and claims no held-back ${READY}`, async () => {
      const fake = fakeGitHub({
        issue: { body: "Blocked by: #12" },
        comments: [laneComment(ESCALATED_BODY)],
        blockers: { 12: { id: 9012, number: 12, state: "open", repository_url: "https://api.github.com/repos/o/r" } },
      });
      const github = async (method, path, body) => {
        if (method === "POST" && path.endsWith("/dependencies/blocked_by")) {
          throw new GitHubError(status, "POST");
        }
        return fake.github(method, path, body);
      };
      const result = await run({ env: ENV, github, dimensionsConfig: DIMS, fieldSetters: noSetters, log: () => {} });
      assert.equal(result.outcome, "needs-decision");
      assert.deepEqual(result.missed, [{ number: 12, status }]);
      const annotation = missedAnnotation(result.missed, result.undeleted, result.plan.ready);
      assert.equal(annotation.fail, false);
      assert.ok(annotation.line.startsWith("::warning title=apply-verdict::blocked-by edges not written on a verdict that is not ready: #12 not written"), annotation.line);
      assert.ok(!annotation.line.includes(`without ${READY}`) && !annotation.line.includes("admission waits"), annotation.line);
      assert.equal(missedAnnotation(result.missed, result.undeleted, true).fail, status === 403, "a ready verdict keeps its behaviour");
    });
  }

  test("an edge the run wrote and could not delete is named, and fails the job on a 403", () => {
    const warned = missedAnnotation([{ number: 13, status: 429 }], [{ number: 12, status: 500 }]);
    assert.equal(warned.fail, false);
    assert.match(warned.line, /#12 written and not deleted \(GitHub answered 500\)/);
    assert.equal(missedAnnotation([{ number: 13, status: 429 }], [{ number: 12, status: 403 }]).fail, true);
  });

  test("two blockers, the first edge written and the second missed: the first is deleted, and no admission runs", async () => {
    const fake = fakeGitHub({
      comments: [laneComment(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", "Blocked by: #12, #13"] }))],
      blockers: {
        12: { id: 9012, number: 12, state: "open", repository_url: "https://api.github.com/repos/o/r" },
        13: { id: 9013, number: 13, state: "open", repository_url: "https://api.github.com/repos/o/r" },
      },
    });
    const github = async (method, path, body) => {
      if (method === "POST" && path.endsWith("/dependencies/blocked_by") && body.issue_id === 9013) {
        throw new GitHubError(502, "POST");
      }
      if (method === "DELETE" && path.includes("/dependencies/blocked_by/")) {
        fake.calls.push({ method, path, body });
        return null;
      }
      return fake.github(method, path, body);
    };
    let admitted = false;
    const result = await run({
      env: ENV,
      github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue: async () => {
        admitted = true;
        return { outcome: "admitted", reasons: [] };
      },
      log: () => {},
    });
    assert.ok(!admitted);
    assert.ok(fake.calls.some(({ method, path }) => method === "DELETE" && path === "/repos/o/r/issues/7/dependencies/blocked_by/9012"));
    assert.deepEqual(result.undeleted, []);
    assert.ok(result.summary.includes("- Blocked by: #12 written, then deleted, since an edge missed; #13 not written (GitHub answered 502)"), result.summary);
  });

  test("an escalated verdict writes no edge", async () => {
    const fake = fakeGitHub({ comments: [laneComment(`${ESCALATED_BODY}\nBlocked by: #12`)] });
    await go(fake);
    assert.ok(!fake.calls.some(({ path }) => path.includes("dependencies")));
  });
});
