import { killTree, query, start } from "./process.mjs";
import { EXIT, guardValues, oneLine, pickBinary, setup, Stop } from "./runner.mjs";

const DEFAULT_TIMEOUT_MS = 15_000;
const CLOSE_GRACE_MS = 500;

const isMap = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const clamp01 = (n) => Math.min(1, Math.max(0, Math.round(n * 10_000) / 10_000));
const lastLine = (text) => text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean).at(-1) ?? "";

function parseObject(text) {
  try {
    const value = JSON.parse(text);
    return isMap(value) ? value : null;
  } catch {
    return null;
  }
}

function formatMinutes(mins) {
  if (typeof mins !== "number" || !Number.isFinite(mins) || mins <= 0) return null;
  if (mins % 1440 === 0) return `${mins / 1440}d`;
  if (mins % 60 === 0) return `${mins / 60}h`;
  return `${mins}m`;
}

function parseJsonRpcReply(msg, source) {
  if (msg.error !== undefined) {
    const code = typeof msg.error?.code === "number" ? ` ${msg.error.code}` : "";
    return { ok: false, reason: `app-server returned error${code}` };
  }
  const primary = msg.result?.rateLimits?.primary;
  if (!isMap(primary) || typeof primary.usedPercent !== "number" || !Number.isFinite(primary.usedPercent)) {
    return { ok: false, reason: "rateLimits.primary.usedPercent missing in reply" };
  }
  const remaining = clamp01(1 - primary.usedPercent / 100);
  const window = formatMinutes(primary.windowDurationMins);
  const resetsAt = typeof primary.resetsAt === "number" && Number.isFinite(primary.resetsAt) && primary.resetsAt > 0
    ? new Date(primary.resetsAt * 1000).toISOString()
    : null;
  return {
    ok: true,
    reading: {
      status: "ok",
      remaining,
      ...(window ? { window } : {}),
      ...(resetsAt ? { resets_at: resetsAt } : {}),
      source,
    },
  };
}

function readJsonRpcStdio(binary, spec, { ctx, source, timeoutMs }) {
  return new Promise((resolve) => {
    const child = start(binary, spec.args, { cwd: ctx.cwd, env: ctx.env, stdio: ["pipe", "pipe", "pipe"] });
    const requestId = 1;
    let settled = false;
    let reply = null;
    let buffer = "";
    let graceTimer = null;

    const killChild = () => {
      try { child.kill("SIGKILL"); } catch {}
      killTree(child.pid);
    };

    const finish = (outcome) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      clearTimeout(graceTimer);
      resolve(outcome);
    };

    const timer = setTimeout(() => {
      try { child.stdin.end(); } catch {}
      killChild();
      finish({ ok: false, reason: `timed out after ${timeoutMs} ms` });
    }, timeoutMs);

    const handleLine = (line) => {
      if (reply || !line.trim()) return;
      const msg = parseObject(line.trim());
      if (!msg || msg.id !== requestId) return;
      reply = parseJsonRpcReply(msg, source);
      clearTimeout(timer);
      try { child.stdin.end(); } catch {}
      graceTimer = setTimeout(() => {
        killChild();
        finish(reply);
      }, CLOSE_GRACE_MS);
    };

    child.stdin.on("error", () => {});
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      buffer += chunk;
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop() ?? "";
      for (const line of lines) handleLine(line);
    });

    child.once("error", (error) => finish({ ok: false, reason: oneLine(error.message) }));
    child.once("close", (code) => {
      if (!reply && buffer.trim()) handleLine(buffer);
      if (reply) {
        finish(reply);
        return;
      }
      finish({ ok: false, reason: code === 0 ? "app-server closed before answering" : `app-server exited ${code}` });
    });

    const payload = [
      JSON.stringify({ method: "initialize", id: 0, params: { clientInfo: { name: "external-agents", version: "1.0.0" } } }),
      JSON.stringify({ method: "initialized" }),
      JSON.stringify({ method: spec.method, id: requestId }),
    ].join("\n") + "\n";
    try {
      child.stdin.write(payload);
    } catch {}
  });
}

function readJsonEnvelopeLines(binary, spec, { ctx, record, source, timeoutMs }) {
  const got = query(binary, spec.args, { env: ctx.env, cwd: ctx.cwd, timeout: timeoutMs });
  if (got.error) {
    const reason = got.error.code === "ETIMEDOUT" ? `timed out after ${timeoutMs} ms` : oneLine(got.error.message);
    return { ok: false, reason };
  }
  if (got.code !== 0) return { ok: false, reason: `exited ${got.code}` };
  const envelope = parseObject(got.stdout.trim()) ?? parseObject(lastLine(got.stdout));
  if (!envelope) return { ok: false, reason: "no JSON envelope on stdout" };
  const statusField = record.output?.status_field;
  const okValue = record.output?.success_value;
  if (statusField && okValue && envelope[statusField] !== undefined && envelope[statusField] !== okValue) {
    return { ok: false, reason: `CLI status ${JSON.stringify(envelope[statusField])}` };
  }
  const text = envelope[record.output?.message_field ?? "response"];
  if (typeof text !== "string") return { ok: false, reason: "no response text in JSON envelope" };
  const windows = [];
  for (const raw of text.split(/\r?\n/)) {
    const cols = raw.split("\t");
    if (cols.length < 3) continue;
    const group = cols[0].trim();
    const label = cols[1].trim().match(/^(.+?)\s+Limit\s+Remaining$/i);
    const pct = cols[2].trim().match(/^(\d+(?:\.\d+)?)%$/);
    if (!group || !label || !pct) continue;
    const remaining = clamp01(Number(pct[1]) / 100);
    const resetsAt = (cols[3] ?? "").trim();
    windows.push({
      group,
      window: label[1].trim(),
      remaining,
      ...(resetsAt ? { resets_at: resetsAt } : {}),
    });
  }
  if (!windows.length) return { ok: false, reason: "no parsable usage lines in response" };
  const lowest = windows.reduce((min, cur) => (cur.remaining < min.remaining ? cur : min));
  return {
    ok: true,
    reading: {
      status: "ok",
      remaining: lowest.remaining,
      window: lowest.window,
      ...(lowest.resets_at ? { resets_at: lowest.resets_at } : {}),
      windows,
      source,
    },
  };
}

const READERS = {
  jsonrpc_stdio: readJsonRpcStdio,
  json_envelope_lines: readJsonEnvelopeLines,
};

/** Reads one plan-usage snapshot from the installed CLI without starting a model turn. */
export async function usage(opts) {
  const product = opts.product ?? "external-agents";
  const out = (code, doc, notices = []) => ({
    code,
    stdout: `${JSON.stringify(doc, null, 2)}\n`,
    stderr: notices.map((n) => `notice: ${n}\n`).join(""),
  });
  let source = product;
  let notices = [];
  try {
    const state = setup(opts);
    const { ctx, record, settings } = state;
    notices = state.notices;
    const spec = record.usage;
    if (!spec) {
      return out(EXIT.unavailable, { status: "unavailable", source: record.binary.name, reason: `the ${record.product} record declares no usage readout` }, notices);
    }
    const command = [record.binary.name, ...spec.args].join(" ");
    source = spec.kind === "jsonrpc_stdio" ? `${command} (${spec.method})` : command;
    const { binary, missing } = pickBinary(ctx, record, settings);
    if (!binary) {
      return out(EXIT.unavailable, { status: "unavailable", source, reason: `${record.binary.name} not found (tried ${missing.tried.join(", ")}); install it, or set ${record.product}.binary_path` }, notices);
    }
    guardValues(record, binary, {}, false);
    const timeoutMs = opts.timeoutMs ?? spec.timeout_ms ?? DEFAULT_TIMEOUT_MS;
    const result = await READERS[spec.kind](binary, spec, { ctx, record, source, timeoutMs });
    if (!result.ok) return out(EXIT.unavailable, { status: "unavailable", source, reason: result.reason }, notices);
    return out(EXIT.ok, result.reading, notices);
  } catch (error) {
    const code = error instanceof Stop && error.kind === "refused" ? EXIT.usage : EXIT.unavailable;
    return out(code, { status: "unavailable", source, reason: oneLine(error?.message ?? error) }, notices);
  }
}
