export const MARKER = "lane-outcome ";
const MAX_LENGTH = 1024;

const NAME = /^[a-z0-9][a-z0-9-]{0,63}$/;
const ACTIVITY = /^(?=.{1,64}$)[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/;
const WINDOW = /^[a-z0-9_]{1,40}$/;
const SECRET = /^(?:(?:([A-Z][A-Z0-9_]{0,75})_)?CLAUDE_CODE_OAUTH_TOKEN|([A-Z][A-Z0-9_]{0,84})_CLAUDE_API_KEY)$/;
const MODEL = /^claude-[a-z0-9.-]{1,56}(?:\[1m\])?$/;
const HEX32 = /^[0-9a-f]{32}$/;
const HEX16 = /^[0-9a-f]{16}$/;
const JOB_KEY = /^[A-Za-z_][A-Za-z0-9_-]{0,99}$/;
const OUTCOMES = new Set(["success", "failure", "timeout", "skip", "cancellation", "error"]);
const CLASS = /^(?=.{1,40}$)[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
const REASONS = new Set(["credit-stop", "auth", "no-key", "limit-stop"]);
const STATUSES = new Set(["allowed", "allowed_warning", "rejected"]);

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const count = (max = Number.MAX_SAFE_INTEGER, min = 0) => (value) => Number.isSafeInteger(value) && value >= min && value <= max;
const matches = (pattern) => (value) => typeof value === "string" && pattern.test(value);
const oneOf = (set) => (value) => set.has(value);
const nullable = (check) => (value) => value === null || check(value);
const shape = (fields, required = []) => (value) => {
  if (!isObject(value) || !required.every((key) => Object.hasOwn(value, key))) {
    return false;
  }
  const kept = {};
  for (const [key, check] of Object.entries(fields)) {
    if (!Object.hasOwn(value, key)) {
      continue;
    }
    const result = check(value[key]);
    if (result === false) {
      return false;
    }
    kept[key] = result === true ? value[key] : result;
  }
  return kept;
};

const calls = shape({ requests: count(), graphql: count(), notModified: count() }, ["requests", "graphql", "notModified"]);
const window = shape({ utilization: (v) => typeof v === "number" && v >= 0 && v <= 1, resetsAt: matches(ISO), status: oneOf(STATUSES) }, ["status"]);
const credentialShape = shape({ secret: matches(SECRET), kind: oneOf(new Set(["oauth-token", "api-key"])), role: matches(/^[A-Z][A-Z0-9_]{0,99}$/) }, ["secret", "kind"]);
const credential = (value) => {
  const kept = credentialShape(value);
  if (!kept) {
    return false;
  }
  const [, tokenRole, keyRole] = SECRET.exec(kept.secret);
  return kept.kind === (keyRole ? "api-key" : "oauth-token") && (kept.role === undefined || kept.role === (keyRole ?? tokenRole)) && kept;
};

const RECORD = shape(
  {
    v: (value) => value === 1,
    lane: matches(NAME),
    activity: matches(ACTIVITY),
    outcome: oneOf(OUTCOMES),
    class: matches(CLASS),
    credential,
    handoff: (value) => typeof value === "boolean",
    shellFailed: (value) => typeof value === "boolean",
    fallback: shape({ reason: oneOf(REASONS) }),
    resets: shape({ at: matches(ISO), window: matches(WINDOW) }),
    error: shape({
      type: nullable(matches(/^[a-z_]{1,40}$/)),
      code: nullable(matches(/^[a-z0-9_]{1,64}$/)),
      status: nullable(count(599, 100)),
      requestId: nullable(matches(/^req_[A-Za-z0-9]{8,64}$/)),
    }),
    turns: count(999999),
    maxTurns: count(999999),
    durationMs: count(),
    runId: count(Number.MAX_SAFE_INTEGER, 1),
    runAttempt: count(9999, 1),
    traceId: matches(HEX32),
    spanId: matches(HEX16),
    jobId: matches(JOB_KEY),
    githubCalls: shape({ githubToken: calls, lanesApp: calls }),
    costUsd: (value) => typeof value === "number" && Number.isFinite(value) && value >= 0,
    usage: shape({ input: count(), output: count(), cacheRead: count(), cacheCreation: count() }),
    windows: shape({ five_hour: window, seven_day: window, seven_day_opus: window, seven_day_sonnet: window, overage: window }),
    models: (value) => Array.isArray(value) && value.length <= 8 && value.every(matches(MODEL)),
  },
  ["v", "lane", "outcome", "credential"],
);

const withoutBadJobId = (value) =>
  isObject(value) && Object.hasOwn(value, "jobId") && !matches(JOB_KEY)(value.jobId) ? Object.fromEntries(Object.entries(value).filter(([key]) => key !== "jobId")) : value;

export function validRecord(value) {
  const kept = RECORD(withoutBadJobId(value));
  if (!kept || (kept.outcome !== "success" && !Object.hasOwn(kept, "class"))) {
    return null;
  }
  const { activity, ...record } = kept;
  return JSON.stringify(record).length <= MAX_LENGTH ? kept : null;
}

export function readRecord(text) {
  const source = String(text ?? "");
  const at = source.indexOf(MARKER);
  if (at < 0) {
    return null;
  }
  const rest = source.slice(at + MARKER.length, at + MARKER.length + MAX_LENGTH + 200);
  for (let end = rest.indexOf("}"); end >= 0; end = rest.indexOf("}", end + 1)) {
    try {
      return validRecord(JSON.parse(rest.slice(0, end + 1)));
    } catch {
    }
  }
  return null;
}
