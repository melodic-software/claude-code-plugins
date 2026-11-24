import { GitHubError } from "../lib/github-client.mjs";

export const TIP = "f".repeat(40);

export function mainCall(url, { offMain = [], mainTag = false } = {}) {
  if (/\/git\/ref\/tags\/main$/.test(url)) {
    if (mainTag) return { ref: "refs/tags/main", object: { sha: TIP } };
    throw new GitHubError(404, "GET tag");
  }
  if (/\/git\/ref\/heads\/main$/.test(url)) return { ref: "refs/heads/main", object: { sha: TIP } };
  const base = new RegExp(`/compare/([0-9a-f]{40})\\.\\.\\.(?:${TIP}|refs/heads/main\\?per_page=1)$`).exec(url)?.[1];
  if (base) return { status: offMain.includes(base) ? "diverged" : base === TIP ? "identical" : "ahead" };
  return undefined;
}
