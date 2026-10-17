// Expected values come from the trust rules in
// .github/actions/select-trusted-text/README.md (a comment is kept only when
// its author id is listed, it was not posted through an unlisted App, and it
// was never edited or last edited by a listed id), from the trusted-actor
// list's kinds (only a `human` entry can record a decision), and from the
// trigger gate's ratified-label rule (the issue is admitted as it stood at the
// newest ratification marker). Ids and logins are the shared trusted-actors
// fixture's.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, beforeEach, test } from "node:test";
import { fileURLToPath } from "node:url";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { MAX_OTHER_COMMENTS, main } from "./write-issue.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SHARED_LIST = path.join(HERE, "..", "..", "actions", "check-trusted-trigger", "fixtures", "trusted-actors.json");
const REPO = "melodic-software/claude-code-plugins";
const OWNER = { id: 153232337, login: "kyle-sexton" };
const LANES_BOT = { id: 337595936, login: "melodic-automation-lanes[bot]" };
const CURSOR_AGENT = { id: 199161495, login: "cursoragent" };
const STRANGER = { id: 999, login: "stranger" };
const MARKER = "<!-- admission: admitted when unblocked, owner batch ratification 2026-10-17 -->";

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

function fakeGitHub({ comments, edits = {}, users = {}, fail = "" }) {
  return async (method, apiPath, body) => {
    const key = `${method} ${apiPath}`;
    if (key === fail) {
      throw new GitHubError(502, key);
    }
    if (key === `GET /repos/${REPO}/issues/6825`) {
      return structuredClone(ISSUE);
    }
    if (key === `GET /repos/${REPO}/issues/6825/comments?per_page=100&page=1`) {
      return structuredClone(comments);
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

async function run(github, { sender = String(OWNER.id) } = {}) {
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

test("on the lanes App's ratified label, leaves out comments created or edited after the newest marker", async () => {
  const { code, issue } = await run(
    fakeGitHub({
      comments: [
        comment(11, OWNER, "**Decision recorded.** → option 1"),
        comment(12, OWNER, "Edited later."),
        comment(13, OWNER, `Admitted.\n\n${MARKER}`),
        comment(14, OWNER, "**Decision recorded.** → option 2"),
      ],
      edits: { IC_12: { lastEditedAt: "2026-10-15T00:00:00Z", editor: { databaseId: OWNER.id } } },
    }),
    { sender: String(LANES_BOT.id) },
  );
  assert.equal(code, 0);
  assert.deepEqual(
    issue.comments.map((kept) => kept.body),
    ["**Decision recorded.** → option 1", `Admitted.\n\n${MARKER}`],
  );
});

test("a human-applied label keeps comments after the marker", async () => {
  const { issue } = await run(
    fakeGitHub({
      comments: [comment(13, OWNER, `Admitted.\n\n${MARKER}`), comment(14, OWNER, "**Decision recorded.** → option 2")],
    }),
  );
  assert.equal(issue.comments.length, 2);
});

test("the lanes App's label with no kept marker writes no file", async () => {
  const { code, issue } = await run(fakeGitHub({ comments: [comment(11, OWNER, "no marker")] }), {
    sender: String(LANES_BOT.id),
  });
  assert.equal(code, 1);
  assert.equal(issue, null);
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
