#!/usr/bin/env node
// apply-dependency-verdict.mjs: the verdict job of the pr-unblock lane's
// review-dependency round, a script activity with no model. The model job's
// runner step recorded the verdict in an artifact; this validates it and acts
// on it with the lane token (pull-requests and issues write, contents read),
// adding no judgment of its own.
//
//   1. Validates run.json strictly: the bytes the model job's runner wrote
//      (SHA-256 from that job), its gated head, and the model's structured
//      verdict, with exactly the template's fields within the limits below.
//      Anything else escalates dependency-invalid.
//   2. Re-reads the pull request. Closed: nothing, unless it is a close this
//      job started (its issue or marker is there), which resumes. merge,
//      close and escalate need the head the model reviewed; a moved head is
//      superseded and the next dispatcher run reviews the new one. fix needs
//      only commits GitHub signed for the lanes App during this workflow run
//      on top of that head, listed whole (else dependency-invalid), each file
//      only modified, a regular file, an npm or pip manifest or lock file
//      outside .github/ in a directory the base's dependabot.yml (read here,
//      never from run.json) lists, and changed only by a version change
//      (fixRefusal; else dependency-fix-refused), else
//      dependency-fix-not-landed (no commit) or superseded (Dependabot
//      rebased, or another commit).
//   3. merge: the round marker it posts, naming the reviewed head, is the
//      record the pr-merge lane merges on; this job never merges or enqueues.
//      A model that saw a truncated files listing escalates
//      dependency-files-truncated instead, and a pull request that changes a
//      workflow or action file escalates dependency-workflow-held: a person
//      merges those. Every commit on the pull request must be Dependabot's
//      own (its account ids, web-flow, a valid signature), the repository's
//      version-bump commit changing only plugin.json `version` and
//      CHANGELOG.md (bumpRefusal), or a single-parent commit whose files pass the
//      fix rule above against its parent; else dependency-fix-refused, so a
//      commit the lanes App pushed outside a fix round is never merged on.
//      A merge on a review-only dependency whose evidence does not quote each
//      matched entry's control (run.json `controls`) escalates
//      dependency-control-uncited instead.
//      close: never on a security update (the security label or an advisory
//      in the body, read fresh here, or the model job's flag), which escalates
//      dependency-security-close; otherwise finds or files the issue
//      proposing the dependabot.yml ignore entry (keyed by PR and head), posts
//      the marker, then closes the pull request, so a re-run after any
//      partial failure resumes. escalate: dependency-escalate. fix: nothing
//      more; CI judges the push.
//   4. Posts the round marker, as the lanes App, once per model run (a run
//      with no attempt is named `none`).
//
// Environment:
//   GH_TOKEN                the lane token
//   GITHUB_REPOSITORY       owner/repo
//   PR_NUMBER, HEAD_SHA     the gated pull request and its head
//   BASE_SHA                the trusted base commit; its .github/dependabot.yml
//                           gives the fix rule's [ecosystem, directory] pairs
//   DEPENDENCY_HEAD_SHA     the head the model job's gate passed, which
//                           run.json's head_sha must name
//   GITHUB_RUN_ID, DEPENDENCY_RUN_ATTEMPT  the model run the round marker names
//   APP_SENDER_ID           the lanes App bot's user id
//   DEPENDENCY_VERDICT_DIR  the downloaded artifact holding run.json
//   DEPENDENCY_RUN_SHA256   run.json's SHA-256, from the model job's runner step
//   SKIP_REASON_FILE, ESCALATION_REASON_FILE  where the runner reads them

import { createHash } from "node:crypto";
import { lstatSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import { createGitHubApi, need, positive, SHA } from "./address-feedback.mjs";
import {
  bumpRefusal,
  COMMIT_FILES_LIMIT,
  commitRefusal,
  fixRefusal,
  isActionsCommit,
  isDependabotSigned,
  isSecurityUpdate,
  isWorkflowFile,
  parseConfig,
  WEB_FLOW_ID,
} from "./dependency-classify.mjs";
import { FILES_CAP, roundLine, rounds, VERDICTS } from "./review-dependency.mjs";

export const LIMITS = { bytes: 65536, reasons: 10, reason: 500, evidence: 20, evidenceItem: 300, config: 200 };
// The compare listing stops at 250 commits and 300 files
// (docs.github.com/en/rest/commits/commits#compare-two-commits, as of
// 2026-10-17; recheck when that section changes its limits).
export const COMPARE_LIMITS = { commits: 250, files: 300 };
export const CONFIG_PATH = ".github/dependabot.yml";

// A commit GitHub signed for the lanes App during this workflow run: author
// the App, committer web-flow, signature valid, committed no earlier than
// run.json's started_at, which the model job's select step recorded before
// any model turn. An author id alone is whatever a pusher claims.
export const isLaneCommit = (commit, appId, started) =>
  Number.isInteger(commit?.author?.id) &&
  commit.author.id === appId &&
  commit.committer?.id === WEB_FLOW_ID &&
  commit.commit?.verification?.verified === true &&
  commit.commit.verification.reason === "valid" &&
  Date.parse(commit.commit.committer?.date ?? "") >= started;

class Invalid extends Error {}

// `date -u +%Y-%m-%dT%H:%M:%SZ`, as the model job's select step records it.
const STARTED_AT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

const exactKeys = (value, keys) =>
  value !== null && typeof value === "object" && !Array.isArray(value) && Object.keys(value).sort().join() === [...keys].sort().join();

// Plain prose: posted inside a fence, so no control character, fence, HTML
// comment or user @-mention can change what the comment shows or who it pings.
// An @ after a slash (a URL) or opening a scoped package (@scope/name) passes;
// that also lets a team-style @org/team through, left to the fence.
function plain(text, max) {
  return (
    typeof text === "string" &&
    text.length >= 1 &&
    text.length <= max &&
    !/[\u0000-\u001f\u007f]/.test(text) &&
    !/```|~~~|<!--|-->/.test(text) &&
    !/(^|[^A-Za-z0-9`/])@[A-Za-z0-9](?![A-Za-z0-9._-]*\/)/.test(text)
  );
}

export function validateRun(run, pr) {
  const fail = (why) => {
    throw new Invalid(`run.json is invalid: ${why}`);
  };
  if (!exactKeys(run, ["version", "pr", "head_sha", "security", "config_unreadable", "files_truncated", "started_at", "controls", "config", "output"])) fail("its fields are not the runner's");
  if (run.version !== 1) fail("version is not 1");
  if (run.pr !== pr) fail("it names another pull request");
  if (!SHA.test(String(run.head_sha))) fail("head_sha is not a commit id");
  if (typeof run.security !== "boolean") fail("security is not a boolean");
  if (typeof run.config_unreadable !== "boolean") fail("config_unreadable is not a boolean");
  if (typeof run.files_truncated !== "boolean") fail("files_truncated is not a boolean");
  if (!STARTED_AT.test(String(run.started_at)) || Number.isNaN(Date.parse(run.started_at))) fail("started_at is not a UTC time");
  if (!Array.isArray(run.controls) || run.controls.length > LIMITS.evidence || !run.controls.every((c) => typeof c === "string" && c.length >= 1)) {
    fail("controls is not a list of review-only controls");
  }
  if (!Array.isArray(run.config) || run.config.length > LIMITS.config || !run.config.every((pair) => Array.isArray(pair) && pair.length === 2 && pair.every((part) => typeof part === "string" && part.length >= 1))) {
    fail("config is not a list of [ecosystem, directory] pairs");
  }
  const out = run.output;
  if (!exactKeys(out, ["verdict", "reasons", "evidence"])) fail("the verdict's fields are not the template's");
  if (!VERDICTS.includes(out.verdict)) fail("the verdict is not merge, fix, close or escalate");
  if (!Array.isArray(out.reasons) || out.reasons.length < 1 || out.reasons.length > LIMITS.reasons) fail("reasons is not 1-10 entries");
  if (!out.reasons.every((reason) => plain(reason, LIMITS.reason))) fail("a reason is not plain prose within the limit");
  if (!Array.isArray(out.evidence) || out.evidence.length > LIMITS.evidence) fail("evidence is not 0-20 entries");
  if (!out.evidence.every((item) => plain(item, LIMITS.evidenceItem))) fail("an evidence entry is not plain prose within the limit");
  return run;
}

// The tree entry for `path` at `sha`, or undefined.
async function entryAt(api, sha, path) {
  const dir = path.slice(0, Math.max(path.lastIndexOf("/"), 0));
  const name = path.slice(dir ? dir.length + 1 : 0);
  return (await api.listTree(sha, dir)).find((entry) => entry.name === name);
}

// fixRefusal (or, with `bump`, bumpRefusal) over `files`, the change from
// `before` to `after`; a read that fails is a refusal, never a pass.
async function changeRefusal(api, files, pairs, before, after, bump = false) {
  const reads = {
    entry: (path) => entryAt(api, after, path),
    text: (side, path) => api.getText(path, side === "before" ? before : after),
  };
  try {
    return await (bump ? bumpRefusal(files, reads) : fixRefusal(files, pairs, reads));
  } catch (error) {
    return `fix-unreadable:${String(error?.message ?? error).slice(0, 120)}`;
  }
}

// Why one pull-request commit is not one the merge path may stand on, or
// null: Dependabot's own, the version-bump commit, or a single-parent commit
// whose files pass the fix rule against its parent.
async function commitFixRefusal(api, item, pairs) {
  const sha = String(item?.sha ?? "");
  if (isDependabotSigned(item)) return null;
  let detail;
  try {
    detail = SHA.test(sha) ? await api.getCommit(sha) : null;
  } catch {
    detail = null;
  }
  const files = detail?.files;
  if (!Array.isArray(files) || files.length === 0 || files.length >= COMMIT_FILES_LIMIT) return `commit-files-unreadable:${sha.slice(0, 12)}`;
  if (!Array.isArray(detail.parents) || detail.parents.length !== 1 || !SHA.test(String(detail.parents[0]?.sha))) {
    return `commit-parents:${sha.slice(0, 12)}`;
  }
  // The version-bump commit: its paths, then only a version in plugin.json.
  const bump = isActionsCommit(item) && commitRefusal(item, () => files.map((file) => String(file?.filename ?? ""))) === null;
  return changeRefusal(api, files, pairs, detail.parents[0].sha, sha, bump);
}

// The base's dependabot.yml pairs, or null when it does not read.
async function basePairs(api, baseSha) {
  try {
    return SHA.test(String(baseSha)) ? parseConfig(await api.getText(CONFIG_PATH, baseSha)) : null;
  } catch {
    return null;
  }
}

const fenced = (lines) => ["~~~text", ...lines, "~~~"].join("\n");

function roundBody({ head, verdict, run, reasons = [], evidence = [] }) {
  const parts = [
    roundLine({ head, verdict, run }),
    `The pr-unblock lane reviewed this Dependabot pull request at \`${head}\`: **${verdict}**.`,
  ];
  if (reasons.length) parts.push("", "Reasons:", "", fenced(reasons));
  if (evidence.length) parts.push("", "Evidence:", "", fenced(evidence));
  return `${parts.join("\n")}\n`;
}

const ignoreLine = (pr, head) => `<!-- pr-unblock:dependency-ignore pr=${pr} head=${head} -->`;

// The ignore-entry issue the lanes App already filed for this PR and head.
async function findIgnoreIssue(api, { pr, head, appId }) {
  const issues = await api.listIssues("state=all&labels=dependencies");
  return issues.find(
    (issue) => issue.user?.id === appId && !issue.pull_request && String(issue.body ?? "").split("\n")[0].replace(/\r$/, "") === ignoreLine(pr, head),
  );
}

function ignoreIssue({ pr, head, title, reasons }) {
  return {
    title: `chore(deps): decide whether dependabot.yml ignores the update closed in #${pr}`,
    body: [
      ignoreLine(pr, head),
      `The pr-unblock lane closed Dependabot pull request #${pr} (${JSON.stringify(String(title).slice(0, 200))}) on its review-dependency verdict.`,
      "Dependabot proposes the next version on its own; add an `ignore` entry to `.github/dependabot.yml` only if this version line should stop coming back, for example:",
      "",
      "```yaml",
      "ignore:",
      '  - dependency-name: "<name from the pull request>"',
      '    update-types: ["version-update:semver-major"]',
      "```",
      "",
      "The lane's reasons:",
      "",
      fenced(reasons),
      "",
    ].join("\n"),
    labels: ["dependencies"],
  };
}

export async function apply({ api, pr, appId, modelRun, run, baseSha, log }) {
  // One value names the model run in the marker and in the re-run check.
  const runKey = modelRun ?? "none";
  const pull = await api.getPull(pr);
  const comments = await api.listIssueComments(pr);
  const posted = rounds(comments, appId).some((round) => round.run === runKey);
  const record = async (verdict, output = {}) => {
    if (posted) {
      log(`the round marker for model run ${runKey} is already posted`);
      return;
    }
    await api.createIssueComment(pr, roundBody({ head: run?.head_sha ?? pull.head.sha, verdict, run: runKey, ...output }));
  };
  if (pull.state !== "open") {
    // A close this job started and did not finish resumes: the PR is closed
    // at the reviewed head and the lane's issue or marker is already there.
    const resumable =
      run?.output.verdict === "close" &&
      pull.head.sha === run.head_sha &&
      (posted || (await findIgnoreIssue(api, { pr, head: run.head_sha, appId })) !== undefined);
    if (!resumable) {
      log(`#${pr} is ${pull.state}; nothing applied`);
      return { escalationReason: "", skipReason: "not-applicable" };
    }
  }
  if (!run) {
    await record("invalid");
    return { escalationReason: "dependency-invalid", skipReason: "" };
  }
  const { verdict, reasons, evidence } = run.output;
  const head = pull.head.sha;
  if (verdict === "fix") {
    if (head === run.head_sha) {
      await record("fix", { reasons, evidence });
      return { escalationReason: "dependency-fix-not-landed", skipReason: "" };
    }
    const compare = await api.compare(run.head_sha, head);
    if (compare.status !== "ahead") {
      log(`#${pr}: the head moved from ${run.head_sha} to ${head} off the reviewed head; the next run reviews it`);
      return { escalationReason: "", skipReason: "superseded-sha" };
    }
    const { commits, files } = compare;
    // A listing at its limit, or short of the total, may hide a commit or a
    // path; neither is read as "nothing more".
    if (
      !Array.isArray(commits) ||
      !Array.isArray(files) ||
      commits.length >= COMPARE_LIMITS.commits ||
      files.length >= COMPARE_LIMITS.files ||
      compare.total_commits !== commits.length
    ) {
      log(`#${pr}: the comparison from ${run.head_sha} to ${head} is not listed whole`);
      await record("invalid", { reasons, evidence });
      return { escalationReason: "dependency-invalid", skipReason: "" };
    }
    const started = Date.parse(run.started_at);
    if (!commits.every((commit) => isLaneCommit(commit, appId, started))) {
      log(`#${pr}: the head moved from ${run.head_sha} to ${head} by more than the lane's fix; the next run reviews it`);
      return { escalationReason: "", skipReason: "superseded-sha" };
    }
    // The promote step already refuses this; checked again on what landed,
    // since the model job's token could write the branch itself.
    const pairs = await basePairs(api, baseSha);
    if (pairs === null) {
      await record("invalid", { reasons, evidence });
      return { escalationReason: "dependency-config-unreadable", skipReason: "" };
    }
    const refusal = await changeRefusal(api, files, pairs, run.head_sha, head);
    if (refusal) {
      log(`#${pr}: the lane's fix is refused (${refusal})`);
      await record("invalid", { reasons, evidence });
      return { escalationReason: "dependency-fix-refused", skipReason: "" };
    }
    await record("fix", { reasons, evidence });
    return { escalationReason: "", skipReason: "" };
  }
  if (head !== run.head_sha) {
    log(`#${pr}: the head moved from ${run.head_sha} to ${head} after the review; the next run reviews it`);
    return { escalationReason: "", skipReason: "superseded-sha" };
  }
  if (verdict === "merge") {
    // The content rule could not run, so no merge marker is posted on it.
    const pairs = await basePairs(api, baseSha);
    if (run.config_unreadable || pairs === null) {
      await record("escalate", { reasons, evidence });
      return { escalationReason: "dependency-config-unreadable", skipReason: "" };
    }
    // The model saw only part of the files listing.
    if (run.files_truncated) {
      await record("escalate", { reasons, evidence });
      return { escalationReason: "dependency-files-truncated", skipReason: "" };
    }
    // A bump that changes a workflow or action file waits for a person.
    const files = await api.listPullFiles(pr);
    if (!Array.isArray(files) || files.length >= FILES_CAP) {
      await record("escalate", { reasons, evidence });
      return { escalationReason: "dependency-files-truncated", skipReason: "" };
    }
    if (files.some((file) => [file.filename, file.previous_filename].filter(Boolean).some(isWorkflowFile))) {
      log(`#${pr}: the pull request changes a workflow or action file; a person merges it`);
      await record("escalate", { reasons, evidence });
      return { escalationReason: "dependency-workflow-held", skipReason: "" };
    }
    // Every commit that is not Dependabot's own: a lanes App commit pushed
    // outside a fix round reaches the head the model reviewed, and pr-merge
    // merges on this marker.
    const commits = await api.listPullCommits(pr);
    let refusal = null;
    if (
      !Array.isArray(commits) ||
      commits.length === 0 ||
      commits.length >= COMPARE_LIMITS.commits ||
      commits.length !== pull.commits ||
      commits.at(-1)?.sha !== head
    ) {
      refusal = "commits-not-listed-whole";
    }
    for (const item of refusal ? [] : commits) {
      refusal = await commitFixRefusal(api, item, pairs);
      if (refusal) break;
    }
    if (refusal) {
      log(`#${pr}: a commit is not Dependabot's or a lane fix (${refusal}); a person decides`);
      await record("escalate", { reasons, evidence });
      return { escalationReason: "dependency-fix-refused", skipReason: "" };
    }
    // A review-only dependency merges only on a verdict that quotes each
    // matched entry's control verbatim in an evidence entry.
    const uncited = run.controls.filter((control) => !evidence.some((item) => item.includes(control)));
    if (uncited.length) {
      log(`#${pr}: the merge verdict's evidence does not quote ${uncited.length} review-only control(s)`);
      await record("escalate", { reasons, evidence });
      return { escalationReason: "dependency-control-uncited", skipReason: "" };
    }
    await record("merge", { reasons, evidence });
    return { escalationReason: "", skipReason: "" };
  }
  if (verdict === "close") {
    const labels = (pull.labels ?? []).map((label) => (typeof label === "string" ? label : label.name));
    if (run.security || isSecurityUpdate({ labels, body: pull.body ?? "" })) {
      await record("escalate", { reasons, evidence });
      return { escalationReason: "dependency-security-close", skipReason: "" };
    }
    // Each step is safe to repeat, so a re-run after a partial failure
    // resumes: the issue is looked up by its marker before it is filed, the
    // round marker is posted once per model run, and only an open PR closes.
    const existing = await findIgnoreIssue(api, { pr, head: run.head_sha, appId });
    const issue = existing ?? (await api.createIssue(ignoreIssue({ pr, head: run.head_sha, title: pull.title ?? "", reasons })));
    log(`#${pr}: ${existing ? "found" : "filed"} #${issue.number} for the ignore entry`);
    await record("close", { reasons, evidence });
    if (pull.state === "open") {
      await api.closePull(pr);
    }
    log(`#${pr}: closed`);
    return { escalationReason: "", skipReason: "" };
  }
  await record("escalate", { reasons, evidence });
  return { escalationReason: "dependency-escalate", skipReason: "" };
}

export async function main(env, { api, log = (line) => console.log(line) } = {}) {
  need(env, [
    "GH_TOKEN",
    "GITHUB_REPOSITORY",
    "PR_NUMBER",
    "HEAD_SHA",
    "BASE_SHA",
    "DEPENDENCY_HEAD_SHA",
    "GITHUB_RUN_ID",
    "APP_SENDER_ID",
    "DEPENDENCY_VERDICT_DIR",
    "SKIP_REASON_FILE",
    "ESCALATION_REASON_FILE",
  ]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
  if (!SHA.test(env.HEAD_SHA)) {
    throw new Error("HEAD_SHA is not a commit id");
  }
  const attempt = env.DEPENDENCY_RUN_ATTEMPT ?? "";
  if (attempt !== "" && !/^[1-9][0-9]{0,4}$/.test(attempt)) {
    throw new Error("DEPENDENCY_RUN_ATTEMPT is not a run attempt");
  }
  const modelRun = attempt ? `${positive(env.GITHUB_RUN_ID, "GITHUB_RUN_ID")}-${attempt}` : null;
  let run = null;
  try {
    const path = join(env.DEPENDENCY_VERDICT_DIR, "run.json");
    const stat = lstatSync(path);
    if (!stat.isFile() || stat.size > LIMITS.bytes) {
      throw new Invalid("run.json is not a regular file within the size limit");
    }
    const text = readFileSync(path, "utf8");
    if (!/^[0-9a-f]{64}$/.test(env.DEPENDENCY_RUN_SHA256 ?? "") || createHash("sha256").update(text).digest("hex") !== env.DEPENDENCY_RUN_SHA256) {
      throw new Invalid("run.json does not match the SHA-256 the model job recorded");
    }
    run = validateRun(JSON.parse(text), pr);
    // The head comes from the model job's gate, not from the file.
    if (!SHA.test(env.DEPENDENCY_HEAD_SHA) || run.head_sha !== env.DEPENDENCY_HEAD_SHA) {
      throw new Invalid("run.json's head_sha is not the head the model job's gate passed");
    }
  } catch (error) {
    log(`the verdict is refused: ${String(error?.message ?? error).slice(0, 300)}`);
    run = null;
  }
  const { escalationReason, skipReason } = await apply({
    api:
      api ??
      createGitHubApi({
        token: env.GH_TOKEN,
        repository: env.GITHUB_REPOSITORY,
        apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
        graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
      }),
    pr,
    appId,
    modelRun,
    run,
    baseSha: env.BASE_SHA,
    log,
  });
  if (escalationReason) {
    writeFileSync(env.ESCALATION_REASON_FILE, `${escalationReason}\n`);
    writeFileSync(env.SKIP_REASON_FILE, "awaiting-human\n");
  } else if (skipReason) {
    writeFileSync(env.SKIP_REASON_FILE, `${skipReason}\n`);
  }
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::apply-dependency-verdict failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
