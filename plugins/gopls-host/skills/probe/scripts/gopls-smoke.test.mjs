import { chmodSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { planGopls, runLspSmoke } from "./gopls-smoke.mjs";

const MZ = Buffer.from([0x4d, 0x5a, 0x90, 0x00]);
const ELF = Buffer.from([0x7f, 0x45, 0x4c, 0x46]);

function winFs(entries) {
  const files = new Map();
  for (const [file, head] of entries) {
    files.set(path.win32.normalize(file).toLowerCase(), head);
  }
  return {
    exists(file) {
      return files.has(path.win32.normalize(file).toLowerCase());
    },
    readHead(file) {
      return files.get(path.win32.normalize(file).toLowerCase()) ?? Buffer.alloc(0);
    },
  };
}

test("windows gopls.exe on GOBIN is blocked until that directory is on PATH", () => {
  const gobin = "C:\\Users\\me\\go\\bin";
  const exe = path.win32.join(gobin, "gopls.exe");
  const fs = winFs([
    [exe, MZ],
    [path.win32.join(gobin, "gopls.cmd"), Buffer.from("@echo off\r\n")],
  ]);
  const plan = planGopls({
    platform: "win32",
    env: { PATH: "C:\\Windows\\System32", USERPROFILE: "C:\\Users\\me" },
    goEnv: { GOBIN: gobin, GOPATH: "C:\\Users\\me\\go" },
    exists: fs.exists,
    readHead: fs.readHead,
  });
  assert.equal(plan.status, "blocked");
  assert.equal(plan.shell, false);
  assert.equal(plan.command, null);
  assert.deepEqual(plan.args, []);
  assert.equal(plan.binary, exe);
  assert.equal(plan.kind, "pe");
  assert.equal(plan.onPath, false);
  assert.equal(plan.installDir, gobin);
  assert.equal(plan.installOnPath, false);
  assert.match(plan.reason, /not on PATH/);
  assert.ok(plan.rejected.some((file) => file.toLowerCase().endsWith(".cmd")));
});

test("windows PATH gopls.exe is the serve command and a .cmd is not", () => {
  const gobin = "C:\\Users\\me\\sdk\\bin";
  const exe = path.win32.join(gobin, "gopls.exe");
  const fs = winFs([
    [exe, MZ],
    [path.win32.join(gobin, "gopls.cmd"), Buffer.from("@echo off\r\n")],
  ]);
  const plan = planGopls({
    platform: "win32",
    env: { PATH: gobin, USERPROFILE: "C:\\Users\\me" },
    goEnv: { GOBIN: "", GOPATH: "" },
    exists: fs.exists,
    readHead: fs.readHead,
  });
  assert.equal(plan.status, "ready");
  assert.equal(plan.shell, false);
  assert.equal(plan.command, exe);
  assert.deepEqual(plan.args, ["serve"]);
  assert.equal(plan.kind, "pe");
  assert.ok(!String(plan.command).toLowerCase().endsWith(".cmd"));
});

test("GOBIN wins over GOPATH/bin", () => {
  const plan = planGopls({
    platform: "linux",
    env: { PATH: "", HOME: "/home/me" },
    goEnv: { GOBIN: "/opt/gobin", GOPATH: "/home/me/gopath" },
    exists: () => false,
    readHead: () => Buffer.alloc(0),
  });
  assert.equal(plan.installDir, "/opt/gobin");
  assert.equal(plan.shell, false);
});

test("empty GOBIN uses the first GOPATH bin directory", () => {
  const bin = path.posix.join("/work/gopath", "bin");
  const binary = path.posix.join(bin, "gopls");
  const plan = planGopls({
    platform: "linux",
    env: { PATH: `/usr/bin:${bin}`, HOME: "/home/me" },
    goEnv: { GOBIN: "", GOPATH: "/work/gopath:/other" },
    exists: (file) => file === binary,
    readHead: (file) => (file === binary ? ELF : Buffer.alloc(0)),
  });
  assert.equal(plan.installDir, bin);
  assert.equal(plan.status, "ready");
  assert.equal(plan.command, binary);
  assert.equal(plan.kind, "elf");
  assert.equal(plan.installOnPath, true);
  assert.deepEqual(plan.args, ["serve"]);
});

test("lsp smoke talks hover, definition, and references to a fake server", async () => {
  const root = mkdtempSync(path.join(tmpdir(), "fake-gopls-"));
  const fake = path.join(root, "gopls");
  writeFileSync(
    fake,
    `#!/usr/bin/env node
import { Buffer } from "node:buffer";
let buf = Buffer.alloc(0);
function send(message) {
  const body = Buffer.from(JSON.stringify(message));
  process.stdout.write(\`Content-Length: \${body.length}\\r\\n\\r\\n\`);
  process.stdout.write(body);
}
process.stdin.on("data", (chunk) => {
  buf = Buffer.concat([buf, chunk]);
  for (;;) {
    const headerEnd = buf.indexOf("\\r\\n\\r\\n");
    if (headerEnd < 0) return;
    const header = buf.slice(0, headerEnd).toString("utf8");
    const match = /Content-Length: (\\d+)/i.exec(header);
    if (!match) throw new Error(header);
    const length = Number(match[1]);
    const start = headerEnd + 4;
    if (buf.length < start + length) return;
    const message = JSON.parse(buf.slice(start, start + length).toString("utf8"));
    buf = buf.slice(start + length);
    if (message.method === "initialize") {
      send({ jsonrpc: "2.0", id: message.id, result: { capabilities: {} } });
    } else if (message.method === "textDocument/hover") {
      send({ jsonrpc: "2.0", id: message.id, result: { contents: { kind: "plaintext", value: "func Target() int" } } });
    } else if (message.method === "textDocument/definition") {
      send({ jsonrpc: "2.0", id: message.id, result: [{ uri: "file:///p.go", range: { start: { line: 2, character: 5 }, end: { line: 2, character: 11 } } }] });
    } else if (message.method === "textDocument/references") {
      send({ jsonrpc: "2.0", id: message.id, result: [{ uri: "file:///p.go" }, { uri: "file:///p.go" }] });
    } else if (message.method === "shutdown") {
      send({ jsonrpc: "2.0", id: message.id, result: null });
    } else if (message.method === "exit") {
      process.exit(0);
    }
  }
});
`,
  );
  chmodSync(fake, 0o755);
  const smoked = await runLspSmoke(fake, { settleMs: 0, timeoutMs: 5000 });
  assert.equal(smoked.error, null);
  assert.equal(smoked.hover, true);
  assert.equal(smoked.definition, true);
  assert.equal(smoked.references, true);
  assert.equal(smoked.ok, true);
});
