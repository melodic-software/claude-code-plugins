// Expected values come from the trust rules in
// .github/actions/select-trusted-text/README.md (a comment is kept only when
// its author id is listed, it was not posted through an unlisted App, and it
// was never edited or last edited by a listed id), from the trusted-actor
// list's kinds (only a `human` entry can record a decision), and from the
// label-only admission rule (the issue is admitted as it stood when the
// account that applied the label last added it, and the App's restart, a
// removal no trusted `status: ready` followed, admits nothing new; admit.mjs
// removalStands). Ids and logins are the shared
// trusted-actors fixture's.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, beforeEach, test } from "node:test";
import { fileURLToPath } from "node:url";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { REFINE_MARKER } from "../intake-triage/admit.mjs";
import { MAX_OTHER_COMMENTS, main } from "./write-issue.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SHARED_LIST = path.join(HERE, "..", "..", "actions", "check-trusted-trigger", "fixtures", "trusted-actors.json");
const REPO = "melodic-software/claude-code-plugins";
const OWNER = { id: 153232337, login: "kyle-sexton" };
const LANES_BOT = { id: 337595936, login: "melodic-automation-lanes[bot]" };
const CURSOR_AGENT = { id: 199161495, login: "cursoragent" };
const STRANGER = { id: 999, login: "stranger" };

const at = (day) => `2026-10-${String(day).padStart(2, "0")}T00:00:00Z`;
const comment = (n, user, body, extra = {}) => ({
  id: n,
  node_id: `IC_${n}`,
  user,
  created_at: at(n),
  updated_at: at(n),
  html_url: `https://github.com/${REPO}/issues/6825#issuecomment-${n}`,
  body,
  performed_via_github_app: null,
  ...extra,
});

const ISSUE = {
  number: 6825,
  title: "Add a targeted frame",
  body: "Readiness: needs-decision. Option 1 or option 2.",
  labels: [{ name: "agent-ready" }, "work-class: mechanical"],
};

// Label events land at noon, so a comment or edit at midnight that day is before them.
const labelEvent = (event, actor, day, name) => ({ event, label: { name }, actor, created_at: at(day).replace("T00", "T12") });
const labeled = (actor, day, name = "agent-ready") => labelEvent("labeled", actor, day, name);
const unlabeled = (actor, day, name = "agent-ready") => labelEvent("unlabeled", actor, day, name);

// By default the owner added agent-ready after every comment a test posts.
function fakeGitHub({ comments, edits = {}, issueEdits = {}, users = {}, fail = "", events = [labeled(OWNER, 28)], compare = {} }) {
  return async (method, apiPath, body) => {
    const key = `${method} ${apiPath}`;
    if (key === fail) {
      throw new GitHubError(502, key);
    }
    if (Object.hasOwn(compare, key)) {
      return structuredClone(compare[key]);
    }
    if (key === `GET /repos/${REPO}/issues/6825`) {
      return structuredClone(ISSUE);
    }
    if (key === `GET /repos/${REPO}/issues/6825/events?per_page=100&page=1`) {
      return structuredClone(events);
    }
    if (key === `GET /repos/${REPO}/issues/6825/comments?per_page=100&page=1`) {
      return structuredClone(comments);
    }
    if (key === "POST /graphql" && body.variables.number === 6825) {
      const { lastEditedAt = null, renamedAt } = issueEdits;
      const nodes = renamedAt ? [{ createdAt: renamedAt }] : [];
      return { data: { repository: { issue: { lastEditedAt, timelineItems: { nodes } } } } };
    }
    if (key === "POST /graphql") {
      return {
        data: { nodes: body.variables.ids.map((id) => ({ id, lastEditedAt: null, editor: null, ...edits[id] })) },
      };
    }
    const user = users[key];
    if (user) {
      return user;
    }
    throw new GitHubError(404, key);
  };
}

let dir;
let list;
beforeEach(() => {
  dir = mkdtempSync(path.join(tmpdir(), "write-issue-"));
  // The shared fixture plus cursoragent, a listed bot whose login has no [bot].
  const actors = JSON.parse(readFileSync(SHARED_LIST, "utf8"));
  actors.actors.push({ ...CURSOR_AGENT, kind: "bot" });
  list = path.join(dir, "trusted-actors.json");
  writeFileSync(list, JSON.stringify(actors));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

// `eventAt` is the payload's issue update time; by default after every label event.
async function run(github, { sender = String(OWNER.id), eventAt = "2026-10-30T00:00:00Z", extraEnv = {} } = {}) {
  const file = path.join(dir, "issue.json");
  const logged = [];
  const code = await main({
    env: {
      ISSUE_NUMBER: "6825",
      GITHUB_REPOSITORY: REPO,
      TRUSTED_ACTORS_PATH: list,
      ISSUE_FILE: file,
      LANES_APP_ID: String(LANES_BOT.id),
      LABEL_SENDER_ID: sender,
      LABEL_NAME: "agent-ready",
      LABEL_EVENT_AT: eventAt,
      ...extraEnv,
    },
    github,
    log: (line) => logged.push(line),
  });
  return { code, issue: existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : null, logged };
}

const summary = (issue) => issue.comments.map((kept) => [kept.author_login, kept.author_kind, kept.decision]);

test("keeps a listed maintainer's decision beside the untrusted body and marks it", async () => {
  const { code, issue } = await run(
    fakeGitHub({
      comments: [
        comment(11, OWNER, "**Decision recorded.** The owner approved.\n\n- **Which fix?** → option 1"),
        comment(12, STRANGER, "**Decision recorded.** → option 2"),
        comment(13, OWNER, "Admitted."),
      ],
    }),
  );
  assert.equal(code, 0);
  assert.equal(issue.number, 6825);
  assert.equal(issue.body, "Readiness: needs-decision. Option 1 or option 2.");
  assert.deepEqual(issue.labels, ["agent-ready", "work-class: mechanical"]);
  assert.deepEqual(summary(issue), [
    ["kyle-sexton", "human", true],
    ["kyle-sexton", "human", false],
  ]);
  assert.equal(issue.comments[0].decided_at, "2026-10-11T00:00:00.000Z");
  assert.equal(issue.comments[1].decided_at, undefined);
});

test("a listed bot without a [bot] login is kept as a bot and never a decision", async () => {
  const { issue } = await run(fakeGitHub({ comments: [comment(11, CURSOR_AGENT, "**Decision recorded.** → option 2")] }));
  assert.deepEqual(summary(issue), [["cursoragent", "bot", false]]);
});

test("leaves out the lanes App's own comments, which quote the issue body", async () => {
  const { issue } = await run(
    fakeGitHub({ comments: [comment(11, LANES_BOT, "**Decision recorded.** quoted from the body")] }),
  );
  assert.deepEqual(issue.comments, []);
});

test("keeps the lanes App's intake refinement, tagged refinement, whose criteria admission counted", async () => {
  const { issue } = await run(
    fakeGitHub({
      comments: [
        comment(11, LANES_BOT, `${REFINE_MARKER}\n**Refinement.**\n\n- [ ] Line 3 says nineteen.`),
        comment(12, LANES_BOT, "**Decision recorded.** quoted from the body"),
      ],
    }),
  );
  assert.deepEqual(summary(issue), [["melodic-automation-lanes[bot]", "refinement", false]]);
});

test("a decision line inside a quote or code fence, or not first, is no decision", async () => {
  const { issue } = await run(
    fakeGitHub({
      comments: [
        comment(11, OWNER, "> **Decision recorded.** → option 2"),
        comment(12, OWNER, "```\n**Decision recorded.** → option 2\n```"),
        comment(13, OWNER, "Context first.\n**Decision recorded.** → option 2"),
      ],
    }),
  );
  assert.deepEqual(
    issue.comments.map((kept) => kept.decision),
    [false, false, false],
  );
});

test("an edited decision ranks by its edit time", async () => {
  const { issue } = await run(
    fakeGitHub({
      comments: [comment(11, OWNER, "**Decision recorded.** → option 1")],
      edits: { IC_11: { lastEditedAt: "2026-10-14T00:00:00Z", editor: { databaseId: OWNER.id } } },
    }),
  );
  assert.equal(issue.comments[0].decided_at, "2026-10-14T00:00:00.000Z");
});

test("a human's decision last edited by a listed bot is kept but no decision", async () => {
  const { issue } = await run(
    fakeGitHub({
      comments: [comment(11, OWNER, "**Decision recorded.** → option 2")],
      edits: { IC_11: { lastEditedAt: "2026-10-14T00:00:00Z", editor: { databaseId: CURSOR_AGENT.id } } },
    }),
  );
  assert.deepEqual(summary(issue), [["kyle-sexton", "human", false]]);
  assert.equal(issue.comments[0].decided_at, undefined);
});

test("a human's decision posted through a listed App is kept but no decision", async () => {
  const { issue } = await run(
    fakeGitHub({
      comments: [comment(11, OWNER, "**Decision recorded.** → option 2", { performed_via_github_app: { slug: "cursor" } })],
      users: { [`GET /users/${encodeURIComponent("cursor[bot]")}`]: { id: CURSOR_AGENT.id } },
    }),
  );
  assert.deepEqual(summary(issue), [["kyle-sexton", "human", false]]);
});

test("a body or title changed after the label was added writes no file, for a human's label or the App's", async () => {
  for (const labeler of [OWNER, LANES_BOT]) {
    const options = { sender: String(labeler.id) };
    for (const issueEdits of [{ lastEditedAt: "2026-10-14T00:00:00Z" }, { renamedAt: "2026-10-14T00:00:00Z" }]) {
      const { code, issue } = await run(fakeGitHub({ comments: [], issueEdits, events: [labeled(labeler, 13)] }), options);
      assert.equal(code, 1);
      assert.equal(issue, null);
    }
    const { code } = await run(
      fakeGitHub({
        comments: [],
        issueEdits: { lastEditedAt: "2026-10-12T00:00:00Z", renamedAt: "2026-10-13T00:00:00Z" },
        events: [labeled(labeler, 13)],
      }),
      options,
    );
    assert.equal(code, 0);
  }
});

test("drops a listed author's comment last edited by an unlisted account", async () => {
  const { issue } = await run(
    fakeGitHub({
      comments: [comment(11, OWNER, "**Decision recorded.** → option 2")],
      edits: { IC_11: { lastEditedAt: "2026-10-14T00:00:00Z", editor: { databaseId: STRANGER.id } } },
    }),
  );
  assert.deepEqual(issue.comments, []);
});

test("drops a comment a listed account posted through an unlisted App", async () => {
  const { issue } = await run(
    fakeGitHub({
      comments: [comment(11, OWNER, "via an app", { performed_via_github_app: { slug: "some-app" } })],
      users: { [`GET /users/${encodeURIComponent("some-app[bot]")}`]: { id: 4242 } },
    }),
  );
  assert.deepEqual(issue.comments, []);
});

const FOUR = [
  comment(11, OWNER, "**Decision recorded.** → option 1"),
  comment(12, OWNER, "Edited later."),
  comment(13, OWNER, "Before the label."),
  comment(14, OWNER, "**Decision recorded.** → option 2"),
];
const LATE_EDIT = { IC_12: { lastEditedAt: "2026-10-15T00:00:00Z", editor: { databaseId: OWNER.id } } };
const bodies = (issue) => issue.comments.map((kept) => kept.body);

test("leaves out comments created or edited after the label was added, for a human's label or the App's", async () => {
  for (const labeler of [OWNER, LANES_BOT]) {
    const { code, issue } = await run(fakeGitHub({ comments: FOUR, edits: LATE_EDIT, events: [labeled(labeler, 13)] }), {
      sender: String(labeler.id),
    });
    assert.equal(code, 0);
    assert.deepEqual(bodies(issue), ["**Decision recorded.** → option 1", "Before the label."]);
  }
});

test("the newest label event from the account that applied it is the anchor; another account's never moves it", async () => {
  const events = [labeled(OWNER, 10), labeled(OWNER, 13), labeled(STRANGER, 20), labeled(OWNER, 25, "bug")];
  const { issue } = await run(fakeGitHub({ comments: FOUR, edits: LATE_EDIT, events }));
  assert.deepEqual(bodies(issue), ["**Decision recorded.** → option 1", "Before the label."]);
  const { code } = await run(fakeGitHub({ comments: [], issueEdits: { lastEditedAt: "2026-10-15T00:00:00Z" }, events }));
  assert.equal(code, 1);
});

// A limit-stop restart (the App removing and re-adding the label) admits
// nothing new: an edit between the admitting label and the restart still fails.
test("the App's restart anchors at the label it restarted, so an edit before the restart fails", async () => {
  const restart = [labeled(OWNER, 13), unlabeled(LANES_BOT, 20), labeled(LANES_BOT, 20)];
  const app = { sender: String(LANES_BOT.id) };
  const { code, issue } = await run(fakeGitHub({ comments: [], issueEdits: { lastEditedAt: "2026-10-15T00:00:00Z" }, events: restart }), app);
  assert.equal(code, 1);
  assert.equal(issue, null);
  const kept = await run(fakeGitHub({ comments: FOUR, edits: LATE_EDIT, events: restart }), app);
  assert.deepEqual(bodies(kept.issue), ["**Decision recorded.** → option 1", "Before the label."]);
  // A first App label, as work-unblock adds it, is its own anchor.
  const first = await run(fakeGitHub({ comments: FOUR, events: [labeled(LANES_BOT, 13)] }), app);
  assert.equal(first.code, 0);
});

// Run 39098689377 on #6642: work-unblock's re-fire removed agent-ready at
// 04:53:59 and re-added it at 04:54:00, and the labeled payload's issue
// updated_at was 04:53:59, a second before its own label event.
test("an App re-fire whose payload update time predates its label event admits, anchored at the label it restarted", async () => {
  const stamp = (event, actor, created_at) => ({ event, label: { name: "agent-ready" }, actor, created_at });
  const refire = [
    stamp("labeled", OWNER, "2026-10-18T03:00:36Z"),
    stamp("unlabeled", LANES_BOT, "2026-10-18T04:53:59Z"),
    stamp("labeled", LANES_BOT, "2026-10-18T04:54:00Z"),
  ];
  const app = { sender: String(LANES_BOT.id), eventAt: "2026-10-18T04:53:59Z" };
  const before = [comment(11, OWNER, "Before the owner's label.")];
  const { code, issue } = await run(fakeGitHub({ comments: before, events: refire }), app);
  assert.equal(code, 0);
  assert.deepEqual(bodies(issue), ["Before the owner's label."]);
  // Anchored at the owner's 03:00:36 label, so a body edit between it and the re-fire still fails.
  const edited = await run(fakeGitHub({ comments: [], issueEdits: { lastEditedAt: "2026-10-18T04:00:00Z" }, events: refire }), app);
  assert.equal(edited.code, 1);
  assert.equal(edited.issue, null);
  // A sender with no label event of its own is still refused, even with the App's re-add after the update time.
  const stranger = await run(fakeGitHub({ comments: before, events: refire }), { ...app, sender: String(STRANGER.id) });
  assert.equal(stranger.code, 1);
  assert.equal(stranger.issue, null);
});

// Security review on #8037: the label a re-fire restarts is what admitted the
// text, so it must come from the App or a listed human.
test("an App re-fire that restarts an unlisted account's label writes no file", async () => {
  const restart = [labeled(OWNER, 10), unlabeled(STRANGER, 12), labeled(STRANGER, 13), unlabeled(LANES_BOT, 20), labeled(LANES_BOT, 20)];
  const { code, issue } = await run(fakeGitHub({ comments: [], events: restart }), { sender: String(LANES_BOT.id) });
  assert.equal(code, 1);
  assert.equal(issue, null);
});

// #6377: the App removed agent-ready on a pushback, a listed human edited the
// body and added `status: ready`, and the App admitted it again days later.
// That admission is fresh, not a restart, so it is the anchor.
test("the App's admission after a pushback and a trusted status: ready is its own anchor", async () => {
  const readmitted = [labeled(OWNER, 10), unlabeled(LANES_BOT, 12), labeled(OWNER, 15, "status: ready"), labeled(LANES_BOT, 20)];
  const app = { sender: String(LANES_BOT.id) };
  const between = await run(fakeGitHub({ comments: [], issueEdits: { lastEditedAt: "2026-10-15T00:00:00Z" }, events: readmitted }), app);
  assert.equal(between.code, 0);
  assert.equal(between.issue.number, 6825);
  const after = await run(fakeGitHub({ comments: [], issueEdits: { lastEditedAt: "2026-10-22T00:00:00Z" }, events: readmitted }), app);
  assert.equal(after.code, 1);
  assert.equal(after.issue, null);
});

test("an unlisted account's status: ready never turns the App's restart into an admission", async () => {
  const restart = [labeled(OWNER, 10), unlabeled(LANES_BOT, 20), labeled(STRANGER, 20, "status: ready"), labeled(LANES_BOT, 20)];
  const { code, issue } = await run(fakeGitHub({ comments: [], issueEdits: { lastEditedAt: "2026-10-15T00:00:00Z" }, events: restart }), {
    sender: String(LANES_BOT.id),
  });
  assert.equal(code, 1);
  assert.equal(issue, null);
});

test("a change in the same second as the label counts as after it", async () => {
  const { code } = await run(fakeGitHub({ comments: [], issueEdits: { lastEditedAt: "2026-10-13T12:00:00Z" }, events: [labeled(OWNER, 13)] }));
  assert.equal(code, 1);
});

// Codex P1 on #7780: a run still going when the same person removes and re-adds
// the label keeps its own admission, so it never adopts the newer text.
test("a run anchors at the label event that started it, never a later one", async () => {
  const events = [labeled(OWNER, 13), unlabeled(OWNER, 20), labeled(OWNER, 20)];
  const edited = { lastEditedAt: "2026-10-15T00:00:00Z" };
  const old = await run(fakeGitHub({ comments: [], issueEdits: edited, events }), { eventAt: "2026-10-13T12:00:00Z" });
  assert.equal(old.code, 1);
  const queued = await run(fakeGitHub({ comments: [], issueEdits: edited, events }), { eventAt: "2026-10-20T12:00:00Z" });
  assert.equal(queued.code, 0);
});

test("a missing payload update time writes no file", async () => {
  const { code, issue } = await run(fakeGitHub({ comments: [] }), { eventAt: "" });
  assert.equal(code, 1);
  assert.equal(issue, null);
});

test("no label event from the account that applied it, or a failed events read, writes no file", async () => {
  for (const github of [
    fakeGitHub({ comments: [], events: [labeled(STRANGER, 13)] }),
    fakeGitHub({ comments: [], fail: `GET /repos/${REPO}/issues/6825/events?per_page=100&page=1` }),
  ]) {
    const { code, issue } = await run(github);
    assert.equal(code, 1);
    assert.equal(issue, null);
  }
});

test("caps comments other than decisions at the newest twenty, keeping every decision", async () => {
  const many = Array.from({ length: 25 }, (_, i) => comment(i + 1, OWNER, `note ${i + 1}`));
  many.unshift(comment(0, OWNER, "**Decision recorded.** → option 1", { created_at: at(1), updated_at: at(1) }));
  const { issue } = await run(fakeGitHub({ comments: many }));
  assert.equal(MAX_OTHER_COMMENTS, 20);
  assert.equal(issue.comments.length, 21);
  assert.equal(issue.comments[0].decision, true);
  assert.equal(issue.comments[1].body, "note 6");
  assert.equal(issue.comments.at(-1).body, "note 25");
});

test("a failed comment read writes no file and fails", async () => {
  const { code, issue } = await run(
    fakeGitHub({ comments: [], fail: `GET /repos/${REPO}/issues/6825/comments?per_page=100&page=1` }),
  );
  assert.equal(code, 1);
  assert.equal(issue, null);
});

// Resume (plan: turn-cap resume, PR 3): when the run continues an earlier
// run's lane branch, issue.json carries `resume`, built by the runner from
// GET /compare between the trusted base and the branch tip: the branch, the
// cause, each commit's subject (the earlier run's words, data) and a diffstat.
const BASE_SHA = "b".repeat(40);
const TIP_SHA = "c".repeat(40);
const RESUME_ENV = {
  RESUME_BRANCH: "work-resolve-issue/issue-6825-400-1",
  RESUME_TIP: TIP_SHA,
  RESUME_CAUSE: "turn-cap",
  BASE_SHA,
};
const COMPARE_KEY = `GET /repos/${REPO}/compare/${BASE_SHA}...${TIP_SHA}`;
const COMPARISON = {
  ahead_by: 2,
  commits: [
    { commit: { message: "docs(work-items): add the frame\n\nBody text." } },
    { commit: { message: "test(work-items): cover the frame" } },
  ],
  files: [
    { filename: "plugins/work-items/README.md", additions: 12, deletions: 3 },
    { filename: "plugins/work-items/scripts/frame.test.sh", additions: 40, deletions: 0 },
  ],
};

test("a resumed run's issue.json names the branch, the cause, its commit subjects and diffstat", async () => {
  const { code, issue } = await run(fakeGitHub({ comments: [], compare: { [COMPARE_KEY]: COMPARISON } }), { extraEnv: RESUME_ENV });
  assert.equal(code, 0);
  assert.deepEqual(issue.resume, {
    branch: "work-resolve-issue/issue-6825-400-1",
    cause: "turn-cap",
    tip: TIP_SHA,
    commits: ["docs(work-items): add the frame", "test(work-items): cover the frame"],
    files: [
      { path: "plugins/work-items/README.md", additions: 12, deletions: 3 },
      { path: "plugins/work-items/scripts/frame.test.sh", additions: 40, deletions: 0 },
    ],
  });
});

// Every outcome report-outcome resumes after: a funding stop's restart
// continues its branch like a turn-cap, stopped or limited one's.
for (const cause of ["turn-cap", "stopped", "limited", "funding"]) {
  test(`a run resuming after a ${cause} stop writes its resume`, async () => {
    const { code, issue } = await run(fakeGitHub({ comments: [], compare: { [COMPARE_KEY]: COMPARISON } }), {
      extraEnv: { ...RESUME_ENV, RESUME_CAUSE: cause },
    });
    assert.equal(code, 0);
    assert.equal(issue.resume.cause, cause);
  });
}

test("a run that resumes nothing writes no resume field", async () => {
  const { code, issue } = await run(fakeGitHub({ comments: [] }));
  assert.equal(code, 0);
  assert.equal(Object.hasOwn(issue, "resume"), false);
});

test("a resume with a malformed tip, branch or cause, or an unreadable comparison, writes no issue file", async () => {
  for (const extra of [
    { RESUME_TIP: "abc" },
    { RESUME_BRANCH: "main" },
    { RESUME_BRANCH: "work-resolve-issue/issue-7-400-1" },
    { RESUME_CAUSE: "pushback" },
    { BASE_SHA: "" },
  ]) {
    const { code, issue } = await run(fakeGitHub({ comments: [], compare: { [COMPARE_KEY]: COMPARISON } }), {
      extraEnv: { ...RESUME_ENV, ...extra },
    });
    assert.equal(code, 1, JSON.stringify(extra));
    assert.equal(issue, null, JSON.stringify(extra));
  }
  const { code, issue } = await run(fakeGitHub({ comments: [] }), { extraEnv: RESUME_ENV });
  assert.equal(code, 1);
  assert.equal(issue, null);
});
