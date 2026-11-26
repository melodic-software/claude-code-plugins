import { execFileSync } from "node:child_process";
import { appendFileSync, existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const TIDY_SCRIPTS = join(HERE, "../../../plugins/code-tidying/skills/tidy/scripts");
const API_BUDGET = join(HERE, "../../actions/log-api-budget/api-budget.bash");
const DAY_MS = 86_400_000;
const WINDOW_DAYS = { daily: 1, weekly: 7, monthly: 30 };
const PULL_LIST_LIMIT = 1000;
const NEVER_SWEPT_DAYS = 90;
export const SWEEP_ARTIFACT = "tidy-code-upkeep-sweeps";
const SAFE_AREA = /^[A-Za-z0-9_][A-Za-z0-9._-]*(\/[A-Za-z0-9._-]+)?$/;
const ADHOC_BRANCH = /^chore\/tidy-adhoc-(.+)-\d{4}-\d{2}-\d{2}$/;

const dayOf = (ms) => Math.floor(ms / DAY_MS);

export function areaOf(path) {
  const parts = path.split("/");
  if (parts[0].startsWith(".")) return null;
  if (parts.length === 1) return { area: "root", glob: "*" };
  const nested = parts[0] === "plugins" || parts[0] === "docs";
  const area = nested && parts.length > 2 ? `${parts[0]}/${parts[1]}` : parts[0];
  const glob = nested && parts.length === 2 ? `${area}/*` : `${area}/**`;
  return SAFE_AREA.test(area) ? { area, glob } : null;
}

export const slugOf = (area) => area.toLowerCase().replace(/[^a-z0-9]+/g, "-");

export function detectAreas(paths) {
  const names = paths.map((path) => areaOf(path)?.area).filter(Boolean);
  return [...new Set(names)].sort();
}

function sweepsOf(pulls) {
  const last = new Map();
  const open = new Set();
  const merges = new Set();
  for (const pull of pulls) {
    const slug = ADHOC_BRANCH.exec(pull.headRefName)?.[1];
    if (!slug) continue;
    last.set(slug, Math.max(last.get(slug) ?? 0, Date.parse(pull.createdAt)));
    if (pull.state === "OPEN") open.add(slug);
    if (pull.mergeCommit?.oid) merges.add(pull.mergeCommit.oid);
  }
  return { last, open, merges };
}

export function lookbackStart(pulls, now) {
  const sweeps = pulls.filter((pull) => ADHOC_BRANCH.test(pull.headRefName)).map((pull) => Date.parse(pull.createdAt));
  return Math.min(now - NEVER_SWEPT_DAYS * DAY_MS, ...sweeps);
}

export function plan({ paths, commits, pulls, cleanSweeps = [], cadence, backstop, limit, open, throttled, now }) {
  const stop = (reason) => ({ proceed: false, reason, areas: [] });
  const windowDays = WINDOW_DAYS[backstop];

  const { last, open: openSlugs, merges } = sweepsOf(pulls);
  for (const { slug, at } of cleanSweeps) last.set(slug, Math.max(last.get(slug) ?? 0, at));
  const newest = Math.max(0, ...last.values());
  if (newest > 0 && dayOf(now) - dayOf(newest) < WINDOW_DAYS[cadence]) return stop("cadence");
  const slots = Math.max(0, limit - open);
  if (throttled || slots === 0) return stop("cap");

  const rows = new Map();
  for (const path of paths) {
    const found = areaOf(path);
    if (!found || rows.has(found.area)) continue;
    const slug = slugOf(found.area);
    rows.set(found.area, { ...found, slug, swept: last.get(slug) ?? 0, unswept: Infinity });
  }
  for (const commit of commits) {
    if (merges.has(commit.sha)) continue;
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

export function readCleanSweeps(artifacts, read) {
  const sweeps = [];
  for (const artifact of artifacts) {
    const run = artifact.workflow_run;
    if (artifact.expired || run?.head_branch !== "main" || run.head_repository_id !== run.repository_id) continue;
    let record;
    try {
      record = JSON.parse(read(artifact));
    } catch {
      continue;
    }
    if (!Number.isSafeInteger(record?.at) || record.at <= 0 || !Array.isArray(record.slugs ?? [])) continue;
    for (const slug of record.slugs ?? []) {
      if (/^[a-z0-9-]+$/.test(slug)) sweeps.push({ slug, at: record.at * 1000 });
    }
  }
  return sweeps;
}

export function parseCount(text) {
  const open = /^Open tidy PR count: (\d+)( or more)?$/m.exec(text);
  const limit = /^Throttle limit: (\d+),/m.exec(text);
  const active = /^Throttle active: (yes|no)$/m.exec(text);
  if (!open || !limit || !active) throw new Error("the open tidy PR count is unknown");
  return { open: Number(open[1]), limit: Number(limit[1]), throttled: active[1] === "yes" };
}

export function parseLog(text) {
  return text
    .split("\0")
    .slice(1)
    .map((chunk) => {
      const [head, ...paths] = chunk.split("\n").filter(Boolean);
      const [sha, at] = head.split(" ");
      return { sha, at: Number(at) * 1000, paths };
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

export function gh(root, args, env = {}) {
  const token = env.API_BUDGET_TOKEN ?? process.env.API_BUDGET_TOKEN;
  if (!token || !existsSync(API_BUDGET)) return run(root, "gh", args, env);
  return run(root, "bash", ["-c", '. "$1" && api_budget_wrap_gh "$2" && shift 2 && gh "$@"', "gh", API_BUDGET, token, ...args], env);
}

function setting(root, key) {
  const [value, source] = run(root, "bash", [join(TIDY_SCRIPTS, "upkeep-setting.sh"), key]).trimEnd().split("\t");
  return { value, source };
}

function downloadRecord(root, artifact) {
  const dir = mkdtempSync(join(tmpdir(), "upkeep-record-"));
  try {
    gh(root, ["run", "download", String(artifact.workflow_run.id), "--name", SWEEP_ARTIFACT, "--dir", dir]);
    return readFileSync(join(dir, "sweeps.json"), "utf8");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function gate(root, now) {
  const specIssue = setting(root, "upkeep_spec_issue");
  if (!specIssue.value) throw new Error(`upkeep_spec_issue is not set (${specIssue.source}); every upkeep pull request links it as its spec, so the batch opens none`);
  const cadence = setting(root, "upkeep_cadence");
  const backstop = setting(root, "upkeep_backstop");
  const count = parseCount(run(root, "bash", [join(TIDY_SCRIPTS, "open-pr-count.sh")]));
  const sweeps = JSON.parse(gh(root, ["pr", "list", "--state", "all", "--limit", String(PULL_LIST_LIMIT), "--search", "head:chore/tidy-adhoc-", "--json", "headRefName,createdAt,state,mergeCommit"]));
  const openPulls = JSON.parse(gh(root, ["pr", "list", "--state", "open", "--limit", String(PULL_LIST_LIMIT), "--json", "headRefName,createdAt,state"]));
  const records = JSON.parse(gh(root, ["api", `repos/{owner}/{repo}/actions/artifacts?name=${SWEEP_ARTIFACT}&per_page=100`])).artifacts ?? [];
  const cleanSweeps = readCleanSweeps(records, (artifact) => downloadRecord(root, artifact));
  const since = new Date(lookbackStart(sweeps, now)).toISOString();
  const commits = parseLog(run(root, "git", ["log", `--since=${since}`, "--no-renames", "--name-only", "--format=%x00%H %ct"]));
  const paths = run(root, "git", ["ls-files"]).split("\n").filter(Boolean);
  const result = plan({ paths, commits, pulls: [...sweeps, ...openPulls], cleanSweeps, cadence: cadence.value, backstop: backstop.value, ...count, now });
  return { ...result, settings: { upkeep_cadence: cadence, upkeep_backstop: backstop, upkeep_max_open: count.limit, upkeep_spec_issue: specIssue }, open: count.open };
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
      const now = Date.now();
      const result = gate(root, now);
      console.log(JSON.stringify(result, null, 2));
      if (process.env.GITHUB_OUTPUT) {
        const date = new Date(now).toISOString().slice(0, 10);
        appendFileSync(process.env.GITHUB_OUTPUT, `proceed=${result.proceed}\nareas=${JSON.stringify(result.areas)}\ndate=${date}\nspec-issue=${result.settings.upkeep_spec_issue.value}\n`);
      }
    } catch (error) {
      console.error(`upkeep gate: ${error.message.split("\n")[0]}`);
      process.exit(1);
    }
  } else {
    console.error("usage: upkeep.mjs detect --before <sha> --after <sha> [--root <dir>] | gate [--root <dir>]");
    process.exit(2);
  }
}
