import assert from "node:assert/strict";
import { OUTSIDE_ACTOR_LABEL } from "../pr-merge/merge-holds.mjs";
import { STATUS_CONFIG, withFields } from "../../actions/resolve-config/read-status.fixtures.mjs";
import { statusLabels, statusReader } from "../../actions/resolve-config/read-status.mjs";
import { admissionSettled } from "./admit.mjs";
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { parseReason } from "../lib/stop-reason.mjs";
import {
  checkActors,
  checkRun,
  closing,
  earlierFlags,
  finish,
  flagsAfterDecision,
  FORBIDDEN_EDGE,
  isFault,
  LANES_APP_LOGIN,
  MARKER,
  missedAnnotation,
  NEEDS_DECISION,
  parseVerdict,
  planWrites,
  raisedAt,
  raisedLine,
  READY,
  run,
  UNRECORDED,
  VERDICT_MARKER,
} from "./apply-verdict.mjs";

const TRUSTED = fileURLToPath(new URL("../work-unblock/fixtures/trusted-actors.json", import.meta.url));
const HUMAN = 153232337;
const LANES_APP = 337595936;
// The labels a repository may still hold from before work classes retired.
const CLASSES = ["work-class: scoped", "work-class: structural", "work-class: mechanical", "provenance: untrusted"];
// The reusable's wording around a proposed class.
const OLD_BASIS = "Basis: automated intake triage; a maintainer confirms or changes it.";
const OLD_FOOTER = "<sub>Automated triage. A maintainer reviews it.</sub>";
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
const UNTRUSTED_BODY = laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: untrusted"] });
const ESCALATED_BODY = `${MARKER}\nProposed work class: none\n\nThanks for the report. Automated triage handed this issue to a maintainer.\n\n${OLD_FOOTER}`;

describe("parseVerdict", () => {
  test("reads the three dimensions and no flags, and carries no work class", () => {
    const verdict = parseVerdict(laneBody(), DIMS);
    assert.deepEqual(verdict, {
      escalated: false,
      untrusted: false,
      cost: false,
      dimensions: { size: "small", complexity: "low", uncertainty: "known" },
      flags: [],
      blockedBy: [],
      blockedByProblem: null,
      problems: [],
    });
  });

  test("reads the Blocked by line, ignoring a quoted one", () => {
    const lines = ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none"];
    assert.deepEqual(parseVerdict(laneBody({ lines: [...lines, "Blocked by: #12, #13"] }), DIMS).blockedBy, [12, 13]);
    assert.deepEqual(parseVerdict(laneBody({ lines: [...lines, "> Blocked by: #12"] }), DIMS).blockedBy, []);
  });

  test("an unreadable Blocked by line names no blocker and holds nothing", () => {
    const verdict = parseVerdict(
      laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", "Blocked by: 12"] }),
      DIMS,
    );
    assert.deepEqual(verdict.blockedBy, []);
    assert.match(verdict.blockedByProblem, /not none or a list of #<number>/);
    assert.deepEqual(verdict.problems, []);
  });

  test("model text quoted in a problem keeps no mention, backtick or markup", () => {
    const verdict = parseVerdict(
      laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: @owner `x` <b>"] }),
      DIMS,
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
    );
    assert.equal(verdict.dimensions, null);
    assert.match(verdict.problems.join(), /more than one `Size:`/);
  });

  test("an option the config does not map writes no fields", () => {
    const verdict = parseVerdict(
      laneBody({
        lines: ["Size: Huge", "Complexity: Low", "Uncertainty: Known", "Flags: none"],
      }),
      DIMS,
    );
    assert.equal(verdict.dimensions, null);
    assert.match(verdict.problems.join(), /`Size: Huge` is not one of small, medium, large/);
  });

  test("reads an option name in any case", () => {
    const verdict = parseVerdict(
      laneBody({
        lines: ["Size: small", "Complexity: HIGH", "Uncertainty: Knowable", "Flags: none"],
      }),
      DIMS,
    );
    assert.deepEqual(verdict.dimensions, { size: "small", complexity: "high", uncertainty: "knowable" });
    assert.deepEqual(verdict.problems, []);
  });

  for (const flags of ["Flags: intent, intent", "Flags: urgent", "Flags: none, cost"]) {
    test(`${flags} is unreadable`, () => {
      assert.equal(
        parseVerdict(
          laneBody({
            lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", flags],
          }),
          DIMS,
        ).flags,
        null,
      );
    });
  }

  test("an escalated run reads as escalated", () => {
    const verdict = parseVerdict(ESCALATED_BODY, DIMS);
    assert.equal(verdict.escalated, true);
  });
});

describe("planWrites", () => {
  const plan = (body, { labels = [], fields = {}, holdSetters = {}, earlierFlags = [], triageLabels = [] } = {}) =>
    planWrites(parseVerdict(body, DIMS), {
      labels,
      fields,
      dimensionsConfig: DIMS,
      appId: LANES_APP,
      humans,
      holdSetters,
      earlierFlags,
      triageLabels,
    });

  test("a clean verdict adds status: ready, never its proposed class, and writes the three fields", () => {
    const result = plan(laneBody());
    assert.equal(result.ready, true);
    assert.deepEqual(result.add, [READY]);
    assert.deepEqual(result.remove, []);
    assert.deepEqual(
      result.fieldWrites.map(({ fieldId, optionId, name }) => [fieldId, optionId, name]),
      [
        [15462270, 27053568, "small"],
        [48625720, 85127651, "low"],
        [48625721, 85127654, "known"],
      ],
    );
  });

  // Admission criteria 1 (intent), 5 (very-high security) and 6 (cost) rest on these.
  for (const flag of ["intent", "security", "cost"]) {
    test(`a ${flag} flag sends it to needs-decision but still writes the fields`, () => {
      const result = plan(
        laneBody({
          lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", `Flags: ${flag}`],
        }),
      );
      assert.equal(result.ready, false);
      assert.deepEqual(result.add, [NEEDS_DECISION]);
      assert.equal(result.fieldWrites.length, 3);
    });
  }

  test("an escalated run adds only needs-decision and takes status: ready off", () => {
    const result = plan(ESCALATED_BODY, { labels: [READY, "needs-human"] });
    assert.deepEqual(result.add, ["needs-owner-decision"]);
    assert.deepEqual(result.remove, [READY]);
    assert.deepEqual(result.fieldWrites, []);
  });

  // The field-first names drop a queue label the Work status field hides, so
  // the issue's own labels decide which stale status labels come off.
  test("a held verdict removes stale status: ready and status: confirmed labels the field hides", () => {
    const verdict = parseVerdict(ESCALATED_BODY, DIMS);
    const shown = ["needs-human", "needs-triage"];
    const own = ["needs-human", READY, "status: confirmed"];
    const base = { fields: {}, dimensionsConfig: DIMS, appId: LANES_APP, humans };
    assert.deepEqual(planWrites(verdict, { ...base, labels: shown, rawLabels: own }).remove, [READY, "needs-triage", "status: confirmed"]);
    assert.deepEqual(planWrites(verdict, { ...base, labels: shown }).remove, ["needs-triage"], "without its own labels only the shown floor label goes");
  });

  for (const hold of ["needs-human", "needs-reporter-info", "needs-owner-decision", NEEDS_DECISION]) {
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
        assert.deepEqual(result.add, [READY]);
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
  for (const hold of ["needs-reporter-info", NEEDS_DECISION]) {
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

  // Owner decision on #9799's review: a clean verdict never lifts needs-human,
  // whoever set it, except a same-run, no-flag needs-human on an otherwise
  // ready plan (the owner's standing direction: a capability limit routes to
  // host-run, never to a person).
  test("needs-human the lanes App set stays on a clean verdict", () => {
    const result = plan(laneBody(), { labels: ["needs-human"], holdSetters: { "needs-human": LANES_APP } });
    assert.equal(result.ready, false);
    assert.deepEqual(result.remove, []);
    assert.ok(!result.add.includes(READY));
    assert.ok(result.reasons.includes("held by needs-human"), result.reasons.join("; "));
  });

  // Run 41064812826 (#9953): the triage run applied needs-human for a host-run
  // step. A capability limit is admission's to route (host-run), never a
  // person's: needs-human this run's triage applied holds only beside a flag.
  test("needs-human this run's triage applied with no flag is refused and the verdict reaches ready", () => {
    const result = plan(laneBody(), { labels: ["needs-human"], holdSetters: { "needs-human": ACTIONS_BOT }, triageLabels: ["needs-human"] });
    assert.equal(result.ready, true);
    assert.deepEqual(result.add, [READY]);
    assert.deepEqual(result.remove, ["needs-human"]);
    assert.deepEqual(result.refused, ["needs-human"]);
    assert.deepEqual(result.reasons, []);
  });

  // An earlier verdict's flag still needs a person: refusing the only hold
  // would drop it, so the hold stays and the flag is carried.
  for (const flag of ["intent", "security"]) {
    test(`needs-human this run's triage applied after an earlier ${flag} flag stays and carries the flag`, () => {
      const result = plan(laneBody(), { labels: ["needs-human"], holdSetters: { "needs-human": ACTIONS_BOT }, triageLabels: ["needs-human"], earlierFlags: [flag] });
      assert.equal(result.ready, false);
      assert.deepEqual(result.refused, []);
      assert.ok(!result.remove.includes("needs-human"));
      assert.ok(result.reasons.includes("held by needs-human"), result.reasons.join("; "));
      assert.ok(result.reasons.includes(`flagged: ${flag} (an earlier verdict)`), result.reasons.join("; "));
    });
  }

  test("needs-human this run's triage applied with no readable earlier verdict is still refused", () => {
    const result = plan(laneBody(), { labels: ["needs-human"], holdSetters: { "needs-human": ACTIONS_BOT }, triageLabels: ["needs-human"], earlierFlags: null });
    assert.equal(result.ready, true);
    assert.deepEqual(result.refused, ["needs-human"]);
  });

  for (const [name, lines] of [
    ["no Flags line", ["Size: Small", "Complexity: Low", "Uncertainty: Known"]],
    ["two Flags lines", ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", "Flags: none"]],
  ]) {
    test(`needs-human this run's triage applied with ${name} holds`, () => {
      const result = plan(laneBody({ lines }), { labels: ["needs-human"], triageLabels: ["needs-human"] });
      assert.equal(result.ready, false);
      assert.deepEqual(result.remove, []);
      assert.deepEqual(result.refused, []);
      assert.ok(result.reasons.includes("held by needs-human"), result.reasons.join("; "));
    });
  }

  // Only an otherwise ready plan reaches admission, which routes the capability
  // limit; a plan held for another reason keeps needs-human and says so.
  test("needs-human this run's triage applied with no flag holds when another hold keeps the plan from ready", () => {
    const result = plan(laneBody(), { labels: ["needs-human", "needs-reporter-info"], triageLabels: ["needs-human"] });
    assert.equal(result.ready, false);
    assert.deepEqual(result.remove, []);
    assert.deepEqual(result.refused, []);
    assert.ok(result.reasons.includes("held by needs-human"), result.reasons.join("; "));
  });

  for (const label of ["security: outside-actor", "provenance: untrusted"]) {
    test(`needs-human this run's triage applied with no flag holds beside ${label}`, () => {
      const result = plan(laneBody(), { labels: ["needs-human", label], triageLabels: ["needs-human"] });
      assert.equal(result.ready, false);
      assert.deepEqual(result.remove, []);
      assert.deepEqual(result.refused, []);
      assert.ok(result.reasons.includes("held by needs-human"), result.reasons.join("; "));
    });
  }

  for (const flag of ["intent", "security", "cost"]) {
    test(`needs-human this run's triage applied beside a ${flag} flag holds`, () => {
      const result = plan(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", `Flags: ${flag}`] }), {
        labels: ["needs-human"],
        triageLabels: ["needs-human"],
      });
      assert.equal(result.ready, false);
      assert.deepEqual(result.remove, []);
      assert.deepEqual(result.refused, []);
      assert.ok(result.reasons.includes("held by needs-human"), result.reasons.join("; "));
    });
  }

  // A kept trust control (loop-lane "When work stops for the owner"): text
  // addressed to the triage run escalates, and the needs-human this run's
  // triage applied for it stays, though the escalated verdict carries no flag.
  test("needs-human on an escalated run holds even when this run's triage applied it", () => {
    const result = plan(ESCALATED_BODY, { labels: ["needs-human"], holdSetters: { "needs-human": ACTIONS_BOT }, triageLabels: ["needs-human"] });
    assert.equal(result.ready, false);
    assert.deepEqual(result.remove, []);
    assert.deepEqual(result.refused, []);
    assert.ok(result.reasons.includes("the triage run escalated"), result.reasons.join("; "));
    assert.ok(result.reasons.includes("held by needs-human"), result.reasons.join("; "));
  });

  // The same hold when the escalated verdict also reads Flags: none with every
  // dimension: only the escalation guard keeps this needs-human from being refused.
  test("needs-human on an escalated run with Flags: none and readable dimensions is not refused", () => {
    const body = `${MARKER}\nProposed work class: none\n\nThanks for the report. Automated triage handed this issue to a maintainer.\n\nSize: Small\nComplexity: Low\nUncertainty: Known\nFlags: none\n\n${OLD_FOOTER}`;
    const verdict = parseVerdict(body, DIMS);
    assert.equal(verdict.escalated, true);
    assert.deepEqual(verdict.flags, []);
    assert.notEqual(verdict.dimensions, null);
    const result = plan(body, { labels: ["needs-human"], holdSetters: { "needs-human": ACTIONS_BOT }, triageLabels: ["needs-human"] });
    assert.deepEqual(result.refused, []);
    assert.ok(!result.remove.includes("needs-human"), result.remove.join(", "));
  });

  // Run 41064812826 (#9953) also applied needs-owner-decision with no flag.
  // Owner's standing direction §2: only a flag (intent, security, cost) stops
  // for a person, so this run's flagless needs-decision gives way like needs-human.
  test("needs-owner-decision this run's triage applied with no flag is refused on an otherwise ready plan", () => {
    const result = plan(laneBody(), { labels: [NEEDS_DECISION], triageLabels: [NEEDS_DECISION] });
    assert.equal(result.ready, true);
    assert.deepEqual(result.add, [READY]);
    assert.deepEqual(result.remove, [NEEDS_DECISION]);
    assert.deepEqual(result.refused, [NEEDS_DECISION]);
  });

  test("needs-human and needs-owner-decision this run's triage applied with no flag are both refused", () => {
    const result = plan(laneBody(), { labels: ["needs-human", NEEDS_DECISION], triageLabels: ["needs-human", NEEDS_DECISION] });
    assert.equal(result.ready, true);
    assert.deepEqual(result.refused, ["needs-human", NEEDS_DECISION]);
    assert.deepEqual(result.remove, ["needs-human", NEEDS_DECISION]);
  });

  for (const [name, options] of [
    ["beside an intent flag", { body: laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: intent"] }) }],
    ["with an unreadable Flags line", { body: laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known"] }) }],
    ["beside security: outside-actor", { labels: ["security: outside-actor"] }],
    ["beside provenance: untrusted", { labels: ["provenance: untrusted"] }],
    ["beside needs-reporter-info", { labels: ["needs-reporter-info"] }],
  ]) {
    test(`needs-owner-decision this run's triage applied holds ${name}`, () => {
      const result = plan(options.body ?? laneBody(), { labels: [NEEDS_DECISION, ...(options.labels ?? [])], triageLabels: [NEEDS_DECISION] });
      assert.equal(result.ready, false);
      assert.deepEqual(result.refused, []);
      assert.ok(!result.remove.includes(NEEDS_DECISION));
    });
  }

  // The COST rule pairs a Cost line with the cost flag; a Cost line beside
  // `Flags: none` still names a charge an owner decides.
  test("a needs-human this run's triage applied stays when the comment carries a Cost line, even with Flags: none", () => {
    const body = laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", "Cost: a paid plan upgrade; no owner decision"] });
    const result = plan(body, { labels: ["needs-human"], triageLabels: ["needs-human"] });
    assert.equal(result.ready, false);
    assert.deepEqual(result.refused, []);
    assert.ok(!result.remove.includes("needs-human"));
  });

  // The COST rule writes a charge a person's recorded decision covers as
  // `Cost decided: `, which needs no owner.
  test("a Cost decided line beside Flags: none still refuses a needs-human this run's triage applied", () => {
    const body = laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", "Cost decided: a paid plan upgrade; the owner's recorded decision"] });
    const result = plan(body, { labels: ["needs-human"], triageLabels: ["needs-human"] });
    assert.deepEqual(result.refused, ["needs-human"]);
    assert.equal(result.ready, true);
  });

  test("a Cost line beside a Cost decided line keeps the needs-human", () => {
    const body = laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", "Cost decided: a plan upgrade; decided", "Cost: a new paid service; no owner decision"] });
    const result = plan(body, { labels: ["needs-human"], triageLabels: ["needs-human"] });
    assert.deepEqual(result.refused, []);
    assert.equal(result.ready, false);
  });

  // The strict Cost parse: a canonical `Cost: ` line holds, a no-charge or
  // `Cost decided: ` one or quoted issue text refuses, and any other cost label
  // is a problem that holds unless it reads no charge.
  const COST_CASES = [
    ["Cost: x", "hold"],
    ["**Cost:** x", "hold"],
    ["- Cost: x", "hold"],
    ["1. Cost: x", "hold"],
    ["COST: x", "hold"],
    [" Cost: a paid plan upgrade", "hold"],
    ["Cost: none", "refuse"],
    ["- **Cost:** none", "refuse"],
    ["- **Cost:** none (prepaid keys)", "hold"],
    ["Cost: none (except the Pro plan upgrade the owner must approve)", "hold"],
    ["## Cost: paid plan", "problem"],
    ["| Cost: | paid plan |", "problem"],
    ["- [ ] Cost: paid plan", "problem"],
    ["- - Cost: paid plan", "problem"],
    ["\u2022 Cost: paid plan", "problem"],
    ["\u200bCost: paid plan", "problem"],
    ["Cost: n/a", "refuse"],
    ["Cost: No charge", "refuse"],
    ["Cost: no cost", "refuse"],
    ["Cost decided: x", "refuse"],
    ["**Cost decided:** x", "refuse"],
    ["> Cost: q", "refuse"],
    ["- > Cost: q", "refuse"],
    ["  > COST: quoted", "refuse"],
    ["Costing: x", "refuse"],
    ["Cost/benefit: x", "refuse"],
    ["Estimated cost: x", "refuse"],
    ["**Cost**: x", "problem"],
    ["*Cost*: x", "problem"],
    ["_Cost:_ x", "problem"],
    ["Costs: x", "problem"],
    ["Cost \u2014 x", "problem"],
    ["Cost \u2013 x", "problem"],
    ["Cost - x", "problem"],
    ["Cost (estimate): x", "problem"],
    ["Cost:x", "problem"],
  ];
  for (const [line, outcome] of COST_CASES) {
    test(`a ${JSON.stringify(line)} line ${outcome === "refuse" ? "refuses" : "keeps"} a needs-human this run's triage applied (${outcome})`, () => {
      const body = laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", line] });
      const verdict = parseVerdict(body, DIMS);
      const result = plan(body, { labels: ["needs-human"], triageLabels: ["needs-human"] });
      assert.equal(verdict.cost, outcome === "hold");
      assert.equal(verdict.problems.includes("a Cost line is not in the `Cost: ` / `Cost decided: ` form"), outcome === "problem");
      assert.deepEqual(result.refused, outcome === "refuse" ? ["needs-human"] : []);
      assert.equal(result.ready, outcome === "refuse");
      assert.equal(result.remove.includes("needs-human"), outcome === "refuse");
    });
  }

  // On a verdict with no triage hold, a non-canonical cost line that names a
  // charge still stops it; a no-charge one or a `Cost-` compound does not.
  for (const [line, ready] of [
    ["Costs: none", true],
    ["Cost (est.): none", true],
    ["Cost-benefit: low", true],
    ["Cost-effective: yes", true],
    ["Costs: a paid Azure plan", false],
    ["Cost - minimal, one-line change", false],
    ["Cost (hours): small", false],
    ["Cost-estimate: a paid Azure plan", false],
    ["Cost-per-month: $40", false],
  ]) {
    test(`a ${JSON.stringify(line)} line ${ready ? "does not stop" : "stops"} a verdict with no hold`, () => {
      const result = plan(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", line] }), { labels: [] });
      assert.equal(result.ready, ready, result.reasons.join("; "));
    });
  }

  // Only a person lifts the outside-actor flag: a clean verdict neither removes it nor reaches ready.
  test("security: outside-actor the lanes App set stays on a clean verdict and holds", () => {
    const label = "security: outside-actor";
    const result = plan(laneBody(), { labels: [label], holdSetters: { [label]: LANES_APP } });
    assert.equal(result.ready, false);
    assert.deepEqual(result.remove, []);
    assert.ok(!result.add.includes(READY));
    assert.ok(result.reasons.includes(`held by ${label}`), result.reasons.join("; "));
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

  // Work classes are retired: a proposed class is never applied, and an old
  // class label on the issue is neither read nor taken off.
  for (const cls of ["none", "work-class: scoped", "work-class: structural", "work-class: anything-goes"]) {
    test(`a verdict proposing ${cls} adds no class label and reaches ready`, () => {
      const result = plan(laneBody({ cls }));
      assert.equal(result.ready, true);
      assert.deepEqual(result.add, [READY]);
      assert.deepEqual(result.remove, []);
    });
  }

  for (const [name, setter] of [
    ["the lanes App", LANES_APP],
    ["a listed human", HUMAN],
    ["an unlisted account", OUTSIDER],
    ["a null actor", null],
  ]) {
    test(`an old work-class label ${name} added is kept, gains no swap and does not hold`, () => {
      const result = plan(laneBody({ cls: "work-class: structural" }), {
        labels: ["work-class: mechanical"],
        holdSetters: { "work-class: mechanical": setter },
      });
      assert.equal(result.ready, true);
      assert.deepEqual(result.remove, []);
      assert.deepEqual(result.add, [READY]);
    });
  }

  test("provenance: untrusted is never taken off and holds the issue, even when the lanes App added it", () => {
    const hold = "provenance: untrusted";
    const result = plan(laneBody(), {
      labels: [hold],
      holdSetters: { [hold]: LANES_APP },
    });
    assert.equal(result.ready, false);
    assert.ok(result.reasons.includes("provenance: untrusted work needs a person"), result.reasons.join("; "));
    assert.deepEqual(result.remove, []);
    assert.deepEqual(result.add, [NEEDS_DECISION]);
  });

  for (const hold of ["provenance: untrusted"]) {
    test(`${hold} on the issue holds it whatever class the verdict proposes`, () => {
      const result = plan(laneBody(), { labels: [hold] });
      assert.equal(result.ready, false);
      assert.ok(result.reasons.includes("provenance: untrusted work needs a person"), result.reasons.join("; "));
      assert.deepEqual(result.remove, []);
    });
  }

  test("an untrusted-provenance verdict adds provenance: untrusted beside an old class label", () => {
    const result = plan(UNTRUSTED_BODY, {
      labels: ["work-class: mechanical"],
      holdSetters: { "work-class: mechanical": HUMAN },
    });
    assert.equal(result.ready, false);
    assert.deepEqual(result.remove, []);
    assert.deepEqual(result.add, ["provenance: untrusted", NEEDS_DECISION]);
  });

  test("Flags: untrusted writes provenance: untrusted, never the proposed class, and holds for security", () => {
    const verdict = parseVerdict(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: untrusted"] }), DIMS);
    assert.equal(verdict.untrusted, true);
    assert.deepEqual(verdict.flags, []);
    assert.deepEqual(verdict.problems, []);
    const result = planWrites(verdict, { labels: [], fields: {}, dimensionsConfig: DIMS, appId: LANES_APP, humans });
    assert.equal(result.ready, false);
    assert.equal(result.reason, "security");
    assert.ok(result.reasons.includes("provenance: untrusted work needs a person"), result.reasons.join("; "));
    assert.deepEqual(result.add, ["provenance: untrusted", NEEDS_DECISION]);
  });

  test("untrusted beside other flags keeps them as flags and still holds", () => {
    const verdict = parseVerdict(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: intent, untrusted"] }), DIMS);
    assert.equal(verdict.untrusted, true);
    assert.deepEqual(verdict.flags, ["intent"]);
  });

  test("an unreadable Flags line naming untrusted still marks the verdict untrusted", () => {
    const verdict = parseVerdict(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: untrusted, maybe"] }), DIMS);
    assert.equal(verdict.untrusted, true);
    assert.equal(verdict.flags, null);
    const result = planWrites(verdict, { labels: [], fields: {}, dimensionsConfig: DIMS, appId: LANES_APP, humans });
    assert.ok(result.add.includes("provenance: untrusted"), result.add.join(", "));
    assert.equal(result.ready, false);
  });

  test("two Flags lines, one naming untrusted, still write provenance: untrusted", () => {
    const verdict = parseVerdict(
      laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", "Flags: untrusted"] }),
      DIMS,
    );
    assert.equal(verdict.untrusted, true);
    assert.equal(verdict.flags, null);
    const result = planWrites(verdict, { labels: [], fields: {}, dimensionsConfig: DIMS, appId: LANES_APP, humans });
    assert.ok(result.add.includes("provenance: untrusted"), result.add.join(", "));
    assert.equal(result.ready, false);
  });

  test("a quoted Flags line naming untrusted marks nothing", () => {
    const verdict = parseVerdict(
      laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: none", "> Flags: untrusted"] }),
      DIMS,
    );
    assert.equal(verdict.untrusted, false);
    assert.deepEqual(verdict.flags, []);
  });

  test("an untrusted verdict does not add provenance: untrusted again when the issue carries it", () => {
    const result = plan(UNTRUSTED_BODY, { labels: ["provenance: untrusted"] });
    assert.equal(result.ready, false);
    assert.deepEqual(result.add, [NEEDS_DECISION]);
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

  test("a proposed class is no problem in the verdict", () => {
    assert.deepEqual(parseVerdict(laneBody({ cls: "work-class: anything-goes" }), DIMS).problems, []);
  });

  test("two old work classes on the issue are kept and do not hold it", () => {
    const result = plan(laneBody(), {
      labels: ["work-class: structural", "work-class: mechanical"],
    });
    assert.deepEqual(result.remove, []);
    assert.deepEqual(result.add, [READY]);
  });

  test("needs-triage the triage left does not keep a clean verdict from ready, and is taken off", () => {
    const result = plan(laneBody(), { labels: ["needs-triage"] });
    assert.equal(result.ready, true);
    assert.deepEqual(result.add, [READY]);
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
    assert.deepEqual(result.add, [READY]);
  });

  test("the proposed class already on the issue is left as it is", () => {
    const result = plan(laneBody(), { labels: ["work-class: scoped"] });
    assert.equal(result.ready, true);
    assert.deepEqual(result.add, [READY]);
    assert.deepEqual(result.remove, []);
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

describe("checkRun", () => {
  const env = {
    EVENT_NAME: "workflow_dispatch",
    ACTOR_ID: "41898282",
    TRIGGERING_ACTOR: "github-actions[bot]",
    RUN_ATTEMPT: "1",
    GITHUB_REPOSITORY: "o/r",
    ISSUE_NUMBER: "7",
  };
  const answering = (answer) => {
    const calls = [];
    const github = async (method, apiPath) => {
      calls.push(`${method} ${apiPath}`);
      if (answer instanceof Error) {
        throw answer;
      }
      return answer;
    };
    return { calls, github };
  };
  const byHuman = { user: { id: HUMAN } };
  const cases = [
    ["the issue is open", { state: "open", ...byHuman }, true],
    ["the issue closed while triage ran", { state: "closed", ...byHuman }, false],
    ["the number is a pull request", { state: "open", pull_request: {}, ...byHuman }, false],
    ["the author is github-actions[bot]", { state: "open", user: { id: ACTIONS_BOT } }, false],
    ["the author is an outsider", { state: "open", user: { id: OUTSIDER } }, false],
    ["the issue names no author", { state: "open" }, false],
    ["the read fails, so the write step's own read decides", new GitHubError(502, "GET"), true],
  ];
  for (const [name, answer, expected] of cases) {
    test(`${expected ? "proceeds" : "stops"} when ${name}`, async () => {
      const { calls, github } = answering(answer);
      assert.equal(await checkRun({ env, humans, logins, github, log: () => {} }), expected);
      assert.deepEqual(calls, ["GET /repos/o/r/issues/7"]);
    });
  }
  test("proceeds when the lanes App filed the issue", async () => {
    const { github } = answering({ state: "open", user: { id: 77 } });
    const withApp = new Map([...logins, [LANES_APP_LOGIN, 77]]);
    assert.equal(await checkRun({ env, humans, logins: withApp, github, log: () => {} }), true);
  });
  test("stops on the actors without reading the issue", async () => {
    const { calls, github } = answering({ state: "open" });
    assert.equal(await checkRun({ env: { ...env, EVENT_NAME: "issues" }, humans, logins, github, log: () => {} }), false);
    assert.deepEqual(calls, []);
  });
});

// A fake GitHub: the issue, its comments and field values, recording every call.
// A field-value write naming a value `refuse` matches is answered `refuseStatus`.
function fakeGitHub({ issue = {}, comments, fieldRows = [], answerRows, events = [], blockers = {}, refuse = () => false, refuseStatus = 422 } = {}) {
  const calls = [];
  const github = async (method, path, body, headers, options) => {
    calls.push({ method, path, body, ...(options ? { options } : {}) });
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
    // Work classes are retired, so no run reads the repository's labels.
    if (method === "GET" && path.startsWith("/repos/o/r/labels")) {
      throw new Error(`the repository's labels were read (${path})`);
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
      if (body.issue_field_values.some(({ value }) => refuse(value))) {
        throw new GitHubError(refuseStatus, path);
      }
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
    // select-trusted-text's last-editor read: every comment unedited.
    if (method === "POST" && path === "/graphql") {
      return { data: { nodes: (body?.variables?.ids ?? []).map((id) => ({ id, lastEditedAt: null })) } };
    }
    return null;
  };
  // write-status.mjs statusWriter's `set`, recorded among the calls in order.
  const setStatus = async (number, state, options) => {
    calls.push({ method: "STATUS", path: `#${number}`, body: state, fields: options?.fields });
  };
  return { github, calls, setStatus };
}
// The Work status writes among `calls`.
const states = (calls) => calls.filter(({ method }) => method === "STATUS").map(({ body }) => body);
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
    setStatus: fake.setStatus,
    statusConfig: STATUS_CONFIG,
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
  test("writes the fields and status: ready, no class, and leaves the lane comment as it is", async () => {
    const fake = fakeGitHub({ comments: [laneComment()] });
    const result = await go(fake);
    assert.equal(result.outcome, "ready");
    const done = writes(fake.calls);
    assert.deepEqual(
      done.map(({ method, path }) => `${method} ${path}`),
      ["POST /repos/o/r/issues/7/issue-field-values", "STATUS #7"],
    );
    assert.deepEqual(done[0].body.issue_field_values, [
      { field_id: 15462270, value: "small" },
      { field_id: 48625720, value: "low" },
      { field_id: 48625721, value: "known" },
    ]);
    assert.equal(done[1].body, "ready", "the Work status field takes the place of the status: ready label");
    assert.ok(!fake.calls.some(({ path }) => path.startsWith("/repos/o/r/labels")), "no repository label read");
  });

  for (const status of [400, 422]) {
    test(`field names GitHub refuses with ${status} are sent once more Title-cased`, async () => {
      const lowercase = (value) => value === value.toLowerCase();
      const fake = fakeGitHub({ comments: [laneComment()], refuse: lowercase, refuseStatus: status });
      assert.equal((await go(fake)).outcome, "ready");
      const posts = fake.calls.filter(({ method, path }) => method === "POST" && path.endsWith("/issue-field-values"));
      assert.deepEqual(
        posts.map(({ body }) => body.issue_field_values.map(({ value }) => value)),
        [
          ["small", "low", "known"],
          ["Small", "Low", "Known"],
        ],
      );
    });
  }

  test("a field write refused for another reason is not sent again", async () => {
    const fake = fakeGitHub({ comments: [laneComment()], refuse: () => true, refuseStatus: 403 });
    await assert.rejects(go(fake), /status 403/);
    assert.equal(fake.calls.filter(({ method, path }) => method === "POST" && path.endsWith("/issue-field-values")).length, 1);
  });

  test("a ready write a person's late hold answers held stops the run: no late label removal, no admission comment, no admission", async () => {
    const fake = fakeGitHub({ issue: { labels: [{ name: "needs-triage" }] }, comments: [laneComment()] });
    const admitted = [];
    const logged = [];
    const result = await run({
      env: ENV,
      github: fake.github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      setStatus: async (number, state, options) => (options?.keepHold ? { outcome: "held", state: "needs-human" } : fake.setStatus(number, state, options)),
      statusConfig: STATUS_CONFIG,
      admitIssue: async () => admitted.push("admit") && { outcome: "admitted", reasons: [] },
      log: (line) => logged.push(line),
    });
    assert.deepEqual(admitted, [], "admission never runs");
    assert.deepEqual(result.admission, { outcome: "held", reasons: ["a person's Work status needs-human holds it"], status: "needs-human" });
    assert.deepEqual(logged, ["apply-verdict: #7 left as is (a person's Work status needs-human holds it); no admission"]);
    assert.deepEqual(
      writes(fake.calls).map(({ method, path }) => `${method} ${path}`),
      ["POST /repos/o/r/issues/7/issue-field-values"],
      "only the field values; needs-triage stays and no comment is written",
    );
  });

  test("an issue holding only an old class label reads no events", async () => {
    const fake = fakeGitHub({ issue: { labels: [{ name: "work-class: mechanical" }] }, comments: [laneComment()] });
    assert.equal((await go(fake)).outcome, "ready");
    assert.ok(!fake.calls.some(({ path }) => path.startsWith("/repos/o/r/issues/7/events")));
    assert.ok(!writes(fake.calls).some(({ method }) => method === "DELETE"));
  });

  test("an escalated run writes only needs-decision and its reasons, and keeps the lane comment", async () => {
    const fake = fakeGitHub({ comments: [laneComment(ESCALATED_BODY)] });
    const result = await go(fake);
    assert.equal(result.outcome, "needs-decision");
    assert.deepEqual(
      writes(fake.calls).map(({ method, path }) => `${method} ${path}`),
      ["POST /repos/o/r/issues/7/comments", "STATUS #7"],
    );
    assert.equal(writes(fake.calls)[1].body, "needs-owner-decision");
  });

  // A manual dispatch skips intake-reenter, so a parked issue reaches a held
  // verdict still at status: confirmed; the field write replaces it.
  test("a held verdict replaces a parked status: confirmed with the field alone", async () => {
    const fake = fakeGitHub({ issue: { labels: [{ name: "status: confirmed" }] }, comments: [laneComment(ESCALATED_BODY)] });
    assert.equal((await go(fake)).outcome, "needs-decision");
    assert.deepEqual(
      writes(fake.calls).map(({ method, path, body }) => `${method} ${path}${method === "STATUS" ? ` ${body}` : ""}`),
      ["POST /repos/o/r/issues/7/comments", "STATUS #7 needs-owner-decision"],
      "the Work status write stands in for taking status: confirmed off",
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

  test("keeps an old class the lanes App added and replaces its own earlier field values given real-shaped ids", async () => {
    // GraphQL answers databaseId as a number, here passed as a string to
    // prove the type does not matter.
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
    assert.ok(!done.some(({ method }) => method === "DELETE"), "the old class stays");
    const post = done.find(({ path }) => path.endsWith("/issue-field-values"));
    assert.deepEqual(post.body.issue_field_values[0], {
      field_id: 15462270,
      value: "small",
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
    // The kept class does not hold the issue.
    assert.equal((await go(fake)).outcome, "ready");
    assert.ok(!writes(fake.calls).some(({ method }) => method === "DELETE"));
  });

  test("a verdict that no longer holds moves the Work status off ready and leaves status: ready unwritten", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: READY }] },
      comments: [laneComment(ESCALATED_BODY)],
    });
    await go(fake);
    assert.deepEqual(
      writes(fake.calls).filter(({ method }) => method === "STATUS" || method === "DELETE").map(({ method, path, body }) => `${method} ${method === "STATUS" ? body : path}`),
      ["STATUS needs-owner-decision"],
      "the field write alone moves the issue off ready",
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
    // Setting a field to an option leaves the same state when sent twice, so
    // a 5xx on it is resent once (run 41814429466 failed on one 500).
    assert.deepEqual(post.options, { resendOnce: true });
  });

  test("a field-values answer that is not a list stops the run before any write", async () => {
    for (const answer of [{ message: "Not Found" }, null, "oops"]) {
      const fake = fakeGitHub({ comments: [laneComment()], fieldRows: answer });
      await assert.rejects(() => go(fake), /field values answered .*, not a list/, JSON.stringify(answer));
      assert.deepEqual(writes(fake.calls), [], JSON.stringify(answer));
    }
  });

  test("an empty field-values list reads as no fields set", async () => {
    const fake = fakeGitHub({ comments: [laneComment()], fieldRows: [] });
    assert.equal((await go(fake)).outcome, "ready");
    assert.ok(writes(fake.calls).some(({ path }) => path.endsWith("/issue-field-values")));
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
    assert.ok(!Object.hasOwn(seen[0], "workClass"), "admission gets no work class");
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

  test("admission gets the Work status the run wrote or found in place, and none when the write answered nothing", async () => {
    for (const [answer, wrote] of [
      [{ outcome: "written", state: "ready", option: 86380003 }, "ready"],
      [{ outcome: "unchanged", state: "ready" }, "ready"],
      [undefined, undefined],
    ]) {
      const fake = fakeGitHub({ comments: [laneComment()] });
      const seen = [];
      await run({
        env: ENV,
        github: fake.github,
        dimensionsConfig: DIMS,
        fieldSetters: noSetters,
        setStatus: async (...args) => {
          await fake.setStatus(...args);
          return answer;
        },
        statusConfig: STATUS_CONFIG,
        admitIssue: async (verdict, options) => {
          seen.push(options);
          return { outcome: "admitted", reasons: [] };
        },
        log: () => {},
      });
      assert.deepEqual(states(fake.calls), ["ready"], JSON.stringify(answer));
      assert.deepEqual(seen, [{ wrote }], JSON.stringify(answer));
    }
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

  test("admission reads the lane comment's write time, and the run edits no comment", async () => {
    const seen = [];
    const fake = fakeGitHub({ comments: [laneComment()] });
    const github = async (method, path, body) => {
      if (method === "PATCH") {
        throw new GitHubError(403, "PATCH");
      }
      return fake.github(method, path, body);
    };
    const result = await run({
      env: ENV,
      github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue: async (verdict) => {
        seen.push(verdict);
        return { outcome: "admitted", reasons: [] };
      },
      log: () => {},
    });
    assert.equal(result.outcome, "ready");
    assert.equal(seen.length, 1);
    // Admission refuses a body edited after the lane comment it read.
    assert.equal(seen[0].writtenAt, laneComment().updated_at);
  });

  test("an admission error still reports the verdict and edits no lane comment", async () => {
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
    assert.ok(!writes(fake.calls).some(({ method }) => method === "PATCH"));
    assert.match(result.summary, /- Admission: error \(admission-rules\.json/);
  });

  test("a GitHub fault in admission holds green with a notice; a rules error still fails", async () => {
    const admitted = async (error) =>
      run({
        env: ENV,
        github: fakeGitHub({ comments: [laneComment()] }).github,
        dimensionsConfig: DIMS,
        fieldSetters: noSetters,
        admitIssue: async () => {
          throw error;
        },
        log: () => {},
      });
    const fault = await admitted(new GitHubError(503, "GET /repos/o/r/issues/1/timeline"));
    assert.deepEqual(closing({ result: fault }), {
      lines: ["::notice title=apply-verdict::held: admission failed: GET /repos/o/r/issues/1/timeline failed with status 503"],
      code: 0,
      held: true,
    });
    const rules = await admitted(new Error("admission-rules.json: `types` must be a list of strings"));
    assert.deepEqual(closing({ result: rules }), {
      lines: ["::error title=apply-verdict::admission failed: admission-rules.json: `types` must be a list of strings"],
      code: 1,
      held: false,
    });
  });

  test("a thrown GitHub or network fault holds green; any other throw fails", () => {
    assert.deepEqual(closing({ error: new GitHubError(500, "GET /repos/o/r/issues/1") }), {
      lines: ["::notice title=apply-verdict::held: GET /repos/o/r/issues/1 failed with status 500"],
      code: 0,
      held: true,
    });
    assert.equal(closing({ error: new TypeError("fetch failed") }).code, 0);
    assert.deepEqual(closing({ error: new Error("models.issue-dimensions maps no option 7") }), {
      lines: ["::error title=apply-verdict::models.issue-dimensions maps no option 7"],
      code: 1,
      held: false,
    });
  });

  test("only a 5xx, a 429, a rate-guard stop or no answer is a fault; another 4xx stays red", () => {
    for (const status of [500, 502, 503, 429]) {
      assert.equal(isFault(new GitHubError(status, "POST labels")), true, `status ${status}`);
    }
    for (const status of [403, 404, 422]) {
      assert.equal(isFault(new GitHubError(status, "POST labels")), false, `status ${status}`);
      assert.equal(closing({ error: new GitHubError(status, "POST labels") }).code, 1, `status ${status}`);
    }
    const stop = Object.assign(new Error("GET /x refused until reset"), { name: "RateLimitStop" });
    assert.equal(isFault(stop), true);
  });

  test("a hold writes the held output refine-select reads; a failure writes none", () => {
    const dir = tempDir("apply-verdict-held-");
    try {
      const output = path.join(dir, "output");
      for (const [error, held] of [[new GitHubError(503, "GET /x"), true], [new Error("bad config"), false]]) {
        writeFileSync(output, "");
        const lines = [];
        const code = finish(closing({ error }), { outputPath: output, log: (line) => lines.push(line) });
        assert.equal(code, held ? 0 : 1);
        assert.equal(lines.length, 1);
        assert.equal(/^held<<ghadelimiter_[0-9a-f-]+\ntrue\n/.test(readFileSync(output, "utf8")), held, error.message);
      }
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
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

  test("a needs-human this run's triage applied with no flag comes off before admission, which then routes the host work", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [{ event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: "2026-10-22T12:04:00Z" }],
    });
    const result = await run({
      env: ENV,
      github: fake.github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue: async () => {
        assert.ok(writes(fake.calls).some(({ method, path }) => method === "DELETE" && path === "/repos/o/r/issues/7/labels/needs-human"));
        return { outcome: "refused", reasons: ["host work"], status: "status: confirmed" };
      },
      log: () => {},
    });
    assert.equal(result.outcome, "ready");
    assert.match(result.summary, /- Refused: `needs-human` came off/);
  });

  test("the ready comment says why a refused needs-human came off", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [{ event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: "2026-10-22T12:04:00Z" }],
    });
    const result = await run({
      env: ENV,
      github: fake.github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue: async () => ({ outcome: "refused", reasons: ["host work"], status: "status: confirmed" }),
      log: () => {},
    });
    assert.equal(result.outcome, "ready");
    const posted = writes(fake.calls).find(({ method, path }) => method === "POST" && path === "/repos/o/r/issues/7/comments");
    assert.match(posted.body.body, /`needs-human` came off: this run's triage applied it with no intent, security or cost flag/);
  });

  // The refused needs-human comes off before a ready verdict's comment posts,
  // so a failed post leaves the removal with no comment: the run fails red
  // (the entry point exits 1 on reasonsError) and the summary keeps the record.
  test("a failed reasons comment after a refused needs-human came off fails the run and keeps the record in the summary", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [{ event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: "2026-10-22T12:04:00Z" }],
    });
    const github = async (method, path, body) => {
      if (method === "POST" && path === "/repos/o/r/issues/7/comments") {
        fake.calls.push({ method, path, body });
        throw new GitHubError(403, "POST comments");
      }
      return fake.github(method, path, body);
    };
    const result = await run({ env: ENV, github, dimensionsConfig: DIMS, fieldSetters: noSetters, log: () => {} });
    assert.equal(result.outcome, "ready");
    assert.deepEqual(result.plan.refused, ["needs-human"]);
    assert.ok(writes(fake.calls).some(({ method, path }) => method === "DELETE" && path === "/repos/o/r/issues/7/labels/needs-human"));
    assert.ok(result.reasonsError, "the run fails");
    assert.match(result.summary, /- Refused: `needs-human` came off/);
    assert.match(result.summary, /- Reasons comment: not written \(/);
  });

  test("a hold that landed after the first read decides the Work status written", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [{ event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: "2026-10-22T12:04:00Z" }],
    });
    let reads = 0;
    const github = async (method, path, body) => {
      const answer = await fake.github(method, path, body);
      if (method === "GET" && path === "/repos/o/r/issues/7" && (reads += 1) === 2) {
        return { ...answer, labels: [...answer.labels, { name: OUTSIDE_ACTOR_LABEL }] };
      }
      return answer;
    };
    await run({ env: ENV, github, dimensionsConfig: DIMS, fieldSetters: noSetters, setStatus: fake.setStatus, statusConfig: STATUS_CONFIG, log: () => {} });
    assert.equal(reads, 2, "the refusal re-read the labels");
    assert.deepEqual(states(fake.calls), ["needs-human"], "the late hold keeps needs-human, which the field reads");
  });

  // security-outside-actor/flag.mjs adds needs-human as github-actions[bot] on
  // GITHUB_TOKEN, so its label can land inside this run's window.
  test("the outside-actor flag's needs-human, landing after this run started, keeps the hold", async () => {
    const at = "2026-10-22T12:04:00Z";
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }, { name: "security: outside-actor" }] },
      comments: [laneComment()],
      events: [
        { event: "labeled", label: { name: "security: outside-actor" }, actor: { id: ACTIONS_BOT }, created_at: at },
        { event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: at },
      ],
    });
    assert.equal((await go(fake)).outcome, "needs-decision");
    assert.ok(!writes(fake.calls).some(({ method }) => method === "DELETE"));
  });

  test("#9953's shape: needs-human and needs-owner-decision this run's triage applied with no flag both come off before admission", async () => {
    const at = "2026-10-22T12:04:00Z";
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }, { name: NEEDS_DECISION }] },
      comments: [laneComment()],
      events: [
        { event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: at },
        { event: "labeled", label: { name: NEEDS_DECISION }, actor: { id: ACTIONS_BOT }, created_at: at },
      ],
    });
    const deleted = (name) => writes(fake.calls).some(({ method, path }) => method === "DELETE" && path === `/repos/o/r/issues/7/labels/${encodeURIComponent(name)}`);
    const result = await run({
      env: ENV,
      github: fake.github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue: async () => {
        assert.ok(deleted("needs-human") && deleted(NEEDS_DECISION));
        return { outcome: "refused", reasons: ["host work"], status: "status: confirmed" };
      },
      log: () => {},
    });
    assert.equal(result.outcome, "ready");
    assert.match(result.summary, /- Refused: `needs-human`, `needs-owner-decision` came off/);
  });

  test("a needs-human a person set before this run started keeps the hold when the bot labels it again after", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [
        { event: "labeled", label: { name: "needs-human" }, actor: { id: HUMAN }, created_at: "2026-10-22T11:00:00Z" },
        { event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: "2026-10-22T12:04:00Z" },
      ],
    });
    assert.equal((await go(fake)).outcome, "needs-decision");
    assert.ok(!writes(fake.calls).some(({ method }) => method === "DELETE"));
  });

  // Only github-actions[bot] adds after STARTED_AT count as this run's triage.
  test("a needs-human a person takes off and puts back after the bot applied it in this run keeps the hold", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [
        { event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: "2026-10-22T12:04:00Z" },
        { event: "unlabeled", label: { name: "needs-human" }, actor: { id: HUMAN }, created_at: "2026-10-22T12:05:00Z" },
        { event: "labeled", label: { name: "needs-human" }, actor: { id: HUMAN }, created_at: "2026-10-22T12:06:00Z" },
      ],
    });
    assert.equal((await go(fake)).outcome, "needs-decision");
    assert.ok(!writes(fake.calls).some(({ method }) => method === "DELETE"));
  });

  test("a needs-human a person also applied after this run started keeps the hold beside the bot's", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [
        { event: "labeled", label: { name: "needs-human" }, actor: { id: HUMAN }, created_at: "2026-10-22T12:03:00Z" },
        { event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: "2026-10-22T12:04:00Z" },
      ],
    });
    assert.equal((await go(fake)).outcome, "needs-decision");
    assert.ok(!writes(fake.calls).some(({ method }) => method === "DELETE"));
  });

  // The lanes App writes the triage run's labels into the Work status field,
  // so on a re-run its field event after `since` is the triage's own add.
  test("a needs-human the lanes App wrote into the field after this run started counts as the triage run's", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [
        { event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: "2026-10-22T12:03:00Z" },
        { event: "labeled", label: { name: "needs-human" }, actor: { id: LANES_APP }, created_at: "2026-10-22T12:04:00Z" },
      ],
    });
    const result = await go(fake);
    assert.equal(result.outcome, "ready");
    assert.deepEqual(result.plan.refused, ["needs-human"]);
    assert.deepEqual(states(fake.calls), ["ready"]);
  });

  // A removal whose time cannot be read lifts nothing that held before.
  test("a person's needs-human before this run, removed at an unreadable time, keeps the hold when the bot adds it again", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [
        { event: "labeled", label: { name: "needs-human" }, actor: { id: HUMAN }, created_at: "2026-10-22T11:00:00Z" },
        { event: "unlabeled", label: { name: "needs-human" }, actor: { id: HUMAN }, created_at: "not a time" },
        { event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: "2026-10-22T12:04:00Z" },
      ],
    });
    assert.equal((await go(fake)).outcome, "needs-decision");
    assert.ok(!writes(fake.calls).some(({ method }) => method === "DELETE"));
  });

  test("a needs-human the bot applied at exactly STARTED_AT is this run's and is refused", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [{ event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: ENV.STARTED_AT }],
    });
    assert.equal((await go(fake)).outcome, "ready");
    assert.ok(writes(fake.calls).some(({ method, path }) => method === "DELETE" && path === "/repos/o/r/issues/7/labels/needs-human"));
  });

  test("events replay by time and id, not API order", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [
        { id: 3, event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: "2026-10-22T12:04:00Z" },
        { id: 2, event: "unlabeled", label: { name: "needs-human" }, actor: { id: HUMAN }, created_at: "2026-10-22T11:30:00Z" },
        { id: 1, event: "labeled", label: { name: "needs-human" }, actor: { id: HUMAN }, created_at: "2026-10-22T11:30:00Z" },
      ],
    });
    assert.equal((await go(fake)).outcome, "ready");
    assert.ok(writes(fake.calls).some(({ method, path }) => method === "DELETE" && path === "/repos/o/r/issues/7/labels/needs-human"));
  });

  test("a needs-human taken off before this run started and applied by its triage is refused", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [
        { event: "labeled", label: { name: "needs-human" }, actor: { id: HUMAN }, created_at: "2026-10-22T11:00:00Z" },
        { event: "unlabeled", label: { name: "needs-human" }, actor: { id: HUMAN }, created_at: "2026-10-22T11:30:00Z" },
        { event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: "2026-10-22T12:04:00Z" },
      ],
    });
    assert.equal((await go(fake)).outcome, "ready");
    assert.ok(writes(fake.calls).some(({ method, path }) => method === "DELETE" && path === "/repos/o/r/issues/7/labels/needs-human"));
  });

  // flag.mjs can add the outside-actor label and needs-human after the first
  // read; admission never reads outside-actor, so needs-human must stay.
  for (const late of ["security: outside-actor", "provenance: untrusted"]) {
    test(`${late} landing after the first read keeps a refused needs-human`, async () => {
      const fake = fakeGitHub({
        issue: { labels: [{ name: "needs-human" }] },
        comments: [laneComment()],
        events: [{ event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: "2026-10-22T12:04:00Z" }],
      });
      let reads = 0;
      const github = async (method, path, body) => {
        const answer = await fake.github(method, path, body);
        if (method === "GET" && path === "/repos/o/r/issues/7" && ++reads > 1) {
          return { ...answer, labels: [{ name: "needs-human" }, { name: late }] };
        }
        return answer;
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
      assert.ok(reads > 1, "the labels were not read again");
      assert.equal(result.outcome, "needs-decision");
      assert.equal(admitted, false);
      assert.deepEqual(result.plan.refused, []);
      assert.ok(!writes(fake.calls).some(({ method, path }) => method === "DELETE" && path === "/repos/o/r/issues/7/labels/needs-human"));
      assert.ok(!writes(fake.calls).some(({ method, body: sent }) => method === "POST" && sent?.labels?.includes(READY)));
    });
  }

  test("a needs-human github-actions[bot] applied before this run started keeps the hold", async () => {
    const fake = fakeGitHub({
      issue: { labels: [{ name: "needs-human" }] },
      comments: [laneComment()],
      events: [{ event: "labeled", label: { name: "needs-human" }, actor: { id: ACTIONS_BOT }, created_at: "2026-10-22T11:59:00Z" }],
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
    ["an earlier unflagged verdict comment and a failed edit", [unflagged("The triage verdict left this issue at `needs-owner-decision`:\n\n- no `Size:` line")], "PATCH /repos/o/r/issues/comments/51"],
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
      assert.ok(result.reasonsError, "the failure is on the result");
      assert.match(result.summary, /- Reasons comment: not written \(/);
      const labelWrites = writes(fake.calls).filter(({ path }) => path.startsWith("/repos/o/r/issues/7/labels"));
      assert.deepEqual(labelWrites, [], "no hold lands without its record");
      assert.ok(!writes(fake.calls).some(({ path }) => path === "/repos/o/r/issues/comments/99"), "the lane comment is never edited");
    });
  }

  // Moving the Work status off ready adds no hold, so it needs no record and never waits on one.
  for (const [name, comments, failing] of [
    ["a failed post", [], "POST /repos/o/r/issues/7/comments"],
    ["a failed edit", [unflagged()], "PATCH /repos/o/r/issues/comments/51"],
  ]) {
    test(`a flagged re-triage of an issue at status: ready with ${name} still moves the Work status off ready and writes no label`, async () => {
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
      const result = await run({ env: ENV, github, dimensionsConfig: DIMS, fieldSetters: noSetters, setStatus: fake.setStatus, statusConfig: STATUS_CONFIG, log: () => {} });
      assert.ok(result.reasonsError, "the run fails");
      assert.deepEqual(states(fake.calls), ["needs-triage"], "the Work status leaves ready and no hold is written");
      const labelWrites = writes(fake.calls).filter(({ path }) => path.startsWith("/repos/o/r/issues/7/labels"));
      assert.deepEqual(labelWrites, [], "no status label is taken off or added");
      assert.match(result.summary, /- Labels: none written, since the reasons comment was not written/);
    });
  }

  test("a failed edit of the reasons comment on a ready verdict still lands the verdict and reports the failure", async () => {
    const fake = fakeGitHub({ comments: [laneComment(), unflagged()] });
    const github = async (method, path, body) => {
      if (method === "PATCH" && path === "/repos/o/r/issues/comments/51") {
        fake.calls.push({ method, path, body });
        throw new GitHubError(403, "PATCH comments");
      }
      return fake.github(method, path, body);
    };
    const result = await run({ env: ENV, github, dimensionsConfig: DIMS, fieldSetters: noSetters, setStatus: fake.setStatus, statusConfig: STATUS_CONFIG, log: () => {} });
    assert.equal(result.outcome, "ready");
    assert.ok(!writes(fake.calls).some(({ path }) => path === "/repos/o/r/issues/comments/99"), "the lane comment is never edited");
    assert.deepEqual(states(fake.calls), ["ready"]);
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

  // Admission's own comment already says why it parked the issue at
  // status: confirmed, which is no hold, so a verdict comment saying only
  // that adds nothing a reader or a later run reads.
  test("a mechanical admission refusal to status: confirmed posts no verdict comment beside admission's", async () => {
    const fake = fakeGitHub({ comments: [laneComment()] });
    const result = await run({
      env: ENV,
      github: fake.github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue: async () => ({ outcome: "refused", reasons: ["no acceptance criteria"], status: "status: confirmed" }),
      log: () => {},
    });
    const posted = writes(fake.calls).filter(({ method, path }) => method === "POST" && path === "/repos/o/r/issues/7/comments");
    assert.deepEqual(posted, []);
    assert.match(result.summary, /- Status: status: confirmed/);
  });

  test("a mechanical admission refusal to status: confirmed still settles an earlier verdict comment, naming the label admission wrote", async () => {
    const fake = fakeGitHub({ comments: [laneComment(), unflagged("The triage verdict left this issue at `needs-owner-decision`:\n\n- flagged: intent")] });
    await run({
      env: ENV,
      github: fake.github,
      dimensionsConfig: DIMS,
      fieldSetters: noSetters,
      admitIssue: async () => ({ outcome: "refused", reasons: ["no acceptance criteria"], status: "status: confirmed" }),
      log: () => {},
    });
    const edited = writes(fake.calls).find(({ method, path }) => method === "PATCH" && path === "/repos/o/r/issues/comments/51");
    assert.match(edited?.body.body ?? "", /admission moved the issue to `status: confirmed`/);
    assert.ok(!edited.body.body.includes("needs-decision"), edited.body.body);
  });

  test("a ready verdict over needs-triage writes the Work status ready and takes no label off", async () => {
    const fake = fakeGitHub({ issue: { labels: [{ name: "needs-triage" }] }, comments: [laneComment()] });
    assert.equal((await go(fake)).outcome, "ready");
    const done = writes(fake.calls).map(({ method, path, body }) => `${method} ${path}${method === "STATUS" ? ` ${body}` : ""}`);
    assert.equal(done.at(-1), "STATUS #7 ready", done.join("\n"));
    assert.ok(!done.some((line) => line.startsWith("DELETE /repos/o/r/issues/7/labels/")), done.join("\n"));
  });

  // The triage run's own hold labels (the reusable's) stay on the issue and
  // reach the field as their state, the strongest first (models.issue-status order).
  for (const [labels, state] of [
    [["needs-human"], "needs-human"],
    [["needs-reporter-info"], "needs-reporter-info"],
    [["needs-human", "needs-reporter-info"], "needs-human"],
    [["needs-owner-decision"], "needs-owner-decision"],
  ]) {
    test(`a held verdict writes the triage run's ${labels.join(" and ")} as ${state}, keeping the labels`, async () => {
      const fake = fakeGitHub({ issue: { labels: labels.map((name) => ({ name })) }, comments: [laneComment(ESCALATED_BODY)] });
      assert.equal((await go(fake)).outcome, "needs-decision");
      assert.deepEqual(states(fake.calls), [state]);
      assert.ok(!writes(fake.calls).some(({ method, path }) => method === "DELETE" && labels.some((name) => path.endsWith(encodeURIComponent(name)))), "the labels stay");
      assert.ok(!writes(fake.calls).some(({ path }) => path.endsWith("/labels")), "no status label is added");
    });
  }

  // The issue carries no hold label and no label event: its field holds
  // needs-owner-decision, which a person set.
  test("a hold that exists only on the Work status field blocks a ready verdict", async () => {
    const fake = fakeGitHub({ comments: [laneComment()] });
    // A real time on the field event, an hour before this run started, so
    // labelSetters replays it in order as an earlier person's hold.
    const node = { __typename: "IssueFieldAddedEvent", createdAt: "2026-10-22T11:00:00Z", value: "needs-owner-decision", actor: { __typename: "User", login: "kyle-sexton", databaseId: HUMAN }, issueField: { fullDatabaseId: String(STATUS_CONFIG["field-id"]) } };
    const github = withFields(fake.github, { 7: { state: "needs-owner-decision", setter: HUMAN, nodes: [node] } });
    const trustedActors = { version: 1, actors: [{ id: HUMAN, login: "kyle-sexton", kind: "human" }] };
    const statusOf = statusReader({ github, repository: "o/r", config: STATUS_CONFIG, trustedActors, log: () => {} });
    const fields = async () => ({ [String(STATUS_CONFIG["field-id"])]: HUMAN });
    const result = await run({ env: ENV, github, dimensionsConfig: DIMS, fieldSetters: fields, setStatus: fake.setStatus, statusConfig: STATUS_CONFIG, statusOf, log: () => {} });
    assert.equal(result.outcome, "needs-decision");
    assert.ok(result.plan.reasons.includes(`held by needs-owner-decision`), JSON.stringify(result.plan.reasons));
    const [written] = fake.calls.filter(({ method }) => method === "STATUS");
    assert.equal(written.body, "needs-owner-decision");
    assert.ok(written.fields[String(STATUS_CONFIG["field-id"])], "the person's value is handed over, so the writer skips it");
  });

  // A born-triaged issue filed with the agent-ready label and no Work status:
  // the label starts no run, so the ready verdict writes ready and admission
  // decides it. An issue whose field already holds agent-ready gets no write.
  const labelOnly = (fields) => {
    const fake = fakeGitHub({ issue: { labels: [{ name: "agent-ready" }] }, comments: [laneComment()] });
    const github = withFields(fake.github, fields);
    const trustedActors = { version: 1, actors: [{ id: HUMAN, login: "kyle-sexton", kind: "human" }] };
    const statusOf = statusReader({ github, repository: "o/r", config: STATUS_CONFIG, trustedActors, log: () => {} });
    return { fake, run: () => run({ env: ENV, github, dimensionsConfig: DIMS, fieldSetters: noSetters, setStatus: fake.setStatus, statusConfig: STATUS_CONFIG, statusOf, log: () => {} }) };
  };

  test("a ready verdict on an issue with only the agent-ready label and an unset Work status writes ready", async () => {
    const { fake, run: apply } = labelOnly({});
    assert.equal((await apply()).outcome, "ready");
    assert.deepEqual(states(fake.calls), ["ready"]);
    assert.ok(!writes(fake.calls).some(({ method, path }) => method === "DELETE" && path.endsWith("/labels/agent-ready")), "the label is left as it is");
  });

  test("a ready verdict on an issue whose Work status already holds agent-ready writes no status", async () => {
    const { fake, run: apply } = labelOnly({ 7: { state: "agent-ready", setter: HUMAN } });
    assert.equal((await apply()).outcome, "ready");
    assert.deepEqual(states(fake.calls), []);
  });

  // Admission reads the issue fresh after that write (admit.mjs
  // admissionFacts), so the agent-ready label left on it no longer settles it.
  test("once ready is written, admission does not read the leftover agent-ready label as already agent-ready", () => {
    const anyone = () => true;
    assert.equal(admissionSettled(["agent-ready"], [], anyone, null), "already agent-ready");
    assert.equal(admissionSettled(statusLabels("ready", ["agent-ready"], STATUS_CONFIG), [], anyone, "ready"), null);
  });

  // A Work status read that fails could hide a person's hold, so the App's
  // own hold is not lifted and nothing is written.
  test("a failed Work status read lifts no App hold and writes nothing", async () => {
    const fake = fakeGitHub({ issue: { labels: [{ name: NEEDS_DECISION }] }, comments: [laneComment()] });
    const github = withFields(fake.github, { 7: new Error("HTTP 502") });
    const trustedActors = { version: 1, actors: [{ id: HUMAN, login: "kyle-sexton", kind: "human" }] };
    const statusOf = statusReader({ github, repository: "o/r", config: STATUS_CONFIG, trustedActors, log: () => {} });
    await assert.rejects(run({ env: ENV, github, dimensionsConfig: DIMS, fieldSetters: noSetters, setStatus: fake.setStatus, statusConfig: STATUS_CONFIG, statusOf, log: () => {} }), { name: "StatusReadError" });
    assert.deepEqual(writes(fake.calls), []);
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
        comments: [laneComment(UNTRUSTED_BODY)],
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
        setStatus: fake.setStatus,
        statusConfig: STATUS_CONFIG,
        admitIssue: async () => {
          admitted = true;
          return { outcome: "admitted", reasons: [] };
        },
        log: () => {},
      });
      assert.deepEqual(result.missed, [{ number: 12, status }]);
      assert.ok(!admitted, "admission reads blockers from native edges only, so it waits");
      const added = fake.calls.filter(({ method, path }) => method === "POST" && path.endsWith("/labels")).flatMap(({ body }) => body.labels);
      assert.ok(!added.some((name) => name.startsWith("work-class:")), added.join(", "));
      assert.ok(!added.includes(READY), added.join(", "));
      assert.ok(!states(fake.calls).includes("ready"), `the Work status is not set to ready: ${states(fake.calls).join(", ")}`);
      assert.ok(!fake.calls.some(({ method, path }) => method === "DELETE" && path.endsWith(`/labels/${encodeURIComponent(READY)}`)), "status: ready is not taken off as a label");
      assert.ok(result.summary.includes(`- Blocked by: #12 not written (GitHub answered ${status})`), result.summary);
      assert.match(result.summary, /- Status: none: admission waits for intake to run again, since a blocked-by edge is missing/);
      const said = fake.calls.find(({ method, path }) => (method === "POST" && path.endsWith("/comments")) || (method === "PATCH" && path.endsWith("/comments/51")));
      assert.ok(said?.body.body.startsWith(`${VERDICT_MARKER}\n`), said?.body.body);
      assert.ok(!said.body.body.includes(`is at \`${READY}\``), said.body.body);
      assert.match(said.body.body, /blocked-by edge is missing/);
      if (status === 403) {
        assert.ok(said.body.body.endsWith(`starts. GitHub answered 403 for an edge, and ${FORBIDDEN_EDGE}.`), said.body.body);
      } else {
        assert.ok(said.body.body.endsWith("which the hourly triage sweep starts."), said.body.body);
        assert.ok(!said.body.body.includes("Issues repository permission"), said.body.body);
      }
    });
  }

  test("the 403 text names the Issues permission at write and how to grant it", () => {
    assert.match(FORBIDDEN_EDGE, /otherwise the lanes App lacks the Issues repository permission at write, which no re-run fixes/);
    assert.match(FORBIDDEN_EDGE, /the App's owner sets Issues to Read and write under Repository permissions on the App's Permissions & events settings page/);
    assert.match(FORBIDDEN_EDGE, /the owner of the account it is installed on approves the updated permissions$/);
    assert.match(FORBIDDEN_EDGE, /^a 403 is a rate limit when this run's label writes landed, since this token makes them through the same grant/);
    assert.ok(!FORBIDDEN_EDGE.includes("dependencies permission"), "GitHub has no dependencies permission");
    assert.ok(!/[\r\n%]/.test(FORBIDDEN_EDGE), "an annotation line carries no newline or percent sign");
  });

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
    assert.equal(
      forbidden.line,
      `::error title=apply-verdict::blocked-by edges not written: #12 not written (GitHub answered 502); #13 not written (GitHub answered 403); ${FORBIDDEN_EDGE}. The verdict's labels are written without status: ready, and admission waits for intake to run again`,
    );
    assert.deepEqual(missedAnnotation([{ number: 12, status: 429 }]), {
      fail: false,
      line: "::warning title=apply-verdict::blocked-by edges not written: #12 not written (GitHub answered 429); the verdict's labels are written without status: ready, and admission waits until the hourly triage sweep runs intake again, which writes them",
    });
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
      assert.equal(missedAnnotation(result.missed, result.undeleted, true).fail, status === 403, "a ready verdict keeps its behavior");
    });
  }

  // A verdict that is not ready: with every edge missed, work-unblock sees none
  // of the blockers; with an edge written and its rollback failed, it sees
  // that partial set, so the warning keeps the partial-set clause.
  test("a not-ready verdict's warning says work-unblock sees no blocker only when no edge stayed written", () => {
    assert.deepEqual(missedAnnotation([{ number: 13, status: 502 }], [], false), {
      fail: false,
      line: "::warning title=apply-verdict::blocked-by edges not written on a verdict that is not ready: #13 not written (GitHub answered 502); the verdict's labels are written, and work-unblock, which reads only native edges, does not see these blockers",
    });
    assert.deepEqual(missedAnnotation([{ number: 13, status: 502 }], [{ number: 12, status: 500 }], false), {
      fail: false,
      line: "::warning title=apply-verdict::blocked-by edges not written on a verdict that is not ready: #13 not written (GitHub answered 502); #12 written and not deleted (GitHub answered 500), so work-unblock can admit the issue when that blocker closes before intake runs again; the verdict's labels are written, and work-unblock, which reads only native edges, does not see the blockers not written",
    });
  });

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

// checkRun reads the issue, so every --check step must pass its number and a token.
describe("the workflow's --check steps", () => {
  const steps = readFileSync(new URL("../../workflows/intake-triage.yml", import.meta.url), "utf8")
    .split(/\n {6}- name: /)
    .filter((step) => step.includes("apply-verdict.mjs --check"));

  test("there is a --check step in each job that runs one", () => {
    assert.ok(steps.length >= 3, `found ${steps.length}`);
  });

  for (const [index, step] of steps.entries()) {
    test(`--check step ${index + 1} sets ISSUE_NUMBER and GH_TOKEN`, () => {
      assert.match(step, /\n\s+ISSUE_NUMBER: \$\{\{ github\.event\.issue\.number \|\| inputs\.issue-number \}\}/);
      assert.match(step, /\n\s+GH_TOKEN: \$\{\{ github\.token \}\}/);
    });
  }
});

// The prompt's paragraphs as flowing text, keyed by their capitalized lead.
const PROMPT = readFileSync(new URL("../../workflows/intake-triage.yml", import.meta.url), "utf8")
  .split("\n")
  .map((line) => line.trim())
  .join(" ");

// Owner's standing direction §2: a choice of implementation means is never a person stop.
describe("the triage prompt", () => {
  test("an intent question is an open outcome, done-when or unpicked primary design, never a choice of implementation means", () => {
    assert.doesNotMatch(PROMPT, /lists options and picks none/);
    assert.doesNotMatch(PROMPT, /intent when the intended outcome is not exact or needs the owner's decision/);
    assert.doesNotMatch(PROMPT, /A choice among means the issue lists, or of how to do the work, is not an intent question/);
    assert.match(PROMPT, /Flags: intent when the intended outcome or done-when is not exact, or the issue lists primary-design alternatives and picks none/);
    assert.match(
      PROMPT,
      /A choice among implementation means that leaves the primary design \(architecture, cross-module contracts, data ownership, public interfaces\) unchanged is not an intent question: the issue lane decides it on evidence/,
    );
    assert.match(
      PROMPT,
      /A primary-design choice the issue lists and leaves unpicked \(two architectures, a new shared store or an existing one\) is an intent question: set `Flags: intent`, apply `needs-owner-decision`, and ask it as a numbered question with a `RECOMMENDED:` answer/,
    );
  });

  test("every needs-owner-decision the prompt asks for comes with a flag, and a flagless one is said to come off", () => {
    assert.match(PROMPT, /c\. When one or more stay open, set `Flags: intent`, apply `needs-owner-decision`/);
    assert.match(PROMPT, /A `needs-owner-decision` or `needs-human` label you apply holds only beside a flag on the Flags line/);
  });

  test("a charge a recorded decision covers goes on a Cost decided line, never a Cost line", () => {
    assert.match(PROMPT, /already covers that charge; then name it on one `Cost decided: <what bills; the decision that covers it>` line instead, never a `Cost: ` line/);
  });

  // Work classes are retired. Run 41807993284: a model told of classes with
  // no meanings grepped outside the checkout, dontAsk denied it, and the clean
  // triage deferred, so the line also says not to search.
  test("the Work class line asks for none, names no class, and keeps untrusted provenance off it", () => {
    const line = /- Work class: (.*?) - Size:/.exec(PROMPT)?.[1] ?? "";
    assert.match(line, /^always none\./);
    assert.match(line, /never search for their meanings/);
    assert.match(line, /mark it with the untrusted flag \(Flags below\), never on the class line/);
    for (const name of [...CLASSES, "work-class: read-only"]) {
      assert.ok(!line.includes(`\`${name}\``), `the rubric offers ${name}`);
    }
    assert.doesNotMatch(PROMPT, /work-class-labels\.md/);
  });

  test("the prompt marks untrusted provenance on the Flags line, which the parser reads as untrusted", () => {
    assert.match(PROMPT, /Flags: none\|intent\|security\|cost\|untrusted/);
    const verdict = parseVerdict(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: untrusted"] }), DIMS);
    assert.equal(verdict.untrusted, true);
  });

  // #13197: the issue lane's blocked-by-issue stop names its blocker for
  // triage to record as an edge, never in reverse of an existing one.
  test("a blocker the issue lane names on a blocked-by-issue stop goes on the Blocked by line", () => {
    assert.match(PROMPT, /latest stop comment on the\s+issue is `blocked-by-issue` and names an open issue, list that issue there, unless the\s+named issue is itself blocked by this one/);
    // The name is the issue lane's own stop code, routed to intake, so a
    // rename there fails here instead of leaving the rubric silently stale.
    const routes = JSON.parse(readFileSync(new URL("../work-resolve-issue/stop-routes.json", import.meta.url), "utf8"));
    assert.equal(routes["blocked-by-issue"]?.route, "intake");
  });

  test("a Cost line is written exactly in its form, and work with no charge gets none", () => {
    assert.match(PROMPT, /Write a Cost line exactly as `Cost: <what bills, where; the owner decision it lacks>` or `Cost decided: <what bills; the decision that covers it>`/);
    assert.match(PROMPT, /Work with no charge gets no Cost line/);
  });
});

// g-holds-governance-1 (a): a held verdict names one owner reason, the
// strongest of its causes, as the stop-reason marker and line.
describe("held verdict reason codes", () => {
  const plan = (body, options = {}) =>
    planWrites(parseVerdict(body, DIMS), { labels: [], fields: {}, dimensionsConfig: DIMS, appId: LANES_APP, humans, earlierFlags: [], ...options });
  const flags = (value, extra = []) => laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", `Flags: ${value}`, ...extra] });

  test("each cause maps to its code, and a ready verdict names none", () => {
    for (const [why, body, options, code] of [
      ["an intent flag", flags("intent"), {}, "intent"],
      ["a security flag", flags("security"), {}, "security"],
      ["a cost flag", flags("cost"), {}, "cost"],
      ["a Cost line beside no flag", flags("none", ["Cost: a new paid plan; no owner decision"]), { labels: ["needs-human"] }, "cost"],
      ["an escalated run", ESCALATED_BODY, {}, "security"],
      ["untrusted provenance", UNTRUSTED_BODY, {}, "security"],
      ["an unreadable Flags line", flags("maybe"), {}, "intent"],
      ["an outside-actor hold", laneBody(), { labels: [OUTSIDE_ACTOR_LABEL] }, "security"],
      ["a carried security flag", laneBody(), { labels: [NEEDS_DECISION], earlierFlags: ["security"] }, "security"],
      ["an unrecorded earlier flag", laneBody(), { labels: [NEEDS_DECISION], earlierFlags: null }, "intent"],
    ]) {
      const result = plan(body, options);
      assert.equal(result.ready, false, why);
      assert.equal(result.reason, code, why);
    }
    assert.equal(plan(laneBody()).reason, null);
  });

  test("a hold with several flags names security over intent and cost", () => {
    assert.equal(plan(flags("intent, cost, security")).reason, "security");
    assert.equal(plan(flags("intent, cost")).reason, "cost");
  });

  test("the held comment carries the marker and line after the reasons, which earlierFlags still reads", async () => {
    const fake = fakeGitHub({ comments: [laneComment(flags("security, intent"))] });
    assert.equal((await go(fake)).outcome, "needs-decision");
    const body = writes(fake.calls).find(({ method, path }) => method === "POST" && path.endsWith("/comments")).body.body;
    assert.deepEqual(parseReason(body), { lane: "intake-triage", reason: "security" });
    assert.ok(body.startsWith(`${VERDICT_MARKER}\n`));
    assert.ok(body.endsWith("\n\n<!-- intake-triage intent-raised-at 2026-10-22T12:05:00Z -->\nReason: `security`\n<!-- stop-reason lane=intake-triage reason=security -->"), body);
    assert.equal(raisedAt(body), "2026-10-22T12:05:00Z", "this run's intent flag records its raise time");
    assert.deepEqual(earlierFlags([{ body, user: { id: LANES_APP } }], LANES_APP), ["security", "intent"]);
  });
});

// g-holds-governance-1 (b): a listed human's recorded decision, newer than the
// lanes App's verdict comment, answers its carried intent flag; a security or
// cost flag still holds (owner Q4).
describe("re-entry after a recorded decision", () => {
  const VERDICT_AT = "2026-10-22T10:00:00Z";
  const appVerdict = (lines) => ({
    id: 51,
    body: `${VERDICT_MARKER}\nThe triage verdict left this issue at \`${NEEDS_DECISION}\`:\n\n${lines}`,
    user: { id: LANES_APP, type: "Bot" },
    created_at: VERDICT_AT,
    updated_at: VERDICT_AT,
  });
  const decision = (at = "2026-10-22T11:00:00Z", overrides = {}) => ({
    id: 61,
    node_id: "IC_decision",
    body: "**Decision recorded.**\nShip the smaller fix.",
    user: { id: HUMAN, login: "kyle-sexton", type: "User" },
    created_at: at,
    performed_via_github_app: null,
    ...overrides,
  });
  const kept = (comment, lastEditedAt = null, lastEditorId = null) => [{ comment, lastEditedAt, lastEditorId }];
  const held = (comments) =>
    fakeGitHub({ issue: { labels: [{ name: NEEDS_DECISION }] }, comments: [laneComment(), ...comments], events: [{ event: "labeled", label: { name: NEEDS_DECISION }, actor: { id: LANES_APP } }] });

  test("flagsAfterDecision drops intent after a newer decision, and keeps security, cost and an unrecorded flag", () => {
    const own = appVerdict("- flagged: intent");
    assert.deepEqual(flagsAfterDecision(["intent", "security", "cost"], own, kept(decision()), humans), ["security", "cost"]);
    assert.equal(flagsAfterDecision(null, own, kept(decision()), humans), null, "an unrecorded flag may have been security");
    assert.deepEqual(flagsAfterDecision(["intent"], own, kept(decision("2026-10-22T09:00:00Z")), humans), ["intent"], "an older decision answers nothing");
    assert.deepEqual(flagsAfterDecision(null, own, kept(decision("2026-10-22T09:00:00Z")), humans), null);
    assert.deepEqual(flagsAfterDecision(["intent"], own, kept(decision(undefined, { user: { id: OUTSIDER } })), humans), ["intent"], "an unlisted author decides nothing");
    assert.deepEqual(flagsAfterDecision(["intent"], own, kept(decision(undefined, { performed_via_github_app: { slug: "x" } })), humans), ["intent"], "a decision through an App decides nothing");
    assert.deepEqual(flagsAfterDecision(["intent"], own, kept(decision(undefined, { body: "I think we should ship it." })), humans), ["intent"], "a comment that is no decision");
    assert.deepEqual(flagsAfterDecision(["intent"], own, kept(decision(), "2026-10-22T11:30:00Z", OUTSIDER), humans), ["intent"], "a decision another account last edited");
    assert.deepEqual(flagsAfterDecision(["intent"], undefined, kept(decision()), humans), ["intent"], "no App verdict comment to answer");
  });

  // An identical body is never re-written, so updated_at can predate a raise
  // made after the decision; the recorded raise time decides instead.
  test("an intent flag raised again after a decision still holds a later clean verdict", async () => {
    const reraised = appVerdict(`- flagged: intent\n${raisedLine(["intent"], "2026-10-22T12:00:00Z", undefined)[0]}`);
    assert.equal(raisedAt(reraised.body), "2026-10-22T12:00:00Z");
    assert.deepEqual(flagsAfterDecision(["intent"], reraised, kept(decision()), humans), ["intent"], "the 11:00 decision predates the 12:00 raise");
    assert.deepEqual(flagsAfterDecision(["intent"], reraised, kept(decision("2026-10-22T13:00:00Z")), humans), [], "a decision after the raise answers it");
    assert.equal((await go(held([reraised, decision()]))).outcome, "needs-decision");
  });

  test("raisedLine records this run's time when its verdict flags intent, else carries the earlier line", () => {
    const earlier = appVerdict(`- flagged: intent\n${raisedLine(["intent"], "2026-10-22T12:00:00Z")[0]}`).body;
    assert.deepEqual(raisedLine(["intent", "cost"], "2026-10-23T08:00:00Z", earlier), ["<!-- intake-triage intent-raised-at 2026-10-23T08:00:00Z -->"]);
    assert.deepEqual(raisedLine(["cost"], "2026-10-23T08:00:00Z", earlier), ["<!-- intake-triage intent-raised-at 2026-10-22T12:00:00Z -->"]);
    assert.deepEqual(raisedLine([], "2026-10-23T08:00:00Z", undefined), []);
    assert.equal(raisedAt("<!-- intake-triage intent-raised-at 2026-10-22T12:00:00Z --> trailing"), null, "a line with other text is not the record");
  });

  test("a carried intent flag a newer decision answers does not re-hold a clean verdict", async () => {
    const fake = held([appVerdict("- flagged: intent"), decision()]);
    assert.equal((await go(fake)).outcome, "ready");
    assert.ok(writes(fake.calls).some(({ method, path }) => method === "DELETE" && path === `/repos/o/r/issues/7/labels/${encodeURIComponent(NEEDS_DECISION)}`));
  });

  test("an unrecorded earlier flag still holds after a decision, since it may have been security", async () => {
    assert.equal((await go(held([appVerdict(`- ${UNRECORDED}`), decision()]))).outcome, "needs-decision");
  });

  test("a failed read of the decisions answers nothing: the carried intent flag holds", async () => {
    const fake = held([appVerdict("- flagged: intent"), decision()]);
    const github = async (method, path, ...rest) => {
      if (method === "POST" && path === "/graphql") {
        throw new GitHubError(502, path);
      }
      return fake.github(method, path, ...rest);
    };
    const result = await run({ env: ENV, github, dimensionsConfig: DIMS, fieldSetters: noSetters, log: () => {} });
    assert.equal(result.outcome, "needs-decision");
  });

  test("with no newer decision the carried intent flag still holds", async () => {
    const fake = held([appVerdict("- flagged: intent"), decision("2026-10-22T09:00:00Z")]);
    assert.equal((await go(fake)).outcome, "needs-decision");
  });

  test("owner Q4: a carried security flag still holds after a decision, as security", async () => {
    const fake = held([appVerdict("- flagged: security\n- flagged: intent (an earlier verdict)"), decision()]);
    const result = await go(fake);
    assert.equal(result.outcome, "needs-decision");
    assert.equal(result.plan.reason, "security");
    const patch = writes(fake.calls).find(({ path }) => path === "/repos/o/r/issues/comments/51");
    assert.match(patch.body.body, /- flagged: security \(an earlier verdict\)/);
    assert.doesNotMatch(patch.body.body, /flagged: intent/);
    assert.deepEqual(parseReason(patch.body.body), { lane: "intake-triage", reason: "security" });
  });

  test("owner Q4: this run's own security flag holds whatever the decision says", async () => {
    const lane = laneComment(laneBody({ lines: ["Size: Small", "Complexity: Low", "Uncertainty: Known", "Flags: security"] }));
    const fake = fakeGitHub({ issue: { labels: [{ name: NEEDS_DECISION }] }, comments: [lane, appVerdict("- flagged: intent"), decision()], events: [{ event: "labeled", label: { name: NEEDS_DECISION }, actor: { id: LANES_APP } }] });
    const result = await go(fake);
    assert.equal(result.outcome, "needs-decision");
    assert.equal(result.plan.reason, "security");
  });

  test("a carried cost flag still holds after a decision", async () => {
    const result = await go(held([appVerdict("- flagged: cost"), decision()]));
    assert.equal(result.outcome, "needs-decision");
    assert.equal(result.plan.reason, "cost");
  });
});
