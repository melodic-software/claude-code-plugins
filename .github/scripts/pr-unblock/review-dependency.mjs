import { createHash } from "node:crypto";
import { appendFileSync, readFileSync, writeFileSync } from "node:fs";

import { runAsScript } from "../lib/run-main.mjs";
import { readRawTrustedActors, trustedListPath } from "../lib/trusted-actors.mjs";
import { guardedFetch, createGitHubApi, need, positive, SHA } from "./address-feedback.mjs";
import {
  classifierGaps,
  classify,
  COMMIT_FILES_LIMIT,
  DEPENDABOT_LOGIN,
  isDependabotCommit,
  parseConfig,
  policyPath,
  provenanceReasons,
  withProvenance,
} from "./dependency-classify.mjs";
import { cdnRequest } from "./cdn-pins-sync.mjs";
import { parseGroups, relockRequest, relockTarget } from "./dependency-relock.mjs";
import { movePin, PACKAGE, unifiedDiff } from "./install-script-pin.mjs";

export const DEFAULT_MAX_ROUNDS = 2;
export const MODEL_CHECK = "pr-unblock / review-dependency";
export const VERDICTS = Object.freeze(["merge", "fix", "close", "escalate"]);
const ROUND_PREFIX = "<!-- pr-unblock:review-dependency-round ";
const ROUND_HEAD = /\shead=([0-9a-f]{40})\s/;
const ROUND_LINE = /^<!-- pr-unblock:review-dependency-round head=([0-9a-f]{40}) verdict=(merge|fix|close|escalate|invalid) run=([1-9][0-9]{0,14}-[1-9][0-9]{0,4}|none) -->$/;
export const FILES_CAP = 3000;
const PATCH_CAP = 20_000;
const PATCHES_TOTAL_CAP = 300_000;

const firstLine = (body) => String(body ?? "").split("\n")[0].replace(/\r$/, "");
const appFirstLines = (issueComments, appId) => issueComments.filter((comment) => comment.user?.id === appId).map((comment) => firstLine(comment.body));
const labelNames = (pull) => (pull.labels ?? []).map((label) => (typeof label === "string" ? label : label.name));

export function roundLine({ head, verdict, run }) {
  return `<!-- pr-unblock:review-dependency-round head=${head} verdict=${verdict} run=${run} -->`;
}

export function rounds(issueComments, appId) {
  return appFirstLines(issueComments, appId)
    .map((line) => ROUND_LINE.exec(line))
    .filter(Boolean)
    .map((match) => ({ head: match[1], verdict: match[2], run: match[3] }));
}

export function countRounds(issueComments, appId, shas = null) {
  const current = Array.isArray(shas) ? new Set(shas) : null;
  return appFirstLines(issueComments, appId)
    .filter((line) => line.startsWith(ROUND_PREFIX))
    .filter((line) => {
      const head = ROUND_HEAD.exec(line)?.[1];
      return head === undefined || current === null || current.has(head);
    }).length;
}

export function countCheckRounds(checkRunsByCommit) {
  return checkRunsByCommit.filter((runs) =>
    runs.some(
      (run) => run.name === MODEL_CHECK && run.app?.slug === "github-actions" && ["success", "failure"].includes(run.conclusion),
    ),
  ).length;
}

export const newestOf = (checkRuns) => checkRuns.filter((run) => run.app?.slug === "github-actions").sort((a, b) => b.id - a.id)[0];

export function ciStatusOf(checkRuns) {
  const newest = newestOf(checkRuns);
  return newest?.status === "completed" ? String(newest.conclusion) : "pending";
}

const SUPERSEDED = /^superseded by full run https:\/\/[^ ]+\/actions\/runs\/[0-9]+ in flight on ([0-9a-f]+)[:. ]/;
const EXIT_LINE = /^Process completed with exit code [0-9]+\.$/;
export function supersededOnly(annotations, headSha) {
  const failures = annotations.filter((note) => note?.annotation_level === "failure").map((note) => String(note.message ?? ""));
  const marks = (message) => SUPERSEDED.exec(message)?.[1] === headSha;
  return failures.some(marks) && failures.every((message) => marks(message) || EXIT_LINE.test(message));
}

export const GATE_HOLD_SKIP = "gate-hold";
const GATE_HOLDS = [
  ["person", /^#([1-9][0-9]*) is by an author no review lane reviews and changes trust-gate paths:/],
  ["verdict", /^#([1-9][0-9]*) by Dependabot swaps only action refs, each to a tagged commit, on trust-gate paths:/],
  ["verdict", /^#([1-9][0-9]*) by Dependabot changes only the CDN pins record on trust-gate paths:/],
];
export function gateHoldOnly(annotations, pr) {
  const failures = annotations.filter((note) => note?.annotation_level === "failure").map((note) => String(note.message ?? ""));
  const kindOf = (message) => GATE_HOLDS.find(([, pattern]) => pattern.exec(message)?.[1] === String(pr))?.[0];
  const kinds = failures.map(kindOf).filter(Boolean);
  if (kinds.length === 0 || !failures.every((message) => kindOf(message) || EXIT_LINE.test(message))) return false;
  return kinds.includes("person") ? "person" : "verdict";
}

export function newestRound(issueComments, appId) {
  const mine = issueComments.filter((comment) => comment.user?.id === appId && firstLine(comment.body).startsWith(ROUND_PREFIX));
  const newest = mine.reduce((a, b) => (a === null || String(b.created_at) > String(a.created_at) || (b.created_at === a.created_at && b.id > a.id) ? b : a), null);
  const match = newest && ROUND_LINE.exec(firstLine(newest.body));
  return match ? { head: match[1], verdict: match[2], run: match[3], createdAt: String(newest.created_at) } : null;
}

export async function gateCheckRuns(list) {
  const runs = await list("CI Status");
  return newestOf(runs) ? runs : list("ci-status");
}

export async function readCiStatus(api, headSha, pr) {
  const runs = await gateCheckRuns((name) => api.listCheckRuns(headSha, name));
  const status = ciStatusOf(runs);
  if (status !== "failure") {
    return { status, gateHold: false };
  }
  try {
    const annotations = await api.listAnnotations(newestOf(runs).id);
    return supersededOnly(annotations, headSha) ? { status: "pending", gateHold: false } : { status, gateHold: gateHoldOnly(annotations, pr) };
  } catch {
    return { status, gateHold: false };
  }
}

export function commitFilesReader(api) {
  const cache = new Map();
  return async (sha) => {
    if (!cache.has(sha)) {
      let paths = null;
      try {
        const listing = (await api.getCommit(sha)).files;
        paths = Array.isArray(listing) && listing.length < COMMIT_FILES_LIMIT ? listing.map((f) => String(f.filename ?? "")) : null;
      } catch {
        paths = null;
      }
      cache.set(sha, paths);
    }
    return cache.get(sha);
  };
}

export async function classifyPull({ pull, ciStatus, commits, files, config, policy, repository, readCommitFiles, provenance = provenanceReasons }) {
  const touched = new Map();
  for (const item of commits) {
    if (!isDependabotCommit(item)) {
      touched.set(String(item.sha ?? ""), await readCommitFiles(String(item.sha ?? "")));
    }
  }
  const classification = classify({
    author: pull.user?.login,
    headRef: pull.head?.ref,
    title: pull.title ?? "",
    body: pull.body ?? "",
    labels: labelNames(pull),
    ciStatus,
    commits,
    totalCommits: pull.commits,
    files,
    config,
    policy,
    repository,
    changedFiles: pull.changed_files,
    commitFiles: (sha) => touched.get(sha) ?? null,
  });
  return withProvenance(classification, provenance);
}

function capPatches(files) {
  let left = PATCHES_TOTAL_CAP;
  return files.map((file) => {
    const patch = String(file.patch ?? "");
    const kept = patch.slice(0, Math.max(0, Math.min(PATCH_CAP, left)));
    left -= kept.length;
    return {
      filename: file.filename,
      previous_filename: file.previous_filename ?? null,
      status: file.status,
      additions: file.additions,
      deletions: file.deletions,
      patch: kept.length < patch.length ? `${kept}\n[patch truncated: read the file]` : kept,
    };
  });
}

export async function pinMove(api, files, headSha) {
  if (!files.some((file) => file.filename === "package.json" || file.filename === "package-lock.json")) {
    return null;
  }
  const manifest = await api.getText("package.json", headSha);
  const lock = manifest === null ? null : await api.getText("package-lock.json", headSha);
  const moved = lock === null ? null : movePin(manifest, lock);
  return moved && { from: moved.from, to: moved.to, patch: unifiedDiff("package.json", manifest, moved.text) };
}

export async function select({
  api,
  pr,
  headSha,
  appId,
  dependabotId,
  config = null,
  groups = [],
  baseDir,
  policy,
  repository = "",
  maxRounds = DEFAULT_MAX_ROUNDS,
  provenance,
}) {
  const pull = await api.getPull(pr);
  if (pull.user?.id !== dependabotId || pull.user?.login !== DEPENDABOT_LOGIN) {
    return { decision: "skip", skipReason: "not-applicable" };
  }
  if (pull.head?.sha !== headSha) {
    return { decision: "skip", skipReason: "superseded-sha" };
  }
  const files = await api.listPullFiles(pr);
  const commits = await api.listPullCommits(pr);
  const gate = await readCiStatus(api, headSha, pr);
  const classification = await classifyPull({
    pull,
    ciStatus: gate.status,
    commits,
    files,
    config,
    policy,
    repository,
    readCommitFiles: commitFilesReader(api),
    provenance,
  });
  if (classification.tier !== "review") {
    return { decision: "skip", skipReason: "not-applicable", classification };
  }
  let pinError = "";
  try {
    const pin = await pinMove(api, files, headSha);
    if (pin) {
      return { decision: "pin", pin, classification };
    }
  } catch (error) {
    pinError = error.message;
  }
  let relockError = "";
  try {
    const target = await relockTarget({ files, groups, readText: (path) => api.getText(path, headSha) });
    if (target) {
      return { decision: "relock", relock: await relockRequest(target, { readText: (path) => api.getText(path, headSha) }), classification };
    }
  } catch (error) {
    relockError = error.message;
  }
  let cdnError = "";
  try {
    const cdn = await cdnRequest({ files, changedFiles: pull.changed_files, baseDir, readText: (path) => api.getText(path, headSha, { exactUtf8: true }) });
    if (cdn) return { decision: "cdn-sync", cdn, classification };
  } catch (error) {
    cdnError = error.message;
  }
  if (gate.gateHold === "person") {
    return { decision: "skip", skipReason: GATE_HOLD_SKIP, gateHold: true, classification, pinError, relockError, cdnError };
  }
  const comments = await api.listIssueComments(pr);
  const checkRuns = [];
  for (const commit of commits) {
    checkRuns.push(await api.listCheckRuns(commit.sha, MODEL_CHECK));
  }
  const whole = commits.length === pull.commits && commits.at(-1)?.sha === headSha;
  const shas = whole ? commits.map((commit) => commit.sha) : null;
  const done = Math.max(countRounds(comments, appId, shas), countCheckRounds(checkRuns));
  if (done >= maxRounds) {
    return { decision: "escalate", escalationReason: "dependency-round-cap", rounds: done, classification, pinError, relockError, cdnError };
  }

  return {
    decision: "proceed",
    rounds: done,
    classification,
    pinError,
    relockError,
    cdnError,
    file: {
      version: 1,
      repository,
      pr,
      head_sha: headSha,
      head_ref: pull.head.ref,
      title: pull.title ?? "",
      labels: labelNames(pull),
      classification,
      rounds: done,
      files_truncated: files.length >= FILES_CAP,
      merge_clears_gate_hold: gate.gateHold === "verdict",
      files: capPatches(files),
      body: pull.body ?? "",
    },
  };
}

export function dependabotIdFrom(trustedActorsPath) {
  const actors = readRawTrustedActors(trustedActorsPath).actors ?? [];
  const actor = actors.find((row) => row.login === DEPENDABOT_LOGIN && row.kind === "bot");
  return positive(actor?.id, `the ${DEPENDABOT_LOGIN} id in ${trustedActorsPath}`);
}

export function readConfig(path, log = (line) => console.log(line)) {
  let text;
  try {
    text = readFileSync(String(path ?? ""), "utf8");
  } catch (error) {
    log(`::warning::cannot read the Dependabot config ${path || "(no path)"} (${error.code ?? error.name}); every Dependabot PR is review tier until it reads`);
    return null;
  }
  const pairs = parseConfig(text);
  if (pairs === null) {
    log(`::warning::the Dependabot config ${path} has no updates entry that reads; every Dependabot PR is review tier until one does`);
  }
  return pairs;
}

export function readPolicy(path, log = (line) => console.log(line)) {
  try {
    return JSON.parse(readFileSync(String(path ?? ""), "utf8"));
  } catch (error) {
    log(`::warning::cannot read the Dependabot policy ${path || "(no path)"} (${error.code ?? error.name}); every Dependabot PR is review tier until it reads`);
    return null;
  }
}

export const reviewControls = (classification) => [...new Set((classification?.reviewOnly ?? []).map((entry) => entry.control))];

export function maxRoundsFrom(value) {
  return value === undefined || value === "" ? DEFAULT_MAX_ROUNDS : positive(value, "DEPENDENCY_REVIEW_ROUNDS");
}

export function contextRun({ pr, headSha, classification, file, config, startedAt }) {
  return {
    version: 1,
    pr,
    head_sha: headSha,
    security: classification?.security === true,
    config_unreadable: (classification?.reasons ?? []).includes("dependabot-config-unreadable"),
    files_truncated: file?.files_truncated === true,
    started_at: startedAt,
    controls: reviewControls(classification),
    config: config ?? [],
  };
}

const utcSeconds = (date) => date.toISOString().replace(/\.\d{3}Z$/, "Z");

export async function main(argv, env, { api, log = (line) => console.log(line), provenance, now = () => new Date() } = {}) {
  if (argv[0] !== "select") {
    throw new Error("usage: review-dependency.mjs select");
  }
  need(env, [
    "GITHUB_TOKEN",
    "GITHUB_REPOSITORY",
    "GITHUB_OUTPUT",
    "PR_NUMBER",
    "HEAD_SHA",
    "APP_SENDER_ID",
    "DEPENDENCY_FILE",
    "CONTEXT_RUN_FILE",
    "DEPENDABOT_CONFIG",
    ...(env.STANDARDS_DIR ? [] : ["TRUSTED_ACTORS", "DEPENDABOT_POLICY"]),
  ]);
  const startedAt = utcSeconds(now());
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  if (!SHA.test(env.HEAD_SHA)) {
    throw new Error("HEAD_SHA is not a commit id");
  }
  const client =
    api ??
    createGitHubApi({
      token: env.GITHUB_TOKEN,
      repository: env.GITHUB_REPOSITORY,
      apiUrl: env.GITHUB_API_URL ?? "https://api.github.com",
      graphqlUrl: env.GITHUB_GRAPHQL_URL ?? "https://api.github.com/graphql",
      fetch: await guardedFetch(),
    });
  const config = readConfig(env.DEPENDABOT_CONFIG, log);
  const result = await select({
    api: client,
    pr,
    headSha: env.HEAD_SHA,
    appId: positive(env.APP_SENDER_ID, "APP_SENDER_ID"),
    dependabotId: dependabotIdFrom(trustedListPath(env, env.TRUSTED_ACTORS)),
    repository: env.GITHUB_REPOSITORY,
    maxRounds: maxRoundsFrom(env.DEPENDENCY_REVIEW_ROUNDS),
    config,
    baseDir: env.BASE_DIR,
    groups: config === null ? [] : parseGroups(readFileSync(env.DEPENDABOT_CONFIG, "utf8")),
    policy: readPolicy(policyPath(env, env.DEPENDABOT_POLICY), log),
    provenance,
  });
  if (result.file) {
    writeFileSync(env.DEPENDENCY_FILE, `${JSON.stringify(result.file, null, 2)}\n`);
    const run = contextRun({ pr, headSha: env.HEAD_SHA, classification: result.classification, file: result.file, config, startedAt });
    writeFileSync(env.CONTEXT_RUN_FILE, `${JSON.stringify(run)}\n`);
  }
  const output = (key, value) => appendFileSync(env.GITHUB_OUTPUT, `${key}=${value}\n`);
  const summary = (line) => {
    log(line);
    if (env.GITHUB_STEP_SUMMARY) {
      appendFileSync(env.GITHUB_STEP_SUMMARY, `${line}\n`);
    }
  };
  if (result.pin) {
    need(env, ["PIN_PATCH_FILE"]);
    writeFileSync(env.PIN_PATCH_FILE, result.pin.patch);
    output("pin-state", "written");
    output("pin-sha256", createHash("sha256").update(result.pin.patch).digest("hex"));
    summary(`${PACKAGE} install-script pin: ${result.pin.from} to ${result.pin.to}, pushed by apply-dependency-pin with no model turn`);
  }
  if (result.relock) {
    need(env, ["RELOCK_DIR"]);
    const request = `${JSON.stringify(result.relock)}\n`;
    writeFileSync(`${env.RELOCK_DIR}/request.json`, request);
    writeFileSync(`${env.RELOCK_DIR}/requirements.in`, result.relock.in_after);
    writeFileSync(`${env.RELOCK_DIR}/requirements.txt`, result.relock.txt_before);
    output("relock-state", "written");
    output("relock-sha256", createHash("sha256").update(request).digest("hex"));
    summary(`${result.relock.directory}: ${result.relock.name} ${result.relock.from} to ${result.relock.to}, relocked by review-dependency-relock and pushed by apply-dependency-relock with no model turn`);
  }
  if (result.cdn) {
    need(env, ["CDN_SYNC_DIR"]);
    const request = `${JSON.stringify(result.cdn)}\n`;
    writeFileSync(`${env.CDN_SYNC_DIR}/request.json`, request);
    output("cdn-sync-state", "written");
    output("cdn-sync-sha256", createHash("sha256").update(request).digest("hex"));
    summary("The CDN pins sync runs before any dependency model turn");
  }
  if (result.cdnError) {
    log("::warning::the CDN pins sync request could not be built; the model reviews the pull request as it stands");
  }
  if (result.gateHold) {
    summary(`#${pr}: the only failing CI Status check is the trust-gate hold, which only a person on the trusted-actor list approving this head clears, so no dependency review ran and the update's content was not judged`);
  }
  if (result.pinError) {
    log(`::warning::the ${PACKAGE} install-script pin was not moved (${result.pinError}); the model reviews the pull request as it stands`);
  }
  if (result.relockError) {
    log(`::warning::the dependency group's lagging directory was not relocked (${result.relockError}); the model reviews the pull request as it stands`);
  }
  output("proceed", String(result.decision === "proceed"));
  output("skip-reason", { skip: result.skipReason, escalate: "awaiting-human", pin: "no-model-turn", relock: "no-model-turn", "cdn-sync": "no-model-turn" }[result.decision] ?? "");
  output("escalation-reason", result.escalationReason ?? "");
  const gaps = classifierGaps(result.classification?.tier === "review" ? result.classification.reasons : []);
  if (gaps.length) {
    log(`::warning::classifier gap: #${pr} goes to review only because the classifier could not read it (${gaps.join(", ")}); fix the classifier, not the pull request`);
  }
  log(
    `${result.decision}: tier ${result.classification?.tier ?? "-"} (${(result.classification?.reasons ?? []).join(", ") || "none"}), ` +
      `${result.rounds ?? 0} earlier round(s)${result.escalationReason ? `, ${result.escalationReason}` : ""}`,
  );
  return 0;
}

runAsScript(import.meta.url, "review-dependency", () => main(process.argv.slice(2), process.env));
