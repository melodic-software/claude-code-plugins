#!/usr/bin/env node
// Counts the checks merged changes record with a `Codifies:` line, from the default branch's
// first-parent git history.
//   count-checks.mjs [--since <YYYY-MM-DD>] [--until <YYYY-MM-DD>] [--bucket week|month]
// A record is a whole message line, at column 0, matching
//   Codifies: <#n | session> rung=<rung id> <blocking|advisory>
// Any other line that looks like an attempted record is listed as not counted, with its reason; a
// mention of `Codifies:` in prose elsewhere on a line is ignored.
// Rung ids and their tiers are read from the plugin's copy of the enforcement ladder: codebase,
// static-analysis and verification rungs count; guidance and human-review rungs are listed as not
// counted. A blocking record whose source `#p` is the pull request that landed an earlier advisory
// record of the same rung (the `(#p)` its commit subject ends with) is a promotion: the check moves
// from the advisory column to the blocking one and is counted once. A record whose commit a later
// default-branch commit reverts is listed as reverted, not counted; a blocking record that would have
// promoted a reverted advisory record counts as a new blocking check and is listed as such.
// Reads git history only: it calls no forge and writes no file. Commit text is data, printed escaped.
// Exit: 0 ok (an empty history prints zeros), 2 usage, 1 no default branch, a failed git read or an
// unreadable ladder.
import { spawnSync } from "node:child_process";
import { readFileSync, realpathSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const ROOT = resolve(dirname(realpathSync.native(fileURLToPath(import.meta.url))), "..");
const LADDER = join(ROOT, "skills/codify/reference/enforcement-ladder.md");
const COUNTED_TIERS = new Set(["Codebase", "Static analysis", "Verification"]);
const USAGE = "usage: count-checks.mjs [--since <YYYY-MM-DD>] [--until <YYYY-MM-DD>] [--bucket week|month]";
const DAY = /^(\d{4})-(\d{2})-(\d{2})$/;
const RECORD = /^Codifies: (#[1-9][0-9]*|session) rung=([a-z0-9-]+) (blocking|advisory)$/;
const RECORD_PREFIX = /^Codifies: (?:#[1-9][0-9]*|session) rung=[a-z0-9-]+ (?:blocking|advisory)\s/;
const KEY = "Codifies:";
const ATTEMPT = /Codifies:[ \t]*(?:#[0-9]|session|<)/;
/** True when a line naming `Codifies:` looks like an attempted record, not a mention in prose. */
const recordLike = (line) => ATTEMPT.test(line) || line.includes("rung=");
const REVERTS_SHA = /^This reverts commit ([0-9a-f]{7,40})\b/;
const REVERTS_PR = /^Reverts (?:([A-Za-z0-9._-]+\/[A-Za-z0-9._-]+))?#([1-9][0-9]*)\b/;
const PR_SUFFIX = /\(#([1-9][0-9]*)\)\s*$/;
const UNSAFE = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/gu;

const say = (text) => process.stderr.write(`count-checks: ${text}\n`);
const usage = (why) => {
  if (why) say(why);
  say(USAGE);
  process.exit(2);
};
const fail = (why) => {
  say(why);
  process.exit(1);
};

/** JSON text with every control, format and separator character escaped. */
const show = (value) =>
  JSON.stringify(value).replace(UNSAFE, (c) =>
    c.split("").map((unit) => `\\u${unit.charCodeAt(0).toString(16).padStart(4, "0")}`).join(""),
  );

/** True when text is a real calendar day in YYYY-MM-DD form. */
function isDay(text) {
  const m = DAY.exec(text);
  if (!m) return false;
  const date = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  return date.toISOString().slice(0, 10) === text;
}

let opts;
try {
  ({ values: opts } = parseArgs({ options: { since: { type: "string" }, until: { type: "string" }, bucket: { type: "string" } } }));
} catch (error) {
  usage(error.message);
}
for (const name of ["since", "until"]) {
  if (opts[name] !== undefined && !isDay(opts[name])) usage(`--${name} must be a day as YYYY-MM-DD, e.g. 2026-11-01`);
}
const bucket = opts.bucket ?? "month";
if (bucket !== "week" && bucket !== "month") usage("--bucket must be week or month");
const today = new Date().toISOString().slice(0, 10);
const until = opts.until ?? today;
if (opts.since !== undefined && opts.since > until) usage(`--since is after ${opts.until === undefined ? "today" : "--until"}`);

/** Rung ids by whether they count, and the aliases, read from the ladder copy. */
function readLadder() {
  let text;
  try {
    text = readFileSync(LADDER, "utf8");
  } catch (error) {
    fail(`cannot read the enforcement ladder at ${LADDER} (${error.code ?? error.message})`);
  }
  const order = [];
  const counted = new Set();
  const notCounted = new Set();
  const aliases = new Map();
  let tier = null;
  for (const line of text.split("\n")) {
    const heading = /^#{2,3} (?:Tier \d+: (.+)|.*)$/.exec(line);
    if (heading) {
      tier = heading[1]?.trim() ?? null;
      continue;
    }
    const alias = /^Alias: `([a-z0-9-]+)` is read as `([a-z0-9-]+)`/.exec(line);
    if (alias) aliases.set(alias[1], alias[2]);
    if (tier === null) continue;
    const id = /^\d+\. \*\*`([a-z0-9-]+)`\*\*/.exec(line)?.[1] ?? /^\| `([a-z0-9-]+)` \|/.exec(line)?.[1];
    if (id) {
      order.push(id);
      (COUNTED_TIERS.has(tier) ? counted : notCounted).add(id);
    }
  }
  if (counted.size === 0) fail(`no counted rung ids found in ${LADDER}`);
  return { order, counted, notCounted, aliases };
}

function git(args) {
  const run = spawnSync("git", args, { encoding: "utf8", maxBuffer: 512 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"] });
  if (run.error) fail(`git ${args[0]} did not complete (${run.error.code ?? run.error.message})`);
  return run;
}

/** The default branch's ref: origin's HEAD, else origin's or the local main or master. */
function defaultBranch() {
  const head = git(["symbolic-ref", "--quiet", "refs/remotes/origin/HEAD"]);
  if (head.status === 0 && head.stdout.trim()) return head.stdout.trim();
  for (const ref of ["refs/remotes/origin/main", "refs/remotes/origin/master", "refs/heads/main", "refs/heads/master"]) {
    if (git(["rev-parse", "--verify", "--quiet", `${ref}^{commit}`]).status === 0) return ref;
  }
  return fail("no default branch found (origin/HEAD, main or master); run from inside the repository");
}

/** origin's `owner/repo`, lowercased, or null when no origin URL can be read. */
function originRepo() {
  const url = git(["remote", "get-url", "origin"]);
  if (url.status !== 0) return null;
  const m = /[/:]([^/:]+)\/([^/]+?)(?:\.git)?\/*$/.exec(url.stdout.trim());
  return m ? `${m[1]}/${m[2]}`.toLowerCase() : null;
}

/** Why a line naming `Codifies:` other than at column 0 is not a record. */
function placement(line) {
  const before = line.slice(0, line.indexOf(KEY));
  const lead = /^[ \t>]*/.exec(before)[0];
  const quoting = before.endsWith("`") ? " quoting it in a code span" : "";
  let where;
  if (/^(?:[-*+]|\d{1,9}[.)])[ \t]/.test(before.slice(lead.length))) where = `a list item${quoting}`;
  else if (lead.includes(">")) where = `a quoted line${quoting}`;
  else if (lead !== "") where = `an indented line${quoting}`;
  else if (before === "`") where = "a code span";
  else where = `a line of other text${quoting}`;
  return `${where}, not a line of its own at column 0`;
}

const ladder = readLadder();
const ref = defaultBranch();
const thisRepo = originRepo();
const log = git([
  "log",
  "--first-parent",
  "--format=%H%x1f%cI%x1f%s%x1f%B%x1e",
  "--grep=Codifies:",
  "--grep=^This reverts commit ",
  "--grep=^Reverts ",
  ref,
  "--",
]);
if (log.status !== 0) fail(`git log ${ref} failed: ${log.stderr.trim()}`);

// Oldest first, so an advisory record is seen before the blocking one that promotes it.
const commits = log.stdout
  .split("\x1e")
  .map((chunk) => chunk.replace(/^\n/, ""))
  .filter((chunk) => chunk.includes("\x1f"))
  .map((chunk) => {
    const [sha, iso, subject, body = ""] = chunk.split("\x1f");
    return { sha, day: new Date(iso).toISOString().slice(0, 10), subject, lines: body.split("\n").map((l) => l.replace(/\r$/, "")) };
  })
  .reverse();
for (const [index, c] of commits.entries()) c.index = index;

// Reverts: by commit hash, or by the pull request number a squash subject ends with.
const byPr = new Map();
for (const c of commits) {
  const pr = PR_SUFFIX.exec(c.subject)?.[1];
  if (pr) byPr.set(pr, [...(byPr.get(pr) ?? []), c]);
}
// Only a commit whose subject starts `Revert ` reverts, and only a commit older than itself.
// `Reverts owner/repo#n` names a pull request in this repository only when owner/repo is origin's;
// with no origin owner/repo to compare, the number alone is matched and the output says so.
const revertersOf = new Map();
let unscopedReverts = 0;
for (const [index, c] of commits.entries()) {
  if (!c.subject.startsWith("Revert ")) continue;
  const older = commits.slice(0, index);
  for (const line of c.lines) {
    const sha = REVERTS_SHA.exec(line)?.[1];
    const [, repo, number] = REVERTS_PR.exec(line) ?? [];
    if (repo && thisRepo === null) unscopedReverts += 1;
    const pr = repo && thisRepo !== null && repo.toLowerCase() !== thisRepo ? undefined : number;
    const targets = sha ? older.filter((t) => t.sha.startsWith(sha)) : pr ? (byPr.get(pr) ?? []).filter((t) => older.includes(t)) : [];
    if (sha && targets.length !== 1) continue;
    for (const t of targets) revertersOf.set(t.sha, [...(revertersOf.get(t.sha) ?? []), c]);
  }
}
const effectiveMemo = new Map();
/** A commit stands unless a commit that itself stands reverts it. */
function effective(c, seen = new Set()) {
  if (effectiveMemo.has(c.sha)) return effectiveMemo.get(c.sha);
  if (seen.has(c.sha)) return true;
  seen.add(c.sha);
  const reverter = (revertersOf.get(c.sha) ?? []).find((r) => effective(r, seen));
  const result = reverter === undefined;
  effectiveMemo.set(c.sha, result);
  if (!result) c.revertedBy = reverter;
  return result;
}

const records = [];
const notCounted = [];
const reverted = [];
const aliased = [];
for (const c of commits) {
  const seenLines = new Set();
  for (const line of c.lines) {
    if (!line.includes(KEY)) continue;
    const atColumn0 = line.startsWith(KEY);
    if (!atColumn0 && !recordLike(line)) continue;
    const entry = { commit: c, line };
    if (seenLines.has(line)) {
      notCounted.push({
        ...entry,
        why: "repeats a line earlier in this commit message, which counts once (two promotions of the same source and rung need two commits)",
      });
      continue;
    }
    seenLines.add(line);
    if (!atColumn0) {
      notCounted.push({ ...entry, why: placement(line) });
      continue;
    }
    const m = RECORD.exec(line);
    if (!m) {
      notCounted.push({ ...entry, why: RECORD_PREFIX.test(line) ? "other text on the line" : "malformed: does not match the record grammar" });
      continue;
    }
    const [, source, named, kind] = m;
    const rung = ladder.aliases.get(named) ?? named;
    if (ladder.notCounted.has(rung)) {
      notCounted.push({ ...entry, why: `rung=${rung} is a guidance or human-review rung, which is not counted` });
      continue;
    }
    if (!ladder.counted.has(rung)) {
      notCounted.push({ ...entry, why: `rung=${named} is not a rung id in the enforcement ladder` });
      continue;
    }
    if (rung === "make-impossible" && kind !== "blocking") {
      notCounted.push({ ...entry, why: "a make-impossible record is blocking" });
      continue;
    }
    if (!effective(c)) {
      reverted.push({ ...entry, rung, kind });
      continue;
    }
    if (rung !== named) aliased.push({ ...entry, named, rung });
    records.push({ ...entry, source, rung, kind });
  }
}

// Events: each record adds a check; a promotion moves one from advisory to blocking. An advisory
// record is known by the pull request that landed it and its rung; a blocking record promotes it by
// naming that pull request as its source.
// A reverted advisory record cannot be promoted: the blocking record naming it stands as a new
// blocking check and is listed with the advisory record it would have promoted.
const advisoryKey = (r) => {
  const landedIn = PR_SUFFIX.exec(r.commit.subject)?.[1];
  return landedIn ? `#${landedIn} ${r.rung}` : undefined;
};
const queue = (map, key, r) => map.set(key, [...(map.get(key) ?? []), r]);
const openAdvisory = new Map();
const revertedAdvisory = new Map();
for (const r of reverted) {
  const key = r.kind === "advisory" ? advisoryKey(r) : undefined;
  if (key) queue(revertedAdvisory, key, r);
}
const events = [];
const promotions = [];
const originReverted = [];
for (const r of records) {
  if (r.kind === "advisory") {
    const key = advisoryKey(r);
    if (key) queue(openAdvisory, key, r);
    events.push({ day: r.commit.day, blocking: 0, advisory: 1, rung: r.rung, rungDelta: 1 });
    continue;
  }
  const key = `${r.source} ${r.rung}`;
  const earlier = r.source === "session" ? undefined : openAdvisory.get(key);
  if (earlier?.length) {
    promotions.push({ ...r, from: earlier.shift() });
    events.push({ day: r.commit.day, blocking: 1, advisory: -1, rung: r.rung, rungDelta: 0 });
    continue;
  }
  const gone = r.source === "session" ? undefined : revertedAdvisory.get(key);
  const goneIndex = gone?.findIndex((a) => a.commit.index < r.commit.index) ?? -1;
  if (goneIndex >= 0) originReverted.push({ ...r, from: gone.splice(goneIndex, 1)[0] });
  events.push({ day: r.commit.day, blocking: 1, advisory: 0, rung: r.rung, rungDelta: 1 });
}

// With no --since the window opens at the first record line in history: a counted or reverted
// record, or a line not counted that looks like an attempted record.
const firstDay = [...records, ...reverted, ...notCounted.filter((e) => recordLike(e.line))].map((e) => e.commit.day).sort()[0];
let since = opts.since ?? firstDay ?? until;
if (since > until) since = until;

const addDays = (day, n) => new Date(Date.parse(`${day}T00:00:00Z`) + n * 86400000).toISOString().slice(0, 10);
/** The first day of the period holding `day`: the month's first, or the ISO week's Monday. */
function periodStart(day) {
  if (bucket === "month") return `${day.slice(0, 7)}-01`;
  const weekday = new Date(`${day}T00:00:00Z`).getUTCDay();
  return addDays(day, -((weekday + 6) % 7));
}
function nextPeriod(start) {
  if (bucket === "week") return addDays(start, 7);
  const [y, m] = start.split("-").map(Number);
  return new Date(Date.UTC(y, m, 1)).toISOString().slice(0, 10);
}
const label = (start) => (bucket === "month" ? start.slice(0, 7) : `week of ${start}`);

const inWindow = (day) => day >= since && day <= until;
const windowEvents = events.filter((e) => inWindow(e.day));
const rungs = ladder.order.filter((id) => windowEvents.some((e) => e.rung === id && e.rungDelta !== 0));
const sum = (list, pick) => list.reduce((n, e) => n + pick(e), 0);
const cumulative = (lastDay) => {
  const upTo = events.filter((e) => e.day <= lastDay);
  return [sum(upTo, (e) => e.blocking), sum(upTo, (e) => e.advisory)];
};
const row = (name, list, lastDay) => {
  const [cumBlocking, cumAdvisory] = cumulative(lastDay);
  const perRung = rungs.map((id) => sum(list.filter((e) => e.rung === id), (e) => e.rungDelta));
  return `| ${name} | ${sum(list, (e) => e.blocking)} | ${sum(list, (e) => e.advisory)} | ${cumBlocking} | ${cumAdvisory} | ${perRung.map((n) => `${n} |`).join(" ")}`.trimEnd();
};

const short = (c) => c.sha.slice(0, 12);
const out = [];
const [allBlocking, allAdvisory] = cumulative(until);
out.push(`Codifies: records on ${ref.replace(/^refs\/(?:heads|remotes)\//, "")}, from git history only`);
out.push(`window: ${since} to ${until}, bucket: ${bucket}`);
out.push(`blocking checks: ${sum(windowEvents, (e) => e.blocking)} new in the window, ${allBlocking} cumulative; advisory: ${sum(windowEvents, (e) => e.advisory)} new, ${allAdvisory} cumulative`);
out.push("new is the net change in the period: a promotion adds one blocking check and removes one advisory check");
if (unscopedReverts > 0) {
  out.push(`no owner/repo read from an origin remote URL: ${unscopedReverts} "Reverts <owner>/<repo>#<n>" line(s) matched by number alone`);
}
out.push("");
out.push(`| period | blocking | advisory | cumulative blocking | cumulative advisory | ${rungs.map((id) => `${id} |`).join(" ")}`.trimEnd());
out.push(`|---|---|---|---|---|${rungs.map(() => "---|").join("")}`);
for (let start = periodStart(since); start <= until; start = nextPeriod(start)) {
  const end = addDays(nextPeriod(start), -1);
  const lastDay = end < until ? end : until;
  out.push(row(label(start), windowEvents.filter((e) => e.day >= start && e.day <= end), lastDay));
}
out.push(row("window", windowEvents, until));

const listed = (title, list, describe) => {
  const shown = list.filter((e) => inWindow(e.commit.day));
  out.push("", `${title}: ${shown.length}`);
  for (const e of shown) out.push(`  ${short(e.commit)} ${e.commit.day} ${describe(e)}`);
};
listed("promoted from advisory to blocking", promotions, (e) => `${e.source} rung=${e.rung}, advisory in ${short(e.from.commit)}`);
listed(
  "blocking, its advisory origin reverted, counted as a new blocking check",
  originReverted,
  (e) => `${e.source} rung=${e.rung}, advisory in ${short(e.from.commit)} reverted by ${short(e.from.commit.revertedBy)}`,
);
listed("read through an alias", aliased, (e) => `rung=${e.named} read as rung=${e.rung}`);
listed("reverted, not counted", reverted, (e) => `${show(e.line)} reverted by ${short(e.commit.revertedBy)}`);
listed("not counted", notCounted, (e) => `${e.why}: ${show(e.line)}`);
process.stdout.write(`${out.join("\n")}\n`);
