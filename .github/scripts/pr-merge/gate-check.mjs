#!/usr/bin/env node
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../lib/github-client.mjs";

export const CHECK_NAME = "pr-merge / gate";
const ACTIONS_APP_ID = 15368;
const EXTERNAL_ID = "pr-merge-gate";
const CHUNK = 50;
const SUITES = 50;
const TITLE_CHARS = 200;
const BLOCKER_CHARS = 300;
const BLOCKERS = 20;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]*$/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
const flat = (text, chars) => Array.from(String(text).replaceAll(/[\r\n`]/g, " ").trim()).slice(0, chars).join("");

export function render(row) {
  if (!Number.isSafeInteger(row?.pr) || row.pr < 1 || !SHA.test(String(row?.head)) || Object.hasOwn(row, "carried")) {
    return null;
  }
  const blockers = Array.isArray(row.blockers) ? row.blockers : [];
  let conclusion = "neutral";
  let title;
  if (row.merged || row.enqueued) {
    conclusion = "success";
    title = row.merged ? "merged" : "in the merge queue at this head";
  } else if (row.ready && row.reportOnly === true) {
    title = "ready; report-only, so not enqueued";
  } else {
    title = flat(row.reason ?? blockers[0] ?? "", TITLE_CHARS) || (row.ready ? "ready, not enqueued this run" : "not ready");
  }
  const listed = blockers.slice(0, BLOCKERS).map((blocker) => flat(blocker, BLOCKER_CHARS));
  const more = blockers.length > BLOCKERS ? [`(${blockers.length - BLOCKERS} more)`] : [];
  const summary = [
    `pr-merge's gate on \`${row.head}\`: ${conclusion === "success" ? "" : "not merging: "}\`${title}\``,
    "",
    ...(listed.length === 0 ? ["No blockers."] : ["Blockers when the gate set this title:", "", "```text", ...listed, ...more, "```"]),
    "",
    "Informational: never required, and not part of `ci-status`.",
  ].join("\n");
  return { conclusion, title, summary };
}

export const READ_QUERY = (candidates) =>
  "query($o:String!,$r:String!,$n:String!){repository(owner:$o,name:$r){" +
  candidates
    .map(
      ({ head, pr }, i) =>
        `h${i}:object(oid:"${head}"){... on Commit{checkSuites(first:${SUITES},filterBy:{appId:${ACTIONS_APP_ID}})` +
        "{totalCount nodes{checkRuns(first:1,filterBy:{checkName:$n,checkType:LATEST}){nodes{databaseId name title conclusion externalId}}}}}} " +
        `p${i}:pullRequest(number:${pr}){headRefOid}`,
    )
    .join(" ") +
  "}}";

export function checkErrors(errors) {
  for (const error of Array.isArray(errors) ? errors : []) {
    const where = error?.path;
    const prAlias = Array.isArray(where) && where.length === 2 && where[0] === "repository" && /^p[0-9]+$/.test(String(where[1]));
    if (error?.type !== "NOT_FOUND" || !prAlias) {
      throw new Error(`GraphQL error: ${error?.type ?? "unknown"} at ${Array.isArray(where) ? where.join(".") : "no path"}`);
    }
  }
}

export function existing(node) {
  const suites = node?.checkSuites;
  const nodes = Array.isArray(suites?.nodes) ? suites.nodes : [];
  if (!suites || suites.totalCount !== nodes.length) {
    return undefined;
  }
  const runs = nodes
    .flatMap((suite) => suite?.checkRuns?.nodes ?? [])
    .filter((run) => run?.name === CHECK_NAME && run.externalId === EXTERNAL_ID && Number.isSafeInteger(run.databaseId));
  return runs.length === 0 ? null : runs.reduce((a, b) => (b.databaseId > a.databaseId ? b : a));
}

export async function main({ env = process.env, github, fetchImpl, now = () => new Date() } = {}) {
  try {
    if (!REPO.test(env.GITHUB_REPOSITORY ?? "")) {
      throw new Error("GITHUB_REPOSITORY is not owner/repo");
    }
    const repo = env.GITHUB_REPOSITORY;
    const [owner, name] = repo.split("/");
    let rows;
    try {
      rows = JSON.parse(readFileSync(env.SUMMARY_PATH, "utf8"));
    } catch {
      rows = [];
    }
    const wanted = new Map();
    for (const row of Array.isArray(rows) ? rows : []) {
      const check = render(row);
      if (check && !wanted.has(row.head)) {
        wanted.set(row.head, { pr: row.pr, ...check });
      }
    }
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined, fetchImpl, keepGraphQLErrors: true });
    const details = RUN_ID.test(env.GITHUB_RUN_ID ?? "")
      ? `${env.GITHUB_SERVER_URL || "https://github.com"}/${repo}/actions/runs/${env.GITHUB_RUN_ID}`
      : undefined;
    const heads = [...wanted.keys()];
    let failed = 0;
    let written = 0;
    let unchanged = 0;
    let skipped = 0;
    let unread = 0;
    let stale = 0;
    let readFailed = false;
    for (let start = 0; start < heads.length; start += CHUNK) {
      const chunk = heads.slice(start, start + CHUNK);
      let found;
      try {
        const answer = await github("POST", "/graphql", {
          query: READ_QUERY(chunk.map((head) => ({ head, pr: wanted.get(head).pr }))),
          variables: { o: owner, r: name, n: CHECK_NAME },
        });
        checkErrors(answer?.errors);
        found = answer?.data?.repository;
        if (!found) throw new Error("no repository in the answer");
      } catch (error) {
        unread += chunk.length;
        readFailed = true;
        console.log(`::warning title=gate-check::${chunk.length} heads not read, their checks left as they are: ${escapeCommand(error?.message ?? error)}`);
        continue;
      }
      for (const [i, head] of chunk.entries()) {
        const { pr, conclusion, title, summary } = wanted.get(head);
        const prHead = found[`p${i}`]?.headRefOid;
        if (prHead !== head) {
          stale += 1;
          console.log(
            `::warning title=gate-check::#${pr}: ${prHead ? `head is ${escapeCommand(prHead)}, not ${head}` : "pull request not read"}, no check written at ${head}`,
          );
          continue;
        }
        const current = existing(found[`h${i}`]);
        if (current === undefined) {
          unread += 1;
          console.log(`::warning title=gate-check::#${pr}: over ${SUITES} check suites at ${head}, its check left as it is`);
          continue;
        }
        if (current && current.title === title && String(current.conclusion).toLowerCase() === conclusion) {
          unchanged += 1;
          continue;
        }
        if (conclusion === "success" && !current) {
          skipped += 1;
          continue;
        }
        const body = {
          name: CHECK_NAME,
          external_id: EXTERNAL_ID,
          status: "completed",
          conclusion,
          completed_at: now().toISOString(),
          ...(details ? { details_url: details } : {}),
          output: { title, summary },
        };
        try {
          if (current) {
            await github("PATCH", `/repos/${repo}/check-runs/${current.databaseId}`, body);
          } else {
            await github("POST", `/repos/${repo}/check-runs`, { ...body, head_sha: head });
          }
          written += 1;
          console.log(`gate-check: #${pr} at ${head}: ${conclusion} ${title}`);
        } catch (error) {
          failed += 1;
          console.log(`::warning title=gate-check::#${pr}: ${escapeCommand(error?.message ?? error)}`);
        }
      }
    }
    console.log(`gate-check: sweep: ${written} written, ${unchanged} unchanged, ${skipped} skipped, ${stale} not the head, ${unread} unread, ${failed} failed`);
    return failed === 0 && !readFailed ? 0 : 1;
  } catch (error) {
    console.log(`::error title=gate-check::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
