import { readFileSync, rmSync, writeFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import {
  createGitHub,
  paginate,
} from "../../scripts/lib/github-client.mjs";
import {
  isListed,
  loadTrustedActors,
} from "../check-trusted-trigger/check-trusted-trigger.mjs";
import { trustedListPath } from "../../scripts/lib/trusted-actors.mjs";

const PR_NUMBER = /^[1-9][0-9]{0,9}$/;
const REPOSITORY = /^[A-Za-z0-9-]+\/(?!\.\.?$)[A-Za-z0-9_.-]+$/;
const APP_SLUG = /^[a-z0-9][a-z0-9-]*$/;

const CLOSING_FIELD = `closingIssuesReferences(first: 100, after: $after) {
        nodes { number repository { nameWithOwner } }
        pageInfo { hasNextPage endCursor }
      }`;
const RENAMES_FIELD = `timelineItems(itemTypes: [RENAMED_TITLE_EVENT], first: 100, after: $after) {
        nodes {
          ... on RenamedTitleEvent {
            actor { __typename ... on User { databaseId } ... on Bot { databaseId } }
          }
        }
        pageInfo { hasNextPage endCursor }
      }`;
const prQuery = (...fields) => `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      ${fields.join("\n      ")}
    }
  }
}`;
const CLOSING_ISSUES = prQuery(CLOSING_FIELD);
const TITLE_RENAMES = prQuery(RENAMES_FIELD);
const CLOSING_AND_RENAMES = prQuery(CLOSING_FIELD, RENAMES_FIELD);
const MAX_GRAPHQL_PAGES = 50;

const prPage = (github, query, repository, prNumber, after) => {
  const [owner, name] = repository.split("/");
  return github("POST", "/graphql", { query, variables: { owner, name, number: Number(prNumber), after } });
};

async function prConnection(github, query, field, repository, prNumber, first) {
  const nodes = [];
  let after = null;
  for (let page = 1; page <= MAX_GRAPHQL_PAGES; page += 1) {
    const answer = page === 1 && first !== undefined ? first : await prPage(github, query, repository, prNumber, after);
    const connection = answer?.data?.repository?.pullRequest?.[field];
    if (!Array.isArray(connection?.nodes)) {
      throw new Error(`${field} could not be read`);
    }
    nodes.push(...connection.nodes);
    if (connection.pageInfo?.hasNextPage !== true) {
      return nodes;
    }
    after = connection.pageInfo.endCursor;
  }
  throw new Error(`${field} exceeds ${MAX_GRAPHQL_PAGES} pages`);
}

export async function titleRenamers(github, repository, prNumber, first) {
  const renames = await prConnection(github, TITLE_RENAMES, "timelineItems", repository, prNumber, first);
  return renames.map((event) => event?.actor ?? null);
}

const LAST_EDITORS = `query($ids: [ID!]!) {
  nodes(ids: $ids) {
    id
    ... on Comment {
      lastEditedAt
      editor { __typename ... on User { databaseId } ... on Bot { databaseId } }
    }
  }
}`;

function createTrustCheck(github, ids) {
  const appBots = new Map();
  async function appBotListed(app) {
    const slug = app?.slug;
    if (typeof slug !== "string" || !APP_SLUG.test(slug)) {
      return false;
    }
    if (!appBots.has(slug)) {
      appBots.set(
        slug,
        github("GET", `/users/${encodeURIComponent(`${slug}[bot]`)}`).then(
          (bot) => isListed(ids, bot),
          () => false,
        ),
      );
    }
    return appBots.get(slug);
  }
  return async (item) => {
    if (!isListed(ids, item.user)) {
      return false;
    }
    const app = item.performed_via_github_app;
    return app == null || (await appBotListed(app));
  };
}

export const PR_READS = "pr-verify-pr-reads.json";
const SHA = /^[0-9a-f]{40}$/;
const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);

export function prReads(number, pull, spec) {
  const refs = spec?.closingIssuesReferences;
  if (!Array.isArray(refs?.nodes) || refs.totalCount !== refs.nodes.length) {
    return null;
  }
  const text =
    typeof pull?.node_id === "string" &&
    typeof pull.title === "string" &&
    (spec.body === null || typeof spec.body === "string") &&
    (spec.lastEditedAt === null || typeof spec.lastEditedAt === "string");
  return {
    v: 1,
    pr: number,
    pull: text
      ? {
          number: pull.number,
          node_id: pull.node_id,
          title: pull.title,
          body: spec.body === "" ? null : spec.body,
          last_edited_at: spec.lastEditedAt,
          user: pull.user ?? null,
          head: { sha: pull.head?.sha },
          base: { sha: pull.base?.sha },
        }
      : null,
    closing: {
      nodes: refs.nodes.map((node) => ({ number: node?.number, repository: { nameWithOwner: node?.repository?.nameWithOwner } })),
      pageInfo: { hasNextPage: false, endCursor: null },
    },
    ...(Array.isArray(spec.renames?.nodes) && isObject(spec.renames.pageInfo) && { renames: spec.renames }),
  };
}

export function takePrReads(text, prNumber, headSha) {
  const reads = JSON.parse(text);
  const number = Number(prNumber);
  const pull = reads?.pull;
  const validPull =
    pull === null ||
    (isObject(pull) &&
      pull.number === number &&
      typeof pull.node_id === "string" &&
      pull.node_id !== "" &&
      typeof pull.title === "string" &&
      (pull.body === null || typeof pull.body === "string") &&
      (pull.last_edited_at === null || !Number.isNaN(Date.parse(pull.last_edited_at ?? ""))) &&
      (pull.user === null || isObject(pull.user)) &&
      SHA.test(pull.head?.sha ?? "") &&
      pull.head.sha === headSha &&
      SHA.test(pull.base?.sha ?? ""));
  const renames = reads?.renames;
  if (
    reads?.v !== 1 ||
    reads.pr !== number ||
    !validPull ||
    !Array.isArray(reads.closing?.nodes) ||
    reads.closing.pageInfo?.hasNextPage !== false ||
    (renames !== undefined && (!Array.isArray(renames?.nodes) || !isObject(renames.pageInfo)))
  ) {
    throw new Error("the handed-on reads are malformed");
  }
  return { pull, closing: reads.closing, renames };
}

export async function buildTrustedContext({ github, repository, prNumber, ids, reads }) {
  const trusted = createTrustCheck(github, ids);
  const dropped = {
    pr: 0,
    "issue-comment": 0,
    review: 0,
    "review-comment": 0,
    "linked-issue": 0,
    "linked-issue-comment": 0,
    "edited-by-untrusted": 0,
  };
  const items = [];
  async function keep(kind, list) {
    for (const item of list) {
      if (!(await trusted(item))) {
        dropped[kind] += 1;
        continue;
      }
      items.push({
        nodeId: item.node_id,
        kind,
        id: item.id,
        author_id: item.user.id,
        author_login: item.user.login,
        created_at: item.created_at ?? item.submitted_at ?? "",
        url: item.html_url,
        body: item.body ?? "",
      });
    }
  }

  const base = `/repos/${repository}`;
  const pull = reads?.pull ?? (await github("GET", `${base}/pulls/${prNumber}`));
  const prTrusted = await trusted(pull);
  if (!prTrusted) {
    dropped.pr += 1;
  }
  await keep("issue-comment", await paginate(github, `${base}/issues/${prNumber}/comments`));
  await keep("review", await paginate(github, `${base}/pulls/${prNumber}/reviews`));
  await keep("review-comment", await paginate(github, `${base}/pulls/${prNumber}/comments`));

  const firstPages = reads
    ? { data: { repository: { pullRequest: { closingIssuesReferences: reads.closing, ...(reads.renames && { timelineItems: reads.renames }) } } } }
    : await prPage(github, prTrusted ? CLOSING_AND_RENAMES : CLOSING_ISSUES, repository, prNumber, null);
  const references = await prConnection(github, CLOSING_ISSUES, "closingIssuesReferences", repository, prNumber, firstPages);
  for (const reference of references) {
    if (reference?.repository?.nameWithOwner !== repository) {
      dropped["linked-issue"] += 1;
      continue;
    }
    if (!Number.isInteger(reference.number)) {
      throw new Error("closing issue reference has an unexpected shape");
    }
    const issuePath = `${base}/issues/${reference.number}`;
    await keep("linked-issue", [await github("GET", issuePath)]);
    await keep("linked-issue-comment", await paginate(github, `${issuePath}/comments`));
  }

  const editedByListed = await readEditors(github, ids, [
    ...(prTrusted ? [pull.node_id] : []),
    ...items.map((item) => item.nodeId),
  ]);
  const stampHeld = reads?.pull == null || editedByListed.lastEditedAt.get(pull.node_id) === reads.pull.last_edited_at;
  const prKept = prTrusted && editedByListed(pull.node_id) && stampHeld;
  if (prTrusted && !prKept) {
    dropped["edited-by-untrusted"] += 1;
  }
  let titleKept = prKept;
  if (prKept) {
    const renamers = await titleRenamers(github, repository, prNumber, reads && !(reads.pull && reads.renames) ? undefined : firstPages);
    titleKept = renamers.every((actor) => isListed(ids, { id: actor?.databaseId }));
    if (!titleKept) {
      dropped["edited-by-untrusted"] += 1;
    }
  }
  const kept = [];
  for (const { nodeId, ...item } of items) {
    if (editedByListed(nodeId)) {
      kept.push(item);
    } else {
      dropped["edited-by-untrusted"] += 1;
    }
  }

  return {
    pr: {
      number: pull.number,
      head_sha: pull.head.sha,
      base_sha: pull.base.sha,
      author_id: pull.user?.id ?? 0,
      title: titleKept ? pull.title : "",
      body: prKept ? pull.body : null,
    },
    items: kept,
    dropped,
  };
}

export async function selectTrustedIssueComments({ github, repository, issueNumber, ids }) {
  const trusted = createTrustCheck(github, ids);
  const dropped = { "issue-comment": 0, "edited-by-untrusted": 0 };
  const authored = [];
  for (const comment of await paginate(github, `/repos/${repository}/issues/${issueNumber}/comments`)) {
    if (await trusted(comment)) {
      authored.push(comment);
    } else {
      dropped["issue-comment"] += 1;
    }
  }
  const editedByListed = await readEditors(github, ids, authored.map((comment) => comment.node_id));
  const kept = [];
  for (const comment of authored) {
    if (!editedByListed(comment.node_id)) {
      dropped["edited-by-untrusted"] += 1;
      continue;
    }
    kept.push({
      comment,
      lastEditedAt: editedByListed.lastEditedAt.get(comment.node_id) ?? null,
      lastEditorId: editedByListed.lastEditorId.get(comment.node_id) ?? null,
    });
  }
  return { kept, dropped };
}

const DECISION = /^\*\*Decision recorded\.\*\*(\s|$)/;
const firstLine = (body) => (body ?? "").trimStart().split("\n", 1)[0].trimEnd();

export function isDecisionComment({ comment, lastEditedAt, lastEditorId }, humans) {
  return (
    humans.has(comment.user?.id) &&
    comment.performed_via_github_app == null &&
    (lastEditedAt === null || humans.has(lastEditorId)) &&
    DECISION.test(firstLine(comment.body))
  );
}

async function readEditors(github, ids, nodeIds) {
  const unique = [...new Set(nodeIds.filter((id) => typeof id === "string" && id !== ""))];
  const trustedNodes = new Set();
  const lastEditedAt = new Map();
  const lastEditorId = new Map();
  for (let start = 0; start < unique.length; start += 100) {
    const answer = await github("POST", "/graphql", {
      query: LAST_EDITORS,
      variables: { ids: unique.slice(start, start + 100) },
    });
    for (const node of answer?.data?.nodes ?? []) {
      if (typeof node?.id !== "string") {
        continue;
      }
      if (node.lastEditedAt === null || isListed(ids, { id: node.editor?.databaseId })) {
        trustedNodes.add(node.id);
        lastEditedAt.set(node.id, node.lastEditedAt);
        lastEditorId.set(node.id, node.lastEditedAt === null ? null : node.editor.databaseId);
      }
    }
  }
  return Object.assign((nodeId) => trustedNodes.has(nodeId), { lastEditedAt, lastEditorId });
}

export async function main({ env = process.env, github, log = console.log } = {}) {
  const outputPath = env.OUTPUT_PATH;
  try {
    if (!outputPath) {
      throw new Error("output-path is empty");
    }
    rmSync(outputPath, { force: true });
    if (!PR_NUMBER.test(env.PR_NUMBER ?? "") || !REPOSITORY.test(env.REPOSITORY ?? "")) {
      throw new Error("pr-number or repository is malformed");
    }
    const ids = loadTrustedActors(trustedListPath(env, env.TRUSTED_ACTORS_PATH));
    const reads = env.READS_PATH ? takePrReads(readFileSync(env.READS_PATH, "utf8"), env.PR_NUMBER, env.HEAD_SHA) : undefined;
    const context = await buildTrustedContext({
      github: github ?? createGitHub({ token: env.GITHUB_TOKEN, apiUrl: env.GITHUB_API_URL }),
      repository: env.REPOSITORY,
      prNumber: env.PR_NUMBER,
      ids,
      reads,
    });
    writeFileSync(outputPath, `${JSON.stringify(context, null, 2)}\n`);
    const total = Object.values(context.dropped).reduce((sum, count) => sum + count, 0);
    log(`select-trusted-text: dropped total=${total} ${JSON.stringify(context.dropped)}`);
    return 0;
  } catch (error) {
    if (outputPath) {
      rmSync(outputPath, { force: true });
    }
    const detail = error?.name === "GitHubError" ? error.message : (error?.name ?? "error");
    log(`select-trusted-text: failed (${detail}); no context written`);
    return 1;
  } finally {
    if (env.READS_PATH) {
      rmSync(env.READS_PATH, { force: true });
    }
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
