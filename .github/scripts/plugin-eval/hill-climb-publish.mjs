#!/usr/bin/env node
// The steps of maintenance-measure-skill-edit.yml after a win. No model runs here, and nothing here
// reads the model's proposal: the edit is the patch the scan job checked and pass b measured, and
// the pull request text is written here from the verdict job's scripted results.
//
//   push     applies edit.patch to a checkout of the base, adds a fixed changelog fragment, checks
//            the result changes only the skill's markdown body (never its frontmatter) and that
//            fragment, and recreates it as one
//            lanes App commit on chore/hill-climb-<plugin>-<skill>-<run id> (mutate-branch)
//   body     writes the draft pull request's title and body from the win's files (no token)
//   publish  opens that branch's pull request as a draft, unless it has one (publish-artifact)
//
// The owner's grant (AL-Q11, #12035) allows chore/hill-climb-* branches and draft pull requests
// only; the broker sees neither, so this file enforces both.
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHubApi } from "../apply-patch/apply-patch.mjs";
import { api, changesHoldPath, commitNetTree, netRawDiff, readNetChanges } from "../upstream-apply-changelog/upstream-apply-changelog.mjs";
import { pathRefusal } from "./hill-climb-edit.mjs";

export const SPEC_ISSUE = 12035;
export const BRANCH_PREFIX = "chore/hill-climb-";
const NAME = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const RUN_ID = /^[1-9][0-9]{0,19}$/;
const SHA = /^[0-9a-f]{40}$/;
// A summary past this is cut, so the body stays under GitHub's 65536-character limit.
const SUMMARY_MAX = 24000;

// The one branch a run may write: the prefix and nothing the inputs can widen.
export function branchOf(plugin, skill, runId) {
  if (!NAME.test(plugin ?? "") || !NAME.test(skill ?? "") || !RUN_ID.test(String(runId ?? ""))) {
    throw new Error("the plugin, the skill or the run id is not a lowercase kebab-case name and a run id");
  }
  return `${BRANCH_PREFIX}${plugin}-${skill}-${runId}`;
}

export const titleOf = (plugin, skill) => `chore(${plugin}): apply the hill-climb edit to the ${skill} skill`;

// Named as scripts/new-changelog-fragment.sh names one, with the suffix taken from the patch, so a
// re-run builds the same tree.
export function fragmentOf(plugin, skill, branch, patch) {
  const slug = branch.toLowerCase().replace(/[^a-z0-9._-]/g, "-");
  const hex = createHash("sha256").update(patch).digest("hex").slice(0, 8);
  return {
    path: `.changes/${plugin}/${slug}-${hex}.md`,
    text: `---\nbump: patch\n---\n\n### Changed\n\n- the \`${skill}\` skill carries an edit that scored above the merged skill on its eval cases\n`,
  };
}

// The change lines of a `git diff --raw` output.
const rawLines = (raw) => raw.split("\n").filter((line) => line.startsWith(":"));

// Why the net raw diff may not be pushed, or null: only regular-file edits to the skill's markdown
// outside evals/, the one fragment added, and no hold path.
export function diffRefusal(raw, { plugin, skill, fragment }, holdPath = changesHoldPath) {
  let skillFiles = 0;
  let fragments = 0;
  for (const line of rawLines(raw)) {
    const [meta, ...paths] = line.split("\t");
    const [srcMode, dstMode] = meta.slice(1).split(" ");
    if (paths.length !== 1) return "a rename or copy";
    const [path] = paths;
    if (path === fragment) {
      if (srcMode !== "000000" || dstMode !== "100644") return "the fragment is not one new regular file";
      fragments++;
      continue;
    }
    if (srcMode !== "100644" || dstMode !== "100644") return "a change that is not an edit to a regular file";
    const refusal = pathRefusal(path, plugin, skill) ?? (path.endsWith(".md") ? null : "not a markdown file");
    if (refusal) return `a path ${refusal}`;
    skillFiles++;
  }
  if (skillFiles === 0) return "no edit to the skill";
  if (fragments !== 1) return "no changelog fragment";
  if (holdPath(raw)) return "a hold path";
  return null;
}

// A markdown file's frontmatter block: the text from an opening `---` line to the next `---` line,
// or "" when the file has none. Frontmatter is configuration (hooks, allowed-tools), not prose.
export function frontmatterOf(text) {
  const match = /^---\r?\n[\s\S]*?\r?\n---(?:\r?\n|$)/.exec(text);
  return match ? match[0] : "";
}

// Why an edit may not be pushed because it changes a file's frontmatter, or null. `show(ref, path)`
// returns the file's text at that commit.
export function frontmatterRefusal(paths, show, baseRef, headRef) {
  const changed = paths.find((path) => frontmatterOf(show(baseRef, path)) !== frontmatterOf(show(headRef, path)));
  return changed ? `a frontmatter change in ${changed}` : null;
}

// A backtick fence longer than any run of backticks in `text`, so the text cannot close it.
const fenced = (text) => {
  const longest = Math.max(2, ...[...text.matchAll(/`+/g)].map(([run]) => run.length));
  const fence = "`".repeat(longest + 1);
  return `${fence}text\n${text.replace(/\n+$/, "")}\n${fence}`;
};

// Cut at the last whitespace within SUMMARY_MAX; a single longer token is cut hard, never inside a
// surrogate pair.
const cut = (text) => {
  if (text.length <= SUMMARY_MAX) return text;
  const head = text.slice(0, SUMMARY_MAX + 1);
  const at = head.search(/\s\S*$/);
  const kept = at > 0 ? head.slice(0, at).trimEnd() : head.slice(0, SUMMARY_MAX).replace(/[\uD800-\uDBFF]$/, "");
  return `${kept}\n(cut at ${SUMMARY_MAX} characters; the run's win artifact holds the whole file)\n`;
};

// The draft's body. Everything quoted from the run sits in a fence: a summary can quote a run's
// error text, so it may carry no live markdown, link or mention.
export function bodyOf({ plugin, skill, runUrl, winTest, summaryA, summaryB, fragment }) {
  return [
    `Refs: #${SPEC_ISSUE}`,
    "",
    "## Summary",
    "",
    `A dispatched hill-climb run measured one edit to \`plugins/${plugin}/skills/${skill}/\` against the skill as merged, and the edit won: ${runUrl}. Nothing merges or marks this draft ready; a person reviews it, then marks it ready or closes it.`,
    "",
    "## Fix",
    "",
    `- The edit the run measured, as the scan job checked it: changes to the skill's markdown body only; its frontmatter is unchanged.`,
    `- \`${fragment}\`: a patch bump.`,
    "",
    "## Verification",
    "",
    "`win-test.py` over pass a (the merged skill), its repeat a2 (run-to-run noise) and pass b (the edit):",
    "",
    fenced(winTest),
    "",
    "Pass a, the merged skill, with versus without the plugin:",
    "",
    fenced(cut(summaryA)),
    "",
    "Pass b, with the edit, with versus without the plugin:",
    "",
    fenced(cut(summaryB)),
    "",
    "## Related",
    "",
    `- #${SPEC_ISSUE}, #6405`,
    `- The run, whose win artifact holds the patch and each pass's results for 3 days: ${runUrl}`,
    "",
  ].join("\n");
}

const pullsOf = (repository, branch) => `/repos/${repository}/pulls?state=all&head=${repository.split("/")[0]}:${encodeURIComponent(branch)}`;

// A re-run finds the branch: at the built tree it is this run's, and is reused; any other tree is
// not this run's, so stop.
export async function existingHead(read, repository, branch, tree) {
  const ref = await read(`/repos/${repository}/git/ref/heads/${branch}`, { allow404: true });
  if (!ref) return null;
  const tip = ref.object?.sha;
  const commit = SHA.test(tip ?? "") ? await read(`/repos/${repository}/git/commits/${tip}`) : null;
  if (commit?.tree?.sha !== tree) throw new Error("the branch already exists with another tree; delete it, then dispatch again");
  return tip;
}

// Opens the branch's pull request as a draft when the branch is still at the head push left and
// has none. Returns whether it opened one.
export async function openDraft(read, repository, { branch, head, title, body }) {
  if (!branch.startsWith(BRANCH_PREFIX) || !SHA.test(head ?? "")) throw new Error("the branch or its head is malformed");
  const ref = await read(`/repos/${repository}/git/ref/heads/${branch}`, { allow404: true });
  if (ref?.object?.sha !== head) throw new Error("the branch is not at the head the push job left");
  if ((await read(pullsOf(repository, branch))).length) return false;
  await read(`/repos/${repository}/pulls`, { method: "POST", body: { title, body, head: branch, base: "main", draft: true } });
  return true;
}

const git = (repo, args) => execFileSync("git", ["-C", repo, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();

function output(name, value) {
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `${name}=${value}\n`);
}

async function push(env) {
  const { PLUGIN: plugin, SKILL: skill, RUN_ID: runId, BASE_SHA: baseSha, PATCH_FILE, EDIT_DIR: repo, GITHUB_REPOSITORY: repository } = env;
  const branch = branchOf(plugin, skill, runId);
  if (!SHA.test(baseSha ?? "") || git(repo, ["rev-parse", "HEAD"]) !== baseSha) throw new Error("the edit checkout is not at the measured base");
  const patch = readFileSync(PATCH_FILE);
  git(repo, ["apply", "--check", PATCH_FILE]);
  git(repo, ["apply", PATCH_FILE]);
  const fragment = fragmentOf(plugin, skill, branch, patch);
  if (existsSync(join(repo, fragment.path))) throw new Error("the fragment already exists at the base");
  mkdirSync(dirname(join(repo, fragment.path)), { recursive: true });
  writeFileSync(join(repo, fragment.path), fragment.text);
  git(repo, ["add", "--all"]);
  const title = titleOf(plugin, skill);
  git(repo, ["-c", "user.name=maintenance-measure-skill-edit", "-c", "user.email=maintenance-measure-skill-edit@users.noreply.github.com", "-c", "core.hooksPath=/dev/null", "commit", "--quiet", "--no-verify", "-m", title]);
  const commit = git(repo, ["rev-parse", "HEAD"]);
  const raw = netRawDiff(repo, baseSha, commit);
  const skillPaths = rawLines(raw).map((line) => line.split("\t")[1]).filter((path) => path !== fragment.path);
  const show = (ref, path) => git(repo, ["show", `${ref}:${path}`]);
  const refusal = diffRefusal(raw, { plugin, skill, fragment: fragment.path }) ?? frontmatterRefusal(skillPaths, show, baseSha, commit);
  if (refusal) throw new Error(`the edit is refused: ${refusal}`);
  const headTree = git(repo, ["rev-parse", `${commit}^{tree}`]);
  let head = await existingHead(api, repository, branch, headTree);
  if (head) {
    console.log("the branch is already at the built tree; reused");
  } else {
    const writer = createGitHubApi({ token: env.GH_TOKEN, repository, apiUrl: env.GITHUB_API_URL || "https://api.github.com" });
    head = await commitNetTree(readNetChanges(repo, baseSha, commit), { message: title, baseSha, baseTree: git(repo, ["rev-parse", `${baseSha}^{tree}`]), headTree, api: writer });
    await writer.createRef(`refs/heads/${branch}`, head);
  }
  output("branch", branch);
  output("head", head);
  output("fragment", fragment.path);
}

function body(env) {
  const { PLUGIN: plugin, SKILL: skill, RUN_ID: runId, WIN_DIR: dir, OUT: out, RUN_URL: runUrl } = env;
  const branch = branchOf(plugin, skill, runId);
  const patch = readFileSync(join(dir, "edit.patch"));
  const read = (name) => readFileSync(join(dir, name), "utf8");
  const fragment = fragmentOf(plugin, skill, branch, patch).path;
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, "title.txt"), titleOf(plugin, skill));
  writeFileSync(join(out, "body.md"), bodyOf({ plugin, skill, runUrl, winTest: read("win-test.txt"), summaryA: read("a/summary.md"), summaryB: read("b/summary.md"), fragment }));
  output("branch", branch);
}

async function publish(env) {
  const { HEAD: head, OUT: out, GITHUB_REPOSITORY: repository } = env;
  const branch = branchOf(env.PLUGIN, env.SKILL, env.RUN_ID);
  const opened = await openDraft(api, repository, { branch, head, title: readFileSync(join(out, "title.txt"), "utf8"), body: readFileSync(join(out, "body.md"), "utf8") });
  console.log(opened ? "opened the draft pull request" : "the branch already has a pull request; none opened");
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  const commands = { push, body, publish };
  const run = commands[process.argv[2]];
  if (!run) {
    console.error("usage: hill-climb-publish.mjs push|body|publish");
    process.exit(2);
  }
  Promise.resolve()
    .then(() => run(process.env))
    .catch((error) => {
      // A failed command's message quotes its stderr, which can hold file text.
      const message = (String(error.message).startsWith("Command failed") ? "a command failed" : String(error.message)).replace(/[\r\n]+/g, " ");
      console.log(`::error::${message}`);
      // The win is in the summary already, so the stop that kept it from a pull request is too.
      if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, `gate: ${process.argv[2]}: ${message}\n`);
      process.exit(1);
    });
}
