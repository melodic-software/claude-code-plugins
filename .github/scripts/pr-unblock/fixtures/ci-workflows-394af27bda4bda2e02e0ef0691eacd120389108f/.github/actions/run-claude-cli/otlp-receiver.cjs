// An OTLP/HTTP receiver for one leg's telemetry, inside the run-claude-cli
// step's own process: no extra process to stop, and it ends with the step
// however the step ends. It binds 127.0.0.1 on a free port, takes the JSON
// encoding of traces and logs (https://opentelemetry.io/docs/specs/otlp/#otlphttp)
// and keeps each accepted request as one line in memory. Nothing it holds
// reaches a file or the log here: lane.cjs decides what to keep once the leg
// has ended.
"use strict";

const http = require("node:http");
const zlib = require("node:zlib");

const HOST = "127.0.0.1";
// Under the transcript artifact's 63 MiB limit (seal-transcript.cjs). Applies
// to one decompressed request and to everything kept.
const MAX_TELEMETRY_BYTES = 60 * 1024 * 1024;
const CLOSE_GRACE_MS = 2000;
// Request path to the top-level field of its Export*ServiceRequest.
const SIGNALS = new Map([
  ["/v1/traces", "resourceSpans"],
  ["/v1/logs", "resourceLogs"],
]);

class Refused extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function decompressed(body, encoding) {
  if (encoding === "" || encoding === "identity") return Promise.resolve(body);
  if (encoding !== "gzip") {
    return Promise.reject(new Refused(415, "unsupported content encoding"));
  }
  return new Promise((resolve, reject) => {
    zlib.gunzip(
      body,
      { maxOutputLength: MAX_TELEMETRY_BYTES },
      (error, out) => {
        if (error === null) resolve(out);
        else if (error.code === "ERR_BUFFER_TOO_LARGE") {
          reject(new Refused(413, "request too large"));
        } else reject(new Refused(400, "request is not gzip"));
      },
    );
  });
}

// The request as one JSONL line, or "" when it carries no telemetry. The text
// is kept as sent, so every id and number survives exactly; a raw line break
// can only be whitespace between JSON tokens.
function lineOf(text, field) {
  let request;
  try {
    request = JSON.parse(text);
  } catch {
    throw new Refused(400, "request is not JSON");
  }
  if (
    request === null ||
    typeof request !== "object" ||
    Array.isArray(request)
  ) {
    throw new Refused(400, "request is not a JSON object");
  }
  const items = request[field];
  if (items === undefined || (Array.isArray(items) && items.length === 0)) {
    return "";
  }
  if (!Array.isArray(items)) throw new Refused(400, "request is malformed");
  return `${text.replace(/[\r\n]+/gu, " ").trim()}\n`;
}

function reply(response, status, body) {
  const text = JSON.stringify(body);
  response.writeHead(status, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(text),
  });
  response.end(text);
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let bytes = 0;
    request.on("data", (chunk) => {
      bytes += chunk.length;
      // Past the limit the rest is read and dropped, so the client gets the 413.
      if (bytes <= MAX_TELEMETRY_BYTES) chunks.push(chunk);
      else chunks.length = 0;
    });
    request.on("end", () => {
      if (bytes > MAX_TELEMETRY_BYTES) {
        reject(new Refused(413, "request too large"));
      } else resolve(Buffer.concat(chunks));
    });
    request.on("error", reject);
  });
}

/**
 * Starts the receiver. Resolves to `{ endpoint, stop }`; rejects when it cannot
 * bind. `stop()` never rejects and resolves to `{ text, dropped }`: the JSONL
 * kept, and how many requests the size limit turned away.
 */
function startOtlpReceiver({
  createServer = http.createServer,
  graceMs = CLOSE_GRACE_MS,
} = {}) {
  const lines = [];
  let kept = 0;
  let dropped = 0;
  let stopped = false;

  const accept = async (request) => {
    const field = SIGNALS.get(request.url);
    if (field === undefined) throw new Refused(404, "unknown path");
    if (request.method !== "POST") throw new Refused(405, "POST only");
    const type = (request.headers["content-type"] ?? "").split(";")[0].trim();
    if (type.toLowerCase() !== "application/json") {
      throw new Refused(415, "only application/json is accepted");
    }
    const encoding = (request.headers["content-encoding"] ?? "").toLowerCase();
    const body = await decompressed(await readBody(request), encoding);
    const line = lineOf(body.toString("utf8"), field);
    if (line === "" || stopped) return;
    const bytes = Buffer.byteLength(line);
    if (kept + bytes > MAX_TELEMETRY_BYTES) {
      throw new Refused(413, "telemetry limit reached");
    }
    kept += bytes;
    lines.push(line);
  };

  const server = createServer((request, response) => {
    response.on("error", () => {});
    accept(request)
      .then(
        () => reply(response, 200, {}),
        (error) => {
          if (error.status === 413) dropped += 1;
          // A closed message only: a request's content never enters a reply.
          const refused = error instanceof Refused;
          reply(response, refused ? error.status : 500, {
            message: refused ? error.message : "request failed",
          });
        },
      )
      .catch(() => {});
  });

  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, HOST, () => {
      server.removeListener("error", reject);
      server.on("error", () => {});
      const { address, port } = server.address();
      if (address !== HOST) {
        server.close();
        reject(new Error("the receiver is not on the loopback address"));
        return;
      }
      // Never the reason the step's process stays up.
      server.unref();
      let stopping = null;
      const stop = () => {
        stopping ??= new Promise((done) => {
          const finish = () => {
            stopped = true;
            clearTimeout(timer);
            done({ text: lines.join(""), dropped });
          };
          // A process the leg left behind may hold a connection open.
          const timer = setTimeout(() => server.closeAllConnections(), graceMs);
          server.close(finish);
          server.closeIdleConnections();
        });
        return stopping;
      };
      resolve({ endpoint: `http://${HOST}:${port}`, stop });
    });
  });
}

module.exports = { HOST, MAX_TELEMETRY_BYTES, startOtlpReceiver };
