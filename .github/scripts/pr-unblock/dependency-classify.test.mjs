import assert from "node:assert/strict";
import { test } from "node:test";

import { classify, isMajor, isSecurityUpdate } from "./dependency-classify.mjs";

const pr = (overrides = {}) => ({
  author: "dependabot[bot]",
  headRef: "dependabot/npm_and_yarn/biomejs/biome-2.3.1",
  title: "build(deps): bump @biomejs/biome from 2.3.0 to 2.3.1",
  body: "Bumps [@biomejs/biome](https://github.com/biomejs/biome) from 2.3.0 to 2.3.1.",
  labels: ["dependencies"],
  ciStatus: "success",
  ...overrides,
});

test("a patch bump of a non-actions package is auto", () => {
  const result = classify(pr());
  assert.equal(result.tier, "auto");
  assert.deepEqual(result.reasons, []);
  assert.deepEqual(result.updates, [{ name: "@biomejs/biome", from: "2.3.0", to: "2.3.1" }]);
  assert.equal(result.ecosystem, "npm_and_yarn");
});

test("a pull request another author opened is not classified", () => {
  assert.equal(classify(pr({ author: "octocat" })), null);
});

test("a major bump is review", () => {
  const result = classify(pr({ title: "Bump @biomejs/biome from 2.3.0 to 3.0.0 in /plugins/miro/server" }));
  assert.equal(result.tier, "review");
  assert.deepEqual(result.reasons, ["major:@biomejs/biome"]);
  assert.deepEqual(result.updates, [{ name: "@biomejs/biome", from: "2.3.0", to: "3.0.0" }]);
});

test("a v-prefixed minor bump of an allowlisted action is auto", () => {
  const result = classify(
    pr({
      headRef: "dependabot/github_actions/actions/checkout-4.2.0",
      title: "build(deps): bump actions/checkout from v4.1.0 to v4.2.0",
    }),
  );
  assert.equal(result.tier, "auto");
});

test("an action from a publisher outside the allowlist is review", () => {
  const result = classify(
    pr({
      headRef: "dependabot/github_actions/zizmorcore/zizmor-action-0.2.1",
      title: "build(deps): bump zizmorcore/zizmor-action from 0.2.0 to 0.2.1",
    }),
  );
  assert.equal(result.tier, "review");
  assert.deepEqual(result.reasons, ["publisher:zizmorcore/zizmor-action"]);
});

test("a group holding one major is review, and every update is listed", () => {
  const body = [
    "Bumps the github-actions group with 2 updates: [a](x) and [b](y).",
    "",
    "Updates `actions/checkout` from 4.1.0 to 5.0.0",
    "<details>",
    "> Updates `actions/fake` from 1.0.0 to 1.0.1",
    "</details>",
    "",
    "Updates `actions/setup-node` from 6.0.0 to 6.1.0",
  ].join("\n");
  const result = classify(
    pr({
      headRef: "dependabot/github_actions/github-actions-abc123",
      title: "build(deps): bump the github-actions group with 2 updates",
      body,
    }),
  );
  assert.equal(result.tier, "review");
  assert.deepEqual(result.reasons, ["major:actions/checkout"]);
  assert.deepEqual(
    result.updates.map((update) => update.name),
    ["actions/checkout", "actions/setup-node"],
  );
});

test("a group whose listed updates do not match its count is review", () => {
  const result = classify(
    pr({
      title: "Bump the npm-minor-patch group across 1 directory with 3 updates",
      body: "Updates `a` from 1.0.0 to 1.0.1\nUpdates `b` from 2.0.0 to 2.1.0",
    }),
  );
  assert.equal(result.tier, "review");
  assert.deepEqual(result.reasons, ["unparsed-group"]);
});

test("a title with no from and to is review", () => {
  const result = classify(pr({ title: "Update everything" }));
  assert.equal(result.tier, "review");
  assert.deepEqual(result.reasons, ["unparsed-title"]);
});

test("a SHA-to-SHA bump is review", () => {
  const from = "a".repeat(40);
  const to = "b".repeat(40);
  const result = classify(pr({ title: `Bump actions/checkout from ${from} to ${to}` }));
  assert.equal(result.tier, "review");
  assert.deepEqual(result.reasons, ["unparsed-version:actions/checkout"]);
});

test("a red ci-status makes any bump review; pending does not", () => {
  assert.deepEqual(classify(pr({ ciStatus: "failure" })).reasons, ["ci-status-red"]);
  assert.deepEqual(classify(pr({ ciStatus: "timed_out" })).reasons, ["ci-status-red"]);
  assert.equal(classify(pr({ ciStatus: "pending" })).tier, "auto");
  assert.equal(classify(pr({ ciStatus: "" })).tier, "auto");
});

test("major means the first numeric component changed", () => {
  assert.equal(isMajor("1.9.9", "2.0.0"), true);
  assert.equal(isMajor("0.2.0", "0.3.0"), false);
  assert.equal(isMajor("v6", "v7"), true);
  assert.equal(isMajor("4.1", "4.2.0-rc.1"), false);
  assert.equal(isMajor("main", "4.2.0"), null);
});

test("a security update is the security label or an advisory in the body", () => {
  assert.equal(isSecurityUpdate({ labels: ["Security"], body: "" }), true);
  assert.equal(isSecurityUpdate({ labels: [], body: "Fixes GHSA-abcd-1234-wxyz." }), true);
  assert.equal(isSecurityUpdate({ labels: [], body: "Patches CVE-2026-12345" }), true);
  assert.equal(isSecurityUpdate({ labels: [], body: "See the security advisory." }), true);
  assert.equal(isSecurityUpdate({ labels: ["dependencies"], body: "Bumps x." }), false);
});

test("the classification carries the security flag", () => {
  assert.equal(classify(pr({ labels: ["security"] })).security, true);
  assert.equal(classify(pr()).security, false);
});
