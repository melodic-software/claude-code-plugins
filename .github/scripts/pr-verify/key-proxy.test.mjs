// key-proxy.mjs, the only path from pr-verify's driven Claude Code to the
// API: each guarantee tested against a local stub upstream over a real unix
// socket, plus the stdin key and never-log guarantees of the script itself.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { statSync, writeFileSync } from "node:fs";
import http from "node:http";
import path from "node:path";
import { after, test } from "node:test";
import { fileURLToPath } from "node:url";
import { tempDir } from "../../../lib/test-tmp.mjs";
import { createProxy, loadConfig } from "./key-proxy.mjs";

const SCRIPT = fileURLToPath(new URL("./key-proxy.mjs", import.meta.url));
// Built at run time so no key-shaped literal sits in the file.
const KEY = `${"sk-ant-"}api03-${"K".repeat(40)}`;
const MODELS = ["model-main", "model-title"];
// Measured from the driven session (Claude Code 2.1.318): its betas and
// top-level body keys. Block types are the ones a restricted session sends.
const MAIN_BETAS = "claude-code-20250219,interleaved-thinking-2025-05-14,context-management-2025-06-27,per-turn-control-2026-07-01,mid-conversation-tool-changes-2026-07-01,thinking-token-count-2026-05-13,advanced-tool-use-2025-11-20,effort-2025-11-24,thinking-display-updates-2026-08-18";
const TITLE_BETAS = "interleaved-thinking-2025-05-14,redact-thinking-2026-02-12,context-management-2025-06-27,per-turn-control-2026-07-01,mid-conversation-tool-changes-2026-07-01,thinking-token-count-2026-05-13,effort-2025-11-24,structured-outputs-2025-12-15";
const BETAS = [...new Set(`${MAIN_BETAS},${TITLE_BETAS}`.split(","))];
const BODY_KEYS = ["context_management", "max_tokens", "messages", "metadata", "model", "output_config", "stream", "system", "thinking", "tools"];
const BLOCK_TYPES = ["text", "image", "document", "tool_use", "tool_result", "thinking", "redacted_thinking"];
const BASE_CONFIG = {
  tokenCap: 1_000_000, driverTokenCap: 1_000_000, models: MODELS, maxTokensCeiling: 1000, maxBodyBytes: 100_000, maxInFlight: 8,
  maxCountTokensRequests: 100, maxPreflightRequests: 1000, betas: BETAS, bodyKeys: BODY_KEYS, blockTypes: BLOCK_TYPES,
  // Longer than any test holds an upstream idle; the timeout tests override it.
  upstreamTimeoutMs: 10_000,
};

const servers = [];
after(() => {
  for (const s of servers) {
    s.closeAllConnections?.();
    s.close();
  }
});

// A stub upstream. /v1/messages requests go to `handler(req, body, res)` and
// are recorded in `seen`; count_tokens requests are recorded in `counts` and
// answered with `countTokens` input tokens (a function may answer instead).
async function stubUpstream(handler, { countTokens = 50 } = {}) {
  const seen = [];
  const counts = [];
  const server = http.createServer((req, res) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const body = Buffer.concat(chunks);
      const entry = { method: req.method, url: req.url, headers: req.headers, body, closed: new Promise((r) => res.on("close", r)) };
      if (req.url.startsWith("/v1/messages/count_tokens")) {
        counts.push(entry);
        if (typeof countTokens === "function") return countTokens(res);
        res.writeHead(200, { "content-type": "application/json" });
        return res.end(JSON.stringify({ input_tokens: countTokens }));
      }
      seen.push(entry);
      handler(req, body, res, entry);
    });
  });
  servers.push(server);
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  return { url: `http://127.0.0.1:${server.address().port}`, seen, counts, server };
}

const okJson = (usage = { input_tokens: 1, output_tokens: 1 }) => (_req, _body, res) => {
  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify({ type: "message", content: [], usage }));
};

async function startProxy(upstream, overrides = {}, options = {}) {
  const config = loadConfig({ ...BASE_CONFIG, ...overrides }, upstream.url);
  const logs = [];
  const { server, budget } = createProxy({ key: KEY, config, log: (e) => logs.push(e), ...options });
  servers.push(server);
  const socket = path.join(tempDir("kp-"), "p.sock");
  await new Promise((r) => server.listen(socket, r));
  return { socket, budget, logs };
}

// One request over the proxy's socket; resolves with status, headers, body.
function call(socket, { method = "POST", url = "/v1/messages", headers = {}, body } = {}) {
  const raw = body === undefined ? undefined : Buffer.isBuffer(body) ? body : Buffer.from(typeof body === "string" ? body : JSON.stringify(body));
  return new Promise((resolve, reject) => {
    const req = http.request({ socketPath: socket, method, path: url, headers: { "content-type": "application/json", ...headers } }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks).toString("utf8") }));
    });
    req.on("error", reject);
    req.end(raw);
  });
}

const message = (extra = {}) => ({ model: "model-main", max_tokens: 100, messages: [{ role: "user", content: "hi" }], ...extra });
const countBody = (extra = {}) => ({ model: "model-main", messages: [{ role: "user", content: "hi" }], ...extra });
const sse = (type, data) => `event: ${type}\ndata: ${JSON.stringify({ type, ...data })}\n\n`;
const tick = () => new Promise((r) => setImmediate(r));
async function until(cond) {
  for (let i = 0; i < 500 && !cond(); i++) await new Promise((r) => setTimeout(r, 10));
  assert.ok(cond(), "condition not reached");
}
const assertRefused = (res, status, type) => {
  assert.equal(res.status, status);
  assert.equal(res.headers["x-should-retry"], "false");
  assert.equal(JSON.parse(res.body).error.type, type);
};

// Opens a request whose response the test controls; resolves on the first
// response byte with the request and response.
function openStream(socket, body) {
  return new Promise((resolve, reject) => {
    const req = http.request({ socketPath: socket, method: "POST", path: "/v1/messages", headers: { "content-type": "application/json" } }, (res) => resolve({ req, res }));
    req.on("error", reject);
    req.end(JSON.stringify(body));
  });
}

test("path allowlist: only POST /v1/messages and /v1/messages/count_tokens reach upstream; everything else is 404", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up);
  const refused = [
    { method: "GET", url: "/v1/messages" },
    { method: "HEAD", url: "/api/hello" },
    { url: "/v1/messages/batches", body: message() },
    { url: "/v1/messages/", body: message() },
    { url: "/v1/x/../messages", body: message() },
    { url: "/v1/complete", body: message() },
  ];
  for (const r of refused) assert.equal((await call(socket, r)).status, 404, `${r.method ?? "POST"} ${r.url}`);
  assert.equal(up.seen.length + up.counts.length, 0);

  assert.equal((await call(socket, { body: message() })).status, 200);
  assert.equal((await call(socket, { url: "/v1/messages/count_tokens", body: countBody() })).status, 200);
  assert.deepEqual(up.seen.map((s) => `${s.method} ${s.url}`), ["POST /v1/messages"]);
  assert.equal(up.counts.at(-1).url, "/v1/messages/count_tokens");
});

test("query: exactly beta=true is forwarded; any other query is refused", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up);
  assert.equal((await call(socket, { url: "/v1/messages?beta=true", body: message() })).status, 200);
  assert.equal(up.seen[0].url, "/v1/messages?beta=true");
  for (const url of ["/v1/messages?beta=true&x=1", "/v1/messages?beta=false", "/v1/messages?", "/v1/messages/count_tokens?foo=1"]) {
    assertRefused(await call(socket, { url, body: message() }), 403, "permission_error");
  }
  assert.equal(up.seen.length, 1);
});

test("credential swap: the client's Authorization and x-api-key are stripped and x-api-key is the held key", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up);
  await call(socket, { body: message(), headers: { authorization: "Bearer client-token", "x-api-key": "dummy-client-key" } });
  for (const r of [up.counts[0], up.seen[0]]) {
    assert.equal(r.headers["x-api-key"], KEY);
    assert.equal(r.headers.authorization, undefined);
  }
});

test("request header allowlist: version, listed betas and x-claude-code-* pass; other headers are dropped; an unlisted beta is refused", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up);
  const headers = {
    "anthropic-version": "2023-06-01", "anthropic-beta": MAIN_BETAS, "x-claude-code-session-id": "s-1",
    "x-stainless-os": "Linux", "accept-encoding": "gzip, br, zstd", cookie: "a=b", "anthropic-workspace-id": "w",
  };
  assert.equal((await call(socket, { body: message(), headers })).status, 200);
  const h = up.seen[0].headers;
  assert.equal(h["anthropic-version"], "2023-06-01");
  assert.equal(h["anthropic-beta"], MAIN_BETAS);
  assert.equal(h["x-claude-code-session-id"], "s-1");
  for (const dropped of ["x-stainless-os", "cookie", "anthropic-workspace-id"]) assert.equal(h[dropped], undefined, dropped);
  // The client's gzip/br/zstd is replaced: both upstream requests ask for identity.
  assert.equal(h["accept-encoding"], "identity");
  assert.equal(up.counts[0].headers["accept-encoding"], "identity");
  assert.equal((await call(socket, { body: message({ model: "model-title" }), headers: { "anthropic-beta": TITLE_BETAS } })).status, 200);

  assertRefused(await call(socket, { body: message(), headers: { "anthropic-beta": `${MAIN_BETAS},files-api-2025-04-14` } }), 403, "permission_error");
  assert.equal(up.seen.length, 2);
});

test("a beta refusal names each refused beta in the response body and the log line", async () => {
  const up = await stubUpstream(okJson());
  const { socket, logs } = await startProxy(up);
  const header = `${MAIN_BETAS},files-api-2025-04-14,mcp-client-2025-04-04,files-api-2025-04-14`;
  const res = await call(socket, { body: message(), headers: { "anthropic-beta": header } });
  assertRefused(res, 403, "permission_error");
  const msg = JSON.parse(res.body).error.message;
  assert.ok(msg.includes("files-api-2025-04-14, mcp-client-2025-04-04"), msg);
  assert.ok(!msg.includes("claude-code-20250219"), "an allowed beta is not named");
  assert.deepEqual(logs.at(-1).betas, ["files-api-2025-04-14", "mcp-client-2025-04-04"]);
  assert.equal(logs.at(-1).status, 403);

  // Twelve unknown betas: ten are named, the rest counted.
  const many = Array.from({ length: 12 }, (_, i) => `x-beta-${i}`);
  const capped = await call(socket, { body: message(), headers: { "anthropic-beta": many.join(",") } });
  assert.deepEqual(logs.at(-1).betas, many.slice(0, 10));
  assert.ok(JSON.parse(capped.body).error.message.includes("x-beta-9 (+2 more)"));
  assert.equal(up.seen.length + up.counts.length, 0);
});

test("body canonicalization: upstream receives the checked object re-serialized, so a duplicate key cannot smuggle its first value", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up);
  const raw = '{ "messages":[{"role":"user","content":"hi"}],\n  "max_tokens" : 100, "model":"model-title", "metadata":{"z":1,"a":2} }';
  assert.equal((await call(socket, { body: raw })).status, 200);
  assert.deepEqual(JSON.parse(up.seen[0].body), { messages: [{ role: "user", content: "hi" }], max_tokens: 100, model: "model-title", metadata: { z: 1, a: 2 } });
  assert.equal(up.seen[0].headers["content-type"], "application/json");
  assert.equal(Number(up.seen[0].headers["content-length"]), up.seen[0].body.length);

  const dup = '{"model":"model-main","max_tokens":100,"messages":[],"tools":[{"type":"web_fetch_20250910","name":"web_fetch"}],"tools":[]}';
  assert.equal((await call(socket, { body: dup })).status, 200);
  assert.deepEqual(JSON.parse(up.seen[1].body), { model: "model-main", max_tokens: 100, messages: [], tools: [] });
  assert.ok(!up.seen[1].body.includes("web_fetch"));

  // A lone 0xff byte: a lenient decoder would turn it into U+FFFD and parse.
  const badUtf8 = Buffer.concat([Buffer.from('{"model":"model-main","max_tokens":100,"messages":[{"role":"user","content":"'), Buffer.from([0xff]), Buffer.from('"}]}')]);
  assert.equal((await call(socket, { body: badUtf8 })).status, 400);
  assert.equal(up.seen.length, 2);
});

test("body key allowlist: the measured top-level keys pass and any other key is refused", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up);
  const full = message({ context_management: {}, metadata: { user_id: "u" }, output_config: {}, stream: false, system: "s", thinking: { type: "adaptive" }, tools: [] });
  assert.equal((await call(socket, { body: full })).status, 200);
  for (const extra of [{ container: "c" }, { mcp_servers: [] }, { service_tier: "auto" }]) {
    assertRefused(await call(socket, { body: message(extra) }), 403, "permission_error");
  }
  assert.equal(up.seen.length, 1);
});

test("SSE streams are relayed unbuffered, ping events included", { timeout: 10_000 }, async () => {
  let release;
  const released = new Promise((r) => (release = r));
  const up = await stubUpstream(async (_req, _body, res) => {
    res.writeHead(200, { "content-type": "text/event-stream" });
    res.write(sse("message_start", { message: { usage: { input_tokens: 3, output_tokens: 1 } } }));
    res.write(sse("ping", {}));
    // The rest is sent only after the client has seen the ping: a proxy that
    // buffers never delivers it, and the test fails on its timeout.
    await released;
    res.write(sse("message_delta", { delta: { stop_reason: "end_turn" }, usage: { output_tokens: 2 } }));
    res.end(sse("message_stop", {}));
  });
  const { socket } = await startProxy(up);
  const { res } = await openStream(socket, message({ stream: true }));
  assert.equal(res.headers["content-type"], "text/event-stream");
  const text = await new Promise((resolve) => {
    let got = "";
    res.on("data", (c) => {
      got += c;
      if (got.includes("event: ping")) release();
    });
    res.on("end", () => resolve(got));
  });
  assert.match(text, /event: message_start[\s\S]*event: ping[\s\S]*event: message_delta[\s\S]*event: message_stop/);
});

test("upstream errors keep their status and body; only the allowlisted response headers are relayed", async () => {
  const errorBody = '{"type":"error","error":{"type":"invalid_request_error","message":"Unexpected value(s) `x-2026` for the `anthropic-beta` header"}}';
  const up = await stubUpstream((_req, _body, res) => {
    res.writeHead(400, {
      "content-type": "application/json", "x-should-retry": "true", "request-id": "req_1", "retry-after": "5",
      "anthropic-ratelimit-unified-status": "allowed", "set-cookie": "s=1", "x-envoy-upstream-service-time": "9", server: "stub",
    });
    res.end(errorBody);
  });
  const { socket } = await startProxy(up);
  const res = await call(socket, { body: message() });
  assert.equal(res.status, 400);
  assert.equal(res.body, errorBody);
  assert.equal(res.headers["x-should-retry"], "true");
  assert.equal(res.headers["request-id"], "req_1");
  assert.equal(res.headers["retry-after"], "5");
  assert.equal(res.headers["anthropic-ratelimit-unified-status"], "allowed");
  for (const dropped of ["set-cookie", "x-envoy-upstream-service-time", "server"]) assert.equal(res.headers[dropped], undefined, dropped);
});

test("a model allowlist of several models and a max_tokens ceiling", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up, { maxTokensCeiling: 1000 });
  assert.equal((await call(socket, { body: message({ model: "model-main" }) })).status, 200);
  assert.equal((await call(socket, { body: message({ model: "model-title" }) })).status, 200);
  assert.equal((await call(socket, { body: message({ max_tokens: 1000 }) })).status, 200);
  const before = up.seen.length;
  for (const body of [message({ model: "model-other" }), message({ max_tokens: 1001 }), message({ max_tokens: undefined })]) {
    assertRefused(await call(socket, { body }), 403, "permission_error");
  }
  assert.equal(up.seen.length, before);
  // count_tokens takes no max_tokens, but its model is still checked.
  // Pointer: https://platform.claude.com/docs/en/api/messages-count-tokens (Body parameters)
  // As of: 2026-11-06. Recheck trigger: that section adds max_tokens.
  assert.equal((await call(socket, { url: "/v1/messages/count_tokens", body: countBody({ model: "model-title" }) })).status, 200);
  assertRefused(await call(socket, { url: "/v1/messages/count_tokens", body: countBody({ model: "model-other" }) }), 403, "permission_error");
});

test("requests carrying server tools are refused", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up, { bodyKeys: [...BODY_KEYS, "mcp_servers"] });
  const custom = { name: "Read", description: "read", input_schema: { type: "object", properties: { path: { type: "string" } } } };
  assert.equal((await call(socket, { body: message({ tools: [custom, { ...custom, name: "Edit", type: "custom" }] }) })).status, 200);
  const before = up.seen.length;
  const refused = [
    message({ tools: [custom, { type: "web_search_20250305", name: "web_search" }] }),
    message({ tools: [{ type: "web_fetch_20250910", name: "web_fetch" }] }),
    message({ mcp_servers: [{ type: "url", url: "https://example.com/mcp", name: "x" }] }),
  ];
  for (const body of refused) assertRefused(await call(socket, { body }), 403, "permission_error");
  assert.equal(up.seen.length, before);
});

test("a tools field that is not a list, or a tools entry that is not an object, is refused", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up);
  const server = { type: "web_fetch_20250910", name: "web_fetch" };
  for (const tools of [server, { 0: server, length: 1 }, "web_fetch", null, ["web_fetch"], [[server]]]) {
    assertRefused(await call(socket, { body: message({ tools }) }), 403, "permission_error");
    assertRefused(await call(socket, { url: "/v1/messages/count_tokens", body: countBody({ tools }) }), 403, "permission_error");
  }
  assert.equal(up.seen.length + up.counts.length, 0);
});

test("content allowlist: block types outside the list and any source other than base64, text or content are refused at any depth", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up);
  const base64 = { type: "image", source: { type: "base64", media_type: "image/png", data: "iVBORw0KGgo=" } };
  const nested = { type: "tool_result", tool_use_id: "toolu_1", content: [{ type: "text", text: "see" }, base64] };
  // The proxy does not walk tool_use input, so a `type` key there is not checked.
  const toolUse = { type: "tool_use", id: "toolu_1", name: "Write", input: { type: "url", source: { type: "url" } } };
  const textDoc = { type: "document", source: { type: "text", media_type: "text/plain", data: "d" } };
  const allowed = message({ messages: [{ role: "assistant", content: [toolUse] }, { role: "user", content: [nested, textDoc] }], system: [{ type: "text", text: "s" }] });
  assert.equal((await call(socket, { body: allowed })).status, 200);
  const before = up.seen.length;
  const url = (kind) => ({ type: kind, source: { type: "url", url: `https://example.com/${kind}` } });
  const user = (content) => message({ messages: [{ role: "user", content }] });
  const refused = [
    user([{ ...nested, content: [url("image")] }]),
    user([url("document")]),
    message({ system: [{ type: "text", text: "x" }, url("document")] }),
    user([{ type: "document", source: { type: "file", file_id: "file_1" } }]),
    user([{ type: "document", source: { type: "content", content: [url("image")] } }]),
    message({ messages: [{ role: "assistant", content: [{ type: "server_tool_use", id: "srvtoolu_1", name: "web_search", input: {} }] }] }),
    user([{ type: "web_fetch_tool_result", tool_use_id: "srvtoolu_1", content: {} }]),
    user([{ type: "search_result", source: "s", title: "t", content: [] }]),
  ];
  for (const body of refused) assertRefused(await call(socket, { body }), 403, "permission_error");
  assert.equal(up.seen.length, before);
});

test("usage is summed without double counting message_start and the cumulative message_delta", async () => {
  // Token counts from the streaming doc's own example streams; message_delta
  // usage is cumulative.
  // Pointer: https://platform.claude.com/docs/en/build-with-claude/streaming#event-types
  // As of: 2026-11-06. Recheck trigger: that section changes what message_delta usage holds.
  const streams = [
    [sse("message_start", { message: { usage: { input_tokens: 25, output_tokens: 1 } } }), sse("ping", {}), sse("message_delta", { usage: { output_tokens: 15 } }), sse("message_stop", {})],
    [sse("message_start", { message: { usage: { input_tokens: 2679, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 3 } } }),
      sse("message_delta", { usage: { input_tokens: 10682, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 510 } }), sse("message_stop", {})],
  ];
  let n = 0;
  const up = await stubUpstream(async (_req, _body, res) => {
    const joined = streams[n++].join("");
    res.writeHead(200, { "content-type": "text/event-stream" });
    // Split one event across two writes so the parser must join chunks.
    res.write(joined.slice(0, 40));
    await tick();
    res.end(joined.slice(40));
  });
  const { socket, budget } = await startProxy(up);
  await call(socket, { body: message({ stream: true }) });
  assert.equal(budget.committed, 40); // 25 input + 15 output; not 41
  await call(socket, { body: message({ stream: true }) });
  assert.equal(budget.committed, 11232); // 40 + 10682 input + 510 output
  assert.equal(budget.reserved, 0);
});

test("non-streaming usage is read from the response body", async () => {
  const up = await stubUpstream(okJson({ input_tokens: 7, cache_read_input_tokens: 5, output_tokens: 3 }));
  const { socket, budget } = await startProxy(up);
  await call(socket, { body: message() });
  assert.equal(budget.committed, 15);
});

test("a streaming 200 that ends with no message_delta commits the reservation", async () => {
  const up = await stubUpstream((_req, _body, res) => {
    res.writeHead(200, { "content-type": "text/event-stream" });
    res.end(sse("message_start", { message: { usage: { input_tokens: 5, output_tokens: 1 } } }));
  }, { countTokens: 50 });
  const { socket, budget } = await startProxy(up);
  await call(socket, { body: message({ max_tokens: 100, stream: true }) });
  assert.equal(budget.committed, 150); // reservation 50 + 100, above the 6 seen
});

test("the reservation is the upstream count_tokens preflight of the checked body plus max_tokens", async () => {
  let releaseHold;
  const hold = new Promise((r) => (releaseHold = r));
  const up = await stubUpstream(async (_req, body, res) => {
    await hold;
    okJson()(_req, body, res);
  }, { countTokens: 250 });
  const { socket, budget } = await startProxy(up);
  const body = message({ max_tokens: 100, stream: true, metadata: { user_id: "u" }, context_management: {}, system: "s", thinking: { type: "adaptive" }, tools: [] });
  const pending = call(socket, { url: "/v1/messages?beta=true", body, headers: { "anthropic-beta": MAIN_BETAS, "x-api-key": "dummy" } });
  await until(() => up.seen.length === 1);
  assert.equal(budget.reserved, 350);
  const pre = up.counts[0];
  assert.equal(pre.url, "/v1/messages/count_tokens?beta=true");
  assert.equal(pre.headers["x-api-key"], KEY);
  assert.equal(pre.headers["anthropic-beta"], MAIN_BETAS);
  assert.deepEqual(JSON.parse(pre.body), { messages: [{ role: "user", content: "hi" }], model: "model-main", system: "s", thinking: { type: "adaptive" }, tools: [] });
  releaseHold();
  await pending;
});

test("a 529 preflight is relayed with its retry headers and body, takes no reservation and frees its slot", async () => {
  const overloaded = '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}';
  const up = await stubUpstream(okJson(), {
    countTokens: (res) => res.writeHead(529, { "content-type": "application/json", "retry-after": "3", "x-should-retry": "true" }).end(overloaded),
  });
  const { socket, budget } = await startProxy(up, { maxInFlight: 1 });
  for (let i = 0; i < 2; i++) {
    // The second pass would get the in-flight 403 if the first kept its slot.
    const res = await call(socket, { body: message() });
    assert.equal(res.status, 529);
    assert.equal(res.body, overloaded);
    assert.equal(res.headers["retry-after"], "3");
    assert.equal(res.headers["x-should-retry"], "true");
  }
  assert.equal(up.seen.length, 0);
  assert.equal(budget.reserved, 0);
  assert.equal(budget.committed, 0);
});

test("a 400 preflight is refused with a status that is not retried", async () => {
  const up = await stubUpstream(okJson(), { countTokens: (res) => res.writeHead(400, { "content-type": "application/json" }).end('{"type":"error","error":{"type":"invalid_request_error","message":"bad"}}') });
  const { socket, budget } = await startProxy(up);
  assertRefused(await call(socket, { body: message() }), 403, "permission_error");
  assert.equal(up.seen.length, 0);
  assert.equal(budget.reserved, 0);
});

test("a 429 preflight is relayed with its retry headers and body, takes no reservation and frees its slot", async () => {
  const limited = '{"type":"error","error":{"type":"rate_limit_error","message":"Number of requests has exceeded your rate limit"}}';
  const up = await stubUpstream(okJson(), {
    countTokens: (res) => res.writeHead(429, { "content-type": "application/json", "retry-after": "7", "anthropic-ratelimit-requests-remaining": "0" }).end(limited),
  });
  const { socket, budget } = await startProxy(up, { maxInFlight: 1 });
  for (let i = 0; i < 2; i++) {
    const res = await call(socket, { body: message() });
    assert.equal(res.status, 429);
    assert.equal(res.body, limited);
    assert.equal(res.headers["retry-after"], "7");
    assert.equal(res.headers["anthropic-ratelimit-requests-remaining"], "0");
  }
  assert.equal(up.seen.length, 0);
  assert.equal(budget.reserved, 0);
  assert.equal(budget.committed, 0);
});

test("a preflight whose connection drops is answered 502 with x-should-retry true, takes no reservation and frees its slot", async () => {
  const up = await stubUpstream(okJson(), { countTokens: (res) => res.socket.destroy() });
  const { socket, budget } = await startProxy(up, { maxInFlight: 1 });
  for (let i = 0; i < 2; i++) {
    const res = await call(socket, { body: message() });
    assert.equal(res.status, 502);
    assert.equal(res.headers["x-should-retry"], "true");
    assert.equal(JSON.parse(res.body).error.type, "api_error");
  }
  assert.equal(up.counts.length, 2);
  assert.equal(up.seen.length, 0);
  assert.equal(budget.reserved, 0);
  assert.equal(budget.committed, 0);
});

test("a main request whose upstream drops after reading the body is a retryable 502 that commits its reservation and frees its slot", async () => {
  let n = 0;
  const up = await stubUpstream((req, body, res) => {
    if (n++ === 0) return res.socket.destroy();
    okJson({ input_tokens: 1, output_tokens: 1 })(req, body, res);
  }, { countTokens: 50 });
  const { socket, budget } = await startProxy(up, { maxInFlight: 1 });
  const res = await call(socket, { body: message({ max_tokens: 100 }) });
  assert.equal(res.status, 502);
  assert.equal(res.headers["x-should-retry"], "true");
  assert.equal(JSON.parse(res.body).error.type, "api_error");
  assert.equal(budget.reserved, 0);
  assert.equal(budget.committed, 150); // 50 counted + 100 max_tokens
  assert.equal((await call(socket, { body: message({ max_tokens: 100 }) })).status, 200);
  assert.equal(budget.committed, 152); // + 1 input + 1 output
});

test("a non-streaming request whose upstream takes the body and then stalls times out as a retryable 502 and commits its reservation", { timeout: 10_000 }, async () => {
  const up = await stubUpstream(() => {}, { countTokens: 50 });
  const { socket, budget } = await startProxy(up, { tokenCap: 1000, maxTokensCeiling: 600, maxInFlight: 1, upstreamTimeoutMs: 150 });
  const body = message({ max_tokens: 600 });
  const res = await call(socket, { body });
  assert.equal(res.status, 502);
  assert.equal(res.headers["x-should-retry"], "true");
  assert.equal(JSON.parse(res.body).error.type, "api_error");
  await up.seen[0].closed; // the proxy aborted the stalled upstream request
  assert.equal(budget.reserved, 0);
  assert.equal(budget.committed, 650); // 50 counted + 600 max_tokens
  // Another 650 fits under 1000 only if the first had been released; the
  // 429 (not the in-flight 403) also shows the slot was freed.
  assertRefused(await call(socket, { body }), 429, "rate_limit_error");
  assert.equal(up.seen.length, 1);
});

test("a connect failure before the body is written is a retryable 502 that releases its reservation", { timeout: 10_000 }, async () => {
  // The preflight answers and closes its connection, then the upstream stops
  // listening, so the main request's connect is refused.
  const up = await stubUpstream(okJson(), {
    countTokens: (res) => {
      res.writeHead(200, { "content-type": "application/json", connection: "close" }).end(JSON.stringify({ input_tokens: 50 }));
      up.server.close();
    },
  });
  const { socket, budget } = await startProxy(up, { tokenCap: 1000, maxTokensCeiling: 600, maxInFlight: 1 });
  const res = await call(socket, { body: message({ max_tokens: 600 }) });
  assert.equal(res.status, 502);
  assert.equal(res.headers["x-should-retry"], "true");
  assert.equal(up.counts.length, 1);
  assert.equal(up.seen.length, 0);
  assert.equal(budget.reserved, 0);
  assert.equal(budget.committed, 0);
});

test("a count_tokens preflight that never answers times out as a retryable 502 and frees its slot", { timeout: 10_000 }, async () => {
  const up = await stubUpstream(okJson(), { countTokens: () => {} });
  const { socket, budget } = await startProxy(up, { maxInFlight: 1, upstreamTimeoutMs: 150 });
  // The second pass would get the in-flight 403 if the first kept its slot.
  for (let i = 0; i < 2; i++) {
    const res = await call(socket, { body: message() });
    assert.equal(res.status, 502);
    assert.equal(res.headers["x-should-retry"], "true");
  }
  assert.equal(up.seen.length, 0);
  assert.equal(budget.reserved, 0);
});

test("an in-flight reservation stops concurrent requests from passing the cap together", async () => {
  let releaseA;
  const holdA = new Promise((r) => (releaseA = r));
  const up = await stubUpstream(async (_req, body, res) => {
    if (JSON.parse(body).metadata?.user_id === "A") await holdA;
    okJson({ input_tokens: 10, output_tokens: 10 })(_req, body, res);
  }, { countTokens: 100 });
  // Each request reserves 100 + 500 = 600; the cap of 1000 fits one, not two.
  const { socket, budget } = await startProxy(up, { tokenCap: 1000, maxTokensCeiling: 500 });
  const a = call(socket, { body: message({ max_tokens: 500, metadata: { user_id: "A" } }) });
  await until(() => up.seen.length === 1);
  assertRefused(await call(socket, { body: message({ max_tokens: 500, metadata: { user_id: "B" } }) }), 429, "rate_limit_error");
  assert.equal(up.seen.length, 1);
  releaseA();
  assert.equal((await a).status, 200);
  assert.equal(budget.committed, 20);
  assert.equal((await call(socket, { body: message({ max_tokens: 500, metadata: { user_id: "B" } }) })).status, 200);
});

test("maxInFlight caps concurrent forwarded requests, count_tokens included", async () => {
  let releaseA;
  const holdA = new Promise((r) => (releaseA = r));
  const up = await stubUpstream(async (_req, body, res) => {
    await holdA;
    okJson()(_req, body, res);
  });
  const { socket } = await startProxy(up, { maxInFlight: 1 });
  const a = call(socket, { body: message() });
  await until(() => up.seen.length === 1);
  assertRefused(await call(socket, { body: message() }), 403, "permission_error");
  assertRefused(await call(socket, { url: "/v1/messages/count_tokens", body: countBody() }), 403, "permission_error");
  releaseA();
  await a;
  assert.equal((await call(socket, { url: "/v1/messages/count_tokens", body: countBody() })).status, 200);
});

test("client count_tokens is limited per job and refused once the cap is spent", async () => {
  const up = await stubUpstream(okJson({ input_tokens: 600, output_tokens: 400 }), { countTokens: 10 });
  const limited = await startProxy(up, { maxCountTokensRequests: 2 });
  for (let i = 0; i < 2; i++) assert.equal((await call(limited.socket, { url: "/v1/messages/count_tokens", body: countBody() })).status, 200);
  assertRefused(await call(limited.socket, { url: "/v1/messages/count_tokens", body: countBody() }), 403, "permission_error");

  const capped = await startProxy(up, { tokenCap: 1000 });
  assert.equal((await call(capped.socket, { url: "/v1/messages/count_tokens", body: countBody() })).status, 200);
  assert.equal((await call(capped.socket, { body: message() })).status, 200); // commits 1000
  assertRefused(await call(capped.socket, { url: "/v1/messages/count_tokens", body: countBody() }), 429, "rate_limit_error");
});

test("a client that disconnects mid-stream has its reservation committed, not released", async () => {
  const up = await stubUpstream((_req, _body, res) => {
    res.writeHead(200, { "content-type": "text/event-stream" });
    res.write(sse("message_start", { message: { usage: { input_tokens: 5, output_tokens: 1 } } }));
    // Then stall: no message_delta ever comes.
  }, { countTokens: 50 });
  const { socket, budget } = await startProxy(up, { tokenCap: 1000, maxTokensCeiling: 600 });
  const body = message({ max_tokens: 600, stream: true });
  const { req, res } = await openStream(socket, body);
  await new Promise((r) => res.once("data", r));
  req.on("error", () => {});
  req.destroy();
  await up.seen[0].closed; // the proxy aborted the upstream request
  await until(() => budget.reserved === 0);
  assert.equal(budget.committed, 650); // 50 counted + 600 max_tokens
  // A second request of the same size fits only if the first had been released.
  assertRefused(await call(socket, { body }), 429, "rate_limit_error");
});

test("an upstream that drops mid-stream drops the client and commits the reservation", { timeout: 10_000 }, async () => {
  const up = await stubUpstream((_req, _body, res) => {
    res.writeHead(200, { "content-type": "text/event-stream" });
    res.write(sse("message_start", { message: { usage: { input_tokens: 5, output_tokens: 1 } } }), () => setTimeout(() => res.socket.destroy(), 20));
  }, { countTokens: 50 });
  const { socket, budget } = await startProxy(up, { tokenCap: 1000, maxTokensCeiling: 600 });
  const { req, res } = await openStream(socket, message({ max_tokens: 600, stream: true }));
  req.on("error", () => {});
  const ended = await new Promise((resolve) => {
    res.on("data", () => {});
    res.on("error", () => resolve("dropped"));
    res.on("end", () => resolve("ended"));
    res.on("close", () => resolve("closed"));
  });
  assert.notEqual(ended, "ended"); // no clean end: the client must see a drop
  await until(() => budget.reserved === 0);
  assert.equal(budget.committed, 650);
});

test("an upstream that stalls mid-stream is aborted after the idle timeout: the client is dropped and the reservation committed", { timeout: 10_000 }, async () => {
  const up = await stubUpstream((_req, _body, res) => {
    res.writeHead(200, { "content-type": "text/event-stream" });
    res.write(sse("message_start", { message: { usage: { input_tokens: 5, output_tokens: 1 } } }));
    // Then nothing: no ping, no message_delta.
  }, { countTokens: 50 });
  const { socket, budget } = await startProxy(up, { tokenCap: 1000, maxTokensCeiling: 600, upstreamTimeoutMs: 150 });
  const { req, res } = await openStream(socket, message({ max_tokens: 600, stream: true }));
  req.on("error", () => {});
  const ended = await new Promise((resolve) => {
    res.on("data", () => {});
    res.on("error", () => resolve("dropped"));
    res.on("end", () => resolve("ended"));
    res.on("close", () => resolve("closed"));
  });
  assert.notEqual(ended, "ended"); // no clean end: the client must see a drop
  await up.seen[0].closed;
  await until(() => budget.reserved === 0);
  assert.equal(budget.committed, 650); // 50 counted + 600 max_tokens
});

test("an oversized body gets a 413 that is not retried, and never reaches upstream", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up, { maxBodyBytes: 2000 });
  const res = await call(socket, { body: message({ messages: [{ role: "user", content: "x".repeat(2000) }] }) });
  assertRefused(res, 413, "request_too_large");
  assert.equal(up.seen.length + up.counts.length, 0);
});

test("an oversized body still uploading in chunks is drained to its end, with no socket error", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up, { maxBodyBytes: 2000 });
  let res;
  let writeError = null;
  let written = 0;
  await new Promise((resolve) => {
    const req = http.request({ socketPath: socket, method: "POST", path: "/v1/messages", headers: { "content-type": "application/json" } }, (r) => {
      const chunks = [];
      r.on("data", (c) => chunks.push(c));
      r.on("end", () => { res = { status: r.statusCode, headers: r.headers, body: Buffer.concat(chunks).toString("utf8") }; });
    });
    req.on("error", (e) => { writeError = e; resolve(); });
    req.on("close", resolve);
    // 40 chunks of 64 KiB, 5 ms apart: more than a socket buffer holds, so the client is still
    // writing when the limit trips on the first chunk. Over TCP (the socat bridge) a socket closed
    // with unread data answers the remaining writes with a reset.
    const next = (err) => {
      if (err) return;
      if (written === 40) return req.end();
      written++;
      req.write("x".repeat(65536), (e) => setTimeout(() => next(e), 5));
    };
    next();
  });
  assert.equal(writeError, null);
  assert.equal(written, 40);
  assertRefused(res, 413, "request_too_large");
  assert.equal(up.seen.length + up.counts.length, 0);
});

test("a body that breaks re-serialization gets a 400 and the proxy keeps serving", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up, { maxBodyBytes: 1_000_000 });
  // tool_use input is not walked, so 50000 nested arrays pass the checks and then overflow the
  // stack when the proxy re-serializes the body. Written by hand: JSON.stringify would overflow here.
  const deep = "[".repeat(50000) + "]".repeat(50000);
  const raw = `{"model":"model-main","max_tokens":100,"messages":[{"role":"user","content":"hi"},{"role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"Write","input":{"a":${deep}}}]}]}`;
  const bad = await call(socket, { body: Buffer.from(raw) });
  assertRefused(bad, 400, "invalid_request_error");
  const next = await call(socket, { body: message() });
  assert.equal(next.status, 200);
  assert.equal(up.seen.length, 1);
});

test("past the cap the refusal is a 429 spend limit with x-should-retry false", async () => {
  const up = await stubUpstream(okJson({ input_tokens: 450, output_tokens: 450 }), { countTokens: 10 });
  // The first request commits 900; the second reserves 10 + 100 more.
  const { socket } = await startProxy(up, { tokenCap: 1000, maxTokensCeiling: 100 });
  assert.equal((await call(socket, { body: message() })).status, 200);
  const res = await call(socket, { body: message() });
  assertRefused(res, 429, "rate_limit_error");
  // The documented spend-limit wording.
  // Pointer: https://code.claude.com/docs/en/errors#spend-limit-reached
  // As of: 2026-11-06. Recheck trigger: that section changes the message wording.
  assert.match(JSON.parse(res.body).error.message, /^spend limit reached/);
  assert.equal(up.seen.length, 1);
});

test("a request whose max_tokens alone passes the spent cap is refused before any count_tokens preflight", async () => {
  const up = await stubUpstream(okJson({ input_tokens: 475, output_tokens: 475 }), { countTokens: 10 });
  const { socket, budget } = await startProxy(up, { tokenCap: 1000, maxTokensCeiling: 100 });
  // Reserves 10 + 100, then commits 475 + 475 = 950.
  assert.equal((await call(socket, { body: message() })).status, 200);
  assert.equal(budget.committed, 950);
  assert.equal(up.counts.length, 1);
  // 950 + 100 = 1050 > 1000: refused with no upstream call at all.
  assertRefused(await call(socket, { body: message({ max_tokens: 100 }) }), 429, "rate_limit_error");
  assert.equal(up.counts.length, 1);
  // 950 + 50 = 1000 is not past the cap, so the preflight runs; 950 + 10 + 50 = 1010 then is.
  assertRefused(await call(socket, { body: message({ max_tokens: 50 }) }), 429, "rate_limit_error");
  assert.equal(up.counts.length, 2);
  assert.equal(up.seen.length, 1);
});

test("preflights are limited per job, so requests refused at reserve cannot repeat the count_tokens call without end", async () => {
  // Each preflight counts 900 input tokens; 900 + max_tokens 200 = 1100 is past the cap of 1000, so every reserve fails.
  const up = await stubUpstream(okJson(), { countTokens: 900 });
  const { socket } = await startProxy(up, { tokenCap: 1000, maxTokensCeiling: 200, maxPreflightRequests: 3 });
  for (let i = 1; i <= 3; i++) {
    assertRefused(await call(socket, { body: message({ max_tokens: 200 }) }), 429, "rate_limit_error");
    assert.equal(up.counts.length, i);
  }
  // The fourth is refused before its preflight: three upstream calls in all, none to /v1/messages.
  const fourth = await call(socket, { body: message({ max_tokens: 200 }) });
  assertRefused(fourth, 429, "rate_limit_error");
  assert.match(JSON.parse(fourth.body).error.message, /^spend limit reached \(per-job request limit\)$/);
  assert.equal(up.counts.length, 3);
  assert.equal(up.seen.length, 0);
});

test("a request that passes counts toward the preflight limit too", async () => {
  const up = await stubUpstream(okJson(), { countTokens: 10 });
  const { socket } = await startProxy(up, { maxPreflightRequests: 2 });
  assert.equal((await call(socket, { body: message() })).status, 200);
  assert.equal((await call(socket, { body: message() })).status, 200);
  assertRefused(await call(socket, { body: message() }), 429, "rate_limit_error");
  assert.equal(up.counts.length, 2);
  assert.equal(up.seen.length, 2);
});

// Runs the script as the workflow will.
function spawnProxy(args, stdin) {
  const child = spawn(process.execPath, [SCRIPT, ...args], { stdio: ["pipe", "pipe", "pipe"], env: { PATH: process.env.PATH } });
  const out = { stdout: "", stderr: "" };
  child.stdout.on("data", (c) => (out.stdout += c));
  child.stderr.on("data", (c) => (out.stderr += c));
  child.stdin.end(stdin);
  const exited = new Promise((r) => child.on("exit", (code) => r(code)));
  return { child, out, exited };
}

test("the script reads the key from stdin, never argv or env, and logs neither the key nor a request body", async () => {
  const sentinel = "BODY-SENTINEL-7f3a";
  const up = await stubUpstream(okJson());
  const dir = tempDir("kp-");
  const config = path.join(dir, "config.json");
  writeFileSync(config, JSON.stringify({ ...BASE_CONFIG, socketMode: "660" }));
  const socket = path.join(dir, "p.sock");
  const p = spawnProxy(["--socket", socket, "--config", config, "--upstream", up.url], `${KEY}\n`);
  try {
    await until(() => p.out.stderr.includes('"listening"'));
    assert.equal(statSync(socket).mode & 0o777, 0o660);
    const res = await call(socket, { body: message({ messages: [{ role: "user", content: sentinel }] }), headers: { "x-api-key": "dummy" } });
    assert.equal(res.status, 200);
    assert.equal(up.seen[0].headers["x-api-key"], KEY);
    await until(() => p.out.stderr.includes('"status":200'));
  } finally {
    p.child.kill("SIGTERM");
    await p.exited;
  }
  for (const stream of [p.out.stdout, p.out.stderr]) {
    assert.ok(!stream.includes(KEY), "key logged");
    assert.ok(!stream.includes(sentinel), "body logged");
  }
  assert.ok(!p.child.spawnargs.some((a) => a.includes(KEY)));
});

test("the script exits non-zero on a missing key or a bad config", async () => {
  const dir = tempDir("kp-");
  const good = path.join(dir, "good.json");
  writeFileSync(good, JSON.stringify(BASE_CONFIG));
  const bad = path.join(dir, "bad.json");
  writeFileSync(bad, JSON.stringify({ ...BASE_CONFIG, tokenCap: 0, models: [] }));
  const noBodyKeys = path.join(dir, "nokeys.json");
  writeFileSync(noBodyKeys, JSON.stringify({ ...BASE_CONFIG, bodyKeys: undefined }));
  assert.equal(await spawnProxy(["--socket", path.join(dir, "a.sock"), "--config", good], "").exited, 2);
  assert.equal(await spawnProxy(["--socket", path.join(dir, "b.sock"), "--config", bad], KEY).exited, 2);
  assert.equal(await spawnProxy(["--socket", path.join(dir, "c.sock"), "--config", noBodyKeys], KEY).exited, 2);
  const noTimeout = path.join(dir, "notimeout.json");
  writeFileSync(noTimeout, JSON.stringify({ ...BASE_CONFIG, upstreamTimeoutMs: undefined }));
  assert.equal(await spawnProxy(["--socket", path.join(dir, "d.sock"), "--config", noTimeout], KEY).exited, 2);
  const noDriverCap = path.join(dir, "nodrivercap.json");
  writeFileSync(noDriverCap, JSON.stringify({ ...BASE_CONFIG, driverTokenCap: undefined }));
  assert.equal(await spawnProxy(["--socket", path.join(dir, "e.sock"), "--config", noDriverCap], KEY).exited, 2);
  assert.equal(await spawnProxy(["--config", good], KEY).exited, 2);
});

// The loopback listener the capture's driver legs use: a client key in place
// of the real one, required on every request.
const CLIENT_KEY = `ccd-outer-${"c".repeat(32)}`;

test("a client key admits only requests carrying it: a wrong, missing or real key is refused 401 before anything goes upstream", async () => {
  const up = await stubUpstream(okJson());
  const { socket, logs } = await startProxy(up, {}, { clientKey: CLIENT_KEY });
  const refused = [{}, { "x-api-key": "ccd-outer-wrong" }, { "x-api-key": KEY }, { "x-api-key": `${CLIENT_KEY}x` }, { authorization: `Bearer ${CLIENT_KEY}` }];
  for (const headers of refused) assertRefused(await call(socket, { headers, body: message() }), 401, "authentication_error");
  assertRefused(await call(socket, { url: "/v1/messages/count_tokens", body: countBody() }), 401, "authentication_error");
  assert.equal(up.seen.length + up.counts.length, 0);
  assert.equal(logs.filter((l) => l.status === 401).length, refused.length + 1);

  const ok = await call(socket, { headers: { "x-api-key": CLIENT_KEY }, body: message() });
  assert.equal(ok.status, 200);
  assert.equal(up.seen.length, 1);
  assert.equal(up.seen[0].headers["x-api-key"], KEY);
  assert.ok(!JSON.stringify(logs).includes(CLIENT_KEY), "client key logged");
});

test("a client key equal to the held key, or empty, is refused at construction", () => {
  const config = loadConfig(BASE_CONFIG, "http://127.0.0.1:1");
  assert.throws(() => createProxy({ key: KEY, config, clientKey: KEY }), /clientKey/);
  assert.throws(() => createProxy({ key: KEY, config, clientKey: "" }), /clientKey/);
});

test("relayPreflightErrors relays a 400 or 401 preflight answer as sent, where the default proxy refuses it 403", async () => {
  const credit = '{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API."}}';
  const auth = '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}';
  for (const [status, body] of [[400, credit], [401, auth]]) {
    const up = await stubUpstream(okJson(), { countTokens: (res) => res.writeHead(status, { "content-type": "application/json", "request-id": "req_1" }).end(body) });
    const relaying = await startProxy(up, {}, { relayPreflightErrors: true });
    const relayed = await call(relaying.socket, { body: message() });
    assert.equal(relayed.status, status);
    assert.equal(relayed.body, body);
    assert.equal(relayed.headers["request-id"], "req_1");
    assert.equal(relaying.budget.reserved, 0);

    const plain = await startProxy(up);
    assertRefused(await call(plain.socket, { body: message() }), 403, "permission_error");
    assert.equal(up.seen.length, 0);
  }
});

// A free loopback port: bound once, then released for the script to take.
async function freePort() {
  const s = http.createServer();
  await new Promise((r) => s.listen(0, "127.0.0.1", r));
  const { port } = s.address();
  await new Promise((r) => s.close(r));
  return port;
}

function callPort(port, { headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: "127.0.0.1", port, method: "POST", path: "/v1/messages", headers: { "content-type": "application/json", ...headers } }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString("utf8") }));
    });
    req.on("error", reject);
    req.end(JSON.stringify(body));
  });
}

test("with --listen the script serves a loopback port that needs the client key from stdin, and the socket still needs none", { timeout: 10_000 }, async () => {
  const up = await stubUpstream(okJson());
  const dir = tempDir("kp-");
  const config = path.join(dir, "config.json");
  writeFileSync(config, JSON.stringify(BASE_CONFIG));
  const socket = path.join(dir, "p.sock");
  const port = await freePort();
  const p = spawnProxy(["--socket", socket, "--config", config, "--upstream", up.url, "--listen", String(port)], `${KEY}\n${CLIENT_KEY}\n`);
  try {
    await until(() => p.out.stderr.includes(`"listening":"127.0.0.1:${port}"`));
    assert.equal((await callPort(port, { body: message() })).status, 401);
    assert.equal((await callPort(port, { headers: { "x-api-key": KEY }, body: message() })).status, 401);
    assert.equal(up.seen.length, 0);
    assert.equal((await callPort(port, { headers: { "x-api-key": CLIENT_KEY }, body: message() })).status, 200);
    assert.equal((await call(socket, { body: message() })).status, 200);
    assert.equal(up.seen.length, 2);
    assert.ok(up.seen.every((s) => s.headers["x-api-key"] === KEY));
    await until(() => p.out.stderr.split("\n").filter((l) => l.includes('"status":200')).length === 2);
  } finally {
    p.child.kill("SIGTERM");
    await p.exited;
  }
  const lines = p.out.stderr.split("\n").filter(Boolean).map((l) => JSON.parse(l)).filter((e) => e.status !== undefined);
  assert.deepEqual(lines.map((e) => `${e.listener} ${e.status}`), ["loopback 401", "loopback 401", "loopback 200", "socket 200"]);
  for (const k of [KEY, CLIENT_KEY]) assert.ok(!p.out.stderr.includes(k) && !p.out.stdout.includes(k), "a key logged");
  assert.ok(!p.child.spawnargs.some((a) => a.includes(CLIENT_KEY)));
});

test("with --listen the socket refuses at tokenCap and the loopback port at driverTokenCap, each with its own budget", { timeout: 10_000 }, async () => {
  const up = await stubUpstream(okJson({ input_tokens: 450, output_tokens: 450 }), { countTokens: 10 });
  const dir = tempDir("kp-");
  const config = path.join(dir, "config.json");
  writeFileSync(config, JSON.stringify({ ...BASE_CONFIG, tokenCap: 1000, driverTokenCap: 1900 }));
  const socket = path.join(dir, "p.sock");
  const port = await freePort();
  const p = spawnProxy(["--socket", socket, "--config", config, "--upstream", up.url, "--listen", String(port)], `${KEY}\n${CLIENT_KEY}\n`);
  const driver = () => callPort(port, { headers: { "x-api-key": CLIENT_KEY }, body: message() });
  const spendLimit = (res, where) => {
    assert.equal(res.status, 429, `${where} refused at its cap`);
    assert.match(JSON.parse(res.body).error.message, /^spend limit reached/);
  };
  try {
    await until(() => p.out.stderr.includes(`"listening":"127.0.0.1:${port}"`));
    // Each call reserves 10 + 100 and commits 900. Socket: 900 + 110 > 1000 on the second call.
    assert.equal((await call(socket, { body: message() })).status, 200, "socket first call within tokenCap");
    spendLimit(await call(socket, { body: message() }), "socket");
    // Loopback: 900 + 110 <= 1900 passes; 1800 + 110 > 1900 on the third call.
    assert.equal((await driver()).status, 200, "loopback first call within driverTokenCap");
    assert.equal((await driver()).status, 200, "loopback second call past tokenCap but within driverTokenCap");
    spendLimit(await driver(), "loopback");
    assert.equal(up.seen.length, 3);
  } finally {
    p.child.kill("SIGTERM");
    await p.exited;
  }
});

test("--listen without a second stdin line, or with the key repeated there, exits 2", { timeout: 10_000 }, async () => {
  const dir = tempDir("kp-");
  const config = path.join(dir, "config.json");
  writeFileSync(config, JSON.stringify(BASE_CONFIG));
  const port = String(await freePort());
  assert.equal(await spawnProxy(["--socket", path.join(dir, "a.sock"), "--config", config, "--listen", port], `${KEY}\n`).exited, 2);
  assert.equal(await spawnProxy(["--socket", path.join(dir, "b.sock"), "--config", config, "--listen", port], `${KEY}\n${KEY}\n`).exited, 2);
  assert.equal(await spawnProxy(["--socket", path.join(dir, "c.sock"), "--config", config, "--listen", "0"], `${KEY}\n${CLIENT_KEY}\n`).exited, 2);
});
