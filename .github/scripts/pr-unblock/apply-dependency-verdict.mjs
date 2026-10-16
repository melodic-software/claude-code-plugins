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
//   2. Re-reads the pull request. Closed: nothing. merge, close and escalate
//      need the head the model reviewed; a moved head is superseded and the
//      next dispatcher run reviews the new one. fix needs only commits the
//      lanes App made on top of that head, else dependency-fix-not-landed (no
//      commit) or superseded (Dependabot rebased).
//   3. merge: the round marker it posts, naming the reviewed head, is the
//      record a merge authority reads; this job never merges or enqueues.
//      close: never on a security update (the security label or an advisory
//      in the body, read fresh here, or the model job's flag), which escalates
//      dependency-security-close; otherwise files an issue proposing the
//      dependabot.yml ignore entry and closes the pull request. escalate:
//      dependency-escalate. fix: nothing more; CI judges the push.
//   4. Posts the round marker, as the lanes App, once per model run.
//
// Environment:
//   GH_TOKEN                the lane token
//   GITHUB_REPOSITORY       owner/repo
//   PR_NUMBER, HEAD_SHA     the gated pull request and its head
//   GITHUB_RUN_ID, MODEL_RUN_ATTEMPT  the model run the round marker names
//   APP_SENDER_ID           the lanes App bot's user id
//   DEPENDENCY_VERDICT_DIR  the downloaded artifact holding run.json
//   RUN_SHA256              run.json's SHA-256, from the model job's runner step
//   SKIP_REASON_FILE, ESCALATION_REASON_FILE  where the runner reads them

import { createHash } from "node:crypto";
import { lstatSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import { createGitHubApi, need, positive, SHA } from "./address-feedback.mjs";
import { isSecurityUpdate } from "./dependency-classify.mjs";
import { roundLine, rounds, VERDICTS } from "./review-dependency.mjs";

export const LIMITS = { bytes: 65536, reasons: 10, reason: 500, evidence: 20, evidenceItem: 300 };

class Invalid extends Error {}

const exactKeys = (value, keys) =>
  value !== null && typeof value === "object" && !Array.isArray(value) && Object.keys(value).sort().join() === [...keys].sort().join();

// Plain prose: posted inside a fence, so no control character, fence, HTML
// comment or @-mention can change what the comment shows or who it pings.
function plain(text, max) {
  return (
    typeof text === "string" &&
    text.length >= 1 &&
    text.length <= max &&
    !/[\u0000-\u001f\u007f]/.test(text) &&
    !/```|~~~|<!--|-->/.test(text) &&
    !/(^|[^A-Za-z0-9`])@[A-Za-z0-9]/.test(text)
  );
}

export function validateRun(run, pr) {
  const fail = (why) => {
    throw new Invalid(`run.json is invalid: ${why}`);
  };
  if (!exactKeys(run, ["version", "pr", "head_sha", "security", "output"])) fail("its fields are not the runner's");
  if (run.version !== 1) fail("version is not 1");
  if (run.pr !== pr) fail("it names another pull request");
  if (!SHA.test(String(run.head_sha))) fail("head_sha is not a commit id");
  if (typeof run.security !== "boolean") fail("security is not a boolean");
  const out = run.output;
  if (!exactKeys(out, ["verdict", "reasons", "evidence"])) fail("the verdict's fields are not the template's");
  if (!VERDICTS.includes(out.verdict)) fail("the verdict is not merge, fix, close or escalate");
  if (!Array.isArray(out.reasons) || out.reasons.length < 1 || out.reasons.length > LIMITS.reasons) fail("reasons is not 1-10 entries");
  if (!out.reasons.every((reason) => plain(reason, LIMITS.reason))) fail("a reason is not plain prose within the limit");
  if (!Array.isArray(out.evidence) || out.evidence.length > LIMITS.evidence) fail("evidence is not 0-20 entries");
  if (!out.evidence.every((item) => plain(item, LIMITS.evidenceItem))) fail("an evidence entry is not plain prose within the limit");
  return run;
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

function ignoreIssue({ pr, title, reasons }) {
  return {
    title: `chore(deps): decide whether dependabot.yml ignores the update closed in #${pr}`,
    body: [
      `<!-- pr-unblock:dependency-ignore pr=${pr} -->`,
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

export async function apply({ api, pr, appId, modelRun, run, log }) {
  const pull = await api.getPull(pr);
  if (pull.state !== "open") {
    log(`#${pr} is ${pull.state}; nothing applied`);
    return { escalationReason: "", skipReason: "not-applicable" };
  }
  const comments = await api.listIssueComments(pr);
  const posted = rounds(comments, appId).some((round) => round.run === modelRun);
  const record = async (verdict, output = {}) => {
    if (posted) {
      log(`the round marker for model run ${modelRun} is already posted`);
      return;
    }
    await api.createIssueComment(pr, roundBody({ head: run?.head_sha ?? pull.head.sha, verdict, run: modelRun ?? "none", ...output }));
  };
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
    if (compare.status !== "ahead" || !compare.commits.every((commit) => commit.author?.id === appId)) {
      log(`#${pr}: the head moved from ${run.head_sha} to ${head} by more than the lane's fix; the next run reviews it`);
      return { escalationReason: "", skipReason: "superseded-sha" };
    }
    await record("fix", { reasons, evidence });
    return { escalationReason: "", skipReason: "" };
  }
  if (head !== run.head_sha) {
    log(`#${pr}: the head moved from ${run.head_sha} to ${head} after the review; the next run reviews it`);
    return { escalationReason: "", skipReason: "superseded-sha" };
  }
  if (verdict === "merge") {
    await record("merge", { reasons, evidence });
    return { escalationReason: "", skipReason: "" };
  }
  if (verdict === "close") {
    const labels = (pull.labels ?? []).map((label) => (typeof label === "string" ? label : label.name));
    if (run.security || isSecurityUpdate({ labels, body: pull.body ?? "" })) {
      await record("escalate", { reasons, evidence });
      return { escalationReason: "dependency-security-close", skipReason: "" };
    }
    const issue = await api.createIssue(ignoreIssue({ pr, title: pull.title ?? "", reasons }));
    log(`#${pr}: filed #${issue.number} for the ignore entry`);
    await api.closePull(pr);
    await record("close", { reasons, evidence });
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
  const attempt = env.MODEL_RUN_ATTEMPT ?? "";
  if (attempt !== "" && !/^[1-9][0-9]{0,4}$/.test(attempt)) {
    throw new Error("MODEL_RUN_ATTEMPT is not a run attempt");
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
    if (!/^[0-9a-f]{64}$/.test(env.RUN_SHA256 ?? "") || createHash("sha256").update(text).digest("hex") !== env.RUN_SHA256) {
      throw new Invalid("run.json does not match the SHA-256 the model job recorded");
    }
    run = validateRun(JSON.parse(text), pr);
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
