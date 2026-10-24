import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

import { ADMIT_MARKER, AGENT_READY, DEFERRED, admit, decide, loadRules, noteUnrunnable, openPullsNaming, unrunnableCriteria } from "./admit.mjs";
import { REFINE_MARKER, render, validateOutput } from "./refine.mjs";

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
  title: "docs(session-flow): README skill count",
  body: BODY,
  user: { id: HUMAN },
  type: { name: "Task" },
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
  // Owner decision Q9 (#8999): pr-verify judges a lane PR only against text a
  // listed human wrote and last edited (resolve-pr.mjs linkedIssues), so an
  // issue with no such body or comment fails verify at every head.
  describe("trusted-human acceptance criteria", () => {
    const appIssue = issueOf({ user: { id: APP } });
    const NO_SPEC =
      "no trusted-human acceptance criteria: a listed human must put the confirmed `- [ ]` criteria in the body or post them as their own comment (owner Q9, #8999)";
    const goAhead = written(USER(HUMAN), { body: "Go ahead." });

    test("an App-authored issue with criteria only in its body is refused", () => {
      for (const spec of [{ ...written(APP_ACTOR), comments: [] }, { ...written(APP_ACTOR), comments: [written(APP_ACTOR), written(USER(OUTSIDER))] }]) {
        assert.deepEqual(decide(facts({ issue: appIssue, spec })), { verdict: "refuse", reasons: [NO_SPEC] });
      }
    });

    test("an App-drafted task list with a listed human's comment that carries none is refused", () => {
      assert.deepEqual(decide(facts({ issue: appIssue, spec: { ...written(APP_ACTOR), comments: [goAhead] } })), { verdict: "refuse", reasons: [NO_SPEC] });
    });

    test("the same issue with a listed human's comment carrying the task list is admitted", () => {
      for (const comment of [written(USER(HUMAN)), written(USER(HUMAN), { editor: USER(HUMAN) })]) {
        assert.deepEqual(decide(facts({ issue: appIssue, spec: { ...written(APP_ACTOR), comments: [goAhead, comment] } })), { verdict: "admit", reasons: [] });
      }
      // A human's comment the App last edited is no longer theirs.
      const edited = decide(facts({ issue: appIssue, spec: { ...written(APP_ACTOR), comments: [written(USER(HUMAN), { editor: APP_ACTOR })] } }));
      assert.deepEqual(edited.reasons, [NO_SPEC]);
    });

    test("a human-authored body last edited by the App is refused unless a human comment carries the task list", () => {
      const body = written(USER(HUMAN), { editor: APP_ACTOR });
      assert.deepEqual(decide(facts({ spec: { ...body, comments: [] } })), { verdict: "refuse", reasons: [NO_SPEC] });
      assert.deepEqual(decide(facts({ spec: { ...body, comments: [goAhead] } })), { verdict: "refuse", reasons: [NO_SPEC] });
      assert.deepEqual(decide(facts({ spec: { ...body, comments: [written(USER(HUMAN))] } })), { verdict: "admit", reasons: [] });
      // No spec read at all fails closed.
      assert.deepEqual(decide(facts({ spec: undefined })).reasons, [NO_SPEC]);
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

    test("admit() reads the authors and refuses an App-only spec to status: needs-decision", async () => {
      const { github, calls } = fakeGitHub({ issue: appIssue, spec: { ...written(APP_ACTOR), comments: [] } });
      const result = await admit({ github, repository: "o/r", number: 7, verdict: VERDICT, rules: RULES, humans, appId: APP, webHosts: HOSTS, status: async () => assert.fail("a refusal reads no status"), log: () => {} });
      assert.deepEqual(result, { outcome: "refused", reasons: [NO_SPEC] });
      const writes = calls.filter((call) => call.method !== "GET" && call.path !== "/graphql").map((call) => `${call.method} ${call.path}`);
      assert.deepEqual(writes, ["POST /repos/o/r/issues/7/labels", "DELETE /repos/o/r/issues/7/labels/status%3A%20ready", "POST /repos/o/r/issues/7/comments"]);
      assert.deepEqual(calls.find((call) => call.method === "POST" && call.path.endsWith("/labels")).body, { labels: [NEEDS_DECISION] });
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
      "criterion 3: Uncertainty Unknown",
      {
        verdict: {
          ...VERDICT,
          dimensions: { ...VERDICT.dimensions, uncertainty: "unknown" },
        },
      },
      /Uncertainty unknown/,
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
    assert.match(result.reasons.join(), /#5 is not closed as completed by a listed human or a merge/);
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

  // The App's refinement comment is model text pr-verify never reads, so its
  // task list admits nothing; a listed human who confirms it posts it as their own.
  describe("criterion 7 and the lanes App's refinement comment", () => {
    const thin = issueOf({ body: "Make the README skill count right." });
    const refinement = (body = `${REFINE_MARKER}\n**Refinement.**\n\n- [ ] Line 3 says nineteen.`) => written(APP_ACTOR, { body });
    const NO_SPEC = /^no trusted-human acceptance criteria: /;

    test("a thin issue whose only task list is the App's refinement comment is refused", () => {
      const result = decide(facts({ issue: thin, spec: humanSpec(thin, [refinement()]) }));
      assert.equal(result.verdict, "refuse");
      assert.match(result.reasons.join(), NO_SPEC);
    });

    test("a listed human's comment carrying the confirmed criteria admits the thin issue", () => {
      const confirmed = written(USER(HUMAN), { body: "Confirmed:\n\n- [ ] Line 3 says nineteen." });
      assert.deepEqual(decide(facts({ issue: thin, spec: humanSpec(thin, [refinement(), confirmed]) })), { verdict: "admit", reasons: [] });
    });

    test("a rendered refinement a listed human posts as their own is still checked for pages outside the lane's web hosts", () => {
      const output = { exact: true, outcome: "Match the spec.", criteria: ["The page at https://example.org/spec says nineteen."], dependencies: [], related: [], questions: [], sources: [], split: [] };
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
function fakeGitHub({ issue = issueOf(), parent = null, blockers = [], closed = {}, timeline = [], closing = [], events = [], comments = [], spec, failOn } = {}) {
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (failOn?.(method, path, body)) {
      throw new Error(`${method} ${path} failed with status 500`);
    }
    const base = "/repos/o/r/issues/7";
    if (method === "POST" && path === "/graphql") {
      if (body.query.includes("closedByPullRequestsReferences")) {
        const refs = { nodes: closing, pageInfo: { hasNextPage: false, endCursor: null } };
        return { data: { repository: { issue: { closedByPullRequestsReferences: refs } } } };
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
    webHosts: HOSTS,
    status: async () => status,
    log: () => {},
  });
// The GraphQL reads are POSTs but write nothing.
const writes = (calls) => calls.filter((call) => call.method !== "GET" && call.path !== "/graphql").map(({ method, path, body }) => `${method} ${path} ${JSON.stringify(body)}`);

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
    assert.equal(done[0], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [NEEDS_DECISION] })}`);
    assert.match(done[1], /^DELETE \/repos\/o\/r\/issues\/7\/labels\/status%3A%20ready/);
    assert.match(done[2], /^POST \/repos\/o\/r\/issues\/7\/comments /);
    assert.ok(done[2].includes(ADMIT_MARKER.replaceAll('"', '\\"')));
    assert.match(done[2], /no trusted-human acceptance criteria/);
  });

  test("a Windows-host done-when item stays out of the lane: needs-decision and a recommended split, never agent-ready", async () => {
    const fake = fakeGitHub({ issue: issueOf({ body: CANARY }) });
    const result = await go(fake);
    assert.equal(result.outcome, "refused");
    const done = writes(fake.calls);
    assert.ok(!done.some((call) => call.includes("/labels ") && call.includes(AGENT_READY)));
    assert.equal(done[0], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [NEEDS_DECISION] })}`);
    assert.match(done[1], /^DELETE \/repos\/o\/r\/issues\/7\/labels\/status%3A%20ready/);
    assert.match(done[2], /item 2 .*Windows 11 host.*recommended split: keep the other items here .* needs-human child issue/);
  });

  test("a refusal whose needs-decision write fails keeps status: ready, so admission-deferred never stands alone", async () => {
    const failOn = (method, path, body) => method === "POST" && path.endsWith("/labels") && body?.labels?.includes(NEEDS_DECISION);
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

  test("a thin issue is refused on the App's refinement alone and admitted on a listed human's confirmed criteria", async () => {
    const thin = issueOf({ body: "Make the README skill count right." });
    const refinement = written(APP_ACTOR, { body: `${REFINE_MARKER}\n- [ ] Line 3 says nineteen.` });
    const refined = await go(fakeGitHub({ issue: thin, spec: humanSpec(thin, [refinement]) }));
    assert.equal(refined.outcome, "refused");
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
    const fake = fakeGitHub({ closing: [{ number: 12, repository: { nameWithOwner: "o/r" } }] });
    const result = await go(fake);
    assert.equal(result.outcome, "waiting");
    const done = writes(fake.calls);
    assert.equal(done[0], `POST /repos/o/r/issues/7/labels ${JSON.stringify({ labels: [DEFERRED] })}`);
    assert.match(done[1], /^POST \/repos\/o\/r\/issues\/7\/comments .*open pull request #12/);
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
});

test("decide: every done-when item unrunnable says a person takes the issue, with no split", () => {
  const result = decide(facts({ issue: issueOf({ body: "- [ ] Run it on a Windows 11 host." }) }));
  assert.equal(result.verdict, "refuse");
  assert.match(result.reasons.join("; "), /no done-when item is left for the lane, so a person takes the issue/);
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
