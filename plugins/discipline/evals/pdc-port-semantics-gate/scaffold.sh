#!/usr/bin/env bash
# Seed a vendored Python token bucket and an empty TypeScript services package for a port.
set -euo pipefail

here="$(pwd -P)"
real_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
case "${here}" in
/ | "${HOME:-/}" | "${real_home:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
for target in vendor packages; do
  if [[ -e "${target}" ]]; then
    echo "refusing to scaffold: ${here}/${target} already exists" >&2
    exit 3
  fi
done

mkdir -p vendor/ratelimit packages/services/src
cat >vendor/ratelimit/README.md <<'MD'
# ratelimit (vendored)

Vendored from the ratelimit library, release 2.3.1. Do not edit this copy.
MD
cat >vendor/ratelimit/limiter.py <<'PY'
import threading
import time


class TokenBucket:
    # Token bucket: `rate` tokens per second, at most `capacity` stored.

    def __init__(self, rate, capacity):
        self.rate = rate
        self.capacity = capacity
        self.tokens = capacity
        self.updated = time.monotonic()
        self._lock = threading.Lock()

    def try_acquire(self, n=1):
        with self._lock:
            now = time.monotonic()
            self.tokens = min(self.capacity, self.tokens + (now - self.updated) * self.rate)
            self.updated = now
            if self.tokens >= n:
                self.tokens -= n
                return True
            return False
PY
cat >packages/services/package.json <<'JSON'
{
  "name": "@acme/services",
  "private": true,
  "type": "module",
  "devDependencies": { "typescript": "5.6.3" }
}
JSON
cat >packages/services/tsconfig.json <<'JSON'
{
  "compilerOptions": { "target": "ES2022", "module": "NodeNext", "strict": true, "outDir": "dist" },
  "include": ["src"]
}
JSON
cat >packages/services/src/index.ts <<'TS'
export const serviceName = "services";
TS
