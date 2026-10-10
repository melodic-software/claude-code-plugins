#!/usr/bin/env node
// Publish a built digest page to the shared page host through `pages-publish`,
// after the shared publish gate has read the exact bytes that would leave the
// machine. A credential refuses the upload; a repository that is not PUBLIC or a
// machine path or hostname sends the page to the private host. The page's id
// lives in a sidecar under the plugin data dir, keyed by repository and pull
// request, so a rebuild replaces the same page. When the page changes host, the
// copy on the old host is deleted.
//
//   publish-hosted.mjs <page> --repo <[host/]owner/repo> --pr <n> --data-dir <dir>
// The script looks up the --repo repository's visibility itself, on --repo's host
// (gh's default host when it names none); no caller passes a visibility. The page
// carries no repository identity, so --repo must name the pull request's
// repository, host included when that is not github.com.
// Prints one JSON object. Exit 0 published, 1 upload failed (keep the file),
// 2 usage or not a builder page, 4 refused: credential-shaped content.

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { publishGate } from "../../../lib/publish-gate.mjs";
import { validateView } from "../../../lib/view-builder.mjs";

const ID = /^[A-Za-z0-9_-]{22}$/;
const NAME = /^[A-Za-z0-9_.-]+$/;
const HOST = /^(?=.{1,253}$)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$/i;
const VISIBILITIES = ["public", "private"];

/** The data block's strings, one per line, so a credential the JSON escaping split is still read whole. */
function dataStrings(html) {
  const block = /<script type="application\/json" id="rv-data">([\s\S]*?)<\/script>/.exec(html);
  const out = [];
  const walk = (value) => {
    if (typeof value === "string") out.push(value);
    else if (value && typeof value === "object") Object.values(value).forEach(walk);
  };
  try {
    walk(JSON.parse(block?.[1] ?? "null"));
  } catch {
    // validateView already refused a page whose data block does not parse.
  }
  return out;
}

const valid = (e) => ID.test(e?.id) && VISIBILITIES.includes(e?.visibility);
const entry = ({ id, visibility, url }) => ({ id, visibility, url });

/** The current page, plus `stale`: copies on another host whose delete has not yet succeeded. */
const readSidecar = (path) => {
  try {
    const old = JSON.parse(readFileSync(path, "utf8"));
    if (!valid(old)) return null;
    return { ...entry(old), stale: (Array.isArray(old.stale) ? old.stale : []).filter(valid).map(entry) };
  } catch {
    return null;
  }
};

/** Written through a rename, so a stop mid-write never leaves the sidecar half-written. */
function writeSidecar(path, current, stale) {
  mkdirSync(join(path, ".."), { recursive: true, mode: 0o700 });
  const temp = `${path}.tmp`;
  writeFileSync(temp, `${JSON.stringify(stale.length ? { ...current, stale } : current)}\n`, { mode: 0o600 });
  renameSync(temp, path);
}

const pagesPublish = (args) => spawnSync("pages-publish", args, { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] });

/** REST, not `gh repo view`: GraphQL is refused in some sessions. Anything but a clean answer is UNKNOWN, which the gate sends private. */
function lookupVisibility(host, repo) {
  const run = spawnSync("gh", ["api", ...(host ? ["--hostname", host] : []), `repos/${repo}`, "--jq", ".visibility"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], timeout: 30000 });
  const answer = run.status === 0 && !run.error ? run.stdout.trim() : "";
  return ["public", "private", "internal"].includes(answer) ? answer.toUpperCase() : "UNKNOWN";
}

/** @returns {{exit: number, result: object}} */
export function publishHosted({ page, host, repo, pr, dataDir }) {
  const html = readFileSync(page, "utf8");
  // A connected page names the session bridge in its policy; it only works on this machine.
  if (!validateView(html).ok || /connect-src http:\/\/127\.0\.0\.1:\d{1,5}"/.test(html)) {
    return { exit: 2, result: { medium: "file", reason: "not a page the builder made for publishing" } };
  }
  const visibility = lookupVisibility(host, repo);
  const text = [html, ...dataStrings(html)].join("\n");
  const gate = publishGate({ explicit: false, visibility, text, subject: "page", medium: "hosted" });
  if (gate.medium !== "hosted") return { exit: 4, result: gate };

  const [owner, name] = repo.split("/");
  const key = host && host.toLowerCase() !== "github.com" ? `${host.toLowerCase()}__${owner}__${name}` : `${owner}__${name}`;
  const sidecar = join(dataDir, "hosted", `${key}__${pr}.json`);
  const old = readSidecar(sidecar);
  const args = [page, "--visibility", gate.destination];
  if (old?.visibility === gate.destination) args.push("--id", old.id);
  const run = pagesPublish(args);
  const failed = (reason) => ({ exit: 1, result: { medium: "file", reason } });
  if (run.error) return failed(`pages-publish did not run (${run.error.code ?? run.error.message})`);
  if (run.status === 4) return { exit: 4, result: { medium: "file", reason: "pages-publish refused credential-shaped content" } };
  if (run.status !== 0) return failed(`pages-publish exited ${run.status}`);
  let published;
  try {
    published = JSON.parse(run.stdout.trim().split("\n").pop());
  } catch {
    return failed("pages-publish printed no JSON line");
  }
  const { id, visibility: landed, url } = published ?? {};
  if (!ID.test(id ?? "") || !VISIBILITIES.includes(landed) || !/^https:\/\/\S+$/.test(url ?? "")) {
    return failed("pages-publish printed an unexpected result");
  }
  // The old copy is recorded as stale before its delete runs, so a failed or interrupted delete is retried next time.
  const current = { id, visibility: landed, url };
  const stale = (old?.stale ?? []).filter((e) => e.id !== id);
  if (old && old.id !== id) stale.push(entry(old));
  writeSidecar(sidecar, current, stale);

  const result = { medium: "hosted", visibility: landed, url, reason: gate.reason };
  if (stale.length) {
    const left = stale.filter((e) => pagesPublish(["--delete", e.id, "--visibility", e.visibility]).status !== 0);
    if (left.length < stale.length) writeSidecar(sidecar, current, left);
    result.old_copy = left.length
      ? `delete failed; ${left.map((e) => e.url ?? e.id).join(", ")} still up, retried on the next publish`
      : `deleted from the ${[...new Set(stale.map((e) => e.visibility))].join(" and ")} host`;
  }
  // pages-publish may lower public to private, never raise it; the sidecar keeps the id so a rerun deletes it.
  if (gate.destination === "private" && landed === "public") {
    return { exit: 1, result: { ...result, reason: `the gate chose the private host (${gate.reason}) but pages-publish put the page on the public host; take down ${url}` } };
  }
  return { exit: 0, result };
}

function main(argv) {
  const [page, ...rest] = argv;
  const flags = {};
  for (let i = 0; i < rest.length; i += 2) flags[rest[i]] = rest[i + 1];
  const parts = String(flags["--repo"] ?? "").split("/");
  const host = parts.length === 3 ? parts.shift() : undefined;
  const [owner, name] = parts;
  const ok =
    page &&
    !page.startsWith("--") &&
    rest.length === 6 &&
    (host === undefined || HOST.test(host)) &&
    parts.length === 2 &&
    NAME.test(owner ?? "") &&
    NAME.test(name ?? "") &&
    /^\d{1,9}$/.test(flags["--pr"] ?? "") &&
    isAbsolute(flags["--data-dir"] ?? "");
  if (!ok || !existsSync(page)) {
    process.stderr.write("usage: publish-hosted.mjs <page> --repo <[host/]owner/repo> --pr <n> --data-dir <absolute dir>\n");
    return 2;
  }
  const { exit, result } = publishHosted({
    page: resolve(page),
    host,
    repo: `${owner}/${name}`,
    pr: flags["--pr"],
    dataDir: flags["--data-dir"],
  });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  return exit;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
