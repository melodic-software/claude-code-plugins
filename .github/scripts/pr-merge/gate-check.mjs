#!/usr/bin/env node
// gate-check.mjs: shows pr-merge's current verdict on each candidate as one
// `pr-merge / gate` check run on the candidate's head, from the sweep's
// pr-merge-summary.json. No model.
//
// The check is informational. Its name is not `ci-status`, the only check the
// main ruleset requires, and pr-require-checks.yml's `ci-status` aggregates
// only its own jobs, so it is never required and never feeds `ci-status`. The
// gate reads a neutral or successful check run as passing
// (babysit_checks.CHECK_SUCCESS_STATES), so it never holds a merge either.
//
//   refused, held, or not judged   neutral, titled with the top refusal: the
//                                  gate's reason, else its first blocker
//   ready but not enqueued         neutral, titled with why
//   enqueued or merged             success, written only over an existing
//                                  check run at that head: with none there is
//                                  no refusal on show to replace
//
// One GraphQL read per CHUNK candidates finds the newest such check run the
// GitHub Actions app posted at each head. A head whose check already has this
// title and conclusion gets no write, so an unchanged sweep writes nothing;
// otherwise that check run is updated in place, or a new one created. The
// summary lists the blockers of the sweep that set the title. A row the gate
// did not judge in this run (`carried`) is left as it is. A failed read leaves
// its chunk's checks as they are.
//
// Environment:
//   GH_TOKEN            the job's own token, with checks: write
//   GITHUB_REPOSITORY   owner/repo
//   SUMMARY_PATH        pr-merge-summary.json
//   GITHUB_RUN_ID, GITHUB_SERVER_URL, GITHUB_API_URL
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

import { createGitHub } from "../../actions/check-trusted-trigger/check-trusted-trigger.mjs";

export const CHECK_NAME = "pr-merge / gate";
const ACTIONS_APP_ID = 15368;
const CHUNK = 50;
// The Actions app's check suites at one head, one per workflow run there
// (judgment: a head with more is read as cut short).
const SUITES = 50;
// Room for a reason and its detail (judgment); GitHub documents no limit.
const TITLE_CHARS = 200;
// As the step summary trims them (pr-merge.yml).
const BLOCKER_CHARS = 300;
const BLOCKERS = 20;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const SHA = /^[0-9a-f]{40}$/;
const RUN_ID = /^[1-9][0-9]*$/;

const escapeCommand = (text) => String(text).replaceAll(/[\r\n%]/g, " ");
// One line with no backticks, so it cannot leave the summary's fence.
const flat = (text, chars) => Array.from(String(text).replaceAll(/[\r\n`]/g, " ").trim()).slice(0, chars).join("");

// The check run a summary row should show, or null for a row with none.
export function render(row) {
  if (!Number.isSafeInteger(row?.pr) || !SHA.test(String(row?.head)) || Object.hasOwn(row, "carried")) {
    return null;
  }
  const blockers = Array.isArray(row.blockers) ? row.blockers : [];
  let conclusion = "neutral";
  let title;
  if (row.merged || row.enqueued) {
    conclusion = "success";
    title = row.merged ? "merged" : "in the merge queue at this head";
  } else if (row.ready) {
    title = row.reportOnly === true ? "ready; report-only, so not enqueued" : "ready, but the enqueue failed";
  } else {
    title = flat(row.reason ?? blockers[0] ?? "not ready", TITLE_CHARS) || "not ready";
  }
  const listed = blockers.slice(0, BLOCKERS).map((blocker) => flat(blocker, BLOCKER_CHARS));
  const more = blockers.length > BLOCKERS ? [`(${blockers.length - BLOCKERS} more)`] : [];
  const summary = [
    `pr-merge's gate on \`${row.head}\`: ${conclusion === "success" ? title : `not merging (${title})`}.`,
    "",
    listed.length === 0 ? "No blockers." : "Blockers when the gate set this title:",
    ...(listed.length === 0 ? [] : ["", "```text", ...listed, ...more, "```"]),
    "",
    "Informational: never required, and not part of `ci-status`.",
  ].join("\n");
  return { conclusion, title, summary };
}

export const READ_QUERY = (heads) =>
  "query($o:String!,$r:String!,$n:String!){rateLimit{cost} repository(owner:$o,name:$r){" +
  heads
    .map(
      (sha, i) =>
        `h${i}:object(oid:"${sha}"){... on Commit{checkSuites(first:${SUITES},filterBy:{appId:${ACTIONS_APP_ID}})` +
        "{totalCount nodes{checkRuns(first:1,filterBy:{checkName:$n,checkType:LATEST}){nodes{databaseId name title conclusion}}}}}}",
    )
    .join(" ") +
  "}}";

// The newest `CHECK_NAME` check run at each head, null for none, and
// undefined when the listing may be cut short.
export function existing(node) {
  const suites = node?.checkSuites;
  const nodes = Array.isArray(suites?.nodes) ? suites.nodes : [];
  if (!suites || suites.totalCount !== nodes.length) {
    return undefined;
  }
  const runs = nodes
    .flatMap((suite) => suite?.checkRuns?.nodes ?? [])
    .filter((run) => run?.name === CHECK_NAME && Number.isSafeInteger(run.databaseId));
  return runs.length === 0 ? null : runs.reduce((a, b) => (b.databaseId > a.databaseId ? b : a));
}

export async function main({ env = process.env, github, now = () => new Date() } = {}) {
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
    // One check per head; a head listed twice keeps its first row.
    const wanted = new Map();
    for (const row of Array.isArray(rows) ? rows : []) {
      const check = render(row);
      if (check && !wanted.has(row.head)) {
        wanted.set(row.head, { pr: row.pr, ...check });
      }
    }
    github ??= createGitHub({ token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL || undefined });
    const details = RUN_ID.test(env.GITHUB_RUN_ID ?? "")
      ? `${env.GITHUB_SERVER_URL || "https://github.com"}/${repo}/actions/runs/${env.GITHUB_RUN_ID}`
      : undefined;
    const heads = [...wanted.keys()];
    let failed = 0;
    let written = 0;
    for (let start = 0; start < heads.length; start += CHUNK) {
      const chunk = heads.slice(start, start + CHUNK);
      let found;
      try {
        found = (await github("POST", "/graphql", { query: READ_QUERY(chunk), variables: { o: owner, r: name, n: CHECK_NAME } }))?.data?.repository;
        if (!found) throw new Error("no repository in the answer");
      } catch (error) {
        failed += 1;
        console.log(`::warning title=gate-check::${chunk.length} heads not read, their checks left as they are: ${escapeCommand(error?.message ?? error)}`);
        continue;
      }
      for (const [i, head] of chunk.entries()) {
        const { pr, conclusion, title, summary } = wanted.get(head);
        const current = existing(found[`h${i}`]);
        if (current && current.title === title && String(current.conclusion).toLowerCase() === conclusion) {
          continue;
        }
        if (conclusion === "success" && !current) {
          continue;
        }
        const body = {
          name: CHECK_NAME,
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
    console.log(`gate-check: ${written} written, ${heads.length - written} unchanged or skipped`);
    return failed === 0 ? 0 : 1;
  } catch (error) {
    console.log(`::error title=gate-check::${escapeCommand(error?.message ?? error)}`);
    return 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = await main();
}
