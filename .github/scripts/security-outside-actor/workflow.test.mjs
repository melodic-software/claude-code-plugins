import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { admits } from "../lib/gate-expression.mjs";
import { workflowText } from "../lib/workflow-text.mjs";
import { OUTSIDE_ACTOR_LABEL } from "../pr-merge/merge-holds.mjs";

const text = readFileSync(new URL("../../workflows/intake-label-outside-actor-activity.yml", import.meta.url), "utf8");
const wf = workflowText(text);
const condition = wf.jobIf("label-outside-actor");
const block = (name) => new RegExp(`\\n {4}${name}:\\n((?: {6}[a-z-]+: .*\\n)+)`).exec(text)[1];
const pairs = (body) => Object.fromEntries([...body.matchAll(/ {6}([a-z-]+): ([^\s#]+)/g)].map((m) => [m[1], m[2]]));
const steps = wf.steps("label-outside-actor");
const named = (name) => steps.find((step) => step.name === name).text;

const runs = (event, repository = "melodic-software/claude-code-plugins", eventName = event.pull_request ? "pull_request_target" : "issues") =>
  admits(condition, { github: { event, repository, event_name: eventName } });

const user = { type: "User", login: "stranger" };

test("the five triggers and their types, unlabeled included where the label can be removed", () => {
  const on = text.slice(text.indexOf("\non:\n"), text.indexOf("\npermissions: {}\n"));
  const triggers = [...on.matchAll(/\n {2}([a-z_]+):.*\n {4}types: \[([a-z, ]+)\]/g)].map((m) => `${m[1]} ${m[2]}`);
  assert.deepEqual(triggers, [
    "issues opened, edited, reopened, unlabeled",
    "issue_comment created, edited",
    "pull_request_review submitted, edited",
    "pull_request_review_comment created, edited",
    "pull_request_target opened, edited, synchronize, reopened, unlabeled",
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

test("a reopen or push by someone other than the content's author starts the job; a member's own does not", () => {
  const member = { id: 1, type: "User" };
  const helper = { id: 2, type: "User" };
  for (const action of ["synchronize", "reopened"]) {
    assert.equal(runs({ action, sender: helper, pull_request: { user: member, author_association: "MEMBER" } }), true, action);
    assert.equal(runs({ action, sender: member, pull_request: { user: member, author_association: "MEMBER" } }), false, action);
  }
  assert.equal(runs({ action: "reopened", sender: helper, issue: { user: member, author_association: "OWNER" } }), true);
  assert.equal(runs({ action: "reopened", sender: member, issue: { user: member, author_association: "OWNER" } }), false);
  assert.equal(runs({ action: "opened", sender: helper, issue: { user: member, author_association: "OWNER" } }), false, "only edit, push and reopen judge the sender");
});

test("a Bot sender starts no job: only Apps installed here send as Bot, so lane traffic costs nothing", () => {
  assert.equal(runs({ sender: { type: "Bot" }, issue: { author_association: "NONE" } }), false);
  assert.equal(runs({ sender: { type: "User" }, issue: { author_association: "NONE" } }), true, "a machine user is still checked");
});

test("a Bot on a fork pull request starts the job on any action; on this repository's own branch, or on an issue, it does not", () => {
  const app = { id: 9, type: "Bot" };
  const author = { id: 1, type: "User" };
  const pull = (fullName, association = "MEMBER") => ({ user: author, author_association: association, head: { repo: { full_name: fullName } } });
  const repository = "melodic-software/claude-code-plugins";
  const fork = "stranger/claude-code-plugins";
  const event = (action, fullName, association) => ({ action, sender: app, repository, pull_request: pull(fullName, association) });
  const runsIn = (e) => runs({ ...e, repository: undefined }, e.repository);
  for (const action of ["opened", "edited", "synchronize", "reopened"]) {
    assert.equal(runsIn(event(action, fork)), action !== "opened", `a Bot ${action} on a member's fork pull request (opened is the member's own act)`);
    assert.equal(runsIn(event(action, fork, "NONE")), true, `a Bot ${action} on an outsider's fork pull request`);
    assert.equal(runsIn(event(action, repository)), false, `a Bot ${action} on our own branch`);
    assert.equal(runsIn(event(action, repository, "NONE")), false, `a Bot ${action} on our own branch, outsider author`);
  }
  assert.equal(runsIn({ ...event("synchronize", null, "NONE"), pull_request: { user: author, author_association: "NONE", head: { repo: null } } }), true, "a deleted fork fails closed");
  for (const eventName of ["issues", "issue_comment"]) {
    assert.equal(runs({ action: "opened", sender: app, issue: { user: author, author_association: "NONE" } }, repository, eventName), false, `a Bot on ${eventName}`);
  }
});

test("removing security: outside-actor starts the job for any sender; removing another label starts none", () => {
  assert.ok(condition.includes(`github.event.label.name == '${OUTSIDE_ACTOR_LABEL}'`), "the gate names the label from merge-holds.mjs");
  const repository = "melodic-software/claude-code-plugins";
  const ownPull = (association) => ({ user: { id: 1 }, author_association: association, head: { repo: { full_name: repository } } });
  for (const sender of [{ id: 1, type: "User" }, { id: 2, type: "User" }, { id: 9, type: "Bot" }]) {
    for (const association of ["OWNER", "MEMBER", "NONE"]) {
      const label = { name: OUTSIDE_ACTOR_LABEL };
      assert.equal(runs({ action: "unlabeled", label, sender, pull_request: ownPull(association) }), true, `${sender.type} ${sender.id} on a ${association} pull request`);
      assert.equal(runs({ action: "unlabeled", label, sender, issue: { user: { id: 1 }, author_association: association } }), true, `${sender.type} ${sender.id} on a ${association} issue`);
      for (const other of ["needs-human", "bug"]) {
        assert.equal(runs({ action: "unlabeled", label: { name: other }, sender, issue: { user: { id: 1 }, author_association: association } }), false, `${other} removed`);
      }
    }
  }
});

test("the job holds the job token with least privilege, and no secret, App token or model", () => {
  assert.match(text, /\npermissions: \{\}\n/);
  assert.equal([...text.matchAll(/^ *permissions:/gm)].length, 2, "one workflow block and one job block");
  assert.deepEqual(pairs(block("permissions")), { contents: "read", issues: "write", "pull-requests": "write" });
  assert.doesNotMatch(text, /secrets\.|id-token|request-lane-token|create-github-app-token|claude-code-action|run-claude-cli/);
});

test("it checks out main only, without credentials, and every external action ref follows ADR 0129's pin rule", () => {
  const checkout = steps.find((step) => step.text.includes("uses: actions/checkout@")).text;
  assert.match(checkout, /\n {8}uses: actions\/checkout@v7/);
  assert.match(checkout, /\n {10}ref: \$\{\{ steps\.tip\.outputs\.sha \}\}\n {10}path: \.base\n {10}persist-credentials: false\n/);
  assert.match(named("Resolve main's tip"), /\n {10}branch: main\n$/);
  for (const [, uses] of text.matchAll(/\n +uses: ([^\s.][^\s]*)/g)) {
    assert.match(uses, /^(?:melodic-software\/\S+@main|(?:actions|github|dependabot|microsoft|azure|Azure|anthropics|openai)\/\S+@v\d+(?:\.\d+){0,2}|(?!(?:melodic-software|actions|github|dependabot|microsoft|azure|Azure|anthropics|openai)\/)\S+@[0-9a-f]{40})$/, uses);
  }
  const forkRead = "github.event.pull_request.head.repo.full_name != github.repository";
  assert.equal(text.split(forkRead).length, 2, "the fork test appears once");
  assert.ok(condition.includes(forkRead), "the fork test sits in the job's if");
  assert.doesNotMatch(text.replace(forkRead, ""), /pull_request\.head|github\.head_ref/);
});

test("no event text reaches a shell: run lines carry no expression, the script reads the payload", () => {
  for (const step of steps) {
    const run = step.text.split(/\n +run: /)[1];
    if (run !== undefined) assert.doesNotMatch(run, /\$\{\{/, step.name);
  }
  const flag = named("Flag an outside actor");
  assert.equal(
    flag,
    "      - name: Flag an outside actor\n        env:\n          GITHUB_TOKEN: ${{ github.token }}\n" +
      "          TRUSTED_ACTORS_PATH: ${{ steps.standards.outputs.path }}/components/trusted-actors/trusted-actors.json\n" +
      "          STANDARDS_DIR: ${{ steps.standards.outputs.path }}\n" +
      "        run: node .base/.github/scripts/security-outside-actor/flag.mjs\n",
  );
});

test("a failed resolve-config install does not skip the flag step", () => {
  const install = named("Install resolve-config's packages");
  assert.match(install, /\n {8}continue-on-error: true\n/);
  const flag = named("Flag an outside actor");
  assert.doesNotMatch(flag, /\n {8}if: /, "the flag step runs on the default success() condition, which a continue-on-error failure keeps");
});

test("runs on one item queue rather than cancel, and the kill switch does not stop the check", () => {
  assert.match(text, /\n {6}group: security-outside-actor-\$\{\{ github\.event\.issue\.number \|\| github\.event\.pull_request\.number \}\}\n {6}queue: max\n/);
  assert.doesNotMatch(text, /check-kill-switch/);
});
