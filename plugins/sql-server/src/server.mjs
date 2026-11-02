// The MCP server over stdio. It serves both protocol eras: a request whose
// _meta names a protocol version is served statelessly under revision
// 2026-07-28, and a request without one under the initialize-based revision
// 2025-11-25. Either way the tools capability declares listChanged false and
// tools/list returns the same fixed list (ADR 0086 section 2).
import { createInterface } from 'node:readline';
import { TOOLS, ToolInputError, callTool } from './tools.mjs';

export const PROTOCOL_VERSION = '2026-07-28';
export const LEGACY_PROTOCOL_VERSION = '2025-11-25';
const SUPPORTED_VERSIONS = Object.freeze([PROTOCOL_VERSION, LEGACY_PROTOCOL_VERSION]);

export const CAPABILITIES = Object.freeze({ tools: Object.freeze({ listChanged: false }) });

const META_VERSION = 'io.modelcontextprotocol/protocolVersion';
const META_CAPABILITIES = 'io.modelcontextprotocol/clientCapabilities';
const META_SERVER_INFO = 'io.modelcontextprotocol/serverInfo';

export const ERROR_CODES = Object.freeze({
  parse: -32700,
  invalidRequest: -32600,
  methodNotFound: -32601,
  invalidParams: -32602,
  internal: -32603,
  unsupportedProtocolVersion: -32022,
});

class RpcError extends Error {
  constructor(code, message, data) {
    super(message);
    this.code = code;
    this.data = data;
  }
}

const isObject = (value) => typeof value === 'object' && value !== null && !Array.isArray(value);
const isId = (value) => typeof value === 'string' || Number.isInteger(value);

function errorResponse(id, code, message, data) {
  return { jsonrpc: '2.0', id, error: data === undefined ? { code, message } : { code, message, data } };
}

function toolResult(data) {
  const result = { content: [{ type: 'text', text: JSON.stringify(data) ?? 'null' }], isError: false };
  if (isObject(data)) result.structuredContent = data;
  return result;
}

const toolError = (message) => ({ content: [{ type: 'text', text: message }], isError: true });

/**
 * @param {object} options
 * @param {readonly string[]} options.databases The registration's allow-list; the first is the default.
 * @param {import('./tools.mjs').Executor} options.executor
 * @param {import('./tools.mjs').Executor} [options.writeExecutor] The write principal's executor; only a registration that opted in to writes has one.
 * @param {{ name: string, version: string }} [options.serverInfo]
 * @param {(line: string) => void} [options.log] Where an unexpected error is reported; never stdout.
 */
export function createServer({ databases, executor, writeExecutor, serverInfo = { name: 'sql-server', version: '0.0.0' }, log = () => {} }) {
  const binding = { databases: Object.freeze([...databases]), executor, writeExecutor };

  async function dispatch(method, params) {
    if (method === 'initialize') {
      const requested = params.protocolVersion;
      return {
        protocolVersion: SUPPORTED_VERSIONS.includes(requested) && requested !== PROTOCOL_VERSION ? requested : LEGACY_PROTOCOL_VERSION,
        capabilities: CAPABILITIES,
        serverInfo,
      };
    }

    const meta = isObject(params._meta) ? params._meta : {};
    const modern = Object.hasOwn(meta, META_VERSION);
    if (modern) {
      if (meta[META_VERSION] !== PROTOCOL_VERSION) {
        throw new RpcError(ERROR_CODES.unsupportedProtocolVersion, 'Unsupported protocol version', {
          supported: SUPPORTED_VERSIONS,
          requested: meta[META_VERSION],
        });
      }
      if (!isObject(meta[META_CAPABILITIES])) {
        throw new RpcError(ERROR_CODES.invalidParams, `_meta is missing ${META_CAPABILITIES}`);
      }
    }
    const complete = (result) => (modern ? { resultType: 'complete', ...result, _meta: { [META_SERVER_INFO]: serverInfo } } : result);

    switch (method) {
      case 'server/discover':
        if (!modern) throw new RpcError(ERROR_CODES.invalidParams, `_meta is missing ${META_VERSION}`);
        return complete({ supportedVersions: SUPPORTED_VERSIONS, capabilities: CAPABILITIES });
      case 'ping':
        return complete({});
      case 'tools/list':
        return complete({ tools: TOOLS });
      case 'tools/call': {
        const { name } = params;
        if (typeof name !== 'string' || !TOOLS.some((tool) => tool.name === name)) {
          throw new RpcError(ERROR_CODES.invalidParams, `Unknown tool: ${String(name)}`);
        }
        try {
          return complete(toolResult(await callTool(binding, name, params.arguments)));
        } catch (error) {
          if (error instanceof ToolInputError) return complete(toolError(error.message));
          return complete(toolError(`the ${name} call failed: ${error instanceof Error ? error.message : String(error)}`));
        }
      }
      default:
        throw new RpcError(ERROR_CODES.methodNotFound, `Method not found: ${method}`);
    }
  }

  // Returns the response for a request, or null for a notification, which
  // never gets one. Never rejects.
  async function handle(message) {
    if (!isObject(message) || message.jsonrpc !== '2.0' || typeof message.method !== 'string') {
      return errorResponse(isObject(message) && isId(message.id) ? message.id : null, ERROR_CODES.invalidRequest, 'Invalid Request');
    }
    if (!Object.hasOwn(message, 'id')) return null;
    if (!isId(message.id)) return errorResponse(null, ERROR_CODES.invalidRequest, 'Invalid Request: the id must be a string or an integer');
    const params = message.params ?? {};
    if (!isObject(params)) return errorResponse(message.id, ERROR_CODES.invalidParams, 'params must be an object');
    try {
      return { jsonrpc: '2.0', id: message.id, result: await dispatch(message.method, params) };
    } catch (error) {
      if (error instanceof RpcError) return errorResponse(message.id, error.code, error.message, error.data);
      log(`sql-server: ${message.method} failed: ${error instanceof Error ? error.stack : String(error)}`);
      return errorResponse(message.id, ERROR_CODES.internal, 'Internal error');
    }
  }

  return { handle };
}

// Reads one JSON-RPC message per line from input and writes each response as
// one line to output. Resolves once input ends and every request in flight has
// been answered.
export function serveStdio(server, { input = process.stdin, output = process.stdout } = {}) {
  const write = (message) => output.write(`${JSON.stringify(message)}\n`);
  const lines = createInterface({ input, crlfDelay: Infinity });
  // A write error (EPIPE) means the client closed stdout; no one is left to answer.
  output.on('error', () => lines.close());
  const inFlight = new Set();
  lines.on('line', (line) => {
    if (line.trim() === '') return;
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      write(errorResponse(null, ERROR_CODES.parse, 'Parse error'));
      return;
    }
    const task = server
      .handle(message)
      .then((response) => {
        if (response && !output.destroyed) write(response);
      })
      .finally(() => inFlight.delete(task));
    inFlight.add(task);
  });
  return new Promise((resolve) => {
    lines.once('close', () => {
      Promise.allSettled([...inFlight]).then(() => resolve());
    });
  });
}
