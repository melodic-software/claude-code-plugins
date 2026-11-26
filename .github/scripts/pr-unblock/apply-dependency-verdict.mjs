#!/usr/bin/env node
import { createHash } from "node:crypto";
import { lstatSync, readFileSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";

import { CDN_RECORD, cdnPaths } from "../apply-patch/cdn-paths.mjs";
import { runAsScript } from "../lib/run-main.mjs";
import { STOP_REASONS } from "../lib/stop-reason.mjs";
import { createGitHubApi, need, positive, scanRefusal, SHA } from "./address-feedback.mjs";
import {
  cdnSyncRefusal,
  COMMIT_FILES_LIMIT,
  fixRefusal,
  isDependabotSigned,
  isSecurityUpdate,
  parseConfig,
  pinSwapRefusal,
  pushRefusal,
  WEB_FLOW_ID,
} from "./dependency-classify.mjs";
import { stopSkip } from "./escalation-routes.mjs";
import { FILES_CAP, roundLine, rounds, VERDICTS } from "./review-dependency.mjs";

export const LIMITS = { bytes: 65536, reasons: 10, reason: 500, evidence: 20, evidenceItem: 300, config: 200 };
// https://docs.github.com/en/rest/pulls/pulls#list-commits-on-a-pull-request
export const PR_COMMITS = 250;
export const CONFIG_PATH = ".github/dependabot.yml";

export const isLaneCommit = (commit, appId, started) =>
  Number.isInteger(commit?.author?.id) &&
  commit.author.id === appId &&
  commit.committer?.id === WEB_FLOW_ID &&
  commit.commit?.verification?.verified === true &&
  commit.commit.verification.reason === "valid" &&
  Date.parse(commit.commit.committer?.date ?? "") >= started;

class Invalid extends Error {}

const STARTED_AT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

const exactKeys = (value, keys) =>
  value !== null && typeof value === "object" && !Array.isArray(value) && Object.keys(value).sort().join() === [...keys].sort().join();

export const UNPLAIN_PATTERN = String.raw`[\u0000-\u001f\u007f]|${"```"}|~~~|<!--|-->|(^|[^A-Za-z0-9${"`"}/])@[A-Za-z0-9][A-Za-z0-9._-]*([^A-Za-z0-9._/-]|$)`;
const UNPLAIN = new RegExp(UNPLAIN_PATTERN);

function plain(text, max) {
  return typeof text === "string" && text.length >= 1 && text.length <= max && !UNPLAIN.test(text);
}

export const CONTEXT_KEYS = Object.freeze(["version", "pr", "head_sha", "security", "config_unreadable", "files_truncated", "started_at", "controls", "config"]);

export function validateContext(run, pr) {
  const fail = (why) => {
    throw new Invalid(`context.json is invalid: ${why}`);
  };
  if (!exactKeys(run, CONTEXT_KEYS)) fail("its fields are not the select job's");
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
  return run;
}

export const VERDICT_KEYS = Object.freeze(["verdict", "owner_reason", "reasons", "evidence"]);

export const escalateReason = (ownerReason) => `dependency-escalate-${ownerReason}`;

export function validateVerdict(out) {
  const fail = (why) => {
    throw new Invalid(`dependency-verdict.json is invalid: ${why}`);
  };
  if (!exactKeys(out, VERDICT_KEYS)) fail("the verdict's fields are not the template's");
  if (!VERDICTS.includes(out.verdict)) fail("the verdict is not merge, fix, close or escalate");
  if (!STOP_REASONS.includes(out.owner_reason)) fail(`owner_reason is not one of ${STOP_REASONS.join(", ")}`);
  if (!Array.isArray(out.reasons) || out.reasons.length < 1 || out.reasons.length > LIMITS.reasons) fail("reasons is not 1-10 entries");
  if (!out.reasons.every((reason) => plain(reason, LIMITS.reason))) fail("a reason is not plain prose within the limit");
  if (!Array.isArray(out.evidence) || out.evidence.length > LIMITS.evidence) fail("evidence is not 0-20 entries");
  if (!out.evidence.every((item) => plain(item, LIMITS.evidenceItem))) fail("an evidence entry is not plain prose within the limit");
  return out;
}

export function validateRun(run, pr) {
  if (run === null || typeof run !== "object" || Array.isArray(run)) {
    throw new Invalid("the round's record is not an object");
  }
  const { output, ...context } = run;
  return { ...validateContext(context, pr), output: validateVerdict(output) };
}

async function entryAt(api, sha, path) {
  const dir = path.slice(0, Math.max(path.lastIndexOf("/"), 0));
  const name = path.slice(dir ? dir.length + 1 : 0);
  return (await api.listTree(sha, dir)).find((entry) => entry.name === name);
}

async function changeRefusal(api, files, pairs, before, after) {
  const reads = {
    entry: (path) => entryAt(api, after, path),
    text: (side, path) => api.getText(path, side === "before" ? before : after),
  };
  try {
    return await fixRefusal(files, pairs, reads);
  } catch (error) {
    return `fix-unreadable:${String(error?.message ?? error).slice(0, 120)}`;
  }
}

async function commitFixRefusal(api, item, pairs, appId, cdn, headRef) {
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
  const parent = detail.parents[0].sha;
  const fix = await changeRefusal(api, files, pairs, parent, sha);
  if (!fix) return null;
  let sync;
  try {
    sync = await cdnSyncRefusal(detail, appId, cdn, (side, path) => entryAt(api, side === "before" ? parent : sha, path), headRef);
  } catch (error) {
    sync = `cdn-sync-unreadable:${String(error?.message ?? error).slice(0, 120)}`;
  }
  return sync ? `${fix};${sync}` : null;
}

async function baseCdnPaths(api, baseSha) {
  try {
    const text = SHA.test(String(baseSha)) ? await api.getText(CDN_RECORD, baseSha) : null;
    return text === null ? null : new Set(cdnPaths(JSON.parse(text)));
  } catch {
    return null;
  }
}

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

async function findIgnoreIssue(api, { pr, head, appId }) {
  const issues = await api.listIssues("state=all&labels=dependencies");
  return issues.find(
    (issue) => issue.user?.id === appId && !issue.pull_request && String(issue.body ?? "").split("\n")[0].replace(/\r$/, "") === ignoreLine(pr, head),
  );
}

const IGNORE_ISSUE_TYPE = "Task";

function ignoreIssue({ pr, head, title, reasons }) {
  return {
    title: `Decide whether dependabot.yml ignores the update closed in #${pr}`,
    type: IGNORE_ISSUE_TYPE,
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

export async function apply({ api, pr, appId, modelRun, run, context = null, missing = false, patchState = "", refused = "", baseSha, log }) {
  const runKey = modelRun ?? "none";
  const pull = await api.getPull(pr);
  const comments = await api.listIssueComments(pr);
  const posted = modelRun !== null && modelRun !== undefined && rounds(comments, appId).some((round) => round.run === runKey);
  const record = async (verdict, output = {}) => {
    if (posted) {
      log(`the round marker for model run ${runKey} is already posted`);
      return;
    }
    await api.createIssueComment(pr, roundBody({ head: (run ?? context)?.head_sha ?? pull.head.sha, verdict, run: runKey, ...output }));
  };
  if (pull.state !== "open") {
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
    if (context !== null && missing) {
      if (refused === "patch") {
        log(`#${pr}: the scan refused the round's patch as too large, so no fix can land`);
        return { escalationReason: "dependency-fix-not-landed", skipReason: "" };
      }
      if (refused === "" && patchState === "" && pull.head.sha === context.head_sha) {
        log(`#${pr}: no verdict and no patch: the model took no turn`);
        return { escalationReason: "", skipReason: "no-model-turn" };
      }
    }
    return { escalationReason: "dependency-invalid", skipReason: "" };
  }
  const { verdict, reasons, evidence } = run.output;
  const end = async (marker, escalationReason) => {
    await record(marker, { reasons, evidence });
    return { escalationReason, skipReason: "" };
  };
  const head = pull.head.sha;
  if (verdict === "fix") {
    if (head === run.head_sha) {
      return end("fix", "dependency-fix-not-landed");
    }
    const compare = await api.compareWhole(run.head_sha, head);
    if (compare.status !== "ahead") {
      log(`#${pr}: the head moved from ${run.head_sha} to ${head} off the reviewed head; the next run reviews it`);
      return { escalationReason: "", skipReason: "superseded-sha" };
    }
    const { commits, files } = compare;
    if (!Array.isArray(commits) || !Array.isArray(files) || compare.total_commits !== commits.length) {
      log(`#${pr}: the comparison from ${run.head_sha} to ${head} is not listed whole`);
      return end("invalid", "dependency-invalid");
    }
    const started = Date.parse(run.started_at);
    if (!commits.every((commit) => isLaneCommit(commit, appId, started))) {
      log(`#${pr}: the head moved from ${run.head_sha} to ${head} by more than the lane's fix; the next run reviews it`);
      return { escalationReason: "", skipReason: "superseded-sha" };
    }
    const pairs = await basePairs(api, baseSha);
    if (pairs === null) {
      return end("invalid", "dependency-config-unreadable");
    }
    const refusal = await changeRefusal(api, files, pairs, run.head_sha, head);
    if (refusal) {
      log(`#${pr}: the lane's fix is refused (${refusal})`);
      return end("invalid", "dependency-fix-refused");
    }
    return end("fix", "");
  }
  if (head !== run.head_sha) {
    log(`#${pr}: the head moved from ${run.head_sha} to ${head} after the review; the next run reviews it`);
    return { escalationReason: "", skipReason: "superseded-sha" };
  }
  if (verdict === "merge") {
    const pairs = await basePairs(api, baseSha);
    if (run.config_unreadable || pairs === null) {
      return end("escalate", "dependency-config-unreadable");
    }
    if (run.files_truncated) {
      return end("escalate", "dependency-files-truncated");
    }
    const files = await api.listPullFiles(pr);
    if (!Array.isArray(files) || files.length >= FILES_CAP) {
      return end("escalate", "dependency-files-truncated");
    }
    const unpinned = pinSwapRefusal(files);
    if (unpinned) {
      log(`#${pr}: a workflow or action file change is not a pin swap (${unpinned})`);
      return end("escalate", "dependency-workflow-unpinned");
    }
    const commits = pull.commits >= PR_COMMITS ? (await api.compareWhole(baseSha, head)).commits : await api.listPullCommits(pr);
    let refusal = null;
    if (
      !Array.isArray(commits) ||
      commits.length === 0 ||
      commits.length !== pull.commits ||
      commits.at(-1)?.sha !== head
    ) {
      refusal = "commits-not-listed-whole";
    }
    let cdnRead;
    const cdn = () => (cdnRead ??= baseCdnPaths(api, baseSha));
    for (const item of refusal ? [] : commits) {
      refusal = await commitFixRefusal(api, item, pairs, appId, cdn, pull.head?.ref);
      if (refusal) break;
    }
    refusal ??= pushRefusal(await api.listActivity(pull.head.ref), head, commits, appId);
    if (refusal) {
      log(`#${pr}: a commit is not Dependabot's or a lane fix, or not its pusher's own (${refusal}); a person decides`);
      return end("escalate", "dependency-fix-refused");
    }
    const uncited = run.controls.filter((control) => !evidence.some((item) => item.includes(control)));
    if (uncited.length) {
      log(`#${pr}: the merge verdict's evidence does not quote ${uncited.length} review-only control(s)`);
      return end("escalate", "dependency-control-uncited");
    }
    return end("merge", "");
  }
  if (verdict === "close") {
    const labels = (pull.labels ?? []).map((label) => (typeof label === "string" ? label : label.name));
    if (run.security || isSecurityUpdate({ labels, body: pull.body ?? "" })) {
      return end("escalate", "dependency-security-close");
    }
    const existing = await findIgnoreIssue(api, { pr, head: run.head_sha, appId });
    const issue = existing ?? (await api.createIssue(ignoreIssue({ pr, head: run.head_sha, title: pull.title ?? "", reasons })));
    log(`#${pr}: ${existing ? "found" : "filed"} #${issue.number} for the ignore entry`);
    if (!existing && issue.type?.name !== IGNORE_ISSUE_TYPE) {
      log(`::warning::#${issue.number} came back without Issue Type ${IGNORE_ISSUE_TYPE}`);
    }
    await record("close", { reasons, evidence });
    if (pull.state === "open") {
      await api.closePull(pr);
    }
    log(`#${pr}: closed`);
    return { escalationReason: "", skipReason: "" };
  }
  return end("escalate", escalateReason(run.output.owner_reason));
}

function readChecked(path, sha256, who) {
  let stat;
  try {
    stat = lstatSync(path);
  } catch (error) {
    if (error.code === "ENOENT") return null;
    throw error;
  }
  if (!stat.isFile() || stat.size > LIMITS.bytes) {
    throw new Invalid(`${basename(path)} is not a regular file within the size limit`);
  }
  const text = readFileSync(path, "utf8");
  if (!/^[0-9a-f]{64}$/.test(sha256 ?? "") || createHash("sha256").update(text).digest("hex") !== sha256) {
    throw new Invalid(`${basename(path)} does not match the SHA-256 ${who} recorded`);
  }
  return JSON.parse(text);
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
  const patchState = env.DEPENDENCY_PATCH_STATE ?? "";
  if (!["", "written", "empty"].includes(patchState)) {
    throw new Error("DEPENDENCY_PATCH_STATE is not a scan output");
  }
  const refused = scanRefusal({ dir: env.SCAN_REFUSED_DIR ?? "", read: env.SCAN_REFUSED_READ ?? "" });
  const modelRun = attempt ? `${positive(env.GITHUB_RUN_ID, "GITHUB_RUN_ID")}-${attempt}` : null;
  let context = null;
  let run = null;
  let missing = false;
  try {
    context = readChecked(join(env.DEPENDENCY_VERDICT_DIR, "context.json"), env.DEPENDENCY_RUN_SHA256, "the select job");
    if (context === null) throw new Invalid("context.json is missing");
    validateContext(context, pr);
    if (!SHA.test(env.DEPENDENCY_HEAD_SHA) || context.head_sha !== env.DEPENDENCY_HEAD_SHA) {
      throw new Invalid("context.json's head_sha is not the head the select job read");
    }
  } catch (error) {
    log(`the round's record is refused: ${String(error?.message ?? error).slice(0, 300)}`);
    context = null;
  }
  if (context !== null) {
    try {
      const output = attempt ? readChecked(join(env.DEPENDENCY_VERDICT_DIR, "dependency-verdict.json"), env.DEPENDENCY_VERDICT_SHA256, "the scan job") : null;
      if (output === null) {
        missing = true;
        log("no verdict arrived from the model call");
      } else {
        run = { ...context, output: validateVerdict(output) };
      }
    } catch (error) {
      log(`the verdict is refused: ${String(error?.message ?? error).slice(0, 300)}`);
      run = null;
    }
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
    context,
    missing,
    patchState,
    refused,
    baseSha: env.BASE_SHA,
    log,
  });
  if (escalationReason) {
    writeFileSync(env.ESCALATION_REASON_FILE, `${escalationReason}\n`);
    writeFileSync(env.SKIP_REASON_FILE, `${stopSkip(escalationReason)}\n`);
  } else if (skipReason) {
    writeFileSync(env.SKIP_REASON_FILE, `${skipReason}\n`);
  }
  return 0;
}

runAsScript(import.meta.url, "apply-dependency-verdict", () => main(process.env));
