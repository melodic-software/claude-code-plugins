// The answers a fake GitHub client gives the reads of head-ref-map.mjs
// `onMain` (check-trusted-trigger.mjs requireOnDefaultBranch): the tag named
// main (a 404 unless `mainTag`), main's tip, and the compare of a head commit
// with that tip or with refs/heads/main (`offMain` lists the commits not on main). Any other URL is
// undefined.
import { GitHubError } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

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
