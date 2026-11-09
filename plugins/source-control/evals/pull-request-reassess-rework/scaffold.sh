#!/usr/bin/env bash
# PR 512 adds getUserWithRetry, which calls request(); main renamed request() to send() through PR 588,
# in lines that merge cleanly with the head's, so nothing but reading the code shows the head is obsolete.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
cat >src/client.ts <<'EOF'
export function request(url) {
  return fetch(url);
}

export function getUser(id) {
  return request('/users/' + id);
}

// Helpers below.
EOF
git add src
git commit -q -m "chore: seed"
git checkout -q -b fix/user-retry
cat >>src/client.ts <<'EOF'

export async function getUserWithRetry(id) {
  const first = await request('/users/' + id);
  return first.status === 503 ? request('/users/' + id) : first;
}
EOF
git commit -q -am "fix: retry getUser on HTTP 503"
git checkout -q main
cat >src/client.ts <<'EOF'
export function send(url) {
  return fetch(url);
}

export function getUser(id) {
  return send('/users/' + id);
}

// Helpers below.
EOF
git commit -q -am "refactor: rename request to send (#588)"
landed=$(git rev-parse HEAD)
bash "$here/../fixtures/gh-forge/install.sh" 512 fix/user-retry main "fix: retry getUser on HTTP 503" --open
bash "$here/../fixtures/gh-forge/reassess-state.sh" 512 \
  --merged 588 "refactor: rename request to send" "Renames the client's request function to send; every caller moves with it." "$landed" \
  --issue 90 "Retry getUser on HTTP 503" "getUser fails at once on an HTTP 503. It should retry." \
  --closes 90 --body $'Closes #90\n\nAdds getUserWithRetry.'
