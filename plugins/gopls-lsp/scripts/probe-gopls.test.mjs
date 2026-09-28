#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import {
  classifyExecutable,
  isNativeKind,
  probeGopls,
} from "./probe-gopls.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const pluginRoot = dirname(here);
let passed = 0;
let failed = 0;

function ok(name) {
  console.log(`ok: ${name}`);
  passed += 1;
}

function fail(name, detail) {
  console.error(`FAIL: ${name}${detail ? ` - ${detail}` : ""}`);
  failed += 1;
}

function check(name, condition, detail) {
  if (condition) ok(name);
  else fail(name, detail);
}

const lsp = JSON.parse(readFileSync(join(pluginRoot, ".lsp.json"), "utf8"));
const server = lsp.gopls;
check("lsp command is gopls", server?.command === "gopls", server?.command);
check("lsp does not wrap gopls in a shell string", !server?.args || Array.isArray(server.args));
check("lsp maps .go to go", server?.extensionToLanguage?.[".go"] === "go");
check(
  "lsp command is not a cmd shim",
  !String(server?.command ?? "").toLowerCase().endsWith(".cmd"),
);

check("elf magic is native", isNativeKind(classifyExecutable(Buffer.from([0x7f, 0x45, 0x4c, 0x46, 0, 0, 0, 0]))));
check("pe magic is native", isNativeKind(classifyExecutable(Buffer.from([0x4d, 0x5a, 0x90, 0x00]))));
const macho = Buffer.alloc(4);
macho.writeUInt32BE(0xfeedfacf, 0);
check("mach-o magic is native", isNativeKind(classifyExecutable(macho)));
check("shebang is not native", classifyExecutable(Buffer.from("#!/bin/sh\n")) === "script");
check("cmd header is not native", classifyExecutable(Buffer.from("@ECHO off\r\n")) === "script");

const go = spawnSync("go", ["version"], { encoding: "utf8" });
if (go.status !== 0) {
  console.log("SKIP: go toolchain is not on PATH, native spawn fixture not built");
} else {
  const temp = mkdtempSync(join(tmpdir(), "gopls-probe-"));
  try {
    writeFileSync(join(temp, "go.mod"), "module stub\n\ngo 1.22\n");
    writeFileSync(
      join(temp, "main.go"),
      `package main

import (
  "bufio"
  "fmt"
  "io"
  "os"
  "strconv"
  "strings"
)

func main() {
  in := bufio.NewReader(os.Stdin)
  length := -1
  for {
    line, err := in.ReadString('\\n')
    if err != nil {
      os.Exit(0)
    }
    line = strings.TrimRight(line, "\\r\\n")
    if line == "" {
      break
    }
    if strings.HasPrefix(strings.ToLower(line), "content-length:") {
      length, _ = strconv.Atoi(strings.TrimSpace(line[len("content-length:"):]))
    }
  }
  body := make([]byte, length)
  if _, err := io.ReadFull(in, body); err != nil {
    os.Exit(1)
  }
  response := "{\\"jsonrpc\\":\\"2.0\\",\\"id\\":1,\\"result\\":{\\"capabilities\\":{\\"hoverProvider\\":true}}}"
  fmt.Fprintf(os.Stdout, "Content-Length: %d\\r\\n\\r\\n%s", len(response), response)
}
`,
    );
    const binary = join(temp, "stub");
    const built = spawnSync("go", ["build", "-o", binary, "."], { cwd: temp, encoding: "utf8" });
    if (built.status !== 0) {
      fail("native stub builds", built.stderr);
    } else {
      const result = await probeGopls({ command: binary, timeoutMs: 10000 });
      check("native stub classifies as a native executable", isNativeKind(result.kind), result.kind);
      check(
        "shell-less spawn of a native executable answers initialize",
        result.capabilities.hoverProvider === true,
        JSON.stringify(result.capabilities),
      );
    }
  } catch (error) {
    fail("shell-less spawn of a native executable answers initialize", error.message);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
}

if (failed > 0) {
  console.error(`${failed} failed, ${passed} passed`);
  process.exit(1);
}
console.log(`${passed} passed`);
