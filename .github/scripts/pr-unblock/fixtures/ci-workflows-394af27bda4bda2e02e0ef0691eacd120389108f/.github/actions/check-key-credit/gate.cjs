// check-key-credit: whether a keyed lane's key job should skip the model
// because the key ended in a credit stop inside the window.
//
// The key job uploads an artifact named markerName(key) after the
// launcher's lane-class `credit-stop` (run-claude-cli: classify.cjs
// isCreditStop), so an auth stop (401, or 402 without the credit text) never
// writes one. This gate's first call reads the repository's artifacts of that
// exact name, and skips the key when the newest unexpired one was created
// inside the window, citing the run that uploaded it. The window counts from
// that upload, so a topped-up or rotated key is tried on the first run after
// it (the window backs off: see below). No marker in the window, any failure
// or an unreadable answer runs the key: it never skips
// the subscription path and never fails the step.
//
// The name carries the key's secret name (KEY_SECRET, as
// select-model-credential derives it from the role), so one credit stop
// holds off every job in the repository that runs the same key. A caller
// that passes no secret name keeps the name of its workflow file and key
// job, judged on its own credit stops. A fork's pull_request run
// holds no secret but can upload an artifact of any name from a modified
// workflow, so a marker counts only when its run's head repository is this
// repository (workflow_run.head_repository_id equal to repository_id). Any
// workflow of this repository can still upload one; the worst it does is
// move reviews to the subscription for the window. More than 100 markers of
// one name in
// retention can push the newest off the page, which runs the key or shortens
// the step.
//
// The probing marker closes the re-probe race: when the window has ended but
// a credit-stop marker is still in retention, every gate until the first
// re-probe's own credit stop lands would run the empty key. So the gate then
// makes a second call, the probing markers (probeName), and:
//   - a probing marker created after that credit stop and inside the probe
//     window skips, citing the probing run;
//   - one created after it but older than the probe window means that probe
//     hit no credit stop, so the key runs and no new probe is written;
//   - none means this gate is the probe: the key runs and the probing-marker
//     output names the artifact the gate job uploads.
// With no credit-stop marker in retention the key is healthy: one call, no
// probe, so a working key is never held to one call per probe window. A
// failed probe read runs the key and writes no probe. A probe run cancelled
// before its key leg leaves no credit stop either, so the next gate after it
// expires runs the key as healthy.
//
// The window backs off: window-hours is the base step, and each consecutive
// credit stop doubles it, capped at 24 hours (1, 2, 4, 8, 16, 24 from a base
// of 1; a base above 24 hours never backs off). Consecutive credit stops are
// the credit-stop markers created after reset-at, oldest first, where:
//   - a marker counts as the next step only when it was created at or after
//     the previous counted marker plus that marker's window, so it came from
//     a run let through to try the key again; markers inside a window, from
//     runs already in flight when the key stopped, add no step;
//   - a probing marker between two markers that no credit-stop marker
//     followed inside the probe window is a key run that worked, and the
//     next marker starts again at the base step.
// The step comes from the two listings the gate already reads, with no new
// call: inside the base window any step skips, so only a credit stop past it
// needs the step, and that path already reads the probing markers. The
// caller sets retention: pr-review-cli.yml keeps both markers 7 days, long
// enough for six steps at the cap; intake-triage.yml keeps its credit-stop
// marker one day with probing off. A marker that expires only shortens the
// step. reset-at, the time the rotation tool
// last pushed a key (vars.KEY_CREDIT_RESET_AT), drops every credit stop
// before it, so a new key is tried on the next run. Empty or anything but an
// ISO-8601 UTC time is no reset. A key whose credit comes back on its
// account's monthly cycle, or one set by hand with `gh secret set`, writes no
// reset-at, so it waits out the current step, at most 24 hours; action.yml
// gives the one-line manual reset.
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const MARKER_PREFIX = "key-credit-stop-";
const PROBE_PREFIX = "key-credit-probing-";
const MAX_WINDOW_HOURS = 168;
// The base window when window-hours is empty, so a caller passes an unset
// vars.KEY_CREDIT_WINDOW_HOURS as it is; the one place this default lives.
const DEFAULT_WINDOW_HOURS = 1;
// The probe window when probe-minutes is empty.
const DEFAULT_PROBE_MINUTES = 15;
// The longest backed-off window; a larger base is used as it is.
const MAX_STEP_HOURS = 24;
const MAX_PROBE_MINUTES = 1440;
const WORKFLOW_REF = /^[\w.-]+\/[\w.-]+\/\.github\/workflows\/([\w.-]+\.ya?ml)@/u;
// The shape the rotation tool writes, optionally with milliseconds. Date.parse
// alone takes far looser text ("2026"), which is no reset here.
// A secret name as run-claude-cli derives it (ROLE_CLAUDE_API_KEY).
const SECRET = /^[A-Z][A-Z0-9_]{0,99}$/u;
const RESET_AT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/u;

// The rate-limit reading report-api-budget reads, as the scope step writes
// it, under the route of the gate's one request (the artifact list). A
// failed write only drops the reading.
function recordBudget(response, runnerTemp) {
  if (!runnerTemp) return;
  const values = ["limit", "remaining", "used", "reset", "resource"].map(
    (key) => {
      const value = String(response.headers?.get?.(`x-ratelimit-${key}`) ?? "");
      return (key === "resource" ? /^[a-z_]+$/u : /^\d+$/u).test(value)
        ? value
        : "na";
    },
  );
  try {
    const dir = path.join(runnerTemp, "api-budget");
    fs.mkdirSync(dir, { recursive: true });
    fs.appendFileSync(
      path.join(dir, "github-token"),
      `${response.status} ${values.join(" ")} repos/{repo}/actions/artifacts\n`,
    );
  } catch {
    // No reading: the notice is only missing one.
  }
}

// What a marker name carries: the key's secret name, or without one the
// caller's workflow file and key job.
const keyOf = (secret, workflow, keyJob) => secret || `${workflow}-${keyJob}`;

// The artifact name the key job uploads and this gate reads.
function markerName(key) {
  return `${MARKER_PREFIX}${key}`;
}

// The artifact name the gate job uploads when it passes the key as a probe.
function probeName(key) {
  return `${PROBE_PREFIX}${key}`;
}

// The unexpired markers of the exact name, created at or after `sinceMs` by
// a run whose head is this repository, oldest first.
function markers(artifacts, name, sinceMs) {
  const found = [];
  for (const artifact of Array.isArray(artifacts) ? artifacts : []) {
    const created = Date.parse(artifact?.created_at ?? "");
    const run = artifact?.workflow_run?.id;
    const repo = artifact?.workflow_run?.repository_id;
    if (
      artifact?.name !== name ||
      artifact.expired !== false ||
      !Number.isFinite(created) ||
      created < sinceMs ||
      !Number.isSafeInteger(run) ||
      !Number.isSafeInteger(repo) ||
      artifact.workflow_run.head_repository_id !== repo
    ) {
      continue;
    }
    found.push({ created, run });
  }
  return found.sort((a, b) => a.created - b.created);
}

// The newest of those markers, or null.
function newestMarker(artifacts, name, sinceMs) {
  return markers(artifacts, name, sinceMs).at(-1) ?? null;
}

// Step `steps` of the backoff from a base window, in milliseconds.
function stepMs(baseMs, steps) {
  const cap = Math.max(MAX_STEP_HOURS * 3600 * 1000, baseMs);
  return Math.min(cap, baseMs * 2 ** Math.min(steps - 1, 30));
}

// How many consecutive credit stops end at the newest of `stops` (oldest
// first, all after reset-at), and that step's window: see the header.
function backoff(stops, probes, baseMs, probeMs) {
  let steps = 0;
  let counted = -Infinity;
  for (const [index, stop] of stops.entries()) {
    const previous = index > 0 ? stops[index - 1].created : -Infinity;
    const worked = probes.some(
      (probe) =>
        probe.created > previous && probe.created + probeMs < stop.created,
    );
    if (worked) steps = 0;
    if (steps === 0 || stop.created >= counted + stepMs(baseMs, steps)) {
      steps++;
      counted = stop.created;
    }
  }
  return { steps, windowMs: stepMs(baseMs, Math.max(steps, 1)) };
}

// reset-at as milliseconds, or -Infinity (no reset) for anything else.
function parseReset(text) {
  const value = String(text ?? "").trim();
  const ms = RESET_AT.test(value) ? Date.parse(value) : NaN;
  return Number.isFinite(ms) ? ms : -Infinity;
}

// The decision from one credit-stop listing: a marker inside the window
// skips, citing its run.
function judgeMarkers(artifacts, name, sinceMs) {
  const newest = newestMarker(artifacts, name, sinceMs);
  return newest
    ? { skip: true, origin: String(newest.run) }
    : { skip: false, reason: "no credit-stop marker in the window" };
}

async function read(listArtifacts, name, what) {
  try {
    const artifacts = await listArtifacts(name);
    return Array.isArray(artifacts)
      ? { artifacts }
      : { reason: `the ${what} list was not a list` };
  } catch (error) {
    return { reason: `the ${what}s were not read (${error.message})` };
  }
}

// The decision, from an injected reader of one exact name; never throws.
// `sinceMs` is the base window's start (nowMs minus window-hours), and only
// credit stops after `resetMs` count. `probe` (the probing marker's name and
// `probeSinceMs`) is optional: without it the gate reads the credit-stop
// marker alone and the backoff sees no key run that worked. `probe: true` on
// a verdict asks the gate job to upload the probing marker; `steps` on a
// credit-stop skip is the backoff step and `hours` its window.
async function decide({ listArtifacts, name, sinceMs, probe = null, probeSinceMs = 0, nowMs = 0, resetMs = -Infinity }) {
  const listed = await read(listArtifacts, name, "marker");
  if (!listed.artifacts) return { skip: false, reason: listed.reason };
  const after = resetMs + 1;
  const verdict = judgeMarkers(listed.artifacts, name, Math.max(sinceMs, after));
  if (verdict.skip) return verdict;
  const stops = markers(listed.artifacts, name, after);
  const stop = stops.at(-1);
  if (!stop) return verdict;
  let probes = { artifacts: [] };
  if (probe) {
    probes = await read(listArtifacts, probe, "probing marker");
    if (!probes.artifacts) return { skip: false, reason: probes.reason };
  }
  const { steps, windowMs } = backoff(
    stops,
    markers(probes.artifacts, probe, -Infinity),
    nowMs - sinceMs,
    nowMs - probeSinceMs,
  );
  if (stop.created >= nowMs - windowMs) {
    return { skip: true, origin: String(stop.run), steps, hours: windowMs / 3600000 };
  }
  if (!probe) return verdict;
  const prior = newestMarker(probes.artifacts, probe, stop.created);
  if (!prior) {
    return {
      skip: false,
      reason: `the credit stop in run ${stop.run} is past the window; this run probes the key`,
      probe: true,
    };
  }
  if (prior.created >= probeSinceMs) {
    return {
      skip: true,
      origin: String(prior.run),
      probing: Math.max(0, Math.round((nowMs - prior.created) / 60000)),
    };
  }
  return {
    skip: false,
    reason: `run ${prior.run} probed the key after its credit stop with no new credit stop`,
  };
}

function readEnv(env) {
  const keyJob = env.KEY_JOB ?? "";
  const window = String(env.WINDOW_HOURS ?? "").trim();
  const hours = window === "" ? DEFAULT_WINDOW_HOURS : Number(window);
  const probe = String(env.PROBE_MINUTES ?? "").trim();
  const probeMinutes = probe === "" ? DEFAULT_PROBE_MINUTES : Number(probe);
  const workflow = (env.WORKFLOW_REF ?? "").match(WORKFLOW_REF)?.[1] ?? null;
  const secretText = String(env.KEY_SECRET ?? "").trim();
  const secret = SECRET.test(secretText) ? secretText : "";
  const repository = env.GITHUB_REPOSITORY ?? "";
  const valid =
    /^[a-z][a-z0-9-]{0,99}$/u.test(keyJob) &&
    /^[\w.-]+\/[\w.-]+$/u.test(repository) &&
    (secret !== "" || workflow !== null);
  const key = keyOf(secret, workflow, keyJob);
  return {
    keyJob,
    hours,
    // Out of range or unreadable turns probing off: the key runs unprobed.
    probeMinutes:
      probeMinutes > 0 && probeMinutes <= MAX_PROBE_MINUTES ? probeMinutes : 0,
    repository,
    marker: valid ? markerName(key) : "",
    probe: valid ? probeName(key) : "",
    api: env.GITHUB_API_URL || "https://api.github.com",
    server: env.GITHUB_SERVER_URL || "https://github.com",
    token: env.GITHUB_TOKEN ?? "",
    runnerTemp: env.RUNNER_TEMP ?? "",
    resetMs: parseReset(env.RESET_AT),
    valid,
  };
}

async function main(env = process.env, fetchImpl = globalThis.fetch, now = () => new Date()) {
  const config = readEnv(env);
  const lines = [];
  let verdict;
  if (!(config.hours > 0 && config.hours <= MAX_WINDOW_HOURS)) {
    verdict = { skip: false, reason: "the window is off" };
  } else if (!config.valid || config.token === "") {
    verdict = { skip: false, reason: "the workflow, job or token is unreadable" };
  } else {
    const nowMs = now().getTime();
    verdict = await decide({
      name: config.marker,
      sinceMs: nowMs - config.hours * 3600 * 1000,
      probe: config.probeMinutes > 0 ? config.probe : null,
      probeSinceMs: nowMs - config.probeMinutes * 60 * 1000,
      nowMs,
      resetMs: config.resetMs,
      // The API's name filter takes one exact name, so each marker is a call.
      listArtifacts: async (name) => {
        const response = await fetchImpl(
          `${config.api}/repos/${config.repository}/actions/artifacts?name=${encodeURIComponent(name)}&per_page=100`,
          {
            headers: {
              Accept: "application/vnd.github+json",
              Authorization: `Bearer ${config.token}`,
              "X-GitHub-Api-Version": "2022-11-28",
            },
            signal: AbortSignal.timeout(15000),
          },
        );
        recordBudget(response, config.runnerTemp);
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return (await response.json())?.artifacts;
      },
    });
  }
  if (verdict.skip && verdict.probing !== undefined) {
    lines.push(
      `::notice title=check-key-credit::${config.keyJob} skips the key: run ${verdict.origin} (${config.server}/${config.repository}/actions/runs/${verdict.origin}) is probing the key, ${verdict.probing} minutes ago, inside the ${config.probeMinutes}-minute probe window; the subscription job reviews`,
    );
  } else if (verdict.skip) {
    lines.push(
      `::notice title=check-key-credit::${config.keyJob} skips the key: the key's credit stop in run ${verdict.origin} (${config.server}/${config.repository}/actions/runs/${verdict.origin}) is inside the ${verdict.hours ?? config.hours}-hour window${verdict.steps ? ` (credit stop ${verdict.steps} in a row)` : ""}; the subscription job reviews`,
    );
  } else {
    lines.push(`check-key-credit: ${config.keyJob || "the key job"} runs the key: ${verdict.reason}`);
  }
  if (env.GITHUB_OUTPUT) {
    fs.appendFileSync(
      env.GITHUB_OUTPUT,
      `skip-key=${verdict.skip}\norigin-run=${verdict.skip ? verdict.origin : ""}\nmarker=${config.marker}\nprobing-marker=${verdict.probe ? config.probe : ""}\n`,
    );
  }
  return { verdict, lines };
}

if (require.main === module) {
  main()
    .then(({ lines }) => process.stdout.write(`${lines.join("\n")}\n`))
    .catch(() => {
      // Fail open: no output leaves skip-key empty, so the key runs.
      process.stdout.write("check-key-credit: the check failed; the key runs\n");
    });
}

module.exports = {
  DEFAULT_WINDOW_HOURS,
  backoff,
  decide,
  judgeMarkers,
  main,
  markerName,
  parseReset,
  probeName,
};
