// Project the last claude-code-action SDK result message into safe, structured
// metadata and classify a genuine infrastructure failure into exactly one coarse
// class from FAILURE_CLASSES (docs/lane-outcome.md, "Failure classes");
// credit-stop only for a caller that opts in (see isCreditStop). Reads
// the action's execution_file output (which may be unset, missing, or
// unparsable) and returns the review detail plus failure class.
//
// This runs on a PUBLIC repo. The result message's `result` field is
// model-authored free text and its `errors[]` entries are raw error stacks; both
// are read INSIDE this module only, and nothing but the class, the
// structured projection below and apiErrorFacts' values ever leaves it.
// apiErrorFacts reads the CLI's own error text from a run with no model
// output and keeps only values that match a closed pattern. Never widen the
// projection to either field, and never emit the result message wholesale.
//
// Classification order:
//   0. `timedOut` — the caller saw the step run its whole timeout-minutes
//      budget. A killed step leaves no result message, so wall time decides.
//      Then `installFailed` with no execution file: the action's Bun install
//      failed (seen as an HTTP 429 on the GitHub release download), so Claude
//      never started. Any other missing execution file is `no-execution`: the
//      step ended before writing one.
//   1. `api_error_status` — the Anthropic-API HTTP status the SDK records when
//      the last assistant turn was an API error: 401/402/403 auth, 429
//      rate-limit, 5xx overloaded, every other status other.
//   2. max-turns: subtype `error_max_turns` (the run used every turn
//      --max-turns allows), or a success-subtype result with `num_turns` above
//      the caller's `maxTurns`. The second is claude-code-action failing a run that finished past the cap
//      ("Claude reported a successful result after N turns, exceeding the
//      configured maximum of M"), whose result message reads as a success.
//   3. an allowlisted substring over `errors[]`, matching the serialized
//      Anthropic error body (`{"type":"error","error":{"type":"<type>",...}}`)
//      that the API SDK folds into an APIError's message, and so into its stack.
//   4. other.
//
// The allowlist mirrors the status mapping type-for-type, so a payload that
// recovers no numeric status still lands in the same class the status would
// have chosen. Against the published error table that is: `authentication_error`
// (401), `billing_error` (402), `permission_error` (403) -> auth;
// `rate_limit_error` (429) -> rate-limit; `api_error` (500), `timeout_error`
// (504), `overloaded_error` (529) -> overloaded. The remaining published types
// — `invalid_request_error` (400), `not_found_error` (404), `conflict_error`
// (409), `request_too_large` (413) — are client errors, not infrastructure, and
// are deliberately left to `other` on both paths. Adding a type to one path
// without the other reopens the asymmetry this note exists to prevent.
//
// `auth` is the credential-unusable class, not the 401-only class: it covers
// every status where the credential cannot be used until a human acts. Per the
// published error table that is 401 `authentication_error`, 402 `billing_error`,
// and 403 `permission_error`. 402 belongs here because a usage-dead
// account credential is a billing/entitlement death, which the API reports as 402.
//
// The two sources are disjoint members of the SDK's result union:
// `api_error_status` exists only on the success variant (the shape a dead
// credential produces — subtype success, is_error true) and `errors[]` only on
// the error subtypes. So the substring pass is the error-variant path, not a
// second look at the same payload, and a present-but-unmapped status stays a
// status decision rather than falling through to it.
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

function classFromStatus(status) {
  if (status === 401 || status === 402 || status === 403) return "auth";
  if (status === 429) return "rate-limit";
  if (status >= 500 && status < 600) return "overloaded";
  return "other";
}

// Closed published-type allowlist. Values projected as error_type come ONLY
// from this list — never from raw model/SDK text — so public-log hygiene holds.
const ERROR_TYPE_ALLOWLIST = [
  ["authentication_error", "auth"],
  ["billing_error", "auth"],
  ["permission_error", "auth"],
  ["rate_limit_error", "rate-limit"],
  ["overloaded_error", "overloaded"],
  ["timeout_error", "overloaded"],
  ["api_error", "overloaded"],
];

function matchErrorType(text) {
  for (const [errorType, failureClass] of ERROR_TYPE_ALLOWLIST) {
    if (text.includes(`"type":"${errorType}"`)) {
      return { errorType, failureClass };
    }
  }
  return { errorType: null, failureClass: "other" };
}

// Mirrors jq's `tostring`, so an object error entry exposes its
// `"type":"..."` body to the substring pass.
function toStringLikeJq(value) {
  return typeof value === "string" ? value : JSON.stringify(value);
}

// The last result message, or undefined.
const resultOf = (messages) =>
  messages.findLast((message) => message?.type === "result");

// A Date as ISO-8601 to the second, or null when it is invalid.
const isoSeconds = (date) =>
  Number.isNaN(date.getTime())
    ? null
    : date.toISOString().replace(/\.000Z$/u, "Z");

// The entries whose value is not null as an object, or null when none is.
function present(entries) {
  const kept = entries.filter(([, value]) => value !== null);
  return kept.length > 0 ? Object.fromEntries(kept) : null;
}

// The execution file's messages, or null when it is unset, missing or not a
// JSON array.
function readMessages(executionFilePath) {
  if (!executionFilePath || !fs.existsSync(executionFilePath)) return null;
  try {
    const parsed = JSON.parse(fs.readFileSync(executionFilePath, "utf8"));
    return Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

// credit-stop: an API-key credential whose Console organization has no credit
// left or has hit a spend limit, judged only where no model output exists, so
// the error text read below is the CLI's own. Opt-in through
// `detectCreditStop`; existing callers never see this class.
//
// Proof that the text is the CLI's: the run made no tool call and every
// assistant message carries the SDK's `error` field (a synthesized API-error
// message), and the result reports 0 output tokens. Then a credit-stop
// status (400 spend limit, 402 billing, 429 tier spend cap) or SDK error
// category must be present, the exit code non-zero, and the text must match
// one documented credit-stop phrase. A real workspace spend-limit stop matches
// (the observed test in classify.test.cjs); a zero-balance stop is not yet
// observed. This function is the one place to change.
const CREDIT_STOP_STATUSES = new Set([400, 402, 429]);
const CREDIT_STOP_ERRORS = new Set([
  "billing_error",
  "rate_limit",
  "invalid_request",
]);
const CREDIT_STOP_PHRASES = [
  /credit balance is too low/iu,
  /you have reached your specified (?:workspace )?api usage limits/iu,
  /you have reached your api usage limits/iu,
  /enforced_spend_limit_reached/u,
];
const REGAIN_ACCESS =
  /regain access on (\d{4}-\d{2}-\d{2}) at (\d{2}):(\d{2}) UTC/u;

// The failed run's messages when no model output exists, so every text in
// them is the CLI's own; else null.
function cliOnlyRun(messages) {
  const result = resultOf(messages);
  if (result?.is_error !== true) return null;
  const assistants = messages.filter((m) => m?.type === "assistant");
  const content = assistants.flatMap((m) =>
    Array.isArray(m.message?.content) ? m.message.content : [],
  );
  if (content.some((block) => block?.type === "tool_use")) return null;
  if (assistants.some((m) => typeof m.error !== "string")) return null;
  const outputTokens = result.usage?.output_tokens;
  if (outputTokens !== undefined && outputTokens !== 0) return null;
  return { result, assistants, content };
}

// The CLI's own error text in a cliOnlyRun: the result text, `errors[]` on
// the error variant, and assistant text blocks.
function cliOnlyText({ result, content }) {
  return [
    typeof result.result === "string" ? result.result : "",
    ...(Array.isArray(result.errors) ? result.errors : []).map(toStringLikeJq),
    ...content
      .filter((block) => block?.type === "text")
      .map((block) => String(block.text ?? "")),
  ].join("\n");
}

function creditStopText(messages) {
  const run = cliOnlyRun(messages);
  if (run === null) return null;
  const { result, assistants } = run;
  const status = result.api_error_status;
  // A 403 is a permission stop whatever its text says, so it never becomes
  // a credit stop, which hands off.
  if (status === 403 || assistants.some((m) => m.api_error_status === 403)) {
    return null;
  }
  const statusMatches =
    typeof status === "number" && CREDIT_STOP_STATUSES.has(status);
  const errorMatches = assistants.some((m) => CREDIT_STOP_ERRORS.has(m.error));
  if (!statusMatches && !errorMatches) return null;
  const text = cliOnlyText(run);
  return CREDIT_STOP_PHRASES.some((phrase) => phrase.test(text)) ? text : null;
}

function isCreditStop(messages, { exitCode = null } = {}) {
  if (!Array.isArray(messages) || exitCode === 0) return false;
  return creditStopText(messages) !== null;
}

// The time a tier spend cap lifts, from the documented "You will regain
// access on YYYY-MM-DD at HH:MM UTC." sentence of a credit stop; else null.
function creditStopResetsAt(messages) {
  const text = Array.isArray(messages) ? creditStopText(messages) : null;
  const match = text?.match(REGAIN_ACCESS);
  return match
    ? isoSeconds(new Date(`${match[1]}T${match[2]}:${match[3]}:00Z`))
    : null;
}

// The API error body's type, `error.details.error_code` and `request_id`
// (the error shape at platform.claude.com/docs/en/api/errors), read from
// the CLI's own error text only (cliOnlyRun): the result text, `errors[]`
// on the error variant, and assistant text. Each is kept only when it
// matches a closed pattern; null when absent. Diagnostics only: no class
// or handoff depends on them.
function apiErrorFacts(messages) {
  const run = Array.isArray(messages) ? cliOnlyRun(messages) : null;
  const none = { errorType: null, errorCode: null, requestId: null };
  if (run === null) return none;
  const text = cliOnlyText(run);
  const match = (pattern) => text.match(pattern)?.[1] ?? null;
  return {
    errorType: match(/"error":\{"type":"([a-z_]{1,40})"/u),
    errorCode: match(/"error_code":"([a-z0-9_]{1,64})"/u),
    requestId: match(/\b(req_[A-Za-z0-9]{8,64})\b/u),
  };
}

// shell-failed: a run that made at least `minCalls` Bash calls the permission
// system allowed, and every one of them returned `is_error: true`, as a lost
// sandbox (`bwrap:` on every call) leaves it. One or two failures are often a
// normal non-zero exit (a grep with no match, a `test -f`), so they never
// qualify on their own. A denied call also returns `is_error: true`, so it is
// taken out first: by its id in the result message's `permission_denials`,
// the Agent SDK's authoritative denial record, or, should a CLI leave it off
// that list, by its result text matching a CLI permission-denied message. A
// call with no result proves nothing either way and is not counted. Returns
// the failed count, or 0 when the run is not shell-failed.
//
// The denial texts, as CLI 2.1.303 (claude-code-action v1.0.253) writes them
// for a Bash call: no allow rule matched; a deny rule matched; dontAsk mode.
const DENIAL_TEXTS = [
  /^This command requires approval$/u,
  /^Permission to use Bash (?:with command [\s\S]* )?has been denied\b/u,
];
const FAILED_SHELL_MIN_CALLS = 3;
function resultText(block) {
  if (typeof block.content === "string") return block.content;
  return (Array.isArray(block.content) ? block.content : [])
    .map((part) => (part?.type === "text" ? String(part.text ?? "") : ""))
    .join("\n");
}
function failedShellCalls(messages, minCalls = FAILED_SHELL_MIN_CALLS) {
  if (!Array.isArray(messages)) return 0;
  const blocks = (type) =>
    messages
      .flatMap((m) => (Array.isArray(m?.message?.content) ? m.message.content : []))
      .filter((block) => block?.type === type);
  const result = resultOf(messages);
  const denied = new Set(
    (Array.isArray(result?.permission_denials) ? result.permission_denials : []).map(
      (denial) => denial?.tool_use_id,
    ),
  );
  const shellIds = new Set(
    blocks("tool_use")
      .filter((block) => block.name === "Bash" && !denied.has(block.id))
      .map((block) => block.id),
  );
  const results = blocks("tool_result").filter(
    (block) =>
      shellIds.has(block.tool_use_id) &&
      !DENIAL_TEXTS.some((pattern) => pattern.test(resultText(block))),
  );
  return results.length >= Math.max(1, minCalls) &&
    results.every((block) => block.is_error === true)
    ? results.length
    : 0;
}

function classifyExecutionFile(
  executionFilePath,
  {
    timedOut = false,
    maxTurns = "",
    installFailed = false,
    detectCreditStop = false,
    exitCode = null,
  } = {},
) {
  const fallbackClass = timedOut ? "timeout" : "other";
  if (!executionFilePath || !fs.existsSync(executionFilePath)) {
    return {
      reviewDetail: "(no execution file was produced)",
      failureClass: timedOut
        ? "timeout"
        : installFailed
          ? "install-failed"
          : "no-execution",
    };
  }

  const messages = readMessages(executionFilePath);
  const last = messages?.at(-1);
  if (last === undefined || last === null) {
    return {
      reviewDetail: "(execution file present but unparsable)",
      failureClass: fallbackClass,
    };
  }

  const status = last.api_error_status;
  let failureClass;
  // error_type is set only on the substring path: numeric-status classification
  // already has api_error_status as its discriminator.
  let errorType = null;
  if (timedOut) {
    failureClass = "timeout";
  } else if (detectCreditStop && isCreditStop(messages, { exitCode })) {
    failureClass = "credit-stop";
  } else if (typeof status === "number") {
    failureClass = classFromStatus(status);
  } else if (
    last.subtype === "error_max_turns" ||
    (last.subtype === "success" &&
      /^\d{1,6}$/u.test(maxTurns) &&
      Number.isInteger(last.num_turns) &&
      last.num_turns > Number(maxTurns))
  ) {
    failureClass = "max-turns";
  } else {
    const text = (Array.isArray(last.errors) ? last.errors : [])
      .map(toStringLikeJq)
      .join("\n");
    const matched = matchErrorType(text);
    failureClass = matched.failureClass;
    errorType = matched.errorType;
  }

  const projection = {
    subtype: last.subtype ?? null,
    is_error: last.is_error ?? null,
    num_turns: last.num_turns ?? null,
    duration_ms: last.duration_ms ?? null,
    total_cost_usd: last.total_cost_usd ?? null,
    api_error_status: status ?? null,
    error_type: errorType,
    class: failureClass,
  };

  return { reviewDetail: JSON.stringify(projection), failureClass };
}

// The run record: structured facts about a run, each a lane-outcome record
// field (docs/lane-outcome.md) so a reader can see limit stops, the
// credential behind them, turn headroom and the models used.
// Values come from typed SDK fields and caller inputs, and the error facts
// from the CLI's own error text (apiErrorFacts), each checked against a
// closed pattern; nothing else is taken from free text.
const CREDENTIAL_PATTERN = /^[A-Z][A-Z0-9_]{0,99}$/u;
const MODEL_PATTERN = /^[\w.:@[\]-]{1,100}$/u;
const COUNT_PATTERN = /^\d{1,6}$/u;
// The largest count COUNT_PATTERN admits, and the record's bound on turns.
const COUNT_MAX = 999999;
// A failure class as a closed kebab token.
const CLASS_PATTERN = /^[a-z][a-z-]{0,39}$/u;
const WINDOW_PATTERN = /^[a-z0-9_]{1,40}$/u;
// Why a later leg ran: the leg before it credit-stopped or had its
// credential refused with API status 401 or 402, the key job had no key, or
// (for the fallback leg) the subscription leg hit a usage limit.
const FALLBACK_REASONS = ["credit-stop", "auth", "no-key", "limit-stop"];

// SDK `resetsAt` is epoch time; a value past 1e12 can only be milliseconds.
function isoFromEpoch(value) {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    return null;
  }
  return isoSeconds(new Date(value < 1e12 ? value * 1000 : value));
}

// A rate_limit_event's info with each field read in either form: camelCase
// as the TypeScript reference (SDKRateLimitEvent) and the CLI's events seen
// so far name them, snake_case as python.md (RateLimitInfo) does. Null for
// any other message.
function limitInfo(message) {
  const info = message?.type === "rate_limit_event" && message.rate_limit_info;
  if (!info || typeof info !== "object") return null;
  return {
    status: info.status,
    resetsAt: info.resetsAt ?? info.resets_at,
    rateLimitType: info.rateLimitType ?? info.rate_limit_type,
    utilization: info.utilization,
  };
}

// The limit that stopped the run: the newest `rate_limit_event` whose status
// is `rejected`. Only a rejected event names the window that stopped the run;
// an allowed or warning event's reset is another window's and would bring the
// restart too early, so with none the caller's fallback delay applies.
function limitStopFrom(messages) {
  const info = messages
    .map(limitInfo)
    .findLast(
      (event) =>
        event?.status === "rejected" && isoFromEpoch(event.resetsAt) !== null,
    );
  if (!info) return { resetsAt: null, resetsWindow: null };
  return {
    resetsAt: isoFromEpoch(info.resetsAt),
    resetsWindow: WINDOW_PATTERN.test(info.rateLimitType ?? "")
      ? info.rateLimitType
      : null,
  };
}

// The subscription windows and statuses `rate_limit_event` names, per the
// Agent SDK reference (code.claude.com/docs/en/agent-sdk/python.md,
// RateLimitInfo). Any other value is dropped.
const RATE_LIMIT_WINDOWS = [
  "five_hour",
  "seven_day",
  "seven_day_opus",
  "seven_day_sonnet",
  "overage",
];
const RATE_LIMIT_STATUSES = ["allowed", "allowed_warning", "rejected"];
const ISO_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/u;

// A 0-1 fraction rounded to 2 decimals, or null.
function fraction(value) {
  return typeof value === "number" && value >= 0 && value <= 1
    ? Math.round(value * 100) / 100
    : null;
}

// Each window's highest utilization over the run, and its newest event's
// status and reset. A window no event gave a utilization has none, never 0.
function rateLimitWindows(messages) {
  const windows = {};
  for (const message of messages) {
    const info = limitInfo(message);
    if (
      !info ||
      !RATE_LIMIT_WINDOWS.includes(info.rateLimitType) ||
      !RATE_LIMIT_STATUSES.includes(info.status)
    ) {
      continue;
    }
    const seen = windows[info.rateLimitType]?.utilization ?? null;
    const now = fraction(info.utilization);
    windows[info.rateLimitType] = {
      utilization: seen === null || (now !== null && now > seen) ? now : seen,
      resetsAt: isoFromEpoch(info.resetsAt),
      status: info.status,
    };
  }
  return windows;
}

// The token usage and windows of the leg, from the last record of
// run-claude-cli's credential-scanned JSONL log, each value checked again
// (a process the leg left could have touched the file). Nulls when absent.
function readLegLog(logFilePath) {
  const none = { usage: null, windows: null };
  if (!logFilePath || !fs.existsSync(logFilePath)) return none;
  let leg;
  try {
    const lines = fs.readFileSync(logFilePath, "utf8").trim().split("\n");
    leg = JSON.parse(lines.at(-1));
  } catch {
    return none;
  }
  const count = (value) =>
    Number.isSafeInteger(value) && value >= 0 ? value : null;
  const usage = leg?.usage ?? {};
  const limits = leg?.rate_limits ?? {};
  return {
    usage: present([
      ["input", count(usage.input_tokens)],
      ["output", count(usage.output_tokens)],
      ["cacheRead", count(usage.cache_read_input_tokens)],
      ["cacheCreation", count(usage.cache_creation_input_tokens)],
    ]),
    windows: present(
      RATE_LIMIT_WINDOWS.filter((window) =>
        RATE_LIMIT_STATUSES.includes(limits[window]?.status),
      ).map((window) => [
        window,
        present([
          ["utilization", fraction(limits[window].utilization)],
          [
            "resetsAt",
            ISO_PATTERN.test(limits[window].resets_at ?? "")
              ? limits[window].resets_at
              : null,
          ],
          ["status", limits[window].status],
        ]),
      ]),
    ),
  };
}

function readRunRecord(executionFilePath) {
  const messages = readMessages(executionFilePath) ?? [];
  const result = resultOf(messages);
  const turns = result?.num_turns;
  const usage = result?.modelUsage;
  const cost = result?.total_cost_usd;
  const duration = result?.duration_ms;
  return {
    turns: Number.isInteger(turns) && turns >= 0 ? turns : null,
    // The CLI's own measure of the run's wall time.
    durationMs: Number.isSafeInteger(duration) && duration >= 0 ? duration : null,
    // The CLI's own list-price estimate of the run, not what was billed.
    costUsd:
      typeof cost === "number" && Number.isFinite(cost) && cost >= 0
        ? cost
        : null,
    models:
      usage && typeof usage === "object" && !Array.isArray(usage)
        ? Object.keys(usage).filter((key) => MODEL_PATTERN.test(key))
        : [],
    ...limitStopFrom(messages),
    ...apiErrorFacts(messages),
  };
}

// At most this many models in the record (docs/lane-outcome.md).
const MAX_MODELS = 8;

// The run's facts for one annotation, each gate applied once: resets only on
// a limit stop (rate-limit), the API error facts only on a failure, the
// credential and fallback reason only from their closed sets, the max-turns
// cap only as a count, the models only up to MAX_MODELS. The lane-outcome
// record serializes this one object.
function runFacts(
  {
    turns = null,
    durationMs = null,
    costUsd = null,
    models = [],
    resetsAt = null,
    resetsWindow = null,
    errorType = null,
    errorCode = null,
    requestId = null,
    usage = null,
    windows = null,
  },
  {
    failureClass = "",
    maxTurns = "",
    credential = "",
    fallbackReason = "",
  } = {},
) {
  const limitStop = failureClass === "rate-limit" && Boolean(resetsAt);
  const failed = failureClass !== "";
  return {
    failureClass,
    resetsAt: limitStop ? resetsAt : null,
    resetsWindow: limitStop ? resetsWindow : null,
    errorType: failed ? errorType : null,
    errorCode: failed ? errorCode : null,
    requestId: failed ? requestId : null,
    credential: CREDENTIAL_PATTERN.test(credential) ? credential : null,
    fallbackReason: FALLBACK_REASONS.includes(fallbackReason)
      ? fallbackReason
      : null,
    turns,
    durationMs,
    costUsd,
    maxTurns: COUNT_PATTERN.test(maxTurns) ? Number(maxTurns) : null,
    models: models.slice(0, MAX_MODELS),
    usage,
    windows,
  };
}

// The lane-outcome record v1 (docs/lane-outcome.md, schemas/
// lane-outcome.v1.schema.json). Written only when the lane id and a
// credential that maps to a kind are both present; `missing` names what is not.
const RECORD_MARKER = "lane-outcome ";
const LANE_ID_PATTERN = /^[a-z0-9][a-z0-9-]{0,63}$/u;
// Basis: docs/lane-outcome.md, "A record is at most 1,024 characters".
const RECORD_MAX_LENGTH = 1024;

// The record's closed failure classes (docs/lane-outcome.md, "Failure
// classes"). A caller's class outside this list is `other` in the record.
const FAILURE_CLASSES = [
  "auth",
  "credit-stop",
  "rate-limit",
  "overloaded",
  "max-turns",
  "timeout",
  "install-failed",
  "no-execution",
  "sandbox-unavailable",
  "skipped-validation",
  "incomplete",
  "review-unposted",
  "shell-failed",
  "no-credential",
  "no-outcome",
  "other",
];
// A Claude credential's secret name, the only shape `credential.secret` may
// take, so a value, token prefix or any other string never reaches a record.
const SECRET_NAME_PATTERN =
  /^(?:(?:[A-Z][A-Z0-9_]{0,75}_)?CLAUDE_CODE_OAUTH_TOKEN|[A-Z][A-Z0-9_]{0,84}_CLAUDE_API_KEY)$/u;
// The GitHub API counters the record reads, by api-budget token name.
const GITHUB_CALL_COUNTERS = [
  ["github-token", "githubToken"],
  ["lanes-app", "lanesApp"],
];
const RUN_ID_PATTERN = /^[1-9]\d{0,15}$/u;
const RUN_ATTEMPT_PATTERN = /^[1-9]\d{0,3}$/u;
const JOB_PATTERN = /^[A-Za-z_][A-Za-z0-9_-]{0,99}$/u;

// One api-budget token file's counts, as api-budget.bash's
// api_budget_emit_calls counts them: requests not answered 304, the 304
// answers, and the GraphQL requests among the first. Null when the file is
// absent or unreadable.
function callCounts(file) {
  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch {
    return null;
  }
  const counts = { requests: 0, graphql: 0, notModified: 0 };
  for (const line of text.split("\n")) {
    if (line === "") continue;
    const fields = line.trim().split(/\s+/u);
    if (fields[0] === "304") counts.notModified += 1;
    else counts.requests += 1;
    if (fields[5] === "graphql" || fields[1] === "graphql") counts.graphql += 1;
  }
  return counts;
}

function hash(text) {
  return crypto.createHash("sha256").update(text).digest("hex");
}

// The run context of one record: the run id and attempt, a trace id every
// record of the run attempt shares, a span id for this record, and the
// GitHub API calls the job made before the report. Each is null when its
// input is absent or out of shape; nothing is guessed.
function runContext({
  runId = "",
  runAttempt = "",
  job = "",
  laneId = "",
  credential = "",
  budgetDir = "",
} = {}) {
  const run = RUN_ID_PATTERN.test(runId) ? Number(runId) : null;
  const attempt = RUN_ATTEMPT_PATTERN.test(runAttempt)
    ? Number(runAttempt)
    : null;
  const traceId =
    run === null || attempt === null
      ? null
      : hash(`lane-outcome:${run}:${attempt}`).slice(0, 32);
  const spanId =
    traceId === null || !JOB_PATTERN.test(job)
      ? null
      : hash(`${traceId}:${job}:${laneId}:${credential}`).slice(0, 16);
  const calls =
    budgetDir === ""
      ? []
      : GITHUB_CALL_COUNTERS.map(([file, key]) => [
          key,
          callCounts(path.join(budgetDir, file)),
        ]).filter(([, counts]) => counts !== null);
  return {
    runId: run,
    runAttempt: attempt,
    traceId,
    spanId,
    githubCalls: calls.length > 0 ? Object.fromEntries(calls) : null,
  };
}

// The credential's kind and role from its secret name, or null.
function credentialFacts(secret) {
  if (secret === null || !SECRET_NAME_PATTERN.test(secret)) return null;
  const key = /^([A-Z][A-Z0-9_]*)_CLAUDE_API_KEY$/u.exec(secret);
  if (key) return { secret, kind: "api-key", role: key[1] };
  const token = /^(?:([A-Z][A-Z0-9_]*)_)?CLAUDE_CODE_OAUTH_TOKEN$/u.exec(
    secret,
  );
  if (!token) return null;
  return token[1] === undefined
    ? { secret, kind: "oauth-token" }
    : { secret, kind: "oauth-token", role: token[1] };
}

// The step's `outcome` input and the reported class, as an OpenTelemetry
// CICD task result.
function recordOutcome(outcome, failureClass) {
  if (failureClass === "skipped-validation") return "skip";
  if (outcome === "success") return failureClass === "" ? "success" : "failure";
  if (outcome === "cancelled") return "cancellation";
  if (outcome === "skipped") return "skip";
  return failureClass === "timeout" ? "timeout" : "failure";
}

// `recordClass` overrides the class in the record alone, for a branch whose
// step reports no failure class of its own (incomplete, skipped-validation).
// `shellFailed` flags a success whose allowed Bash calls all failed without
// failing it.
function factRecord(
  facts,
  {
    laneId = "",
    outcome = "",
    handoff = "",
    shellFailed = false,
    recordClass = facts.failureClass,
    context = {},
  },
) {
  const credential = credentialFacts(facts.credential);
  const missing = [
    ...(LANE_ID_PATTERN.test(laneId) ? [] : ["lane-id"]),
    ...(credential === null ? ["credential"] : []),
  ];
  if (missing.length > 0) return { record: null, missing };
  const record = present([
    ["v", 1],
    ["lane", laneId],
    ["outcome", recordOutcome(outcome, recordClass)],
    [
      "class",
      recordClass === ""
        ? null
        : FAILURE_CLASSES.includes(recordClass)
          ? recordClass
          : "other",
    ],
    ["credential", credential],
    ["handoff", handoff === "true" ? true : null],
    ["shellFailed", shellFailed === true ? true : null],
    ["fallback", present([["reason", facts.fallbackReason]])],
    [
      "resets",
      facts.resetsAt === null
        ? null
        : present([
            ["at", facts.resetsAt],
            ["window", facts.resetsWindow],
          ]),
    ],
    [
      "error",
      present([
        ["type", facts.errorType],
        ["code", facts.errorCode],
        ["requestId", facts.requestId],
      ]),
    ],
    ["turns", facts.turns !== null && facts.turns <= COUNT_MAX ? facts.turns : null],
    ["maxTurns", facts.maxTurns],
    ["durationMs", facts.durationMs],
    ["costUsd", facts.costUsd],
    ["runId", context.runId ?? null],
    ["runAttempt", context.runAttempt ?? null],
    ["traceId", context.traceId ?? null],
    ["spanId", context.spanId ?? null],
    ["githubCalls", context.githubCalls ?? null],
    ["usage", facts.usage],
    ["windows", facts.windows],
    ["models", facts.models.length > 0 ? facts.models : null],
  ]);
  // Past the limit the least needed facts go first, the GitHub calls last.
  for (const field of ["models", "usage", "windows", "githubCalls"]) {
    if (JSON.stringify(record).length <= RECORD_MAX_LENGTH) break;
    delete record[field];
  }
  return { record, missing };
}

// One annotation's lane-outcome record (null with `missing` when it cannot be
// written).
function laneReport(run, inputs = {}) {
  return factRecord(runFacts(run, inputs), inputs);
}

// The record as it sits in an annotation message: the marker and the JSON,
// or "" when there is no record.
function recordText(record) {
  return record === null ? "" : `${RECORD_MARKER}${JSON.stringify(record)}`;
}

module.exports = {
  apiErrorFacts,
  CLASS_PATTERN,
  classifyExecutionFile,
  COUNT_MAX,
  CREDENTIAL_PATTERN,
  creditStopResetsAt,
  FAILURE_CLASSES,
  FALLBACK_REASONS,
  failedShellCalls,
  isCreditStop,
  runContext,
  SECRET_NAME_PATTERN,
  LANE_ID_PATTERN,
  laneReport,
  limitStopFrom,
  MAX_MODELS,
  rateLimitWindows,
  readLegLog,
  readMessages,
  readRunRecord,
  recordText,
  WINDOW_PATTERN,
};
