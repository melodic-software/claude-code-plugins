// A workflow job's log as text, for work-unblock's refusal check: one fetch
// through the rate guard's latch, no retry, and a body over `maxBytes` bytes
// refused by its Content-Length or as it streams.
import { Buffer } from "node:buffer";

import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";
import { rateLimitLatch } from "../../actions/log-api-budget/rate-guard.mjs";

const TIMEOUT_MS = 20_000;

export function createJobLogReader({ token, apiUrl = "https://api.github.com", fetchImpl = fetch, latch = rateLimitLatch, timeoutMs = TIMEOUT_MS }) {
  const send = latch.guard(fetchImpl);
  return async function jobLog(repo, jobId, { maxBytes }) {
    const what = `GET /repos/${repo}/actions/jobs/${jobId}/logs`;
    const response = await send(`${apiUrl}/repos/${repo}/actions/jobs/${jobId}/logs`, {
      method: "GET",
      headers: { Accept: "application/vnd.github+json", Authorization: `Bearer ${token}`, "X-GitHub-Api-Version": "2022-11-28" },
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!response.ok) {
      await response.body?.cancel().catch(() => {});
      throw new GitHubError(response.status, what);
    }
    const over = () => new Error(`${what} answered a body over ${maxBytes} bytes`);
    if (Number(response.headers.get("content-length")) > maxBytes) {
      await response.body?.cancel().catch(() => {});
      throw over();
    }
    // Leaving the loop cancels the stream.
    const chunks = [];
    let size = 0;
    for await (const chunk of response.body ?? []) {
      size += chunk.byteLength;
      if (size > maxBytes) {
        throw over();
      }
      chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString("utf8");
  };
}
