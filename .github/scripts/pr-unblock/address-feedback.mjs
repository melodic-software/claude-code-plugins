// The pr-unblock lane's address-feedback thread selection, shared by the model
// job's runner step and the reply job's script (publish-feedback.mjs). It runs
// no PR head code and hands the model no decision.
//
//   select  run by .github/workflows/pr-run-activity-write.yml around a
//           `prepare: review-threads` skill, before the head checkout and any
//           model turn, with the job's read-only token: keeps the unresolved
//           review threads the reviewer bot opened in a review on a head a
//           review lane's marker confirms, when every comment is the bot's or
//           a trusted person answered the lane's escalation, then decides
//           skip (no such thread), escalate (the PR changes .github/**, or
//           the configured number of rounds already ran) or proceed, writing the thread file
//           the skill's review-thread tool reads.
//
// Every comment body is copied into the thread file and never logged or
// interpolated into a command. Only a trusted person's reply to the lane's
// escalation is marked as direction; every other body is data.

import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

// The round cap is the config's `loop.review-rounds`, passed in as
// REVIEW_ROUNDS; the resolver's default is the fallback.
export const DEFAULT_MAX_ROUNDS = 2;
export const ROUND_MARKER = "<!-- pr-unblock:address-feedback-round -->";
// github-actions[bot], the author of the review lanes' reviewed-head markers.
export const MARKER_AUTHOR_ID = 41898282;
const REVIEWED_HEAD =
  /^<!-- claude-lane-reviewed-head lane=(claude-review|claude-security-review) sha=([0-9a-f]{40}) -->$/;
export const SHA = /^[0-9a-f]{40}$/;
const THREAD_COMMENT_CAP = 100;
// The most files the pulls files listing returns
// (docs.github.com/en/rest/pulls/pulls#list-pull-requests-files, as of
// 2026-10-15; recheck when that section changes its limit).
const FILES_CAP = 3000;

const firstLine = (body) => String(body ?? "").split("\n")[0].replace(/\r$/, "");

export function isProtectedPath(path) {
  return /^\.github(\/|$)/i.test(String(path));
}

// Round markers the lanes App posted; any other author's copy is ignored.
export const isRoundMarker = (comment, appId) => comment.user?.id === appId && firstLine(comment.body) === ROUND_MARKER;

export function countRounds(issueComments, appId) {
  return issueComments.filter((comment) => isRoundMarker(comment, appId)).length;
}

// The model job's check run, posted by its report job with the job token on
// the head it gated. A round that took a model turn ends success or failure;
// skips end neutral. It counts rounds the reply job could not record (a gate
// or broker refusal after the push moved the head); a forged one only stops
// the lane sooner.
export const MODEL_CHECK = "pr-unblock / address-feedback";
export function countCheckRounds(checkRunsByCommit) {
  return checkRunsByCommit.filter((runs) =>
    runs.some(
      (run) =>
        run.name === MODEL_CHECK &&
        run.app?.slug === "github-actions" &&
        ["success", "failure"].includes(run.conclusion),
    ),
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

// The first line of the reply publish-feedback.mjs posts on a thread it
// leaves open for a person: every disposition but VALID.
const ESCALATION_REPLY =
  /^\*\*pr-unblock \/ address-feedback: (INCORRECT, left open|UNCERTAIN, left open for a person|VALID \(defer\), left open for a person)\*\*$/;
export const isEscalationReply = (comment, appId) => comment?.user?.id === appId && ESCALATION_REPLY.test(firstLine(comment.body));

// Who wrote each comment, or null when the thread is not one to work: every
// comment is the reviewer bot's, or the lanes App's last comment escalated the
// thread and every comment after it is a trusted person's reply. Those replies
// are direction. A comment by anyone else, a trusted person's comment last
// edited by anyone but a trusted person, or a reply not after the escalation
// leaves the thread alone.
function authorsOf(rows, nodes, { reviewerId, appId, trustedHumans }) {
  if (rows.every((row) => row.user?.id === reviewerId)) {
    return rows.map(() => ({ author: "reviewer" }));
  }
  const last = rows.findLastIndex((row) => row.user?.id === appId);
  if (last < 1 || !isEscalationReply(rows[last], appId)) {
    return null;
  }
  const escalatedAt = Date.parse(rows[last].created_at ?? "");
  const authors = [];
  for (const [i, row] of rows.entries()) {
    const id = row.user?.id;
    const node = nodes[i];
    const human = trustedHumans.has(id) && (node.lastEditedAt == null || trustedHumans.has(node.editor?.databaseId));
    if (i > last) {
      // NaN compares false, so an unparseable time leaves the thread alone.
      if (!human || !(Date.parse(row.created_at ?? "") > escalatedAt)) {
        return null;
      }
      authors.push({ author: "trusted-human", direction: true });
    } else if (id === reviewerId || id === appId || human) {
      authors.push({ author: id === reviewerId ? "reviewer" : id === appId ? "lane" : "trusted-human" });
    } else {
      return null;
    }
  }
  return last < rows.length - 1 ? authors : null;
}

// A thread is kept when it is unresolved, its first comment belongs to a
// review the reviewer bot submitted on a marker-confirmed head, and authorsOf
// accepts its comments. A thread with more comments than one page reads is
// left alone.
export function keepThreads({ threads, reviewComments, reviews, heads, reviewerId, appId, trustedHumans = new Set() }) {
  const comments = new Map(reviewComments.map((comment) => [comment.id, comment]));
  const reviewsById = new Map(reviews.map((review) => [review.id, review]));
  const kept = [];
  for (const thread of threads) {
    if (thread.isResolved || thread.comments.totalCount > THREAD_COMMENT_CAP) {
      continue;
    }
    const nodes = thread.comments.nodes;
    const rows = nodes.map((node) => comments.get(node.databaseId));
    if (rows.length === 0 || rows.some((row) => row === undefined) || rows[0].user?.id !== reviewerId) {
      continue;
    }
    const review = reviewsById.get(rows[0].pull_request_review_id);
    if (review?.user?.id !== reviewerId || !heads.has(review.commit_id)) {
      continue;
    }
    const authors = authorsOf(rows, nodes, { reviewerId, appId, trustedHumans });
    if (authors === null) {
      continue;
    }
    kept.push({
      id: thread.id,
      path: rows[0].path,
      line: rows[0].line ?? rows[0].original_line ?? null,
      review_commit: review.commit_id,
      root_comment_id: rows[0].id,
      comments: rows.map((row, i) => ({ id: row.id, ...authors[i], body: row.body ?? "" })),
    });
  }
  return kept;
}

export async function select({
  api,
  pr,
  headSha,
  laneBranch,
  repository,
  appId,
  reviewerId,
  trustedHumans,
  maxRounds = DEFAULT_MAX_ROUNDS,
}) {
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
    appId,
    trustedHumans,
  });
  if (kept.length === 0) {
    return { decision: "skip", skipReason: "not-applicable", threads: kept };
  }
  // The files listing stops at FILES_CAP, so a longer diff could hide a
  // .github/ path and is treated as touching one.
  if (
    files.length >= FILES_CAP ||
    files.some((file) => isProtectedPath(file.filename) || isProtectedPath(file.previous_filename ?? ""))
  ) {
    return { decision: "escalate", escalationReason: "feedback-protected-path", threads: kept };
  }
  const commits = await api.listPullCommits(pr);
  const checkRuns = await Promise.all(commits.map((commit) => api.listCheckRuns(commit.sha, MODEL_CHECK)));
  const rounds = Math.max(countRounds(issueComments, appId), countCheckRounds(checkRuns));
  if (rounds >= maxRounds) {
    return { decision: "escalate", escalationReason: "feedback-round-cap", rounds, threads: kept };
  }
  return {
    decision: "proceed",
    rounds,
    threads: kept,
    file: { version: 1, repository, pr, head_sha: headSha, lane_branch: laneBranch, threads: kept },
  };
}

// The kept threads of a PR as they are now: the reply job's re-read.
export async function currentThreads({ api, pr, reviewerId, appId, trustedHumans }) {
  const [issueComments, reviews, reviewComments, threads] = await Promise.all([
    api.listIssueComments(pr),
    api.listReviews(pr),
    api.listReviewComments(pr),
    api.listThreads(pr),
  ]);
  return {
    issueComments,
    kept: keepThreads({ threads, reviewComments, reviews, heads: reviewedHeads(issueComments), reviewerId, appId, trustedHumans }),
  };
}

const THREAD_QUERY = `query($id: ID!) {
  node(id: $id) {
    ... on PullRequestReviewThread {
      isResolved pullRequest { number } comments(first: 100) { totalCount nodes { databaseId } }
    }
  }
}`;

const RESOLVE_MUTATION = `mutation($id: ID!) {
  resolveReviewThread(input: { threadId: $id }) { thread { isResolved } }
}`;

const THREADS_QUERY = `query($owner: String!, $name: String!, $pr: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $after) {
        nodes {
          id isResolved
          comments(first: 100) {
            totalCount
            nodes { databaseId lastEditedAt editor { ... on User { databaseId } ... on Bot { databaseId } } }
          }
        }
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
  async function graphql(query, variables) {
    const { data } = await request(graphqlUrl, "POST", { query, variables });
    if (data.errors?.length) {
      throw new Error(`GraphQL: ${data.errors.map((error) => error.message).join("; ")}`);
    }
    return data.data;
  }
  const repo = `${apiUrl}/repos/${owner}/${name}`;
  return {
    getPull: async (pr) => (await request(`${repo}/pulls/${pr}`)).data,
    closePull: async (pr) => (await request(`${repo}/pulls/${pr}`, "PATCH", { state: "closed" })).data,
    createIssue: async (fields) => (await request(`${repo}/issues`, "POST", fields)).data,
    listIssues: (query) => paginate(`issues?${query}`),
    listPullFiles: (pr) => paginate(`pulls/${pr}/files`),
    listIssueComments: (pr) => paginate(`issues/${pr}/comments`),
    listReviews: (pr) => paginate(`pulls/${pr}/reviews`),
    listReviewComments: (pr) => paginate(`pulls/${pr}/comments`),
    listPullCommits: (pr) => paginate(`pulls/${pr}/commits`),
    async listCheckRuns(sha, name) {
      const url = `${repo}/commits/${sha}/check-runs?check_name=${encodeURIComponent(name)}&filter=all&per_page=100`;
      return (await request(url)).data.check_runs ?? [];
    },
    async getCommit(sha) {
      return (await request(`${repo}/commits/${sha}`)).data;
    },
    async listThreads(pr) {
      const nodes = [];
      let after = null;
      for (;;) {
        const page = (await graphql(THREADS_QUERY, { owner, name, pr, after })).repository.pullRequest.reviewThreads;
        nodes.push(...page.nodes);
        if (!page.pageInfo.hasNextPage) {
          return nodes;
        }
        after = page.pageInfo.endCursor;
      }
    },
    async readThread(id) {
      const node = (await graphql(THREAD_QUERY, { id })).node;
      return {
        isResolved: node?.isResolved,
        pr: node?.pullRequest?.number,
        commentCount: node?.comments?.totalCount,
        commentIds: (node?.comments?.nodes ?? []).map((comment) => comment.databaseId),
      };
    },
    // From git/ref, which GET /pulls can lag behind after a push.
    async readBranch(ref) {
      return (await request(`${repo}/git/ref/heads/${ref.split("/").map(encodeURIComponent).join("/")}`)).data.object.sha;
    },
    async compare(base, head) {
      return (await request(`${repo}/compare/${base}...${head}`)).data;
    },
    async getRun(id) {
      return (await request(`${repo}/actions/runs/${id}`)).data;
    },
    async replyToComment(pr, commentId, body) {
      return (await request(`${repo}/pulls/${pr}/comments/${commentId}/replies`, "POST", { body })).data;
    },
    async resolveThread(id) {
      return (await graphql(RESOLVE_MUTATION, { id })).resolveReviewThread.thread.isResolved;
    },
    async createIssueComment(pr, body) {
      await request(`${repo}/issues/${pr}/comments`, "POST", { body });
    },
  };
}

export function need(env, keys) {
  for (const key of keys) {
    if (!env[key]) {
      throw new Error(`${key} is not set`);
    }
  }
}

export function positive(value, name) {
  if (!/^[1-9][0-9]{0,14}$/.test(String(value))) {
    throw new Error(`${name} is not a positive integer`);
  }
  return Number(value);
}

export function maxRoundsFrom(value) {
  return value === undefined || value === "" ? DEFAULT_MAX_ROUNDS : positive(value, "REVIEW_ROUNDS");
}

const readActors = (path) => JSON.parse(readFileSync(path, "utf8")).actors ?? [];

// The ids of the people on the base's trusted-actors list.
export function trustedHumansFrom(trustedActorsPath) {
  return new Set(
    readActors(trustedActorsPath)
      .filter((row) => row.kind === "human")
      .map((row) => positive(row.id, `a human id in ${trustedActorsPath}`)),
  );
}

// The reviewer bot's id comes from the base's trusted-actors list, by login.
export function reviewerIdFrom(trustedActorsPath, login = "claude[bot]") {
  const actor = readActors(trustedActorsPath).find((row) => row.login === login && row.kind === "bot");
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
      trustedHumans: trustedHumansFrom(env.TRUSTED_ACTORS),
      maxRounds: maxRoundsFrom(env.REVIEW_ROUNDS),
    });
    if (result.file) {
      writeFileSync(env.THREAD_FILE, `${JSON.stringify(result.file, null, 2)}\n`);
    }
    output("proceed", String(result.decision === "proceed"));
    output("skip-reason", result.decision === "skip" ? result.skipReason : result.decision === "escalate" ? "awaiting-human" : "");
    output("escalation-reason", result.escalationReason ?? "");
    log(`${result.decision}: ${result.threads.length} kept thread(s), ${result.rounds ?? 0} earlier round(s)${result.escalationReason ? `, ${result.escalationReason}` : ""}`);
    return 0;
  }
  throw new Error("usage: address-feedback.mjs select");
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
