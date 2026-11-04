#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p src
for i in 1 2 3 4 5; do
  printf 'export const RATE_LIMIT = %s;\n' "$((i * 10))" >src/limits.ts
  printf 'import { RATE_LIMIT } from "./limits";\nexport const check = (n: number) => n <= RATE_LIMIT; // v%s\n' "$i" >src/throttle.ts
  git add . && git commit -q -m "feat: raise the rate limit to $((i * 10))"
  printf 'export const greet = (n: string) => "hi " + n + " %s";\n' "$i" >src/greet.ts
  git add . && git commit -q -m "chore: greet revision $i"
done
