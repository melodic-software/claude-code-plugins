// key-proxy.mjs, the only path from pr-verify's driven Claude Code to the
// API: one test per PLAN Phase 2 bullet, each against a local stub upstream
// and a real unix socket, plus the stdin key and never-log guarantees.
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
const servers = [];
after(() => {
  for (const s of servers) {
    s.closeAllConnections?.();
    s.close();
  }
});

// A stub upstream: each request is handed to `handler(req, body, res)` and
// recorded with its exact path, headers and body bytes.
async function stubUpstream(handler) {
  const seen = [];
  const server = http.createServer((req, res) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const body = Buffer.concat(chunks);
      const entry = { method: req.method, url: req.url, headers: req.headers, body, closed: new Promise((r) => res.on("close", r)) };
      seen.push(entry);
      handler(req, body, res, entry);
    });
  });
  servers.push(server);
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  return { url: `http://127.0.0.1:${server.address().port}`, seen };
}

const okJson = (usage = { input_tokens: 1, output_tokens: 1 }) => (_req, _body, res) => {
  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify({ type: "message", content: [], usage }));
};

async function startProxy(upstream, overrides = {}) {
  const config = loadConfig({ tokenCap: 1_000_000, models: MODELS, maxTokensCeiling: 1000, maxBodyBytes: 100_000, bytesPerToken: 4, ...overrides }, upstream.url);
  const { server, budget } = createProxy({ key: KEY, config });
  servers.push(server);
  const socket = path.join(tempDir("kp-"), "p.sock");
  await new Promise((r) => server.listen(socket, r));
  return { socket, budget };
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
const sse = (type, data) => `event: ${type}\ndata: ${JSON.stringify({ type, ...data })}\n\n`;
const tick = () => new Promise((r) => setImmediate(r));
async function until(cond) {
  for (let i = 0; i < 500 && !cond(); i++) await new Promise((r) => setTimeout(r, 10));
  assert.ok(cond(), "condition not reached");
}

test("path allowlist: only POST /v1/messages and /v1/messages/count_tokens reach upstream; the query passes; everything else is 404", async () => {
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
  for (const r of refused) {
    const res = await call(socket, r);
    assert.equal(res.status, 404, `${r.method ?? "POST"} ${r.url}`);
  }
  assert.equal(up.seen.length, 0);

  assert.equal((await call(socket, { url: "/v1/messages?beta=true", body: message() })).status, 200);
  assert.equal((await call(socket, { url: "/v1/messages/count_tokens", body: { model: "model-main", messages: [] } })).status, 200);
  assert.deepEqual(up.seen.map((s) => `${s.method} ${s.url}`), ["POST /v1/messages?beta=true", "POST /v1/messages/count_tokens"]);
});

test("credential swap: the client's Authorization and x-api-key are stripped and x-api-key is the held key", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up);
  await call(socket, { body: message(), headers: { authorization: "Bearer client-token", "x-api-key": "dummy-client-key" } });
  assert.equal(up.seen[0].headers["x-api-key"], KEY);
  assert.equal(up.seen[0].headers.authorization, undefined);
});

test("anthropic-* headers and the request body reach upstream unchanged", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up);
  // Odd whitespace and key order: a re-serialized body would differ.
  const raw = Buffer.from('{ "messages":[{"role":"user","content":"hi"}],\n  "max_tokens" : 100, "model":"model-title", "metadata":{"z":1,"a":2} }');
  await call(socket, { body: raw, headers: { "anthropic-version": "2023-06-01", "anthropic-beta": "a-2026-01-01,b-2026-02-02" } });
  assert.ok(up.seen[0].body.equals(raw));
  assert.equal(up.seen[0].headers["anthropic-version"], "2023-06-01");
  assert.equal(up.seen[0].headers["anthropic-beta"], "a-2026-01-01,b-2026-02-02");
});

test("SSE streams are relayed unbuffered, ping events included", { timeout: 10_000 }, async () => {
  let release;
  const released = new Promise((r) => (release = r));
  const up = await stubUpstream(async (_req, _body, res) => {
    res.writeHead(200, { "content-type": "text/event-stream" });
    res.write(sse("message_start", { message: { usage: { input_tokens: 3, output_tokens: 1 } } }));
    res.write(sse("ping", {}));
    // The rest is sent only after the client has seen the ping: a proxy that
    // buffers never delivers it, and the test hangs to its timeout.
    await released;
    res.write(sse("message_delta", { delta: { stop_reason: "end_turn" }, usage: { output_tokens: 2 } }));
    res.end(sse("message_stop", {}));
  });
  const { socket } = await startProxy(up);
  const text = await new Promise((resolve, reject) => {
    const req = http.request({ socketPath: socket, method: "POST", path: "/v1/messages", headers: { "content-type": "application/json" } }, (res) => {
      assert.equal(res.headers["content-type"], "text/event-stream");
      let got = "";
      res.on("data", (c) => {
        got += c;
        if (got.includes("event: ping")) release();
      });
      res.on("end", () => resolve(got));
    });
    req.on("error", reject);
    req.end(JSON.stringify(message({ stream: true })));
  });
  assert.match(text, /event: message_start[\s\S]*event: ping[\s\S]*event: message_delta[\s\S]*event: message_stop/);
});

test("upstream error status, x-should-retry and body are forwarded unmodified", async () => {
  const errorBody = '{"type":"error","error":{"type":"invalid_request_error","message":"Unexpected value(s) `x-2026` for the `anthropic-beta` header"}}';
  const up = await stubUpstream((_req, _body, res) => {
    res.writeHead(400, { "content-type": "application/json", "x-should-retry": "true", "request-id": "req_1" });
    res.end(errorBody);
  });
  const { socket } = await startProxy(up);
  const res = await call(socket, { body: message() });
  assert.equal(res.status, 400);
  assert.equal(res.body, errorBody);
  assert.equal(res.headers["x-should-retry"], "true");
  assert.equal(res.headers["request-id"], "req_1");
});

test("a model allowlist of several models and a max_tokens ceiling", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up, { maxTokensCeiling: 1000 });
  assert.equal((await call(socket, { body: message({ model: "model-main" }) })).status, 200);
  assert.equal((await call(socket, { body: message({ model: "model-title" }) })).status, 200);
  assert.equal((await call(socket, { body: message({ max_tokens: 1000 }) })).status, 200);
  const before = up.seen.length;
  for (const body of [message({ model: "model-other" }), message({ max_tokens: 1001 }), message({ max_tokens: undefined })]) {
    const res = await call(socket, { body });
    assert.equal(res.status, 403);
    assert.equal(JSON.parse(res.body).error.type, "permission_error");
  }
  assert.equal(up.seen.length, before);
  // count_tokens takes no max_tokens, but its model is still checked.
  assert.equal((await call(socket, { url: "/v1/messages/count_tokens", body: { model: "model-title", messages: [] } })).status, 200);
  assert.equal((await call(socket, { url: "/v1/messages/count_tokens", body: { model: "model-other", messages: [] } })).status, 403);
});

test("requests carrying server-tool blocks are refused", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up);
  const custom = { name: "Read", description: "read", input_schema: { type: "object" } };
  assert.equal((await call(socket, { body: message({ tools: [custom, { ...custom, name: "Edit", type: "custom" }] }) })).status, 200);
  const before = up.seen.length;
  const refused = [
    message({ tools: [custom, { type: "web_search_20250305", name: "web_search" }] }),
    message({ tools: [{ type: "web_fetch_20250910", name: "web_fetch" }] }),
    message({ mcp_servers: [{ type: "url", url: "https://example.com/mcp", name: "x" }] }),
    message({ messages: [{ role: "assistant", content: [{ type: "server_tool_use", id: "srvtoolu_1", name: "web_search", input: {} }] }] }),
    message({ messages: [{ role: "user", content: [{ type: "web_fetch_tool_result", tool_use_id: "srvtoolu_1", content: {} }] }] }),
  ];
  for (const body of refused) assert.equal((await call(socket, { body })).status, 403);
  assert.equal(up.seen.length, before);
});

test("content blocks with a url source are refused at any depth; a base64 source passes", async () => {
  const up = await stubUpstream(okJson());
  const { socket } = await startProxy(up);
  const base64 = { type: "image", source: { type: "base64", media_type: "image/png", data: "iVBORw0KGgo=" } };
  const nested = { type: "tool_result", tool_use_id: "toolu_1", content: [{ type: "text", text: "see" }, base64] };
  assert.equal((await call(socket, { body: message({ messages: [{ role: "user", content: [nested] }] }) })).status, 200);
  const before = up.seen.length;
  const refused = [
    message({ messages: [{ role: "user", content: [{ ...nested, content: [{ type: "image", source: { type: "url", url: "https://example.com/a.png" } }] }] }] }),
    message({ messages: [{ role: "user", content: [{ type: "document", source: { type: "url", url: "https://example.com/a.pdf" } }] }] }),
    message({ system: [{ type: "text", text: "x" }, { type: "document", source: { type: "url", url: "https://example.com/s.pdf" } }] }),
  ];
  for (const body of refused) {
    const res = await call(socket, { body });
    assert.equal(res.status, 403);
    assert.equal(res.headers["x-should-retry"], "false");
    assert.equal(JSON.parse(res.body).error.type, "permission_error");
  }
  assert.equal(up.seen.length, before);
});

test("usage is summed without double counting message_start and the cumulative message_delta", async () => {
  // Token counts from the streaming doc's own examples
  // (https://platform.claude.com/docs/en/build-with-claude/streaming).
  const streams = [
    [sse("message_start", { message: { usage: { input_tokens: 25, output_tokens: 1 } } }), sse("ping", {}), sse("message_delta", { usage: { output_tokens: 15 } }), sse("message_stop", {})],
    [sse("message_start", { message: { usage: { input_tokens: 2679, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 3 } } }),
      sse("message_delta", { usage: { input_tokens: 10682, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 510 } }), sse("message_stop", {})],
  ];
  let n = 0;
  const up = await stubUpstream(async (_req, _body, res) => {
    const events = streams[n++];
    res.writeHead(200, { "content-type": "text/event-stream" });
    // Split one event across two writes so the parser must join chunks.
    const joined = events.join("");
    res.write(joined.slice(0, 40));
    await tick();
    res.end(joined.slice(40));
  });
  const { socket, budget } = await startProxy(up);
  await call(socket, { body: message({ stream: true }) });
  assert.equal(budget.committed, 40); // 25 input + 15 output; not 41
  await call(socket, { body: message({ stream: true }) });
  assert.equal(budget.committed, 40 + 11192); // 10682 input + 510 output
  assert.equal(budget.reserved, 0);
});

test("non-streaming usage is read from the response body", async () => {
  const up = await stubUpstream(okJson({ input_tokens: 7, cache_read_input_tokens: 5, output_tokens: 3 }));
  const { socket, budget } = await startProxy(up);
  await call(socket, { body: message() });
  assert.equal(budget.committed, 15);
});

test("an in-flight reservation stops concurrent requests from passing the cap together", async () => {
  let releaseA;
  const holdA = new Promise((r) => (releaseA = r));
  const up = await stubUpstream(async (_req, body, res) => {
    if (JSON.parse(body).metadata?.user_id === "A") await holdA;
    okJson({ input_tokens: 10, output_tokens: 10 })(_req, body, res);
  });
  // Each request reserves ceil(bytes / 4) + 500; the cap fits one, not two.
  const { socket, budget } = await startProxy(up, { tokenCap: 1000, maxTokensCeiling: 500 });
  const a = call(socket, { body: message({ max_tokens: 500, metadata: { user_id: "A" } }) });
  await until(() => up.seen.length === 1);
  const b = await call(socket, { body: message({ max_tokens: 500, metadata: { user_id: "B" } }) });
  assert.equal(b.status, 429);
  assert.equal(up.seen.length, 1);
  releaseA();
  assert.equal((await a).status, 200);
  assert.equal(budget.committed, 20);
  // With A settled at its real usage, the same request now fits.
  assert.equal((await call(socket, { body: message({ max_tokens: 500, metadata: { user_id: "B" } }) })).status, 200);
});

test("a client that disconnects mid-stream has its reservation committed, not released", async () => {
  const up = await stubUpstream((_req, _body, res) => {
    res.writeHead(200, { "content-type": "text/event-stream" });
    res.write(sse("message_start", { message: { usage: { input_tokens: 5, output_tokens: 1 } } }));
    // Then stall: no message_delta ever comes.
  });
  const { socket, budget } = await startProxy(up, { tokenCap: 1000, maxTokensCeiling: 600 });
  const body = JSON.stringify(message({ max_tokens: 600, stream: true }));
  const reservation = Math.ceil(Buffer.byteLength(body) / 4) + 600;
  await new Promise((resolve, reject) => {
    const req = http.request({ socketPath: socket, method: "POST", path: "/v1/messages", headers: { "content-type": "application/json" } }, (res) => {
      res.once("data", () => {
        req.destroy();
        resolve();
      });
    });
    req.on("error", () => {});
    req.on("close", resolve);
    req.end(body);
    setTimeout(() => reject(new Error("no first event")), 5000).unref();
  });
  await up.seen[0].closed; // the proxy aborted the upstream request
  await until(() => budget.reserved === 0);
  assert.equal(budget.committed, reservation);
  // A second request of the same size fits only if the first had been released.
  assert.equal((await call(socket, { body })).status, 429);
});

test("an upstream that drops mid-stream drops the client and commits the reservation", { timeout: 10_000 }, async () => {
  const up = await stubUpstream((_req, _body, res) => {
    res.writeHead(200, { "content-type": "text/event-stream" });
    res.write(sse("message_start", { message: { usage: { input_tokens: 5, output_tokens: 1 } } }), () => setTimeout(() => res.socket.destroy(), 20));
  });
  const { socket, budget } = await startProxy(up, { tokenCap: 1000, maxTokensCeiling: 600 });
  const body = JSON.stringify(message({ max_tokens: 600, stream: true }));
  const ended = await new Promise((resolve) => {
    const req = http.request({ socketPath: socket, method: "POST", path: "/v1/messages", headers: { "content-type": "application/json" } }, (res) => {
      res.on("data", () => {});
      res.on("error", () => resolve("dropped"));
      res.on("end", () => resolve("ended"));
      res.on("close", () => resolve("closed"));
    });
    req.on("error", () => resolve("dropped"));
    req.end(body);
  });
  assert.notEqual(ended, "ended"); // no clean end: Claude Code must see a drop
  await until(() => budget.reserved === 0);
  assert.equal(budget.committed, Math.ceil(Buffer.byteLength(body) / 4) + 600);
});

test("a request body size limit, and the input estimate is taken from body size", async () => {
  let releaseHold;
  const hold = new Promise((r) => (releaseHold = r));
  const up = await stubUpstream(async (_req, body, res) => {
    await hold;
    okJson()(_req, body, res);
  });
  const { socket, budget } = await startProxy(up, { maxBodyBytes: 2000, bytesPerToken: 4 });
  const big = message({ messages: [{ role: "user", content: "x".repeat(2000) }] });
  const res = await call(socket, { body: big });
  assert.equal(res.status, 413);
  assert.equal(up.seen.length, 0);

  // A 1000-byte body at 4 bytes per token reserves 250 plus max_tokens 100.
  const filler = "y".repeat(1000 - Buffer.byteLength(JSON.stringify(message({ messages: [{ role: "user", content: "" }] }))));
  const body = JSON.stringify(message({ messages: [{ role: "user", content: filler }] }));
  assert.equal(Buffer.byteLength(body), 1000);
  const pending = call(socket, { body });
  await until(() => up.seen.length === 1);
  assert.equal(budget.reserved, 350);
  releaseHold();
  await pending;
});

test("refusals carry statuses Claude Code does not retry: 429 spend limit past the cap, with x-should-retry false", async () => {
  // The first request commits 900; the second reserves about 130 more.
  const up = await stubUpstream(okJson({ input_tokens: 450, output_tokens: 450 }));
  const { socket } = await startProxy(up, { tokenCap: 1000, maxTokensCeiling: 100 });
  assert.equal((await call(socket, { body: message() })).status, 200);
  const res = await call(socket, { body: message() });
  assert.equal(res.status, 429);
  assert.equal(res.headers["x-should-retry"], "false");
  assert.deepEqual(JSON.parse(res.body), { type: "error", error: { type: "rate_limit_error", message: "spend limit reached (per-job token cap)" } });
  for (const body of [message({ model: "model-other" }), message({ max_tokens: 101 })]) {
    assert.equal((await call(socket, { body })).headers["x-should-retry"], "false");
  }
  assert.equal(up.seen.length, 1);
});

// Runs the script as the workflow will; resolves once it is listening.
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
  writeFileSync(config, JSON.stringify({ tokenCap: 100000, models: MODELS, maxTokensCeiling: 1000, maxBodyBytes: 100000, socketMode: "660" }));
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
  writeFileSync(good, JSON.stringify({ tokenCap: 1, models: MODELS, maxTokensCeiling: 1, maxBodyBytes: 1 }));
  const bad = path.join(dir, "bad.json");
  writeFileSync(bad, JSON.stringify({ tokenCap: 0, models: [], maxTokensCeiling: 1, maxBodyBytes: 1 }));
  assert.equal(await spawnProxy(["--socket", path.join(dir, "a.sock"), "--config", good], "").exited, 2);
  assert.equal(await spawnProxy(["--socket", path.join(dir, "b.sock"), "--config", bad], KEY).exited, 2);
  assert.equal(await spawnProxy(["--config", good], KEY).exited, 2);
});
