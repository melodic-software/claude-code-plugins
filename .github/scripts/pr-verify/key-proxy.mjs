// The key proxy: the only path from pr-verify's Claude Code sessions to the
// Messages API. It runs as its own OS user, holds the real key (read from
// stdin, never argv or env) and listens on a unix socket, so pull request code
// in the no-network sandbox never sees the key. With --listen it also listens
// on a loopback TCP port for the capture's driver legs, which hold a per-run
// client key instead of the real one; that listener refuses with a 401 any
// request whose x-api-key is not the client key, has its own budget and state,
// and relays an upstream error to a count_tokens preflight as sent, so a
// credit stop or a refused key reaches the leg as the API's own answer. Any
// process on the runner can reach a loopback port, so the client key, not the
// port, is what admits a request (our decision). Every request passes an
// ordered pipeline of checks (path, query, size, parse, body keys, model,
// max_tokens, betas, server tools, content, count_tokens limits, in-flight
// slot, cap reservation). One that passes goes upstream as the re-serialized
// checked object with the client's credential replaced, and the response is
// relayed as it arrives. One budget holds the committed and in-flight reserved
// tokens, so concurrent requests cannot pass the per-job cap together; each
// /v1/messages reservation is the upstream's own count_tokens figure for the
// request plus its max_tokens.
//
//   node key-proxy.mjs --socket <path> --config <file.json> [--upstream <url>] [--listen <port>] < key
//
// Stdin holds the key; with --listen, the key's line is followed by a second
// line holding the loopback listener's client key, which must differ from it.
//
// Config (JSON, read from the base branch by the workflow, never the head):
//   tokenCap               per-job token budget (input, cache and output tokens) of the socket
//   driverTokenCap         the same budget for the --listen loopback listener
//   models                 model ids the driven session may use
//   maxTokensCeiling       largest max_tokens a /v1/messages request may ask for
//   maxBodyBytes           largest request body accepted
//   maxInFlight            concurrent forwarded requests, count_tokens included
//   maxCountTokensRequests client count_tokens requests allowed per job
//   maxPreflightRequests   /v1/messages requests per job that may reach the count_tokens preflight
//   betas                  anthropic-beta values a request may name
//   bodyKeys               top-level request body keys a request may carry
//   blockTypes             content block types allowed in messages and system
//   upstreamTimeoutMs      idle time after which a stalled upstream request is aborted;
//                          set it longer than the longest non-streaming generation and
//                          the longest gap between SSE pings. Claude Code's own
//                          API_TIMEOUT_MS bounds only the time to response headers.
//                          Pointer: https://code.claude.com/docs/en/errors#tune-retry-behavior
//                          As of: 2026-11-06. Recheck trigger: the API_TIMEOUT_MS row changes.
//   upstream               API base URL (default https://api.anthropic.com)
//   socketMode             octal mode set on the socket after listen, e.g. "660"
//
// It logs one JSON line per request to stderr: the listener (socket or
// loopback), method, path without query, status and token counts, and for a beta refusal the refused beta names, so a
// failed capture says what to add to `betas`. Never the key, any other header
// value, or a body.
import { createHash, timingSafeEqual } from "node:crypto";
import { chmodSync, readFileSync, rmSync } from "node:fs";
import http from "node:http";
import https from "node:https";
import process from "node:process";
import { pathToFileURL } from "node:url";

export const ALLOWED_PATHS = Object.freeze(["/v1/messages", "/v1/messages/count_tokens"]);
const COUNT_TOKENS = "/v1/messages/count_tokens";
const DEFAULT_UPSTREAM = "https://api.anthropic.com";
// The one query the driven session sends; any other is refused (our decision).
const ALLOWED_QUERY = "beta=true";
// Request headers forwarded upstream (our allowlist): the API version and
// betas, session attribution, accept and user-agent. The client's
// accept-encoding is never forwarded; every upstream request asks for
// identity instead, because the proxy reads usage from the bytes it relays
// and relays them untouched (our decision). A request with no Accept-Encoding
// would accept any coding.
// Pointer: https://www.rfc-editor.org/rfc/rfc9110#section-12.5.3
// As of: 2026-11-06. Recheck trigger: an RFC obsoletes RFC 9110's Accept-Encoding section.
const FORWARD_NAMED = new Set(["anthropic-version", "anthropic-beta", "accept", "user-agent"]);
const FORWARD_PREFIX = /^x-claude-code-/;
// Response headers relayed to the client (our allowlist).
const RELAY_NAMED = new Set(["content-type", "cache-control", "request-id", "x-should-retry", "retry-after"]);
const RELAY_PREFIX = /^anthropic-ratelimit-/;
// Content sources that carry their data inline in the request. A url or file
// source names data held elsewhere, so it is refused (our decision).
const SOURCE_TYPES = Object.freeze(["base64", "text", "content"]);
// Refused beta names logged and returned, at most (our decision); the header
// is client-controlled.
const MAX_NAMED_BETAS = 10;
// How long an oversized upload is drained after its 413 before the socket is closed.
const DRAIN_MS = 10_000;
// Body fields the count_tokens preflight forwards.
// Pointer: https://platform.claude.com/docs/en/api/messages-count-tokens (Body parameters)
// As of: 2026-11-06. Recheck trigger: that section adds or removes a parameter.
const COUNT_TOKENS_FIELDS = Object.freeze(["messages", "model", "cache_control", "output_config", "speed", "system", "thinking", "tool_choice", "tools"]);
// Counted toward the cap. Cache reads and writes are counted in full: the cap
// is a token count, not a price (our decision).
const USAGE_FIELDS = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"];

// Refusal statuses Claude Code does not retry. Every refusal carries
// `x-should-retry: false`, which Claude Code reads as not retryable. The cap
// refusal is a 429 shaped like a gateway spend limit, which Claude Code shows
// without retrying; a policy refusal is a 403 and an oversized body a 413,
// neither in the automatic-retry list (the 403 retry there needs an
// apiKeyHelper, which the driven session does not use). Not 400 or 422, which
// Claude Code may resend after once when it does not recognize the cause.
// An upstream failure (no answer, a connection dropped before any response
// byte, a stall) is the opposite: a 502 with `x-should-retry: true`, a server
// error before anything streamed, which Claude Code retries with backoff.
// Pointer: https://code.claude.com/docs/en/llm-gateway-protocol#response-headers (x-should-retry row),
//   https://code.claude.com/docs/en/llm-gateway-protocol#retry-without-tool-search,
//   https://code.claude.com/docs/en/errors#automatic-retries,
//   https://code.claude.com/docs/en/errors#spend-limit-reached
// As of: 2026-11-06 (Claude Code 2.1.318).
// Recheck trigger: the automatic-retries lists, the x-should-retry row, the
//   tool-search retry or the spend-limit section changes.
const refuse = (status, type, message) => ({ status, type, message });
const policy = (message) => refuse(403, "permission_error", message);
const spendLimit = (what) => refuse(429, "rate_limit_error", `spend limit reached (${what})`);
const retryable = (message) => ({ ...refuse(502, "api_error", message), retry: true });
const UPSTREAM_TIMEOUT = "UPSTREAM_TIMEOUT";
const upstreamFailure = (err) => retryable(err?.code === UPSTREAM_TIMEOUT ? "upstream timed out" : "upstream unreachable");
const clip = (v) => String(v).slice(0, 80);

const stringList = (c, name) => {
  if (!Array.isArray(c[name]) || !c[name].every((m) => typeof m === "string" && m)) throw new Error(`config ${name} must be a list of strings`);
  return Object.freeze([...c[name]]);
};

export function loadConfig(raw, upstreamOverride) {
  const c = typeof raw === "string" ? JSON.parse(raw) : raw;
  const positiveInt = (name) => {
    if (!Number.isInteger(c[name]) || c[name] <= 0) throw new Error(`config ${name} must be a positive integer`);
    return c[name];
  };
  const nonEmpty = (name) => {
    const list = stringList(c, name);
    if (list.length === 0) throw new Error(`config ${name} must not be empty`);
    return list;
  };
  const upstream = new URL(upstreamOverride ?? c.upstream ?? DEFAULT_UPSTREAM);
  if (upstream.protocol !== "https:" && upstream.protocol !== "http:") throw new Error("config upstream must be an http(s) URL");
  if (c.socketMode !== undefined && !/^[0-7]{3,4}$/.test(String(c.socketMode))) throw new Error("config socketMode must be an octal string");
  return Object.freeze({
    tokenCap: positiveInt("tokenCap"),
    driverTokenCap: positiveInt("driverTokenCap"),
    models: nonEmpty("models"),
    maxTokensCeiling: positiveInt("maxTokensCeiling"),
    maxBodyBytes: positiveInt("maxBodyBytes"),
    maxInFlight: positiveInt("maxInFlight"),
    maxCountTokensRequests: positiveInt("maxCountTokensRequests"),
    maxPreflightRequests: positiveInt("maxPreflightRequests"),
    upstreamTimeoutMs: positiveInt("upstreamTimeoutMs"),
    betas: stringList(c, "betas"),
    bodyKeys: nonEmpty("bodyKeys"),
    blockTypes: nonEmpty("blockTypes"),
    upstream,
    socketMode: c.socketMode === undefined ? undefined : parseInt(String(c.socketMode), 8),
  });
}

// Committed tokens (used, or charged on an abandoned response) plus tokens
// reserved by requests in flight. A reservation settles exactly once.
export function createBudget(cap) {
  let committed = 0;
  let reserved = 0;
  return {
    get cap() { return cap; },
    get committed() { return committed; },
    get reserved() { return reserved; },
    reserve(tokens) {
      if (committed + reserved + tokens > cap) return null;
      reserved += tokens;
      let settled = false;
      return {
        tokens,
        settle(used) {
          if (settled) return;
          settled = true;
          reserved -= tokens;
          committed += used;
        },
      };
    },
  };
}

// Final usage of one response. message_delta usage is cumulative, so a later
// value replaces an earlier one field by field; message_start and
// message_delta are never added together.
// Pointer: https://platform.claude.com/docs/en/build-with-claude/streaming#event-types
// As of: 2026-11-06. Recheck trigger: that section changes what message_delta usage holds.
export function createUsageMeter(streaming) {
  const usage = {};
  let seen = false;
  let sawDelta = false;
  let pending = "";
  let whole = [];
  const take = (u) => {
    if (!u || typeof u !== "object") return;
    for (const f of USAGE_FIELDS) {
      if (Number.isFinite(u[f])) {
        usage[f] = u[f];
        seen = true;
      }
    }
  };
  const line = (l) => {
    if (!l.startsWith("data:")) return;
    let event;
    try { event = JSON.parse(l.slice(5)); } catch { return; }
    if (event?.type === "message_start") take(event.message?.usage);
    else if (event?.type === "message_delta") {
      sawDelta = true;
      take(event.usage);
    }
  };
  return {
    feed(chunk) {
      if (!streaming) {
        whole.push(chunk);
        return;
      }
      pending += chunk.toString("utf8");
      const lines = pending.split("\n");
      pending = lines.pop();
      for (const l of lines) line(l.replace(/\r$/, ""));
    },
    end() {
      if (streaming) {
        if (pending) line(pending.replace(/\r$/, ""));
        pending = "";
      } else if (whole.length) {
        try { take(JSON.parse(Buffer.concat(whole).toString("utf8"))?.usage); } catch { /* not JSON: no usage */ }
        whole = [];
      }
    },
    get seen() { return seen; },
    get sawDelta() { return sawDelta; },
    total() { return USAGE_FIELDS.reduce((sum, f) => sum + (usage[f] ?? 0), 0); },
  };
}

// Content blocks in messages and system, walked at every depth through a
// block's `content` and a content-type source's `content` (the nesting this
// proxy checks, our decision). We do not walk tool_use input or tool schemas:
// we treat them as data the model or tool definition supplies, and checking
// their `type` keys as block types would refuse ordinary JSON (our decision).
function contentRefusal(content, config) {
  const stack = [content];
  while (stack.length) {
    const list = stack.pop();
    if (typeof list === "string") continue;
    if (!Array.isArray(list)) return policy("content must be a string or a list of blocks");
    for (const b of list) {
      if (!b || typeof b !== "object" || !config.blockTypes.includes(b.type)) {
        return policy(`content block type not allowed through this proxy: ${clip(b?.type)}`);
      }
      if (b.source !== undefined) {
        if (!b.source || typeof b.source !== "object" || !SOURCE_TYPES.includes(b.source.type)) {
          return policy(`content source type not allowed through this proxy: ${clip(b.source?.type)}`);
        }
        if (b.source.type === "content") stack.push(b.source.content);
      }
      if (b.content !== undefined) stack.push(b.content);
    }
  }
  return null;
}

const decoder = new TextDecoder("utf-8", { fatal: true });

// The ordered pipeline. Each check returns null (allow) or a refusal, or a
// promise of one. Size is enforced as the body arrives (see createProxy).
export const CHECKS = Object.freeze([
  function path(ctx) {
    return ctx.method === "POST" && ALLOWED_PATHS.includes(ctx.path) ? null : refuse(404, "not_found_error", "not found");
  },
  function query(ctx) {
    return ctx.query === undefined || ctx.query === ALLOWED_QUERY ? null : policy("query string not allowed through this proxy");
  },
  function parse(ctx) {
    try { ctx.body = JSON.parse(decoder.decode(ctx.raw)); } catch { return refuse(400, "invalid_request_error", "request body is not UTF-8 JSON"); }
    return ctx.body && typeof ctx.body === "object" && !Array.isArray(ctx.body) ? null : refuse(400, "invalid_request_error", "request body is not a JSON object");
  },
  function bodyKeys(ctx) {
    const extra = Object.keys(ctx.body).find((k) => !ctx.config.bodyKeys.includes(k));
    return extra === undefined ? null : policy(`body field not allowed through this proxy: ${clip(extra)}`);
  },
  function model(ctx) {
    return ctx.config.models.includes(ctx.body.model) ? null : policy(`model not allowed through this proxy: ${clip(ctx.body.model)}`);
  },
  function maxTokens(ctx) {
    if (ctx.path === COUNT_TOKENS) return null;
    const m = ctx.body.max_tokens;
    if (!Number.isInteger(m) || m <= 0) return policy("max_tokens is required");
    return m > ctx.config.maxTokensCeiling ? policy(`max_tokens exceeds this proxy's ceiling of ${ctx.config.maxTokensCeiling}`) : null;
  },
  function betas(ctx) {
    const header = ctx.headers["anthropic-beta"];
    if (header === undefined) return null;
    const unknown = [...new Set(String(header).split(",").map((b) => b.trim()).filter((b) => b && !ctx.config.betas.includes(b)))];
    if (unknown.length === 0) return null;
    const named = unknown.slice(0, MAX_NAMED_BETAS).map(clip);
    const more = unknown.length > named.length ? ` (+${unknown.length - named.length} more)` : "";
    return {
      ...policy(`anthropic-beta values not allowed through this proxy: ${named.join(", ")}${more}; add them to the config betas list to allow them`),
      log: { betas: named },
    };
  },
  // Server tools run inside the API with the held key, so a tools[] entry is
  // allowed only as a custom tool (no type, or type "custom"), which fails
  // closed on any new server tool type (our decision).
  // Pointer: https://platform.claude.com/docs/en/agents-and-tools/tool-use/server-tools#the-server-tool-use-block
  // As of: 2026-11-06. Recheck trigger: that section stops saying the API runs the tool.
  function serverTools(ctx) {
    const { body } = ctx;
    if (body.mcp_servers !== undefined) return policy("mcp_servers is not allowed through this proxy");
    if (body.tools !== undefined && !Array.isArray(body.tools)) return policy("tools must be a list");
    for (const t of body.tools ?? []) {
      if (!t || typeof t !== "object" || Array.isArray(t)) return policy("tools entries must be objects");
      if (t.type !== undefined && t.type !== "custom") return policy(`server tools are not allowed through this proxy: ${clip(t.type)}`);
    }
    return null;
  },
  function content(ctx) {
    const { body, config } = ctx;
    if (!Array.isArray(body.messages)) return policy("messages must be a list");
    for (const m of body.messages) {
      if (!m || typeof m !== "object") return policy("messages must be objects");
      const r = contentRefusal(m.content, config);
      if (r) return r;
    }
    return body.system === undefined ? null : contentRefusal(body.system, config);
  },
  // Client count_tokens is not counted toward the cap, since token counting
  // is free, so it is limited per job and stops once the cap is spent, and
  // cannot be used as an unmetered channel (our decision).
  // Pointer: https://platform.claude.com/docs/en/build-with-claude/token-counting#pricing-and-rate-limits
  // As of: 2026-11-06. Recheck trigger: that section stops calling token counting free.
  function countTokensLimits(ctx) {
    if (ctx.path !== COUNT_TOKENS) return null;
    if (ctx.budget.committed >= ctx.budget.cap) return spendLimit("per-job token cap");
    if (ctx.state.countTokensRequests >= ctx.config.maxCountTokensRequests) return policy("count_tokens request limit reached for this job");
    ctx.state.countTokensRequests += 1;
    return null;
  },
  function inFlight(ctx) {
    if (ctx.state.inFlight >= ctx.config.maxInFlight) return policy("too many requests in flight through this proxy");
    ctx.state.inFlight += 1;
    let released = false;
    ctx.release = () => {
      if (released) return;
      released = true;
      ctx.state.inFlight -= 1;
    };
    return null;
  },
  async function cap(ctx) {
    if (ctx.path === COUNT_TOKENS) return null;
    // Its max_tokens alone already passes the cap: refused before the preflight,
    // so a spent budget makes no further upstream call (our decision).
    if (ctx.budget.committed + ctx.budget.reserved + ctx.body.max_tokens > ctx.budget.cap) return spendLimit("per-job token cap");
    // Each preflight is an upstream call the cap does not count, and one refused
    // at reserve costs the client nothing, so preflights are limited per job too
    // (our decision).
    if (ctx.state.preflights >= ctx.config.maxPreflightRequests) return spendLimit("per-job request limit");
    ctx.state.preflights += 1;
    const pre = await ctx.preflight(ctx);
    // A failure the client would retry against the API itself (a 429 or a
    // 5xx, relayed as sent; no answer, as a retryable 502) goes back to the
    // client so Claude Code's own retry covers it; any other failure is a
    // refusal it does not retry (our decision). See the refusal-status
    // pointer above (errors#automatic-retries).
    if (pre.relay) return { relay: pre.relay, status: pre.relay.status, type: "relayed" };
    if (pre.refusal) return pre.refusal;
    const input = pre.input;
    if (!Number.isInteger(input) || input < 0) return policy("token count preflight failed");
    ctx.reservation = ctx.budget.reserve(input + ctx.body.max_tokens);
    return ctx.reservation ? null : spendLimit("per-job token cap");
  },
]);

export async function runChecks(ctx) {
  for (const check of CHECKS) {
    const r = await check(ctx);
    if (r) return r;
  }
  return null;
}

const sendRefusal = (res, r) => {
  const body = JSON.stringify({ type: "error", error: { type: r.type, message: r.message } });
  res.writeHead(r.status, { "content-type": "application/json", "x-should-retry": r.retry ? "true" : "false", "content-length": Buffer.byteLength(body), ...(r.status === 413 ? { connection: "close" } : {}) });
  res.end(body);
};

const forwardHeaders = (incoming, key, length) => {
  const out = {};
  for (const [name, value] of Object.entries(incoming)) {
    if (FORWARD_NAMED.has(name) || FORWARD_PREFIX.test(name)) out[name] = value;
  }
  out["content-type"] = "application/json";
  out["accept-encoding"] = "identity";
  out["x-api-key"] = key;
  out["content-length"] = String(length);
  return out;
};

const relayHeaders = (incoming) => Object.fromEntries(Object.entries(incoming).filter(([name]) => RELAY_NAMED.has(name) || RELAY_PREFIX.test(name)));

const digest = (s) => createHash("sha256").update(s, "utf8").digest();

// clientKey, when set, is the x-api-key every request must carry, compared in
// constant time over SHA-256 digests so the length leaks nothing either.
// relayPreflightErrors relays every non-200 count_tokens preflight answer
// instead of only a 429 or 5xx.
export function createProxy({ key, config, log = () => {}, clientKey, relayPreflightErrors = false }) {
  if (typeof key !== "string" || !key) throw new Error("key is required");
  if (clientKey !== undefined && (typeof clientKey !== "string" || !clientKey || clientKey === key)) throw new Error("clientKey must be a non-empty string other than the key");
  const clientDigest = clientKey === undefined ? null : digest(clientKey);
  const admitted = (header) => clientDigest === null || (typeof header === "string" && timingSafeEqual(digest(header), clientDigest));
  const budget = createBudget(config.tokenCap);
  const state = { inFlight: 0, countTokensRequests: 0, preflights: 0 };
  const lib = config.upstream.protocol === "https:" ? https : http;
  const basePath = config.upstream.pathname.replace(/\/$/, "");
  const upstreamPath = (ctx, path) => basePath + path + (ctx.query === ALLOWED_QUERY ? `?${ALLOWED_QUERY}` : "");
  // An upstream socket idle for upstreamTimeoutMs, before or during the
  // response, is destroyed with an UPSTREAM_TIMEOUT error.
  const upstreamRequest = (ctx, path, body, onResponse) => {
    const req = lib.request({
      protocol: config.upstream.protocol,
      hostname: config.upstream.hostname,
      port: config.upstream.port || undefined,
      method: "POST",
      path: upstreamPath(ctx, path),
      headers: forwardHeaders(ctx.headers, key, body.length),
      timeout: config.upstreamTimeoutMs,
    }, onResponse);
    req.on("timeout", () => req.destroy(Object.assign(new Error("upstream timed out"), { code: UPSTREAM_TIMEOUT })));
    return req;
  };

  // The upstream's own input count for the checked request: { input }, or
  // { relay } for a 429 or 5xx answer, { refusal } for no answer, or {} for
  // any other failure. The first resolve wins.
  const preflight = (ctx) => new Promise((resolve) => {
    const subset = Object.fromEntries(COUNT_TOKENS_FIELDS.filter((f) => ctx.body[f] !== undefined).map((f) => [f, ctx.body[f]]));
    const body = Buffer.from(JSON.stringify(subset));
    const failed = (err) => resolve({ refusal: upstreamFailure(err) });
    const req = upstreamRequest(ctx, COUNT_TOKENS, body, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const raw = Buffer.concat(chunks);
        if (res.statusCode === 429 || res.statusCode >= 500 || (relayPreflightErrors && res.statusCode !== 200)) return resolve({ relay: { status: res.statusCode, headers: relayHeaders(res.headers), body: raw } });
        if (res.statusCode !== 200) return resolve({});
        try { resolve({ input: JSON.parse(raw.toString("utf8")).input_tokens }); } catch { resolve({}); }
      });
      res.on("error", failed);
      res.on("close", () => failed());
    });
    req.on("error", failed);
    req.end(body);
  });

  const server = http.createServer((req, res) => {
    const q = req.url.indexOf("?");
    const path = q < 0 ? req.url : req.url.slice(0, q);
    const query = q < 0 ? undefined : req.url.slice(q + 1);
    const chunks = [];
    let bytes = 0;
    let tooLarge = false;
    let clientGone = false;
    res.on("close", () => { clientGone = true; });
    const done = (status, extra = {}) => log({ method: req.method, path, status, ...extra });
    // Before any of the body is kept: an unadmitted client's body is drained unread.
    if (!admitted(req.headers["x-api-key"])) {
      req.resume();
      sendRefusal(res, refuse(401, "authentication_error", "invalid x-api-key"));
      done(401, { refused: "authentication_error" });
      return;
    }

    req.on("data", (c) => {
      if (tooLarge) return;
      bytes += c.length;
      if (bytes <= config.maxBodyBytes) {
        chunks.push(c);
        return;
      }
      tooLarge = true;
      // Read and drop the rest, answering the 413 once the body ends: the server closes a
      // `connection: close` socket when the response ends, so answering now would leave a client
      // still uploading with a reset, which it retries. A client still sending after DRAIN_MS gets
      // the 413 and the socket is closed (our decision: the drain stays bounded).
      drainTimer = setTimeout(() => { refuseTooLarge(); req.destroy(); }, DRAIN_MS);
      drainTimer.unref();
    });
    let drainTimer;
    let answered = false;
    const refuseTooLarge = () => {
      if (answered) return;
      answered = true;
      clearTimeout(drainTimer);
      sendRefusal(res, refuse(413, "request_too_large", "request body exceeds the proxy's size limit"));
      done(413, { refused: "request_too_large" });
    };
    req.on("end", async () => {
      if (tooLarge) return refuseTooLarge();
      const ctx = { method: req.method, path, query, headers: req.headers, raw: Buffer.concat(chunks), config, budget, state, preflight };
      try {
        await handle(ctx);
      } catch (err) {
        // A throw here (a body that passes the checks but breaks re-serialization, or a bug in a
        // check) must not end the process the whole capture job depends on. Nothing went upstream
        // on this path, so the reservation is released (our decision).
        ctx.reservation?.settle(0);
        ctx.release?.();
        if (!clientGone && !res.headersSent) sendRefusal(res, refuse(400, "invalid_request_error", "the proxy could not process this request"));
        else if (!res.writableEnded) res.destroy();
        done(400, { refused: "proxy_error", error: String(err?.name ?? "Error"), committed: budget.committed });
      }
    });

    async function handle(ctx) {
      const refusal = await runChecks(ctx);
      if (refusal) {
        ctx.release?.();
        if (!clientGone && refusal.relay) {
          res.writeHead(refusal.relay.status, { ...refusal.relay.headers, "content-length": refusal.relay.body.length });
          res.end(refusal.relay.body);
        } else if (!clientGone) sendRefusal(res, refusal);
        done(refusal.status, { refused: refusal.type, ...refusal.log, committed: budget.committed });
        return;
      }
      if (clientGone) {
        ctx.reservation?.settle(0);
        ctx.release();
        done(499, { committed: budget.committed });
        return;
      }
      forward(res, ctx, done);
    }
  });

  function forward(res, ctx, done) {
    const { reservation } = ctx;
    const reserved = reservation?.tokens ?? 0;
    let meter = null;
    let finished = false;
    const settle = (used) => {
      reservation?.settle(used);
      ctx.release();
      done(res.statusCode, { reserved, used, committed: budget.committed });
    };
    const abandoned = () => Math.max(reserved, meter?.total() ?? 0);
    // Upstream sees exactly the object the checks passed.
    const body = Buffer.from(JSON.stringify(ctx.body));

    const upReq = upstreamRequest(ctx, ctx.path, body, (upRes) => {
      const streaming = /^text\/event-stream/i.test(upRes.headers["content-type"] ?? "");
      meter = createUsageMeter(streaming);
      res.writeHead(upRes.statusCode, relayHeaders(upRes.headers));
      res.flushHeaders();
      upRes.on("data", (c) => {
        meter.feed(c);
        res.write(c);
      });
      upRes.on("end", () => {
        finished = true;
        meter.end();
        res.end();
        const ok = upRes.statusCode >= 200 && upRes.statusCode < 300;
        // An error status with no usage commits nothing. A success commits
        // its usage, except a stream that ended before its message_delta
        // (an incomplete response) or a body with no usage: those commit at
        // least the reservation (our decision).
        if (!ok) settle(meter.total());
        else if (streaming ? !meter.sawDelta : !meter.seen) settle(abandoned());
        else settle(meter.total());
      });
      // Upstream dropped or stalled mid-response: drop the client too, so it
      // sees a dropped connection rather than a stall, and commit as for a
      // client disconnect (our decision). Claude Code's handling of a dropped
      // connection: errors#automatic-retries, see the refusal-status pointer.
      upRes.on("error", () => {});
      upRes.on("close", () => {
        if (finished) return;
        finished = true;
        meter.end();
        res.destroy();
        settle(abandoned());
      });
    });

    // No response byte relayed yet: a retryable answer either way. Once the
    // body was fully written upstream, we assume generation may have run and
    // be billed even though no response byte came back (our decision), and Claude Code
    // resends a retryable failure, so the full reservation is committed;
    // it is released only when the connection failed before the body was
    // written (our decision). Bytes relayed: drop the client and commit as
    // for a disconnect.
    // Pointer: https://code.claude.com/docs/en/errors#automatic-retries
    // As of: 2026-11-06. Recheck trigger: that section changes which
    //   failures before any streamed response Claude Code retries.
    let bodySent = false;
    upReq.on("finish", () => { bodySent = true; });
    upReq.on("error", (err) => {
      if (finished) return;
      finished = true;
      if (!res.headersSent) {
        sendRefusal(res, upstreamFailure(err));
        settle(bodySent ? reserved : 0);
      } else {
        meter?.end();
        res.destroy();
        settle(abandoned());
      }
    });

    // The client went away before the response finished: stop generation
    // upstream and commit the reservation; an abandoned response counts as
    // fully spent (our decision).
    res.on("close", () => {
      if (finished) return;
      finished = true;
      upReq.destroy();
      meter?.end();
      settle(abandoned());
    });

    upReq.end(body);
  }

  return { server, budget, state };
}

function argValue(argv, name) {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : undefined;
}

async function readStdin() {
  const chunks = [];
  for await (const c of process.stdin) chunks.push(c);
  return Buffer.concat(chunks).toString("utf8").trim();
}

async function main(argv) {
  const socket = argValue(argv, "--socket");
  const configPath = argValue(argv, "--config");
  const port = argValue(argv, "--listen");
  if (!socket || !configPath || (port !== undefined && !(/^[1-9][0-9]{0,4}$/.test(port) && Number(port) <= 65535))) {
    process.stderr.write("usage: key-proxy.mjs --socket <path> --config <file.json> [--upstream <url>] [--listen <port>] < key\n");
    return 2;
  }
  let config;
  try {
    config = loadConfig(readFileSync(configPath, "utf8"), argValue(argv, "--upstream"));
  } catch (e) {
    process.stderr.write(`key-proxy: bad config: ${e.message}\n`);
    return 2;
  }
  const [key, clientKey] = (await readStdin()).split("\n").map((l) => l.trim());
  if (!key) {
    process.stderr.write("key-proxy: no key on stdin\n");
    return 2;
  }
  if (port !== undefined && (!clientKey || clientKey === key)) {
    process.stderr.write("key-proxy: --listen needs a client key on stdin's second line, other than the key\n");
    return 2;
  }
  const write = (entry) => process.stderr.write(`${JSON.stringify({ t: new Date().toISOString(), ...entry })}\n`);
  const log = (entry) => write({ listener: "socket", ...entry });
  const { server } = createProxy({ key, config, log });
  rmSync(socket, { force: true });
  await new Promise((resolve, reject) => server.once("error", reject).listen(socket, resolve));
  if (config.socketMode !== undefined) chmodSync(socket, config.socketMode);
  log({ listening: socket, models: config.models, tokenCap: config.tokenCap });
  const servers = [server];
  if (port !== undefined) {
    const loopbackLog = (entry) => write({ listener: "loopback", ...entry });
    const loopbackConfig = { ...config, tokenCap: config.driverTokenCap };
    const loopback = createProxy({ key, config: loopbackConfig, log: loopbackLog, clientKey, relayPreflightErrors: true }).server;
    await new Promise((resolve, reject) => loopback.once("error", reject).listen(Number(port), "127.0.0.1", resolve));
    servers.push(loopback);
    loopbackLog({ listening: `127.0.0.1:${port}`, models: config.models, tokenCap: loopbackConfig.tokenCap });
  }
  let open = servers.length;
  const stop = () => servers.forEach((s) => s.close(() => { open -= 1; if (open === 0) process.exit(0); }));
  process.on("SIGTERM", stop);
  process.on("SIGINT", stop);
  return null;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main(process.argv.slice(2)).then((code) => {
    if (code !== null) process.exit(code);
  }, (e) => {
    process.stderr.write(`key-proxy: ${e.message}\n`);
    process.exit(1);
  });
}
