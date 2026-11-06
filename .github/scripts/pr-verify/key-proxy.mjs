// The key proxy: the only path from pr-verify's driven Claude Code to the
// Messages API. It runs as its own OS user, holds the real key (read from
// stdin, never argv or env) and listens on a unix socket, so pull request code
// in the no-network sandbox never sees the key. Every request passes an
// ordered pipeline of checks (path, size, parse, model, max_tokens, server
// tools, cap reservation); one that passes goes upstream with the client's
// credential replaced, and the response is relayed byte for byte as it
// arrives. One budget holds the committed and in-flight reserved tokens, so
// concurrent requests cannot pass the per-job cap together.
//
//   node key-proxy.mjs --socket <path> --config <file.json> [--upstream <url>] < key
//
// Config (JSON, read from the base branch by the workflow, never the head):
//   tokenCap          per-job token budget (input, cache and output tokens)
//   models            model ids the driven session may use
//   maxTokensCeiling  largest max_tokens a /v1/messages request may ask for
//   maxBodyBytes      largest request body accepted
//   bytesPerToken     divisor for the input estimate from body size (default 3)
//   upstream          API base URL (default https://api.anthropic.com)
//   socketMode        octal mode set on the socket after listen, e.g. "660"
//
// It logs one JSON line per request to stderr: method, path without query,
// status and token counts. Never the key, a header value or a body.
import { chmodSync, readFileSync, rmSync } from "node:fs";
import http from "node:http";
import https from "node:https";
import process from "node:process";
import { pathToFileURL } from "node:url";

export const ALLOWED_PATHS = Object.freeze(["/v1/messages", "/v1/messages/count_tokens"]);
const COUNT_TOKENS = "/v1/messages/count_tokens";
const DEFAULT_UPSTREAM = "https://api.anthropic.com";
// anthropic-* carries the API version and betas; the gateway guide says to
// forward it as an open list. x-claude-code-* is session attribution.
const FORWARD_PREFIX = /^(anthropic-|x-claude-code-)/;
const FORWARD_NAMED = new Set(["content-type", "accept", "user-agent"]);
const HOP_BY_HOP = new Set(["connection", "keep-alive", "transfer-encoding", "proxy-authenticate", "proxy-authorization", "te", "trailer", "trailers", "upgrade"]);
// Counted toward the cap. Cache reads and writes are counted in full though
// they bill differently: the cap is a token count, not a price (judgment).
const USAGE_FIELDS = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"];

// Refusal statuses Claude Code does not retry. Every refusal carries
// `x-should-retry: false`, which Claude Code reads as not retryable. The cap
// refusal is a 429 shaped like a gateway spend limit, which Claude Code shows
// without retrying; a policy refusal is a 403 and an oversized body a 413,
// neither in the automatic-retry list (the 403 retry there needs an
// apiKeyHelper, which the driven session does not use). Not 400 or 422: the
// gateway guide says Claude Code may resend after one whose cause it does not
// recognize.
// Pointer: https://code.claude.com/docs/en/llm-gateway-protocol#response-headers,
//   https://code.claude.com/docs/en/errors#automatic-retries,
//   https://code.claude.com/docs/en/errors#spend-limit-reached
// As of: 2026-11-05 (Claude Code 2.1.318).
// Recheck trigger: the automatic-retries lists, the x-should-retry row or the
//   spend-limit section changes.
const refuse = (status, type, message) => ({ status, type, message });
const policy = (message) => refuse(403, "permission_error", message);

export function loadConfig(raw, upstreamOverride) {
  const c = typeof raw === "string" ? JSON.parse(raw) : raw;
  const positiveInt = (name) => {
    if (!Number.isInteger(c[name]) || c[name] <= 0) throw new Error(`config ${name} must be a positive integer`);
    return c[name];
  };
  if (!Array.isArray(c.models) || c.models.length === 0 || !c.models.every((m) => typeof m === "string" && m)) {
    throw new Error("config models must be a non-empty list of model ids");
  }
  const bytesPerToken = c.bytesPerToken ?? 3;
  if (typeof bytesPerToken !== "number" || !(bytesPerToken > 0)) throw new Error("config bytesPerToken must be a positive number");
  const upstream = new URL(upstreamOverride ?? c.upstream ?? DEFAULT_UPSTREAM);
  if (upstream.protocol !== "https:" && upstream.protocol !== "http:") throw new Error("config upstream must be an http(s) URL");
  if (c.socketMode !== undefined && !/^[0-7]{3,4}$/.test(String(c.socketMode))) throw new Error("config socketMode must be an octal string");
  return Object.freeze({
    tokenCap: positiveInt("tokenCap"),
    models: Object.freeze([...c.models]),
    maxTokensCeiling: positiveInt("maxTokensCeiling"),
    maxBodyBytes: positiveInt("maxBodyBytes"),
    bytesPerToken,
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
    else if (event?.type === "message_delta") take(event.usage);
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
    total() { return USAGE_FIELDS.reduce((sum, f) => sum + (usage[f] ?? 0), 0); },
  };
}

const isServerToolBlock = (b) => b && typeof b === "object" && typeof b.type === "string"
  && (b.type === "server_tool_use" || b.type === "mcp_tool_use" || (b.type.endsWith("_tool_result") && b.type !== "tool_result"));

// The ordered pipeline. Each check returns null (allow) or a refusal.
// Server tools are refused because they reach the network or run code with
// the held key: a tools[] entry is allowed only as a custom tool (no type, or
// type "custom"), which fails closed on any new server tool type.
export const CHECKS = Object.freeze([
  function path(ctx) {
    return ctx.method === "POST" && ALLOWED_PATHS.includes(ctx.path) ? null : refuse(404, "not_found_error", "not found");
  },
  function size(ctx) {
    return ctx.bytes > ctx.config.maxBodyBytes ? refuse(413, "request_too_large", "request body exceeds the proxy's size limit") : null;
  },
  function parse(ctx) {
    try { ctx.body = JSON.parse(ctx.raw.toString("utf8")); } catch { return refuse(400, "invalid_request_error", "request body is not JSON"); }
    return ctx.body && typeof ctx.body === "object" && !Array.isArray(ctx.body) ? null : refuse(400, "invalid_request_error", "request body is not a JSON object");
  },
  function model(ctx) {
    return ctx.config.models.includes(ctx.body.model) ? null : policy(`model not allowed through this proxy: ${String(ctx.body.model).slice(0, 80)}`);
  },
  function maxTokens(ctx) {
    if (ctx.path === COUNT_TOKENS) return null;
    const m = ctx.body.max_tokens;
    if (!Number.isInteger(m) || m <= 0) return policy("max_tokens is required");
    return m > ctx.config.maxTokensCeiling ? policy(`max_tokens exceeds this proxy's ceiling of ${ctx.config.maxTokensCeiling}`) : null;
  },
  function serverTools(ctx) {
    const { body } = ctx;
    if (body.mcp_servers !== undefined) return policy("mcp_servers is not allowed through this proxy");
    for (const t of Array.isArray(body.tools) ? body.tools : []) {
      if (t && typeof t === "object" && t.type !== undefined && t.type !== "custom") {
        return policy(`server tools are not allowed through this proxy: Input tag '${String(t.type).slice(0, 80)}'`);
      }
    }
    for (const m of Array.isArray(body.messages) ? body.messages : []) {
      if (Array.isArray(m?.content) && m.content.some(isServerToolBlock)) return policy("server tool blocks are not allowed through this proxy");
    }
    return null;
  },
  // count_tokens is free and returns no usage, so it reserves nothing.
  function cap(ctx) {
    if (ctx.path === COUNT_TOKENS) return null;
    const estimate = Math.ceil(ctx.bytes / ctx.config.bytesPerToken) + ctx.body.max_tokens;
    ctx.reservation = ctx.budget.reserve(estimate);
    return ctx.reservation ? null : refuse(429, "rate_limit_error", "spend limit reached (per-job token cap)");
  },
]);

export function runChecks(ctx) {
  for (const check of CHECKS) {
    const r = check(ctx);
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
    if (FORWARD_PREFIX.test(name) || FORWARD_NAMED.has(name)) out[name] = value;
  }
  out["x-api-key"] = key;
  out["content-length"] = String(length);
  return out;
};

const relayHeaders = (incoming) => Object.fromEntries(Object.entries(incoming).filter(([name]) => !HOP_BY_HOP.has(name)));

export function createProxy({ key, config, log = () => {} }) {
  if (typeof key !== "string" || !key) throw new Error("key is required");
  const budget = createBudget(config.tokenCap);
  const lib = config.upstream.protocol === "https:" ? https : http;
  const basePath = config.upstream.pathname.replace(/\/$/, "");

  const server = http.createServer((req, res) => {
    const [path] = req.url.split("?");
    const chunks = [];
    let bytes = 0;
    const done = (status, extra = {}) => log({ method: req.method, path, status, ...extra });

    req.on("data", (c) => {
      bytes += c.length;
      if (bytes <= config.maxBodyBytes) chunks.push(c);
    });
    req.on("end", () => {
      const ctx = { method: req.method, path, bytes, raw: Buffer.concat(chunks), config, budget };
      const refusal = runChecks(ctx);
      if (refusal) {
        sendRefusal(res, refusal);
        done(refusal.status, { refused: refusal.type, committed: budget.committed });
        return;
      }
      forward(req, res, ctx, done);
    });
  });

  function forward(req, res, ctx, done) {
    const reservation = ctx.reservation;
    let meter = null;
    let finished = false;
    const settle = (used) => {
      reservation?.settle(used);
      done(res.statusCode, { reserved: reservation?.tokens ?? 0, used, committed: budget.committed });
    };

    const upReq = lib.request({
      protocol: config.upstream.protocol,
      hostname: config.upstream.hostname,
      port: config.upstream.port || undefined,
      method: "POST",
      path: basePath + req.url,
      headers: forwardHeaders(req.headers, key, ctx.raw.length),
    }, (upRes) => {
      meter = createUsageMeter(/^text\/event-stream/i.test(upRes.headers["content-type"] ?? ""));
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
        // A completed response with no usage commits nothing on an error
        // status and the whole reservation on a success.
        const ok = upRes.statusCode >= 200 && upRes.statusCode < 300;
        settle(meter.seen ? meter.total() : ok ? reservation?.tokens ?? 0 : 0);
      });
      upRes.on("error", () => {});
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
        settle(Math.max(reservation?.tokens ?? 0, meter?.total() ?? 0));
      }
    });

    // The client went away before the response finished: stop generation
    // upstream and commit the reservation, since the tokens may be billed.
    res.on("close", () => {
      if (finished) return;
      finished = true;
      upReq.destroy();
      meter?.end();
      settle(Math.max(reservation?.tokens ?? 0, meter?.total() ?? 0));
    });

    upReq.end(ctx.raw);
  }

  return { server, budget };
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
