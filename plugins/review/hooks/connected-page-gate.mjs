#!/usr/bin/env node
// PreToolUse guard on the Artifact tool: deny publishing an HTML page whose content
// security policy names a loopback connect-src. That is a connected page built with
// --connect (lib/view-builder.mjs): it reaches a session bridge on this machine, so
// published it is dead weight on claude.ai and leaks the local port.
//
// Detection reads the file content, not its path, mode or builder, so a connected page
// from any builder is caught. Checked: the `file_path` and every HTML entry in `files`.
// Everything else passes: a call with no file (read, list, open, quickstart, a type_url
// create), a non-HTML asset, a page without that directive, and a file that cannot be
// read (the Artifact tool fails on it anyway).
//
// Fail-open: a malformed payload or any internal error exits 0 with no output.
// Kill switch: userConfig connected_page_guard_enabled, read via its hook-process mirror.
// Option (a), an approval-marker publish gate, is not built here (#7956).

import { closeSync, openSync, readSync } from 'node:fs';
import { resolve } from 'node:path';

// Each connect-src source list, up to the directive's end; quoted keywords stay in it.
const CONNECT_SRC = /connect-src\s+([^;"<>]*)/gi;
// A source's host: scheme and path dropped, a bracketed IPv6 literal kept whole.
const SOURCE_HOST = /^(?:[a-z][a-z0-9+.-]*:\/\/)?(\[[^\]]*\]|[^/:?#]*)/i;
const LOOPBACK_HOST = /^(?:localhost|(?:[^.]+\.)+localhost|0\.0\.0\.0|127(?:\.\d{1,3}){0,3}|\[(?:::1|(?:0{1,4}:){7}0{0,3}1|::ffff:127(?:\.\d{1,3}){3})\])$/i;
const HTML_NAME = /\.html?$/i;
const HTML_SNIFF = /^\s*<(?:!doctype\s+html|html[\s>])/i;
const READ_LIMIT = 2 * 1024 * 1024;

const loopbackConnect = (text) =>
  [...text.matchAll(CONNECT_SRC)].some(([, list]) =>
    list.split(/\s+/).some((source) =>
      source && !source.startsWith("'") && LOOPBACK_HOST.test(SOURCE_HOST.exec(source)?.[1] ?? '')));

function head(path) {
  const fd = openSync(path, 'r');
  try {
    const buf = Buffer.alloc(READ_LIMIT);
    const n = readSync(fd, buf, 0, READ_LIMIT, 0);
    return buf.toString('utf8', 0, n);
  } finally {
    closeSync(fd);
  }
}

function connected(path, cwd) {
  let text;
  try {
    text = head(resolve(cwd, path));
  } catch {
    return false; // unreadable: the Artifact tool fails on it anyway
  }
  if (!HTML_NAME.test(path) && !HTML_SNIFF.test(text.slice(0, 1024))) return false;
  return loopbackConnect(text);
}

const paths = (input) =>
  [input?.file_path, ...(Array.isArray(input?.files) ? input.files : [])
    .map((f) => (typeof f === 'string' ? f : f?.file_path ?? f?.path))]
    .filter((p) => typeof p === 'string');

if (process.env.CLAUDE_PLUGIN_OPTION_CONNECTED_PAGE_GUARD_ENABLED === 'false') {
  process.exit(0);
}

let raw = '';
process.stdin.on('data', (d) => { raw += d; });
process.stdin.on('end', () => {
  try {
    const payload = JSON.parse(raw);
    if (payload?.tool_name !== 'Artifact') process.exit(0);
    const cwd = typeof payload.cwd === 'string' && payload.cwd ? payload.cwd : process.cwd();
    const hit = paths(payload.tool_input).find((p) => connected(p, cwd));
    if (hit) process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'deny',
        permissionDecisionReason: `review: ${hit} is a connected page: its content security policy names a loopback connect-src, so it works only on this machine. Keep it as a local file and give the reader its path; do not publish it as an Artifact.`,
      },
    }));
  } catch {
    // fail-open
  }
  process.exit(0);
});
