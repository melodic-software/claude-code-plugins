// security-outside-actor.yml's hardening: members and Bot senders start no
// job, the job checks out main only, holds the job token with least privilege
// and no secret, and passes no event text to a shell.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const text = readFileSync(new URL("../../workflows/security-outside-actor.yml", import.meta.url), "utf8");
// The job's folded `if: >-` scalar, joined as YAML folds it.
const condition = /\n {4}if: >-\n((?: {6,}.*\n)+)/.exec(text)[1].split("\n").map((line) => line.trim()).filter(Boolean).join(" ");
const block = (name) => new RegExp(`\\n {4}${name}:\\n((?: {6}[a-z-]+: .*\\n)+)`).exec(text)[1];
const pairs = (body) => Object.fromEntries([...body.matchAll(/ {6}([a-z-]+): ([^\s#]+)/g)].map((m) => [m[1], m[2]]));
const steps = text.split(/\n {6}- name: /).slice(1);

// Evaluates the job's `if` against a payload: it uses only `github.event`
// paths, `!=`, `&&`, `||`, `!`, contains() and fromJSON() over literals.
function runs(event) {
  const get = (pathText) => pathText.split(".").reduce((value, key) => value?.[key], event) ?? null;
  const js = condition
    .replace(/github\.event\.([a-z_.]+)/g, (_, p) => `get(${JSON.stringify(p)})`)
    .replace(/fromJSON\('([^']*)'\)/g, "JSON.parse('$1')")
    .replace(/ (==|!=) /g, " $1= ");
  return new Function("get", "contains", `return Boolean(${js});`)(get, (list, item) => list.includes(item));
}

const user = { type: "User", login: "stranger" };

test("the five triggers and their types", () => {
  const on = text.slice(text.indexOf("\non:\n"), text.indexOf("\npermissions: {}\n"));
  const triggers = [...on.matchAll(/\n {2}([a-z_]+):.*\n {4}types: \[([a-z, ]+)\]/g)].map((m) => `${m[1]} ${m[2]}`);
  assert.deepEqual(triggers, [
    "issues opened, edited, reopened",
    "issue_comment created, edited",
    "pull_request_review submitted, edited",
    "pull_request_review_comment created, edited",
    "pull_request_target opened, edited, synchronize, reopened",
  ]);
});

test("an OWNER or MEMBER author starts no job, read from the comment, review, pull request or issue", () => {
  for (const association of ["OWNER", "MEMBER"]) {
    assert.equal(runs({ sender: user, issue: { author_association: association } }), false);
    assert.equal(runs({ sender: user, pull_request: { author_association: association } }), false);
    assert.equal(runs({ sender: user, issue: { author_association: "NONE" }, comment: { author_association: association } }), false);
    assert.equal(runs({ sender: user, pull_request: { author_association: "NONE" }, review: { author_association: association } }), false);
  }
});

test("an outsider's comment on a member's issue or review on a member's pull request starts the job", () => {
  assert.equal(runs({ sender: user, issue: { author_association: "OWNER" }, comment: { author_association: "NONE" } }), true);
  assert.equal(runs({ sender: user, pull_request: { author_association: "MEMBER" }, review: { author_association: "CONTRIBUTOR" } }), true);
  assert.equal(runs({ sender: user, pull_request: { author_association: "FIRST_TIME_CONTRIBUTOR" } }), true);
  assert.equal(runs({ sender: user, issue: { author_association: "COLLABORATOR" } }), true);
});

test("an edit by someone other than the content's author starts the job, whatever the author's association", () => {
  const member = { id: 1, ...user };
  const editor = { id: 2, type: "User" };
  for (const association of ["OWNER", "MEMBER"]) {
    assert.equal(runs({ action: "edited", sender: editor, issue: { user: member, author_association: association } }), true);
    assert.equal(runs({ action: "edited", sender: editor, pull_request: { user: member, author_association: association } }), true);
    assert.equal(runs({ action: "edited", sender: editor, issue: { user: editor, author_association: "NONE" }, comment: { user: member, author_association: association } }), true);
    assert.equal(runs({ action: "edited", sender: editor, pull_request: { user: editor, author_association: "NONE" }, review: { user: member, author_association: association } }), true);
    assert.equal(runs({ action: "edited", sender: member, issue: { user: member, author_association: association } }), false, "a member editing their own item");
    assert.equal(runs({ action: "created", sender: editor, issue: { user: editor }, comment: { user: member, author_association: association } }), false, "not an edit");
  }
  assert.equal(runs({ action: "edited", sender: { id: 2, type: "Bot" }, issue: { user: { id: 1 }, author_association: "MEMBER" } }), false, "a Bot editor");
});

test("a Bot sender starts no job: only Apps installed here send as Bot, so lane traffic costs nothing", () => {
  assert.equal(runs({ sender: { type: "Bot" }, issue: { author_association: "NONE" } }), false);
  assert.equal(runs({ sender: { type: "User" }, issue: { author_association: "NONE" } }), true, "a machine user is still checked");
});

test("the job holds the job token with least privilege, and no secret, App token or model", () => {
  assert.match(text, /\npermissions: \{\}\n/);
  assert.equal([...text.matchAll(/^ *permissions:/gm)].length, 2, "one workflow block and one job block");
  assert.deepEqual(pairs(block("permissions")), { contents: "read", issues: "write", "pull-requests": "write" });
  assert.doesNotMatch(text, /secrets\.|id-token|request-lane-token|create-github-app-token|claude-code-action|run-claude-cli/);
});

test("it checks out main only, without credentials, and pins every external action by SHA", () => {
  const checkout = steps.find((step) => step.includes("uses: actions/checkout@"));
  assert.match(checkout, /\n {8}uses: actions\/checkout@[0-9a-f]{40} #/);
  assert.match(checkout, /\n {10}ref: refs\/heads\/main\n {10}path: \.base\n {10}persist-credentials: false\n/);
  for (const [, uses] of text.matchAll(/\n +uses: ([^\s.][^\s]*)/g)) {
    assert.match(uses, /@[0-9a-f]{40}$/, uses);
  }
  assert.doesNotMatch(text, /pull_request\.head|github\.head_ref/);
});

test("no event text reaches a shell: run lines carry no expression, the script reads the payload", () => {
  for (const [, run] of text.matchAll(/\n +run: (.*)/g)) {
    assert.doesNotMatch(run, /\$\{\{|^[|>]/, run);
  }
  const flag = steps.find((step) => step.startsWith("Flag an outside actor\n"));
  assert.equal(
    flag,
    "Flag an outside actor\n        env:\n          GITHUB_TOKEN: ${{ github.token }}\n" +
      "          TRUSTED_ACTORS_PATH: .base/.github/standards/trusted-actors/trusted-actors.json\n" +
      "        run: node .base/.github/scripts/security-outside-actor/flag.mjs\n",
  );
});

test("runs on one item queue rather than cancel, and the kill switch does not stop the check", () => {
  assert.match(text, /\n {6}group: security-outside-actor-\$\{\{ github\.event\.issue\.number \|\| github\.event\.pull_request\.number \}\}\n {6}queue: max\n/);
  assert.doesNotMatch(text, /check-kill-switch/);
});
