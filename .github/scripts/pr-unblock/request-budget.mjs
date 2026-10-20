// A fetch wrapper the dispatchers' GitHub adapters share. It counts the calls
// a run makes, keeps the x-ratelimit-* headers of the last response per
// resource (the headers are the authoritative reading, per
// https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api),
// logs the message and retry-after of a 403 or 429 so a secondary limit can be
// told from a primary one, and repeats a GET of a URL it already read as a
// conditional request: a 304 "does not count against your primary rate limit"
// when the request is authorized
// (https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests),
// and the first response's body is returned for it.

export function budgetedFetch({ fetch = globalThis.fetch, log = (line) => console.log(line) } = {}) {
  const seen = new Map();
  const counts = { rest: 0, notModified: 0, graphql: 0 };
  const last = new Map();

  async function wrapped(url, init = {}) {
    const method = init.method ?? "GET";
    const graphql = String(url).endsWith("/graphql");
    const cached = method === "GET" ? seen.get(String(url)) : undefined;
    const headers = cached ? { ...init.headers, "If-None-Match": cached.etag } : init.headers;
    const response = await fetch(url, { ...init, headers });
    const header = (name) => response.headers?.get?.(name) ?? null;
    const resource = header("x-ratelimit-resource");
    if (resource) {
      last.set(resource, ["limit", "remaining", "used", "reset"].map((key) => header(`x-ratelimit-${key}`)));
    }
    if (cached && response.status === 304) {
      counts.notModified += 1;
      return new Response(cached.body, { status: 200, headers: cached.headers });
    }
    counts[graphql ? "graphql" : "rest"] += 1;
    if (response.status === 403 || response.status === 429) {
      const text = await response.clone().text();
      let message = "";
      try {
        message = String(JSON.parse(text).message ?? "");
      } catch {
        message = "";
      }
      log(
        `::warning::${method} returned ${response.status}: message=${JSON.stringify(message.slice(0, 200))}` +
          ` retry-after=${header("retry-after") ?? "none"} remaining=${header("x-ratelimit-remaining") ?? "none"}`,
      );
    }
    const etag = header("etag");
    if (method === "GET" && response.status === 200 && etag) {
      seen.set(String(url), { etag, body: await response.clone().text(), headers: [...response.headers] });
    }
    return response;
  }

  // One line in the pr-merge rate line's shape: counts, then each resource's
  // last header reading.
  function summary() {
    const readings = [...last].map(([resource, [limit, remaining, used, reset]]) => {
      const at = Number(reset) > 0 ? new Date(Number(reset) * 1000).toISOString().replace(".000Z", "Z") : "unknown";
      return `${resource} remaining=${remaining} used=${used} limit=${limit} reset=${at}`;
    });
    return [`api-calls rest=${counts.rest} not-modified=${counts.notModified} graphql=${counts.graphql}`, ...readings].join(" ");
  }

  return { fetch: wrapped, counts, summary };
}
