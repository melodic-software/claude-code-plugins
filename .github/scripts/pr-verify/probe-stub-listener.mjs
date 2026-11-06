// Throwaway stand-in for key-proxy.mjs in the #13711 runner probe
// (.github/workflows/probe-13711-bash.yml). Same command line as the proxy:
//
//   node probe-stub-listener.mjs --socket <path> --config <file.json> < stub-key
//
// It reads a `stub-` key on stdin (anything else exits 2), listens on the unix
// socket, sets the config's socketMode on it after listen, and logs one JSON
// line per request to stderr with key-proxy's `status`, `used` and `committed`
// fields, so "Report the key proxy's usage" reads it unchanged. Each line adds
// the request's path, model, max_tokens, body bytes, anthropic-beta header and
// caller: `outer` for the x-api-key `stub-key-not-secret`, `driven` for a
// `ccd-dummy-` key, else `other`. It never forwards anything and logs no key.
//
// /v1/messages gets a canned reply, streaming or not. An outer request whose
// user text holds a `PROBE-BASH: <command>` line, with no tool_result yet,
// gets a Bash tool_use running that command; after the tool_result it answers
// `probe-done`. A driven request whose user text holds `DRIVEN-BASH:`, with
// no tool_result yet, gets a Bash tool_use running DRIVEN_COMMAND; after the
// tool_result it answers STUB-DRIVEN-DONE. Haiku requests never get a
// tool_use. Every other /v1/messages request gets the text STUB-DRIVEN-REPLY.
// count_tokens answers 10; any other path 404.
import http from 'node:http';
import { chmodSync, readFileSync, rmSync } from 'node:fs';
import process from 'node:process';

const OUTER_KEY = 'stub-key-not-secret';
const DRIVEN_PREFIX = 'ccd-dummy-';
const DRIVEN_TEXT = 'STUB-DRIVEN-REPLY';
const DRIVEN_DONE = 'STUB-DRIVEN-DONE';
// Run by the driven session's Bash tool; it prints facts only, never a value
// of the key variable.
const DRIVEN_COMMAND = [
  'echo probe',
  'echo "uid=$(id -u) pids_bash=$(ls -d /proc/[0-9]* | wc -l) pid1=$(cat /proc/1/comm)"',
  'echo "apikey_bash=${ANTHROPIC_API_KEY:+set}"',
  'echo "sentinel_bash=$(grep -lsF CCD_SENTINEL_CREDENTIAL= /proc/[0-9]*/environ | wc -l)"',
  'curl -sS -o /dev/null --max-time 5 https://example.com/; echo "curl_https=$?"',
  'curl -sS -o /dev/null --max-time 5 http://1.1.1.1/; echo "curl_ip=$?"',
  "node -e 'fetch(\"https://example.com/\").then((r) => console.log(\"node_fetch=open \" + r.status), (e) => console.log(\"node_fetch=refused \" + (e.cause && e.cause.code)))'",
  'echo "proxy_env=${HTTPS_PROXY:-none}"',
].join('; ');

const argValue = (argv, name) => {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : undefined;
};

const textOf = (c) =>
  typeof c === 'string'
    ? c
    : (c ?? []).map((b) => b.text ?? (b.type === 'tool_result' ? `[tool_result] ${JSON.stringify(b.content)}` : '')).join(' ');

const callerOf = (key) => (key === OUTER_KEY ? 'outer' : typeof key === 'string' && key.startsWith(DRIVEN_PREFIX) ? 'driven' : 'other');

function reply(body, caller) {
  const all = body.messages ?? [];
  const last = all.at(-1);
  const results = (Array.isArray(last?.content) ? last.content : []).filter((b) => b.type === 'tool_result');
  const answered = all.some((m) => Array.isArray(m.content) && m.content.some((b) => b.type === 'tool_result'));
  let command;
  for (const m of all) {
    if (m.role !== 'user') continue;
    const hit = /PROBE-BASH: ([^\n]+)/.exec(textOf(m.content));
    if (hit) command = hit[1].trim();
  }
  const haiku = /haiku/.test(body.model ?? '');
  const wantsBash = caller === 'outer' && !answered && command && !haiku;
  if (wantsBash) return { results, block: { type: 'tool_use', id: 'toolu_probe01', name: 'Bash', input: { command, description: 'probe' } } };
  if (caller === 'driven' && !haiku) {
    const asked = all.some((m) => m.role === 'user' && textOf(m.content).includes('DRIVEN-BASH:'));
    if (asked && !answered) return { results, block: { type: 'tool_use', id: 'toolu_probe02', name: 'Bash', input: { command: DRIVEN_COMMAND, description: 'probe' } } };
    if (asked && results.length) return { results, block: { type: 'text', text: DRIVEN_DONE } };
  }
  return { results, block: { type: 'text', text: caller === 'outer' ? (results.length ? 'probe-done' : 'ok') : DRIVEN_TEXT } };
}

function sse(res, model, block) {
  res.writeHead(200, { 'content-type': 'text/event-stream' });
  const ev = (type, data) => res.write(`event: ${type}\ndata: ${JSON.stringify({ type, ...data })}\n\n`);
  ev('message_start', { message: { id: 'msg_probe', type: 'message', role: 'assistant', model, content: [], stop_reason: null, stop_sequence: null, usage: { input_tokens: 10, output_tokens: 1 } } });
  if (block.type === 'tool_use') {
    ev('content_block_start', { index: 0, content_block: { ...block, input: {} } });
    ev('content_block_delta', { index: 0, delta: { type: 'input_json_delta', partial_json: JSON.stringify(block.input) } });
  } else {
    ev('content_block_start', { index: 0, content_block: { type: 'text', text: '' } });
    ev('content_block_delta', { index: 0, delta: { type: 'text_delta', text: block.text } });
  }
  ev('content_block_stop', { index: 0 });
  ev('message_delta', { delta: { stop_reason: block.type === 'tool_use' ? 'tool_use' : 'end_turn', stop_sequence: null }, usage: { output_tokens: 5 } });
  ev('message_stop', {});
  res.end();
}

async function main(argv) {
  const socket = argValue(argv, '--socket');
  const configPath = argValue(argv, '--config');
  if (!socket || !configPath) {
    process.stderr.write('usage: probe-stub-listener.mjs --socket <path> --config <file.json> < stub-key\n');
    return 2;
  }
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  const chunks = [];
  for await (const c of process.stdin) chunks.push(c);
  if (!Buffer.concat(chunks).toString('utf8').trim().startsWith('stub-')) {
    process.stderr.write('probe-stub-listener: the key on stdin is not a stub- key\n');
    return 2;
  }
  const log = (o) => process.stderr.write(`${JSON.stringify({ t: new Date().toISOString(), ...o })}\n`);
  let committed = 0;
  const server = http.createServer((req, res) => {
    const parts = [];
    req.on('data', (d) => parts.push(d));
    req.on('end', () => {
      const raw = Buffer.concat(parts);
      const [path, query = null] = req.url.split('?');
      let body = {};
      try {
        body = JSON.parse(raw.toString('utf8') || '{}');
      } catch {}
      const caller = callerOf(req.headers['x-api-key']);
      const entry = {
        method: req.method,
        path,
        query,
        caller,
        model: typeof body.model === 'string' ? body.model : null,
        max_tokens: Number.isInteger(body.max_tokens) ? body.max_tokens : null,
        bytes: raw.length,
        beta: req.headers['anthropic-beta'] ?? null,
        stream: body.stream === true,
        keys: Object.keys(body).sort(),
        auth: Boolean(req.headers.authorization),
      };
      if (req.method === 'POST' && path === '/v1/messages/count_tokens') {
        log({ ...entry, status: 200, used: 0, committed });
        res.writeHead(200, { 'content-type': 'application/json' }).end('{"input_tokens":10}');
        return;
      }
      if (req.method !== 'POST' || path !== '/v1/messages') {
        log({ ...entry, status: 404, used: 0, committed });
        res.writeHead(404, { 'content-type': 'application/json' }).end('{"type":"error","error":{"type":"not_found_error","message":"probe stub"}}');
        return;
      }
      const { results, block } = reply(body, caller);
      committed += 15;
      log({ ...entry, status: 200, used: 15, committed, reply: block.type, toolResults: results.map((r) => ({ error: r.is_error === true, content: JSON.stringify(r.content).slice(0, 4000) })) });
      if (body.stream) return sse(res, body.model, block);
      res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ id: 'msg_probe', type: 'message', role: 'assistant', model: body.model, content: [block], stop_reason: block.type === 'tool_use' ? 'tool_use' : 'end_turn', stop_sequence: null, usage: { input_tokens: 10, output_tokens: 5 } }));
    });
  });
  rmSync(socket, { force: true });
  await new Promise((resolve, reject) => server.once('error', reject).listen(socket, resolve));
  if (config.socketMode !== undefined) chmodSync(socket, config.socketMode);
  log({ listening: socket, stub: true });
  const stop = () => server.close(() => process.exit(0));
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
  return null;
}

main(process.argv.slice(2)).then(
  (code) => {
    if (code !== null) process.exit(code);
  },
  (e) => {
    process.stderr.write(`probe-stub-listener: ${e.message}\n`);
    process.exit(1);
  },
);
