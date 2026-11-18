#!/usr/bin/env bash
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p src/api
cat >src/api/orders.ts <<'EOF'
export const createOrder = (log: (line: string) => void, body: unknown) => {
  log("create order: " + JSON.stringify(body));
};
EOF
git add . && git commit -q -m "feat: add the create order endpoint"
cat >src/api/orders.ts <<'EOF'
export const createOrder = (log: (line: string) => void, body: { id: string }) => {
  log("create order: " + body.id);
};
EOF
git add . && git commit -q -m "fix: the create order log line printed the whole request body"
