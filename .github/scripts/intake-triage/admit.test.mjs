import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { bodyVersion, personChecks, renderSplitRecord, SIZE_SPLIT_MARKER, splitChildBody, splitChildHeader, splitItemsLine, splitTaskLines, trustedSplitChild } from "./admit.mjs";
import { fileURLToPath } from "node:url";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { tempDir } from "../../../lib/test-tmp.mjs";

import { ADMIT_MARKER, AGENT_READY, DEFERRED, PATCH_ROW, RACE_WINDOW_MS, UNTRUSTED as UNTRUSTED_CLASS, admissionFacts, admissionsAhead, admissionsSince, admit, authorAdmitted, chargeHits, closedByTrusted, chargePattern, decide, deferralLapsed, doneReason, issuePushRefusals, loadRules, mergedRefsAfter, mergedRefsReader, noteUnrunnable, openPullsNaming, pushRefusalsOf, readSchedule, refsNames, refusalText, unrunnableCriteria, untrustedHold } from "./admit.mjs";
import { REFINE_MARKER, render, sizeSplitPending, validateOutput } from "./refine.mjs";
import { VERDICT_MARKER } from "./apply-verdict.mjs";
import { TARGETS } from "../apply-patch/apply-patch.mjs";

const VECTORS = JSON.parse(readFileSync(new URL("./split-child.vectors.json", import.meta.url), "utf8"));
const RULES = loadRules(fileURLToPath(new URL("../../actions/resolve-config/admission-rules.json", import.meta.url)));
const HUMAN = 153232337;
const OUTSIDER = 4242;
const APP = 337595936;
const humans = new Set([HUMAN]);
const READY = "status: ready";
const NEEDS_DECISION = "status: needs-decision";
const CONFIRMED = "status: confirmed";

const BODY = ["## Problem", "", "`plugins/session-flow/README.md:3` says eighteen.", "", "## Done when", "", "- [ ] Line 3 says nineteen."].join(
  "\n",
);
// #9287's done-when, as filed.
const CANARY = [
  "## Done when",
  "",
  "- [ ] Line 9 of `plugins/machine-health/README.md` says 27 checks.",
  "- [ ] Run `/machine-health:audit` on a Windows 11 host and confirm the report lists 27 check results.",
  "- [ ] One changelog fragment made with `scripts/new-changelog-fragment.sh machine-health patch`.",
].join("\n");
const HOSTS = ["code.claude.com", "docs.github.com"];
const issueOf = (overrides = {}) => ({
  number: 7,
  state: "open",
  created_at: "2026-10-20T08:00:00Z",
  title: "docs(session-flow): README skill count",
  body: BODY,
  user: { id: HUMAN },
  type: { name: "Task" },
  sub_issues_summary: { total: 0, completed: 0, percent_completed: 0 },
  labels: [{ name: READY }, { name: "work-class: mechanical" }],
  ...overrides,
});
// Authors and editors as GraphQL answers them, for the trusted-spec criterion.
const USER = (databaseId) => ({ __typename: "User", databaseId });
const APP_ACTOR = { __typename: "Bot", databaseId: APP };
// A body or comment as SPEC_QUERY answers it; by default it carries BODY's task list.
const written = (author, { body = BODY, editor = null, lastEditedAt = editor ? "2026-10-20T00:00:00Z" : null } = {}) => ({ body, author, editor, lastEditedAt });
// The issue's text as a listed human wrote it, unedited.
const humanSpec = (issue, comments = []) => ({ ...written(USER(HUMAN), { body: issue.body }), comments });
const VERDICT = {
  workClass: "work-class: mechanical",
  dimensions: { size: "small", complexity: "low", uncertainty: "known" },
};
const facts = (overrides = {}) => ({
  issue: issueOf(),
  verdict: VERDICT,
  rules: RULES,
  parent: null,
  blockers: [],
  trustedCloses: new Set(),
  pulls: [],
  events: [],
  humans,
  appId: APP,
  webHosts: HOSTS,
  repository: "o/r",
  spec: humanSpec(overrides.issue ?? issueOf()),
  ...overrides,
});

describe("decide", () => {
  // pr-verify judges a lane PR only against text a listed human wrote and
  // last edited, and the refinement on their issue (resolve-pr.mjs
  // linkedIssues), so an issue with no such text fails verify at every head.
  describe("trusted-human acceptance criteria", () => {
    const appIssue = issueOf({ user: { id: APP } });
    const NO_SPEC =
      "no trusted-human acceptance criteria: a listed human must put the confirmed `- [ ]` criteria in the body or post them as their own comment, or, on an issue a listed human filed, intake's newest refinement comment must hold them unedited";
    const goAhead = written(USER(HUMAN), { body: "Go ahead." });
    const APP_FILED = "the lanes App filed it and it is not a trusted size-split sub-issue (splitChildBody), so a listed human files it as their own";

    test("an App-authored issue with criteria only in its body is refused for a person", () => {
      for (const spec of [{ ...written(APP_ACTOR), comments: [] }, { ...written(APP_ACTOR), comments: [written(APP_ACTOR), written(USER(OUTSIDER))] }]) {
        assert.deepEqual(decide(facts({ issue: appIssue, spec })), { verdict: "refuse", reasons: [APP_FILED, NO_SPEC], hold: true });
      }
    });

    test("an App-drafted task list with a listed human's comment that carries none is refused for a person", () => {
      assert.deepEqual(decide(facts({ issue: appIssue, spec: { ...written(APP_ACTOR), comments: [goAhead] } })), { verdict: "refuse", reasons: [APP_FILED, NO_SPEC], hold: true });
    });

    // Owner decision on #10735: the lanes App's issue is admitted only as a
    // trusted size-split sub-issue, whatever a listed human's comment carries.
    test("the same issue with a listed human's comment carrying the task list is still refused for a person", () => {
      for (const comment of [written(USER(HUMAN)), written(USER(HUMAN), { editor: USER(HUMAN) })]) {
        assert.deepEqual(decide(facts({ issue: appIssue, spec: { ...written(APP_ACTOR), comments: [goAhead, comment] } })), { verdict: "refuse", reasons: [APP_FILED], hold: true });
      }
      // A human's comment the App last edited is no longer theirs.
      const edited = decide(facts({ issue: appIssue, spec: { ...written(APP_ACTOR), comments: [written(USER(HUMAN), { editor: APP_ACTOR })] } }));
      assert.deepEqual(edited.reasons, [APP_FILED, NO_SPEC]);
    });

    test("a human-authored body last edited by the App is refused unless a human comment carries the task list", () => {
      const body = written(USER(HUMAN), { editor: APP_ACTOR });
      assert.deepEqual(decide(facts({ spec: { ...body, comments: [] } })), { verdict: "refuse", reasons: [NO_SPEC] });
      assert.deepEqual(decide(facts({ spec: { ...body, comments: [goAhead] } })), { verdict: "refuse", reasons: [NO_SPEC] });
      assert.deepEqual(decide(facts({ spec: { ...body, comments: [written(USER(HUMAN))] } })), { verdict: "admit", reasons: [] });
      // No spec read at all fails closed.
      assert.deepEqual(decide(facts({ spec: undefined })).reasons, [NO_SPEC]);
    });

    test("a task list only inside a code fence is refused, and one after the fence is admitted", () => {
      // A shorter fence line inside a longer fence does not close it.
      for (const [open, inner, close] of [
        ["```", [], "```"],
        ["~~~", ["```"], "~~~"],
        ["````markdown", ["```", "- [ ] Another item."], "````"],
      ]) {
        const fenced = issueOf({ body: ["## Done when", "", open, "- [ ] Line 3 says nineteen.", ...inner, close].join("\n") });
        assert.deepEqual(decide(facts({ issue: fenced })), { verdict: "refuse", reasons: [NO_SPEC] }, open);
        const after = issueOf({ body: [...fenced.body.split("\n"), "", "- [ ] Line 3 says nineteen."].join("\n") });
        assert.deepEqual(decide(facts({ issue: after })), { verdict: "admit", reasons: [] }, open);
      }
    });

    test("admit() writes nothing when the text read answers an unexpected shape", async () => {
      for (const spec of ["no-issue", "no-body"]) {
        const { github, calls } = fakeGitHub({ spec });
        await assert.rejects(
          admit({ github, repository: "o/r", number: 7, verdict: VERDICT, rules: RULES, humans, appId: APP, webHosts: HOSTS, status: async () => ({}), log: () => {} }),
          /unexpected shape/,
        );
        assert.deepEqual(calls.filter((call) => call.method !== "GET" && call.path !== "/graphql"), [], spec);
      }
    });

    test("admit() reads the authors and parks an App-only spec at status: needs-decision for a person", async () => {
      const { github, calls } = fakeGitHub({ issue: appIssue, spec: { ...written(APP_ACTOR), comments: [] } });
      const result = await admit({ github, repository: "o/r", number: 7, verdict: VERDICT, rules: RULES, humans, appId: APP, webHosts: HOSTS, status: async () => assert.fail("a refusal reads no status"), log: () => {} });
      assert.deepEqual(result, { outcome: "refused", reasons: [APP_FILED, NO_SPEC], status: NEEDS_DECISION });
      const writes = calls.filter((call) => call.method !== "GET" && call.path !== "/graphql").map((call) => `${call.method} ${call.path}`);
      assert.deepEqual(writes, ["POST /repos/o/r/issues/7/labels", "DELETE /repos/o/r/issues/7/labels/status%3A%20ready", "POST /repos/o/r/issues/7/comments"]);
      assert.deepEqual(calls.find((call) => call.method === "POST" && call.path.endsWith("/labels")).body, { labels: [NEEDS_DECISION] });
    });

    test("a body line opening with Hold: refuses the issue for a person, and Hold: inside a line does not", () => {
      for (const line of ["Hold: a human merges this", "  hold: wait for the release", "HOLD: owner review"]) {
        const result = decide(facts({ issue: issueOf({ body: `${BODY}\n\n${line}` }) }));
        assert.deepEqual(result, { verdict: "refuse", reasons: ["a line of its body opens with `Hold:`, a person's hold; removing that line lifts it"], hold: true }, line);
      }
      assert.deepEqual(decide(facts({ issue: issueOf({ body: `${BODY}\n\nNo \`Hold:\` line here.` }) })), { verdict: "admit", reasons: [] });
    });
  });

  test("admits a clear Task that meets every criterion", () => {
    assert.deepEqual(decide(facts()), { verdict: "admit", reasons: [] });
  });

  // Owner decision Q85 (#9668): the work class gates nothing.
  test("admits a structural class, a class outside `classes` and no class", () => {
    for (const workClass of ["work-class: structural", "work-class: anything-goes", null]) {
      assert.deepEqual(decide(facts({ verdict: { ...VERDICT, workClass } })), { verdict: "admit", reasons: [] }, String(workClass));
    }
  });

  // The hold is a constant of decide, so no rules file loadRules accepts
  // lifts it, one whose `classes` names the class included.
  test("no admission rules loadRules accepts make untrusted-provenance work admissible", () => {
    const dir = tempDir("admit-rules-");
    const widened = [
      { ...RULES, classes: [...RULES.classes, UNTRUSTED_CLASS] },
      { ...RULES, classes: [UNTRUSTED_CLASS], "refuse-labels": [], sizes: ["small", "medium", "large"], uncertainty: ["known", "knowable", "unknown"] },
    ];
    widened.forEach((content, index) => {
      const path = join(dir, `rules-${index}.json`);
      writeFileSync(path, JSON.stringify(content));
      const rules = loadRules(path);
      for (const overrides of [{ verdict: { ...VERDICT, workClass: UNTRUSTED_CLASS } }, { issue: issueOf({ labels: [{ name: READY }, { name: UNTRUSTED_CLASS }] }) }]) {
        const result = decide(facts({ rules, ...overrides }));
        assert.equal(result.verdict, "refuse", path);
        assert.equal(result.hold, true, path);
        assert.match(result.reasons.join(), /untrusted-provenance work needs a person/, path);
      }
    });
  });

  // The work-unblock sweep re-admits a deferred issue on no verdict comment,
  // so what changed since its newest admission-deferred add refuses.
  describe("a deferred issue re-admitted with no fresh verdict", () => {
    const DEFERRED_AT = "2026-10-20T09:00:00Z";
    const event = (kind, name, id, at) => ({ event: kind, label: { name }, actor: { id }, created_at: at });
    const deferredAdd = event("labeled", DEFERRED, APP, DEFERRED_AT);
    const deferredIssue = (...more) => issueOf({ labels: [{ name: READY }, { name: DEFERRED }, ...more.map((name) => ({ name }))] });
    const SECURITY = "area: security was added after it was deferred, so the admission it was deferred from did not judge it";
    const EDITED = "its body was edited after it was deferred, so the admission it was deferred from judged an older body";

    test("admits a deferred issue nothing changed on", () => {
      assert.deepEqual(decide(facts({ issue: deferredIssue(), events: [deferredAdd] })), { verdict: "admit", reasons: [] });
    });

    test("refuses for a person a deferred issue that now carries do-not-merge, needs-human or the hold class, whatever the rules say", () => {
      const bare = { ...RULES, "refuse-labels": [] };
      for (const [label, reason] of [
        ["do-not-merge", "it carries do-not-merge"],
        ["needs-human", "it carries needs-human"],
        [UNTRUSTED_CLASS, `${UNTRUSTED_CLASS} work needs a person`],
      ]) {
        for (const rules of [RULES, bare]) {
          assert.deepEqual(decide(facts({ rules, issue: deferredIssue(label), events: [deferredAdd] })), { verdict: "refuse", reasons: [reason], hold: true }, label);
        }
      }
      const removed = [deferredAdd, event("labeled", UNTRUSTED_CLASS, APP, DEFERRED_AT), event("unlabeled", UNTRUSTED_CLASS, OUTSIDER, "2026-10-20T10:00:00Z")];
      assert.deepEqual(decide(facts({ issue: deferredIssue(), events: removed })), { verdict: "refuse", reasons: [`${UNTRUSTED_CLASS} work needs a person`], hold: true });
    });

    test("a deferred issue that lost status: ready lapses, and decide skips it", () => {
      const lost = issueOf({ labels: [{ name: DEFERRED }] });
      assert.deepEqual(deferralLapsed({ labels: lost.labels, events: [deferredAdd], editedAt: null, humans, appId: APP }), [
        { reason: `it lost ${READY} while deferred`, kind: "not-ready", hold: false },
      ]);
      assert.deepEqual(deferralLapsed({ labels: deferredIssue().labels, events: [deferredAdd], editedAt: null, humans, appId: APP }), []);
      assert.deepEqual(decide(facts({ issue: lost, events: [deferredAdd] })), { verdict: "skip", reasons: [`no ${READY}`] });
    });

    test("refuses for a person a deferred issue that gained area: security after its deferral", () => {
      const after = [deferredAdd, event("labeled", "area: security", HUMAN, "2026-10-20T10:00:00Z")];
      assert.deepEqual(decide(facts({ issue: deferredIssue("area: security"), events: after })), { verdict: "refuse", reasons: [SECURITY], hold: true });
      const before = [event("labeled", "area: security", HUMAN, "2026-10-20T08:00:00Z"), deferredAdd];
      assert.deepEqual(decide(facts({ issue: deferredIssue("area: security"), events: before })), { verdict: "admit", reasons: [] });
    });

    test("refuses a deferred issue whose body was edited after its deferral", () => {
      const issue = deferredIssue();
      const editedAt = (at) => ({ ...written(USER(HUMAN), { body: issue.body, editor: USER(HUMAN), lastEditedAt: at }), comments: [] });
      assert.deepEqual(decide(facts({ issue, events: [deferredAdd], spec: editedAt("2026-10-20T10:00:00Z") })), { verdict: "refuse", reasons: [EDITED] });
      assert.deepEqual(decide(facts({ issue, events: [deferredAdd], spec: editedAt("2026-10-20T08:00:00Z") })), { verdict: "admit", reasons: [] });
    });

    test("a fresh verdict judges the security area and the body itself", () => {
      const issue = deferredIssue("area: security");
      const events = [deferredAdd, event("labeled", "area: security", HUMAN, "2026-10-20T10:00:00Z")];
      const spec = { ...written(USER(HUMAN), { body: issue.body, editor: USER(HUMAN), lastEditedAt: "2026-10-20T10:00:00Z" }), comments: [] };
      const verdict = { ...VERDICT, writtenAt: "2026-10-20T11:00:00Z" };
      assert.deepEqual(decide(facts({ issue, events, spec, verdict })), { verdict: "admit", reasons: [] });
    });
  });

  test("an issue row in patch-rules.json that refuses no protected path fails admission closed", () => {
    const dir = tempDir("admit-patch-rules-");
    for (const row of [{ refuse: [] }, { refuse: ["symlink", "gitlink"] }, {}]) {
      const path = join(dir, "patch-rules.json");
      writeFileSync(path, JSON.stringify({ [PATCH_ROW]: row }));
      assert.throws(() => pushRefusalsOf(path), /row refuses no protected path/, JSON.stringify(row));
    }
    assert.ok(issuePushRefusals().length > 0);
  });

  test("an untrusted-provenance label removed by neither a listed human nor the App still refuses", () => {
    const event = (kind, id) => ({ event: kind, label: { name: "work-class: untrusted-provenance" }, actor: { id } });
    const refused = decide(facts({ events: [event("labeled", APP), event("unlabeled", OUTSIDER)] }));
    assert.equal(refused.verdict, "refuse");
    assert.match(refused.reasons.join(), /untrusted-provenance work needs a person/);
    for (const remover of [HUMAN, APP]) {
      assert.deepEqual(decide(facts({ events: [event("labeled", APP), event("unlabeled", remover)] })), { verdict: "admit", reasons: [] }, String(remover));
    }
  });

  test("admits Uncertainty Knowable, which the lane researches first", () => {
    const verdict = { ...VERDICT, dimensions: { ...VERDICT.dimensions, uncertainty: "knowable" } };
    assert.deepEqual(decide(facts({ verdict })), { verdict: "admit", reasons: [] });
  });

  const refusals = [
    ["criterion 2: a type the rules do not list", { issue: issueOf({ type: { name: "Epic" } }) }, /type Epic/],
    ["criterion 2: an issue with no type", { issue: issueOf({ type: null }) }, /type none/],
    [
      "criterion 2: a Feature under a parent no listed human filed",
      {
        issue: issueOf({ type: { name: "Feature" } }),
        parent: { state: "open", user: { id: OUTSIDER }, labels: [] },
      },
      /parent/,
    ],
    [
      "criterion 2: a Feature under a parent still awaiting a decision",
      {
        issue: issueOf({ type: { name: "Feature" } }),
        parent: {
          state: "open",
          user: { id: HUMAN },
          labels: [{ name: NEEDS_DECISION }],
        },
      },
      /parent/,
    ],
    [
      "criterion 3: Uncertainty Unknown",
      {
        verdict: {
          ...VERDICT,
          dimensions: { ...VERDICT.dimensions, uncertainty: "unknown" },
        },
      },
      /Uncertainty unknown/,
    ],
    ["criterion 3: untrusted-provenance work", { verdict: { ...VERDICT, workClass: "work-class: untrusted-provenance" } }, /untrusted-provenance work needs a person/],
    [
      "criterion 3: an untrusted-provenance label on the issue",
      { issue: issueOf({ labels: [{ name: READY }, { name: "work-class: untrusted-provenance" }] }) },
      /untrusted-provenance work needs a person/,
    ],
    ["criterion 7: no task list to check", { issue: issueOf({ body: "Make the README better." }) }, /no trusted-human acceptance criteria: .*confirmed `- \[ \]` criteria/],
    [
      "criterion 8: a duplicate label",
      {
        issue: issueOf({
          labels: [{ name: READY }, { name: "duplicate" }],
        }),
      },
      /duplicate/,
    ],
    ["criterion 9: an author who is not listed", { issue: issueOf({ user: { id: OUTSIDER } }) }, /author/],
    [
      "a lane-runnable done-when: a Windows-host criterion (#9287)",
      { issue: issueOf({ body: CANARY }) },
      /item 2 \(a run on a host the lane is not: "Run \/machine-health:audit on a Windows 11 host.*recommended split/,
    ],
  ];
  for (const [name, input, reason] of refusals) {
    test(`refuses on ${name}`, () => {
      const result = decide(facts(input));
      assert.equal(result.verdict, "refuse");
      assert.match(result.reasons.join("; "), reason);
    });
  }

  // #9372: intake's split never edits the body, so it stays the listed
  // human's text; the split refinement alone takes the person-only item out.
  describe("intake's split refinement", () => {
    const issue = issueOf({ body: CANARY });
    const SPLIT = { exact: true, outcome: "Line 9 says 27 checks.", criteria: [], dependencies: [], related: [], questions: [], sources: [], split: [2], external: { state: "none", repo: "", class: "", what: "" } };
    const splitRefinement = (body = CANARY, items = [2], extra = {}) => {
      const output = validateOutput({ ...SPLIT, split: items }, new Set(), { count: 3, items: items.map((n) => ({ n })) });
      return written(APP_ACTOR, { body: render(output, { body, checks: ["- [ ] a check"], retriage: true }), ...extra });
    };
    const held = (spec) => {
      const result = decide(facts({ issue, spec }));
      assert.equal(result.verdict, "refuse");
      assert.equal(result.hold, true);
      assert.match(result.reasons.join("; "), /item 2 \(a run on a host the lane is not/);
    };

    test("admits the human's untouched body once the refinement lists the item a person runs", () => {
      const spec = humanSpec(issue, [splitRefinement()]);
      assert.deepEqual(decide(facts({ issue, spec })), { verdict: "admit", reasons: [] });
      assert.equal(spec.body, CANARY, "the body is as its author wrote it");
      assert.deepEqual(personChecks(spec, humans, APP, RULES["task-list"]), [2]);
    });

    test("holds the item again when the record does not stand", () => {
      held(humanSpec(issue, [splitRefinement(`${CANARY}\n- [ ] Added since.`)]));
      held(humanSpec(issue, [splitRefinement(undefined, undefined, { editor: APP_ACTOR })]));
      held(humanSpec(issue, [splitRefinement(), written(APP_ACTOR, { body: `${REFINE_MARKER}\n${bodyVersion(CANARY)}\nA newer one.` })]));
      held(humanSpec(issue, [written(USER(OUTSIDER), { body: splitRefinement().body })]));
    });

    test("never drops a runnable criterion: the items must be exactly the ones the lane cannot perform", () => {
      for (const items of [[1], [2, 3], [1, 2]]) {
        const result = decide(facts({ issue, spec: humanSpec(issue, [splitRefinement(undefined, items)]) }));
        assert.equal(result.verdict, "refuse", `items ${items}`);
        assert.equal(result.hold, true);
      }
      const all = written(APP_ACTOR, { body: `${REFINE_MARKER}\n${bodyVersion(CANARY)}\n${splitItemsLine([1, 2, 3])}` });
      assert.deepEqual(personChecks(humanSpec(issue, [all]), humans, APP, RULES["task-list"]), [], "a record leaving no item for the lane");
    });

    test("a body another account last edited stays untrusted, the record with it", () => {
      const spec = { ...written(USER(HUMAN), { body: CANARY, editor: APP_ACTOR }), comments: [splitRefinement()] };
      assert.deepEqual(personChecks(spec, humans, APP, RULES["task-list"]), []);
      const result = decide(facts({ issue, spec }));
      assert.equal(result.verdict, "refuse");
      assert.match(result.reasons.join("; "), /no trusted-human acceptance criteria/);
    });

    test("a size split leaves the item a person runs out of its parts", () => {
      const { lines } = splitTaskLines(humanSpec(issue, [splitRefinement()]), humans, RULES["task-list"], APP, HOSTS);
      assert.deepEqual(lines, [CANARY.split("\n")[2], CANARY.split("\n")[4]]);
    });

    test("a size split keeps every item the lane can perform, whatever the record names", () => {
      const all = CANARY.split("\n").filter((row) => row.startsWith("- [ ]"));
      for (const items of [[1], [1, 2], [2, 3]]) {
        const { lines } = splitTaskLines(humanSpec(issue, [splitRefinement(undefined, items)]), humans, RULES["task-list"], APP, HOSTS);
        assert.deepEqual(lines, all, `items ${items}`);
      }
    });

    test("a split row anywhere but the App's counted refinement excuses nothing", () => {
      const row = `${REFINE_MARKER}\n${bodyVersion(CANARY)}\n${splitItemsLine([2])}`;
      held(humanSpec(issueOf({ body: `${CANARY}\n${splitItemsLine([2])}` }), []));
      held({ ...written(USER(HUMAN), { body: `${row}\n${CANARY}` }), comments: [] });
      held(humanSpec(issue, [written(USER(HUMAN), { body: row })]));
    });

    test("a record holds only under the configured web hosts: an item they make runnable stays the lane's", () => {
      const body = [CANARY.split("\n")[0], "", "- [ ] Line 3 says nineteen.", "- [ ] Confirm https://example.com/page says nineteen."].join("\n");
      const spec = humanSpec(issueOf({ body }), [splitRefinement(body, [2])]);
      assert.deepEqual(personChecks(spec, humans, APP, RULES["task-list"], []), [2]);
      assert.deepEqual(personChecks(spec, humans, APP, RULES["task-list"], ["example.com"]), []);
      assert.deepEqual(personChecks(spec, humans, APP, RULES["task-list"], "any"), []);
    });
  });

  // Owner Q93 settled Size Large without a person: the split happens at intake,
  // so the issue parks at status: ready (a wait with no pull request).
  test("Size Large parks the issue for the intake split instead of refusing it", () => {
    const result = decide(facts({ verdict: { ...VERDICT, dimensions: { ...VERDICT.dimensions, size: "large" } } }));
    assert.deepEqual(result, { verdict: "wait", reasons: ["Size large: the split into sub-issues at intake is pending (owner Q93)"], pulls: [] });
  });

  test("Size Large beside a real refusal reason still refuses, and names both", () => {
    const result = decide(facts({ issue: issueOf({ user: { id: OUTSIDER } }), verdict: { ...VERDICT, dimensions: { ...VERDICT.dimensions, size: "large" } } }));
    assert.equal(result.verdict, "refuse");
    assert.match(result.reasons.join("; "), /author.*Size large/);
  });

  test("admits an issue whose title and body name a path under .github/ or docs/conventions/", () => {
    const result = decide(
      facts({
        issue: issueOf({
          title: "fix docs/conventions/pr-pipeline.yaml",
          body: `${BODY}\n\nAlso edit \`.github/workflows/x.yml\` and \`.claude/settings.json\`.`,
        }),
      }),
    );
    assert.deepEqual(result, { verdict: "admit", reasons: [] });
  });

  test("admits a Feature with no parent", () => {
    const result = decide(facts({ issue: issueOf({ type: { name: "Feature" } }), parent: null }));
    assert.deepEqual(result, { verdict: "admit", reasons: [] });
  });

  test("refuses a Feature, parent or not, once the rules no longer list it", () => {
    const rules = { ...RULES, "types-parent-if-present": [] };
    const issue = issueOf({ type: { name: "Feature" } });
    for (const parent of [null, { state: "open", user: { id: HUMAN }, labels: [] }]) {
      const result = decide(facts({ issue, rules, parent }));
      assert.equal(result.verdict, "refuse");
      assert.match(result.reasons.join(), /type Feature is not one of/);
    }
  });

  test("admits a Feature under an open parent a listed human filed", () => {
    const result = decide(
      facts({
        issue: issueOf({ type: { name: "Feature" } }),
        parent: { state: "open", user: { id: HUMAN }, labels: [] },
      }),
    );
    assert.equal(result.verdict, "admit");
  });

  test("waits, with no hold, on criterion 8: an open blocker", () => {
    const result = decide(facts({ blockers: [{ number: 5, state: "open" }] }));
    assert.equal(result.verdict, "wait");
    assert.match(result.reasons.join(), /#5/);
  });

  test("waits on criterion 8: an open pull request for it", () => {
    const result = decide(facts({ pulls: [12] }));
    assert.equal(result.verdict, "wait");
    assert.deepEqual(result.pulls, [12]);
    assert.match(result.reasons.join(), /#12/);
  });

  // The fixture repository's issue; a cross-reference as the REST timeline reports it.
  const ref = (issue) => ({
    event: "cross-referenced",
    source: { issue: { number: 12, state: "open", pull_request: {}, repository_url: "https://api.github.com/repos/o/r", body: "", ...issue } },
  });
  const closer = (number, nameWithOwner = "o/r") => ({ number, repository: { nameWithOwner } });

  test("an open pull request is for the issue when GitHub says it closes it or its body has a Refs line", () => {
    assert.deepEqual(openPullsNaming([], "o/r", 7, [closer(12)]), [12]);
    assert.deepEqual(openPullsNaming([ref({ body: "No related issue.\r\nRefs: #7\r\n" })], "o/r", 7), [12]);
    assert.deepEqual(openPullsNaming([ref({ number: 13, body: "Refs: #7" })], "o/r", 7, [closer(12), closer(13)]), [12, 13]);
  });

  test("a passing mention, another issue's Refs line, a closed or another repository's pull request is not for the issue", () => {
    const timeline = [
      ref({ body: "Follows the approach in #7." }),
      ref({ number: 13, body: "Refs: #70" }),
      ref({ number: 14, body: "Refs: #7, see the thread" }),
      ref({ number: 15, state: "closed", body: "Refs: #7" }),
      ref({ number: 16, body: "Refs: #7", repository_url: "https://api.github.com/repos/o/other" }),
      ref({ number: 17, pull_request: undefined, body: "Refs: #7" }),
    ];
    assert.deepEqual(openPullsNaming(timeline, "o/r", 7, [closer(18, "o/other")]), []);
  });

  const completed = { number: 5, state: "closed", state_reason: "completed", repository_url: "https://api.github.com/repos/o/r" };
  test("a blocker closed as completed with a trusted close does not hold it", () => {
    const result = decide(facts({ blockers: [completed], trustedCloses: new Set([5]) }));
    assert.equal(result.verdict, "admit");
  });

  test("a blocker closed as completed without a trusted close holds it", () => {
    const result = decide(facts({ blockers: [completed] }));
    assert.equal(result.verdict, "wait");
    assert.match(result.reasons.join(), /#5 is not closed by a listed human or a merge/);
  });

  // A blocker closed as not planned or a duplicate leaves nothing to wait
  // for; the close still has to be a listed human's or a merge's.
  for (const reason of ["not_planned", "duplicate"]) {
    test(`a blocker closed as ${reason} with a trusted close does not hold it; without one it does`, () => {
      const blocker = { ...completed, state_reason: reason };
      assert.equal(decide(facts({ blockers: [blocker], trustedCloses: new Set([5]) })).verdict, "admit");
      assert.equal(decide(facts({ blockers: [blocker] })).verdict, "wait");
    });
  }

  test("another repository's blocker counts only on its own trusted close, never this repository's same number", () => {
    const other = { ...completed, repository_url: "https://api.github.com/repos/o/other" };
    assert.equal(decide(facts({ blockers: [other], trustedCloses: new Set(["o/other#5"]) })).verdict, "admit");
    const result = decide(facts({ blockers: [other], trustedCloses: new Set([5]) }));
    assert.equal(result.verdict, "wait");
    assert.match(result.reasons.join(), /blocker o\/other#5 is not closed/);
  });

  test("the refusal comment names the reasons and asks no one to add agent-ready by hand", () => {
    const text = refusalText("Size large is not one of small, medium");
    assert.match(text, /^Not admitted to the issue lane: Size large is not one of small, medium\. /);
    assert.doesNotMatch(text, /agent-ready/);
  });

  // A standing recurring item links to its schedule row by `[Maintenance] {title}`.
  describe("a recurring item whose schedule row needs an operator", () => {
    const row = (id, precondition) => ({ id, title: "Re-run the ablation", cadence: "quarterly", ...(precondition && { precondition }) });
    const recurring = issueOf({ title: "[Maintenance] Re-run the ablation", labels: [{ name: READY }, { name: "recurring" }] });
    const CONFIRM = "its recurring schedule row ablation needs an operator's confirmation (requires_operator_confirmation)";

    test("is refused when its row sets requires_operator_confirmation", () => {
      const schedule = { items: [row("ablation", { id: "frontier-release-since-last-checked", requires_operator_confirmation: true })] };
      assert.deepEqual(decide(facts({ issue: recurring, schedule })), { verdict: "refuse", reasons: [CONFIRM] });
    });

    test("is admitted when its row has no such flag, or no row matches its title", () => {
      for (const items of [[row("ablation")], [row("ablation", { id: "x", requires_operator_confirmation: false })], [{ ...row("other"), title: "Something else" }], []]) {
        assert.deepEqual(decide(facts({ issue: recurring, schedule: { items } })), { verdict: "admit", reasons: [] }, JSON.stringify(items));
      }
    });

    test("is refused when the schedule could not be read", () => {
      for (const schedule of [null, undefined, { rows: [] }]) {
        const result = decide(facts({ issue: recurring, schedule }));
        assert.equal(result.verdict, "refuse", String(schedule));
        assert.match(result.reasons.join(), /recurring-schedule\.json could not be read/);
      }
      // Without the recurring label nothing is read.
      assert.deepEqual(decide(facts({ schedule: null })), { verdict: "admit", reasons: [] });
    });

    test("readSchedule answers null for a missing or malformed file and reads the default branch's schedule", () => {
      assert.equal(readSchedule(fileURLToPath(new URL("./no-such-schedule.json", import.meta.url))), null);
      assert.equal(readSchedule(fileURLToPath(new URL("./admit.mjs", import.meta.url))), null);
      assert.ok(Array.isArray(readSchedule().items));
    });
  });

  // apply-patch refuses these paths on the issue row (patch-rules.json), so a
  // run for a criterion that names one ends at patch-protected-path.
  describe("a criterion naming a path the issue lane cannot push", () => {
    const withCriteria = (...lines) => issueOf({ body: ["## Problem", "", "Basis: `.github/workflows/a.yml:3`", "", "## Done when", "", ...lines].join("\n") });
    const pushReason = (path) => `a criterion names ${path}, which the issue lane cannot push (patch-protected-path); a builder session takes it`;

    const refused = [
      // #9398's criterion.
      ["- [ ] The check-plugins job in .github/workflows/pr-require-checks.yml still has timeout-minutes: 3", ".github/workflows/pr-require-checks.yml"],
      ["- [ ] `.github/workflows/x.yml:12` reads the new input.", ".github/workflows/x.yml"],
      ["- [ ] .github/CODEOWNERS names the team.", ".github/CODEOWNERS"],
      ["- [ ] CODEOWNERS names the team.", "CODEOWNERS"],
      ["- [ ] .GITMODULES drops the old submodule.", ".GITMODULES"],
      // #9113's criterion: a bare name of a workflow on disk.
      ["- [ ] pr-require-checks.yml pins that ci-workflows release.", ".github/workflows/pr-require-checks.yml"],
      ["- [ ] `pr-test-windows.yml:94` reads the new output.", ".github/workflows/pr-test-windows.yml"],
      ["- [ ] pr-require-checks.yml is unchanged.", ".github/workflows/pr-require-checks.yml"],
    ];
    for (const [line, path] of refused) {
      test(`refuses, with no hold, on ${line}`, () => {
        const issue = withCriteria(line);
        assert.deepEqual(decide(facts({ issue })), { verdict: "refuse", reasons: [pushReason(path)] });
      });
    }

    test("refuses on a path a criterion wraps onto an indented continuation line", () => {
      const issue = withCriteria("- [ ] Update the permissions in", "  .github/workflows/a.yml for the new job.");
      assert.deepEqual(decide(facts({ issue })), { verdict: "refuse", reasons: [pushReason(".github/workflows/a.yml")] });
    });

    test("admits a criterion whose nested bullet cites a protected path as evidence", () => {
      for (const bullet of ["  - Basis: .github/workflows/pr-require-checks.yml:40", "  * see .github/CODEOWNERS", "  1. .gitmodules lists it"]) {
        const issue = withCriteria("- [ ] The job times out at 3 minutes.", bullet);
        assert.deepEqual(decide(facts({ issue })), { verdict: "admit", reasons: [] }, bullet);
      }
    });

    const evasions = [
      ["a case change", "- [ ] `.GitHub/Workflows/a.yml` reads the new input.", ".GitHub/Workflows/a.yml"],
      ["a case change in .gitmodules", "- [ ] `.GITMODULES` drops the old submodule.", ".GITMODULES"],
      ["a case change in a bare workflow name", "- [ ] PR-Require-Checks.yml pins that release.", ".github/workflows/PR-Require-Checks.yml"],
      ["a missing leading dot", "- [ ] github/workflows/a.yml reads the new input.", "github/workflows/a.yml"],
      ["a missing leading dot on .gitmodules", "- [ ] `vendor/gitmodules` drops the old submodule.", "vendor/gitmodules"],
      ["fullwidth characters", "- [ ] ．github／workflows／a.yml reads the new input.", ".github/workflows/a.yml"],
      ["zero-width characters", "- [ ] .git​hub/work⁠flows/a﻿.yml reads the new input.", ".github/workflows/a.yml"],
      ["URL encoding", "- [ ] %2Egithub%2Fworkflows%2Fa.yml reads the new input.", ".github/workflows/a.yml"],
      ["fullwidth percent signs", "- [ ] ％2Egithub％2Fworkflows％2Fa.yml reads the new input.", ".github/workflows/a.yml"],
      ["zero-width characters in the task-list prefix", "​- [ ]​ .github/workflows/a.yml reads the new input.", ".github/workflows/a.yml"],
      ["a case change in a root CODEOWNERS", "- [ ] `codeowners` names the team.", "codeowners"],
      ["a root .gitmodules without its dot", "- [ ] `gitmodules` drops the old submodule.", "gitmodules"],
    ];
    for (const [name, line, path] of evasions) {
      test(`still refuses a protected path written with ${name}`, () => {
        assert.deepEqual(decide(facts({ issue: withCriteria(line) })), { verdict: "refuse", reasons: [pushReason(path)] });
      });
    }

    test("still refuses a protected path in a code fence under a criterion, past its blank and bullet-like lines", () => {
      const issue = withCriteria("- [ ] Apply this change:", "  ```diff", "  - timeout-minutes: 3", "", "  + see .github/workflows/a.yml", "  ```");
      assert.deepEqual(decide(facts({ issue })), { verdict: "refuse", reasons: [pushReason(".github/workflows/a.yml")] });
    });

    const admitted = [
      // #9137's shape.
      "- [ ] `babysit_merge.py` merges on a green head, with tests in `tests/test_babysit_merge.py`.",
      "- [ ] `plugins/x/cases/y/settings.json` sets the model.",
      "- [ ] settings.json keeps its key.",
      // #9092's: a bare .yml name no workflow on disk has.
      "- [ ] No pr-test-macos.yml is added.",
      "- [ ] The runner no longer writes /__w/_temp/.claude/settings.json or /__w/r/r/.base/.github/workflows/a.yml:1.",
      // A root name in prose, outside backticks, names no file.
      "- [ ] The codeowners check reports the missing team.",
      "- [ ] Codeowners review is requested.",
      "- [ ] The gitmodules parser skips comments.",
    ];
    for (const line of admitted) {
      test(`admits ${line}`, () => {
        const issue = withCriteria(line);
        assert.deepEqual(decide(facts({ issue })), { verdict: "admit", reasons: [] });
      });
    }

    // A title names the subject, not the change: #8682 and #9054 named an
    // existing workflow in theirs and changed only scripts.
    test("admits an issue whose title alone names an existing workflow", () => {
      const issue = { ...withCriteria("- [ ] Line 3 says nineteen."), title: "ci: move the macOS planning job out of pr-test-windows.yml" };
      assert.deepEqual(decide(facts({ issue })), { verdict: "admit", reasons: [] });
    });

    test("reads the row apply-patch pushes an issue lane patch under", () => {
      assert.equal(PATCH_ROW, TARGETS.issue.row(""));
    });

    test("turns an otherwise admissible issue into a refusal that parks at status: confirmed", () => {
      const issue = withCriteria("- [ ] Line 3 says nineteen.", "- [ ] `.gitmodules` drops the old submodule.");
      const result = decide(facts({ issue }));
      assert.equal(decide(facts({ issue: withCriteria("- [ ] Line 3 says nineteen.") })).verdict, "admit");
      assert.equal(result.verdict, "refuse");
      assert.equal(result.hold, undefined);
      assert.deepEqual(result.reasons, [pushReason(".gitmodules")]);
    });
  });

  // rule-admit.sh's fixed checks: its charge words, read from one definition,
  // and its body-edited-after-the-verdict refusal.
  describe("a charge word in the title or body", () => {
    const CHARGE = /names a charge \(([^)]+)\), which needs an owner decision/;

    test("refuses and holds for a person, naming each word once", () => {
      for (const [issue, words] of [
        [issueOf({ body: `${BODY}\n\nMove the job to larger runners and a paid Azure SKU. Larger runners are faster.` }), "larger runners, sku"],
        [issueOf({ title: "chore: raise the Actions spending limit" }), "spending limit"],
      ]) {
        const result = decide(facts({ issue }));
        assert.equal(result.verdict, "refuse");
        assert.equal(result.hold, true);
        assert.equal(CHARGE.exec(result.reasons.join("; "))?.[1], words);
      }
    });

    // docs/contracts/loop-lane/README.md: model usage under the
    // Claude subscriptions is not cost; a plan or seat change and a paid
    // purchase are.
    test("holds only for a charge the owner's cost list names", () => {
      assert.deepEqual(decide(facts({ issue: issueOf({ body: `${BODY}\n\nThe lane runs on the subscription login.` }) })), { verdict: "admit", reasons: [] });
      assert.deepEqual(chargeHits("Each lane signs in with its subscription logins.", chargePattern()), []);
      assert.deepEqual(chargeHits("The lane spends Claude subscription usage.", chargePattern()), []);
      for (const [body, words] of [
        ["This needs a plan or seat change.", "seat"],
        ["This needs a paid subscription purchase.", "subscription"],
        ["Create a new Azure subscription for the lane.", "subscription"],
        ["Reduce the Azure subscription usage.", "subscription"],
        ["Upgrade the Claude subscription to a higher plan.", "subscription"],
        ["Buy a new Claude subscription for the lane.", "subscription"],
        ["The lane raises Copilot subscription usage-based pricing.", "subscription"],
      ]) {
        const result = decide(facts({ issue: issueOf({ body: `${BODY}\n\n${body}` }) }));
        assert.equal(result.hold, true);
        assert.equal(CHARGE.exec(result.reasons.join("; "))?.[1], words);
      }
    });

    test("an issue that names no charge is still admitted", () => {
      assert.deepEqual(decide(facts({ issue: issueOf({ body: `${BODY}\n\nThe sweep deletes runs older than a week.` }) })), { verdict: "admit", reasons: [] });
    });

    // Code names a job or file, not a charge; prose still refuses.
    test("skips fenced blocks and inline code spans", () => {
      const hits = (body, extra = {}) => CHARGE.exec(decide(facts({ issue: issueOf({ body: `${BODY}\n\n${body}` }), ...extra })).reasons.join("; "))?.[1];
      assert.equal(hits("The `fix-ci-subscription` job fails on main."), undefined);
      assert.equal(hits("Fix the step:\n\n```yaml\n- uses: actions/upload-artifact@v4\n  with:\n    retention-days: 5\n```"), undefined);
      assert.equal(hits("The `fix-ci-subscription` job needs a paid subscription."), "subscription");
      assert.equal(hits("Move the `lint` leg to larger runners.", { public: true }), "larger runners");
      assert.equal(hits("Move the `lint` leg to larger GitHub-hosted runners.", { public: true }), "larger github-hosted runners");
      // A fence is a whole line: ``` inside a line neither opens nor closes one.
      assert.equal(hits('```yaml\nmessage: "```"\n```\n\nBuy a paid subscription.\n\n```yaml\nretention-days: 5\n```'), "subscription");
      assert.equal(hits("````\n```\nretention-days: 5\n````\n\n~~~\nretention-days: 5\n~~~~"), undefined);
      // Web-typed bodies end lines in CRLF; a fence line ending in \r still closes.
      assert.equal(hits("```yaml\r\nretention-days: 5\r\n```\r\n\r\n~~~\r\nretention-days: 5\r\n~~~\r\n"), undefined);
      assert.equal(hits('```yaml\r\nmessage: "```"\r\n```\r\n\r\nBuy a paid subscription.\r\n\r\n```yaml\r\nretention-days: 5\r\n```'), "subscription");
      // A bare identifier still refuses: excluding words joined by - _ / . would
      // also drop prose such as per-seat billing or data-retention.
      assert.deepEqual(chargeHits("We pay per-seat; data-retention grows.", chargePattern()), ["seat", "retention"]);
    });

    // Standard GitHub-hosted runner minutes are free only on a public
    // repository (https://docs.github.com/en/billing/concepts/product-billing/github-actions).
    test("a hosted runner refuses unless the repository is public", () => {
      const body = `${BODY}\n\nThe check runs on GitHub-hosted runners.`;
      assert.deepEqual(decide(facts({ issue: issueOf({ body }), public: true })), { verdict: "admit", reasons: [] });
      for (const extra of [{ public: false }, {}]) {
        assert.equal(CHARGE.exec(decide(facts({ issue: issueOf({ body }), ...extra })).reasons.join("; "))?.[1], "hosted runners");
      }
    });

    test("admissionFacts counts a repository public only when its visibility reads public", async () => {
      const read = async (answer) => {
        const fake = fakeGitHub();
        const github = async (method, path, body) => (method === "GET" && path === "/repos/o/r" ? answer() : fake.github(method, path, body));
        return (await admissionFacts({ github, repository: "o/r", number: 7, issue: issueOf(), rules: RULES, humans, isTrusted: async () => true })).public;
      };
      assert.equal(await read(() => ({ visibility: "public" })), true);
      assert.equal(await read(() => ({ visibility: "internal" })), false);
      assert.equal(await read(() => Promise.reject(new Error("GET /repos/o/r failed"))), false);
    });

    // rule-admit.test.sh shows the script reads the same file.
    test("reads the patterns from the one definition rule-admit.sh reads", () => {
      const shared = JSON.parse(readFileSync(new URL("../../../plugins/work-items/scripts/charge-words.json", import.meta.url), "utf8"));
      const { code, cost, costPrivate } = chargePattern();
      assert.deepEqual([code.source, cost.source, costPrivate.source], [shared.code, shared.cost, shared.cost_private].map((p) => new RegExp(p).source));
      assert.deepEqual(chargeHits("Turn on auto-renewal for the Codespaces plan.", chargePattern()), ["auto-renewal", "codespaces"]);
    });
  });

  describe("a body edited after the triage verdict", () => {
    const at = (writtenAt) => ({ ...VERDICT, writtenAt });
    const editedAt = (lastEditedAt) => ({ ...humanSpec(issueOf()), editor: USER(HUMAN), lastEditedAt });
    const EDITED = "its body was edited after the triage verdict, which judged the body as it stood before";

    test("refuses at status: confirmed, as no person must answer it", () => {
      const result = decide(facts({ verdict: at("2026-10-22T12:05:00Z"), spec: editedAt("2026-10-22T12:06:00Z") }));
      assert.deepEqual(result, { verdict: "refuse", reasons: [EDITED] });
    });

    test("a body never edited, or edited before the verdict, is still admitted", () => {
      for (const spec of [humanSpec(issueOf()), editedAt("2026-10-22T12:04:59Z"), editedAt("2026-10-22T12:05:00Z")]) {
        assert.deepEqual(decide(facts({ verdict: at("2026-10-22T12:05:00Z"), spec })), { verdict: "admit", reasons: [] });
      }
    });

    test("a verdict time that does not parse refuses; the sweep, which passes none, is not judged on it", () => {
      assert.deepEqual(decide(facts({ verdict: at("soon"), spec: humanSpec(issueOf()) })).reasons, [EDITED]);
      assert.equal(decide(facts({ spec: editedAt("2026-10-22T12:06:00Z") })).verdict, "admit");
    });

    test("admit() reads the edit time and parks the issue at status: confirmed", async () => {
      const fake = fakeGitHub({ spec: editedAt("2026-10-22T12:06:00Z") });
      const result = await admit({ ...goArgs(fake), verdict: at("2026-10-22T12:05:00Z"), status: async () => assert.fail("a refusal reads no status") });
      assert.deepEqual(result, { outcome: "refused", reasons: [EDITED], status: CONFIRMED });
      assert.ok(!writes(fake.calls).some((line) => line.includes(AGENT_READY)), "no agent-ready label");
    });
  });

  test("skips an issue already agent-ready, or without status: ready", () => {
    assert.equal(
      decide(
        facts({
          issue: issueOf({
            labels: [{ name: READY }, { name: AGENT_READY }],
          }),
        }),
      ).verdict,
      "skip",
    );
    assert.equal(decide(facts({ issue: issueOf({ labels: [] }) })).verdict, "skip");
  });

  test("skips an issue whose agent-ready someone removed before", () => {
    const result = decide(
      facts({
        events: [{ event: "unlabeled", label: { name: AGENT_READY } }],
      }),
    );
    assert.equal(result.verdict, "skip");
  });

  // A removal bars admission only until triage or a listed human marks the
  // issue ready again after it.
  describe("an agent-ready removal and a later status: ready", () => {
    const removed = (at) => ({ event: "unlabeled", label: { name: AGENT_READY }, actor: { id: HUMAN }, created_at: at });
    const marked = (at, id = APP) => ({ event: "labeled", label: { name: READY }, actor: { id }, created_at: at });
    const verdictFor = (events) => decide(facts({ events })).verdict;

    test("a removal with no later status: ready skips", () => {
      assert.equal(verdictFor([marked("2026-10-20T00:00:00Z"), removed("2026-10-21T00:00:00Z")]), "skip");
    });
    test("a removal then a later status: ready is decided", () => {
      assert.equal(verdictFor([removed("2026-10-20T00:00:00Z"), marked("2026-10-21T00:00:00Z")]), "admit");
      assert.equal(verdictFor([removed("2026-10-20T00:00:00Z"), marked("2026-10-21T00:00:00Z", HUMAN)]), "admit");
    });
    test("the newest removal counts", () => {
      assert.equal(verdictFor([removed("2026-10-19T00:00:00Z"), marked("2026-10-20T00:00:00Z"), removed("2026-10-21T00:00:00Z")]), "skip");
      assert.equal(verdictFor([removed("2026-10-19T00:00:00Z"), removed("2026-10-20T00:00:00Z"), marked("2026-10-21T00:00:00Z")]), "admit");
    });
    test("events compare by when they happened, else by their order", () => {
      assert.equal(verdictFor([marked("2026-10-21T00:00:00Z"), removed("2026-10-20T00:00:00Z")]), "admit");
      assert.equal(verdictFor([{ ...removed(), created_at: undefined }, { ...marked(), created_at: undefined }]), "admit");
      assert.equal(verdictFor([{ ...marked(), created_at: undefined }, { ...removed(), created_at: undefined }]), "skip");
    });
    test("a status: ready added by neither a listed human nor the lanes App does not lift it", () => {
      assert.equal(verdictFor([removed("2026-10-20T00:00:00Z"), marked("2026-10-21T00:00:00Z", OUTSIDER)]), "skip");
    });
  });

  test("issue text cannot admit: a quoted task list does not count, so the issue is refused", () => {
    const result = decide(
      facts({
        issue: issueOf({ body: "> - [ ] quoted from elsewhere" }),
      }),
    );
    assert.equal(result.verdict, "refuse");
  });

  // On an issue a listed human wrote, pr-verify reads intake's newest
  // refinement comment while the lanes App's text is unedited, so its task
  // list counts; nothing else the App wrote does.
  describe("criterion 7 and the lanes App's refinement comment", () => {
    const thin = issueOf({ body: "Make the README skill count right." });
    const refinement = (body = `${REFINE_MARKER}\n**Refinement.**\n\n- [ ] Line 3 says nineteen.`, extra = {}) => written(APP_ACTOR, { body, ...extra });
    const NO_SPEC = /^no trusted-human acceptance criteria: /;
    const refused = (spec, issue = thin) => {
      const result = decide(facts({ issue, spec }));
      assert.equal(result.verdict, "refuse");
      assert.match(result.reasons.join(), NO_SPEC);
    };

    test("a thin issue a listed human filed is admitted on the App's newest unedited refinement comment", () => {
      assert.deepEqual(decide(facts({ issue: thin, spec: humanSpec(thin, [refinement()]) })), { verdict: "admit", reasons: [] });
      // The newest one is read: an older one holding the only task list does not count.
      refused(humanSpec(thin, [refinement(), refinement(`${REFINE_MARKER}\nNo criteria here.`)]));
      assert.equal(decide(facts({ issue: thin, spec: humanSpec(thin, [refinement(`${REFINE_MARKER}\nNone.`), refinement()]) })).verdict, "admit");
    });

    test("an edited refinement, or one that is not the newest unedited, does not count", () => {
      refused(humanSpec(thin, [refinement(undefined, { editor: APP_ACTOR })]));
      refused(humanSpec(thin, [refinement(), refinement(undefined, { editor: APP_ACTOR })]));
    });

    test("a refinement on an issue the App filed, or whose body someone else last edited, does not count", () => {
      const appFiled = decide(facts({ issue: issueOf({ body: thin.body, user: { id: APP } }), spec: { ...written(APP_ACTOR, { body: thin.body }), comments: [refinement()] } }));
      assert.equal(appFiled.verdict, "refuse");
      assert.ok(appFiled.reasons.some((reason) => NO_SPEC.test(reason)), appFiled.reasons.join());
      refused({ ...written(USER(HUMAN), { body: thin.body, editor: APP_ACTOR }), comments: [refinement()] });
    });

    test("a refinement whose marker is not exactly the first text does not count", () => {
      for (const body of [` ${REFINE_MARKER}\n- [ ] x`, `${REFINE_MARKER.toUpperCase()}\n- [ ] x`, `- [ ] x\n${REFINE_MARKER}`, `${ADMIT_MARKER}\n- [ ] x`]) {
        refused(humanSpec(thin, [refinement(body)]));
      }
    });

    test("a marked comment by anyone but the lanes App does not count as a refinement", () => {
      for (const author of [{ __typename: "Bot", databaseId: 41898282 }, USER(OUTSIDER), { __typename: "User", databaseId: APP }]) {
        refused(humanSpec(thin, [written(author, { body: `${REFINE_MARKER}\n- [ ] Line 3 says nineteen.` })]));
      }
      // Without the App's id nothing it wrote counts.
      const result = decide(facts({ issue: thin, appId: undefined, spec: humanSpec(thin, [refinement()]) }));
      assert.match(result.reasons.join(), NO_SPEC);
    });

    test("a listed human's comment carrying the confirmed criteria admits the thin issue", () => {
      const confirmed = written(USER(HUMAN), { body: "Confirmed:\n\n- [ ] Line 3 says nineteen." });
      assert.deepEqual(decide(facts({ issue: thin, spec: humanSpec(thin, [refinement(), confirmed]) })), { verdict: "admit", reasons: [] });
    });

    test("a rendered refinement a listed human posts as their own is still checked for pages outside the lane's web hosts", () => {
      const output = { exact: true, outcome: "Match the spec.", criteria: ["The page at https://example.org/spec says nineteen."], dependencies: [], related: [], questions: [], sources: [], split: [], external: { state: "none", repo: "", class: "", what: "" } };
      const body = render(validateOutput(output, new Set()));
      assert.ok(!body.includes("https://"), "the rendered comment breaks the URL");
      const result = decide(facts({ issue: thin, spec: humanSpec(thin, [written(USER(HUMAN), { body })]) }));
      assert.equal(result.verdict, "refuse");
      assert.match(result.reasons.join(), /example\.org/);
    });

    test("criteria past the comments read do not count: more comments than read is a refusal", () => {
      const spec = { ...humanSpec(thin, [written(USER(HUMAN))]), commentCount: 150 };
      const result = decide(facts({ issue: thin, spec }));
      assert.equal(result.verdict, "refuse");
      assert.match(result.reasons.join(), /150 comments, more than the 100 pr-verify reads/);
      assert.equal(decide(facts({ issue: thin, spec: { ...spec, commentCount: 1 } })).verdict, "admit");
    });

    for (const [name, author] of [
      ["github-actions[bot]", { __typename: "Bot", databaseId: 41898282 }],
      ["an outsider", USER(OUTSIDER)],
      ["the App", APP_ACTOR],
    ]) {
      test(`a task list from ${name} does not count`, () => {
        const result = decide(facts({ issue: thin, spec: humanSpec(thin, [written(author)]) }));
        assert.equal(result.verdict, "refuse");
        assert.match(result.reasons.join(), NO_SPEC);
      });
    }
  });
});

// A fake GitHub for admit(): the issue, its parent, blockers, timeline,
// events and comments, recording every call.
// `spec` is what SPEC_QUERY answers (by default the issue's body as a listed
// human wrote it); "no-issue" and "no-body" answer an unexpected shape.
// `closing` is what closedByPullRequestsReferences answers.
// `elsewhere` answers another repository's issue reads by path; `older` is
// the count the older-deferred search answers, or "incomplete". `closer` is
// what the closing-event query answers. Label writes on the issue land in its
// labels and events, which the issues listing answers; `racers` are other
// issues it lists, each {number, labels, events}.
function fakeGitHub({ issue = issueOf(), parent = null, blockers = [], closed = {}, elsewhere = {}, older = 0, timeline = [], closing = [], events = [], comments = [], spec, closer, failOn, done = null, racers = [] } = {}) {
  const calls = [];
  const labelsNow = new Set((issue.labels ?? []).map((label) => label.name));
  const eventsNow = [...events];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (failOn?.(method, path, body)) {
      throw new Error(`${method} ${path} failed with status 500`);
    }
    const base = "/repos/o/r/issues/7";
    const mark = (event, name) => eventsNow.push({ event, label: { name }, actor: { id: APP }, created_at: new Date().toISOString() });
    if (method === "POST" && path === `${base}/labels`) {
      for (const name of body.labels) {
        labelsNow.add(name);
        mark("labeled", name);
      }
    }
    if (method === "DELETE" && path.startsWith(`${base}/labels/`)) {
      const name = decodeURIComponent(path.slice(`${base}/labels/`.length));
      labelsNow.delete(name);
      mark("unlabeled", name);
    }
    if (method === "GET" && path.startsWith("/repos/o/r/issues?")) {
      const label = new URLSearchParams(path.split("?")[1]).get("labels");
      const own = labelsNow.has(label) ? [{ number: 7 }] : [];
      return [...own, ...racers.filter((racer) => racer.labels.includes(label)).map(({ number }) => ({ number }))];
    }
    const racer = /^\/repos\/o\/r\/issues\/(\d+)\/events/.exec(path);
    if (method === "GET" && racer && racer[1] !== "7") {
      return racers.find((item) => String(item.number) === racer[1])?.events ?? [];
    }
    if (method === "POST" && path === "/graphql") {
      // mergedRefsPulls' batch: `done` is the fixture issue as DONE_QUERY reads it.
      if (body.query.includes("fragment done on Issue")) {
        return { data: { repository: { i7: done } } };
      }
      if (body.query.includes("closedByPullRequestsReferences")) {
        const refs = { nodes: closing, pageInfo: { hasNextPage: false, endCursor: null } };
        return { data: { repository: { issue: { closedByPullRequestsReferences: refs } } } };
      }
      if (body.query.includes("ClosedEvent")) {
        return { data: { repository: { issue: { timelineItems: { nodes: closer ? [{ closer }] : [] } } } } };
      }
      if (spec === "no-issue") {
        return { data: { repository: { issue: null } } };
      }
      const answer = spec === "no-body" ? { ...humanSpec(issue), body: null } : (spec ?? humanSpec(issue));
      return { data: { repository: { issue: { ...answer, comments: { totalCount: answer.totalCount ?? answer.comments.length, nodes: answer.comments } } } } };
    }
    if (method !== "GET") {
      return null;
    }
    if (path === base) {
      return issue;
    }
    if (path === `${base}/parent`) {
      if (parent === null) {
        const error = new Error("No parent issue found");
        error.status = 404;
        throw error;
      }
      return parent;
    }
    if (path.startsWith(`${base}/dependencies/blocked_by`)) {
      return blockers;
    }
    const blocker = path.match(/^\/repos\/o\/r\/issues\/(\d+)$/);
    if (blocker && closed[blocker[1]]) {
      return closed[blocker[1]];
    }
    if (Object.hasOwn(elsewhere, path)) {
      return elsewhere[path];
    }
    if (path.startsWith("/search/issues?")) {
      return older === "incomplete" ? { total_count: 0, incomplete_results: true, items: [] } : { total_count: older, incomplete_results: false, items: [] };
    }
    if (path.startsWith(`${base}/timeline`)) {
      return timeline;
    }
    if (path.startsWith(`${base}/events`)) {
      return [...eventsNow];
    }
    if (path.startsWith(`${base}/comments`)) {
      return comments;
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  return { github, calls };
}
const open = {
  paused: false,
  admission_open: true,
  admission_room: 3,
  admission_reason: null,
};
const goArgs = (fake, { status = open } = {}) => ({
  github: fake.github,
  repository: "o/r",
  number: 7,
  verdict: VERDICT,
  rules: RULES,
  humans,
  appId: APP,
  webHosts: HOSTS,
  status: async () => status,
  log: () => {},
});
const go = (fake, options) => admit(goArgs(fake, options));
// The GraphQL reads are POSTs but write nothing.
const writes = (calls) => calls.filter((call) => call.method !== "GET" && call.path !== "/graphql").map(({ method, path, body }) => `${method} ${path} ${JSON.stringify(body)}`);

describe("admit", () => {
  // Under a cap the issue claims its place with admission-deferred before it
  // takes agent-ready.
  const CLAIMED = [
    `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [DEFERRED] })}`,
    `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [AGENT_READY] })}`,
    `DELETE /repos/o/r/issues/7/labels/${DEFERRED} undefined`,
  ];

  test("adds agent-ready when every criterion holds and the caps have room", async () => {
    const fake = fakeGitHub();
    const result = await go(fake);
    assert.equal(result.outcome, "admitted");
    assert.deepEqual(writes(fake.calls), CLAIMED);
  });

  // A manual re-dispatch skips intake-reenter, so the parked status comes off here.
  test("adds agent-ready and lifts a parked status: confirmed beside status: ready", async () => {
    const fake = fakeGitHub({ issue: issueOf({ labels: [{ name: READY }, { name: CONFIRMED }, { name: "work-class: mechanical" }] }) });
    const result = await go(fake);
    assert.equal(result.outcome, "admitted");
    assert.deepEqual(writes(fake.calls), [...CLAIMED, `DELETE /repos/o/r/issues/7/labels/${encodeURIComponent(CONFIRMED)} undefined`]);
  });

  // Parallel apply-verdict runs for other issues read the same room: only
  // those that entered admission first, up to that room, take agent-ready.
  describe("parallel admissions under one room", () => {
    const ago = (minutes) => new Date(Date.now() - minutes * 60_000).toISOString();
    const entered = (number, label, minutes) => ({ number, labels: [label], events: [{ event: "labeled", label: { name: label }, actor: { id: APP }, created_at: ago(minutes) }] });
    const ROOM_ONE = { ...open, admission_room: 1 };

    test("an issue another run claimed the last room ahead of stays deferred, never agent-ready", async () => {
      for (const racer of [entered(8, DEFERRED, 1), entered(8, AGENT_READY, 1)]) {
        const fake = fakeGitHub({ racers: [racer] });
        const result = await go(fake, { status: ROOM_ONE });
        assert.equal(result.outcome, "deferred", racer.labels[0]);
        assert.match(result.reasons[0], /1 issue\(s\) entered admission ahead of it/);
        assert.deepEqual(writes(fake.calls), [`POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [DEFERRED] })}`], racer.labels[0]);
      }
    });

    test("an issue that claimed ahead of a later racer takes the room", async () => {
      const later = { ...entered(8, DEFERRED, 0), events: [{ event: "labeled", label: { name: DEFERRED }, actor: { id: APP }, created_at: new Date(Date.now() + 60_000).toISOString() }] };
      const fake = fakeGitHub({ racers: [later] });
      assert.equal((await go(fake, { status: ROOM_ONE })).outcome, "admitted");
      assert.deepEqual(writes(fake.calls), CLAIMED);
    });

    test("two issues fit a room of two, and an entry before the race window does not count", async () => {
      assert.equal((await go(fakeGitHub({ racers: [entered(8, AGENT_READY, 1)] }), { status: { ...open, admission_room: 2 } })).outcome, "admitted");
      assert.equal((await go(fakeGitHub({ racers: [entered(8, AGENT_READY, 1), entered(9, DEFERRED, 2)] }), { status: { ...open, admission_room: 2 } })).outcome, "deferred");
      assert.equal((await go(fakeGitHub({ racers: [entered(8, DEFERRED, RACE_WINDOW_MS / 60_000 + 5)] }), { status: ROOM_ONE })).outcome, "admitted");
    });

    test("a racing read that fails keeps the claim and admits nothing", async () => {
      const fake = fakeGitHub({ failOn: (method, path) => method === "GET" && path.startsWith("/repos/o/r/issues?") });
      const result = await go(fake, { status: ROOM_ONE });
      assert.equal(result.outcome, "deferred");
      assert.match(result.reasons[0], /could not be read/);
      assert.deepEqual(writes(fake.calls), [`POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [DEFERRED] })}`]);
    });

    test("an issue already deferred claims afresh, so a racer reads its new place", async () => {
      const fake = fakeGitHub({ issue: issueOf({ labels: [{ name: READY }, { name: DEFERRED }, { name: "work-class: mechanical" }] }), events: [{ event: "labeled", label: { name: DEFERRED }, actor: { id: APP }, created_at: ago(120) }] });
      assert.equal((await go(fake, { status: ROOM_ONE })).outcome, "admitted");
      assert.deepEqual(writes(fake.calls), [`DELETE /repos/o/r/issues/7/labels/${DEFERRED} undefined`, ...CLAIMED]);
    });

    // An issue's place is its newest claim in the window, so one re-claimed
    // after another run's read sorts after that run, whatever it added earlier.
    test("admissionsSince keys each entry by its newest claim, else its first agent-ready add, in the window", async () => {
      const since = Date.parse("2026-10-30T10:00:00Z");
      const add = (name, at) => ({ event: "labeled", label: { name }, actor: { id: APP }, created_at: at });
      const lists = { [AGENT_READY]: [{ number: 3 }, { number: 4, pull_request: {} }, { number: 8 }], [DEFERRED]: [{ number: 2 }, { number: 3 }, { number: 5 }, { number: 6 }, { number: 7 }] };
      const events = {
        2: [add(DEFERRED, "2026-10-30T10:02:00Z")],
        3: [add(DEFERRED, "2026-10-30T09:00:00Z"), add(DEFERRED, "2026-10-30T10:01:00Z"), add(AGENT_READY, "2026-10-30T10:03:00Z")],
        5: [add(DEFERRED, "2026-10-30T09:59:59Z"), add("other", "2026-10-30T10:00:30Z")],
        6: [add(DEFERRED, "2026-10-30T10:00:10Z"), add(DEFERRED, "2026-10-30T10:05:00Z")],
        7: [],
        8: [add(DEFERRED, "2026-10-30T09:00:00Z"), add(AGENT_READY, "2026-10-30T10:04:00Z"), add(AGENT_READY, "2026-10-30T10:06:00Z")],
      };
      const github = async (method, path) => {
        if (path.startsWith("/repos/o/r/issues?")) {
          return lists[new URLSearchParams(path.split("?")[1]).get("labels")];
        }
        return events[/issues\/(\d+)\/events/.exec(path)[1]];
      };
      assert.deepEqual(await admissionsSince(github, "o/r", since), [
        { number: 7, at: null },
        { number: 3, at: Date.parse("2026-10-30T10:01:00Z") },
        { number: 2, at: Date.parse("2026-10-30T10:02:00Z") },
        { number: 8, at: Date.parse("2026-10-30T10:04:00Z") },
        { number: 6, at: Date.parse("2026-10-30T10:05:00Z") },
      ]);
    });

    test("admissionsAhead counts a tie and an unread add ahead, and every other entry when its own add is unread", () => {
      const entered = [
        { number: 9, at: null },
        { number: 3, at: 100 },
        { number: 7, at: 200 },
        { number: 2, at: 200 },
        { number: 5, at: 300 },
      ];
      assert.equal(admissionsAhead(entered, 7), 3);
      assert.equal(admissionsAhead(entered, 2), 3);
      assert.equal(admissionsAhead(entered, 3), 1);
      assert.equal(admissionsAhead([{ number: 7, at: null }, { number: 3, at: 100 }], 7), 1);
      assert.equal(admissionsAhead([{ number: 3, at: 100 }], 7), 1);
      assert.equal(admissionsAhead([], 7), 0);
    });
  });

  // refine.mjs starts the size split only from this exact wait comment.
  test("the Size Large wait comment admit() posts is the one refine.mjs splits on", async () => {
    const fake = fakeGitHub();
    const result = await admit({ ...goArgs(fake), verdict: { ...VERDICT, dimensions: { ...VERDICT.dimensions, size: "large" } } });
    assert.equal(result.outcome, "waiting");
    const posted = fake.calls.filter((call) => call.method !== "GET" && /\/comments(\/\d+)?$/.test(call.path)).map((call) => call.body.body);
    assert.equal(posted.length, 1);
    assert.equal(sizeSplitPending([{ user: { id: APP }, body: posted[0] }], APP), true);
  });

  const feature = issueOf({ type: { name: "Feature" } });

  test("a Feature with no parent is admitted through the real fetch path", async () => {
    const fake = fakeGitHub({ issue: feature });
    assert.equal((await go(fake)).outcome, "admitted");
    assert.ok(fake.calls.some((call) => call.path === "/repos/o/r/issues/7/parent"), "the parent was looked up");
  });

  for (const [name, parent] of [
    ["an outsider filed", { state: "open", user: { id: OUTSIDER }, labels: [] }],
    ["awaits a decision", { state: "open", user: { id: HUMAN }, labels: [{ name: NEEDS_DECISION }] }],
    ["is closed", { state: "closed", user: { id: HUMAN }, labels: [] }],
  ]) {
    test(`a Feature whose parent ${name} is refused through the real fetch path`, async () => {
      const fake = fakeGitHub({ issue: feature, parent });
      const result = await go(fake);
      assert.equal(result.outcome, "refused");
      assert.ok(fake.calls.some((call) => call.path === "/repos/o/r/issues/7/parent"), "the parent was looked up");
      assert.ok(!writes(fake.calls).some((line) => line.startsWith("POST /repos/o/r/issues/7/labels") && line.includes(AGENT_READY)), "no agent-ready label");
    });
  }

  const full = [
    [
      "the queued cap is reached",
      {
        ...open,
        admission_open: false,
        admission_room: 0,
        admission_reason: "queued",
      },
    ],
    ["the WIP or held cap paused the lane", { ...open, paused: true, pause_reason: "held-cap" }],
    [
      "the search answered incomplete results",
      {
        ...open,
        admission_open: false,
        admission_room: 0,
        admission_reason: "search-incomplete",
      },
    ],
    // On a failed queued read check-wip-cap leaves admissions open, room null.
    ["check-wip-cap could not read the queued count", { ...open, admission_room: null, admission_basis: "fail-open" }],
  ];
  for (const [name, status] of full) {
    test(`defers, never agent-ready, when ${name}`, async () => {
      const fake = fakeGitHub();
      const result = await go(fake, { status });
      assert.equal(result.outcome, "deferred");
      assert.deepEqual(writes(fake.calls), [`POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [DEFERRED] })}`]);
    });
  }

  // With wip.pause-from empty check-wip-cap leaves admissions open with room
  // null even over the queued cap, so clearing it removes intake's cap.
  test("adds agent-ready over the queued cap when wip.pause-from is empty", async () => {
    const fake = fakeGitHub();
    const result = await go(fake, { status: { ...open, admission_room: null, admission_basis: "read" } });
    assert.equal(result.outcome, "admitted");
    assert.deepEqual(writes(fake.calls), [`POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [AGENT_READY] })}`]);
  });

  test("a mechanical refusal swaps status: ready for status: confirmed and posts the reason", async () => {
    const fake = fakeGitHub({
      issue: issueOf({ body: "Make the README better." }),
    });
    const result = await go(fake);
    assert.equal(result.outcome, "refused");
    const done = writes(fake.calls);
    assert.equal(done.length, 3);
    assert.equal(done[0], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [CONFIRMED] })}`);
    assert.match(done[1], /^DELETE \/repos\/o\/r\/issues\/7\/labels\/status%3A%20ready/);
    assert.match(done[2], /^POST \/repos\/o\/r\/issues\/7\/comments /);
    assert.ok(done[2].includes(ADMIT_MARKER.replaceAll('"', '\\"')));
    assert.match(done[2], /no trusted-human acceptance criteria/);
  });

  test("a Windows-host done-when item stays out of the lane: needs-decision, which refine splits from, and a recommended split, never agent-ready", async () => {
    const fake = fakeGitHub({ issue: issueOf({ body: CANARY }) });
    const result = await go(fake);
    assert.equal(result.outcome, "refused");
    const done = writes(fake.calls);
    assert.ok(!done.some((call) => call.includes("/labels ") && call.includes(AGENT_READY)));
    assert.equal(done[0], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [NEEDS_DECISION] })}`);
    assert.match(done[1], /^DELETE \/repos\/o\/r\/issues\/7\/labels\/status%3A%20ready/);
    assert.match(done[2], /item 2 .*Windows 11 host.*recommended split: keep the other items here .* a child issue for the host queue \(`host-run`\)/);
  });

  test("a refusal that needs a person swaps status: ready for needs-decision", async () => {
    const fake = fakeGitHub({ issue: issueOf({ labels: [{ name: READY }, { name: "work-class: untrusted-provenance" }] }) });
    const result = await go(fake);
    assert.equal(result.outcome, "refused");
    const done = writes(fake.calls);
    assert.equal(done[0], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [NEEDS_DECISION] })}`);
    assert.match(done[1], /^DELETE \/repos\/o\/r\/issues\/7\/labels\/status%3A%20ready/);
  });

  test("a refusal with a person reason among mechanical ones still sets needs-decision", async () => {
    const fake = fakeGitHub({ issue: issueOf({ body: "Make the README better.", labels: [{ name: READY }, { name: "work-class: untrusted-provenance" }] }) });
    const result = await go(fake);
    assert.equal(result.outcome, "refused");
    assert.match(result.reasons.join(), /no trusted-human acceptance criteria/);
    assert.equal(writes(fake.calls)[0], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [NEEDS_DECISION] })}`);
  });

  test("a refusal whose status: confirmed write fails keeps status: ready, so admission-deferred never stands alone", async () => {
    const failOn = (method, path, body) => method === "POST" && path.endsWith("/labels") && body?.labels?.includes(CONFIRMED);
    const fake = fakeGitHub({ issue: issueOf({ body: "Make the README better.", labels: [{ name: READY }, { name: DEFERRED }] }), failOn });
    await assert.rejects(() => go(fake), /failed with status 500/);
    assert.ok(!writes(fake.calls).some((call) => call.startsWith("DELETE ")), writes(fake.calls).join("\n"));
  });

  test("an issue with more comments than the text read covers is refused, as pr-verify stops on it", async () => {
    const result = await go(fakeGitHub({ spec: { ...humanSpec(issueOf()), totalCount: 101 } }));
    assert.equal(result.outcome, "refused");
    assert.match(result.reasons.join(), /101 comments, more than the 100 pr-verify reads/);
  });

  test("a refusal edits the App's earlier admission comment instead of adding one", async () => {
    const fake = fakeGitHub({
      issue: issueOf({ body: "Make the README better." }),
      comments: [
        {
          id: 31,
          body: `${ADMIT_MARKER}\nold`,
          user: { login: "melodic-automation-lanes[bot]" },
        },
      ],
    });
    await go(fake);
    assert.match(writes(fake.calls).at(-1), /^PATCH \/repos\/o\/r\/issues\/comments\/31 /);
  });

  test("a thin issue a listed human filed is admitted on the App's refinement alone or on a listed human's confirmed criteria", async () => {
    const thin = issueOf({ body: "Make the README skill count right." });
    const refinement = written(APP_ACTOR, { body: `${REFINE_MARKER}\n- [ ] Line 3 says nineteen.` });
    const refined = await go(fakeGitHub({ issue: thin, spec: humanSpec(thin, [refinement]) }));
    assert.equal(refined.outcome, "admitted");
    const edited = await go(fakeGitHub({ issue: thin, spec: humanSpec(thin, [{ ...refinement, editor: APP_ACTOR, lastEditedAt: "2026-10-20T00:00:00Z" }]) }));
    assert.equal(edited.outcome, "refused");
    const confirmed = await go(fakeGitHub({ issue: thin, spec: humanSpec(thin, [refinement, written(USER(HUMAN), { body: "- [ ] Line 3 says nineteen." })]) }));
    assert.equal(confirmed.outcome, "admitted");
  });

  test("an open blocker posts the reason and keeps status: ready", async () => {
    const fake = fakeGitHub({ blockers: [{ number: 5, state: "open" }] });
    const result = await go(fake);
    assert.equal(result.outcome, "waiting");
    const done = writes(fake.calls);
    assert.equal(done.length, 1);
    assert.match(done[0], /^POST \/repos\/o\/r\/issues\/7\/comments /);
  });

  test("an open pull request that closes it adds admission-deferred, so the sweep revisits it", async () => {
    const fake = fakeGitHub({ closing: [{ number: 12, state: "OPEN", repository: { nameWithOwner: "o/r" } }] });
    const result = await go(fake);
    assert.equal(result.outcome, "waiting");
    const done = writes(fake.calls);
    assert.equal(done[0], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [DEFERRED] })}`);
    assert.match(done[1], /^POST \/repos\/o\/r\/issues\/7\/comments .*open pull request #12/);
  });

  test("a merged or closed pull request GitHub still lists as closing it does not hold it", async () => {
    for (const state of ["MERGED", "CLOSED"]) {
      const result = await go(fakeGitHub({ closing: [{ number: 12, state, repository: { nameWithOwner: "o/r" } }] }));
      assert.equal(result.outcome, "admitted", state);
    }
  });

  test("an open pull request that only mentions it does not defer it", async () => {
    const mention = { event: "cross-referenced", source: { issue: { number: 12, state: "open", pull_request: {}, repository_url: "https://api.github.com/repos/o/r", body: "Like #7." } } };
    const result = await go(fakeGitHub({ timeline: [mention] }));
    assert.equal(result.outcome, "admitted");
  });

  test("a blocker its own outside author closed as completed keeps it waiting; a listed human's close admits it", async () => {
    const blocker = { number: 5, state: "closed", state_reason: "completed", repository_url: "https://api.github.com/repos/o/r" };
    const closedBy = (id) => ({ 5: { ...blocker, closed_by: { id } } });
    const outsider = await go(fakeGitHub({ blockers: [blocker], closed: closedBy(OUTSIDER) }));
    assert.equal(outsider.outcome, "waiting");
    assert.match(outsider.reasons.join(), /#5/);
    const human = await go(fakeGitHub({ blockers: [blocker], closed: closedBy(HUMAN) }));
    assert.equal(human.outcome, "admitted");
  });

  test("a blocker closed as not planned admits it on a listed human's close and keeps it waiting on an outsider's", async () => {
    const blocker = { number: 5, state: "closed", state_reason: "not_planned", repository_url: "https://api.github.com/repos/o/r" };
    const closedBy = (id) => ({ 5: { ...blocker, closed_by: { id } } });
    assert.equal((await go(fakeGitHub({ blockers: [blocker], closed: closedBy(HUMAN) }))).outcome, "admitted");
    assert.equal((await go(fakeGitHub({ blockers: [blocker], closed: closedBy(OUTSIDER) }))).outcome, "waiting");
  });

  test("another repository's closed blocker is read there: a listed human's close admits it, an outsider's or an unreadable one keeps it waiting", async () => {
    const blocker = { number: 5, state: "closed", state_reason: "completed", repository_url: "https://api.github.com/repos/o/other" };
    const there = (id) => ({ "/repos/o/other/issues/5": { ...blocker, closed_by: { id } } });
    const human = fakeGitHub({ blockers: [blocker], elsewhere: there(HUMAN) });
    assert.equal((await go(human)).outcome, "admitted");
    assert.ok(human.calls.some((call) => call.method === "GET" && call.path === "/repos/o/other/issues/5"));
    assert.equal((await go(fakeGitHub({ blockers: [blocker], elsewhere: there(OUTSIDER) }))).outcome, "waiting");
    const unreadable = await go(fakeGitHub({ blockers: [blocker] }));
    assert.equal(unreadable.outcome, "waiting");
    assert.match(unreadable.reasons.join(), /o\/other#5/);
  });

  test("another repository's blocker closed by a commit or merge there keeps it waiting; here the same close admits it", async () => {
    const blocker = (repo) => ({ number: 5, state: "closed", state_reason: "completed", repository_url: `https://api.github.com/repos/${repo}` });
    const commit = (repo) => ({ __typename: "Commit", repository: { nameWithOwner: repo } });
    const merge = (repo) => ({ __typename: "PullRequest", merged: true, repository: { nameWithOwner: repo } });
    for (const by of [commit, merge]) {
      const there = { "/repos/o/other/issues/5": { ...blocker("o/other"), closed_by: { id: OUTSIDER } } };
      const elsewhere = await go(fakeGitHub({ blockers: [blocker("o/other")], elsewhere: there, closer: by("o/other") }));
      assert.equal(elsewhere.outcome, "waiting");
      assert.match(elsewhere.reasons.join(), /o\/other#5/);
      const own = { 5: { ...blocker("o/r"), closed_by: { id: OUTSIDER } } };
      assert.equal((await go(fakeGitHub({ blockers: [blocker("o/r")], closed: own, closer: by("o/r") }))).outcome, "admitted");
    }
  });

  test("a merged pull request blocker counts only in this repository", () => {
    const merged = (repo) => ({ number: 5, state: "closed", pull_request: { merged_at: "2026-10-24T00:00:00Z" }, repository_url: `https://api.github.com/repos/${repo}` });
    assert.deepEqual(decide(facts({ blockers: [merged("o/r")] })), { verdict: "admit", reasons: [] });
    const elsewhere = decide(facts({ blockers: [merged("o/other")] }));
    assert.equal(elsewhere.verdict, "wait");
    assert.match(elsewhere.reasons.join(), /o\/other#5 is not closed by a listed human or a merge/);
  });

  test("a caller's isTrusted answers only this repository's blockers", async () => {
    const blocker = { number: 5, state: "closed", state_reason: "completed", repository_url: "https://api.github.com/repos/o/other" };
    const fake = fakeGitHub({ blockers: [blocker], elsewhere: { "/repos/o/other/issues/5": { ...blocker, closed_by: { id: OUTSIDER } } } });
    const read = await admissionFacts({ github: fake.github, repository: "o/r", number: 7, issue: issueOf(), rules: RULES, humans, isTrusted: async () => true });
    assert.deepEqual([...read.trustedCloses], []);
  });

  // Owner Q95: admission takes the unblocked frontier oldest first, so a new
  // issue with room still queues behind an older deferred one.
  test("with room, an issue waits behind an older admission-deferred issue, never agent-ready", async () => {
    const fake = fakeGitHub({ older: 1 });
    const result = await go(fake);
    assert.equal(result.outcome, "deferred");
    assert.deepEqual(writes(fake.calls), [`POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [DEFERRED] })}`]);
    const search = fake.calls.find((call) => call.path.startsWith("/search/issues?"));
    const q = new URLSearchParams(search.path.split("?")[1]).get("q");
    assert.equal(q, "repo:o/r is:issue is:open label:admission-deferred created:<2026-10-20T08:00:00+00:00");
  });

  // work-unblock's sweep counts these blockers as decide() does, so such an
  // issue defers like any other and the sweep admits it oldest first.
  test("an issue resting on a not planned, duplicate or other repository's blocker defers behind an older one", async () => {
    const here = (reason) => ({ number: 5, state: "closed", state_reason: reason, repository_url: "https://api.github.com/repos/o/r" });
    for (const reason of ["not_planned", "duplicate", "completed"]) {
      const fake = fakeGitHub({ blockers: [here(reason)], closed: { 5: { ...here(reason), closed_by: { id: HUMAN } } }, older: 1 });
      assert.equal((await go(fake)).outcome, "deferred", reason);
    }
    const other = { ...here("completed"), repository_url: "https://api.github.com/repos/o/other" };
    const elsewhere = fakeGitHub({ blockers: [other], elsewhere: { "/repos/o/other/issues/5": { ...other, closed_by: { id: HUMAN } } }, older: 1 });
    assert.equal((await go(elsewhere)).outcome, "deferred");
  });

  test("with the lane full, an issue resting on a not planned blocker gets admission-deferred", async () => {
    const blocker = { number: 5, state: "closed", state_reason: "not_planned", repository_url: "https://api.github.com/repos/o/r" };
    const fake = fakeGitHub({ blockers: [blocker], closed: { 5: { ...blocker, closed_by: { id: HUMAN } } } });
    const result = await go(fake, { status: { ...open, paused: true, pause_reason: "held-cap" } });
    assert.equal(result.outcome, "deferred");
    assert.deepEqual(writes(fake.calls), ['POST /repos/o/r/issues/7/labels {"labels":["admission-deferred"]}']);
  });

  test("an incomplete or failed older-deferred search defers rather than admits", async () => {
    assert.equal((await go(fakeGitHub({ older: "incomplete" }))).outcome, "deferred");
    const failed = fakeGitHub({ failOn: (_method, path) => path.startsWith("/search/issues?") });
    assert.equal((await go(failed)).outcome, "deferred");
  });

  test("an issue already agent-ready is left alone", async () => {
    const fake = fakeGitHub({
      issue: issueOf({ labels: [{ name: READY }, { name: AGENT_READY }] }),
    });
    const result = await go(fake);
    assert.equal(result.outcome, "skipped");
    assert.deepEqual(writes(fake.calls), []);
  });

  test("a refusal or a wait takes admission-deferred off, so the sweep cannot admit it", async () => {
    const deferred = { name: DEFERRED };
    for (const issue of [
      issueOf({
        body: "Make the README better.",
        labels: [{ name: READY }, deferred],
      }),
      issueOf({ labels: [{ name: READY }, deferred] }),
    ]) {
      const fake = fakeGitHub({
        issue,
        blockers: [{ number: 5, state: "open" }],
      });
      await go(fake);
      assert.ok(writes(fake.calls).includes(`DELETE /repos/o/r/issues/7/labels/${DEFERRED} undefined`));
    }
  });
});


describe("a merged Refs pull request after the newest decision or refinement", () => {
  // The fixture issue as DONE_QUERY reads it: opened 10-20, with `comments` and
  // the pull requests that mention it.
  const node = ({ comments = [], pulls = [] } = {}) => ({
    createdAt: "2026-10-20T08:00:00Z",
    comments: { nodes: comments },
    timelineItems: { nodes: pulls.map((source) => ({ source })) },
  });
  const pull = (overrides = {}) => ({ number: 30, merged: true, mergedAt: "2026-10-27T15:54:34Z", body: "Refs: #7\n\n## Summary", repository: { nameWithOwner: "o/r" }, ...overrides });
  const comment = (author, body, createdAt) => ({ createdAt, body, lastEditedAt: null, author, editor: null });
  const decision = (createdAt) => comment(USER(HUMAN), "**Decision recorded.** Build it as the refinement says.", createdAt);
  const refinement = (createdAt) => comment(APP_ACTOR, `${REFINE_MARKER}\n**Refinement.**`, createdAt);
  const after = (fields) => mergedRefsAfter(node(fields), 7, "o/r", humans, APP);

  test("one merged after the newest decision comment may have done the work", () => {
    assert.deepEqual(after({ comments: [decision("2026-10-25T21:47:04Z")], pulls: [pull()] }), [30]);
  });

  test("one merged before the newest decision or refinement comment did not", () => {
    assert.deepEqual(after({ comments: [decision("2026-10-28T09:00:00Z")], pulls: [pull()] }), []);
    assert.deepEqual(after({ comments: [decision("2026-10-25T21:47:04Z"), refinement("2026-10-28T09:00:00Z")], pulls: [pull()] }), []);
  });

  test("with neither comment, one merged since the issue opened counts", () => {
    assert.deepEqual(after({ pulls: [pull()] }), [30]);
  });

  test("no pull request, or one that is open, another repository's, or only mentions it, is none", () => {
    assert.deepEqual(after(), []);
    assert.deepEqual(
      after({
        pulls: [
          pull({ number: 31, merged: false, mergedAt: null }),
          pull({ number: 32, repository: { nameWithOwner: "o/other" } }),
          pull({ number: 33, body: "Follows the approach in #7." }),
          pull({ number: 34, body: "Closes #8\nRefs: #70" }),
        ],
      }),
      [],
    );
  });

  test("a decision comment someone outside the list wrote, or an outsider edited, moves no cutoff", () => {
    const outsider = comment(USER(OUTSIDER), "**Decision recorded.** Run it again.", "2026-10-28T09:00:00Z");
    const edited = { ...decision("2026-10-28T09:00:00Z"), lastEditedAt: "2026-10-28T10:00:00Z", editor: USER(OUTSIDER) };
    assert.deepEqual(after({ comments: [outsider, edited], pulls: [pull()] }), [30]);
  });

  test("a Refs line names the issue alone, in a list of issues, or with a note after", () => {
    for (const body of ["Refs: #7", "  Refs: #7\r", "Refs: #3, #7", "Refs: #7 (closes once the check is green)"]) {
      assert.equal(refsNames(body, 7), true, body);
    }
    for (const body of ["Refs: #70", "Refs: #7, see the thread", "Refs: o/x#7", "Refs: #1; possible overlap with #7", "See #7"]) {
      assert.equal(refsNames(body, 7), false, body);
    }
  });

  test("admit() parks such an issue at status: confirmed with one comment naming the pull request", async () => {
    const fake = fakeGitHub({ done: node({ comments: [decision("2026-10-25T21:47:04Z")], pulls: [pull()] }) });
    const result = await go(fake);
    assert.equal(result.outcome, "refused");
    assert.equal(result.status, CONFIRMED);
    assert.equal(fake.calls.filter((call) => call.path === "/graphql" && call.body.query.includes("fragment done on Issue")).length, 1);
    assert.deepEqual(writes(fake.calls), [
      `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [CONFIRMED] })}`,
      `DELETE /repos/o/r/issues/7/labels/${encodeURIComponent(READY)} undefined`,
      `POST /repos/o/r/issues/7/comments ${JSON.stringify({ body: `${ADMIT_MARKER}\n${refusalText(doneReason([30]))}` })}`,
    ]);
    assert.match(doneReason([30]), /#30/);
  });

  test("admit() admits one whose Refs pull request merged before its newest decision", async () => {
    const fake = fakeGitHub({ done: node({ comments: [decision("2026-10-28T09:00:00Z")], pulls: [pull()] }) });
    assert.equal((await go(fake)).outcome, "admitted");
    assert.equal(fake.calls.filter((call) => call.path === "/graphql" && call.body.query.includes("fragment done on Issue")).length, 1);
  });

  test("admit() admits one with no pull request", async () => {
    const fake = fakeGitHub({ done: node() });
    assert.equal((await go(fake)).outcome, "admitted");
  });

  test("admit() admits as before when the read fails or answers no repository", async () => {
    const failing = fakeGitHub({ done: node({ pulls: [pull()] }), failOn: (method, path, body) => path === "/graphql" && body.query.includes("fragment done on Issue") });
    const logged = [];
    assert.equal((await admit({ ...goArgs(failing), log: (line) => logged.push(line) })).outcome, "admitted");
    assert.ok(logged.some((line) => line.startsWith("::warning title=admit::merged Refs pull requests not read")), logged.join("\n"));
    const empty = { github: async () => ({ errors: [{ message: "rate limited" }] }) };
    assert.deepEqual(await mergedRefsReader({ ...empty, repository: "o/r", humans, appId: APP, log: () => {} })(7), []);
  });

  test("a pass reads each batch of its issues in one call", async () => {
    const queries = [];
    const github = async (method, path, body) => {
      queries.push(body.query);
      return { data: { repository: { i7: node({ pulls: [pull()] }), i8: node(), i9: node({ pulls: [pull({ number: 40, body: "Refs: #9" })] }) } } };
    };
    const read = mergedRefsReader({ github, repository: "o/r", numbers: [7, 8, 9], humans, appId: APP });
    assert.deepEqual([await read(7), await read(8), await read(9)], [[30], [], [40]]);
    assert.equal(queries.length, 1);
    assert.match(queries[0], /i7: issue\(number: 7\).*i8: issue\(number: 8\).*i9: issue\(number: 9\)/s);
  });
});

describe("unrunnableCriteria", () => {
  const kinds = (line, hosts = HOSTS) => unrunnableCriteria(`- [ ] ${line}`, "- [ ] ", hosts).found.map(({ kind }) => kind);
  const positives = [
    ["a Windows host run", "Run `/machine-health:audit` on a Windows 11 host and confirm 27 results.", /host/],
    ["a macOS machine", "Install the plugin on a macOS machine and see the banner.", /host/],
    ["a WSL box", "The hook fires from a WSL2 box.", /host/],
    ["a paid eval", "Run a paid eval of the skill and record the delta.", /paid eval/],
    ["a plugin eval run", "Run `claude plugin eval` on the suite and the delta is positive.", /paid eval/],
    ["N consecutive runs", "Run the lane 20 consecutive runs without a failure.", /repeated run/],
    ["consecutive runs pass", "Twenty consecutive runs pass on main.", /repeated run/],
    ["a measurement over time", "Monitor the queue for two weeks and confirm no backlog.", /over time/],
    ["after days", "Confirm after 7 days that the cache stays under 1 GB.", /over time/],
    ["a page outside the lane's hosts", "The page at https://example.com/docs shows the new flag.", /example\.com/],
    ["a page an item compares against", "Confirm the table matches https://example.com/page.", /example\.com/],
    // Done-when items from the concise-skills rollout issues (#6584, #6602, #6615).
    ["before and after numbers", "The PR body holds a per-skill decision table, description and body decided separately, with the before and after numbers behind each row.", /paid eval/],
    ["measure-invocation trigger scores", "The PR body shows `/skill-quality:check measure-invocation` trigger scores for the before and the after description on the same probes.", /paid eval/],
    [
      "before and after trigger rates",
      "The PR body carries the before and after trigger rates from held-out probes (`measure-invocation.sh emit-plugin-eval`, run with `--ablation none` on each target model).",
      /paid eval/,
    ],
    ["a plugin-eval delta", "`/evals:plugin-eval` with and without; difference in the PR body.", /paid eval/],
    ["a run of measure-invocation", "Run `measure-invocation.sh` on the new probes and paste the output.", /paid eval/],
    // Live CLI items from #6963, #6758, #6761, #6877 and #9914.
    ["claude -p", 'A comment on this issue records whether the `/usage` report from `claude -p "/usage" --output-format stream-json` carries its rate limits.', /Claude Code CLI/],
    ["a recorded probe", "A recorded probe: a subagent Write into a path covered by a path-scoped rule, with a logging InstructionsLoaded hook.", /Claude Code CLI/],
    ["a named Claude Code version", "A recorded probe answers questions 1 to 3 on a named Claude Code version.", /Claude Code CLI/],
    ["the probe's version", "The monitor guidance states the `-p` behavior with the probe's Claude Code version.", /Claude Code CLI/],
    ["a measured result", "The verified-mechanics row is updated with the measured result and the Claude Code version.", /Claude Code CLI/],
    ["a plugin install", "`claude plugin install testing@melodic-software` exits 0.", /Claude Code CLI/],
    // A comment-only deliverable (#6636).
    ["a comment on this issue", "One comment on this issue with the versions released per plugin over the last 14 days.", /comment instead/],
    ["no file changed", "No file is changed.", /comment instead/],
    ["a result recorded in a comment on this issue", "The script's output is recorded in a comment on this issue.", /comment instead/],
    ["a comment on this issue listing a result (#9735)", "A comment on this issue lists the machines done.", /comment instead/],
    ["a comment on this issue starting with a heading (#7556)", "A comment on this issue starting `Probe result:` records the Cursor version.", /comment instead/],
    // Live CLI items the corpus diff flagged (#7135, #9930).
    ["claude plugin test passing", "`claude plugin test` passes for each touched plugin; skill, eval and drift checks pass.", /Claude Code CLI/],
    ["claude plugin install exiting", "`claude plugin marketplace add \"$PWD\"` and `claude plugin install core@melodic-software` both exit 0.", /Claude Code CLI/],
    ["a run of claude plugin install", "Run `claude plugin install testing@melodic-software` in a fresh config directory.", /Claude Code CLI/],
    ["a headless Claude Code run", "A headless Claude Code session started with the new flag exits 0.", /Claude Code CLI/],
    ["a run result recorded in a comment on this issue (#4281)", "`/instruction-placement:migrate cutover-check` has been run, with its met/unmet output recorded in a comment on this issue.", /comment instead/],
  ];
  for (const [name, line, kind] of positives) {
    test(`flags ${name}`, () => {
      assert.match(kinds(line).join(), kind);
    });
  }
  const negatives = [
    ["a Windows-host criterion named in prose", "A test covers a Windows-host criterion staying out of the lane."],
    ["a host named without a run", "The README says Windows host support is fully implemented."],
    ["the lane's own OS", "Run the script on a Linux host and it exits 0."],
    ["a list that names a paid eval", "Intake's rubric marks a host or OS run, a paid eval, or a loaded multi-run."],
    ["a no-spend eval", "Run `claude plugin eval --validate` on the suite and it passes."],
    ["a failure threshold", "The lane pauses after 3 consecutive failures."],
    ["a retention period", "The sweep deletes files older than 30 days."],
    ["a config duration", "Set `cleanupPeriodDays` to keep transcripts for 30 days."],
    ["a GitHub link", "The PR at https://github.com/o/r/pull/1 links the issue."],
    ["a lane docs host", "The section matches https://code.claude.com/docs/en/hooks."],
    ["a localhost URL", "The server answers on http://localhost:8080/health."],
    ["a URL named as text to edit", "Replace https://example.com in README.md with https://code.claude.com."],
    ["an expiry period", "Verify tokens expire after 30 days."],
    ["a retention setting", "Confirm the config keeps transcripts for 30 days."],
    ["a window naming kept data", "Monitor that transcripts are kept for the next 30 days."],
    ["a window naming retention", "Track retention for the next 30 days."],
    ["a monthly summary", "Monitor the logs for a monthly summary line."],
    ["hourly rollups", "Watch the output for hourly rollups."],
    ["a lane host at a sentence end", "The page matches https://code.claude.com."],
    ["GitHub at a sentence end", "Check the repository at https://github.com."],
    ["a subdomain of a wildcard host", "Confirm the step matches https://docs.example.org/en/actions.", ["*.example.org"]],
    ["a no-spend trigger probe check", "`bash plugins/skill-quality/scripts/measure-invocation.sh validate plugins/tdd/probes` exits 0."],
    ["a dry-run plugin eval", "`/evals:plugin-eval` dry-run reports the cost estimate."],
    ["measure-invocation's own test", "`bash scripts/run-test-file.sh plugins/skill-quality/scripts/measure-invocation.test.sh` exits 0, with a new case."],
    ["a static skill check", "`/skill-quality:check plugins/improvement` on the PR head reports no FAIL that the run on main does not."],
    ["an eval suite validation", "`/evals:validate` passes on `plugins/improvement`'s eval suite at the PR head."],
    ["before and after named as text", "`plugins/review/README.md` states that a PR changing a lane's prompt, model or effort cites a before and after score."],
    ["a headless browser run", "The page makes no network request when opened from `file://` (verified in a browser network panel or a headless run)."],
    ["a probe as one source among docs", "Default, range, and subagent reach are established from docs or a recorded probe."],
    ["claude --version in code", "`precompute.sh` emits a notice when `claude --version` is a newer minor, using fixture strings."],
    ["a path under .claude", "`.claude/settings.json` denies the new command."],
    ["a script posting a comment", "work-unblock posts a comment on the issue saying why."],
    ["a code comment", "A code comment in `admit.mjs` explains the new kind."],
    ["a PR body line", "The PR body says which items moved."],
    ["a file change limit", "No file outside `plugins/tdd` is changed."],
    ["a file change limit worded as no file is changed outside", "No file is changed outside `plugins/tdd`."],
    ["a file change limit under a path", "No file is changed under .github/."],
    ["a script posting a comment on this issue", "work-unblock posts a comment on this issue saying why."],
    ["claude plugin install shown in a README", "The README's install section shows `claude plugin install testing@melodic-software`."],
    ["claude plugin install named in a file", "The marketplace.json entry installs with `claude plugin install x`."],
    ["measure-invocation score", "`bash plugins/skill-quality/scripts/measure-invocation.sh score plugins/tdd/probes` exits 0."],
    ["measure-invocation compare", "`measure-invocation.sh compare baseline.json treatment.json` reports the delta."],
    ["measure-invocation emit-plugin-eval", "`measure-invocation.sh emit-plugin-eval plugins/tdd/probes evals/` writes the cases."],
    ["an edit to a claude -p call", "The wrapper's `claude -p` call passes `--max-turns 30`."],
    ["an edit to a headless Claude Code step", "The headless Claude Code step in the workflow keeps its `--allowedTools` list."],
    ["a script posting its refusal as a comment on this issue", "The refusal is posted as a comment on this issue with the item numbers."],
    ["a script recording in a comment on this issue", "refine.mjs records the split in a comment on this issue."],
    ["an option measure-invocation accepts", "`measure-invocation.sh` accepts a `--probes-dir` flag."],
    ["a README documenting measure-invocation", "`plugins/skill-quality/README.md` documents `measure-invocation.sh`."],
    ["an edit to measure-invocation with its test", "`measure-invocation.sh` handles an empty probe set, with a case in `measure-invocation.test.sh`."],
    ["plugin-eval named in docs", "The `/evals:plugin-eval` section names the cost ceiling."],
    ["a subject-first comment a script posts", "A comment on this issue names each refused item."],
    ["a named script's result posted as a comment on this issue", "work-unblock's result is posted as a comment on this issue."],
  ];
  for (const [name, line, hosts] of negatives) {
    test(`passes ${name}`, () => {
      assert.deepEqual(kinds(line, hosts), []);
    });
  }
  test("any web host skips the URL check; no listed hosts allow only GitHub and local ones", () => {
    assert.deepEqual(kinds("See https://example.com.", "any"), []);
    assert.equal(kinds("Confirm it matches https://code.claude.com/docs.", []).length, 1);
    assert.equal(unrunnableCriteria("- [ ] Confirm it matches https://code.claude.com/docs.", "- [ ] ", undefined).found.length, 1);
  });
  test("a *. host allows only that domain's subdomains", () => {
    assert.equal(kinds("Confirm it matches https://example.org/x.", ["*.example.org"]).length, 1);
    assert.equal(kinds("Confirm it matches https://badexample.org/x.", ["*.example.org"]).length, 1);
  });
  test("an observation window over time is flagged", () => {
    assert.match(kinds("Check error rates over the next two weeks.").join(), /over time/);
    assert.match(kinds("Track the hit rate for 14 days after release.").join(), /over time/);
  });
  test("reads only task-list lines and numbers items from 1", () => {
    const body = "Runs on a Windows 11 host today.\n- [ ] Fix line 3.\n- [ ] Run it on a Windows 11 host.";
    assert.deepEqual(unrunnableCriteria(body, "- [ ] ", HOSTS), {
      items: 2,
      found: [{ n: 2, kind: "a run on a host the lane is not", text: "Run it on a Windows 11 host." }],
    });
  });
  test("quotes issue text without backticks or live mentions, cut to 80 characters", () => {
    const [{ text }] = unrunnableCriteria(`- [ ] Ask @owner to run \`x\` on a Windows 11 host ${"and more ".repeat(20)}`, "- [ ] ", HOSTS).found;
    assert.ok(!text.includes("`"));
    assert.ok(text.includes("@\u200bowner"));
    assert.equal(text.length, 80);
  });
  test("still flags an item written with a case change, fullwidth or zero-width characters or URL encoding", () => {
    for (const line of [
      "RUN IT ON A WINDOWS 11 HOST.",
      "Run it on a \uff37\uff49\uff4e\uff44\uff4f\uff57\uff53 11 host.",
      "Run it on a Win\u200bdo\u200cws 11\u2060 host.",
      "Run it on%20a%20Windows%2011%20host.",
    ]) {
      assert.deepEqual(kinds(line), ["a run on a host the lane is not"], line);
    }
    // An invisible character in the task-list prefix still leaves an item.
    assert.equal(unrunnableCriteria("​- [ ]​ Run it on a Windows 11 host.", "- [ ] ", HOSTS).found.length, 1);
    assert.deepEqual(kinds("The page at https://exa\u200bmple.com/docs shows the new flag."), ["a page on example.com, outside the lane's web hosts"]);
  });
});

// Host work goes to the host queue (`host-run`), parked at status: confirmed,
// never to a person (docs/contracts/loop-lane/README.md, the three labels
// that take work off the unattended path). Only a mixed issue lacking
// host-run holds, so refine.mjs splitOf can split it from needs-decision.
describe("host-run work", () => {
  const HOST_ONLY = "- [ ] Run it on a Windows 11 host.";
  const hostRun = (body, labels = [{ name: READY }]) => issueOf({ body, labels });
  const queued = (body) => hostRun(body, [{ name: READY }, { name: "host-run" }]);
  const addedBy = (id) => [{ event: "labeled", label: { name: "host-run" }, actor: { id }, created_at: "2026-10-21T00:00:00Z" }];

  test("every done-when item unrunnable goes to the host queue: host-run added, no hold, no split", async () => {
    const result = decide(facts({ issue: hostRun(HOST_ONLY) }));
    assert.equal(result.verdict, "refuse");
    assert.equal(result.hold, undefined);
    assert.equal(result.hostRun, true);
    assert.match(result.reasons.join("; "), /no done-when item is left for the lane, so it goes to the host queue \(`host-run`\)/);
    const fake = fakeGitHub({ issue: hostRun(HOST_ONLY) });
    assert.equal((await go(fake)).status, CONFIRMED);
    assert.equal(writes(fake.calls)[0], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [CONFIRMED, "host-run"] })}`);
  });

  // #9293: the owner released it with host-run added, and admission held it again.
  test("an issue already carrying host-run parks at status: confirmed, whether all or some items are host work", async () => {
    for (const [body, by] of [
      [HOST_ONLY, HUMAN],
      [CANARY, HUMAN],
      [CANARY, APP],
    ]) {
      const issue = queued(body);
      const result = decide(facts({ issue, events: addedBy(by) }));
      assert.equal(result.verdict, "refuse", body);
      assert.equal(result.hold, undefined, body);
      assert.equal(result.hostRun, undefined, body);
      const fake = fakeGitHub({ issue, events: addedBy(by) });
      assert.equal((await go(fake)).status, CONFIRMED, body);
      assert.equal(writes(fake.calls)[0], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [CONFIRMED] })}`, body);
    }
  });

  // host-run starts an unattended host run, so it goes only on an issue whose
  // one obstacle is that no item is left for the lane.
  test("host work with another refusal, a wait or a pending split parks at status: confirmed with no host-run", async () => {
    const issue = hostRun(HOST_ONLY);
    for (const [why, overrides] of [
      ["Uncertainty unknown", { verdict: { ...VERDICT, dimensions: { ...VERDICT.dimensions, uncertainty: "unknown" } } }],
      ["a duplicate label", { issue: hostRun(HOST_ONLY, [{ name: READY }, { name: "duplicate" }]) }],
      ["an attended label", { issue: hostRun(HOST_ONLY, [{ name: READY }, { name: "attended" }]) }],
      ["an open pull request", { pulls: [5] }],
      ["a pending size split", { verdict: { ...VERDICT, dimensions: { ...VERDICT.dimensions, size: "large" } } }],
    ]) {
      const result = decide(facts({ issue, ...overrides }));
      assert.equal(result.verdict, "refuse", why);
      assert.equal(result.hold, undefined, why);
      assert.equal(result.hostRun, undefined, why);
    }
    const fake = fakeGitHub({ issue: hostRun(HOST_ONLY, [{ name: READY }, { name: "duplicate" }]) });
    await go(fake);
    assert.equal(writes(fake.calls)[0], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [CONFIRMED] })}`);
  });

  // A host-run label counts only when a listed human or the lanes App added it
  // last, as attendedHold judges `attended`'s provenance.
  test("a host-run label an unlisted account added does not lift the split hold", () => {
    for (const events of [addedBy(OUTSIDER), []]) {
      const result = decide(facts({ issue: queued(CANARY), events }));
      assert.equal(result.verdict, "refuse");
      assert.equal(result.hold, true, JSON.stringify(events));
    }
    assert.equal(decide(facts({ issue: queued(CANARY), events: addedBy(HUMAN) })).hold, undefined);
  });

  // Billing is an owner stop reason (docs/contracts/loop-lane/README.md, when
  // work stops for the owner), so a paid eval keeps the person hold; any other
  // unrunnable kind, an off-allowlist page included, goes to the host queue.
  test("a paid-eval item keeps the person hold and adds no host-run; an off-allowlist page goes to host-run", () => {
    const PAID = "- [ ] Run a paid eval of the skill and record the delta.";
    for (const [why, input] of [
      ["paid eval alone", { issue: hostRun(PAID) }],
      ["paid eval beside a host item", { issue: hostRun(`${HOST_ONLY}\n${PAID}`) }],
      ["paid eval on an issue carrying host-run", { issue: queued(`${HOST_ONLY}\n${PAID}`), events: addedBy(HUMAN) }],
    ]) {
      const result = decide(facts(input));
      assert.equal(result.verdict, "refuse", why);
      assert.equal(result.hold, true, why);
      assert.equal(result.hostRun, undefined, why);
      assert.match(result.reasons.join("; "), /the owner, since a paid eval can bill the owner/, why);
    }
    const page = decide(facts({ issue: hostRun("- [ ] Confirm it matches https://example.com/docs.") }));
    assert.equal(page.hold, undefined);
    assert.equal(page.hostRun, true);
  });

  test("a hold for a person adds no host-run, so no unattended host run acts on held text", async () => {
    const trusted = decide(facts({ issue: hostRun(HOST_ONLY) }));
    assert.equal(trusted.hostRun, true);
    const issue = issueOf({ body: HOST_ONLY, user: { id: OUTSIDER } });
    const held = decide(facts({ issue }));
    assert.equal(held.hold, true);
    assert.equal(held.hostRun, undefined);
    const fake = fakeGitHub({ issue });
    await go(fake);
    assert.equal(writes(fake.calls)[0], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [NEEDS_DECISION] })}`);
  });
});

describe("noteUnrunnable", () => {
  const HELD = issueOf({ body: CANARY, labels: [{ name: NEEDS_DECISION }] });
  const note = (fake, issue = HELD) => noteUnrunnable({ github: fake.github, repository: "o/r", issue, rules: RULES, webHosts: HOSTS, log: () => {} });
  test("a held issue with a Windows-host item gets the split comment and no label change (#9372)", async () => {
    const fake = fakeGitHub({ issue: HELD });
    const result = await note(fake);
    assert.equal(result.outcome, "noted");
    const done = writes(fake.calls);
    assert.equal(done.length, 1);
    assert.match(done[0], /^POST \/repos\/o\/r\/issues\/7\/comments /);
    assert.ok(done[0].includes(ADMIT_MARKER.replaceAll('"', '\\"')));
    assert.match(done[0], /item 2 .*Windows 11 host.*recommended split: keep the other items here as the admissible issue/);
  });
  test("a held issue whose done-when the lane can run gets nothing", async () => {
    const fake = fakeGitHub();
    assert.deepEqual(await note(fake, issueOf()), { outcome: "none", reasons: [] });
    assert.deepEqual(writes(fake.calls), []);
  });
  test("an issue a person already made agent-ready gets no note", async () => {
    const issue = issueOf({ body: CANARY, labels: [{ name: NEEDS_DECISION }, { name: AGENT_READY }] });
    const fake = fakeGitHub({ issue });
    assert.deepEqual(await note(fake, issue), { outcome: "skipped", reasons: [`already ${AGENT_READY}`] });
    assert.deepEqual(writes(fake.calls), []);
  });
  test("an issue whose agent-ready was removed before gets no note", async () => {
    const fake = fakeGitHub({ issue: HELD, events: [{ event: "unlabeled", label: { name: AGENT_READY } }] });
    assert.deepEqual(await note(fake), { outcome: "skipped", reasons: [`${AGENT_READY} was removed and ${READY} not added since`] });
    assert.deepEqual(writes(fake.calls), []);
  });
  test("a repeated run leaves an unchanged note alone, and edits a changed one in place", async () => {
    const first = fakeGitHub({ issue: HELD });
    await note(first);
    const posted = writes(first.calls)[0];
    const body = JSON.parse(posted.slice(posted.indexOf("{"))).body;
    const own = (text) => [{ id: 31, body: text, user: { login: "melodic-automation-lanes[bot]" } }];
    const again = fakeGitHub({ issue: HELD, comments: own(body) });
    assert.equal((await note(again)).outcome, "noted");
    assert.deepEqual(writes(again.calls), []);
    const changed = fakeGitHub({ issue: HELD, comments: own(`${ADMIT_MARKER}\nold`) });
    await note(changed);
    assert.match(writes(changed.calls)[0], /^PATCH \/repos\/o\/r\/issues\/comments\/31 /);
  });
});

// Owner Q93 with the coordinator's Q9 extension: a sub-issue a size split
// filed is the lanes App's verbatim copy of its listed-human parent's lines,
// so its body counts as that human's text; anything else stays untrusted.
describe("size split sub-issues", () => {
  const PARENT = 5;
  const PARENT_BODY = ["## Done when", "", "- [ ] Line 3 says nineteen.", "- [ ] Line 4 says twenty.", "- [ ] Line 5 says twenty-one."].join("\n");
  const parentSpec = (author = USER(HUMAN)) => ({ ...written(author, { body: PARENT_BODY }), comments: [] });
  const childBody = (lines = ["- [ ] Line 3 says nineteen.", "- [ ] Line 4 says twenty."], parent = PARENT) =>
    `${splitChildHeader(parent, 1, 2)}\n${lines.join("\n")}`;
  const childIssue = (body = childBody()) => issueOf({ user: { id: APP }, body });
  const NO_SPEC =
    "no trusted-human acceptance criteria: a listed human must put the confirmed `- [ ]` criteria in the body or post them as their own comment, or, on an issue a listed human filed, intake's newest refinement comment must hold them unedited";

  // The shared cases (split-child.vectors.json), as specOf and admissionFacts
  // shape them: a trusted child is admitted at its Size, Large included; an
  // untrusted one is refused at Small and at Large.
  const actorOf = (actor) => (actor ? { __typename: actor.type, databaseId: actor.id } : null);
  const commentOf = (c) => ({ databaseId: c.id, createdAt: c.created_at, updatedAt: c.updated_at, body: c.body, lastEditedAt: c.last_edited_at, author: actorOf(c.author), editor: actorOf(c.editor) });
  // admissionFacts sets splitParent only for a native parent in this
  // repository, with the lanes App id it was given (none when null).
  const vectorSpec = ({ child, parent, ...rest }) => {
    const appId = ("app_id" in rest ? rest.app_id : VECTORS.app_id) ?? undefined;
    const here = child.parent !== null && (child.parent.repo ?? "o/r") === "o/r";
    return {
      body: child.body,
      lastEditedAt: child.last_edited_at,
      author: actorOf(child.author),
      editor: actorOf(child.editor),
      comments: [],
      ...(here
        ? { splitParent: { number: child.parent.number, spec: { ...written(actorOf(VECTORS.parents[parent].author), { body: VECTORS.parents[parent].body }), comments: VECTORS.parents[parent].comments.map(commentOf) }, appId } }
        : {}),
    };
  };
  for (const vector of VECTORS.cases) {
    test(`split-child vector: ${vector.name}`, () => {
      assert.deepEqual([VECTORS.app_id, VECTORS.humans], [APP, [...humans]]);
      const spec = vectorSpec(vector);
      const issue = issueOf({ user: { id: vector.child.author.id }, body: vector.child.body });
      const at = (size) => decide(facts({ issue, spec, verdict: { ...VERDICT, dimensions: { ...VERDICT.dimensions, size } } }));
      if (vector.expect.trusted) {
        assert.deepEqual(at(vector.size), { verdict: "admit", reasons: [] }, vector.expect.reason);
      } else {
        assert.equal(at("small").verdict, "refuse", vector.expect.reason);
        assert.ok(at("small").reasons.includes(NO_SPEC), vector.expect.reason);
        assert.equal(at("large").verdict, "refuse", vector.expect.reason);
        assert.ok(at("large").reasons.some((reason) => /^Size large/.test(reason)), vector.expect.reason);
      }
    });
  }

  test("splitChildBody counts nothing without a task-list marker", () => {
    const spec = vectorSpec(VECTORS.cases.find((item) => item.name === "the trusted child"));
    assert.notEqual(splitChildBody(spec, humans, RULES["task-list"]), null);
    for (const taskList of [undefined, ""]) {
      assert.equal(splitChildBody(spec, humans, taskList), null, JSON.stringify(taskList));
    }
  });

  test("splitChildBody's edited path takes only exact lines when the marker has no box to tick", () => {
    const edited = vectorSpec(VECTORS.cases.find((item) => item.name === "edited by a listed human"));
    const header = edited.body.slice(0, edited.body.indexOf("- [x]"));
    const spec = (lines) => ({ ...edited, body: header + lines.join("\n"), splitParent: { ...edited.splitParent, spec: { ...edited.splitParent.spec, body: "## Done when\n\n* Line 3.\n  * Line 4." } } });
    assert.notEqual(splitChildBody(spec(["* Line 3.", "  * Line 4."]), humans, "* "), null);
    assert.equal(splitChildBody(spec(["* Line 3.", "* Line 4."]), humans, "* "), null, "the indent is part of the line");
    assert.equal(splitChildBody(spec(["* [x] Line 3."]), humans, "* "), null, "no ticked form to derive");
  });

  test("an issue waits while a sub-issue is open, and not for a closed one", () => {
    const subIssues = [
      { number: 8, state: "open" },
      { number: 9, state: "closed" },
    ];
    assert.deepEqual(decide(facts({ subIssues })), { verdict: "wait", reasons: ["sub-issue #8 is open"], pulls: [] });
    assert.deepEqual(decide(facts({ subIssues: [subIssues[1]] })), { verdict: "admit", reasons: [] });
  });

  test("a parent with an open sub-issue waits on it instead of refusing for a mechanical reason or a pending split", () => {
    const subIssues = [{ number: 8, state: "open" }];
    const noCriteria = { ...humanSpec(issueOf({ body: "Make the README better." })) };
    assert.deepEqual(decide(facts({ issue: issueOf({ body: "Make the README better." }), spec: noCriteria, subIssues })), { verdict: "wait", reasons: ["sub-issue #8 is open"], pulls: [] });
    assert.deepEqual(decide(facts({ verdict: { ...VERDICT, dimensions: { ...VERDICT.dimensions, size: "large" } }, subIssues })), { verdict: "wait", reasons: ["sub-issue #8 is open"], pulls: [] });
  });

  test("a parent waiting on an open sub-issue keeps its open pull requests, so admission-deferred stays", () => {
    const result = decide(facts({ issue: issueOf({ body: "Make the README better." }), spec: humanSpec(issueOf({ body: "Make the README better." })), pulls: [41], subIssues: [{ number: 8, state: "open" }] }));
    assert.deepEqual(result, { verdict: "wait", reasons: ["open pull request #41 is for it", "sub-issue #8 is open"], pulls: [41] });
  });

  test("a parent with an open sub-issue still refuses for a person when a hold applies", () => {
    const result = decide(facts({ verdict: { ...VERDICT, workClass: "work-class: untrusted-provenance" }, subIssues: [{ number: 8, state: "open" }] }));
    assert.equal(result.verdict, "refuse");
    assert.equal(result.hold, true);
  });

  // fakeGitHub answers one issue's text; these reads add the parent's text,
  // sub-issue lists and other issues by number.
  const withIssues = (fake, { specs = {}, subIssues = {}, issues = {}, comments = {}, events = {} }) => {
    const github = async (method, path, body) => {
      if (method === "POST" && path === "/graphql" && specs[body.variables?.number] && !body.query.includes("closedByPullRequestsReferences")) {
        fake.calls.push({ method, path, body });
        const spec = specs[body.variables.number];
        return { data: { repository: { issue: { ...spec, comments: { totalCount: spec.comments.length, nodes: spec.comments } } } } };
      }
      const sub = /^\/repos\/o\/r\/issues\/(\d+)\/sub_issues/.exec(path);
      if (method === "GET" && sub) {
        fake.calls.push({ method, path, body });
        return subIssues[sub[1]] ?? [];
      }
      const linked = /^\/repos\/o\/r\/issues\/(\d+)\/events/.exec(path);
      if (method === "GET" && linked && linked[1] !== "7") {
        fake.calls.push({ method, path, body });
        return events[linked[1]] ?? [];
      }
      const read = /^\/repos\/o\/r\/issues\/(\d+)(\/comments)?(\?|$)/.exec(path);
      if (method === "GET" && read && read[1] !== "7") {
        fake.calls.push({ method, path, body });
        return read[2] ? (comments[read[1]] ?? []) : issues[read[1]];
      }
      return fake.github(method, path, body);
    };
    return { github, calls: fake.calls };
  };

  test("admit() reads the native parent's text and admits the sub-issue", async () => {
    const child = childIssue();
    const parent = { number: PARENT, repository_url: "https://api.github.com/repos/o/r", user: { id: HUMAN } };
    const spec = { ...written(APP_ACTOR, { body: child.body }), comments: [] };
    const fake = withIssues(fakeGitHub({ issue: child, parent, spec }), { specs: { [PARENT]: parentSpec() } });
    assert.equal((await go(fake)).outcome, "admitted");
    // With no parent read the body is not a trusted sub-issue, so the App's
    // issue holds for a person (owner decision on #10735).
    const orphan = fakeGitHub({ issue: child, spec });
    const refused = await go(orphan);
    assert.equal(refused.status, NEEDS_DECISION);
    assert.deepEqual(refused.reasons, [
      "the lanes App filed it and it is not a trusted size-split sub-issue (splitChildBody), so a listed human files it as their own",
      NO_SPEC,
    ]);
  });

  test("admit() waits on an open sub-issue the issue read counts", async () => {
    const issue = issueOf({ sub_issues_summary: { total: 1, completed: 0, percent_completed: 0 } });
    const fake = withIssues(fakeGitHub({ issue }), { subIssues: { 7: [{ number: 8, state: "open" }] } });
    assert.deepEqual(await go(fake), { outcome: "waiting", reasons: ["sub-issue #8 is open"] });
  });

  test("admit() lists sub-issues and waits when the issue read has no summary", async () => {
    const fake = withIssues(fakeGitHub({ issue: issueOf({ sub_issues_summary: undefined }) }), { subIssues: { 7: [{ number: 8, state: "open" }] } });
    assert.deepEqual(await go(fake), { outcome: "waiting", reasons: ["sub-issue #8 is open"] });
  });

  test("a blocker the lanes App closed counts only as a split parent whose sub-issues a listed human closed", async () => {
    const record = { user: { id: APP, login: "melodic-automation-lanes[bot]" }, body: `${SIZE_SPLIT_MARKER}\n${renderSplitRecord({ items: "a".repeat(64), parts: [[1], [2]], order: [], filed: [31, 32] })}` };
    const blocker = { number: PARENT, state: "closed", state_reason: "completed", repository_url: "https://api.github.com/repos/o/r", closed_by: { id: APP }, user: { id: HUMAN } };
    const closedChild = (number) => ({ number, state: "closed", state_reason: "completed", closed_by: { id: HUMAN }, repository_url: "https://api.github.com/repos/o/r" });
    // A split made by hand: a listed human linked each sub-issue.
    const link = (number, id = HUMAN) => ({ event: "sub_issue_added", actor: { id }, created_at: "2026-10-15T00:00:00Z", sub_issue: { number, repository: { full_name: "o/r" } } });
    for (const [comments, expected, links = []] of [
      [[record], "admitted"],
      [[], "waiting"],
      [[], "admitted", [link(31), link(32)]],
      [[], "waiting", [link(31), link(32, 4242)]],
    ]) {
      const fake = withIssues(fakeGitHub({ blockers: [blocker] }), {
        issues: { [PARENT]: blocker, 31: closedChild(31), 32: closedChild(32) },
        comments: { [PARENT]: comments },
        subIssues: { [PARENT]: [closedChild(31), closedChild(32)] },
        events: { [PARENT]: links },
      });
      assert.equal((await go(fake)).outcome, expected);
    }
  });
});

describe("untrustedHold", () => {
  const LABEL = "work-class: untrusted-provenance";
  const humans = new Set([1]);
  const isApp = (actor) => actor?.id === 9;
  const event = (kind, id, name = LABEL) => ({ event: kind, label: { name }, actor: { id } });
  test("the label on the issue holds it", () => {
    assert.equal(untrustedHold({ labels: [{ name: LABEL }], events: [], humans, isApp }), true);
    assert.equal(untrustedHold({ labels: [LABEL], events: [], humans, isApp }), true);
  });
  test("a newest removal by neither a listed human nor the App still holds it; theirs lifts it", () => {
    assert.equal(untrustedHold({ labels: [], events: [event("labeled", 9), event("unlabeled", 5)], humans, isApp }), true);
    assert.equal(untrustedHold({ labels: [], events: [event("labeled", 9), event("unlabeled", 1)], humans, isApp }), false);
    assert.equal(untrustedHold({ labels: [], events: [event("labeled", 9), event("unlabeled", 9)], humans, isApp }), false);
    assert.equal(untrustedHold({ labels: [], events: [event("unlabeled", 5), event("labeled", 1, "other")], humans, isApp }), true);
  });
  test("an issue never labeled is not held", () => {
    assert.equal(untrustedHold({ labels: [{ name: "agent-ready" }], events: [event("labeled", 5, "agent-ready")], humans, isApp }), false);
  });
});

// A parent's status: needs-decision blocks its Features only while a decision
// is open: a person set the label, or the newest refinement on the parent asks
// questions no later Decision recorded comment answers.
describe("a Feature under a parent at status: needs-decision", () => {
  const PARENT = 9;
  const feature = issueOf({ type: { name: "Feature" } });
  const parentIssue = (labels = [NEEDS_DECISION]) => ({
    number: PARENT,
    state: "open",
    repository_url: "https://api.github.com/repos/o/r",
    user: { id: HUMAN },
    labels: labels.map((name) => ({ name })),
  });
  const setBy = (id) => [{ event: "labeled", label: { name: NEEDS_DECISION }, actor: { id } }];
  const output = (exact) => ({
    exact,
    outcome: "Ship the epic's parts.",
    criteria: exact ? ["Line 3 says nineteen."] : [],
    dependencies: [],
    related: [],
    questions: exact ? [] : [{ question: "Which part ships first?", recommended: "Part A.", basis: "judgment" }],
    sources: [],
    split: [],
    external: { state: "none", repo: "", class: "", what: "" },
  });
  const refinement = (exact) => ({
    id: 40,
    node_id: "IC_40",
    user: { id: APP },
    performed_via_github_app: null,
    created_at: "2026-10-21T00:00:00Z",
    body: render(validateOutput(output(exact), new Set())),
  });
  const decision = {
    id: 41,
    node_id: "IC_41",
    user: { id: HUMAN },
    performed_via_github_app: null,
    created_at: "2026-10-22T00:00:00Z",
    body: "**Decision recorded.** Part A first.",
  };
  // fakeGitHub answers the Feature; this answers the parent's events, comments and
  // the comment editor read select-trusted-text sends.
  const withParent = ({ labels, events = setBy(APP), comments = [], failOn } = {}) => {
    const fake = fakeGitHub({ issue: feature, parent: parentIssue(labels), failOn });
    const github = async (method, path, body) => {
      if (failOn?.(method, path, body)) {
        fake.calls.push({ method, path, body });
        throw new Error(`${method} ${path} failed with status 500`);
      }
      if (method === "GET" && path.startsWith(`/repos/o/r/issues/${PARENT}/events`)) {
        fake.calls.push({ method, path, body });
        return events;
      }
      if (method === "GET" && path.startsWith(`/repos/o/r/issues/${PARENT}/comments`)) {
        fake.calls.push({ method, path, body });
        return comments;
      }
      if (method === "POST" && path === "/graphql" && body.query.includes("nodes(ids")) {
        fake.calls.push({ method, path, body });
        return { data: { nodes: body.variables.ids.map((id) => ({ id, lastEditedAt: null, editor: null })) } };
      }
      return fake.github(method, path, body);
    };
    return { github, calls: fake.calls };
  };
  const read = (fake, what) => fake.calls.some((call) => call.method === "GET" && call.path.startsWith(`/repos/o/r/issues/${PARENT}/${what}`));
  const refusedForParent = (result) => result.outcome === "refused" && result.reasons.some((reason) => /parent/.test(reason));

  test("is admitted when the lanes App set the label and no refinement asks anything", async () => {
    const fake = withParent();
    assert.equal((await go(fake)).outcome, "admitted");
    assert.ok(read(fake, "events"), "the parent's events were read");
  });

  test("is refused when a person set the label", async () => {
    const fake = withParent({ events: setBy(HUMAN) });
    assert.ok(refusedForParent(await go(fake)));
    assert.ok(read(fake, "events"), "the parent's events were read");
  });

  test("is refused when the parent's newest refinement is not exact and no decision followed it", async () => {
    const fake = withParent({ comments: [refinement(false)] });
    assert.ok(refusedForParent(await go(fake)));
    assert.ok(read(fake, "comments"), "the parent's comments were read");
  });

  test("is admitted once a listed human's Decision recorded comment follows that refinement", async () => {
    const fake = withParent({ comments: [refinement(false), decision] });
    assert.equal((await go(fake)).outcome, "admitted");
  });

  test("is refused when the only decision predates the newest not-exact refinement, and admitted under an exact one", async () => {
    const earlier = { ...decision, created_at: "2026-10-20T00:00:00Z" };
    assert.ok(refusedForParent(await go(withParent({ comments: [earlier, refinement(false)] }))));
    assert.equal((await go(withParent({ comments: [refinement(true)] }))).outcome, "admitted");
  });

  const verdict = (flag) => ({
    id: 39,
    node_id: "IC_39",
    user: { id: APP },
    performed_via_github_app: null,
    created_at: "2026-10-20T00:00:00Z",
    body: [VERDICT_MARKER, `The triage verdict left this issue at \`${NEEDS_DECISION}\`:`, "", `- flagged: ${flag}`].join("\n"),
  });

  test("is refused when the lanes App's newest verdict on the parent flags security, with no refinement", async () => {
    assert.ok(refusedForParent(await go(withParent({ comments: [verdict("security")] }))));
  });

  test("is refused while the parent's intent verdict has no refinement and no later decision, and admitted after one", async () => {
    assert.ok(refusedForParent(await go(withParent({ comments: [verdict("intent")] }))));
    assert.equal((await go(withParent({ comments: [verdict("intent"), decision] }))).outcome, "admitted");
  });

  test("is admitted when the parent's only verdict holds nothing and no refinement exists", async () => {
    const holdsNothing = {
      ...verdict("intent"),
      body: [VERDICT_MARKER, "The latest triage verdict holds nothing: admission moved the issue to needs-decision; its comment says why."].join("\n"),
    };
    assert.equal((await go(withParent({ comments: [holdsNothing] }))).outcome, "admitted");
  });

  test("is refused when the parent also carries needs-human", async () => {
    const fake = withParent({ labels: [NEEDS_DECISION, "needs-human"] });
    assert.ok(refusedForParent(await go(fake)));
  });

  test("is refused when the parent's events cannot be read", async () => {
    const fake = withParent({ failOn: (method, path) => method === "GET" && path.startsWith(`/repos/o/r/issues/${PARENT}/events`) });
    assert.ok(refusedForParent(await go(fake)));
    assert.ok(read(fake, "events"), "the parent's events read was tried");
  });
});

// Owner decision 2026-10-28: work that needs the owner present carries
// `attended`, which admission refuses like host-run, parks at status:
// confirmed (no decision asked), and only a listed human removes.
describe("attended", () => {
  const thin = issueOf({ body: "Point the docs domain at the new host." });
  const refined = (line) =>
    written(APP_ACTOR, { body: `${REFINE_MARKER}\n**Refinement.**\n\n**Acceptance criteria**\n\n- [ ] Line 3 says nineteen.\n\n${line}\n` });
  const at = (comment, createdAt) => ({ ...comment, createdAt });
  const manual = at(refined("External state: manual (dns: a CNAME for docs at the registrar)"), "2026-10-20T09:00:00Z");
  const label = (event, actor, created_at = "2026-10-21T00:00:00Z") => ({ event, label: { name: "attended" }, actor: { id: actor }, created_at });

  test("an issue carrying attended is refused, parked at status: confirmed", async () => {
    const decision = decide(facts({ issue: issueOf({ labels: [{ name: READY }, { name: "attended" }] }) }));
    assert.equal(decision.verdict, "refuse");
    assert.deepEqual(decision.reasons, ["it carries attended"]);
    assert.equal(decision.hold, undefined);
    const fake = fakeGitHub({ issue: issueOf({ labels: [{ name: READY }, { name: "attended" }] }) });
    assert.equal((await go(fake)).status, CONFIRMED);
  });

  test("a refinement recording a manual external step is refused with attended added, and no decision asked", async () => {
    const decision = decide(facts({ issue: thin, spec: humanSpec(thin, [manual]) }));
    assert.equal(decision.verdict, "refuse");
    assert.equal(decision.attended, true);
    assert.equal(decision.hold, undefined);
    assert.match(decision.reasons.join(), /External state: manual \(dns: a CNAME for docs at the registrar\)/);
    const fake = fakeGitHub({ issue: thin, spec: humanSpec(thin, [manual]) });
    const result = await go(fake);
    assert.equal(result.outcome, "refused");
    assert.equal(writes(fake.calls)[0], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [CONFIRMED, "attended"] })}`);
  });

  test("an iac or none external state routes nothing", () => {
    for (const line of ["External state: iac (melodic-software/github-iac)", "External state: none"]) {
      assert.deepEqual(decide(facts({ issue: thin, spec: humanSpec(thin, [at(refined(line), "2026-10-20T09:00:00Z")]) })), { verdict: "admit", reasons: [] }, line);
    }
  });

  test("the line counts only in the counted refinement, not in a listed human's text", () => {
    const body = `${BODY}\n\nExternal state: manual (dns: a CNAME)`;
    const issue = issueOf({ body });
    assert.deepEqual(decide(facts({ issue, spec: humanSpec(issue) })), { verdict: "admit", reasons: [] });
  });

  test("a removal by the lanes App or an unlisted account keeps the hold; a listed human's lifts it", () => {
    for (const actor of [APP, OUTSIDER]) {
      const decision = decide(facts({ events: [label("labeled", APP, "2026-10-20T10:00:00Z"), label("unlabeled", actor)] }));
      assert.equal(decision.verdict, "refuse", String(actor));
      assert.deepEqual(decision.reasons, ["the newest removal of attended was not a listed human's, so its hold stands"]);
    }
    assert.deepEqual(decide(facts({ events: [label("labeled", APP, "2026-10-20T10:00:00Z"), label("unlabeled", HUMAN)] })), { verdict: "admit", reasons: [] });
  });

  test("a listed human's removal after the refinement settles its manual step; one before it does not", () => {
    const after = decide(facts({ issue: thin, spec: humanSpec(thin, [manual]), events: [label("labeled", APP, "2026-10-20T10:00:00Z"), label("unlabeled", HUMAN, "2026-10-21T00:00:00Z")] }));
    assert.deepEqual(after, { verdict: "admit", reasons: [] });
    const before = decide(facts({ issue: thin, spec: humanSpec(thin, [manual]), events: [label("unlabeled", HUMAN, "2026-10-19T00:00:00Z")] }));
    assert.equal(before.verdict, "refuse");
    assert.equal(before.attended, true);
  });
});

// Owner Q9 (2026-10-29): a blocker the lanes App closed as already-done counts
// for its dependents only while the merged pull request it cites still closes
// it; closedByTrusted passes the App's id through to isTrustedClose.
test("closedByTrusted counts the lanes App's already-done close only while its evidence holds", async () => {
  const APP = { login: "melodic-automation-lanes[bot]", id: 337595936, type: "Bot" };
  const mergeSha = "4".repeat(40);
  const closeBody = (stop) =>
    [
      "<!-- work-resolve-issue outcome=closed run=555 -->",
      `The work-resolve-issue lane stopped on this issue (\`${stop}\`): the run found the issue's work already on the default branch.`,
      "It closes the issue as completed.",
      "",
      "In the run's words:",
      "",
      `> ${stop}: ＃5 shipped it`,
    ].join("\n");
  const client = (stop, message) => async (method, path) => {
    const routes = {
      "GET /repos/o/r/issues/77": { number: 77, state: "closed", closed_by: APP, created_at: "2026-10-01T00:00:00Z", repository_url: "https://api.github.com/repos/o/r" },
      "POST /graphql": { data: { repository: { issue: { timelineItems: { nodes: [] } } } } },
      "GET /repos/o/r/issues/77/comments?per_page=100&page=1": [{ user: APP, body: closeBody(stop) }],
      "GET /repos/o/r/issues/77/sub_issues?per_page=100&page=1": [],
      "GET /repos/o/r/issues/77/events?per_page=100&page=1": [],
      "GET /repos/o/r": { default_branch: "main" },
      "GET /repos/o/r/pulls/5": { merged_at: "2026-10-20T00:00:00Z", base: { ref: "main" }, merge_commit_sha: mergeSha },
      [`GET /repos/o/r/commits/${mergeSha}`]: { commit: { message } },
    };
    if (!Object.hasOwn(routes, `${method} ${path}`)) {
      throw new Error(`no route for ${method} ${path}`);
    }
    return routes[`${method} ${path}`];
  };
  const trusted = (stop, message, { appId = APP.id } = {}) => closedByTrusted({ github: client(stop, message), repository: "o/r", humans: new Set(), appId })(77);
  assert.equal(await trusted("already-done", "fix: tidy (#5)\n\nCloses #77"), true);
  assert.equal(await trusted("already-done", "fix: tidy (#5)"), false, "the merge commit no longer closes it");
  assert.equal(await trusted("report-delivered", "fix: tidy (#5)\n\nCloses #77"), false, "a report close");
  assert.equal(await trusted("already-done", "fix: tidy (#5)\n\nCloses #77", { appId: 1 }), false, "another App id");
});

describe("authorAdmitted", () => {
  const humans = new Set([101]);
  test("admits a listed human's or the lanes App's issue, nobody else's", () => {
    assert.equal(authorAdmitted({ user: { id: 101 } }, humans, 303), true);
    assert.equal(authorAdmitted({ user: { id: 303 } }, humans, 303), true);
    assert.equal(authorAdmitted({ user: { id: 202 } }, humans, 303), false);
  });
  test("refuses an issue with no author, whatever App id is unset", () => {
    for (const appId of [undefined, null, 303]) {
      assert.equal(authorAdmitted({}, humans, appId), false, String(appId));
      assert.equal(authorAdmitted({ user: { id: 303 } }, humans, appId === 303 ? undefined : appId), false, String(appId));
    }
  });
});

// resolve-config's splitChild fact (read by check-blockers.mjs): the issue lane's budget for a trusted
// size-split sub-issue rated Large (pr-pipeline.yaml split-child-size).
test("trustedSplitChild reads the issue and its native parent and applies splitChildBody", async () => {
  const LANES = 337595936;
  const HUMAN_ID = 153232337;
  const lines = ["- [ ] Line 3 says nineteen.", "- [ ] Line 4 says twenty."];
  const node = (body, author) => ({ body, lastEditedAt: null, author, editor: null, comments: { totalCount: 0, nodes: [] } });
  const human = { __typename: "User", databaseId: HUMAN_ID };
  const app = { __typename: "Bot", databaseId: LANES };
  const childBody = `${splitChildHeader(5, 1, 2)}\n${lines[0]}`;
  const fake = (child, parent = { number: 5, repository_url: "https://api.github.com/repos/o/r" }) => async (method, path, body) => {
    if (method === "POST" && path === "/graphql") {
      return { data: { repository: { issue: body.variables.number === 5 ? node(lines.join("\n"), human) : child } } };
    }
    if (path === "/repos/o/r/issues/8/parent") {
      if (parent === null) {
        throw Object.assign(new Error("404"), { status: 404 });
      }
      return parent;
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  const humansSet = new Set([HUMAN_ID]);
  assert.equal(await trustedSplitChild(fake(node(childBody, app)), "o/r", 8, humansSet, LANES, "- [ ] "), true);
  assert.equal(await trustedSplitChild(fake(node(`${childBody}\n- [ ] Invented.`, app)), "o/r", 8, humansSet, LANES, "- [ ] "), false, "a line the parent lacks");
  assert.equal(await trustedSplitChild(fake(node(childBody, human)), "o/r", 8, humansSet, LANES, "- [ ] "), false, "not the lanes App's");
  assert.equal(await trustedSplitChild(fake(node(childBody, app), null), "o/r", 8, humansSet, LANES, "- [ ] "), false, "no parent");
  assert.equal(await trustedSplitChild(fake(node("Plain issue.", human)), "o/r", 8, humansSet, LANES, "- [ ] "), false, "no split marker, no parent read");
});
