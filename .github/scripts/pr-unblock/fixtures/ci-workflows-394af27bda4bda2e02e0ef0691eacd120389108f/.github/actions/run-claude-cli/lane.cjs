// run-claude-cli: run one prompt with headless `claude -p` on exactly one
// credential: the lane's API key, its subscription token, or the central
// fallback subscription token.
//
// Subcommands (argv[2]):
//   verify-isolation  fail closed unless managed settings are root-owned and
//                     pinned, sudo and docker are gone, bubblewrap can create
//                     a PID namespace, socat runs (unless the sandbox input
//                     is false) and no loader, TLS or proxy variable is set
//   install           resolve the CLI version, install it from the public
//                     registry outside any checkout's .npmrc, and fail closed
//                     unless npm verifies both packages' registry signatures
//                     and the binary matches Anthropic's GPG-signed manifest
//   run               run the one leg and write the action's outputs
//
// Security contract:
//   - One leg per invocation: readConfig fails closed unless exactly one of
//     the three credentials is set. A caller that falls back to the
//     subscription after a key leg hands off (a credit stop, or class auth
//     with api_error_status 401 or 402, NEXT_STEPS) runs a second job, on a
//     fresh runner, gated on this one's handoff output being `true`. A 403
//     stops the run with its error type, error_code and request_id.
//   - A subscription leg hands off only when fallback-ready is `true`: on a
//     limit stop (a rejected rate_limit_event with its reset; a CLI that
//     starts waiting out a reset past the watchdog wait cap is stopped at
//     once), a credit stop
//     (classify.cjs isCreditStop) or a 401 or 402. The caller then runs the
//     fallback leg, on FALLBACK_SECRET, as a third job; that leg is the last
//     and never hands off. handoff-reason names the stop. fallback-ready
//     `handoff-only` hands off on the same stops with no further leg: the
//     caller ends on the handoff.
//   - legEnv copies the step environment and removes every credential and
//     file-command VARIABLE, then sets the leg's one credential. That is a
//     denylist, not a sandbox: code the leg runs (a Bash tool call, a hook)
//     runs as the runner user.
//   - Unless the sandbox input is `false`, cliArgs passes SANDBOX_SETTINGS
//     with --settings: Bash runs in Claude Code's sandbox with no unsandboxed
//     retry and network only to github.com and api.github.com, and the CLI
//     exits at startup when the sandbox cannot start (failIfUnavailable).
//   - Every file-command file the step was given is bound read-only for the
//     leg (and anything it leaves running), restored to its exact content
//     once the leg ends, and only then does run write the action's own
//     outputs, lane-class included, and summary.
//   - The CLI install tree and _work/_actions have their write bits removed
//     before the leg and restored after it.
//   - Caller rule: a lane that gives the model unrestricted Bash, or any
//     code-running tool beyond fixed read-only command rules, runs this
//     action in a job that holds no other secret or write token, and does
//     its reporting and uploads in a downstream job that validates its
//     inputs. A lane whose Bash is limited to fixed read-only rules may stay
//     in one job.
//   - Input contract: no head code runs in the job before this action, and
//     the step environment holds no NODE_OPTIONS, LD_PRELOAD,
//     LD_LIBRARY_PATH, BASH_ENV, NODE_EXTRA_CA_CERTS,
//     NODE_TLS_REJECT_UNAUTHORIZED or *_PROXY other than NO_PROXY
//     (verifyEnvironment, checked before the install and again before the
//     leg).
//   - The CLI runs in --restricted mode: code-running tools only when the
//     tools input names them, no user, project or local settings, file tools
//     confined to the working directories, no bypassPermissions.
//   - Only the key leg can end in `credit-stop` (classify.cjs isCreditStop),
//     judged from structured fields; a subscription leg's credit stop keeps
//     its class and shows only as handoff-reason.
//   - The managed settings pin env.ANTHROPIC_BASE_URL to the public API. The
//     loopback-base-url opt-in instead pins exactly http://127.0.0.1:<port>
//     or http://[::1]:<port>, a key proxy the caller runs, and only on an
//     api-key leg (managed-settings.cjs, readConfig).
//   - Secret names are derived from the role, or are FALLBACK_SECRET, and
//     never taken from input.
//   - The CLI's stdout is captured in memory, read line by line for a
//     rejected rate_limit_event and, unless the live-log input is `false`,
//     for the live view, and written to files only after the leg exits. The
//     live view prints only assistant text lines and tool calls (each
//     argument value cut to LIVE_VALUE_CHARS, newlines collapsed), each
//     prefixed with its turn; a line holding a credential prints as
//     LIVE_WITHHELD. Never a tool result, thinking block, system or user
//     message, the result text, or an assistant message the CLI wrote as an
//     error. The CLI's stderr, the live view and closed-pattern tokens reach
//     the job log, inside ::stop-commands::; the job summary shows only
//     closed tokens.
//   - The log file is written only after a scan finds no credential in it.
//     It alone keeps a CLI-authored error line. The execution file is
//     scanned the same way and kept either way, since callers parse it;
//     execution-file-clean reports the scan.
//   - Telemetry is off unless the otel-receiver input is `true`. Then the leg
//     exports traces and logs to a receiver inside this process, on 127.0.0.1
//     only (otlp-receiver.cjs), and every inherited telemetry destination is
//     removed from its environment. What arrives stays in memory until the leg
//     ends, is written only after a scan finds no credential in it, and is
//     never printed. A receiver failure warns and never changes the leg's
//     outcome.
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { spawn: spawnAsync, spawnSync } = require("node:child_process");

const {
  apiErrorFacts,
  classifyExecutionFile,
  creditStopResetsAt,
  isCreditStop,
  limitStopFrom,
  rateLimitWindows,
  readMessages,
  readRunRecord,
  runContext,
} = require("../report-lane-outcome/classify.cjs");
const {
  resolveNpmToolVersion,
} = require("../../scripts/resolve-npm-tool-version.cjs");
const {
  PINNED_BASE_URL,
  expectedBaseUrl,
  settingsProblem,
} = require("./managed-settings.cjs");
const { startOtlpReceiver } = require("./otlp-receiver.cjs");

const CLI_PACKAGE = "@anthropic-ai/claude-code";
const NAME_PATTERN = /^[A-Z][A-Z0-9_]{0,99}$/u;
const KEBAB_PATTERN = /^[a-z][a-z0-9-]{0,39}$/u;
const MODEL_PATTERN = /^[\w.:@[\]-]{1,100}$/u;
const EFFORT_PATTERN = /^[a-z]{1,20}$/u;
const TOOL_NAME_PATTERN = /^[\w.:-]{1,100}$/u;
const PERMISSION_MODES = new Set([
  "default",
  "acceptEdits",
  "plan",
  "auto",
  "dontAsk",
]);
// Every variable that selects or carries a credential. legEnv removes all of
// them, then sets the leg's one.
const CREDENTIAL_VARIABLES = [
  "ANTHROPIC_API_KEY",
  "ANTHROPIC_AUTH_TOKEN",
  "CLAUDE_CODE_OAUTH_TOKEN",
  "CLAUDE_CODE_USE_BEDROCK",
  "CLAUDE_CODE_USE_VERTEX",
  "CLAUDE_CODE_USE_FOUNDRY",
  "CLAUDE_CODE_ENTRYPOINT",
  "LANE_API_KEY",
  "LANE_SUBSCRIPTION_TOKEN",
  "LANE_FALLBACK_TOKEN",
];
// The org secret holding the central fallback subscription's token, the same
// for every role.
const FALLBACK_SECRET = "FALLBACK_CLAUDE_CODE_OAUTH_TOKEN";
const KEY_SHAPE = /sk-ant-[A-Za-z0-9_-]{8,}/u;
// Workflow file-command variables. legEnv removes them, so a leg cannot set
// environment, path, outputs, state or summary for later steps.
const FILE_COMMAND_VARIABLES = [
  "GITHUB_ENV",
  "GITHUB_PATH",
  "GITHUB_OUTPUT",
  "GITHUB_STATE",
  "GITHUB_STEP_SUMMARY",
];
// The most CLI stdout the leg may produce; past it the leg is killed and ends
// with class `other`.
const MAX_LEG_STDOUT_BYTES = 256 * 1024 * 1024;
const LIVE_VALUE_CHARS = 200;
const LIVE_WITHHELD = "[line withheld: it matched the credential check]";
const OTEL_FILE = "otel.jsonl";
// Inherited settings that could send the leg's telemetry anywhere but the
// receiver, or put prompt and tool content in it
// (https://code.claude.com/docs/en/monitoring-usage).
const OTEL_INHERITED =
  /^(?:OTEL_|CLAUDE_CODE_OTEL_|BETA_TRACING_ENDPOINT$|ENABLE_BETA_TRACING_DETAILED$)/u;
// Closed texts for the step's one telemetry warning; none carries telemetry.
const OTEL_WARNINGS = {
  start:
    "the telemetry receiver did not start, so this leg ran without telemetry",
  empty: "the telemetry receiver got nothing from this leg",
  capped:
    "the telemetry limit was reached, so part of this leg's telemetry is left out",
  credential: "the leg's telemetry held a credential and is left out",
  failed: "the leg's telemetry could not be kept",
};
const NPM_REGISTRY = "https://registry.npmjs.org/";
// Release manifest location and signing key, as
// https://code.claude.com/docs/en/setup#binary-integrity-and-code-signing
// gives them. Releases from 2.1.89 on carry a signed manifest.
const RELEASES_URL = "https://downloads.claude.ai/claude-code-releases";
const SIGNING_KEY_URL = "https://downloads.claude.ai/keys/claude-code.asc";
const SIGNING_KEY_FINGERPRINT = "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"; // gitleaks:allow (public key fingerprint)
const DOCKER_SOCKET = "/var/run/docker.sock";
const BWRAP_PROBE = ["--unshare-pid", "--dev-bind", "/", "/", "true"];
// Claude Code's sandbox, passed with --settings unless the sandbox input is
// `false`: Bash runs under bubblewrap, with no unsandboxed retry, the CLI exits
// at startup rather than run Bash unsandboxed when the sandbox cannot start,
// and its network reaches only GitHub through the sandbox's proxy, which needs
// socat (https://code.claude.com/docs/en/sandboxing).
const SANDBOX_SETTINGS = JSON.stringify({
  sandbox: {
    enabled: true,
    allowUnsandboxedCommands: false,
    failIfUnavailable: true,
    network: { allowedDomains: ["github.com", "api.github.com"] },
  },
});
// Variables that load code into node or bash, or redirect or weaken TLS, so
// head code that set them could read a leg's credential. Any name ending in
// _PROXY counts too, NO_PROXY excepted. The ubuntu-24.04 image sets none of
// them (images/ubuntu in actions/runner-images at ee1ff45: its environment
// tables and build scripts name no such variable), so any one set is the
// caller's.
const UNSAFE_VARIABLES = new Set([
  "NODE_OPTIONS",
  "LD_PRELOAD",
  "LD_LIBRARY_PATH",
  "BASH_ENV",
  "NODE_EXTRA_CA_CERTS",
  "NODE_TLS_REJECT_UNAUTHORIZED",
]);
// What each class means for the run. `statuses`: the numeric
// api_error_status values of an auth class that hand off (handoffReason),
// never an error-type string, which errors[] text could carry. `note`: the
// job summary's closed token, the named stop and what happens next.
const NEXT_STEPS = {
  "": { note: "" },
  "credit-stop": {
    note: "credits used up: the subscription job runs; the owner rotates a key by hand when needed",
  },
  // 401 (key disabled or deleted) and 402 (billing) hand off. 403
  // (permission) does not: the key reached the API but may not use the
  // resource, a setting the owner fixes, and handing off would hide it. An
  // auth class with no numeric status does not hand off either.
  auth: {
    statuses: [401, 402],
    note: "credential unusable: 401 or 402 hands off to the subscription job, 403 (permission) stops the run; the owner fixes the key by hand",
  },
  "rate-limit": { note: "limit stop: rerun after the reset" },
  overloaded: { note: "API overloaded: rerun later" },
  "max-turns": {
    note: "turn cap: raise max-turns or narrow the task",
  },
  timeout: {
    note: "leg timeout: raise leg-timeout-minutes or narrow the task",
  },
  other: { note: "see the step log" },
};

// The Stop note when a leg hands off to the fallback job, by handoff reason.
// A subscription credit stop keeps class other, so the reason picks the note.
const FALLBACK_NOTES = {
  auth: "credential refused: the fallback job runs instead; the owner replaces the secret",
  "credit-stop": "credits used up: the fallback job runs instead",
  "limit-stop": "limit stop: the fallback job runs instead",
};

// The Stop note when a subscription leg hands off with fallback-ready
// `handoff-only`, so no leg runs after it.
const LAST_LEG_NOTES = {
  auth: "credential refused: handed off, no further leg runs; the owner replaces the secret",
  "credit-stop": "credits used up: handed off, no further leg runs",
  "limit-stop": "limit stop: handed off, no further leg runs",
};

function nextStep(failureClass) {
  return Object.hasOwn(NEXT_STEPS, failureClass)
    ? NEXT_STEPS[failureClass]
    : NEXT_STEPS.other;
}

// Why the leg hands off, or "" when it does not. A key leg hands off on a
// credit stop or a 401 or 402 (NEXT_STEPS). A subscription leg hands off
// only when the caller has a fallback leg (fallbackReady): on a limit stop, a
// rejected rate_limit_event with its reset (`limitStop`), on a credit stop
// whatever its class (`creditStop`), or on a 401 or 402. The fallback leg is
// the last one. `apiErrorStatus` is the last message's numeric
// api_error_status.
function handoffReason(
  leg,
  failureClass,
  apiErrorStatus,
  { fallbackReady = false, limitStop = false, creditStop = false } = {},
) {
  const refused =
    failureClass === "auth" && NEXT_STEPS.auth.statuses.includes(apiErrorStatus);
  if (leg.leg === "api-key") {
    if (failureClass === "credit-stop") return "credit-stop";
    return refused ? "auth" : "";
  }
  if (leg.leg !== "subscription" || !fallbackReady || failureClass === "") {
    return "";
  }
  if (creditStop) return "credit-stop";
  if (refused) return "auth";
  return failureClass === "rate-limit" && limitStop ? "limit-stop" : "";
}

class LaneError extends Error {
  constructor(message) {
    super(message);
    this.name = "LaneError";
  }
}

// The sandbox input: `true` or empty turns it on, `false` turns it off, and
// any other value fails the step.
function switchedOn(env, name, label) {
  const value = (env[name] ?? "").trim();
  if (!["", "true", "false"].includes(value)) {
    throw new LaneError(
      `${label} ${JSON.stringify(value)} is not true, false or empty`,
    );
  }
  return value !== "false";
}

function sandboxEnabled(env) {
  return switchedOn(env, "LANE_SANDBOX", "sandbox");
}

// The otel-receiver input: only `true` turns it on.
function otelReceiverOn(env) {
  const value = (env.LANE_OTEL_RECEIVER ?? "").trim();
  if (!["", "true", "false"].includes(value)) {
    throw new LaneError(
      `otel-receiver ${JSON.stringify(value)} is not true, false or empty`,
    );
  }
  return value === "true";
}

function required(env, name, pattern, label) {
  const value = (env[name] ?? "").trim();
  if (!pattern.test(value)) {
    throw new LaneError(`${label} ${JSON.stringify(value)} is not valid`);
  }
  return value;
}

// The run's settings from the action's environment, each checked against a
// closed pattern, so nothing unchecked reaches the CLI's argv or the log.
function readConfig(env) {
  const role = required(env, "LANE_ROLE", KEBAB_PATTERN, "role");
  const supplied = [
    ["api-key", env.LANE_API_KEY ?? "", "CLAUDE_API_KEY"],
    ["subscription", env.LANE_SUBSCRIPTION_TOKEN ?? "", "CLAUDE_CODE_OAUTH_TOKEN"],
    ["fallback", env.LANE_FALLBACK_TOKEN ?? "", null],
  ].filter(([, value]) => value !== "");
  if (supplied.length !== 1) {
    throw new LaneError(
      `${supplied.length === 0 ? "no credential" : `${supplied.length} credentials`}: set exactly one of api-key, subscription-token and fallback-token, and run each leg as its own job`,
    );
  }
  const [[legName, value, suffix]] = supplied;
  // The role's name, `<ROLE>_<suffix>` with the role upper-snake, is the only
  // one; the fallback leg's is FALLBACK_SECRET.
  const name =
    suffix === null
      ? FALLBACK_SECRET
      : `${role.toUpperCase().replaceAll("-", "_")}_${suffix}`;
  if (!NAME_PATTERN.test(name)) {
    throw new LaneError(
      `${legName} secret name ${JSON.stringify(name)} is not an upper-case secret name`,
    );
  }
  // A loopback base URL routes the leg through a key proxy the caller runs.
  // Anthropic bars developers from intermediating Claude.ai credentials
  // (https://code.claude.com/docs/en/legal-and-compliance), so both OAuth
  // legs refuse it. What the proxy injects upstream is the caller's: it must
  // hold only a Console key, which this check cannot see.
  const base = expectedBaseUrl(env.LANE_LOOPBACK_BASE_URL);
  if (base.problem !== undefined) throw new LaneError(base.problem);
  if (base.baseUrl !== PINNED_BASE_URL && legName !== "api-key") {
    throw new LaneError(
      `loopback-base-url is allowed only on an api-key leg, not the ${legName} leg: an OAuth token may not be routed through a proxy the caller runs`,
    );
  }
  const permissionMode = (env.LANE_PERMISSION_MODE ?? "").trim();
  if (!PERMISSION_MODES.has(permissionMode)) {
    throw new LaneError(
      `permission-mode ${JSON.stringify(permissionMode)} is not one of ${[...PERMISSION_MODES].join(", ")}`,
    );
  }
  const fallbackReady = (env.LANE_FALLBACK_READY ?? "").trim();
  if (!["", "true", "false", "handoff-only"].includes(fallbackReady)) {
    throw new LaneError(
      `fallback-ready ${JSON.stringify(fallbackReady)} is not true, handoff-only, false or empty`,
    );
  }
  const legTimeout = (env.LANE_LEG_TIMEOUT_MINUTES ?? "").trim();
  if (legTimeout !== "" && !/^[1-9]\d{0,3}$/u.test(legTimeout)) {
    throw new LaneError(
      `leg-timeout-minutes ${JSON.stringify(legTimeout)} is not valid`,
    );
  }
  const promptFile = (env.LANE_PROMPT_FILE ?? "").trim();
  if (promptFile === "" || !fs.existsSync(promptFile)) {
    throw new LaneError(
      `prompt-file ${JSON.stringify(promptFile)} does not exist`,
    );
  }
  const allowedTools = toolLines(env.LANE_ALLOWED_TOOLS, "allowed-tools");
  const disallowedTools = toolLines(
    env.LANE_DISALLOWED_TOOLS,
    "disallowed-tools",
  );
  const tools = toolLines(env.LANE_TOOLS, "tools");
  const pluginDirs = dirLines(
    env.LANE_PLUGIN_DIRS,
    "plugin-dirs",
    env.GITHUB_WORKSPACE,
  );
  const addDirs = dirLines(env.LANE_ADD_DIRS, "add-dirs", env.GITHUB_WORKSPACE);
  const schemaFile = (env.LANE_JSON_SCHEMA_FILE ?? "").trim();
  let jsonSchema = "";
  if (schemaFile !== "") {
    try {
      jsonSchema = JSON.stringify(
        JSON.parse(fs.readFileSync(schemaFile, "utf8")),
      );
    } catch {
      throw new LaneError(
        `json-schema-file ${JSON.stringify(schemaFile)} is not a readable JSON file`,
      );
    }
  }
  return {
    leg: { leg: legName, name, value },
    baseUrl: base.baseUrl,
    // A subscription leg may hand off; handoffOnly: no leg runs after it.
    fallbackReady: fallbackReady === "true" || fallbackReady === "handoff-only",
    handoffOnly: fallbackReady === "handoff-only",
    lane: required(env, "LANE_NAME", KEBAB_PATTERN, "lane"),
    role,
    model: required(env, "LANE_MODEL", MODEL_PATTERN, "model"),
    // Empty keeps the model's default effort.
    effort:
      (env.LANE_EFFORT ?? "").trim() === ""
        ? ""
        : required(env, "LANE_EFFORT", EFFORT_PATTERN, "effort"),
    maxTurns: required(env, "LANE_MAX_TURNS", /^[1-9]\d{0,5}$/u, "max-turns"),
    permissionMode,
    sandbox: sandboxEnabled(env),
    disallowMcp: switchedOn(env, "LANE_DISALLOW_MCP", "disallow-mcp"),
    liveLog: switchedOn(env, "LANE_LIVE_LOG", "live-log"),
    otelReceiver: otelReceiverOn(env),
    watchdogMaxWaitMs: required(
      env,
      "LANE_WATCHDOG_MAX_WAIT_MS",
      /^[1-9]\d{0,9}$/u,
      "watchdog-max-wait-ms",
    ),
    legTimeoutMs: legTimeout === "" ? 0 : Number(legTimeout) * 60_000,
    cliVersion: required(
      env,
      "LANE_CLI_VERSION",
      /^\d+\.\d+\.\d+$/u,
      "cli-version",
    ),
    cliPath: required(env, "LANE_CLI_PATH", /^\/.+/u, "cli path"),
    promptFile,
    preamble: env.LANE_PREAMBLE ?? "",
    allowedTools,
    disallowedTools,
    tools,
    pluginDirs,
    addDirs,
    jsonSchema,
    workDir: required(env, "LANE_WORK_DIR", /^\/.+/u, "work dir"),
    runId: (env.GITHUB_RUN_ID ?? "").trim(),
  };
}

// `latest` asks the registry for the newest release; anything else must be an
// exact version. Either way the value passes the shared exact-version check before it is
// installed.
function resolveCliVersion(input, npmView) {
  const wanted = (input ?? "").trim() || "latest";
  const candidate =
    wanted === "latest" ? String(npmView() ?? "").trim() : wanted;
  // An empty candidate would take the resolver's fallback; there is none here.
  let resolved;
  try {
    resolved = resolveNpmToolVersion({
      versionInput: candidate,
      fallbackVersion: "0.0.0",
      packageName: CLI_PACKAGE,
      packageJsonPath: "/nonexistent/package.json",
    });
  } catch (error) {
    throw new LaneError(`cli-version: ${error.message}`);
  }
  const { version, source } = resolved;
  if (source !== "input") {
    throw new LaneError(
      `cli-version must resolve to an exact major.minor.patch, got ${JSON.stringify(candidate)}`,
    );
  }
  return version;
}

// The leg's W3C trace context, under the run attempt's lane-outcome trace id;
// null when the run id or attempt is absent or out of shape. The parent id is
// this leg's own: the lane-outcome spanId hashes report-lane-outcome's lane-id,
// which this action never receives. Flag 01 (sampled) keeps the leg's spans
// under a parent-based sampler.
function traceParent(baseEnv, leg, config) {
  const { traceId } = runContext({
    runId: baseEnv.GITHUB_RUN_ID,
    runAttempt: baseEnv.GITHUB_RUN_ATTEMPT,
  });
  if (traceId === null) return null;
  const parentId = crypto
    .createHash("sha256")
    .update(
      `run-claude-cli:${traceId}:${baseEnv.GITHUB_JOB}:${config.lane}:${leg.name}`,
    )
    .digest("hex")
    .slice(0, 16);
  return `00-${traceId}-${parentId}-01`;
}

// The CLI environment for the leg: every credential and file-command
// variable and any inherited trace context removed, then only the leg's
// credential and the run's trace context set. With a receiver's endpoint, the
// leg exports traces and logs there as OTLP/HTTP JSON; prompt and tool content
// stay redacted, the CLI's default.
function legEnv(baseEnv, leg, config, otelEndpoint = null) {
  const env = { ...baseEnv };
  for (const name of CREDENTIAL_VARIABLES) delete env[name];
  for (const name of FILE_COMMAND_VARIABLES) delete env[name];
  delete env.TRACEPARENT;
  delete env.TRACESTATE;
  const traceparent = traceParent(baseEnv, leg, config);
  if (traceparent !== null) env.TRACEPARENT = traceparent;
  if (leg.leg === "api-key") env.ANTHROPIC_API_KEY = leg.value;
  else env.CLAUDE_CODE_OAUTH_TOKEN = leg.value;
  env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB = "1";
  env.CLAUDE_CODE_RETRY_WATCHDOG = "1";
  env.CLAUDE_CODE_RETRY_WATCHDOG_MAX_WAIT_MS = config.watchdogMaxWaitMs;
  if (otelEndpoint !== null) {
    for (const name of Object.keys(env)) {
      if (OTEL_INHERITED.test(name)) delete env[name];
    }
    Object.assign(env, {
      CLAUDE_CODE_ENABLE_TELEMETRY: "1",
      CLAUDE_CODE_ENHANCED_TELEMETRY_BETA: "1",
      OTEL_TRACES_EXPORTER: "otlp",
      OTEL_LOGS_EXPORTER: "otlp",
      OTEL_METRICS_EXPORTER: "none",
      OTEL_EXPORTER_OTLP_PROTOCOL: "http/json",
      OTEL_EXPORTER_OTLP_ENDPOINT: otelEndpoint,
    });
  }
  return env;
}

function cliArgs(config) {
  const args = [
    "-p",
    "--output-format",
    "stream-json",
    "--verbose",
    "--model",
    config.model,
    ...(config.effort === "" ? [] : ["--effort", config.effort]),
    "--max-turns",
    config.maxTurns,
    "--permission-mode",
    config.permissionMode,
    "--permission-prompts",
    "none",
    "--restricted",
    "--strict-mcp-config",
    "--no-session-persistence",
    // Under --restricted the CLI loads only managed settings and --settings,
    // and no input passes other flag settings, so there is nothing to merge.
    ...(config.sandbox ? ["--settings", SANDBOX_SETTINGS] : []),
  ];
  // Under --restricted a plugin's own files are readable only inside a
  // working directory, so each plugin directory is added as one too.
  const pluginDirs = config.pluginDirs ?? [];
  for (const dir of pluginDirs) args.push("--plugin-dir", dir);
  for (const dir of new Set([...pluginDirs, ...(config.addDirs ?? [])])) {
    args.push("--add-dir", dir);
  }
  if (config.tools.length > 0) args.push("--tools", config.tools.join(","));
  if (config.jsonSchema !== "") args.push("--json-schema", config.jsonSchema);
  const disallowedTools = [...(config.disallowedTools ?? [])];
  if (config.disallowMcp && !disallowedTools.includes("mcp__*")) {
    disallowedTools.push("mcp__*");
  }
  if (disallowedTools.length > 0) {
    args.push("--disallowedTools", ...disallowedTools);
  }
  if (config.allowedTools.length > 0) {
    args.push("--allowedTools", ...config.allowedTools);
  }
  return args;
}

// The input's non-blank lines, trimmed.
function inputLines(text) {
  return (text ?? "")
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
}

function toolLines(text, label) {
  const rules = inputLines(text);
  if (rules.some((rule) => rule.startsWith("-"))) {
    throw new LaneError(`${label} entries may not start with '-'`);
  }
  return rules;
}

// Directory lines, one per line, each resolved against GITHUB_WORKSPACE (an
// absolute one as written) and kept only when it has no `..` part and its
// real path is an existing directory inside the workspace's real path.
function dirLines(text, label, workspace) {
  const entries = inputLines(text);
  if (entries.length === 0) return [];
  if ((workspace ?? "").trim() === "") {
    throw new LaneError(`${label} needs GITHUB_WORKSPACE to resolve against`);
  }
  const root = fs.realpathSync(workspace.trim());
  return entries.map((entry) => {
    if (entry.split(/[\\/]/u).includes("..")) {
      throw new LaneError(
        `${label} entry ${JSON.stringify(entry)} has a '..' part`,
      );
    }
    let resolved;
    try {
      resolved = fs.realpathSync(path.resolve(root, entry));
    } catch {
      resolved = "";
    }
    if (resolved === "" || !fs.statSync(resolved).isDirectory()) {
      throw new LaneError(
        `${label} entry ${JSON.stringify(entry)} is not an existing directory`,
      );
    }
    if (resolved !== root && !resolved.startsWith(`${root}${path.sep}`)) {
      throw new LaneError(
        `${label} entry ${JSON.stringify(entry)} must resolve inside GITHUB_WORKSPACE`,
      );
    }
    return resolved;
  });
}

function promptText(config) {
  const prompt = fs.readFileSync(config.promptFile, "utf8");
  if (prompt.trim() === "") throw new LaneError("prompt-file is empty");
  const preamble = config.preamble.trim();
  return preamble === "" ? prompt : `${preamble}\n\n${prompt}`;
}

// Stream JSON lines into the JSON array claude-code-action's execution_file
// holds, so classify.cjs reads both the same way. Unparsable lines drop.
function linesToMessages(text) {
  const messages = [];
  for (const line of text.split("\n")) {
    if (line.trim() === "") continue;
    try {
      messages.push(JSON.parse(line));
    } catch {
      // A non-JSON line (a stray warning) carries no structured fact.
    }
  }
  return messages;
}

function finalResult(messages) {
  return messages.findLast((message) => message?.type === "result");
}

// The last message's numeric api_error_status, the one classify.cjs reads,
// or null.
function apiErrorStatus(messages) {
  const status = messages.at(-1)?.api_error_status;
  return Number.isInteger(status) ? status : null;
}

// The CLI's first error line, only when classify proved it is the CLI's own
// text (a credit stop or a limit stop with no model output). Workflow
// commands are neutralized and the line is cut short. It goes to the scanned
// log only, never the job summary.
function cliMessage(messages, failureClass) {
  if (failureClass !== "credit-stop" && failureClass !== "rate-limit")
    return null;
  const result = finalResult(messages);
  const assistants = messages.filter((m) => m?.type === "assistant");
  const modelWrote =
    assistants.some((m) => typeof m.error !== "string") ||
    (result?.usage?.output_tokens ?? 0) !== 0;
  if (modelWrote || typeof result?.result !== "string") return null;
  const line = result.result.split("\n")[0].replaceAll("::", ": :").trim();
  return line === "" ? null : line.slice(0, 200);
}

function legRecord({
  config,
  leg,
  startedAt,
  endedAt,
  exitCode,
  messages,
  failureClass,
  resets,
  next,
  message = null,
}) {
  const result = finalResult(messages) ?? {};
  const denials = Array.isArray(result.permission_denials)
    ? result.permission_denials
    : [];
  const usage = result.usage ?? {};
  const count = (value) =>
    Number.isInteger(value) && value >= 0 ? value : null;
  const amount = (value) =>
    typeof value === "number" && Number.isFinite(value) && value >= 0
      ? value
      : null;
  const modelUsage =
    result.modelUsage && typeof result.modelUsage === "object"
      ? result.modelUsage
      : {};
  const facts = failureClass === "" ? {} : apiErrorFacts(messages);
  return {
    run_id: config.runId,
    lane: config.lane,
    role: config.role,
    leg: 1,
    credential: leg.leg,
    secret: leg.name,
    cli_version: config.cliVersion,
    model: config.model,
    permission_mode: config.permissionMode,
    started_at: startedAt,
    ended_at: endedAt,
    duration_ms: count(result.duration_ms),
    exit_code: exitCode,
    // The CLI's own list-price estimate; for attribution and trends, not billing.
    total_cost_usd: amount(result.total_cost_usd),
    models_used: Object.fromEntries(
      Object.entries(modelUsage).map(([name, u]) => [
        name,
        {
          cost_usd: amount(u?.costUSD),
          input_tokens: count(u?.inputTokens),
          output_tokens: count(u?.outputTokens),
        },
      ]),
    ),
    num_turns: count(result.num_turns),
    is_error: typeof result.is_error === "boolean" ? result.is_error : null,
    class: failureClass,
    api_error_status: apiErrorStatus(messages),
    error_type: facts.errorType ?? null,
    error_code: facts.errorCode ?? null,
    request_id: facts.requestId ?? null,
    message: message ?? cliMessage(messages, failureClass),
    resets,
    usage: {
      input_tokens: count(usage.input_tokens),
      output_tokens: count(usage.output_tokens),
      cache_read_input_tokens: count(usage.cache_read_input_tokens),
      cache_creation_input_tokens: count(usage.cache_creation_input_tokens),
    },
    // Each subscription window's highest utilization, newest reset and status.
    rate_limits: Object.fromEntries(
      Object.entries(rateLimitWindows(messages)).map(([window, info]) => [
        window,
        {
          utilization: info.utilization,
          resets_at: info.resetsAt,
          status: info.status,
        },
      ]),
    ),
    denials: {
      count: denials.length,
      tools: [
        ...new Set(
          denials
            .map((d) => d?.tool_name)
            .filter((name) => TOOL_NAME_PATTERN.test(name ?? "")),
        ),
      ],
    },
    next,
  };
}

// At or past this utilization a window warns, as an allowed_warning or
// rejected status does.
const USAGE_WARNING_UTILIZATION = 0.7;

// One warning annotation naming the leg's secret and every window near its
// limit, from the logged record's closed values; null when none is.
function usageWarning(record) {
  const near = Object.entries(record.rate_limits ?? {}).filter(
    ([, info]) =>
      info.status !== "allowed" ||
      (info.utilization ?? 0) >= USAGE_WARNING_UTILIZATION,
  );
  if (near.length === 0) return null;
  const windows = near.map(([window, info]) =>
    [
      `window=${window}`,
      info.utilization === null ? "" : `utilization=${info.utilization}`,
      `status=${info.status}`,
      info.resets_at === null ? "" : `resets=${info.resets_at}`,
    ]
      .filter(Boolean)
      .join(" "),
  );
  return `::warning title=run-claude-cli usage::${record.secret} is near a subscription usage limit: ${windows.join("; ")}`;
}

// True when the text holds any credential value or anything shaped like an
// Anthropic key.
function holdsCredential(text, secretValues) {
  if (KEY_SHAPE.test(text)) return true;
  return secretValues.some(
    (value) => value.length >= 8 && text.includes(value),
  );
}

// True only when the file reads and holds no credential; a missing or
// unreadable file is not clean.
function fileClean(file, secretValues) {
  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch {
    return false;
  }
  return !holdsCredential(text, secretValues);
}

// Classes a token leg's rejected rate_limit_event overrides: with retries on,
// the CLI waits out a rejected window until the leg timeout kills it, or
// ends with no error it can name.
const LIMIT_MASKED_CLASSES = new Set(["timeout", "other"]);

// Whether the run ended still held by a rejection: its newest rate_limit_event
// (any window) is rejected and no assistant or tool message came after it.
function rejectionInForce(messages) {
  const at = messages.findLastIndex(
    (message) => message?.type === "rate_limit_event",
  );
  return (
    at !== -1 &&
    messages[at].rate_limit_info?.status === "rejected" &&
    !messages
      .slice(at + 1)
      .some(
        (message) => message?.type === "assistant" || message?.type === "user",
      )
  );
}

// What the finished leg means for the run: success or a stop with a class.
// Only the key leg can end in a credit stop. A token leg that timed out or
// failed unnamed while a rejection was still in force is a limit stop
// (rate-limit with the rejected window's reset). A leg stopped on a reset
// past the wait cap (`limitResets`) is a limit stop with that reset.
function judgeLeg({
  leg,
  executionFile,
  exitCode,
  timedOut,
  maxTurns,
  limitResets = null,
}) {
  const messages = readMessages(executionFile) ?? [];
  if (limitResets !== null) {
    return { failureClass: "rate-limit", resets: limitResets, messages };
  }
  const result = finalResult(messages);
  if (!timedOut && exitCode === 0 && result && result.is_error === false) {
    return { failureClass: "", resets: null, messages };
  }
  let { failureClass } = classifyExecutionFile(executionFile, {
    timedOut,
    maxTurns,
    detectCreditStop: leg.leg === "api-key",
    exitCode,
  });
  if (failureClass === "credit-stop") {
    return { failureClass, resets: creditStopResetsAt(messages), messages };
  }
  const { resetsAt } = readRunRecord(executionFile);
  if (
    leg.leg !== "api-key" &&
    resetsAt !== null &&
    LIMIT_MASKED_CLASSES.has(failureClass) &&
    rejectionInForce(messages)
  ) {
    failureClass = "rate-limit";
  }
  return {
    failureClass,
    resets: failureClass === "rate-limit" ? resetsAt : null,
    messages,
  };
}

// The content of each file-command file the step was given, so restoreFiles
// can put back exactly what was there, whatever the leg appended or
// rewrote. run writes the action's own outputs and summary after the reset.
function snapshotFiles(baseEnv) {
  const snapshots = [];
  for (const name of FILE_COMMAND_VARIABLES) {
    const file = (baseEnv[name] ?? "").trim();
    if (file === "" || !fs.existsSync(file)) continue;
    snapshots.push({ file, content: fs.readFileSync(file) });
  }
  return snapshots;
}

function restoreFiles(snapshots) {
  for (const { file, content } of snapshots) {
    if (!fs.existsSync(file) || !fs.readFileSync(file).equals(content)) {
      fs.writeFileSync(file, content);
    }
  }
}

// What no leg may write: the CLI install under the work directory, the
// runner's action checkouts (`_work/_actions` beside RUNNER_WORKSPACE), and
// the step's file-command files. bwrap binds each read-only in the leg's mount
// namespace, which a process the leg leaves behind keeps after it ends.
function readOnlyPaths(config, baseEnv, files = []) {
  const runnerWorkspace = (baseEnv.RUNNER_WORKSPACE ?? "").trim();
  return [
    path.join(config.workDir, "cli"),
    runnerWorkspace === ""
      ? ""
      : path.join(path.dirname(runnerWorkspace), "_actions"),
    ...files,
  ].filter((dir) => dir !== "" && fs.existsSync(dir));
}

// Removes every write bit under each tree, recording each mode it changes in
// `modes` first, so restoreModes can put them back even after a partial lock.
// Symbolic links are left alone.
function lockTrees(dirs, modes) {
  const walk = (entry) => {
    const info = fs.lstatSync(entry);
    if (info.isSymbolicLink()) return;
    modes.push({ entry, mode: info.mode & 0o7777 });
    fs.chmodSync(entry, info.mode & 0o7555);
    if (info.isDirectory()) {
      for (const name of fs.readdirSync(entry)) walk(path.join(entry, name));
    }
  };
  for (const dir of dirs) walk(dir);
}

// The command the leg runs. With trees to protect, bwrap binds each one
// read-only over a view of the whole filesystem, so the leg cannot restore the
// write bits lockTrees removed. --die-with-parent kills the CLI when the leg's
// stop (a timeout, an overflow or a limit stop) kills bwrap, which forwards no
// signal.
function legCommand(config, readOnly) {
  if (readOnly.length === 0) return [config.cliPath, cliArgs(config)];
  return [
    "bwrap",
    [
      "--die-with-parent",
      "--dev-bind",
      "/",
      "/",
      ...readOnly.flatMap((dir) => ["--ro-bind", dir, dir]),
      "--",
      config.cliPath,
      ...cliArgs(config),
    ],
  ];
}

function restoreModes(modes) {
  for (const { entry, mode } of modes.toReversed()) {
    try {
      fs.chmodSync(entry, mode);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
}

// A stdout line watcher that returns the reset once the CLI is waiting out a
// limit it cannot outlast: a rejected rate_limit_event resetting after
// `deadlineMs()`, then a 429 `api_retry` with no assistant or user message
// between (rejectionInForce's rule). A rejection the CLI works past, or one a
// later event replaces, never stops the leg. Null for every other line.
function limitWatch(deadlineMs) {
  let pending = null;
  return (message) => {
    const type = message?.type;
    if (type === "assistant" || type === "user") pending = null;
    else if (type === "rate_limit_event") {
      const { resetsAt } = limitStopFrom([message]);
      pending =
        resetsAt !== null && Date.parse(resetsAt) > deadlineMs()
          ? resetsAt
          : null;
    } else if (
      pending !== null &&
      type === "system" &&
      message.subtype === "api_retry" &&
      message.error_status === 429
    ) {
      return pending;
    }
    return null;
  };
}

function parseLine(line) {
  try {
    return JSON.parse(line.toString("utf8"));
  } catch {
    return null;
  }
}

function liveValue(value, limit) {
  const text =
    typeof value === "string" ? value : (JSON.stringify(value) ?? String(value));
  const flat = text.replace(/[\r\n]+/gu, " ");
  return limit === undefined || flat.length <= limit
    ? flat
    : `${flat.slice(0, limit)}...`;
}

function toolCallLine(block, limit) {
  const input =
    block.input !== null &&
    typeof block.input === "object" &&
    !Array.isArray(block.input)
      ? block.input
      : {};
  return [
    "tool",
    liveValue(String(block.name ?? ""), limit),
    ...Object.entries(input).map(
      ([name, value]) => `${liveValue(name, limit)}=${liveValue(value, limit)}`,
    ),
  ].join(" ");
}

function liveView(write, secretValues) {
  let turn = 0;
  let inTurn = false;
  return (message) => {
    if (message?.type === "user") inTurn = false;
    if (message?.type !== "assistant" || typeof message.error === "string") {
      return;
    }
    if (!inTurn) {
      turn += 1;
      inTurn = true;
    }
    const content = message.message?.content;
    if (!Array.isArray(content)) return;
    for (const block of content) {
      let lines = [];
      if (block?.type === "text" && typeof block.text === "string") {
        lines = block.text
          .split(/[\r\n]+/u)
          .filter((line) => line.trim() !== "")
          .map((line) => [line, line]);
      } else if (block?.type === "tool_use") {
        lines = [[toolCallLine(block), toolCallLine(block, LIVE_VALUE_CHARS)]];
      }
      for (const [full, shown] of lines) {
        const held =
          holdsCredential(full, secretValues) ||
          holdsCredential(shown, secretValues);
        write(`[turn ${turn}] ${held ? LIVE_WITHHELD : shown}\n`);
      }
    }
  };
}

// Runs the leg's command with the prompt on stdin and stderr inherited, and
// resolves once it has exited and closed stdout. Stdout is kept up to
// `maxBytes` and each complete line goes to `onLine`, which returns true to
// stop the leg. The timeout, an overflow and onLine share one stop: SIGINT,
// once, with the first reason kept.
function runChild(
  spawn,
  [command, args],
  { env, input, timeoutMs, maxBytes, onLine },
) {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      env,
      stdio: ["pipe", "pipe", "inherit"],
    });
    const chunks = [];
    let bytes = 0;
    let stopped = null;
    const stop = (reason) => {
      if (stopped !== null) return;
      stopped = reason;
      child.kill("SIGINT");
    };
    const timer = timeoutMs > 0 ? setTimeout(stop, timeoutMs, "timeout") : null;
    // The unfinished line's chunks. A 0x0A byte is always a newline in UTF-8.
    let partial = [];
    // A spawn failure (ENOENT) ends in close with no exit code, as spawnSync's
    // null status did.
    child.on("error", () => {});
    child.stdin.on("error", () => {});
    child.stdin.end(input);
    child.stdout.on("data", (chunk) => {
      const kept = chunk.subarray(0, Math.max(0, maxBytes - bytes));
      chunks.push(kept);
      bytes += kept.length;
      let start = 0;
      for (let end; (end = kept.indexOf(10, start)) !== -1; start = end + 1) {
        const line = [...partial, kept.subarray(start, end)];
        partial = [];
        if (stopped === null && onLine(Buffer.concat(line))) stop("limit");
      }
      if (start < kept.length) partial.push(kept.subarray(start));
      if (kept.length < chunk.length) stop("overflow");
    });
    child.on("close", (code) => {
      if (timer !== null) clearTimeout(timer);
      resolve({
        exitCode: Number.isInteger(code) && code >= 0 ? code : null,
        stdout: Buffer.concat(chunks),
        stopped,
      });
    });
  });
}

// Null when the receiver cannot start: the leg then runs without telemetry.
async function openReceiver(start) {
  try {
    return await start();
  } catch {
    return null;
  }
}

// Stops the receiver and writes what it kept, unless that holds a credential.
// Never throws: telemetry cannot change the leg's outcome.
async function keepTelemetry(receiver, config, secretValues) {
  if (receiver === null) return { file: "", warning: OTEL_WARNINGS.start };
  try {
    const { text, dropped } = await receiver.stop();
    if (holdsCredential(text, secretValues)) {
      return { file: "", warning: OTEL_WARNINGS.credential };
    }
    const capped = dropped > 0 ? OTEL_WARNINGS.capped : "";
    if (text === "")
      return { file: "", warning: capped || OTEL_WARNINGS.empty };
    const file = path.join(config.workDir, OTEL_FILE);
    // `wx`: a path the leg planted first is refused, never followed.
    fs.writeFileSync(file, text, { flag: "wx", mode: 0o600 });
    return { file, warning: capped };
  } catch {
    return { file: "", warning: OTEL_WARNINGS.failed };
  }
}

async function runLeg(
  config,
  {
    baseEnv = process.env,
    spawn = spawnAsync,
    now = () => new Date(),
    maxStdoutBytes = MAX_LEG_STDOUT_BYTES,
    write = (text) => process.stdout.write(text),
    startReceiver = startOtlpReceiver,
  } = {},
) {
  const prompt = promptText(config);
  const { leg } = config;
  const executionFile = path.join(config.workDir, "leg-1-execution.json");
  const snapshots = snapshotFiles(baseEnv);
  const modes = [];
  let record;
  let judged;
  let reason = "";
  const telemetryOn = config.otelReceiver === true;
  let receiver = null;
  let telemetry = { file: "", warning: "" };
  try {
    const readOnly = readOnlyPaths(
      config,
      baseEnv,
      snapshots.map(({ file }) => file),
    );
    lockTrees(readOnly, modes);
    if (telemetryOn) receiver = await openReceiver(startReceiver);
    const startedAt = now().toISOString();
    const waitCapMs = Number(config.watchdogMaxWaitMs);
    let limitResets = null;
    const watch = limitWatch(() => now().getTime() + waitCapMs);
    const live =
      config.liveLog === true ? liveView(write, [leg.value]) : () => {};
    const { exitCode, stdout, stopped } = await runChild(
      spawn,
      legCommand(config, readOnly),
      {
        env: legEnv(baseEnv, leg, config, receiver?.endpoint ?? null),
        input: prompt,
        timeoutMs: config.legTimeoutMs,
        maxBytes: maxStdoutBytes,
        onLine: (line) => {
          const message = parseLine(line);
          live(message);
          limitResets = watch(message);
          return limitResets !== null;
        },
      },
    );
    const endedAt = now().toISOString();
    fs.writeFileSync(path.join(config.workDir, "leg-1.jsonl"), stdout);
    fs.writeFileSync(
      executionFile,
      JSON.stringify(linesToMessages(stdout.toString("utf8"))),
    );
    let message = null;
    if (stopped === "overflow") {
      message = `CLI stdout passed ${maxStdoutBytes} bytes; the leg was stopped`;
      judged = {
        failureClass: "other",
        resets: null,
        messages: readMessages(executionFile) ?? [],
      };
      process.stderr.write(`run-claude-cli: ${message}\n`);
    } else {
      if (stopped === "limit") {
        process.stderr.write(
          `run-claude-cli: the usage limit resets at ${limitResets}, past the ${waitCapMs} ms wait cap; the leg was stopped\n`,
        );
      }
      judged = judgeLeg({
        leg,
        executionFile,
        exitCode,
        timedOut: stopped === "timeout",
        maxTurns: config.maxTurns,
        limitResets: stopped === "limit" ? limitResets : null,
      });
    }
    reason = handoffReason(
      leg,
      judged.failureClass,
      apiErrorStatus(judged.messages),
      {
        fallbackReady: config.fallbackReady === true,
        limitStop: judged.failureClass === "rate-limit" && judged.resets !== null,
        creditStop:
          leg.leg === "subscription" &&
          isCreditStop(judged.messages, { exitCode }),
      },
    );
    record = legRecord({
      config,
      leg,
      startedAt,
      endedAt,
      exitCode,
      messages: judged.messages,
      failureClass: judged.failureClass,
      resets: judged.resets,
      next:
        reason === ""
          ? null
          : leg.leg === "api-key"
            ? "subscription"
            : config.handoffOnly === true
              ? null
              : "fallback",
      message,
    });
  } finally {
    try {
      if (telemetryOn) {
        telemetry = await keepTelemetry(receiver, config, [leg.value]);
      }
    } finally {
      try {
        restoreModes(modes);
      } finally {
        restoreFiles(snapshots);
      }
    }
  }
  const run = readRunRecord(executionFile);
  return {
    records: [record],
    ...(telemetryOn ? { telemetryWarning: telemetry.warning } : {}),
    outputs: {
      "lane-class": judged.failureClass,
      handoff: String(reason !== ""),
      "lane-resets": judged.resets ?? "",
      "lane-turns": run.turns === null ? "" : String(run.turns),
      "lane-models": run.models.join(","),
      credential: leg.name,
      "handoff-reason": reason,
      "execution-file": executionFile,
      ...(telemetryOn ? { "otel-file": telemetry.file } : {}),
    },
  };
}

// The record's API error facts as `key=value` tokens, each a closed value.
function errorTokens(record) {
  return [
    ["api_error_status", record.api_error_status],
    ["error_type", record.error_type],
    ["error_code", record.error_code],
    ["request_id", record.request_id],
  ]
    .filter(([, value]) => value !== null && value !== undefined)
    .map(([key, value]) => `${key}=${value}`)
    .join(" ");
}

function stopNote(record, reason) {
  const notes =
    record.next === "fallback"
      ? FALLBACK_NOTES
      : record.next === null
        ? LAST_LEG_NOTES
        : {};
  return Object.hasOwn(notes, reason) ? notes[reason] : nextStep(record.class).note;
}

// Every cell is a closed token or a value lane.cjs checked; no CLI text.
function summaryTable(records, reason = "") {
  const cell = (value) =>
    String(value ?? "")
      .replaceAll("|", "\\|")
      .replaceAll("`", "'");
  const rows = records.map(
    (r) =>
      `| ${r.leg} | ${cell(r.secret)} | ${cell(r.class || "success")} | ${cell(errorTokens(r))} | ${cell(r.num_turns)} | ${cell(r.denials.count)} | ${cell(r.resets)} | ${cell(r.next)} | ${cell(stopNote(r, reason))} |`,
  );
  return [
    "| Leg | Secret | Class | Error | Turns | Denials | Resets | Next | Stop |",
    "|---|---|---|---|---|---|---|---|---|",
    ...rows,
  ].join("\n");
}

function writeOutputs(outputPath, outputs) {
  const lines = Object.entries(outputs).map(([key, value]) => {
    if (String(value).includes("\n"))
      throw new LaneError(`output ${key} holds a newline`);
    return `${key}=${value}`;
  });
  fs.appendFileSync(outputPath, `${lines.join("\n")}\n`);
}

// Root-owned, not writable by group or others, pinning `apiKeyHelper` and
// `env.ANTHROPIC_BASE_URL` to the public API (or to the loopback-base-url
// opt-in, managed-settings.cjs), disabling bypassPermissions, and keeping
// user, project and plugin hooks from loading (`allowManagedHooksOnly` or
// `disableAllHooks`), so head code cannot repoint the credential or run a
// hook through settings it writes.
function verifyManagedSettings(
  file,
  { stat = fs.statSync, read = fs.readFileSync, loopbackBaseUrl = "" } = {},
) {
  const { baseUrl, problem } = expectedBaseUrl(loopbackBaseUrl);
  if (problem !== undefined) throw new LaneError(problem);
  let info;
  try {
    info = stat(file);
  } catch {
    throw new LaneError(
      `${file} is missing: run the apply-claude-managed-settings action before runner isolation`,
    );
  }
  if (info.uid !== 0) throw new LaneError(`${file} is not owned by root`);
  if ((info.mode & 0o022) !== 0)
    throw new LaneError(`${file} is writable by group or others`);
  let settings;
  try {
    settings = JSON.parse(read(file, "utf8"));
  } catch {
    throw new LaneError(`${file} is not JSON`);
  }
  const wrong = settingsProblem(settings, baseUrl);
  if (wrong !== null) throw new LaneError(`${file} ${wrong}`);
}

// True when the runner user can still write the Docker socket, which is root
// on the host by another name.
function dockerReachable(socket) {
  if (!fs.existsSync(socket)) return false;
  try {
    fs.accessSync(socket, fs.constants.W_OK);
    return true;
  } catch {
    return false;
  }
}

// Fail closed when the step environment sets a loader, TLS or proxy
// variable (UNSAFE_VARIABLES) to anything non-empty.
function verifyEnvironment(env) {
  const unsafe = Object.keys(env)
    .filter((name) => {
      const upper = name.toUpperCase();
      return (
        UNSAFE_VARIABLES.has(upper) ||
        (upper.endsWith("_PROXY") && upper !== "NO_PROXY")
      );
    })
    .filter((name) => (env[name] ?? "") !== "")
    .sort();
  if (unsafe.length > 0) {
    throw new LaneError(
      `the step environment sets ${unsafe.join(", ")}: no head code may run before run-claude-cli, and none of these may reach the CLI`,
    );
  }
}

function verifyIsolation({
  managedSettings,
  env = process.env,
  spawn = spawnSync,
  dockerSocket = DOCKER_SOCKET,
  ...io
}) {
  verifyEnvironment(env);
  verifyManagedSettings(managedSettings, {
    ...io,
    loopbackBaseUrl: env.LANE_LOOPBACK_BASE_URL ?? "",
  });
  if (spawn("sudo", ["-n", "true"], { stdio: "ignore" }).status === 0) {
    throw new LaneError(
      "sudo still works: run runner isolation before run-claude-cli",
    );
  }
  if (dockerReachable(dockerSocket)) {
    throw new LaneError(
      `${dockerSocket} is writable: runner isolation must remove docker access`,
    );
  }
  // The scrub needs bubblewrap to create namespaces, not merely be installed.
  const probe = spawn("bwrap", BWRAP_PROBE, { stdio: "ignore" });
  if (probe.error?.code === "ENOENT") {
    throw new LaneError(
      "bubblewrap is missing: CLAUDE_CODE_SUBPROCESS_ENV_SCRUB needs it",
    );
  }
  if (probe.status !== 0) {
    throw new LaneError(
      `bwrap ${BWRAP_PROBE.join(" ")} failed: bubblewrap cannot create a PID namespace. In a Docker worker, Docker's default seccomp profile blocks it: set the ci-runner target's seccompProfile: userns. On an Ubuntu 24.04 host run \`sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0\` in runner isolation, before sudo is removed (see pr-review.yml, "Install subprocess isolation")`,
    );
  }
  // The sandbox's network proxy needs socat; with the sandbox off, nothing does.
  if (!sandboxEnabled(env)) return;
  const socat = spawn("socat", ["-V"], { stdio: "ignore" });
  if (socat.error || socat.status !== 0) {
    throw new LaneError(
      `socat is missing or does not run (${socat.error?.code ?? `exit ${socat.status}`}): Claude Code's sandbox needs it for its network proxy. Install it with bubblewrap in runner isolation, or set the sandbox input to false`,
    );
  }
}

// Run a command and fail closed when it cannot start or exits non-zero.
function mustRun(spawn, what, command, args, options) {
  const result = spawn(command, args, { encoding: "utf8", ...options });
  if (result.error || result.status !== 0) {
    const why = result.error
      ? (result.error.code ?? result.error.message)
      : `exit ${result.status}`;
    throw new LaneError(`${what} failed (${why})`);
  }
  return result;
}

function sha256File(file) {
  const hash = crypto.createHash("sha256");
  const buffer = Buffer.alloc(1024 * 1024);
  const fd = fs.openSync(file, "r");
  try {
    let read;
    while ((read = fs.readSync(fd, buffer, 0, buffer.length, null)) > 0) {
      hash.update(buffer.subarray(0, read));
    }
  } finally {
    fs.closeSync(fd);
  }
  return hash.digest("hex");
}

// The installed tree must hold exactly the wrapper and the platform package,
// both at the resolved version, so the audit's package count names them.
function verifyInstalledTree(prefix, version, platformPackage) {
  const modules = path.join(prefix, "node_modules");
  const allowed = new Set([".bin", ".package-lock.json", "@anthropic-ai"]);
  const extra = fs.readdirSync(modules).filter((name) => !allowed.has(name));
  const scoped = fs.readdirSync(path.join(modules, "@anthropic-ai")).sort();
  const expected = [CLI_PACKAGE, platformPackage]
    .map((name) => name.split("/")[1])
    .sort();
  if (extra.length > 0 || scoped.join(",") !== expected.join(",")) {
    throw new LaneError(
      `the install tree holds ${[...extra, ...scoped].join(", ")}, not exactly ${CLI_PACKAGE} and ${platformPackage}`,
    );
  }
  for (const name of [CLI_PACKAGE, platformPackage]) {
    const manifest = JSON.parse(
      fs.readFileSync(path.join(modules, name, "package.json"), "utf8"),
    );
    if (manifest.version !== version) {
      throw new LaneError(
        `${name} installed at ${manifest.version}, not ${version}`,
      );
    }
  }
}

// `npm audit signatures --json` lists only invalid and missing signatures,
// never the packages it verified (lib/utils/verify-signatures.js in
// npm/cli), and a registry that serves no keys is skipped with exit 0. So
// the text report must count both packages as audited and verified.
function auditSignatures(spawn, { cwd, prefix, registry }) {
  const audit = mustRun(
    spawn,
    "npm audit signatures",
    "npm",
    ["audit", "signatures", registry, "--color=false", "--prefix", prefix],
    { cwd },
  );
  const report = String(audit.stdout ?? "");
  if (
    !/^audited 2 packages in /mu.test(report) ||
    !/^2 packages have verified registry signatures$/mu.test(report)
  ) {
    throw new LaneError(
      `npm audit signatures did not verify both ${CLI_PACKAGE} packages: ${JSON.stringify(report.trim())}`,
    );
  }
  return report.match(/^audited .*$/mu)[0];
}

// Verify the release manifest's signature with the pinned key and return the
// platform's entry. GPG runs with its own home, so no runner keyring counts.
function signedManifestEntry(spawn, { dir, version, platform }) {
  fs.mkdirSync(dir, { recursive: true });
  const files = {
    key: path.join(dir, "claude-code.asc"),
    manifest: path.join(dir, "manifest.json"),
    signature: path.join(dir, "manifest.json.sig"),
  };
  const urls = {
    key: SIGNING_KEY_URL,
    manifest: `${RELEASES_URL}/${version}/manifest.json`,
    signature: `${RELEASES_URL}/${version}/manifest.json.sig`,
  };
  for (const name of Object.keys(files)) {
    mustRun(
      spawn,
      `download ${urls[name]}`,
      "curl",
      ["--proto", "=https", "-fsSL", "-o", files[name], urls[name]],
      { cwd: dir },
    );
  }
  const home = fs.mkdtempSync(path.join(dir, "gnupg-"));
  fs.chmodSync(home, 0o700);
  const gpg = ["--batch", "--homedir", home];
  mustRun(spawn, "gpg --import", "gpg", [...gpg, "--import", files.key], {
    cwd: dir,
  });
  const verify = mustRun(
    spawn,
    "gpg --verify of the release manifest",
    "gpg",
    [...gpg, "--status-fd", "1", "--verify", files.signature, files.manifest],
    { cwd: dir },
  );
  const status = String(verify.stdout ?? "").split("\n");
  const goodSig = status.some((line) => line.startsWith("[GNUPG:] GOODSIG "));
  const signedBy = status
    .filter((line) => line.startsWith("[GNUPG:] VALIDSIG "))
    .map((line) => line.trim().split(" ").at(-1));
  if (
    !goodSig ||
    signedBy.length !== 1 ||
    signedBy[0] !== SIGNING_KEY_FINGERPRINT
  ) {
    throw new LaneError(
      `the ${version} release manifest is not signed by key ${SIGNING_KEY_FINGERPRINT}`,
    );
  }
  let manifest;
  try {
    manifest = JSON.parse(fs.readFileSync(files.manifest, "utf8"));
  } catch {
    throw new LaneError(`the ${version} release manifest is not JSON`);
  }
  if (manifest.version !== version) {
    throw new LaneError(
      `the signed manifest is for ${JSON.stringify(manifest.version)}, not ${version}`,
    );
  }
  const entry = manifest.platforms?.[platform];
  if (!/^[0-9a-f]{64}$/u.test(entry?.checksum ?? "")) {
    throw new LaneError(
      `the signed ${version} manifest has no ${platform} checksum`,
    );
  }
  return entry;
}

// Every npm call runs in the work directory with the public registry named,
// so a checkout's .npmrc cannot steer it. The install keeps scripts on: the
// wrapper's postinstall puts the platform binary in place of a stub.
function install(
  env,
  { spawn = spawnSync, platform = `${process.platform}-${process.arch}` } = {},
) {
  const registry = `--registry=${NPM_REGISTRY}`;
  const cwd = env.LANE_WORK_DIR;
  const npmVersion = mustRun(spawn, "npm --version", "npm", ["--version"], {
    cwd,
  });
  process.stdout.write(
    `run-claude-cli: npm ${String(npmVersion.stdout).trim()}\n`,
  );
  const version = resolveCliVersion(env.LANE_CLI_VERSION_INPUT, () => {
    const view = spawn("npm", ["view", registry, CLI_PACKAGE, "version"], {
      cwd,
      encoding: "utf8",
    });
    if (view.status !== 0)
      throw new LaneError(`npm view ${CLI_PACKAGE} version failed`);
    return view.stdout;
  });
  const platformPackage = `${CLI_PACKAGE}-${platform}`;
  const prefix = path.join(cwd, "cli");
  fs.mkdirSync(prefix, { recursive: true });
  // npm 12 blocks dependency install scripts unless the root package.json
  // allows them (npm 11 runs them with a notice); allow this one version.
  fs.writeFileSync(
    path.join(prefix, "package.json"),
    `${JSON.stringify({ allowScripts: { [`${CLI_PACKAGE}@${version}`]: true } }, null, 2)}\n`,
  );
  mustRun(
    spawn,
    `npm install ${CLI_PACKAGE}@${version}`,
    "npm",
    [
      "install",
      registry,
      "--save-exact",
      "--no-audit",
      "--no-fund",
      "--prefix",
      prefix,
      `${CLI_PACKAGE}@${version}`,
    ],
    { cwd, stdio: ["ignore", "ignore", "inherit"] },
  );
  process.stdout.write(`run-claude-cli: Claude Code CLI ${version}\n`);
  verifyInstalledTree(prefix, version, platformPackage);
  const audited = auditSignatures(spawn, { cwd, prefix, registry });
  process.stdout.write(
    `run-claude-cli: npm audit signatures: ${audited}, both verified\n`,
  );

  const entry = signedManifestEntry(spawn, {
    dir: path.join(cwd, "cli-manifest"),
    version,
    platform,
  });
  const cliPath = path.join(prefix, "node_modules", ".bin", "claude");
  const checksum = sha256File(fs.realpathSync(cliPath));
  process.stdout.write(
    `run-claude-cli: ${platform} binary sha256 ${checksum}, signed manifest ${entry.checksum}\n`,
  );
  if (checksum !== entry.checksum) {
    throw new LaneError(
      `the installed ${platform} binary does not match the signed ${version} manifest`,
    );
  }
  const reported = mustRun(
    spawn,
    `${cliPath} --version`,
    cliPath,
    ["--version"],
    { cwd },
  );
  process.stdout.write(`run-claude-cli: ${String(reported.stdout).trim()}\n`);
  writeOutputs(env.GITHUB_OUTPUT, {
    "cli-version": version,
    "cli-path": cliPath,
  });
}

// The final result's structured_output as JSON text, when the leg ran with
// json-schema-file and succeeded; else null.
function structuredOutputText(config, laneClass, executionFile) {
  if (config.jsonSchema === "" || laneClass !== "") return null;
  const value = finalResult(readMessages(executionFile) ?? [])
    ?.structured_output;
  return value !== null && typeof value === "object"
    ? JSON.stringify(value)
    : null;
}

async function run(env) {
  verifyEnvironment(env);
  const config = readConfig(env);
  const token = crypto.randomBytes(16).toString("hex");
  process.stdout.write(`::stop-commands::${token}\n`);
  let outcome;
  try {
    outcome = await runLeg(config, { baseEnv: env });
  } finally {
    process.stdout.write(`::${token}::\n`);
  }
  const logFile = path.join(config.workDir, "run-claude-cli-log.jsonl");
  const secrets = [config.leg.value];
  const logText = `${outcome.records.map((r) => JSON.stringify(r)).join("\n")}\n`;
  const clean = !holdsCredential(logText, secrets);
  if (clean) fs.writeFileSync(logFile, logText);
  const structuredText = structuredOutputText(
    config,
    outcome.outputs["lane-class"],
    outcome.outputs["execution-file"],
  );
  const structuredClean =
    structuredText === null ||
    !holdsCredential(structuredText, secrets);
  const structuredFile = path.join(config.workDir, "structured-output.json");
  const structuredWritten = structuredText !== null && structuredClean;
  if (structuredWritten) fs.writeFileSync(structuredFile, structuredText);
  writeOutputs(env.GITHUB_OUTPUT, {
    ...outcome.outputs,
    "execution-file-clean": String(
      fileClean(outcome.outputs["execution-file"], secrets),
    ),
    "log-file": clean ? logFile : "",
    "structured-output-file": structuredWritten ? structuredFile : "",
  });
  if (env.GITHUB_STEP_SUMMARY && clean) {
    fs.appendFileSync(
      env.GITHUB_STEP_SUMMARY,
      `### run-claude-cli: ${config.lane} (${config.role})\n\n${summaryTable(outcome.records, outcome.outputs["handoff-reason"])}\n`,
    );
  }
  // After the stop-commands block, so the runner reads it, and before a
  // lane class ends the step, so a stopped leg still warns.
  const warning = clean ? usageWarning(outcome.records[0]) : null;
  if (warning !== null) process.stdout.write(`${warning}\n`);
  if (outcome.telemetryWarning) {
    process.stdout.write(
      `::warning title=run-claude-cli telemetry::${outcome.telemetryWarning}\n`,
    );
  }
  // A refused subscription token hands off and the run can go green, so the
  // dead secret is named here.
  if (
    outcome.outputs["handoff-reason"] === "auth" &&
    config.leg.leg === "subscription"
  ) {
    const after = config.handoffOnly
      ? "No further leg runs."
      : "The fallback job runs instead.";
    process.stdout.write(
      `::warning title=run-claude-cli credential::class=auth: the API refused ${outcome.outputs.credential}; the owner must replace the secret. ${after}\n`,
    );
  }
  if (!clean) {
    throw new LaneError(
      "the execution log held a credential and was not written",
    );
  }
  if (!structuredClean) {
    throw new LaneError(
      "the structured output held a credential and was not written",
    );
  }
  const laneClass = outcome.outputs["lane-class"];
  if (laneClass !== "") {
    const facts = errorTokens(outcome.records[0]);
    throw new LaneError(
      `${config.lane} ended class=${laneClass} on ${outcome.outputs.credential}${facts === "" ? "" : ` ${facts}`}`,
    );
  }
}

if (require.main === module) {
  (async () => {
    const command = process.argv[2];
    if (command === "verify-isolation") {
      verifyIsolation({ managedSettings: process.env.LANE_MANAGED_SETTINGS });
    } else if (command === "install") {
      install(process.env);
    } else if (command === "run") {
      await run(process.env);
    } else {
      throw new LaneError(`unknown command ${JSON.stringify(command)}`);
    }
  })().catch((error) => {
    const known = error instanceof LaneError;
    if (!known) console.error(error);
    const message = known
      ? error.message
      : "unexpected failure (see the step log)";
    process.stdout.write(`::error title=run-claude-cli::${message}\n`);
    process.exitCode = 1;
  });
}

module.exports = {
  CREDENTIAL_VARIABLES,
  FALLBACK_SECRET,
  FILE_COMMAND_VARIABLES,
  LaneError,
  LIVE_VALUE_CHARS,
  LIVE_WITHHELD,
  NPM_REGISTRY,
  SANDBOX_SETTINGS,
  SIGNING_KEY_FINGERPRINT,
  cliArgs,
  fileClean,
  handoffReason,
  holdsCredential,
  install,
  judgeLeg,
  legEnv,
  linesToMessages,
  readConfig,
  resolveCliVersion,
  run,
  runLeg,
  summaryTable,
  usageWarning,
  verifyEnvironment,
  verifyIsolation,
  verifyManagedSettings,
};
