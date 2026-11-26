import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";

const guardedFetch = (url, init) => rateLimitLatch.guard(globalThis.fetch)(url, init);

export class BudgetSpent extends Error {}

export function budgetedClient(env, { budget = Number.POSITIVE_INFINITY, pace = async () => {} } = {}) {
  let used = 0;
  const call = async (method, path, body) => {
    if (used >= budget) throw new BudgetSpent(`call budget of ${budget} spent`);
    used += 1;
    await pace();
    const hasBody = body !== undefined;
    const response = await guardedFetch(`${env.GITHUB_API_URL ?? "https://api.github.com"}${path}`, {
      method,
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${env.GITHUB_TOKEN}`,
        "x-github-api-version": "2022-11-28",
        ...(hasBody && { "content-type": "application/json" }),
      },
      ...(hasBody && { body: JSON.stringify(body) }),
    });
    if (response.status === 404 && method === "GET") return null;
    if (!response.ok) {
      throw Object.assign(new Error(`${method} ${path.split("?")[0]}: HTTP ${response.status}`), { status: response.status });
    }
    if (response.status === 204) return null;
    return path.endsWith("/zip") ? Buffer.from(await response.arrayBuffer()) : response.json();
  };
  call.used = () => used;
  call.remaining = () => budget - used;
  return call;
}

export async function pages(call, path, { key, max = 20 } = {}) {
  const items = [];
  for (let page = 1; page <= max; page += 1) {
    const answer = await call("GET", `${path}${path.includes("?") ? "&" : "?"}per_page=100&page=${page}`);
    const batch = (key ? answer?.[key] : answer) ?? [];
    items.push(...batch);
    if (batch.length < 100) return items;
  }
  throw new Error(`${path.split("?")[0]}: more than ${max} pages`);
}
