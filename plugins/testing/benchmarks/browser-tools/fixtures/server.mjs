#!/usr/bin/env node
// Fixture server for the browser-tools benchmark. Serves the pages under ./pages, keeps a
// per-run record of what each page reported, and answers the grader. Two ports share one state so
// a cross-origin iframe can report to its own origin.
//
//   node server.mjs [--port 4400] [--port2 4401]
//
// Every page URL carries ?run=<id>&delay=<ms>. Pages report through /fx.js (fx.record), which posts
// to /__record on their own origin. The grader reads /__state?run=<id>.

import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { createHmac, randomBytes } from "node:crypto";
import { extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";

const here = fileURLToPath(new URL(".", import.meta.url));
const pagesDir = join(here, "pages");
const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => (a.startsWith("--") ? [...acc, [a.slice(2), all[i + 1]]] : acc), []),
);
const port = Number(args.port ?? 4400);
const port2 = Number(args.port2 ?? port + 1);
const secret = randomBytes(16).toString("hex");

const runs = new Map();
function run(id) {
  if (!runs.has(id)) runs.set(id, { records: {}, events: [], requests: [] });
  return runs.get(id);
}
// Codes are unguessable from the URL: an HMAC of the run id and a purpose under a per-process secret.
const code = (id, purpose) => `${purpose.toUpperCase().slice(0, 3)}-${createHmac("sha256", secret).update(`${id}:${purpose}`).digest("hex").slice(0, 6).toUpperCase()}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, Math.max(0, Number(ms) || 0)));

const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".txt": "text/plain", ".json": "application/json" };
const tokens = new Map(); // auth token -> run id

function send(res, status, body, headers = {}) {
  const data = typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body);
  res.writeHead(status, { "cache-control": "no-store", "access-control-allow-origin": "*", ...headers });
  res.end(data);
}
async function body(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  return Buffer.concat(chunks).toString("utf8");
}
function cookies(req) {
  return Object.fromEntries((req.headers.cookie ?? "").split(";").filter(Boolean).map((c) => c.trim().split("=")));
}

async function handle(req, res, origin) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const q = Object.fromEntries(url.searchParams);
  const id = q.run ?? "none";
  const r = run(id);
  r.requests.push({ t: Date.now(), method: req.method, path: url.pathname, query: q, origin });

  switch (url.pathname) {
    case "/__record": {
      const { key, value, mode } = JSON.parse((await body(req)) || "{}");
      if (mode === "append") (r.records[key] ??= []).push(value);
      else if (mode === "inc") r.records[key] = (r.records[key] ?? 0) + 1;
      else r.records[key] = value;
      r.events.push({ t: Date.now(), key, value, mode: mode ?? "set" });
      return send(res, 204, "");
    }
    case "/__state":
      return send(res, 200, { ...r, codes: Object.fromEntries(["nav", "str", "pop", "dlx", "toa", "frm", "acc", "rpt", "dev", "sav", "won"].map((p) => [p, code(id, p)])) });
    case "/__reset":
      runs.delete(id);
      return send(res, 204, "");
    case "/api/code":
      return send(res, 200, { code: code(id, q.purpose ?? "x") });
    case "/api/fragment": {
      await sleep(q.delay);
      const p = Number(q.p ?? 2);
      const html =
        p === 2
          ? `<h1>Page 2: Archive</h1><p id="navcode">Reference code: ${code(id, "nav")}</p><ul id="arch">${["Apple", "Kiwi", "Mango", "Plum"]
              .map((n) => `<li data-name="${n}">${n} <button type="button" data-archive="${n}">Archive ${n}</button></li>`)
              .join("")}</ul><a href="/f/F02-enhanced-nav.html?run=${id}&delay=${q.delay ?? 0}">Back to page 1</a>`
          : `<h1>Page 1</h1>`;
      return send(res, 200, html, { "content-type": "text/html; charset=utf-8" });
    }
    case "/api/stream": {
      res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "transfer-encoding": "chunked" });
      const shell = await readFile(join(pagesDir, "F04-streaming.html"), "utf8");
      res.write(shell);
      await sleep(q.delay);
      res.write(`<template id="streamed"><span id="total">Total due: ${code(id, "str")}</span></template><script>document.getElementById('placeholder').replaceWith(document.getElementById('streamed').content.cloneNode(true));fx.record('streamed', true);</script></body></html>`);
      return res.end();
    }
    case "/api/save": {
      await sleep(q.delay);
      const data = Object.fromEntries(new URLSearchParams(await body(req)));
      r.records.saved = data;
      return send(res, 200, `<p id="saved">Saved: ${code(id, "frm")}</p>`, { "content-type": "text/html; charset=utf-8" });
    }
    case "/api/items":
      await sleep(q.delay);
      return send(res, 200, [{ name: "Real item 1" }, { name: "Real item 2" }], { "content-type": "application/json" });
    case "/api/report":
      await sleep(q.delay);
      return send(res, 500, { error: "report generator unavailable" }, { "content-type": "application/json" });
    case "/beacon":
      (r.records.beacons ??= []).push(q.c);
      return send(res, 204, "");
    case "/download/report.txt":
      return send(res, 200, `Quarterly report\nDownload code: ${code(id, "dlx")}\n`, {
        "content-type": "text/plain",
        "content-disposition": 'attachment; filename="report.txt"',
      });
    case "/login": {
      if (req.method !== "POST") break;
      const form = Object.fromEntries(new URLSearchParams(await body(req)));
      r.records.logins = (r.records.logins ?? 0) + 1;
      if (form.username === "demo" && form.password === "correct-horse") {
        const token = randomBytes(12).toString("hex");
        tokens.set(token, id);
        return send(res, 303, "", { location: `/account?run=${id}&phase=1`, "set-cookie": `fx_session=${token}; Path=/; HttpOnly; SameSite=Lax` });
      }
      return send(res, 401, `<p id="error">Invalid credentials</p>`, { "content-type": "text/html; charset=utf-8" });
    }
    case "/account": {
      const token = cookies(req).fx_session;
      if (!token || tokens.get(token) !== id)
        return send(res, 302, "", { location: `/f/T05-login.html?run=${id}` });
      (r.records.accountViews ??= []).push(q.phase ?? "0");
      return send(
        res,
        200,
        `<!doctype html><title>Account</title><h1>Your account</h1><p id="acct">Account code: ${code(id, "acc")}</p>`,
        { "content-type": "text/html; charset=utf-8" },
      );
    }
  }

  // Static pages and fx.js.
  const rel = url.pathname === "/fx.js" ? "fx.js" : url.pathname.startsWith("/f/") ? url.pathname.slice(3) : null;
  if (!rel) return send(res, 404, "not found");
  const file = normalize(join(pagesDir, rel));
  if (!file.startsWith(pagesDir)) return send(res, 403, "forbidden");
  try {
    const content = await readFile(file);
    return send(res, 200, content, { "content-type": types[extname(file)] ?? "application/octet-stream" });
  } catch {
    return send(res, 404, "not found");
  }
}

for (const [p, origin] of [
  [port, "primary"],
  [port2, "secondary"],
]) {
  createServer((req, res) =>
    handle(req, res, origin).catch((e) => {
      console.error(e);
      if (!res.headersSent) send(res, 500, "server error");
    }),
  ).listen(p, "127.0.0.1", () => console.log(`fixture server (${origin}) on http://127.0.0.1:${p}`));
}
