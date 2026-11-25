
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";

const HOST = /^(?=.{1,253}$)(?![\d.]+$)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/i;
const PR_URL = /^https:\/\/([^/]+)\/([A-Za-z0-9-]+\/(?!\.\.?\/)[A-Za-z0-9_.-]+)\/pull\/([1-9]\d{0,8})$/;

/**
 * `{host, repo, pr}` from the `url` (`https://<host>/<owner>/<repo>/pull/<n>`) in the facts file
 * `/source-control:pull-request view` writes, or null when the file or its URL is unusable.
 */
export function prFromFacts(path) {
  let url;
  try {
    url = JSON.parse(readFileSync(path, "utf8"))?.url;
  } catch {
    return null;
  }
  const match = PR_URL.exec(typeof url === "string" ? url : "");
  return match && HOST.test(match[1]) ? { host: match[1].toLowerCase(), repo: match[2], pr: match[3] } : null;
}

/** Logged in through gh's stored hosts; an enterprise token in the environment would vouch for any host, so it is left out. */
function ghLoggedIn(host) {
  const { GH_ENTERPRISE_TOKEN, GITHUB_ENTERPRISE_TOKEN, ...env } = process.env;
  return spawnSync("gh", ["auth", "status", "--hostname", host], { env, stdio: "ignore", timeout: 30000 }).status === 0;
}

/** REST, not `gh repo view`: GraphQL is refused in some sessions. Anything but a clean answer is UNKNOWN, which the gates send private. */
export function lookupVisibility(host, repo) {
  if (host !== "github.com" && !ghLoggedIn(host)) return "UNKNOWN";
  const run = spawnSync("gh", ["api", "--hostname", host, `repos/${repo}`, "--jq", ".visibility"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 30000 });
  const answer = run.status === 0 && !run.error ? run.stdout.trim() : "";
  return ["public", "private", "internal"].includes(answer) ? answer.toUpperCase() : "UNKNOWN";
}
