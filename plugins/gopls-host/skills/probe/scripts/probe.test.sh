#!/usr/bin/env bash
# PATH/GOBIN classification plus hover, definition, and references.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if grep -nE 'shell:[[:space:]]*true|cmd\.exe' "$SCRIPT_DIR/"*.mjs; then
  printf 'gopls smoke must not set shell true or call cmd.exe\n' >&2
  exit 1
fi

node --test "$SCRIPT_DIR/gopls-smoke.test.mjs"

probe="$(node "$SCRIPT_DIR/gopls-smoke.mjs" --probe || true)"
binary="$(printf '%s\n' "$probe" | node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{const j=JSON.parse(s);process.stdout.write(j.binary||"")})')"
if [[ -z "$binary" ]]; then
  printf 'gopls-smoke: no native gopls installed; live hover/definition/references skipped\n'
  exit 0
fi

node "$SCRIPT_DIR/gopls-smoke.mjs" --lsp >/tmp/gopls-lsp-smoke.json
node -e 'const j=require("node:fs").readFileSync("/tmp/gopls-lsp-smoke.json","utf8"); const o=JSON.parse(j); if(!o.lsp||o.lsp.ok!==true||o.shell!==false){console.error(j); process.exit(1)} console.log("live lsp ok binary="+o.binary+" onPath="+o.onPath+" installDir="+o.installDir)'
