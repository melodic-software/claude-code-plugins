#!/usr/bin/env bash
# SessionStart bootstrap for Claude Code cloud sessions (Claude Code on the web).
#
# Registered in .claude/settings.json (matcher: startup|resume); runs before the
# agent takes its first turn. Local sessions exit immediately via the
# CLAUDE_CODE_REMOTE guard — a local machine is presumed provisioned by its
# owner, and this script must never mutate one.
#
# Purpose: give a fresh cloud VM the same tool inventory as
# .github/workflows/ci.yml, so the repo's gates (scripts/run-plugin-tests.sh,
# scripts/validate-plugins.sh, hygiene linters) run instead of SKIPping.
# In-repo manifests stay the single source of truth where one exists:
#   Node               — .node-version (standards-synced)
#   ruff               — .github/requirements-ci.txt (hash-locked, standards-synced)
#   claude CLI / Biome — root package-lock.json (installed via npm ci)
# Tools with no in-repo manifest are pinned in the VERSION PINS block below.
#
# Idempotent by design: every step checks before it installs, so re-runs on
# session resume cost seconds. Required steps (Node, npm ci, ruff) fail the
# session start when they break; best-effort steps warn and continue, because
# a hygiene binary being briefly unreachable should not block a session. The
# cloud proxy only reliably allows GitHub release-asset downloads for repos
# attached to the session, so every GitHub-release install is best-effort.
set -euo pipefail

if [[ "${CLAUDE_CODE_REMOTE:-}" != "true" ]]; then
  echo "session-start: not a cloud session; nothing to do." >&2
  exit 0
fi

repo_root="${CLAUDE_PROJECT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd -- "$repo_root"

bin_dir="$HOME/.local/bin"
mkdir -p "$bin_dir"
export PATH="$bin_dir:$PATH"

# --- VERSION PINS (only for tools with no in-repo manifest) -----------------
# The proxy blocks the GitHub API and /releases/latest redirects; only direct
# /releases/download/ asset URLs resolve, hence hard pins. Bump deliberately.
shellcheck_pin="v0.11.0" # .shellcheckrc targets 0.11.0+
actionlint_pin="1.7.12"  # matches the pin documented in .github/actionlint.yaml
typos_pin="v1.42.1"
ec_pin="v3.4.0" # editorconfig-checker 3.x, per .editorconfig-checker.json
gitleaks_pin="8.28.0"
markdownlint_pin="0.23.1" # matches the .markdownlint-cli2.jsonc schema pin

# --- Node (required) ---------------------------------------------------------
# CI resolves Node from .node-version; the cloud image ships 20/21/22 via nvm,
# so the pinned major is installed from nodejs.org on first run (~10s).
node_pin="$(tr -d '[:space:]' <.node-version)"
current_node="$(node --version 2>/dev/null || true)"
if [[ "$current_node" != "v$node_pin" ]]; then
  export NVM_DIR="${NVM_DIR:-/opt/nvm}"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    echo "session-start: error: Node $node_pin required and nvm not found at $NVM_DIR" >&2
    exit 1
  fi
  set +u # nvm.sh reads intentionally-unset variables
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
  nvm install "$node_pin" >/dev/null
  nvm alias default "$node_pin" >/dev/null
  set -u
fi
node_bin="$(dirname -- "$(command -v node)")"

# --- Session PATH (required) -------------------------------------------------
# Hook-process env dies with this script; $CLAUDE_ENV_FILE is the sanctioned
# channel for shaping the session's Bash environment (per the cloud-environments
# doc). node_modules/.bin exposes the pinned claude CLI and Biome from npm ci.
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
  # shellcheck disable=SC2016 # $PATH must stay literal for the session to expand
  printf 'export PATH="%s:%s/node_modules/.bin:%s:$PATH"\n' \
    "$node_bin" "$repo_root" "$bin_dir" >>"$CLAUDE_ENV_FILE"
fi

# --- Root npm toolchain (required) --------------------------------------------
# Provides the pinned claude CLI and Biome that scripts/validate-plugins.sh and
# the biome-format contract tests expect. Skipped when node_modules is already
# in sync with package-lock.json, so resume-time re-runs are free.
if [[ ! -f node_modules/.package-lock.json || package-lock.json -nt node_modules/.package-lock.json ]]; then
  npm ci --no-audit --no-fund
fi

# --- ruff (required) -----------------------------------------------------------
# The same hash-locked install CI's plugin-gate lane runs; a satisfied install
# is a fast no-op. Wheel hashes in the requirements file are Linux-x64 only,
# which matches the cloud VM.
python3 -m pip install --user --quiet --only-binary=:all: --require-hashes \
  --requirement .github/requirements-ci.txt

# --- Hygiene binaries (best effort) --------------------------------------------
# CI installs these via hosted composite actions this VM can't reach; having
# them locally lets the agent run the same hygiene checks before pushing.
# Failures warn instead of blocking: each corresponding contract test SKIPs
# visibly when its tool is absent, and CI still enforces the real gate.
fetch_release_tool() {
  # fetch_release_tool <cmd-name> <asset-url> <path-inside-archive>
  local name="$1" url="$2" member="$3" tmp
  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "session-start: warning: skipping $name (non-x86_64 VM)" >&2
    return 0
  fi
  tmp="$(mktemp -d)"
  local ok=1
  case "$url" in
    *.tar.xz) curl -fsSL "$url" | tar -xJ -C "$tmp" || ok=0 ;;
    *) curl -fsSL "$url" | tar -xz -C "$tmp" || ok=0 ;;
  esac
  if [[ "$ok" -eq 1 && -f "$tmp/$member" ]]; then
    install -m 0755 "$tmp/$member" "$bin_dir/$name"
  else
    echo "session-start: warning: $name install failed ($url); its checks will SKIP" >&2
  fi
  rm -rf "$tmp"
  return 0
}

fetch_release_tool shellcheck \
  "https://github.com/koalaman/shellcheck/releases/download/${shellcheck_pin}/shellcheck-${shellcheck_pin}.linux.x86_64.tar.xz" \
  "shellcheck-${shellcheck_pin}/shellcheck"
fetch_release_tool actionlint \
  "https://github.com/rhysd/actionlint/releases/download/v${actionlint_pin}/actionlint_${actionlint_pin}_linux_amd64.tar.gz" \
  "actionlint"
fetch_release_tool typos \
  "https://github.com/crate-ci/typos/releases/download/${typos_pin}/typos-${typos_pin}-x86_64-unknown-linux-musl.tar.gz" \
  "typos"
fetch_release_tool editorconfig-checker \
  "https://github.com/editorconfig-checker/editorconfig-checker/releases/download/${ec_pin}/ec-linux-amd64.tar.gz" \
  "bin/ec-linux-amd64"
fetch_release_tool gitleaks \
  "https://github.com/gitleaks/gitleaks/releases/download/v${gitleaks_pin}/gitleaks_${gitleaks_pin}_linux_x64.tar.gz" \
  "gitleaks"

if ! command -v markdownlint-cli2 >/dev/null 2>&1; then
  npm install -g --no-audit --no-fund "markdownlint-cli2@${markdownlint_pin}" ||
    echo "session-start: warning: markdownlint-cli2 install failed" >&2
fi

if ! command -v check-jsonschema >/dev/null 2>&1; then
  if command -v uv >/dev/null 2>&1; then
    uv tool install --quiet check-jsonschema ||
      echo "session-start: warning: check-jsonschema install failed" >&2
  else
    python3 -m pip install --user --quiet check-jsonschema ||
      echo "session-start: warning: check-jsonschema install failed" >&2
  fi
fi

# --- Git history (best effort) --------------------------------------------------
# Several CI lanes (sync/parity/portability checks) diff against origin/<base>;
# CI checks out with fetch-depth: 0. A shallow cloud clone breaks base-ref
# resolution, so deepen it and make sure origin/main resolves.
git_dir="$(git rev-parse --git-dir)"
if [[ -f "$git_dir/shallow" ]]; then
  git fetch --quiet --unshallow ||
    echo "session-start: warning: could not unshallow; base-ref diffs may fail" >&2
fi
git fetch --quiet origin main ||
  echo "session-start: warning: could not fetch origin/main" >&2

# --- Report --------------------------------------------------------------------
report_tool() {
  # report_tool <cmd-name> <version-args...>
  local name="$1"
  shift
  if command -v "$name" >/dev/null 2>&1; then
    echo "session-start: $name $("$name" "$@" 2>/dev/null | head -1)"
  else
    echo "session-start: $name ABSENT (its checks will SKIP)"
  fi
}
echo "session-start: bootstrap complete in $repo_root"
report_tool node --version
report_tool ruff --version
report_tool shellcheck --version
report_tool actionlint --version
report_tool typos --version
report_tool editorconfig-checker --version
report_tool gitleaks version
report_tool markdownlint-cli2 --help
report_tool check-jsonschema --version
report_tool jq --version
exit 0
