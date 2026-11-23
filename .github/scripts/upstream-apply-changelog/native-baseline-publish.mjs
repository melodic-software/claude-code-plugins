import { appendFileSync, readFileSync } from "node:fs";
import { gzipSync, gunzipSync } from "node:zlib";

import { api } from "./upstream-apply-changelog.mjs";
import { runAsScript } from "../lib/run-main.mjs";

export const BASELINE = "docs/upstream/claude-code-native-surfaces.min.json";
const SHA = /^[0-9a-f]{40}$/;
const RELEASE = /^[0-9]+\.[0-9]+\.[0-9]+$/;
const MAX_OUTPUT = 96 * 1024;
const MAX_SUMMARY = 1024 * 1024;

const branchOf = (release) => {
  if (!RELEASE.test(release ?? "")) throw new Error("invalid Claude Code release");
  return `chore/native-surfaces-baseline-${release}`;
};
const titleOf = (release) => `chore(upstream): refresh native surfaces for Claude Code ${release}`;

function summaryOf(content, release) {
  const summary = JSON.parse(content);
  if (summary?.schema !== 1 || summary.cli_version !== release || summary.native_build !== true ||
      !["ok", "degraded"].includes(summary.integrity?.status) ||
      !summary.surfaces || !summary.detect) {
    throw new Error("expected a passing native-surface summary for the selected release");
  }
  return summary;
}

function output(env, key, value) {
  appendFileSync(env.GITHUB_OUTPUT, `${key}=${value}\n`);
}

function encode(value) {
  const encoded = gzipSync(value).toString("base64");
  if (encoded.length > MAX_OUTPUT) throw new Error("native-surface summary exceeds the job output budget");
  return encoded;
}

function decode(value) {
  if (!value || value.length > MAX_OUTPUT) throw new Error("missing or oversized native-surface output");
  return gunzipSync(Buffer.from(value, "base64"), { maxOutputLength: MAX_SUMMARY }).toString("utf8");
}

export function checkEntry({ path, type, mode }) {
  if (path !== BASELINE || type !== "blob" || mode !== "100644") {
    throw new Error("expected only the regular native-surface baseline file");
  }
}

export async function pushBaseline(read, repository, { release, base, entry, content }) {
  const branch = branchOf(release);
  checkEntry(entry);
  summaryOf(content, release);
  if (!SHA.test(base ?? "")) throw new Error("invalid baseline base commit");
  const repo = `/repos/${repository}`;
  const { tree } = await read(`${repo}/git/commits/${base}`);
  let directory = tree.sha;
  const parts = BASELINE.split("/");
  for (const [index, name] of parts.entries()) {
    const listing = await read(`${repo}/git/trees/${directory}`);
    const item = listing.tree.find(({ path }) => path === name);
    if (listing.truncated || !item) throw new Error("the base lacks the tracked native-surface baseline");
    if (index === parts.length - 1) {
      checkEntry({ ...item, path: BASELINE });
    } else if (item.type !== "tree" || item.mode !== "040000") {
      throw new Error("a baseline parent is not a directory");
    }
    directory = item.sha;
  }

  const old = await read(`${repo}/git/blobs/${directory}`);
  if (old.encoding !== "base64") throw new Error("unexpected baseline blob encoding");
  if (Buffer.from(old.content, "base64").toString("utf8") === content) return null;

  const post = (path, body) => read(`${repo}/git/${path}`, { method: "POST", body });
  const ref = await read(`${repo}/git/ref/heads/${branch}`, { allow404: true });
  const { sha: nextTree } = await post("trees", {
    base_tree: tree.sha,
    tree: [{ path: entry.path, type: entry.type, mode: entry.mode, content }],
  });
  if (ref) {
    const head = ref.object.sha;
    if (!SHA.test(head)) throw new Error("invalid existing baseline branch head");
    const commit = await read(`${repo}/git/commits/${head}`);
    if (commit.parents?.length !== 1 || commit.parents[0].sha !== base || commit.tree.sha !== nextTree) {
      throw new Error("the release baseline branch already exists with different changes");
    }
    return head;
  }
  const commit = await post("commits", { message: titleOf(release), tree: nextTree, parents: [base] });
  await post("refs", { ref: `refs/heads/${branch}`, sha: commit.sha });
  return commit.sha;
}

export async function publishBaseline(read, repository, { release, head, report }) {
  const branch = branchOf(release);
  if (!SHA.test(head ?? "")) throw new Error("invalid baseline branch head");
  const repo = `/repos/${repository}`;
  const ref = await read(`${repo}/git/ref/heads/${branch}`, { allow404: true });
  if (ref?.object?.sha !== head) throw new Error("the baseline branch moved since the push job");
  if ((await read(`${repo}/pulls?state=all&head=${repository.split("/")[0]}:${encodeURIComponent(branch)}`)).length) return false;
  await read(`${repo}/pulls`, {
    method: "POST",
    body: {
      title: titleOf(release), head: branch, base: "main", draft: false,
      body: `No related issue: each release's native-surface baseline refresh.\n\nRefreshes the native-surface baseline for release ${release}.\n\n${report}`,
    },
  });
  return true;
}

export function formatSummary(summary) {
  const lines = Object.entries(summary).map(([key, value]) => {
    if (key !== "surfaces") return `  ${JSON.stringify(key)}: ${JSON.stringify(value)}`;
    const lanes = Object.entries(value).map(([lane, records]) => {
      const entries = Object.entries(records).map(([name, record]) => `      ${JSON.stringify(name)}: ${JSON.stringify(record)}`);
      return entries.length
        ? `    ${JSON.stringify(lane)}: {\n${entries.join(",\n")}\n    }`
        : `    ${JSON.stringify(lane)}: {}`;
    });
    return `  "surfaces": {\n${lanes.join(",\n")}\n  }`;
  });
  return `{\n${lines.join(",\n")}\n}\n`;
}

function reportOf(previous, summary, diff) {
  const status = diff.inventory?.status;
  if (status !== summary.integrity.status) throw new Error("self-check and extraction verdicts differ");
  const changes = JSON.stringify({
    release: diff.cli_version,
    changed_sections: Object.keys(summary).filter((key) => JSON.stringify(summary[key]) !== JSON.stringify(previous[key])),
    surfaces: diff.surface_changes,
    docs: diff.docs_changes,
    new_candidates: diff.new_candidates,
    newly_unresolved_descriptions: diff.unresolved_descriptions?.new,
  }, null, 2);
  const clipped = changes.length > 24000 ? `${changes.slice(0, 24000)}\n… Full baseline changes are in the pull request diff.` : changes;
  const fence = "~".repeat(Math.max(3, ...Array.from(clipped.matchAll(/~+/g), ([run]) => run.length + 1)));
  return `Inventory self-check: **${status}**.\n\nSummary difference\n\n${fence}text\n${clipped}\n${fence}\n`;
}

runAsScript(import.meta.url, "native baseline", async () => {
  const env = process.env;
  const { RELEASE: release, GITHUB_REPOSITORY: repository } = env;
  switch (process.argv[2]) {
    case "report": {
      const summary = summaryOf(readFileSync(`${env.NATIVE_DIR}/summary.json`, "utf8"), release);
      const content = formatSummary(summary);
      const diff = JSON.parse(readFileSync(`${env.NATIVE_DIR}/diff.json`, "utf8"));
      const previous = readFileSync(`.base/${BASELINE}`, "utf8");
      const report = reportOf(JSON.parse(previous), summary, diff);
      appendFileSync(env.GITHUB_STEP_SUMMARY, report);
      if (previous === content) break;
      output(env, "summary", encode(content));
      output(env, "report", encode(report));
      break;
    }
    case "push": {
      const head = await pushBaseline(api, repository, {
        release, base: env.BASE_SHA, entry: { path: BASELINE, type: "blob", mode: "100644" },
        content: decode(env.BASELINE_SUMMARY),
      });
      if (head) output(env, "head", head);
      break;
    }
    case "publish":
      await publishBaseline(api, repository, { release, head: env.HEAD_SHA, report: decode(env.BASELINE_REPORT) });
      break;
    default:
      throw new Error("usage: native-baseline-publish.mjs report|push|publish");
  }
});
