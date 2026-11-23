import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";

import { loadRules } from "./admit.mjs";
import { isSplitParent, partitionProblem, renderSplitRecord, SIZE_SPLIT_MARKER, splitChildHeader, splitParentClosed, subsetProblem, trustedSplitChild } from "./size-split.mjs";

const VECTORS = JSON.parse(readFileSync(new URL("./split-child.vectors.json", import.meta.url), "utf8"));
const RULES = loadRules(fileURLToPath(new URL("../../actions/resolve-config/admission-rules.json", import.meta.url)));
const HUMAN = 153232337;
const OUTSIDER = 4242;
const APP = 337595936;
const humans = new Set([HUMAN]);
const LINES = ["- [ ] L1", "- [ ] L2", "  - [ ] L3"];
const TASK = "- [ ] ";

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

describe("trustedSplitChild agrees with admission", () => {
  const actorOf = (actor) => (actor ? { __typename: actor.type, databaseId: actor.id } : null);
  const commentOf = (c) => ({ databaseId: c.id, createdAt: c.created_at, updatedAt: c.updated_at, body: c.body, lastEditedAt: c.last_edited_at, author: actorOf(c.author), editor: actorOf(c.editor) });
  const reader = ({ child, parent: parentNode, parentLink }) => async (method, path, body) => {
    if (method === "POST" && path === "/graphql") {
      return { data: { repository: { issue: body.variables.number === 8 ? child : parentNode } } };
    }
    if (method === "GET" && path === "/repos/o/r/issues/8/parent") {
      if (parentLink === null) {
        throw Object.assign(new Error("404"), { status: 404 });
      }
      return parentLink;
    }
    throw new Error(`unexpected ${method} ${path}`);
  };
  for (const vector of VECTORS.cases) {
    test(`split-child vector through trustedSplitChild: ${vector.name}`, async () => {
      const appId = ("app_id" in vector ? vector.app_id : VECTORS.app_id) ?? undefined;
      const parent = VECTORS.parents[vector.parent];
      const github = reader({
        child: { body: vector.child.body, lastEditedAt: vector.child.last_edited_at, author: actorOf(vector.child.author), editor: actorOf(vector.child.editor), comments: { totalCount: 0, nodes: [] } },
        parent: parent && { body: parent.body, lastEditedAt: null, author: actorOf(parent.author), editor: null, comments: { totalCount: parent.comments.length, nodes: parent.comments.map(commentOf) } },
        parentLink: vector.child.parent === null ? null : { number: vector.child.parent.number, repository_url: `https://api.github.com/repos/${vector.child.parent.repo ?? "o/r"}` },
      });
      assert.equal(await trustedSplitChild(github, "o/r", 8, new Set(VECTORS.humans), appId, RULES["task-list"]), vector.expect.trusted, vector.expect.reason);
    });
  }
  test("a child of a parent whose body another account edited, its lines from a listed human's comment, is trusted by the lane", async () => {
    const lines = ["- [ ] Line 3 says nineteen.", "- [ ] Line 4 says twenty."];
    const user = (databaseId) => ({ __typename: "User", databaseId });
    const decision = { databaseId: 77, createdAt: "2026-10-21T00:00:00Z", updatedAt: "2026-10-21T00:00:00Z", body: `**Decision recorded.**\n\n${lines.join("\n")}`, lastEditedAt: null, author: user(HUMAN), editor: null };
    const childBody = `${splitChildHeader(5, 1, 2)}\n${lines[0]}`;
    const app = { __typename: "Bot", databaseId: APP };
    const github = reader({
      child: { body: childBody, lastEditedAt: null, author: app, editor: null, comments: { totalCount: 0, nodes: [] } },
      parent: { body: "## Done when\n\nSee the decision below.", lastEditedAt: "2026-10-20T00:00:00Z", author: user(HUMAN), editor: user(OUTSIDER), comments: { totalCount: 1, nodes: [decision] } },
      parentLink: { number: 5, repository_url: "https://api.github.com/repos/o/r" },
    });
    assert.equal(await trustedSplitChild(github, "o/r", 8, humans, APP, RULES["task-list"]), true);
  });
});

describe("splitParentClosed", () => {
  const humans = new Set([HUMAN]);
  const repository_url = "https://api.github.com/repos/o/r";
  const child = (number, state_reason = "completed") => ({ number, state: "closed", state_reason, closed_by: { id: HUMAN }, repository_url });
  const app = { id: APP, login: "melodic-automation-lanes[bot]" };
  const record = (parts = [[1], [2]], filed = [31, 32]) => ({ user: app, created_at: "2026-10-16T00:00:00Z", body: `${SIZE_SPLIT_MARKER}\n${renderSplitRecord({ items: "a".repeat(64), parts, order: [], filed })}` });
  const link = (number) => ({ event: "sub_issue_added", actor: { id: HUMAN }, created_at: "2026-10-15T00:00:00Z", sub_issue: { number, repository: { full_name: "o/r" } } });
  const closed = ({ body = "- [ ] One\n- [ ] Two", comments = [record()], children = [child(31), child(32)] } = {}) => {
    const github = async (method, path) => (path.includes("/sub_issues") ? children : path.includes("/comments") ? comments : path.includes("/events") ? [link(31), link(32)] : []);
    return splitParentClosed({
      github,
      repository: "o/r",
      issue: { number: 30, body, labels: [], state: "closed", state_reason: "completed", closed_by: { id: APP } },
      isApp: (actor) => actor?.id === APP,
      humans,
      trusted: async () => true,
    });
  };

  test("every sub-issue completed and every item covered counts", async () => {
    assert.equal(await closed(), true);
    assert.equal(await closed({ body: "- [ ] #31\n- [ ] #32", comments: [] }), true);
    assert.equal(await closed({ body: "- [x] One\n- [x] Two", comments: [] }), true);
  });
  test("a sub-issue closed as not planned, as a duplicate or with no reason does not count", async () => {
    for (const reason of ["not_planned", "duplicate", null]) {
      assert.equal(await closed({ children: [child(31), child(32, reason)] }), false, String(reason));
    }
  });
  test("a split record that leaves an item out does not count", async () => {
    assert.equal(await closed({ comments: [record([[1], [3]])] }), false, "a gap in the parts");
    assert.equal(await closed({ body: "- [ ] One\n- [ ] Two\n- [ ] Three" }), false, "an item past the parts");
    assert.equal(await closed({ comments: [record([[1], [2]], [31, 33])] }), false, "a filed number that is no sub-issue");
  });
  test("an item a listed human left on the parent does not count", async () => {
    const stays = { user: { id: HUMAN }, created_at: "2026-10-17T00:00:00Z", body: "- [ ] The broker change stays here." };
    assert.equal(await closed({ comments: [record(), stays] }), false);
    assert.equal(await closed({ body: "- [ ] #31\n- [ ] #32", comments: [stays] }), false, "split by hand");
  });
  test("an item in a listed human's comment last written before the split record was split with the rest", async () => {
    const carried = { user: { id: HUMAN }, created_at: "2026-10-15T00:00:00Z", body: "- [ ] A line a part holds." };
    assert.equal(await closed({ comments: [carried, record()] }), true);
    assert.equal(await closed({ comments: [{ ...carried, updated_at: "2026-10-17T00:00:00Z" }, record()] }), false, "edited since");
  });
  test("a split by hand with no task list does not count", async () => {
    assert.equal(await closed({ body: "## Acceptance\n\n- Prose only.", comments: [] }), false);
  });
});

describe("isSplitParent, split by hand", () => {
  const humans = new Set([HUMAN]);
  const titles = { 31: "feat(io): the parser", 32: "The writer" };
  const child = (number, repo = "o/r") => ({ number, title: titles[number], state: "closed", repository_url: `https://api.github.com/repos/${repo}` });
  const link = (number) => ({ event: "sub_issue_added", actor: { id: HUMAN }, created_at: "2026-10-15T00:00:00Z", sub_issue: { number, repository: { full_name: "o/r" } } });
  const github = async (method, path) => (path.includes("/events") ? [link(31), link(32)] : []);
  const splitParent = (body, labels = []) =>
    isSplitParent({ github, repository: "o/r", issue: { number: 30, body, labels }, comments: [], children: [child(31), child(32)], isApp: () => false, humans });

  test("every unticked item citing one of its sub-issues makes it a split parent", async () => {
    assert.equal(await splitParent("Parts:\n\n- [ ] The parser (#31)\n- [ ] The writer, #32\n- [x] Done already"), true);
  });
  test("one unticked item citing no sub-issue keeps it open", async () => {
    assert.equal(await splitParent("- [ ] The parser (#31)\n- [ ] The writer\n"), false);
  });
  test("an item citing a number that is not one of its sub-issues, here or in another repository, keeps it open", async () => {
    assert.equal(await splitParent("- [ ] The parser (#31)\n- [ ] The writer (#99)"), false);
    assert.equal(await splitParent("- [ ] The parser (#31)\n- [ ] The writer (other/repo#32)"), false);
  });
  test("a sub-issue named mid-item, or only in a link, does not cover the item", async () => {
    assert.equal(await splitParent("- [ ] #31 the parser\n- [ ] after #32 lands, update the README"), false);
    assert.equal(await splitParent("- [ ] #31 the parser\n- [ ] see [#32](https://github.com/other/repo/issues/32) for context"), false);
    assert.equal(await splitParent("- [ ] #31\n- [ ] see https://example.com/?q=#32"), false);
  });
  test("an item whose text is not its sub-issue's title is the parent's own work, wherever the citation sits", async () => {
    for (const item of ["Update the README after #32", "Write migration guide, blocked by #32", "#32 must land first, then update the README", "Test #32", "the #32", "Writer #32"]) {
      assert.equal(await splitParent(`- [ ] #31\n- [ ] ${item}`), false, item);
    }
    assert.equal(await splitParent("- [ ] **#31** The parser.\n- [ ] #32"), true);
  });
  test("a line under a cited item is more work", async () => {
    assert.equal(await splitParent("- [ ] #31\n- [ ] #32 The writer\n  - also update the README"), false);
  });
  test("a recurring issue is never a split parent, even with every item cited", async () => {
    assert.equal(await splitParent("- [ ] The parser (#31)\n- [ ] The writer (#32)", [{ name: "recurring" }]), false);
  });
});

test("partitionProblem accepts only a partition of every item into 2 or more parts with an acyclic order", () => {
  assert.equal(partitionProblem({ parts: [[1, 3], [2]], order: [[1, 2]] }, 3), null);
  assert.equal(partitionProblem({ parts: [[1], [2], [3]], order: [] }, 3), null);
  const bad = {
    "an item left out": [{ parts: [[1], [2]], order: [] }, 3],
    "an item twice": [{ parts: [[1, 2], [2, 3]], order: [] }, 3],
    "one part": [{ parts: [[1, 2, 3]], order: [] }, 3],
    "no parts": [{ parts: [], order: [] }, 3],
    "an empty part": [{ parts: [[1, 2, 3], []], order: [] }, 3],
    "a number past the items": [{ parts: [[1], [4]], order: [] }, 2],
    "an order naming no part": [{ parts: [[1], [2]], order: [[1, 3]] }, 2],
    "a cycle": [{ parts: [[1], [2], [3]], order: [[1, 2], [2, 3], [3, 1]] }, 3],
    "a part waiting on itself": [{ parts: [[1], [2]], order: [[2, 2]] }, 2],
    "a key beyond parts and order": [{ parts: [[1], [2]], order: [], exact: true }, 2],
    "a fraction": [{ parts: [[1.5], [2]], order: [] }, 2],
  };
  for (const [name, [output, count]] of Object.entries(bad)) {
    assert.notEqual(partitionProblem(output, count), null, name);
  }
});

test("subsetProblem takes only 2 or more groups of distinct targets that are verbatim task-line text, with an acyclic order", () => {
  assert.equal(subsetProblem({ groups: [["L1"], ["L2", "L3"]], order: [[1, 2]] }, LINES, 10, TASK), null);
  const bad = {
    "one group": { groups: [["L1"]], order: [] },
    "an empty group": { groups: [["L1"], []], order: [] },
    "a name not in the lines": { groups: [["L1"], ["L9"]], order: [] },
    "a name twice": { groups: [["L1"], ["L1"]], order: [] },
    "a one-character name": { groups: [["L1"], ["L"]], order: [] },
    "a name with a comma": { groups: [["L1"], ["L2, L3"]], order: [] },
    "a cycle": { groups: [["L1"], ["L2"]], order: [[1, 2], [2, 1]] },
    "too many groups": { groups: [["L1"], ["L2"], ["L3"]], order: [], max: 2 },
    "a task line no target covers": { groups: [["L1"], ["L2"]], order: [] },
    "the task-list marker as a target": { groups: [["- [ ]"], ["L1"]], order: [] },
  };
  for (const [name, { max = 10, ...output }] of Object.entries(bad)) {
    assert.notEqual(subsetProblem(output, LINES, max, TASK), null, name);
  }
  const overlap = ["- [ ] Port alpha and alpha-tools", "- [ ] Update alpha docs"];
  assert.match(subsetProblem({ groups: [["alpha"], ["alpha-tools"]], order: [] }, overlap, 10, TASK) ?? "", /another target/, "a target inside another gives two parts the same work");
  assert.match(subsetProblem({ groups: [["alpha", "alpha-tools"], ["docs"]], order: [] }, overlap, 10, TASK) ?? "", /another target/, "a target inside another gives two parts the same work");
  const long = Array.from({ length: 80 }, (_, i) => `target-${String(i).padStart(2, "0")}-${"x".repeat(90)}`);
  const wide = long.map((name) => `- [ ] Update ${name}.`);
  const fits = [long.slice(0, 2), long.slice(2, 4)];
  assert.equal(subsetProblem({ groups: fits, order: [] }, wide.slice(0, 4), 10, TASK), null);
  assert.match(subsetProblem({ groups: [long.slice(0, 40), long.slice(40)], order: [] }, wide, 10, TASK) ?? "", /split record/, "groups the split record cannot hold leave it unreadable, so the next triage would file the parts again");
});
