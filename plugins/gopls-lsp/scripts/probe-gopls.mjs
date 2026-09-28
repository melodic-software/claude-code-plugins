#!/usr/bin/env node

// Prove gopls is a native executable and that spawning it with no shell
// completes an LSP initialize. gopls defaults to the serve command when no
// subcommand is given, which is the shape the official gopls-lsp manifest uses.

import { spawn } from "node:child_process";
import { openSync, readSync, closeSync, statSync } from "node:fs";
import { delimiter, join } from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const NATIVE = new Set(["elf", "pe", "mach-o"]);

export function classifyExecutable(buffer) {
  if (
    buffer.length >= 4 &&
    buffer[0] === 0x7f &&
    buffer[1] === 0x45 &&
    buffer[2] === 0x4c &&
    buffer[3] === 0x46
  ) {
    return "elf";
  }
  if (buffer.length >= 2 && buffer[0] === 0x4d && buffer[1] === 0x5a) return "pe";
  if (buffer.length >= 4) {
    const be = buffer.readUInt32BE(0);
    const le = buffer.readUInt32LE(0);
    const macho = new Set([0xfeedface, 0xfeedfacf, 0xcafebabe]);
    if (macho.has(be) || macho.has(le)) return "mach-o";
  }
  const head = buffer.subarray(0, 160).toString("utf8");
  if (head.startsWith("#!") || /^\s*@echo\b/i.test(head)) return "script";
  return "unknown";
}

export function isNativeKind(kind) {
  return NATIVE.has(kind);
}

export function readPrefix(filePath, length = 256) {
  const fd = openSync(filePath, "r");
  try {
    const buffer = Buffer.alloc(length);
    const count = readSync(fd, buffer, 0, length, 0);
    return buffer.subarray(0, count);
  } finally {
    closeSync(fd);
  }
}

function isFile(filePath) {
  try {
    return statSync(filePath).isFile();
  } catch {
    return false;
  }
}

export function pathDirs(pathEnv) {
  return String(pathEnv ?? "")
    .split(delimiter)
    .map((part) => part.trim())
    .filter(Boolean);
}

export function candidateCommands(env, home) {
  const names = ["gopls.exe", "gopls"];
  const dirs = [...pathDirs(env.PATH)];
  if (env.GOBIN) dirs.push(env.GOBIN);
  if (env.GOPATH) {
    for (const root of env.GOPATH.split(delimiter)) {
      if (root) dirs.push(join(root, "bin"));
    }
  }
  if (home) dirs.push(join(home, "go", "bin"));
  const files = [];
  for (const dir of dirs) {
    for (const name of names) files.push(join(dir, name));
  }
  return files;
}

export function resolveGopls(options) {
  const env = options.env ?? {};
  const fileExists = options.isFile ?? isFile;
  if (env.GOPLS_PATH && fileExists(env.GOPLS_PATH)) {
    return env.GOPLS_PATH;
  }
  if (options.command && fileExists(options.command)) return options.command;
  for (const candidate of candidateCommands(env, options.home ?? "")) {
    if (fileExists(candidate) && !/\.(cmd|bat)$/i.test(candidate)) return candidate;
  }
  return null;
}

function encode(message) {
  const body = Buffer.from(JSON.stringify(message), "utf8");
  const header = Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, "utf8");
  return Buffer.concat([header, body]);
}

function takeMessage(buffer) {
  const sep = buffer.indexOf("\r\n\r\n");
  if (sep < 0) return null;
  const header = buffer.subarray(0, sep).toString("utf8");
  const match = header.match(/Content-Length:\s*(\d+)/i);
  if (!match) return { error: new Error("missing Content-Length") };
  const length = Number(match[1]);
  const start = sep + 4;
  if (buffer.length < start + length) return null;
  let message;
  try {
    message = JSON.parse(buffer.subarray(start, start + length).toString("utf8"));
  } catch (error) {
    return { error };
  }
  return { message, rest: buffer.subarray(start + length) };
}

export function probeGopls(options) {
  const command = options.command;
  const prefix = readPrefix(command);
  const kind = classifyExecutable(prefix);
  if (!isNativeKind(kind)) {
    return Promise.reject(
      new Error(`${command} is ${kind}, not a native executable (elf, pe, or mach-o)`),
    );
  }
  const args = options.args ?? [];
  const child = spawn(command, args, {
    stdio: ["pipe", "pipe", "pipe"],
    shell: false,
    windowsHide: true,
  });
  const timeoutMs = options.timeoutMs ?? 20000;
  return new Promise((resolve, reject) => {
    let buffer = Buffer.alloc(0);
    let settled = false;
    const finish = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      child.kill();
      if (error) reject(error);
      else resolve(value);
    };
    const timer = setTimeout(() => {
      finish(new Error(`timed out waiting for initialize from ${command}`));
    }, timeoutMs);
    child.on("error", (error) => finish(error));
    child.stderr.on("data", () => {});
    child.stdout.on("data", (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      for (;;) {
        const taken = takeMessage(buffer);
        if (!taken) return;
        if (taken.error) {
          finish(taken.error);
          return;
        }
        buffer = taken.rest;
        if (taken.message.id !== 1) continue;
        if (taken.message.error) {
          finish(new Error(taken.message.error.message || "initialize failed"));
          return;
        }
        const capabilities = taken.message.result?.capabilities;
        if (!capabilities) {
          finish(new Error("initialize result has no capabilities"));
          return;
        }
        finish(null, { kind, command, args, capabilities });
        return;
      }
    });
    child.on("exit", (code) => {
      if (!settled) finish(new Error(`${command} exited ${code} before initialize`));
    });
    child.stdin.write(
      encode({
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: {
          processId: process.pid,
          capabilities: {},
          rootUri: null,
        },
      }),
    );
  });
}

function isDirectRun() {
  const entry = process.argv[1];
  if (!entry) return false;
  return import.meta.url === pathToFileURL(entry).href;
}

function commandFromArgv(argv) {
  const index = argv.indexOf("--command");
  if (index === -1) return null;
  return argv[index + 1] ?? null;
}

if (isDirectRun()) {
  const command = resolveGopls({
    env: process.env,
    home: process.env.HOME || process.env.USERPROFILE || "",
    command: commandFromArgv(process.argv),
  });
  if (!command) {
    console.error("gopls was not found. Install with: go install golang.org/x/tools/gopls@latest");
    process.exit(2);
  }
  probeGopls({ command })
    .then((result) => {
      console.log(
        `gopls native ${result.kind} spawn ok: ${result.command} args=${JSON.stringify(result.args)}`,
      );
      process.exit(0);
    })
    .catch((error) => {
      console.error(error.message);
      process.exit(1);
    });
}
