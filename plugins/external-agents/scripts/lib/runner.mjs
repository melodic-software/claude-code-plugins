import { execFileSync } from "node:child_process";
import { closeSync, existsSync, openSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { basename, isAbsolute, join, sep, win32 } from "node:path";
import { resolveBinary, unavailableMessage } from "./binary.mjs";
import { blockedBy, closeBreaker, openBreaker, readBreaker } from "./breaker.mjs";
import { binaryNames, conventionHome, loadConfig, pluginRoot } from "./config.mjs";
import { jobFolder, listJobs, newJobId, pruneJobs, readJob, repoKey, writeJob } from "./jobs.mjs";
import { classify } from "./outcome.mjs";
import { killTree, pidStartTime, query, shellUnsafe, start } from "./process.mjs";
import { loadProvider } from "./provider.mjs";

export const EXIT = { ok: 0, failed: 1, usage: 2, blocked: 3, unavailable: 4 };
const USES = ["task", "investigate"];
const MODES = ["read-only", "write"];
const COMMANDS = ["run", "resume", "review"];
const MAX_TIMER_MS = 2_147_483_647;
const LISTED_FILES = 200;
const PLAIN_VALUE = /^[A-Za-z0-9][A-Za-z0-9_.-]*$/;

export class Stop extends Error {
  constructor(kind, reason) {
    super(reason);
    this.kind = kind;
  }
}
export const refuse = (reason) => new Stop("refused", reason);

const git = (cwd, args, options = {}) => {
  try {
    return execFileSync("git", ["-C", cwd, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], windowsHide: true, cwd: pluginRoot, ...options });
  } catch {
    return null;
  }
};

const read = (path) => (path && existsSync(path) ? readFileSync(path, "utf8") : "");
const fill = (list, token, value) => list.map((a) => a.replaceAll(token, () => value ?? ""));
const plural = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;
const withoutQuotesCmdWouldStrip = (arg) => arg.replaceAll('"', "");
const clip = (text) => (text.length > 160 ? `${text.slice(0, 157)}...` : text);

/**
 * The plugin's data directory, worked out from where an installed copy sits. A command run through
 * the Bash tool can carry another plugin's CLAUDE_PLUGIN_DATA, so the install path wins. The
 * directory name follows https://code.claude.com/docs/en/plugins-reference#environment-variables;
 * null for any other layout.
 */
export function installedDataDir(root) {
  const parts = root.split(sep);
  const cache = parts.lastIndexOf("cache");
  if (cache < 1 || parts[cache - 1] !== "plugins" || parts.length !== cache + 4) return null;
  const [marketplace, plugin] = parts.slice(cache + 1);
  return join(parts.slice(0, cache).join(sep), "data", `${plugin}@${marketplace}`.replace(/[^A-Za-z0-9_-]/g, "-"));
}

/** The data directory: the caller's, then the install path's, then CLAUDE_PLUGIN_DATA only when it is named for this plugin. */
export function dataDirFor({ dataDir, env, root = pluginRoot }) {
  if (dataDir) return { dataDir, notice: null };
  const given = env.CLAUDE_PLUGIN_DATA;
  const own = given && /^external-agents-/.test(win32.basename(given));
  const foreign = given && !own ? `CLAUDE_PLUGIN_DATA ${JSON.stringify(given)} belongs to another plugin, so it is not used` : null;
  const installed = installedDataDir(root);
  if (installed) return { dataDir: installed, notice: foreign };
  if (own) return { dataDir: given, notice: null };
  throw refuse(`${foreign ?? "CLAUDE_PLUGIN_DATA is not set"} and this copy is not an installed plugin, so there is nowhere to keep job files`);
}

function context(opts) {
  const env = opts.env ?? process.env;
  const cwd = opts.cwd ?? process.cwd();
  const warn = opts.warn ?? ((line) => process.stderr.write(line));
  const { dataDir, notice } = dataDirFor({ dataDir: opts.dataDir, env });
  if (notice) warn(`notice: ${notice}\n`);
  return {
    cwd, env, dataDir, now: opts.now ?? Date.now, key: repoKey(cwd), binary: opts.binary, writeJob: opts.writeJob ?? writeJob,
    fetch: opts.fetch ?? globalThis.fetch, warn,
  };
}

export function setup(opts) {
  const ctx = context(opts);
  let record;
  try {
    record = loadProvider(opts.product, opts.providersRoot);
  } catch (error) {
    throw refuse(error.message);
  }
  const projectRoot = git(ctx.cwd, ["rev-parse", "--show-toplevel"])?.trim() || ctx.cwd;
  const bound = conventionHome(projectRoot);
  const config = loadConfig({ projectRoot, home: bound.home, userConfig: opts.userConfig });
  if (bound.problem) config.errors.push(`convention home: ${bound.problem}; reading ${bound.home}`);
  return { ctx, record, config, settings: config.values[record.product] ?? {}, notices: config.errors.map((e) => `config: ${e}`), announced: [] };
}

function modeFor(record, settings, use, requested, notices) {
  const ceiling = settings.uses?.[use]?.mode === "write" ? "write" : "read-only";
  if (requested === "write" && ceiling !== "write") {
    notices.push(`write was requested, but ${record.product}.uses.${use}.mode is read-only, so this run is read-only`);
  }
  return requested === "read-only" ? "read-only" : ceiling;
}

function checkAddDirs(dirs) {
  for (const dir of dirs) {
    if (!isAbsolute(dir)) throw refuse(`--add-dir ${JSON.stringify(dir)} is not an absolute path`);
    if (!existsSync(dir) || !statSync(dir).isDirectory()) throw refuse(`--add-dir ${JSON.stringify(dir)} is not an existing directory`);
  }
}

function fenceFor(record, { mode, command, use, requested, addDirs = [], unsandboxed }) {
  const spec = record.modes[mode];
  const asked = [addDirs.length ? "--add-dir" : null, unsandboxed !== undefined ? "--unsandboxed" : null].filter(Boolean);
  if (mode !== "write" && asked.length) {
    const ceiling = requested === "write" ? ` because ${record.product}.uses.${use}.mode is read-only` : "";
    throw refuse(`${asked.join(" and ")} needs a write run, and this run is read-only${ceiling}`);
  }
  if (addDirs.length && !spec.add_dir) throw refuse(`${record.product} takes no --add-dir`);
  if (addDirs.length && !spec.add_dir.commands.includes(command)) throw refuse(`${record.product} takes --add-dir on ${spec.add_dir.commands.join(" and ")} only, and this is a ${command}`);
  if (mode !== "write") return { spec, fence: null };
  if (unsandboxed === undefined) return { spec, fence: "sandbox" };
  const variant = spec.unsandboxed?.[unsandboxed];
  if (!variant) {
    const names = Object.keys(spec.unsandboxed ?? {});
    throw refuse(`${record.product} has no --unsandboxed ${JSON.stringify(unsandboxed)}${names.length ? `; it takes ${names.join(", ")}` : ""}`);
  }
  const { unsandboxed: _variants, fallback_warning: _sandboxed, ...shared } = spec;
  return { spec: { ...shared, ...variant }, fence: `unsandboxed ${unsandboxed}` };
}

function buildArgs(record, binary, p) {
  const spec = p.spec;
  const args = fill(fill(p.baseArgs ?? record[p.command]?.args ?? [], "{thread}", p.thread), "{base}", p.base);
  if (record.output.final_message_arg) args.push(record.output.final_message_arg, p.finalPath);
  args.push(...(spec.args?.[p.command] ?? []), ...(record.always_args ?? []));
  if (spec.settings) args.push(spec.settings_arg, p.settingsPath);
  for (const dir of p.addDirs ?? []) args.push(spec.add_dir.arg, dir);
  if (spec.fallback_warning?.log_arg) args.push(spec.fallback_warning.log_arg, p.cliLogPath);
  if (p.model && record.model_flag) args.push(record.model_flag, p.model);
  if (p.profile && record.profile_flag && (record.profile_on ?? COMMANDS).includes(p.command)) args.push(record.profile_flag, p.profile);
  if (p.effort && record.effort_flag) args.push(record.effort_flag, p.effort);
  else if (p.effort && record.effort_config) args.push(record.config_arg, `${record.effort_config}="${p.effort}"`);
  if (p.dir) args.push(record.review.dir_arg, p.dir);
  if (p.prompt !== null) args.push(...fill([record.prompt.form], "{prompt}", p.prompt));
  return binary.shell ? args.map(withoutQuotesCmdWouldStrip) : args;
}

/** Throws unless every value that reaches argv is safe for the way the binary is started. */
export function guardValues(record, binary, values, promptInArgv) {
  const fix = `set ${record.product}.binary_path in <home>/external-agents.local.yaml to the real executable`;
  if (binary.shell && shellUnsafe(binary.path)) throw refuse(`${JSON.stringify(binary.path)} cannot be started safely through cmd.exe; ${fix}`);
  for (const [name, value] of Object.entries(values)) {
    if (value === undefined || value === null) continue;
    if (value.startsWith("-")) throw refuse(`${name} ${JSON.stringify(value)} starts with "-" and would be read as an option`);
    if (binary.shell && shellUnsafe(value)) {
      throw refuse(`${name} ${JSON.stringify(value)} cannot be passed safely to ${binary.path}, which runs through cmd.exe; ${fix}`);
    }
  }
  if (values.effort && !PLAIN_VALUE.test(values.effort)) throw refuse(`effort ${JSON.stringify(values.effort)} is not a plain word`);
  if (binary.shell && promptInArgv) {
    throw refuse(`${record.product} takes its prompt as an argument, which cannot be passed safely to ${binary.path}, which runs through cmd.exe; ${fix}`);
  }
}

/** The executable to start: `ctx.binary`, else the record's resolution with binary_path checked; `missing` holds what was tried. */
export function pickBinary(ctx, record, settings) {
  if (ctx.binary) return { binary: ctx.binary, missing: null };
  const chosen = settings.binary_path;
  const fileName = chosen && (process.platform === "win32" ? win32.basename(chosen).toLowerCase() : basename(chosen));
  if (chosen && !binaryNames(record.binary.name).includes(fileName)) {
    throw refuse(`${record.product}.binary_path ${JSON.stringify(chosen)} is not named ${record.binary.name}, so it is not run`);
  }
  const found = resolveBinary(record, { binaryPath: chosen, env: ctx.env });
  return found.path ? { binary: { path: found.path, args: [], shell: found.shell }, missing: null } : { binary: null, missing: found };
}

function trip(ctx, record, config, failureClass, reason, resetAt = null) {
  openBreaker(ctx.dataDir, record.product, { failureClass, reason, now: ctx.now(), resetAt, cooldownHours: config.values.breaker?.cooldown_hours ?? 24 });
}

async function launch({ ctx, record, config, settings, notices }, plan) {
  const product = record.product;
  const open = blockedBy(ctx.dataDir, product, ctx.now());
  const breakerOnTrial = open ? null : readBreaker(ctx.dataDir, product);
  if (open) {
    throw new Stop("unavailable", `${open.reason}; not retried until ${open.next_trial_at}. To check sooner, run: external-agents update ${product}`);
  }
  const { binary, missing } = pickBinary(ctx, record, settings);
  if (!binary) {
    trip(ctx, record, config, "binary-missing", `${record.binary.name} not found`);
    throw new Stop("unavailable", unavailableMessage(record, missing).replace(`${product}: unavailable: `, ""));
  }

  const model = plan.model ?? settings.model;
  const effort = plan.effort ?? settings.effort;
  const promptInArgv = record.prompt.form.includes("{prompt}");
  guardValues(record, binary, { model, profile: settings.profile, effort, base: plan.base, thread: plan.thread }, promptInArgv && plan.prompt !== null);

  const login = record.login_status && query(binary, record.login_status.args, { env: ctx.env, cwd: ctx.cwd });
  if (login && login.code === null) throw new Stop("failed", `could not check the login state: ${login.error?.message ?? "the query was stopped"}`);
  if (login && login.code !== 0) {
    trip(ctx, record, config, "not-logged-in", "not logged in");
    throw new Stop("unavailable", `not logged in. Log in with ${record.binary.name}, then run: external-agents update ${product}`);
  }
  if (!model && record.unset_model === "skip-with-notice") throw new Stop("skipped", `no model is configured; set ${product}.model`);

  const id = newJobId(ctx.now());
  const folder = jobFolder(ctx.dataDir, ctx.key, id);
  const paths = { final: join(folder, "final.txt"), log: join(folder, "stdout.log"), stderr: join(folder, "stderr.log"), prompt: join(folder, "prompt.txt"), settings: join(folder, "settings.json"), diff: join(folder, "review.diff"), cliLog: join(folder, "cli.log") };
  const spec = plan.spec ?? record.modes[plan.mode];
  let prompt = plan.prompt;
  if (plan.diffBase) {
    writeFileSync(paths.diff, git(ctx.cwd, ["diff", "--end-of-options", `${plan.diffBase}...HEAD`], { maxBuffer: 256 * 1024 * 1024 }) ?? "");
    prompt = [prompt, `The change to review is the diff file ${paths.diff}. Read that file; its contents are not in this prompt.`].filter(Boolean).join("\n\n");
  }
  if (prompt !== null) prompt = [spec.prompt_preface, prompt].filter(Boolean).join("\n\n");
  if (prompt !== null) writeFileSync(paths.prompt, prompt);
  if (spec.settings) writeFileSync(paths.settings, `${JSON.stringify(spec.settings)}\n`);

  const args = buildArgs(record, binary, {
    command: plan.command, baseArgs: plan.baseArgs, spec, addDirs: plan.addDirs, cliLogPath: paths.cliLog, thread: plan.thread, base: plan.base, model, profile: settings.profile, effort,
    finalPath: paths.final, settingsPath: paths.settings, dir: plan.diffBase ? folder : null, prompt: promptInArgv ? prompt : prompt === null ? null : "",
  });
  if (binary.shell) {
    const bad = [binary.path, ...args].find(shellUnsafe);
    if (bad !== undefined) rmSync(folder, { recursive: true, force: true });
    if (bad !== undefined) throw refuse(`${JSON.stringify(bad)} cannot be passed safely to ${binary.path}, which runs through cmd.exe; set ${product}.binary_path in <home>/external-agents.local.yaml to the real executable`);
  }

  const version = query(binary, record.version.args, { env: ctx.env, cwd: ctx.cwd });
  const timeoutSeconds = settings.timeout_seconds ?? 1800;
  const job = {
    id, product, use: plan.use, mode: plan.mode, fence: plan.fence ?? null, ...(plan.addDirs?.length ? { add_dirs: plan.addDirs } : {}), model: model ?? null, effort: effort ?? null, argv: [binary.path, ...(binary.args ?? []), ...args],
    cli_version: version.code === 0 ? version.stdout.trim().split(/\r?\n/)[0] || null : null,
    cwd: ctx.cwd, started_at: new Date(ctx.now()).toISOString(), ended_at: null, exit_code: null, status: "running", reason: null,
    pid: null, pid_started_at: null, runner_pid: process.pid, runner_started_at: pidStartTime(process.pid), thread_id: plan.thread ?? null, final_message_path: paths.final, log_path: paths.log, stderr_path: paths.stderr, notices,
    ...(plan.scope ? { review_scope: plan.scope } : {}),
  };

  const handles = [openSync(paths.log, "w"), openSync(paths.stderr, "w")];
  if (prompt !== null && !promptInArgv) handles.unshift(openSync(paths.prompt, "r"));
  const stdio = handles.length === 3 ? handles : ["ignore", ...handles];
  let timedOut = false;
  let unrecorded = null;
  const exit = await new Promise((done) => {
    const child = start(binary, args, { cwd: ctx.cwd, env: ctx.env, stdio });
    let timer;
    child.once("error", (error) => {
      clearTimeout(timer);
      done({ code: null, error });
    });
    child.once("spawn", () => {
      job.pid = child.pid;
      job.pid_started_at = pidStartTime(child.pid);
      try {
        ctx.writeJob(ctx.dataDir, ctx.key, job);
      } catch (error) {
        unrecorded = error;
        killTree(child.pid);
        return;
      }
      timer = setTimeout(() => {
        timedOut = true;
        killTree(child.pid);
      }, Math.min(timeoutSeconds * 1000, MAX_TIMER_MS));
    });
    child.once("close", (code) => {
      clearTimeout(timer);
      done({ code, error: null });
    });
  });
  for (const handle of handles) closeSync(handle);
  if (unrecorded) {
    rmSync(folder, { recursive: true, force: true });
    throw new Stop("failed", `could not write the job file (${unrecorded.message}); the CLI was stopped`);
  }

  const stdout = read(paths.log);
  const outcome = exit.error
    ? { status: "failed", reason: `could not start ${binary.path}: ${exit.error.message}`, thread_id: null, message: "", denied_commands: { count: 0, commands: [] }, failed_commands: { count: 0, commands: [] }, mcp_calls: { count: 0, tools: [] }, last_error: exit.error.message, unavailable: null, notices: [] }
    : classify(record, { exitCode: exit.code, stdout, stderr: read(paths.stderr), finalMessage: read(paths.final), mode: plan.mode, spec, cliLog: read(paths.cliLog), now: ctx.now() });
  if (record.output.kind === "json_envelope") writeFileSync(paths.final, outcome.message);

  const cancelledByAnotherProcess = readJob(ctx.dataDir, ctx.key, id)?.status === "cancelled";
  const { unavailable, message, notices: more, ...fields } = outcome;
  Object.assign(job, fields, { thread_id: outcome.thread_id ?? job.thread_id, exit_code: exit.code, ended_at: new Date(ctx.now()).toISOString(), notices: [...notices, ...more] });
  if (cancelledByAnotherProcess) Object.assign(job, { status: "cancelled", reason: "cancelled by request" });
  else if (timedOut) Object.assign(job, { status: "timed-out", reason: `no result after ${timeoutSeconds} s` });
  ctx.writeJob(ctx.dataDir, ctx.key, job);

  if (job.status === "failed" && unavailable) trip(ctx, record, config, unavailable.class, clip(outcome.last_error ?? outcome.reason), unavailable.reset_at);
  else if (breakerOnTrial && ["ok", "blocked-by-mode", "failed"].includes(job.status) && readBreaker(ctx.dataDir, product)?.opened_at === breakerOnTrial.opened_at) closeBreaker(ctx.dataDir, product);
  pruneJobs(ctx.dataDir, ctx.key, config.values.jobs?.keep ?? 50);
  return { job, message };
}

function details(job) {
  const parts = [];
  if (job.denied_commands?.count) parts.push(`${plural(job.denied_commands.count, "command")} blocked by ${job.mode} mode: ${job.denied_commands.commands.map(clip).join("; ")}`);
  if (job.failed_commands?.count) parts.push(plural(job.failed_commands.count, "failed command"));
  if (job.mcp_calls?.count) parts.push(`${plural(job.mcp_calls.count, "MCP call")}: ${job.mcp_calls.tools.join(", ")}`);
  return parts;
}

export const oneLine = (text) => String(text).replace(/\s+/g, " ").trim();
const within = (parts) => (parts.length ? ` (${parts.map(oneLine).join("; ")})` : "");
const runLine = (job) => `${job.product}: ${job.status}${within([job.reason, ...details(job)].filter(Boolean))}`;
const exitFor = (status) => (status === "ok" ? EXIT.ok : status === "blocked-by-mode" ? EXIT.blocked : EXIT.failed);
const body = (message) => (message === "" || message.endsWith("\n") ? message : `${message}\n`);
const noticeLines = (notices, announced = []) => notices.filter((n) => !announced.includes(n)).map((n) => `notice: ${n}\n`).join("");
const errLines = (job, state) => `job: ${job.id}\n${noticeLines(job.notices, state?.announced)}`;

function stopped(name, error, review, state) {
  const product = name ?? "external-agents";
  const stderr = state ? noticeLines(state.notices, state.announced) : "";
  if (!(error instanceof Stop)) {
    return { code: EXIT.failed, stdout: `${product}: failed (${oneLine(error?.message ?? error)})\n`, stderr: `${stderr}${error?.stack ?? error}\n` };
  }
  const code = error.kind === "refused" ? EXIT.usage : error.kind === "failed" ? EXIT.failed : EXIT.unavailable;
  const why = oneLine(error.message);
  if (review) return { code, stdout: `${product}: ${["refused", "failed"].includes(error.kind) ? "failed" : "skipped"} (${why})\n`, stderr };
  const line = ["skipped", "failed"].includes(error.kind) ? `${product}: ${error.kind} (${why})` : `${product}: ${error.kind}: ${why}`;
  return { code, stdout: `${line}\n`, stderr };
}

export async function run(opts) {
  let state = null;
  try {
    if (!USES.includes(opts.use)) throw refuse(`--use takes ${USES.join(" or ")}`);
    if (opts.mode !== undefined && !MODES.includes(opts.mode)) throw refuse(`--mode takes ${MODES.join(" or ")}`);
    if (!opts.prompt?.trim()) throw refuse("no prompt was given");
    const addDirs = opts.addDirs ?? [];
    checkAddDirs(addDirs);
    state = setup(opts);
    const { ctx, record } = state;
    let thread = null;
    if (opts.resume !== undefined || opts.last) {
      if (!record.resume) throw refuse(`${record.product} has no resume form`);
      const mine = listJobs(ctx.dataDir, ctx.key).filter((j) => j.product === record.product && j.thread_id);
      const match = opts.last ? mine[0] : mine.find((j) => j.thread_id === opts.resume);
      if (!match) throw refuse(opts.last ? "no earlier job in this repository has a thread to resume" : `thread ${JSON.stringify(opts.resume)} is not in this plugin's job files for this repository`);
      thread = match.thread_id;
    }
    const mode = modeFor(record, state.settings, opts.use, opts.mode, state.notices);
    const command = thread ? "resume" : "run";
    const { spec, fence } = fenceFor(record, { mode, command, use: opts.use, requested: opts.mode, addDirs, unsandboxed: opts.unsandboxed });
    const { job, message } = await launch(state, { use: opts.use, mode, spec, fence, addDirs, command, model: opts.model, effort: opts.effort, prompt: opts.prompt, thread });
    return { code: exitFor(job.status), stdout: `${runLine(job)}\n${body(message)}`, stderr: errLines(job, state), job };
  } catch (error) {
    return stopped(opts.product, error, false, state);
  }
}

export async function review(opts) {
  let state = null;
  try {
    if (!opts.base) throw refuse("--base is required");
    if (opts.addDirs?.length || opts.unsandboxed !== undefined) throw refuse("a review is read-only and takes no --add-dir or --unsandboxed");
    state = setup(opts);
    const { ctx, record } = state;
    if (!record.review) throw refuse(`${record.product} has no review form`);
    if (opts.council && state.settings.council?.enabled === false) throw new Stop("skipped", `${record.product}.council.enabled is false`);
    if (opts.base.startsWith("-")) throw refuse(`base ${JSON.stringify(opts.base)} starts with "-"`);
    if (git(ctx.cwd, ["rev-parse", "--verify", "--quiet", "--end-of-options", `${opts.base}^{commit}`]) === null) throw refuse(`base ${JSON.stringify(opts.base)} is not a commit in ${ctx.cwd}`);
    const mergeBase = git(ctx.cwd, ["merge-base", "--end-of-options", opts.base, "HEAD"])?.trim();
    if (!mergeBase) throw refuse(`base ${JSON.stringify(opts.base)} shares no history with HEAD in ${ctx.cwd}`);
    const changed = (git(ctx.cwd, ["diff", "--name-only", "--end-of-options", `${mergeBase}...HEAD`]) ?? "").split(/\r?\n/).filter(Boolean);
    const scope = { base: opts.base, merge_base: mergeBase, changed_files: changed.length };
    for (const prefix of record.review.config_paths ?? []) {
      const hits = changed.filter((path) => path.startsWith(prefix)).length;
      if (!hits) continue;
      const notice = `the reviewed change touches ${prefix} (${plural(hits, "file")}): ${record.product} configuration there (hooks and MCP servers) runs outside the read-only sandbox`;
      state.notices.push(notice);
      state.announced.push(notice);
      ctx.warn(`notice: ${notice}\n`);
    }
    const native = record.review.kind === "native";
    const brief = opts.brief?.trim() ? opts.brief : null;
    const briefed = native && brief !== null && record.review.brief_args !== undefined;
    const listed = [...changed.slice(0, LISTED_FILES).map((path) => `\n- ${path}`), ...(changed.length > LISTED_FILES ? [`\n- and ${changed.length - LISTED_FILES} more`] : [])].join("");
    const tokens = { "{base}": opts.base, "{merge_base}": mergeBase, "{file_count}": String(changed.length), "{files}": listed };
    const preface = record.review.brief_preface?.replace(/\{[a-z_]+\}/g, (token) => tokens[token] ?? token);
    const prompt = briefed ? [preface, brief].filter(Boolean).join("\n\n") : brief;
    const { job, message } = await launch(state, {
      use: "review", mode: "read-only", command: native ? "review" : "run", model: opts.model, effort: opts.effort, prompt, baseArgs: briefed ? record.review.brief_args : undefined,
      base: native && !briefed ? opts.base : undefined, diffBase: native ? undefined : opts.base, thread: null, scope,
    });
    const ran = (job.status === "ok" || (job.status === "blocked-by-mode" && !job.reason)) && message.trim() !== "";
    const reviewed = `reviewed ${plural(scope.changed_files, "changed file")} against ${mergeBase.slice(0, 8)}`;
    const line = ran ? `${job.product}: ran${within([reviewed, ...details(job)])}` : `${job.product}: failed${within([job.status === "failed" ? null : job.status, job.reason, ...details(job)].filter(Boolean))}`;
    return { code: ran ? EXIT.ok : EXIT.failed, stdout: `${line}\n${ran ? body(message) : ""}`, stderr: errLines(job, state), job };
  } catch (error) {
    return stopped(opts.product, error, true, state);
  }
}

const alive = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

const owns = (pid, startedAt) => Number.isInteger(pid) && alive(pid) && (!startedAt || pidStartTime(pid) === startedAt);

function settle(ctx, job) {
  if (job.status !== "running") return job;
  if (owns(job.pid, job.pid_started_at) || owns(job.runner_pid, job.runner_started_at)) return job;
  const latest = readJob(ctx.dataDir, ctx.key, job.id) ?? job;
  if (latest.status !== "running") return latest;
  const ended = { ...latest, status: "failed", reason: "process exited", ended_at: new Date(ctx.now()).toISOString() };
  writeJob(ctx.dataDir, ctx.key, ended);
  return ended;
}

function find(opts) {
  const ctx = context(opts);
  if (!opts.jobId) throw refuse("a job id is required");
  let job;
  try {
    job = readJob(ctx.dataDir, ctx.key, opts.jobId);
  } catch (error) {
    throw refuse(error.message);
  }
  if (!job) throw refuse(`no job ${opts.jobId} for this repository`);
  return { ctx, job: settle(ctx, job) };
}

const guarded = (fn) => (opts = {}) => {
  try {
    return fn(opts);
  } catch (error) {
    return { code: error instanceof Stop ? EXIT.usage : EXIT.failed, stdout: "", stderr: `external-agents: ${oneLine(error?.message ?? error)}\n` };
  }
};

export const status = guarded((opts) => {
  if (opts.jobId) {
    const { job } = find(opts);
    const fields = ["id", "use", "mode", "fence", "add_dirs", "model", "effort", "started_at", "ended_at", "exit_code", "thread_id", "cli_version", "log_path", "final_message_path"];
    return { code: EXIT.ok, stdout: `${runLine(job)}\n${fields.map((f) => `${f}: ${[job[f] ?? ""].flat().join(", ")}`).join("\n")}\n`, stderr: "", job };
  }
  const ctx = context(opts);
  const jobs = listJobs(ctx.dataDir, ctx.key).map((job) => settle(ctx, job));
  return { code: EXIT.ok, stdout: jobs.length ? jobs.map((j) => `${j.id}  ${j.use}  ${runLine(j)}\n`).join("") : "no jobs for this repository\n", stderr: "", jobs };
});

export const result = guarded((opts) => {
  const { job } = find(opts);
  return { code: job.status === "running" ? EXIT.failed : exitFor(job.status), stdout: `${runLine(job)}\n${body(read(job.final_message_path))}`, stderr: errLines(job), job };
});

export const cancel = guarded((opts) => {
  const { ctx, job } = find(opts);
  if (job.status !== "running") return { code: EXIT.failed, stdout: `${job.product}: job ${job.id} is ${job.status}; nothing to cancel\n`, stderr: "", job };
  if (!job.pid_started_at || pidStartTime(job.pid) !== job.pid_started_at) {
    return { code: EXIT.failed, stdout: "", stderr: `external-agents: cannot confirm pid ${job.pid} is still job ${job.id}; nothing was killed\n`, job };
  }
  const cancelled = { ...job, status: "cancelled", reason: "cancelled by request", ended_at: new Date(ctx.now()).toISOString() };
  writeJob(ctx.dataDir, ctx.key, cancelled);
  if (killTree(job.pid) || !alive(job.pid)) return { code: EXIT.ok, stdout: `${runLine(cancelled)}\n`, stderr: "", job: cancelled };
  if (readJob(ctx.dataDir, ctx.key, job.id)?.status === "cancelled") writeJob(ctx.dataDir, ctx.key, job);
  return { code: EXIT.failed, stdout: "", stderr: `external-agents: could not kill pid ${job.pid}; job ${job.id} is still running\n`, job };
});
