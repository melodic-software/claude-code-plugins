#!/usr/bin/env bash
set -euo pipefail
git init -q
git symbolic-ref HEAD refs/heads/main
printf '%s\n' '{' '  "compilerOptions": { "strict": true, "noEmit": true },' '  "include": ["src"]' '}' >tsconfig.json
mkdir src
printf '%s\n' 'export function add(a: number, b: number): number {' '  return a + b;' '}' >src/math.ts
git add tsconfig.json src/math.ts
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
printf '%s\n' \
  'export function parse(raw: string): any {' \
  '  const data: any = JSON.parse(raw);' \
  '  const id: number = data.id;' \
  '  return { id, name: data.name as string };' \
  '}' >src/parse.ts
printf '%s\n' \
  'from typing import Any' \
  '' \
  '' \
  'def load(raw: Any) -> dict:' \
  '    value: Any = raw.get("value")' \
  '    count: int = len(raw)' \
  '    return {"value": value, "count": count}' >src/loader.py
