#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "../lib/yaml-subset.mjs";

const PLUGIN = join(dirname(fileURLToPath(import.meta.url)), "..");
const APPLY = join(PLUGIN, "skills", "setup", "scripts", "setup-apply.mjs");
const VERDICTS = ["fail", "note"];
const REPOSITORY_FILE = "docs/conventions/review.yaml";
const RECORD_KEY = "loosened_check_decision_record";
const RECORD_PATTERN = new RegExp(
  JSON.parse(readFileSync(join(PLUGIN, "schemas", "review.schema.json"), "utf8")).properties[RECORD_KEY].pattern,
  "u",
);
const UNREADABLE_CITATION = "no spec can allow a loosening on this run";

function usage(message) {
  process.stderr.write(`loosened-check-settings: ${message}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const opts = { root: null, ref: null, verdict: null, patterns: null };
  const names = { "--root": "root", "--ref": "ref", "--verdict-option": "verdict", "--patterns-file": "patternsFile", "--spec-issue": "specIssue" };
  for (let i = 0; i < argv.length; i++) {
    const name = names[argv[i]];
    if (!name) usage(`unknown argument ${JSON.stringify(argv[i])}`);
    if (i + 1 >= argv.length) usage(`${argv[i]} needs a value`);
    opts[name] = argv[++i];
  }
  if (opts.patternsFile !== undefined) {
    try {
      opts.patterns = readFileSync(opts.patternsFile, "utf8").trim();
    } catch (err) {
      usage(`--patterns-file ${JSON.stringify(opts.patternsFile)} could not be read: ${err.code ?? err.message}`);
    }
  }
  if (opts.specIssue !== undefined && !/^[1-9][0-9]{0,9}$/.test(opts.specIssue)) usage("--spec-issue needs an issue number");
  return opts;
}

const TRUSTED_ACTORS = ".github/standards/trusted-actors/trusted-actors.json";
const SOURCE_CONTROL = "docs/conventions/source-control.yaml";
const SOURCES = ["repository", "standards"];
const REPOSITORY = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const STANDARDS_LIST = "components/trusted-actors/trusted-actors.json";
const ACTOR_KEYS = "id,kind,login";
const isObject = (v) => typeof v === "object" && v !== null && !Array.isArray(v);

const MEMBER_ASSOCIATIONS = ["OWNER", "MEMBER", "COLLABORATOR"];

const BRANCH_NAME = /^[A-Za-z0-9._/-]+$/;

/**
 * The remote's default branch as `origin/<name>`, resolved here and never taken from the caller:
 * the local refs/remotes/origin/HEAD, else the default branch gh reports for the repository. Throws when neither resolves.
 */
function defaultBranch(git, root) {
  const local = git("symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD");
  const localName = local.status === 0 ? local.stdout.trim() : "";
  if (localName.startsWith("origin/") && BRANCH_NAME.test(localName)) return localName;
  const remote = spawnSync("gh", ["api", "repos/{owner}/{repo}", "--jq", ".default_branch"], { cwd: root, encoding: "utf8", timeout: 30000 });
  const name = remote.status === 0 ? remote.stdout.trim() : "";
  if (name && BRANCH_NAME.test(name)) return `origin/${name}`;
  throw new Error("the default branch could not be resolved");
}

/**
 * The trusted-actor list the standards repository holds at its main commit, resolved once, as
 * [where, text]. Read only for a repository whose source-control.yaml sets
 * trusted_actors_source: standards and names that repository in standards_repository.
 */
function standardsList(root, standards) {
  const api = (...args) => spawnSync("gh", ["api", ...args], { cwd: root, encoding: "utf8", timeout: 30000 });
  const main = api(`repos/${standards}/commits/main`, "--jq", ".sha");
  const sha = main.status === 0 ? main.stdout.trim() : "";
  if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error(`${standards} main could not be resolved`);
  const read = api("-H", "Accept: application/vnd.github.raw", `repos/${standards}/contents/${STANDARDS_LIST}?ref=${sha}`);
  if (read.status !== 0) throw new Error(`${STANDARDS_LIST} is not readable at ${standards}@${sha}`);
  return [`${standards}@${sha}`, read.stdout];
}

/**
 * The human ids of the trusted-actor list on the default branch, schema-checked as loadTrustedList
 * does; null when the default branch has no list; throws on any other failure, and when --ref names
 * another commit, so a run pointed at a head branch never reads a list that branch edited. The list
 * comes from the standards repository instead when the default branch's source-control.yaml opts in.
 */
function trustedHumans(opts, root) {
  const git = (...args) => spawnSync("git", ["-C", root, ...args], { encoding: "utf8" });
  const ref = defaultBranch(git, root);
  const commit = (name) => {
    const parsed = git("rev-parse", "--verify", "--quiet", `${name}^{commit}`);
    if (parsed.status !== 0) throw new Error(`${name} is not readable`);
    return parsed.stdout.trim();
  };
  const head = commit(ref);
  if (opts.ref !== null) {
    if (!/^(origin\/[A-Za-z0-9._/-]+|[0-9a-f]{40})$/.test(opts.ref)) throw new Error(`--ref ${opts.ref} names no branch or commit`);
    if (commit(opts.ref) !== head) throw new Error(`--ref ${opts.ref} is not the default branch ${ref}, so its trusted-actor list is not read`);
  }
  let source = "repository";
  let standards;
  if (git("cat-file", "-e", `${head}:${SOURCE_CONTROL}`).status === 0) {
    const conf = git("show", `${head}:${SOURCE_CONTROL}`);
    if (conf.status !== 0) throw new Error(`${SOURCE_CONTROL} is not readable at ${ref}`);
    const settings = parse(conf.stdout);
    source = settings?.trusted_actors_source ?? "repository";
    standards = settings?.standards_repository;
    if (!SOURCES.includes(source)) throw new Error(`${SOURCE_CONTROL} at ${ref}: trusted_actors_source ${JSON.stringify(source)} is not one of ${SOURCES.join(", ")}`);
    if (source === "standards" && !(typeof standards === "string" && REPOSITORY.test(standards))) {
      throw new Error(`${SOURCE_CONTROL} at ${ref}: trusted_actors_source standards needs standards_repository as <owner>/<repo>`);
    }
  }
  let where = ref;
  let text;
  if (source === "standards") [where, text] = standardsList(root, standards);
  else {
    if (git("cat-file", "-e", `${head}:${TRUSTED_ACTORS}`).status !== 0) return { ref, humans: null };
    const shown = git("show", `${head}:${TRUSTED_ACTORS}`);
    if (shown.status !== 0) throw new Error(`${TRUSTED_ACTORS} is not readable at ${ref}`);
    text = shown.stdout;
  }
  const list = JSON.parse(text);
  if (!isObject(list) || Object.keys(list).sort().join() !== "actors,version" || list.version !== 1 || !Array.isArray(list.actors)) {
    throw new Error(`the trusted-actor list at ${where} does not match its schema`);
  }
  const humans = new Set();
  for (const a of list.actors) {
    if (!isObject(a) || Object.keys(a).sort().join() !== ACTOR_KEYS || !Number.isInteger(a.id) || a.id < 1 || typeof a.login !== "string" || !["human", "bot"].includes(a.kind)) {
      throw new Error(`the trusted-actor list at ${where} has an entry that does not match its schema`);
    }
    if (a.kind === "human") humans.add(a.id);
  }
  return { ref: where, humans };
}

/** Whether the spec issue's text may give a loosening its reason: [counts, why]. */
function specTrust(opts) {
  if (opts.specIssue === undefined) return [false, "no --spec-issue names the issue"];
  const root = resolve(opts.root ?? process.cwd());
  try {
    const { ref, humans } = trustedHumans(opts, root);
    const read = spawnSync("gh", ["api", `repos/{owner}/{repo}/issues/${opts.specIssue}`], { cwd: root, encoding: "utf8" });
    if (read.status !== 0) throw new Error(`issue #${opts.specIssue}'s author could not be read`);
    const issue = JSON.parse(read.stdout);
    const user = issue?.user;
    if (!isObject(user) || !Number.isInteger(user.id)) throw new Error(`issue #${opts.specIssue} names no author`);
    const who = `issue #${opts.specIssue} by ${user.login}, id ${user.id}`;
    if (humans === null) {
      const assoc = typeof issue.author_association === "string" ? issue.author_association : "unread";
      const rule = `author_association ${assoc}, no trusted-actor list at ${ref}`;
      const counts = user.type === "User" && MEMBER_ASSOCIATIONS.includes(assoc);
      return [counts, `${who}, ${user.type === "User" ? "" : `type ${user.type}, `}${rule}`];
    }
    if (user.type === "User" && humans.has(user.id)) return [true, `${who}, a trusted person at ${ref}`];
    return [false, `${who}, not a trusted person at ${ref}`];
  } catch (err) {
    return [false, err instanceof SyntaxError ? "a reply could not be parsed" : err.message];
  }
}

const unset = (raw) => raw === null || raw === "" || raw.startsWith("${user_config.");
const isPatternList = (v) => Array.isArray(v) && v.every((p) => typeof p === "string" && p.length > 0);

/** The user layer: {verdict, patterns} with undefined for unset, and the notes for invalid values. */
function userLayer(opts, notes) {
  const layer = {};
  if (!unset(opts.verdict)) {
    if (VERDICTS.includes(opts.verdict)) layer.verdict = opts.verdict;
    else notes.push(`WARN userConfig loosened_check_verdict=${JSON.stringify(opts.verdict)} is not one of ${VERDICTS.join(", ")}; layer dropped for this key`);
  }
  if (!unset(opts.patterns)) {
    let value;
    try {
      value = JSON.parse(opts.patterns);
    } catch {
      value = undefined;
    }
    if (isPatternList(value)) layer.patterns = value;
    else notes.push("WARN userConfig loosened_check_patterns is not a JSON list of non-empty strings; layer dropped for this key");
  }
  return layer;
}

/** The repository layer as committed at opts.ref: {verdict, patterns} for each key that passed the schema check. */
function repositoryLayer(opts, notes) {
  if (opts.ref === null) {
    notes.push("INFO repository layer skipped: no --ref names the default branch");
    notes.push(`WARN ${RECORD_KEY} resolves unreadable: no --ref names the default branch, so ${UNREADABLE_CITATION}`);
    return { record: { value: "unreadable", from: "no --ref names the default branch" } };
  }
  const args = [APPLY, "--check", "--ref", opts.ref, ...(opts.root ? ["--root", opts.root] : [])];
  const check = spawnSync(process.execPath, args, { encoding: "utf8" });
  const unreadable = (why) => {
    notes.push(`WARN ${opts.ref} could not be read (${why}): verdict resolves fail, the safe floor, only the user's patterns apply, and ${UNREADABLE_CITATION}`);
    return { verdict: "fail", unreadable: true, record: { value: "unreadable", from: "unreadable default branch" } };
  };
  if (check.status === 2 || check.status === null) return unreadable((check.stderr || "").trim() || `exit ${check.status}`);
  const out = check.stdout;
  for (const line of out.split("\n")) if (line.startsWith("WARN ")) notes.push(line);
  const read = out.match(/^INFO read (\S+) at \S+, commit ([0-9a-f]{40})$/m);
  if (!read) return unreadable((check.stderr || "").trim() || `the settings file could not be read, exit ${check.status}`);
  if (/^INFO \S+: absent;/m.test(out)) {
    notes.push(`INFO ${read[1]} is absent at ${opts.ref}, commit ${read[2]}`);
    return {};
  }
  notes.push(`INFO read ${read[1]} at ${opts.ref}, commit ${read[2]}`);
  const passed = (key) => new RegExp(`^PASS ${key}: (?!\\(unset\\)$)`, "m").test(out);
  const layer = {};
  const verdict = out.match(/^PASS loosened_check_verdict: (fail|note)$/m);
  if (verdict) layer.verdict = verdict[1];
  const committed = (key) => {
    const root = resolve(opts.root ?? process.cwd());
    const shown = spawnSync("git", ["-C", root, "show", `${read[2]}:${read[1]}`], { cwd: PLUGIN, encoding: "utf8" });
    try {
      return shown.status === 0 ? parse(shown.stdout)?.[key] : undefined;
    } catch {
      return undefined;
    }
  };
  if (passed("loosened_check_patterns")) {
    const value = committed("loosened_check_patterns");
    if (isPatternList(value)) layer.patterns = value;
    else notes.push(`WARN ${read[1]} at ${read[2]}: loosened_check_patterns could not be read as a list; layer dropped for this key`);
  }
  if (!/^PASS /m.test(out)) {
    notes.push(`WARN ${read[1]} at ${read[2]} could not be parsed: ${RECORD_KEY} resolves unreadable, so ${UNREADABLE_CITATION}`);
    layer.record = { value: "unreadable", from: `${read[1]} could not be parsed` };
  } else if (!new RegExp(`^PASS ${RECORD_KEY}: `, "m").test(out)) {
    notes.push(`WARN ${read[1]} at ${read[2]}: ${RECORD_KEY} is invalid; it resolves unreadable, so ${UNREADABLE_CITATION}`);
    layer.record = { value: "unreadable", from: `invalid value in ${read[1]}` };
  } else if (passed(RECORD_KEY)) {
    const value = committed(RECORD_KEY);
    if (typeof value === "string" && RECORD_PATTERN.test(value)) layer.record = { value, from: read[1] };
    else {
      notes.push(`WARN ${read[1]} at ${read[2]}: ${RECORD_KEY} could not be read; it resolves unreadable, so ${UNREADABLE_CITATION}`);
      layer.record = { value: "unreadable", from: `${read[1]} could not be read` };
    }
  }
  return layer;
}

/** Resolve both keys over the named layers ([name, {verdict, patterns}] in order). */
export function resolveLoosenedCheck(layers) {
  const setVerdict = layers.filter(([, l]) => l.verdict !== undefined);
  const failing = setVerdict.filter(([, l]) => l.verdict === "fail");
  const verdict = setVerdict.length === 0 || failing.length > 0 ? "fail" : "note";
  const verdictFrom = setVerdict.length === 0 ? ["default"] : (failing.length ? failing : setVerdict).map(([n]) => n);
  const patterns = [];
  const patternsFrom = [];
  for (const [name, l] of layers) {
    if (!l.patterns) continue;
    let added = false;
    for (const p of l.patterns) {
      if (!patterns.includes(p)) {
        patterns.push(p);
        added = true;
      }
    }
    if (added) patternsFrom.push(name);
  }
  return { verdict, verdictFrom, patterns, patternsFrom: patternsFrom.length ? patternsFrom : ["default"] };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const opts = parseArgs(process.argv.slice(2));
  const notes = [];
  const user = userLayer(opts, notes);
  const repo = repositoryLayer(opts, notes);
  const layers = [
    ["userConfig", user],
    [repo.unreadable ? "unreadable default branch" : REPOSITORY_FILE, repo],
  ];
  const r = resolveLoosenedCheck(layers);
  const record = repo.record ?? { value: "unset", from: "default" };
  const [counts, why] = specTrust(opts);
  process.stdout.write(
    `loosened_check_verdict: ${r.verdict} (${r.verdictFrom.join(", ")})\n` +
      `loosened_check_patterns: ${JSON.stringify(r.patterns)} (${r.patternsFrom.join(", ")})\n` +
      `${RECORD_KEY}: ${record.value} (${record.from})\n` +
      `loosened_check_spec: ${counts ? "counts" : "no reason"} (${why})\n` +
      notes.map((n) => `${n}\n`).join(""),
  );
}
