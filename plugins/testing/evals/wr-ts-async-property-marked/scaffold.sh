#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main src package.json tsconfig.json
mkdir -p src
cat >package.json <<'EOF'
{
  "name": "records",
  "version": "0.1.0",
  "type": "module",
  "scripts": { "test": "vitest run" },
  "devDependencies": { "fast-check": "^4.0.0", "typescript": "^5.6.0", "vitest": "^3.0.0" }
}
EOF
cat >tsconfig.json <<'EOF'
{ "compilerOptions": { "target": "ES2022", "module": "ESNext", "moduleResolution": "Bundler", "strict": true } }
EOF
cat >src/codec.ts <<'EOF'
export interface Record {
  id: string;
  tags: string[];
  score: number;
}

// Encodes a record for the storage queue, which only accepts base64 text.
export async function encodeRecord(record: Record): Promise<string> {
  const json = JSON.stringify({ id: record.id, tags: record.tags, score: record.score });
  return Buffer.from(json, 'utf8').toString('base64');
}

// Reads back what encodeRecord wrote.
export async function decodeRecord(text: string): Promise<Record> {
  const parsed = JSON.parse(Buffer.from(text, 'base64').toString('utf8'));
  return { id: parsed.id, tags: parsed.tags, score: parsed.score };
}
EOF
g add -A
g commit -q -m "record codec"
