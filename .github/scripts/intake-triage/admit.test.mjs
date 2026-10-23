import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

import { ADMIT_MARKER, AGENT_READY, DEFERRED, admit, decide, loadRules } from "./admit.mjs";

const RULES = loadRules(fileURLToPath(new URL("../../actions/resolve-config/admission-rules.json", import.meta.url)));
const HUMAN = 153232337;
const OUTSIDER = 4242;
const APP = 337595936;
const humans = new Set([HUMAN]);
const READY = "status: ready";
const NEEDS_DECISION = "status: needs-decision";

const BODY = ["## Problem", "", "`plugins/session-flow/README.md:3` says eighteen.", "", "## Done when", "", "- [ ] Line 3 says nineteen."].join(
  "\n",
);
const issueOf = (overrides = {}) => ({
  number: 7,
  state: "open",
  title: "docs(session-flow): README skill count",
  body: BODY,
  user: { id: HUMAN },
  type: { name: "Task" },
  labels: [{ name: READY }, { name: "work-class: mechanical" }],
  ...overrides,
});
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
  timeline: [],
  events: [],
  humans,
  appId: APP,
  repository: "o/r",
  ...overrides,
});

describe("decide", () => {
  test("admits a clear Task that meets every criterion", () => {
    assert.deepEqual(decide(facts()), { verdict: "admit", reasons: [] });
  });

  const refusals = [
    ["criterion 2: a type the rules do not list", { issue: issueOf({ type: { name: "Epic" } }) }, /type Epic/],
    ["criterion 2: an issue with no type", { issue: issueOf({ type: null }) }, /type none/],
    ["criterion 2: a Feature with no parent", { issue: issueOf({ type: { name: "Feature" } }) }, /Feature.*parent/],
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
      "criterion 3: Uncertainty Knowable",
      {
        verdict: {
          ...VERDICT,
          dimensions: { ...VERDICT.dimensions, uncertainty: "knowable" },
        },
      },
      /Uncertainty knowable/,
    ],
    [
      "criterion 3: Size Large",
      {
        verdict: {
          ...VERDICT,
          dimensions: { ...VERDICT.dimensions, size: "large" },
        },
      },
      /Size large/,
    ],
    ["criterion 3: a structural class", { verdict: { ...VERDICT, workClass: "work-class: structural" } }, /work-class: structural/],
    ["criterion 7: no task list to check", { issue: issueOf({ body: "Make the README better." }) }, /no `- \[ \] ` task list/],
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
  ];
  for (const [name, input, reason] of refusals) {
    test(`refuses for a person on ${name}`, () => {
      const result = decide(facts(input));
      assert.equal(result.verdict, "refuse");
      assert.match(result.reasons.join("; "), reason);
    });
  }

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

  test("waits on criterion 8: an open pull request in this repository names it", () => {
    const result = decide(
      facts({
        timeline: [
          {
            event: "cross-referenced",
            source: {
              issue: {
                number: 12,
                state: "open",
                pull_request: {},
                repository: { full_name: "o/r" },
              },
            },
          },
        ],
      }),
    );
    assert.equal(result.verdict, "wait");
    assert.match(result.reasons.join(), /#12/);
  });

  test("ignores a closed pull request and a mention from an issue", () => {
    const ref = (issue) => ({
      event: "cross-referenced",
      source: { issue: { repository: { full_name: "o/r" }, ...issue } },
    });
    const result = decide(
      facts({
        timeline: [ref({ number: 12, state: "closed", pull_request: {} }), ref({ number: 13, state: "open" })],
      }),
    );
    assert.equal(result.verdict, "admit");
  });

  test("a closed, completed blocker does not hold it", () => {
    const result = decide(
      facts({
        blockers: [
          {
            number: 5,
            state: "closed",
            state_reason: "completed",
            repository_url: "https://api.github.com/repos/o/r",
          },
        ],
      }),
    );
    assert.equal(result.verdict, "admit");
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

  test("issue text cannot admit: a quoted task list still counts, a missing one refuses", () => {
    const result = decide(
      facts({
        issue: issueOf({ body: "> - [ ] quoted from elsewhere" }),
      }),
    );
    assert.equal(result.verdict, "refuse");
  });
});

// A fake GitHub for admit(): the issue, its parent, blockers, timeline,
// events and comments, recording every call.
function fakeGitHub({ issue = issueOf(), parent = null, blockers = [], timeline = [], events = [], comments = [] } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    const base = "/repos/o/r/issues/7";
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
    if (path.startsWith(`${base}/timeline`)) {
      return timeline;
    }
    if (path.startsWith(`${base}/events`)) {
      return events;
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
const go = (fake, { status = open } = {}) =>
  admit({
    github: fake.github,
    repository: "o/r",
    number: 7,
    verdict: VERDICT,
    rules: RULES,
    humans,
    appId: APP,
    status: async () => status,
    log: () => {},
  });
const writes = (calls) => calls.filter((call) => call.method !== "GET").map(({ method, path, body }) => `${method} ${path} ${JSON.stringify(body)}`);

describe("admit", () => {
  test("adds agent-ready when every criterion holds and the caps have room", async () => {
    const fake = fakeGitHub();
    const result = await go(fake);
    assert.equal(result.outcome, "admitted");
    assert.deepEqual(writes(fake.calls), [`POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [AGENT_READY] })}`]);
  });

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
  ];
  for (const [name, status] of full) {
    test(`defers, never agent-ready, when ${name}`, async () => {
      const fake = fakeGitHub();
      const result = await go(fake, { status });
      assert.equal(result.outcome, "deferred");
      assert.deepEqual(writes(fake.calls), [`POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [DEFERRED] })}`]);
    });
  }

  test("a refusal swaps status: ready for needs-decision and posts the reason", async () => {
    const fake = fakeGitHub({
      issue: issueOf({ body: "Make the README better." }),
    });
    const result = await go(fake);
    assert.equal(result.outcome, "refused");
    const done = writes(fake.calls);
    assert.equal(done.length, 3);
    assert.match(done[0], /^DELETE \/repos\/o\/r\/issues\/7\/labels\/status%3A%20ready/);
    assert.equal(done[1], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [NEEDS_DECISION] })}`);
    assert.match(done[2], /^POST \/repos\/o\/r\/issues\/7\/comments /);
    assert.ok(done[2].includes(ADMIT_MARKER.replaceAll('"', '\\"')));
    assert.match(done[2], /task list/);
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

  test("an open blocker posts the reason and keeps status: ready", async () => {
    const fake = fakeGitHub({ blockers: [{ number: 5, state: "open" }] });
    const result = await go(fake);
    assert.equal(result.outcome, "waiting");
    const done = writes(fake.calls);
    assert.equal(done.length, 1);
    assert.match(done[0], /^POST \/repos\/o\/r\/issues\/7\/comments /);
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
