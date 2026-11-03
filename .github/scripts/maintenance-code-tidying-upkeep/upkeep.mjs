// Code-tidying upkeep, no model. Two commands:
//
//   detect --before <sha> --after <sha> [--root <dir>]
//     Per merge: names the areas a pushed range changed, on stdout and in the
//     job summary. Opens nothing.
//   gate [--root <dir>]
//     Prints the batch as JSON: whether it may run and which areas to sweep,
//     with `/code-tidying:tidy <glob>` opening one PR per area on the
//     chore/tidy-adhoc-<slug>-YYYY-MM-DD branch that skill names. Exit 1 when
//     a read fails: nothing is planned on a count it could not read.
//
// The gate derives churn from git log, so a push run GitHub lost drops no area
// (dependabot-fragments.yml records that those happen).
import { execFileSync } from "node:child_process";
import { appendFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const TIDY_SCRIPTS = join(HERE, "../../../plugins/code-tidying/skills/tidy/scripts");
const DAY_MS = 86_400_000;
const WINDOW_DAYS = { daily: 1, weekly: 7, monthly: 30 };
const PULL_PAGE_CAP = 100;
const SAFE_AREA = /^[A-Za-z0-9_][A-Za-z0-9._-]*(\/[A-Za-z0-9._-]+)?$/;
const ADHOC_BRANCH = /^chore\/tidy-adhoc-(.+)-\d{4}-\d{2}-\d{2}$/;
const PULL_FIELDS = "[.[] | {headRefName: .head.ref, createdAt: .created_at, state: (.state | ascii_upcase)}]";

const dayOf = (ms) => Math.floor(ms / DAY_MS);

// A path's area: plugins/<name>, docs/<dir>, else the first segment. A path under
// a dot directory is left out: tidy's HARD list covers agent and CI config. A
// file directly under plugins/ or docs/, or at the root, has no subtree of its
// own, so its glob stops at that level.
export function areaOf(path) {
  const parts = path.split("/");
  if (parts[0].startsWith(".")) return null;
  let found;
  if (parts.length === 1) {
    found = { area: "root", glob: "*" };
  } else if ((parts[0] === "plugins" || parts[0] === "docs") && parts.length > 2) {
    const area = `${parts[0]}/${parts[1]}`;
    found = { area, glob: `${area}/**` };
  } else if (parts[0] === "plugins" || parts[0] === "docs") {
    found = { area: parts[0], glob: `${parts[0]}/*` };
  } else {
    found = { area: parts[0], glob: `${parts[0]}/**` };
  }
  return SAFE_AREA.test(found.area) ? found : null;
}

// The <slug> tidy's ad hoc branch carries: the glob's literal directory prefix in kebab case.
export const slugOf = (area) => area.toLowerCase().replace(/[^a-z0-9]+/g, "-");

export function detectAreas(paths) {
  const names = paths.map((path) => areaOf(path)?.area).filter(Boolean);
  return [...new Set(names)].sort();
}

// pulls: { headRefName, createdAt, state }. Slug to the newest sweep's time, and the slugs with one open.
function sweepsOf(pulls) {
  const last = new Map();
  const open = new Set();
  for (const pull of pulls) {
    const slug = ADHOC_BRANCH.exec(pull.headRefName)?.[1];
    if (!slug) continue;
    last.set(slug, Math.max(last.get(slug) ?? 0, Date.parse(pull.createdAt)));
    if (pull.state === "OPEN") open.add(slug);
  }
  return { last, open };
}

// Pulls newest first until one is older than the window, so a busy repository
// costs one call per hundred pull requests in the window. truncated: the page
// cap came first, so an older sweep may be missing.
export function readPulls(fetchPage, windowStart) {
  const pulls = [];
  for (let page = 1; page <= PULL_PAGE_CAP; page += 1) {
    const rows = fetchPage(page);
    pulls.push(...rows);
    if (rows.length === 0 || Date.parse(rows.at(-1).createdAt) < windowStart) return { pulls, truncated: false };
  }
  return { pulls, truncated: true };
}

// paths: every tracked file. commits: { at (ms), paths } and pulls: the same
// lookback, plus every open pull request. Only an area with a commit after its
// last sweep is eligible. It is overdue once that oldest unswept commit is past
// the backstop window; overdue areas go first, then the oldest unswept.
export function plan({ paths, commits, pulls, truncated, cadence, backstop, limit, open, throttled, now }) {
  const stop = (reason) => ({ proceed: false, reason, areas: [] });
  const windowDays = WINDOW_DAYS[backstop];
  if (truncated) return stop("sweep-history-truncated");

  const { last, open: openSlugs } = sweepsOf(pulls);
  const newest = Math.max(0, ...last.values());
  if (newest > 0 && dayOf(now) - dayOf(newest) < WINDOW_DAYS[cadence]) return stop("cadence");
  const slots = Math.max(0, limit - open);
  if (throttled || slots === 0) return stop("cap");

  const rows = new Map();
  for (const path of paths) {
    const found = areaOf(path);
    if (!found || rows.has(found.area)) continue;
    const slug = slugOf(found.area);
    const swept = last.get(slug) ?? 0;
    rows.set(found.area, { ...found, slug, swept, unswept: Infinity });
  }
  for (const commit of commits) {
    for (const path of commit.paths) {
      const row = rows.get(areaOf(path)?.area);
      if (row && commit.at > row.swept) row.unswept = Math.min(row.unswept, commit.at);
    }
  }

  const overdue = (row) => dayOf(now) - dayOf(row.unswept) >= windowDays;
  const eligible = [...rows.values()].filter((row) => row.unswept !== Infinity && !openSlugs.has(row.slug));
  eligible.sort((a, b) => Number(overdue(b)) - Number(overdue(a)) || a.unswept - b.unswept || a.area.localeCompare(b.area));
  const areas = eligible.slice(0, slots).map((row) => ({ area: row.area, glob: row.glob, slug: row.slug, overdue: overdue(row) }));
  return { proceed: areas.length > 0, reason: areas.length > 0 ? "due" : "nothing-due", areas };
}

export function parseCount(text) {
  const open = /^Open tidy PR count: (\d+)( or more)?$/m.exec(text);
  const limit = /^Throttle limit: (\d+),/m.exec(text);
  const active = /^Throttle active: (yes|no)$/m.exec(text);
  if (!open || !limit || !active) throw new Error("the open tidy PR count is unknown");
  return { open: Number(open[1]), limit: Number(limit[1]), throttled: active[1] === "yes" };
}

// `\0<unix seconds>` before each commit's paths.
export function parseLog(text) {
  return text
    .split("\0")
    .slice(1)
    .map((chunk) => {
      const [at, ...paths] = chunk.split("\n").filter(Boolean);
      return { at: Number(at) * 1000, paths };
    });
}

function run(root, file, args, env = {}) {
  return execFileSync(file, args, {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 512 * 1024 * 1024,
    env: { ...process.env, CLAUDE_PROJECT_DIR: root, ...env },
    stdio: ["ignore", "pipe", "pipe"],
  });
}

function setting(root, key) {
  const [value, source] = run(root, "bash", [join(TIDY_SCRIPTS, "upkeep-setting.sh"), key]).trimEnd().split("\t");
  return { value, source };
}

function gate(root, now) {
  const cadence = setting(root, "upkeep_cadence");
  const backstop = setting(root, "upkeep_backstop");
  const count = parseCount(run(root, "bash", [join(TIDY_SCRIPTS, "open-pr-count.sh")]));
  const windowStart = now - 2 * WINDOW_DAYS[backstop.value] * DAY_MS;
  const { pulls: recent, truncated } = readPulls(
    (page) => JSON.parse(run(root, "gh", ["api", `repos/{owner}/{repo}/pulls?state=all&sort=created&direction=desc&per_page=100&page=${page}`, "--jq", PULL_FIELDS])),
    windowStart,
  );
  const openPulls = JSON.parse(run(root, "gh", ["pr", "list", "--state", "open", "--limit", "1000", "--json", "headRefName,createdAt,state"]));
  const since = new Date(windowStart).toISOString();
  const commits = parseLog(run(root, "git", ["log", `--since=${since}`, "--no-renames", "--name-only", "--format=%x00%ct"]));
  const paths = run(root, "git", ["ls-files"]).split("\n").filter(Boolean);
  const result = plan({ paths, commits, pulls: [...recent, ...openPulls], truncated, cadence: cadence.value, backstop: backstop.value, ...count, now });
  return { ...result, settings: { upkeep_cadence: cadence, upkeep_backstop: backstop, upkeep_max_open: count.limit }, open: count.open };
}

function detect(root, before, after) {
  const sha = /^[0-9a-f]{40}$/;
  if (!sha.test(before) || !sha.test(after) || /^0+$/.test(before)) {
    console.log("::warning::the pushed range has no readable start; the daily gate's git log still covers it");
    return;
  }
  let changed;
  try {
    changed = run(root, "git", ["diff", "--name-only", "--no-renames", before, after]);
  } catch {
    console.log("::warning::the pushed range did not diff; the daily gate's git log still covers it");
    return;
  }
  const areas = detectAreas(changed.split("\n").filter(Boolean));
  console.log(areas.join("\n"));
  if (process.env.GITHUB_STEP_SUMMARY) {
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, `Upkeep areas changed: ${areas.join(", ") || "none"}\n`);
  }
}

function option(args, name, fallback) {
  const at = args.indexOf(name);
  return at === -1 ? fallback : args[at + 1];
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [command, ...args] = process.argv.slice(2);
  const root = option(args, "--root", process.cwd());
  if (command === "detect") {
    detect(root, option(args, "--before", ""), option(args, "--after", ""));
  } else if (command === "gate") {
    try {
      console.log(JSON.stringify(gate(root, Date.now()), null, 2));
    } catch (error) {
      console.error(`upkeep gate: ${error.message.split("\n")[0]}`);
      process.exit(1);
    }
  } else {
    console.error("usage: upkeep.mjs detect --before <sha> --after <sha> [--root <dir>] | gate [--root <dir>]");
    process.exit(2);
  }
}
