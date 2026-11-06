// The key proxy: the only path from pr-verify's driven Claude Code to the
// Messages API. It runs as its own OS user, holds the real key (read from
// stdin, never argv or env) and listens on a unix socket, so pull request code
// in the no-network sandbox never sees the key. Every request passes an
// ordered pipeline of checks (path, query, size, parse, body keys, model,
// max_tokens, betas, server tools, content, count_tokens limits, in-flight
// slot, cap reservation). One that passes goes upstream as the re-serialized
// checked object with the client's credential replaced, and the response is
// relayed as it arrives. One budget holds the committed and in-flight reserved
// tokens, so concurrent requests cannot pass the per-job cap together; each
// /v1/messages reservation is the upstream's own count_tokens figure for the
// request plus its max_tokens.
//
//   node key-proxy.mjs --socket <path> --config <file.json> [--upstream <url>] < key
//
// Config (JSON, read from the base branch by the workflow, never the head):
//   tokenCap               per-job token budget (input, cache and output tokens)
//   models                 model ids the driven session may use
//   maxTokensCeiling       largest max_tokens a /v1/messages request may ask for
//   maxBodyBytes           largest request body accepted
//   maxInFlight            concurrent forwarded requests, count_tokens included
//   maxCountTokensRequests client count_tokens requests allowed per job
//   betas                  anthropic-beta values a request may name
//   bodyKeys               top-level request body keys a request may carry
//   blockTypes             content block types allowed in messages and system
//   upstream               API base URL (default https://api.anthropic.com)
//   socketMode             octal mode set on the socket after listen, e.g. "660"
//
// It logs one JSON line per request to stderr: method, path without query,
// status and token counts. Never the key, a header value or a body.
import { chmodSync, readFileSync, rmSync } from "node:fs";
import http from "node:http";
import https from "node:https";
import process from "node:process";
import { pathToFileURL } from "node:url";

export const ALLOWED_PATHS = Object.freeze(["/v1/messages", "/v1/messages/count_tokens"]);
const MESSAGES = "/v1/messages";
const COUNT_TOKENS = "/v1/messages/count_tokens";
const DEFAULT_UPSTREAM = "https://api.anthropic.com";
// The one query the driven session sends; any other is refused (our decision).
const ALLOWED_QUERY = "beta=true";
// Request headers forwarded upstream (our allowlist): the API version and
// betas, session attribution, and content negotiation. accept-encoding is
// never forwarded, so the response arrives uncompressed and usage is readable.
const FORWARD_NAMED = new Set(["anthropic-version", "anthropic-beta", "accept", "user-agent"]);
const FORWARD_PREFIX = /^x-claude-code-/;
// Response headers relayed to the client (our allowlist).
const RELAY_NAMED = new Set(["content-type", "cache-control", "request-id", "x-should-retry", "retry-after"]);
const RELAY_PREFIX = /^anthropic-ratelimit-/;
// Content sources that carry their data inline; any other type (url, file)
// makes the API fetch or look up something the client chose (our decision).
const SOURCE_TYPES = Object.freeze(["base64", "text", "content"]);
// Body fields the count_tokens preflight forwards.
// Pointer: https://platform.claude.com/docs/en/api/messages-count-tokens (Body parameters)
// As of: 2026-11-05. Recheck trigger: that section adds or removes a parameter.
const COUNT_TOKENS_FIELDS = Object.freeze(["messages", "model", "cache_control", "output_config", "speed", "system", "thinking", "tool_choice", "tools"]);
// Counted toward the cap. Cache reads and writes are counted in full though
// they bill differently: the cap is a token count, not a price (judgment).
const USAGE_FIELDS = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"];

// Refusal statuses Claude Code does not retry. Every refusal carries
// `x-should-retry: false`, which Claude Code reads as not retryable. The cap
// refusal is a 429 shaped like a gateway spend limit, which Claude Code shows
// without retrying; a policy refusal is a 403 and an oversized body a 413,
// neither in the automatic-retry list (the 403 retry there needs an
// apiKeyHelper, which the driven session does not use). Not 400 or 422, which
// Claude Code may resend after once when it does not recognize the cause.
// Pointer: https://code.claude.com/docs/en/llm-gateway-protocol#response-headers (x-should-retry row),
//   https://code.claude.com/docs/en/llm-gateway-protocol#retry-without-tool-search,
//   https://code.claude.com/docs/en/errors#automatic-retries,
//   https://code.claude.com/docs/en/errors#spend-limit-reached
// As of: 2026-11-05 (Claude Code 2.1.318).
// Recheck trigger: the automatic-retries lists, the x-should-retry row, the
//   tool-search retry or the spend-limit section changes.
const refuse = (status, type, message) => ({ status, type, message });
const policy = (message) => refuse(403, "permission_error", message);
const spendLimit = (what) => refuse(429, "rate_limit_error", `spend limit reached (${what})`);
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
    models: nonEmpty("models"),
    maxTokensCeiling: positiveInt("maxTokensCeiling"),
    maxBodyBytes: positiveInt("maxBodyBytes"),
    maxInFlight: positiveInt("maxInFlight"),
    maxCountTokensRequests: positiveInt("maxCountTokensRequests"),
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
// As of: 2026-11-05. Recheck trigger: that section changes what message_delta usage holds.
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

// Content blocks in messages and system, walked at every depth through the
// places the API reads nested blocks (tool_result content, a content-type
// source). tool_use input and tool schemas are not walked: their `type`
// strings are JSON values, not block types.
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
    const unknown = String(header).split(",").map((b) => b.trim()).filter(Boolean).find((b) => !ctx.config.betas.includes(b));
    return unknown === undefined ? null : policy(`anthropic-beta value not allowed through this proxy: ${clip(unknown)}`);
  },
  // Server tools reach the network or run code with the held key: a tools[]
  // entry is allowed only as a custom tool (no type, or type "custom"), which
  // fails closed on any new server tool type (our decision).
  function serverTools(ctx) {
    const { body } = ctx;
    if (body.mcp_servers !== undefined) return policy("mcp_servers is not allowed through this proxy");
    for (const t of Array.isArray(body.tools) ? body.tools : []) {
      if (t && typeof t === "object" && t.type !== undefined && t.type !== "custom") {
        return policy(`server tools are not allowed through this proxy: ${clip(t.type)}`);
      }
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
  // Client count_tokens is free, but it is limited per job and stops once the
  // cap is spent, so it cannot be used as an unmetered channel.
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
    const input = await ctx.preflight(ctx);
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
  res.writeHead(r.status, { "content-type": "application/json", "x-should-retry": "false", "content-length": Buffer.byteLength(body), ...(r.status === 413 ? { connection: "close" } : {}) });
  res.end(body);
};

const forwardHeaders = (incoming, key, length) => {
  const out = {};
  for (const [name, value] of Object.entries(incoming)) {
    if (FORWARD_NAMED.has(name) || FORWARD_PREFIX.test(name)) out[name] = value;
  }
  out["content-type"] = "application/json";
  out["x-api-key"] = key;
  out["content-length"] = String(length);
  return out;
};

const relayHeaders = (incoming) => Object.fromEntries(Object.entries(incoming).filter(([name]) => RELAY_NAMED.has(name) || RELAY_PREFIX.test(name)));

export function createProxy({ key, config, log = () => {} }) {
  if (typeof key !== "string" || !key) throw new Error("key is required");
  const budget = createBudget(config.tokenCap);
  const state = { inFlight: 0, countTokensRequests: 0 };
  const lib = config.upstream.protocol === "https:" ? https : http;
  const basePath = config.upstream.pathname.replace(/\/$/, "");
  const upstreamPath = (ctx, path) => basePath + path + (ctx.query === ALLOWED_QUERY ? `?${ALLOWED_QUERY}` : "");
  const upstreamRequest = (ctx, path, body, onResponse) => lib.request({
    protocol: config.upstream.protocol,
    hostname: config.upstream.hostname,
    port: config.upstream.port || undefined,
    method: "POST",
    path: upstreamPath(ctx, path),
    headers: forwardHeaders(ctx.headers, key, body.length),
  }, onResponse);

  // The upstream's own input count for the checked request; null on failure.
  const preflight = (ctx) => new Promise((resolve) => {
    const subset = Object.fromEntries(COUNT_TOKENS_FIELDS.filter((f) => ctx.body[f] !== undefined).map((f) => [f, ctx.body[f]]));
    const body = Buffer.from(JSON.stringify(subset));
    const req = upstreamRequest(ctx, COUNT_TOKENS, body, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        if (res.statusCode !== 200) return resolve(null);
        try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")).input_tokens); } catch { resolve(null); }
      });
      res.on("error", () => resolve(null));
    });
    req.on("error", () => resolve(null));
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

    req.on("data", (c) => {
      if (tooLarge) return;
      bytes += c.length;
      if (bytes <= config.maxBodyBytes) {
        chunks.push(c);
        return;
      }
      tooLarge = true;
      sendRefusal(res, refuse(413, "request_too_large", "request body exceeds the proxy's size limit"));
      req.destroy();
      done(413, { refused: "request_too_large" });
    });
    req.on("end", async () => {
      if (tooLarge) return;
      const ctx = { method: req.method, path, query, headers: req.headers, raw: Buffer.concat(chunks), config, budget, state, preflight };
      const refusal = await runChecks(ctx);
      if (refusal) {
        ctx.release?.();
        if (!clientGone) sendRefusal(res, refusal);
        done(refusal.status, { refused: refusal.type, committed: budget.committed });
        return;
      }
      if (clientGone) {
        ctx.reservation?.settle(0);
        ctx.release();
        done(499, { committed: budget.committed });
        return;
      }
      forward(res, ctx, done);
    });
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
        // least the reservation.
        if (!ok) settle(meter.total());
        else if (streaming ? !meter.sawDelta : !meter.seen) settle(abandoned());
        else settle(meter.total());
      });
      // Upstream dropped mid-response: drop the client too, so it sees a
      // dropped connection rather than a stall, and commit as for a client
      // disconnect.
      upRes.on("error", () => {});
      upRes.on("close", () => {
        if (finished) return;
        finished = true;
        meter.end();
        res.destroy();
        settle(abandoned());
      });
    });

    upReq.on("error", () => {
      if (finished) return;
      finished = true;
      if (!res.headersSent) {
        sendRefusal(res, { status: 502, type: "api_error", message: "upstream unreachable" });
        settle(0);
      } else {
        meter?.end();
        res.destroy();
        settle(abandoned());
      }
    });

    // The client went away before the response finished: stop generation
    // upstream and commit the reservation, since the tokens may be billed.
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
  if (!socket || !configPath) {
    process.stderr.write("usage: key-proxy.mjs --socket <path> --config <file.json> [--upstream <url>] < key\n");
    return 2;
  }
  let config;
  try {
    config = loadConfig(readFileSync(configPath, "utf8"), argValue(argv, "--upstream"));
  } catch (e) {
    process.stderr.write(`key-proxy: bad config: ${e.message}\n`);
    return 2;
  }
  const key = await readStdin();
  if (!key) {
    process.stderr.write("key-proxy: no key on stdin\n");
    return 2;
  }
  const log = (entry) => process.stderr.write(`${JSON.stringify({ t: new Date().toISOString(), ...entry })}\n`);
  const { server } = createProxy({ key, config, log });
  rmSync(socket, { force: true });
  await new Promise((resolve, reject) => server.once("error", reject).listen(socket, resolve));
  if (config.socketMode !== undefined) chmodSync(socket, config.socketMode);
  log({ listening: socket, models: config.models, tokenCap: config.tokenCap });
  const stop = () => server.close(() => process.exit(0));
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
