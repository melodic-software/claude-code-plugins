// A GitHub REST client within a call budget, and a paginator over it, for
// lane scripts that call the API with a token and no retry.
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";

// Every GitHub call goes through the rate guard (rate-guard.mjs); the fetch
// is read at call time, so a test's stub is guarded too.
const guardedFetch = (url, init) => rateLimitLatch.guard(globalThis.fetch)(url, init);

export class BudgetSpent extends Error {}

// `call(method, path, body)` against GITHUB_API_URL with GITHUB_TOKEN. Each
// call spends one of `budget`, then waits for `pace`. A GET's 404 and any 204
// answer null; another failure throws with its `status`; a /zip path answers
// a Buffer, anything else its JSON.
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

// Every page of a list endpoint, until a short page. `key` names the array in
// an object answer (jobs, workflow_runs); more than `max` pages throws.
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
