// The pr-unblock lane's address-feedback runner steps, run by
// .github/workflows/pr-run-activity-write.yml around a `prepare: review-threads`
// skill. Neither subcommand runs PR head code or hands the model a decision.
//
//   select        before the head checkout and any model turn, with the job's
//                 read-only token: keeps the unresolved review threads whose
//                 every comment is the reviewer bot's and whose review is on a
//                 head a review lane's marker confirms, then decides
//                 skip (no such thread), escalate (the PR changes .github/**,
//                 or MAX_ROUNDS rounds already ran) or proceed, writing the
//                 thread file the skill's review-thread tool reads.
//   record-round  after the skill, with the lane token: posts one round
//                 marker comment as the lanes App, then escalates when the
//                 tool's log holds an UNCERTAIN or VALID (defer) reply, or a
//                 thread was resolved on a fix the PR branch never received.
//
// Every comment body is untrusted data: it is copied into the thread file and
// never logged or interpolated into a command.

import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

// Owner decision on #7032: at most two rounds per pull request.
export const MAX_ROUNDS = 2;
export const ROUND_MARKER = "<!-- pr-unblock:address-feedback-round -->";
// github-actions[bot], the author of the review lanes' reviewed-head markers.
export const MARKER_AUTHOR_ID = 41898282;
const REVIEWED_HEAD =
  /^<!-- claude-lane-reviewed-head lane=(claude-review|claude-security-review) sha=([0-9a-f]{40}) -->$/;
const SHA = /^[0-9a-f]{40}$/;
const THREAD_COMMENT_CAP = 100;

const firstLine = (body) => String(body ?? "").split("\n")[0].replace(/\r$/, "");

export function isProtectedPath(path) {
  return /^\.github(\/|$)/i.test(String(path));
}

// Round markers the lanes App posted; any other author's copy is ignored.
export function countRounds(issueComments, appId) {
  return issueComments.filter(
    (comment) => comment.user?.id === appId && firstLine(comment.body) === ROUND_MARKER,
  ).length;
}

export function reviewedHeads(issueComments) {
  const heads = new Set();
  for (const comment of issueComments) {
    if (comment.user?.id !== MARKER_AUTHOR_ID) {
      continue;
    }
    const match = REVIEWED_HEAD.exec(firstLine(comment.body));
    if (match) {
      heads.add(match[2]);
    }
  }
  return heads;
}

// A thread is kept when it is unresolved, every comment in it is the
// reviewer bot's, and its first comment belongs to a review the reviewer bot
// submitted on a marker-confirmed head. A thread with a human reply, or more
// comments than one page reads, is left alone.
export function keepThreads({ threads, reviewComments, reviews, heads, reviewerId }) {
  const comments = new Map(reviewComments.map((comment) => [comment.id, comment]));
  const reviewsById = new Map(reviews.map((review) => [review.id, review]));
  const kept = [];
  for (const thread of threads) {
    if (thread.isResolved || thread.comments.totalCount > THREAD_COMMENT_CAP) {
      continue;
    }
    const ids = thread.comments.nodes.map((node) => node.databaseId);
    const rows = ids.map((id) => comments.get(id));
    if (rows.length === 0 || rows.some((row) => row?.user?.id !== reviewerId)) {
      continue;
    }
    const review = reviewsById.get(rows[0].pull_request_review_id);
    if (review?.user?.id !== reviewerId || !heads.has(review.commit_id)) {
      continue;
    }
    kept.push({
      id: thread.id,
      path: rows[0].path,
      line: rows[0].line ?? rows[0].original_line ?? null,
      review_commit: review.commit_id,
      root_comment_id: rows[0].id,
      comments: rows.map((row) => ({ id: row.id, body: row.body ?? "" })),
    });
  }
  return kept;
}

export async function select({ api, pr, headSha, laneBranch, repository, appId, reviewerId }) {
  const [files, issueComments, reviews, reviewComments, threads] = await Promise.all([
    api.listPullFiles(pr),
    api.listIssueComments(pr),
    api.listReviews(pr),
    api.listReviewComments(pr),
    api.listThreads(pr),
  ]);
  const kept = keepThreads({
    threads,
    reviewComments,
    reviews,
    heads: reviewedHeads(issueComments),
    reviewerId,
  });
  if (kept.length === 0) {
    return { decision: "skip", skipReason: "not-applicable", threads: kept };
  }
  if (files.some((file) => isProtectedPath(file.filename) || isProtectedPath(file.previous_filename ?? ""))) {
    return { decision: "escalate", escalationReason: "feedback-protected-path", threads: kept };
  }
  const rounds = countRounds(issueComments, appId);
  if (rounds >= MAX_ROUNDS) {
    return { decision: "escalate", escalationReason: "feedback-round-cap", rounds, threads: kept };
  }
  return {
    decision: "proceed",
    rounds,
    threads: kept,
    file: { version: 1, repository, pr, head_sha: headSha, lane_branch: laneBranch, threads: kept },
  };
}

// The tool's log is one JSON object per line. A line that does not parse, or
// a disposition outside the four, hands the PR to a person.
export function judgeLog(text, { promoted }) {
  let uncertain = false;
  let resolved = false;
  for (const line of text.split("\n").filter((row) => row.trim() !== "")) {
    let entry;
    try {
      entry = JSON.parse(line);
    } catch {
      return "feedback-uncertain";
    }
    if (entry.disposition === "UNCERTAIN" || entry.disposition === "VALID-defer") {
      uncertain = true;
    } else if (entry.disposition === "VALID") {
      resolved ||= entry.resolved === true;
    } else if (entry.disposition !== "INCORRECT") {
      return "feedback-uncertain";
    }
  }
  if (resolved && !promoted) {
    return "feedback-not-landed";
  }
  return uncertain ? "feedback-uncertain" : "";
}

export async function recordRound({ api, pr, headSha, appId, logText, promoted }) {
  const rounds = countRounds(await api.listIssueComments(pr), appId) + 1;
  const reason = judgeLog(logText, { promoted });
  const body = [
    ROUND_MARKER,
    `pr-unblock / address-feedback finished round ${rounds} of ${MAX_ROUNDS} on ${headSha}.`,
  ].join("\n");
  await api.createIssueComment(pr, body);
  return { rounds, escalationReason: reason };
}

const THREADS_QUERY = `query($owner: String!, $name: String!, $pr: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $after) {
        nodes { id isResolved comments(first: 100) { totalCount nodes { databaseId } } }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}`;

export function createGitHubApi({ token, repository, apiUrl, graphqlUrl, fetch = globalThis.fetch }) {
  const [owner, name] = repository.split("/");
  const headers = {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${token}`,
    "X-GitHub-Api-Version": "2022-11-28",
  };
  async function request(url, method = "GET", body) {
    const response = await fetch(url, {
      method,
      headers: body === undefined ? headers : { ...headers, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!response.ok) {
      throw new Error(`${method} ${url} returned ${response.status}`);
    }
    return { data: await response.json(), link: response.headers.get("link") ?? "" };
  }
  async function paginate(path) {
    const rows = [];
    let url = `${apiUrl}/repos/${owner}/${name}/${path}${path.includes("?") ? "&" : "?"}per_page=100`;
    while (url) {
      const { data, link } = await request(url);
      rows.push(...data);
      url = /<([^>]+)>;\s*rel="next"/.exec(link)?.[1] ?? "";
    }
    return rows;
  }
  return {
    listPullFiles: (pr) => paginate(`pulls/${pr}/files`),
    listIssueComments: (pr) => paginate(`issues/${pr}/comments`),
    listReviews: (pr) => paginate(`pulls/${pr}/reviews`),
    listReviewComments: (pr) => paginate(`pulls/${pr}/comments`),
    async listThreads(pr) {
      const nodes = [];
      let after = null;
      for (;;) {
        const { data } = await request(graphqlUrl, "POST", {
          query: THREADS_QUERY,
          variables: { owner, name, pr, after },
        });
        if (data.errors?.length) {
          throw new Error(`GraphQL: ${data.errors.map((error) => error.message).join("; ")}`);
        }
        const page = data.data.repository.pullRequest.reviewThreads;
        nodes.push(...page.nodes);
        if (!page.pageInfo.hasNextPage) {
          return nodes;
        }
        after = page.pageInfo.endCursor;
      }
    },
    async createIssueComment(pr, body) {
      await request(`${apiUrl}/repos/${owner}/${name}/issues/${pr}/comments`, "POST", { body });
    },
  };
}

function need(env, keys) {
  for (const key of keys) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
}

function positive(value, name) {
  if (!/^[1-9][0-9]{0,14}$/.test(String(value))) {
    throw new Error(`${name} is not a positive integer`);
  }
  return Number(value);
}

// The reviewer bot's id comes from the base's trusted-actors list, by login.
export function reviewerIdFrom(trustedActorsPath, login = "claude[bot]") {
  const actors = JSON.parse(readFileSync(trustedActorsPath, "utf8")).actors ?? [];
  const actor = actors.find((row) => row.login === login && row.kind === "bot");
  return positive(actor?.id, `the ${login} id in ${trustedActorsPath}`);
}

export async function main(argv, env, { api, log = (line) => console.log(line) } = {}) {
  const command = argv[0];
  need(env, ["GITHUB_TOKEN", "GITHUB_REPOSITORY", "GITHUB_OUTPUT", "PR_NUMBER", "HEAD_SHA", "APP_SENDER_ID"]);
  const pr = positive(env.PR_NUMBER, "PR_NUMBER");
  const appId = positive(env.APP_SENDER_ID, "APP_SENDER_ID");
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
    });
  const output = (key, value) => appendFileSync(env.GITHUB_OUTPUT, `${key}=${value}\n`);
  if (command === "select") {
    need(env, ["LANE_BRANCH", "THREAD_FILE", "TRUSTED_ACTORS"]);
    const result = await select({
      api: client,
      pr,
      headSha: env.HEAD_SHA,
      laneBranch: env.LANE_BRANCH,
      repository: env.GITHUB_REPOSITORY,
      appId,
      reviewerId: reviewerIdFrom(env.TRUSTED_ACTORS),
    });
    if (result.file) {
      writeFileSync(env.THREAD_FILE, `${JSON.stringify(result.file, null, 2)}\n`);
    }
    output("proceed", String(result.decision === "proceed"));
    output("skip-reason", result.decision === "skip" ? result.skipReason : result.decision === "escalate" ? "awaiting-human" : "");
    output("escalation-reason", result.escalationReason ?? "");
    log(`${result.decision}: ${result.threads.length} reviewer-bot thread(s), ${result.rounds ?? 0} earlier round(s)${result.escalationReason ? `, ${result.escalationReason}` : ""}`);
    return 0;
  }
  if (command === "record-round") {
    need(env, ["FEEDBACK_LOG"]);
    const logText = existsSync(env.FEEDBACK_LOG) ? readFileSync(env.FEEDBACK_LOG, "utf8") : "";
    const { rounds, escalationReason } = await recordRound({
      api: client,
      pr,
      headSha: env.HEAD_SHA,
      appId,
      logText,
      promoted: env.PROMOTE_OUTCOME === "success",
    });
    output("escalation-reason", escalationReason);
    output("skip-reason", escalationReason ? "awaiting-human" : "");
    log(`recorded round ${rounds}${escalationReason ? `; escalating ${escalationReason}` : ""}`);
    return 0;
  }
  throw new Error("usage: address-feedback.mjs select|record-round");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2), process.env).then(
    (code) => {
      process.exitCode = code;
    },
    (error) => {
      console.log(`::error::address-feedback failed: ${error.message}`);
      process.exitCode = 1;
    },
  );
}
