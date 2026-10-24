// Expected values come from the issue that added these holds and the gate's
// own rules: the merge gate holds a manifest change that installs or runs
// something new (babysit_risk manifest-review-required, the classes #9280
// set: an executable plugin.json key or experimental.monitors; a marketplace
// plugin added, removed, renamed or re-sourced, or its name; a manifest
// removed, renamed or copied; a side that does not read or parse or repeats a
// key) and lets a userConfig default merge (#9483), holds a change to a cost path
// (babysit_risk.COST_PATHS) until the owner's cost decision, which
// babysit_merge_policy.cost_decision reads and test_babysit_merge_cost.py
// pins case by case. ci-status names its owner by the trusted-actor list, as
// its cost-only review hold step does, so a review approval lifts a hold path
// but never a cost hold.
import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { COMMENT_EDITED_QUERY, PULL_OPENED_QUERY, changeOf, costDecision, costHold, linkHold, main } from "./merge-holds.mjs";

const REPO = "owner/repo";
const LINK = "https://github.com/owner/repo/issues/40#issuecomment-7";
const PR_CREATED = "2026-10-22T10:00:00Z";
const HUMANS = new Set([5]);
const HEAD = "0123456789abcdef0123456789abcdef01234567";
const BASE = "89abcdef0123456789abcdef0123456789abcdef";

const comment = (changes = {}) => ({
  issue_url: "https://api.github.com/repos/owner/repo/issues/40",
  user: { login: "owner-person", id: 5, type: "User" },
  performed_via_github_app: null,
  body: "**Decision recorded.** Cost: approve the larger runner.",
  node_id: "IC_7",
  created_at: "2026-10-22T12:00:00Z",
  ...changes,
});

// A GitHub that answers the decision reads: the pull request's creation time
// and closing issues, comment 7, and its edit time. `fail` names a read that
// throws.
function world({ row = comment(), closing = [{ number: 40, repository: { nameWithOwner: REPO } }], node, created = PR_CREATED, fail } = {}) {
  const reads = [];
  const github = async (method, path, body) => {
    const read = body?.query === PULL_OPENED_QUERY ? "pull" : body?.query === COMMENT_EDITED_QUERY ? "edited" : `${method} ${path}`;
    reads.push(read);
    if (read === fail) {
      throw new Error(`${read} failed`);
    }
    if (read === "pull") {
      assert.deepEqual(body.variables, { owner: "owner", name: "repo", number: 99 });
      return { data: { repository: { pullRequest: { createdAt: created, closingIssuesReferences: { totalCount: closing.length, nodes: closing } } } } };
    }
    if (read === "edited") {
      assert.deepEqual(body.variables, { id: "IC_7" });
      return { data: { node: node === undefined ? { lastEditedAt: null } : node } };
    }
    assert.equal(read, "GET /repos/owner/repo/issues/comments/7");
    return row;
  };
  return { github, reads };
}

const decide = (body = `Closes #40\n\nCost decision: ${LINK}\n`, options = {}) => {
  const { github, reads } = world(options);
  return costDecision(github, REPO, 99, body, HUMANS).then((link) => ({ link, reads }));
};

test("an owner decision on the closing issue, linked from the body, clears the cost hold", async () => {
  const { link, reads } = await decide();
  assert.equal(link, LINK);
  assert.deepEqual(reads, ["pull", "GET /repos/owner/repo/issues/comments/7", "edited"]);
});

test("one on the pull request itself clears with no time check", async () => {
  const own = "https://github.com/owner/repo/pull/99#issuecomment-7";
  const row = comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/99", created_at: null });
  assert.equal((await decide(own, { row, closing: [] })).link, own);
});

test("a body with no covering link reads nothing", async () => {
  for (const body of ["Closes #40", LINK.replace("owner/repo", "evil/repo"), `Closes #40\n<!-- ${LINK} -->\n`, `Closes #40\n<!--\n${LINK}\n`]) {
    const { link, reads } = await decide(body);
    assert.equal(link, null, body);
    assert.deepEqual(reads, [], body);
  }
});

test("each failing condition of the gate's rule clears nothing", async () => {
  const cases = {
    "a decision on another issue": { closing: [{ number: 12, repository: { nameWithOwner: REPO } }] },
    "two closing issues": {
      closing: [
        { number: 40, repository: { nameWithOwner: REPO } },
        { number: 41, repository: { nameWithOwner: REPO } },
      ],
    },
    "a closing issue in another repository": { closing: [{ number: 40, repository: { nameWithOwner: "evil/repo" } }] },
    "a comment not on the linked issue": { row: comment({ issue_url: "https://api.github.com/repos/owner/repo/issues/41" }) },
    "a person not on the trusted-actor list": { row: comment({ user: { login: "someone", id: 6, type: "User" } }) },
    "a bot": { row: comment({ user: { login: "owner-person", id: 5, type: "Bot" } }) },
    "posted through an App": { row: comment({ performed_via_github_app: { slug: "cursor" } }) },
    edited: { node: { lastEditedAt: "2026-10-22T13:00:00Z" } },
    "a null node": { node: null },
    "no lastEditedAt key": { node: {} },
    "no decision line": { row: comment({ body: "Sounds fine to me." }) },
    "a quoted decision": { row: comment({ body: "> **Decision recorded.** Cost: quoted" }) },
    "no cost marker": { row: comment({ body: "**Decision recorded.** Option 2." }) },
    "a cost marker on the next line": { row: comment({ body: "**Decision recorded.**\nCost: approve it." }) },
    "a decision older than the pull request": { row: comment({ created_at: "2026-10-21T09:00:00Z" }) },
    "a decision at the pull request's creation": { row: comment({ created_at: PR_CREATED }) },
    "no comment time": { row: comment({ created_at: null }) },
    "no pull request time": { created: "" },
    "an unreadable pull request": { fail: "pull" },
    "an unreadable comment": { fail: "GET /repos/owner/repo/issues/comments/7" },
    "an unreadable edit time": { fail: "edited" },
  };
  for (const [name, options] of Object.entries(cases)) {
    assert.equal((await decide(undefined, options)).link, null, name);
  }
});

test("a decision line after leading blank lines still counts", async () => {
  assert.equal((await decide(undefined, { row: comment({ body: "\n  **Decision recorded.**\tCost: yes" }) })).link, LINK);
});

test("costHold holds a cost path, case-folded, until a decision", () => {
  for (const path of ["plugins/multi-agent/reference/defaults.yaml", "Pulumi.yaml", "infra/pulumi.Dev.yaml", "infra/.x/main.TF", "a.tfvars", "deploy/main.bicep", "deploy/main.bicepparam"]) {
    assert.match(costHold([path], null), new RegExp(`it changes ${path.replaceAll(".", "\\.")}, a cost path`), path);
    assert.equal(costHold([path], LINK), null, path);
  }
  assert.equal(costHold(["docs/a.md", "plugins/multi-agent/reference/other.yaml", "Pulumi.md"], null), null);
  assert.equal(costHold(null, null), null);
});

// ci-status: merge-holds.mjs's command line on the live files, as the
// workflow step runs it, with a GitHub for the decision reads.
// A `files` entry is a path, or a files API row; `texts` maps
// `<path>@<sha>` to a manifest's text, which the contents API answers.
function ci(files, { reviews = [], body = "Closes #40", options, texts = {} } = {}) {
  const dir = mkdtempSync(join(tmpdir(), "merge-holds-"));
  writeFileSync(join(dir, "body"), body);
  writeFileSync(join(dir, "discussion"), reviews.map((row) => JSON.stringify(row)).join("\n"));
  writeFileSync(join(dir, "actors"), JSON.stringify({ actors: [{ kind: "human", login: "owner-person", id: 5 }] }));
  writeFileSync(join(dir, "files"), files.map((row) => JSON.stringify(typeof row === "string" ? [row] : row)).join("\n"));
  writeFileSync(join(dir, "denied"), "[]");
  const argv = ["99", ...["body", "discussion", "files", "denied", "actors"].map((name) => join(dir, name)), HEAD];
  const { github: decisions } = world(options);
  const github = async (method, path, data) => {
    const read = /^\/repos\/owner\/repo\/contents\/(.+)\?ref=([0-9a-f]{40})$/.exec(path);
    if (!read) {
      return decisions(method, path, data);
    }
    const text = texts[`${decodeURIComponent(read[1])}@${read[2]}`];
    if (text === undefined) {
      throw new Error("not found");
    }
    return { type: "file", encoding: "base64", content: Buffer.from(text).toString("base64") };
  };
  const lines = [];
  const log = console.log;
  console.log = (line) => lines.push(line);
  return main(argv, { env: { GITHUB_REPOSITORY: REPO, BASE_SHA: BASE }, github }).then(
    (code) => {
      console.log = log;
      return { code, out: lines.join("\n") };
    },
    (error) => {
      console.log = log;
      throw error;
    },
  );
}
const approve = { user: { login: "owner-person", id: 5, type: "User" }, state: "APPROVED", commit_id: HEAD, submitted_at: "2026-10-23T11:00:00Z" };

const PLUGIN = "plugins/foo/.claude-plugin/plugin.json";
const MARKET = ".claude-plugin/marketplace.json";
const PLUGIN_BASE = '{"name": "foo", "version": "1.0.0", "userConfig": {"guard_enabled": {"type": "boolean", "default": true}}}';
const MARKET_BASE = '{"name": "m", "plugins": [{"name": "foo", "source": "./plugins/foo", "category": "dev"}]}';
const withKey = (key) => PLUGIN_BASE.replace('"name": "foo",', `"name": "foo", ${key},`);
// One manifest change through ci-status: its files API row and its sides.
const manifest = (path, before, after, row = {}) =>
  ci([{ filename: path, status: "modified", ...row }], {
    texts: { ...(before === undefined ? {} : { [`${path}@${BASE}`]: before }), ...(after === undefined ? {} : { [`${path}@${HEAD}`]: after }) },
  });

test("ci-status holds every manifest change the merge gate reviews", async () => {
  const cases = {
    hooks: [PLUGIN, PLUGIN_BASE, withKey('"hooks": "./h.json"'), "hooks"],
    mcpServers: [PLUGIN, PLUGIN_BASE, withKey('"mcpServers": {}'), "mcpServers"],
    lspServers: [PLUGIN, PLUGIN_BASE, withKey('"lspServers": {}'), "lspServers"],
    monitors: [PLUGIN, PLUGIN_BASE, withKey('"monitors": []'), "monitors"],
    "experimental.monitors": [PLUGIN, PLUGIN_BASE, withKey('"experimental": {"monitors": []}'), "experimental.monitors"],
    "a plugin added": [MARKET, MARKET_BASE, MARKET_BASE.replace("]}", ', {"name": "bar", "source": "./plugins/bar"}]}'), "plugins[bar] added"],
    "a plugin removed": [MARKET, MARKET_BASE, '{"name": "m", "plugins": []}', "plugins[foo] removed"],
    "a plugin renamed": [MARKET, MARKET_BASE, MARKET_BASE.replace('"name": "foo"', '"name": "fob"'), "plugins[fob] added, plugins[foo] removed"],
    "a plugin source changed": [MARKET, MARKET_BASE, MARKET_BASE.replace("./plugins/foo", "https://example.com/foo.git"), "plugins[foo].source"],
    "the marketplace name changed": [MARKET, MARKET_BASE, MARKET_BASE.replace('"name": "m"', '"name": "n"'), "name"],
    "a parse error": [PLUGIN, PLUGIN_BASE, "{", "unreadable, malformed or a repeated key"],
    "a duplicate key": [PLUGIN, PLUGIN_BASE, withKey('"name": "x"'), "unreadable, malformed or a repeated key"],
    "an unreadable side": [PLUGIN, undefined, PLUGIN_BASE, "contents unreadable"],
  };
  for (const [name, [path, before, after, found]] of Object.entries(cases)) {
    const held = await manifest(path, before, after);
    assert.equal(held.code, 1, name);
    assert.ok(held.out.includes(`it changes ${path} (${found}), a manifest change that needs review`), `${name}: ${held.out}`);
  }
  for (const [name, row] of Object.entries({
    removed: { status: "removed" },
    renamed: { status: "renamed", previous_filename: "plugins/foo/plugin.json" },
    copied: { status: "copied", previous_filename: "plugins/bar/.claude-plugin/plugin.json" },
  })) {
    const held = await manifest(PLUGIN, PLUGIN_BASE, PLUGIN_BASE, row);
    assert.equal(held.code, 1, name);
    assert.ok(held.out.includes(`(${name} manifest)`), `${name}: ${held.out}`);
  }
  // Renamed away from a manifest path holds too.
  const away = await ci([{ filename: "plugins/foo/plugin.json", previous_filename: PLUGIN, status: "renamed" }]);
  assert.ok(away.out.includes("(renamed manifest)"), away.out);
});

test("ci-status passes a manifest change the merge gate does not review, such as a userConfig default (#9483)", async () => {
  for (const [path, before, after] of [
    [PLUGIN, PLUGIN_BASE, PLUGIN_BASE.replace('"default": true', '"default": false')],
    [PLUGIN, PLUGIN_BASE, PLUGIN_BASE.replace("1.0.0", "1.1.0")],
    [MARKET, MARKET_BASE, MARKET_BASE.replace('"dev"', '"tools"')],
  ]) {
    const passed = await manifest(path, before, after);
    assert.equal(passed.code, 0, passed.out);
    assert.match(passed.out, /no body hold, no member veto and no hold path\./);
  }
  const added = await ci([{ filename: PLUGIN, status: "added" }], { texts: { [`${PLUGIN}@${HEAD}`]: PLUGIN_BASE } });
  assert.equal(added.code, 0, added.out);
});

test("a trusted approval of the head lifts a manifest hold", async () => {
  const hooked = withKey('"hooks": {}');
  const texts = { [`${PLUGIN}@${BASE}`]: PLUGIN_BASE, [`${PLUGIN}@${HEAD}`]: hooked };
  const lifted = await ci([{ filename: PLUGIN, status: "modified" }], { texts, reviews: [approve] });
  assert.equal(lifted.code, 0, lifted.out);
  assert.match(lifted.out, /owner-person approved this head, which lifts its hold path/);
});

test("an old files line, with no status, holds a manifest", async () => {
  const held = await ci([MARKET]);
  assert.equal(held.code, 1);
  assert.match(held.out, /\.claude-plugin\/marketplace\.json \(unknown manifest\)/);
});

test("ci-status holds a cost path that an approval does not lift, and the owner's decision does", async () => {
  const held = await ci(["infra/main.tf"]);
  assert.equal(held.code, 1);
  assert.match(held.out, /it changes infra\/main\.tf, a cost path/);
  const approved = await ci(["infra/main.tf"], { reviews: [approve] });
  assert.equal(approved.code, 1);
  assert.match(approved.out, /a cost path/);
  const decided = await ci(["infra/main.tf"], { body: `Closes #40\n\n${LINK}` });
  assert.equal(decided.code, 0, decided.out);
  assert.match(decided.out, /no body hold, no member veto and no hold path\./);
  assert.equal((await ci(["infra/main.tf"], { body: `Closes #40\n\n${LINK}`, options: { node: { lastEditedAt: "2026-10-22T13:00:00Z" } } })).code, 1);
});

// The live link a pass binds, by the gate's rule (README "Eligibility"): one
// closing issue in this repository, or, with none, one plain `Refs: #<n>`
// issue; a pass binds only the issue it judged, linked the same way
// (babysit_verify_evidence.py _pass_refusal: verify:spec-changed otherwise).
test("linkHold binds a pass to the issue and link kind it judged", () => {
  const closes = (...numbers) => ({ totalCount: numbers.length, nodes: numbers.map((number) => ({ number, repository: { nameWithOwner: "o/r" } })) });
  const record = (number, spec_kind) => ({ linked_issues: [{ number }], ...(spec_kind ? { spec_kind } : {}) });
  assert.equal(linkHold(record(5, "closes"), "Closes #5", closes(5), "o/r"), null);
  // A record from before the kind was written judged a closing issue.
  assert.equal(linkHold(record(5), "Closes #5", closes(5), "O/R"), null);
  assert.equal(linkHold(record(5, "refs"), "Refs: #5\n\n## Summary", closes(), "o/r"), null);
  assert.match(linkHold(record(5, "refs"), "Closes #6", closes(6), "o/r"), /link changed since pr-verify passed it: it closes #6, and the pass judged #5 \(refs\)/);
  assert.match(linkHold(record(5, "refs"), "Closes #5", closes(5), "o/r"), /link changed/);
  assert.match(linkHold(record(5, "closes"), "Refs: #5", closes(), "o/r"), /link changed/);
  assert.match(linkHold(record(5, "refs"), "Refs: #6", closes(), "o/r"), /refs #6, and the pass judged #5/);
  assert.match(linkHold(record(5, "refs"), "Refs: #5\nRefs: #6", closes(), "o/r"), /names no issue/);
  assert.match(linkHold(record(5, "refs"), "<!-- Refs: #5 -->", closes(), "o/r"), /names no issue/);
  assert.match(linkHold(record(5, "closes"), "Closes #5", closes(5, 6), "o/r"), /exactly one issue/);
  assert.match(
    linkHold(record(5, "closes"), "Closes x/y#5", { totalCount: 1, nodes: [{ number: 5, repository: { nameWithOwner: "x/y" } }] }, "o/r"),
    /exactly one issue/,
  );
  assert.match(linkHold(record(5, "pull-request"), "", closes(), "o/r"), /kind 'pull-request'/);
  assert.match(linkHold(null, "Closes #5", closes(5), "o/r"), /record could not be read/);
  assert.match(linkHold({ linked_issues: [{ number: 5 }, { number: 6 }] }, "Closes #5", closes(5), "o/r"), /link changed/);
  assert.match(linkHold(record(5), "Closes #5", { totalCount: 11, nodes: [] }, "o/r"), /closing issues could not be read/);
});

// ci-status writes [filename, previous_filename, status]; an older line has
// no status, which holds a manifest.
test("changeOf reads a files line with and without its status", () => {
  assert.deepEqual(changeOf(["a.md", null, "modified"]), { path: "a.md", previous: null, status: "modified" });
  assert.deepEqual(changeOf(["b.md", "a.md", "renamed"]), { path: "b.md", previous: "a.md", status: "renamed" });
  assert.deepEqual(changeOf(["b.md", "a.md"]), { path: "b.md", previous: "a.md", status: null });
  assert.deepEqual(changeOf(["a.md"]), { path: "a.md", previous: null, status: null });
  assert.throws(() => changeOf("a.md"), /does not read/);
});
