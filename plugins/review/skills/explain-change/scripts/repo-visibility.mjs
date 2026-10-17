// The verified visibility of a pull request's repository, shared by the artifact
// gate (digest-policy.mjs) and the hosted publisher (publish-hosted.mjs), so both
// gate on the same value. No caller passes a visibility.

import { spawnSync } from "node:child_process";

const NAME = /^[A-Za-z0-9_.-]+$/;
const HOST = /^(?=.{1,253}$)(?![\d.]+$)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/i;

/** `[host/]owner/repo` as `{host, repo}` (`repo` is `owner/name`), or null when malformed. */
export function parseRepo(value) {
  const parts = String(value ?? "").split("/");
  const host = parts.length === 3 ? parts.shift() : undefined;
  const [owner, name] = parts;
  const ok = (host === undefined || HOST.test(host)) && parts.length === 2 && NAME.test(owner ?? "") && NAME.test(name ?? "");
  return ok ? { host, repo: `${owner}/${name}` } : null;
}

/** Logged in through gh's stored hosts; an enterprise token in the environment would vouch for any host, so it is left out. */
function ghLoggedIn(host) {
  const { GH_ENTERPRISE_TOKEN, GITHUB_ENTERPRISE_TOKEN, ...env } = process.env;
  return spawnSync("gh", ["auth", "status", "--hostname", host], { env, stdio: "ignore", timeout: 30000 }).status === 0;
}

/** REST, not `gh repo view`: GraphQL is refused in some sessions. Anything but a clean answer is UNKNOWN, which the gates send private. */
export function lookupVisibility(host, repo) {
  // A host gh is not logged in to could be anyone's server, answering "public" for a private repository.
  if (host && !ghLoggedIn(host)) return "UNKNOWN";
  const run = spawnSync("gh", ["api", ...(host ? ["--hostname", host] : []), `repos/${repo}`, "--jq", ".visibility"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 30000 });
  const answer = run.status === 0 && !run.error ? run.stdout.trim() : "";
  return ["public", "private", "internal"].includes(answer) ? answer.toUpperCase() : "UNKNOWN";
}
