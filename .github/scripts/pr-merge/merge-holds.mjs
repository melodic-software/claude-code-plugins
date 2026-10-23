#!/usr/bin/env node
// merge-holds.mjs: the merge holds a pull request's own text carries, by the
// rules pr-merge's gate reads them. enable-auto-merge.mjs arms nothing they
// hold, and ci-status runs this file alone, fetched from the base commit, on
// every lanes App pull request, so it imports no other file of the repository.
//
// - A body hold (babysit_merge_policy.BODY_MERGE_HOLD_RE): a line opening with
//   `Hold:`, or "do not merge" anywhere. Removing that text lifts it.
// - A member veto (babysit_merge.human_veto_logins): each OWNER, MEMBER or
//   COLLABORATOR person's newest comment, review or inline comment with text
//   decides, and holds when it says "do not merge"
//   (babysit_merge.HUMAN_MERGE_VETO_RE). A later one by the same person
//   lifts it; an item with no text lifts nothing.
//
// Command line: merge-holds.mjs <number> <body-file> <discussion-file>. The
// discussion file holds one REST issue comment, review or review comment per
// line. Each hold prints as an ::error:: and exits 1; no hold exits 0.
import { readFileSync } from "node:fs";
import process from "node:process";
import { pathToFileURL } from "node:url";

// enable-auto-merge.test.mjs checks both agree with the gate's Python on every
// text it tries.
export const BODY_HOLD = /\bdo(?:n['’]?t| not)\s+merge\b|(?:^|\r)[^\S\r\n]*hold:/im;
export const HUMAN_VETO = /\bdo(?:n['’]?t| not|-not)[\s-]*merge\b/i;
// babysit_merge_policy.BLOCKER_ASSOCIATIONS.
const MEMBERS = new Set(["OWNER", "MEMBER", "COLLABORATOR"]);

// The members whose newest item with text vetoes the merge, sorted. Each item
// is { login, isUser, association, at, body }, `at` an ISO 8601 UTC time.
export function vetoers(items) {
  const newest = new Map();
  for (const { login, isUser, association, at, body } of items) {
    if (!isUser || !MEMBERS.has(String(association).toUpperCase()) || !String(body ?? "").trim()) {
      continue;
    }
    if (!newest.has(login) || at >= newest.get(login).at) {
      newest.set(login, { at, body: String(body) });
    }
  }
  return [...newest]
    .filter(([, { body }]) => HUMAN_VETO.test(body))
    .map(([login]) => login)
    .sort();
}

// One REST issue comment, review or review comment as a vetoers item.
export const fromRest = (row) => ({
  login: String(row?.user?.login ?? ""),
  isUser: row?.user?.type === "User",
  association: row?.author_association,
  at: String(row?.submitted_at ?? row?.created_at ?? ""),
  body: String(row?.body ?? ""),
});

// Why the pull request's `body` and discussion `items` hold it; empty when
// nothing does.
export function holds(body, items) {
  const reasons = [];
  if (BODY_HOLD.test(String(body ?? ""))) {
    reasons.push("its body holds it (a line opening with 'Hold:', or 'do not merge'); removing that text lifts it");
  }
  const vetoes = vetoers(items);
  if (vetoes.length) {
    reasons.push(`${vetoes.join(", ")} asked not to merge it; a later comment by the same person lifts it, then re-run ci-status`);
  }
  return reasons;
}

export function main(argv = process.argv.slice(2)) {
  const [number, bodyFile, discussionFile] = argv;
  try {
    if (!/^[1-9][0-9]*$/.test(String(number)) || !bodyFile || !discussionFile) {
      throw new Error("usage: merge-holds.mjs <number> <body-file> <discussion-file>");
    }
    const items = readFileSync(discussionFile, "utf8")
      .split("\n")
      .filter((line) => line.trim())
      .map((line) => fromRest(JSON.parse(line)));
    const reasons = holds(readFileSync(bodyFile, "utf8"), items);
    for (const reason of reasons) {
      console.log(`::error::#${number}: ${reason.replaceAll("%", "%25")}.`);
    }
    if (!reasons.length) {
      console.log(`#${number}: no body hold and no member veto.`);
    }
    return reasons.length ? 1 : 0;
  } catch (error) {
    console.log(`::error::merge-holds: ${String(error?.message ?? error).replaceAll(/[\r\n%]/g, " ")}`);
    return 2;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  process.exitCode = main();
}
