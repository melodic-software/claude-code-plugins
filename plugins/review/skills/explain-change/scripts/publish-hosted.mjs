#!/usr/bin/env node
// Publish a built digest page to the shared page host through `pages-publish`,
// after the shared publish gate has read the exact bytes that would leave the
// machine. A credential refuses the upload; a repository that is not PUBLIC or a
// machine path or hostname sends the page to the private host. The page's id
// lives in a sidecar under the plugin data dir, keyed by repository and pull
// request, so a rebuild replaces the same page. When the page changes host, the
// copy on the old host is deleted.
//
//   publish-hosted.mjs <page> --repo <owner/repo> --pr <n>
//                      --repo-visibility <PUBLIC|PRIVATE|INTERNAL|UNKNOWN> --data-dir <dir>
// Prints one JSON object. Exit 0 published, 1 upload failed (keep the file),
// 2 usage or not a builder page, 4 refused: credential-shaped content.

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { publishGate } from "../../../lib/publish-gate.mjs";
import { validateView } from "../../../lib/view-builder.mjs";

const ID = /^[A-Za-z0-9_-]{22}$/;
const NAME = /^[A-Za-z0-9_.-]+$/;
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

const readSidecar = (path) => {
  try {
    const old = JSON.parse(readFileSync(path, "utf8"));
    return ID.test(old?.id) && VISIBILITIES.includes(old?.visibility) ? old : null;
  } catch {
    return null;
  }
};

const pagesPublish = (args) => spawnSync("pages-publish", args, { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] });

/** @returns {{exit: number, result: object}} */
export function publishHosted({ page, repo, pr, repoVisibility, dataDir }) {
  const html = readFileSync(page, "utf8");
  // A connected page names the session bridge in its policy; it only works on this machine.
  if (!validateView(html).ok || /connect-src http:\/\/127\.0\.0\.1:\d{1,5}"/.test(html)) {
    return { exit: 2, result: { medium: "file", reason: "not a page the builder made for publishing" } };
  }
  // A pull request always has a repository, so NONE counts as not PUBLIC here.
  const visibility = repoVisibility === "NONE" ? "UNKNOWN" : repoVisibility;
  const text = [html, ...dataStrings(html)].join("\n");
  const gate = publishGate({ explicit: false, visibility, text, subject: "page", medium: "hosted" });
  if (gate.medium !== "hosted") return { exit: 4, result: gate };

  const [owner, name] = repo.split("/");
  const sidecar = join(dataDir, "hosted", `${owner}__${name}__${pr}.json`);
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
  mkdirSync(join(dataDir, "hosted"), { recursive: true, mode: 0o700 });
  writeFileSync(sidecar, `${JSON.stringify({ id, visibility: landed, url })}\n`, { mode: 0o600 });

  const result = { medium: "hosted", visibility: landed, url, reason: gate.reason };
  if (old && old.visibility !== landed) {
    const removed = pagesPublish(["--delete", old.id, "--visibility", old.visibility]);
    result.old_copy = removed.status === 0 ? `deleted from the ${old.visibility} host` : `delete on the ${old.visibility} host failed; ${old.url ?? old.id} is still up`;
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
  const [owner, name, extra] = String(flags["--repo"] ?? "").split("/");
  const ok =
    page &&
    !page.startsWith("--") &&
    rest.length === 8 &&
    NAME.test(owner ?? "") &&
    NAME.test(name ?? "") &&
    extra === undefined &&
    /^\d{1,9}$/.test(flags["--pr"] ?? "") &&
    /^[A-Za-z]+$/.test(flags["--repo-visibility"] ?? "") &&
    isAbsolute(flags["--data-dir"] ?? "");
  if (!ok || !existsSync(page)) {
    process.stderr.write(
      "usage: publish-hosted.mjs <page> --repo <owner/repo> --pr <n> --repo-visibility <VISIBILITY> --data-dir <absolute dir>\n",
    );
    return 2;
  }
  const { exit, result } = publishHosted({
    page: resolve(page),
    repo: flags["--repo"],
    pr: flags["--pr"],
    repoVisibility: flags["--repo-visibility"].toUpperCase(),
    dataDir: flags["--data-dir"],
  });
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  return exit;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
