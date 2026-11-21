import { restLogin } from "./pr-messages.mjs";

const PAGE_CAP = 30;
const ID = /^[1-9][0-9]{0,15}$/;

export const PR_COMMENTS_QUERY = `query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      comments(first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          fullDatabaseId body createdAt lastEditedAt isMinimized
          author { __typename login }
          editor { __typename login }
        }
      }
    }
  }
}`;

function comment(node) {
  if (!ID.test(node?.fullDatabaseId ?? "") || typeof node.body !== "string" || typeof node.isMinimized !== "boolean") {
    throw new Error("a comment in the answer is not of its shape");
  }
  return {
    id: Number(node.fullDatabaseId),
    author: restLogin(node.author),
    body: node.body,
    createdAt: node.createdAt,
    lastEditedAt: node.lastEditedAt ?? null,
    editor: restLogin(node.editor),
    isMinimized: node.isMinimized,
  };
}

export function graphqlStore(github, { timeoutMs } = {}) {
  return {
    async list({ repo, number }) {
      const [owner, name] = repo.split("/");
      const signal = timeoutMs === undefined ? undefined : AbortSignal.timeout(timeoutMs);
      const out = [];
      let after = null;
      for (let page = 0; page < PAGE_CAP; page++) {
        const answer = await github("POST", "/graphql", { query: PR_COMMENTS_QUERY, variables: { owner, name, number, after } }, {}, { signal });
        const comments = answer?.data?.repository?.pullRequest?.comments;
        if (!Array.isArray(comments?.nodes) || typeof comments.pageInfo?.hasNextPage !== "boolean") {
          throw new Error(`the answer for #${number} holds no comment list`);
        }
        out.push(...comments.nodes.map(comment));
        if (!comments.pageInfo.hasNextPage) return out;
        after = comments.pageInfo.endCursor;
      }
      throw new Error(`#${number} has more than ${PAGE_CAP * 100} comments`);
    },
    async create({ repo, number, body }) {
      const made = await github("POST", `/repos/${repo}/issues/${number}/comments`, { body });
      if (!Number.isSafeInteger(made?.id)) throw new Error("the new comment's answer carries no id");
      return { id: made.id };
    },
    async update({ repo, id, body }) {
      await github("PATCH", `/repos/${repo}/issues/comments/${id}`, { body });
    },
  };
}

export function memoryStore({ comments = [], login = "github-actions[bot]", now = () => new Date().toISOString() } = {}) {
  let next = comments.reduce((max, c) => Math.max(max, c.id ?? 0), 0) + 1;
  for (const c of comments) c.id ??= next++;
  const store = {
    comments,
    lists: 0,
    async list() {
      store.lists += 1;
      return comments.map((c) => ({ ...c }));
    },
    async create({ body }) {
      const made = { id: next++, author: login, body, createdAt: now(), lastEditedAt: null, editor: null, isMinimized: false };
      comments.push(made);
      return { id: made.id };
    },
    async update({ id, body }) {
      const own = comments.find((c) => c.id === id);
      if (!own) throw new Error(`no comment ${id}`);
      Object.assign(own, { body, lastEditedAt: now(), editor: login });
    },
  };
  return store;
}
