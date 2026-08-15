#!/usr/bin/env bash
# Cloud bootstrap for Claude Code cloud sessions (Claude Code on the web).
#
# Two callers run this script, both with CLAUDE_CODE_REMOTE=true:
#   1. The account environments' setup scripts, after clone and BEFORE the
#      session process launches. Claude Code builds its plugin/command/skill
#      registry at process start and never re-reads it, so this pre-launch call
#      is the only path that gets the repo's plugins loaded at turn one.
#   2. The SessionStart hook registered in .claude/settings.json (matcher:
#      startup|resume), which re-runs the same script on every session start
#      and resume as drift repair — the environment cache can be ~7 days
#      stale. Plugin installs made by a hook run go live at the next resume,
#      not in the session that ran the hook.
# Local sessions exit immediately via the CLAUDE_CODE_REMOTE guard — a local
# machine is presumed provisioned by its owner, and this script must never
# mutate one.
#
# Purpose: give a fresh cloud VM the same tool inventory as
# .github/workflows/ci.yml, so the repo's gates (scripts/run-plugin-tests.sh,
# scripts/validate-plugins.sh, hygiene linters) run instead of SKIPping.
# In-repo manifests stay the single source of truth where one exists:
#   Node               — .node-version (standards-synced)
#   ruff               — .github/requirements-ci.txt (hash-locked)
#   claude CLI / Biome — root package-lock.json (installed via npm ci)
# Tools with no in-repo manifest are pinned in the VERSION PINS block below.
#
# Idempotent by design: every step checks before it installs, so re-runs on
# session resume cost seconds. Required steps (Node, npm ci, hash-locked Python
# CI deps) fail the session start when they break; best-effort steps warn and
# continue, because a hygiene binary being briefly unreachable should not block
# a session. The cloud proxy only reliably allows GitHub release-asset downloads
# for repos attached to the session, so every GitHub-release install is
# best-effort.
set -euo pipefail

if [[ "${CLAUDE_CODE_REMOTE:-}" != "true" ]]; then
  echo "cloud-bootstrap: not a cloud session; nothing to do." >&2
  exit 0
fi

repo_root="${CLAUDE_PROJECT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
cd -- "$repo_root"

bin_dir="$HOME/.local/bin"
mkdir -p "$bin_dir"
export PATH="$bin_dir:$PATH"

# --- VERSION PINS (only for tools with no in-repo manifest) -----------------
# The proxy blocks the GitHub API and /releases/latest redirects; only direct
# /releases/download/ asset URLs resolve, hence hard pins. Each pinned asset
# also carries a SHA-256 recorded from a verified download of that exact
# version; a mismatch refuses the install. Bump pin and hash together — and
# authenticate before executing: on a bump, download the new asset, check it
# against the checksums file / signature / attestation the project publishes
# for that release BEFORE running the binary (a compromised artifact can lie
# about its version, and hashing it here would only legitimize it), then
# confirm the binary reports the pinned version and record
# `sha256sum <downloaded-asset>` here.
shellcheck_pin="v0.11.0" # .shellcheckrc targets 0.11.0+
shellcheck_sha="8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198"
actionlint_pin="1.7.12" # matches the pin documented in .github/actionlint.yaml
actionlint_sha="8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
typos_pin="v1.42.1"
typos_sha="fe1492d6c1079c328ef66de2094b7a3a4569987ec972ab56002c5db4746a8d1b"
ec_pin="v3.4.0" # editorconfig-checker 3.x, per .editorconfig-checker.json
ec_sha="feae0baaf8d55e51fd9b6c9e04497f2fb288b40034110fb9ac83fb1bf0b6011e"
gitleaks_pin="8.28.0"
gitleaks_sha="a65b5253807a68ac0cafa4414031fd740aeb55f54fb7e55f386acb52e6a840eb"
shfmt_pin="v3.12.0" # bash-format plugin hook; optional in CI by design
shfmt_sha="d9fbb2a9c33d13f47e7618cf362a914d029d02a6df124064fff04fd688a745ea"
markdownlint_pin="0.23.1"     # matches the .markdownlint-cli2.jsonc schema pin
check_jsonschema_pin="0.37.4" # pip/uv installs carry registry integrity checks

# --- Node (required) ---------------------------------------------------------
# CI resolves Node from .node-version; the cloud image ships 20/21/22 via nvm,
# so the pinned major is installed from nodejs.org on first run (~10s).
node_pin="$(tr -d '[:space:]' <.node-version)"
current_node="$(node --version 2>/dev/null || true)"
if [[ "$current_node" != "v$node_pin" ]]; then
  export NVM_DIR="${NVM_DIR:-/opt/nvm}"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    echo "cloud-bootstrap: error: Node $node_pin required and nvm not found at $NVM_DIR" >&2
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
# This process's env dies with the script; $CLAUDE_ENV_FILE is the sanctioned
# channel for shaping the session's Bash environment (per the cloud-environments
# doc). It is set only for the SessionStart-hook caller — the pre-launch caller
# has no session yet, so this block is skipped there.
# node_modules/.bin exposes the pinned claude CLI and Biome from npm ci.
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
  # shellcheck disable=SC2016 # $PATH must stay literal for the session to expand
  path_line="$(printf 'export PATH="%s:%s/node_modules/.bin:%s:$PATH"' \
    "$node_bin" "$repo_root" "$bin_dir")"
  # Resume re-runs must not stack duplicate lines: append only when absent.
  if ! grep -qxF "$path_line" "$CLAUDE_ENV_FILE" 2>/dev/null; then
    printf '%s\n' "$path_line" >>"$CLAUDE_ENV_FILE"
  fi
fi

# --- Root npm toolchain (required) --------------------------------------------
# Provides the pinned claude CLI and Biome that scripts/validate-plugins.sh and
# the biome-format contract tests expect. Skipped when node_modules is already
# in sync with package-lock.json, so resume-time re-runs are free.
if [[ ! -f node_modules/.package-lock.json || package-lock.json -nt node_modules/.package-lock.json ]]; then
  npm ci --no-audit --no-fund
fi

# --- Plugins (best effort) -----------------------------------------------------
# .claude/settings.json declares this repo as its own marketplace through a
# relative `directory` source and enables the full catalog. Cloud sessions do
# install plugins declared in project settings at session start, but only from a
# marketplace source that path can resolve; a checkout-relative `directory`
# source is documented as a development source, and sessions in fact arrive with
# an empty plugin registry — no plugin skill loaded and every `/plugin` command
# unknown. Registering the checkout by absolute path and installing the enabled
# set repairs the on-disk state while keeping the property the directory source
# exists for: a session exercises the plugin code on the current branch, not
# published main.
#
# Timing limit (docs/CLOUD-SESSIONS.md, "Plugins in sessions on this repo"):
# the plugin/command registry is read at process start, BEFORE a SessionStart
# hook runs, and is not re-read, so a hook run's installs are invisible to the
# session performing them. They serve the next process start — which on an
# ephemeral cloud VM means the environment's setup script must run this script
# at cache-build time for a session to ever start with plugins loaded.
#
# Never `claude plugin marketplace remove` here. That subcommand deletes the
# marketplace's entry from .claude/settings.json, so using it to force a
# re-add would silently mutate tracked repository config.
#
# Best effort by design: a plugin that fails to install costs that plugin's
# skills, not the session. Idempotent — installed plugins are skipped, so a
# resume re-run costs one `claude plugin list` call.
claude_bin="$repo_root/node_modules/.bin/claude"
marketplace_name="melodic-software"
if [[ -x "$claude_bin" ]] && command -v jq >/dev/null 2>&1; then
  if ! "$claude_bin" plugin marketplace list --json 2>/dev/null |
    jq -e --arg n "$marketplace_name" 'any(.[]; .name == $n)' >/dev/null; then
    "$claude_bin" plugin marketplace add "$repo_root" --scope user >/dev/null ||
      echo "cloud-bootstrap: warning: could not register the $marketplace_name marketplace" >&2
  fi

  # Enabled-and-not-yet-installed, computed from the tracked settings file so
  # this script can never drift from the catalog the repo actually enables.
  mapfile -t wanted < <(
    jq -r --arg n "$marketplace_name" \
      '.enabledPlugins // {} | to_entries[]
       | select(.value == true and (.key | endswith("@" + $n))) | .key' \
      .claude/settings.json 2>/dev/null
  )
  mapfile -t have < <("$claude_bin" plugin list --json 2>/dev/null | jq -r '.[].id' 2>/dev/null)

  # A directory-source install cache is keyed by the semver in plugin.json, not
  # by commit, so a later commit under the same version never replaces the
  # snapshot and `plugin update` false-greens on the version compare — see
  # "Same-version commit drift" in docs/MIGRATION-PLAYBOOK.md and #2061. On a
  # resume after the checkout advanced, a presence check alone would therefore
  # keep serving the skills and hooks of whatever commit installed first, which
  # defeats the reason this repo uses a directory source at all. Compare the SHA
  # recorded at install time against HEAD and refresh only the plugins whose own
  # directory actually changed between them, so the common resume stays cheap.
  #
  # Uncommitted edits to a plugin are out of scope here and stay that way: the
  # playbook's answer for that loop is `claude --plugin-dir ./plugins/<name>`,
  # which takes session precedence over the cached install.
  plugins_registry="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
  head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
  needs_refresh() {
    # needs_refresh <plugin-id> — true when the cached snapshot predates a
    # change to that plugin's directory in this checkout.
    local id="$1" name="${1%@*}" recorded
    [[ -n "$head_sha" && -f "$plugins_registry" ]] || return 1
    recorded="$(jq -r --arg id "$id" \
      '(.plugins[$id] // []) | map(select(.scope == "user")) | .[0].gitCommitSha // ""' \
      "$plugins_registry" 2>/dev/null)"
    [[ -n "$recorded" && "$recorded" != "$head_sha" ]] || return 1
    # A commit this clone doesn't have (shallow fetch, force-push): refresh
    # rather than guess that the snapshot is current.
    git cat-file -e "${recorded}^{commit}" 2>/dev/null || return 0
    ! git diff --quiet "$recorded" HEAD -- "plugins/$name" 2>/dev/null
  }

  installed=0
  refreshed=0
  failed=0
  for id in "${wanted[@]}"; do
    [[ -n "$id" ]] || continue
    if [[ " ${have[*]} " == *" $id "* ]]; then
      # shellcheck disable=SC2310  # the return status IS the verdict
      needs_refresh "$id" || continue
      # `uninstall` drops enabled state, so re-enable explicitly or the plugin
      # goes silently absent instead of silently stale.
      if "$claude_bin" plugin uninstall "$id" >/dev/null 2>&1 &&
        "$claude_bin" plugin install "$id" --scope user -y >/dev/null 2>&1 &&
        "$claude_bin" plugin enable "$id" --scope user >/dev/null 2>&1; then
        refreshed=$((refreshed + 1))
      else
        failed=$((failed + 1))
        echo "cloud-bootstrap: warning: plugin refresh failed: $id" >&2
      fi
      continue
    fi
    if "$claude_bin" plugin install "$id" --scope user -y >/dev/null 2>&1; then
      installed=$((installed + 1))
    else
      failed=$((failed + 1))
      echo "cloud-bootstrap: warning: plugin install failed: $id" >&2
    fi
  done
  echo "cloud-bootstrap: plugins ${#wanted[@]} enabled, $installed newly installed, $refreshed refreshed, $failed failed"
else
  echo "cloud-bootstrap: warning: claude CLI or jq unavailable; plugins will not load" >&2
fi

# --- Python CI deps (required) -------------------------------------------------
# The same hash-locked install CI's plugin-gate lane runs; a satisfied install is
# a fast no-op. --require-hashes is the integrity control that catches a resolved
# wheel whose digest is not in the lockfile — including a genuine supply-chain
# compromise — so a failure here stays fatal via `set -e`. Do not swallow stderr
# or fall back to an unpinned install: that would convert the one tampering
# signal into a warning easy to lose among bootstrap log lines.
#
# `.github/requirements-ci.txt` carries ABI-specific hashes for both the CI
# interpreter (cp314) and the cloud VM system Python (cp311; #2657 / #2654), so
# the locked install succeeds on either without an interpreter-mismatch skip.
# pip rather than uv: uv's PyPI fetches time out against this VM's egress proxy.
python3 -m pip install --user --quiet --only-binary=:all: --require-hashes \
  --requirement .github/requirements-ci.txt

# --- Hygiene binaries (best effort) --------------------------------------------
# CI installs these via hosted composite actions this VM can't reach; having
# them locally lets the agent run the same hygiene checks before pushing.
# Failures warn instead of blocking: each corresponding contract test SKIPs
# visibly when its tool is absent, and CI still enforces the real gate.
fetch_release_tool() {
  # fetch_release_tool <cmd-name> <asset-url> <asset-sha256> <path-inside-archive>
  # Pass "-" as <path-inside-archive> for a bare-binary asset (no archive).
  local name="$1" url="$2" sha="$3" member="$4" tmp
  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "cloud-bootstrap: warning: skipping $name (non-x86_64 VM)" >&2
    return 0
  fi
  tmp="$(mktemp -d)"
  local failed=0
  curl -fsSL -o "$tmp/asset" "$url" || failed=1
  if [[ "$failed" -eq 0 ]] && ! echo "$sha  $tmp/asset" | sha256sum --check --quiet --status; then
    echo "cloud-bootstrap: warning: $name checksum mismatch ($url); refusing to install" >&2
    failed=1
  fi
  if [[ "$failed" -eq 0 ]]; then
    case "$url" in
    *.tar.xz) tar -xJf "$tmp/asset" -C "$tmp" || failed=1 ;;
    *.tar.gz) tar -xzf "$tmp/asset" -C "$tmp" || failed=1 ;;
    *) member="asset" ;; # bare binary: install the download itself
    esac
  fi
  if [[ "$failed" -eq 0 && -f "$tmp/$member" ]]; then
    install -m 0755 "$tmp/$member" "$bin_dir/$name"
  else
    echo "cloud-bootstrap: warning: $name install failed ($url); its checks will SKIP" >&2
  fi
  rm -rf "$tmp"
  return 0
}

fetch_release_tool shellcheck \
  "https://github.com/koalaman/shellcheck/releases/download/${shellcheck_pin}/shellcheck-${shellcheck_pin}.linux.x86_64.tar.xz" \
  "$shellcheck_sha" "shellcheck-${shellcheck_pin}/shellcheck"
fetch_release_tool actionlint \
  "https://github.com/rhysd/actionlint/releases/download/v${actionlint_pin}/actionlint_${actionlint_pin}_linux_amd64.tar.gz" \
  "$actionlint_sha" "actionlint"
fetch_release_tool typos \
  "https://github.com/crate-ci/typos/releases/download/${typos_pin}/typos-${typos_pin}-x86_64-unknown-linux-musl.tar.gz" \
  "$typos_sha" "typos"
fetch_release_tool editorconfig-checker \
  "https://github.com/editorconfig-checker/editorconfig-checker/releases/download/${ec_pin}/ec-linux-amd64.tar.gz" \
  "$ec_sha" "bin/ec-linux-amd64"
fetch_release_tool gitleaks \
  "https://github.com/gitleaks/gitleaks/releases/download/v${gitleaks_pin}/gitleaks_${gitleaks_pin}_linux_x64.tar.gz" \
  "$gitleaks_sha" "gitleaks"
# shfmt ships as a bare binary (no archive); enables the bash-format plugin's
# format pass (its lint pass uses shellcheck above).
fetch_release_tool shfmt \
  "https://github.com/mvdan/sh/releases/download/${shfmt_pin}/shfmt_${shfmt_pin}_linux_amd64" \
  "$shfmt_sha" "-"

# The npm and pip/uv installs below carry no committed hash: both registries
# verify package integrity against registry metadata (npm `_integrity`
# sha512, PyPI digests), a weaker trust anchor than the committed SHA-256s
# above but an accepted one — npm -g has no --require-hashes equivalent.
if ! command -v markdownlint-cli2 >/dev/null 2>&1; then
  npm install -g --no-audit --no-fund "markdownlint-cli2@${markdownlint_pin}" ||
    echo "cloud-bootstrap: warning: markdownlint-cli2 install failed" >&2
fi

if ! command -v check-jsonschema >/dev/null 2>&1; then
  if command -v uv >/dev/null 2>&1; then
    uv tool install --quiet "check-jsonschema==${check_jsonschema_pin}" ||
      echo "cloud-bootstrap: warning: check-jsonschema install failed" >&2
  else
    python3 -m pip install --user --quiet "check-jsonschema==${check_jsonschema_pin}" ||
      echo "cloud-bootstrap: warning: check-jsonschema install failed" >&2
  fi
fi

# --- Git history (best effort) --------------------------------------------------
# Several CI lanes (sync/parity/portability checks) diff against origin/<base>;
# CI checks out with fetch-depth: 0. A shallow cloud clone breaks base-ref
# resolution, so deepen it and make sure origin/main resolves.
git_dir="$(git rev-parse --git-dir)"
if [[ -f "$git_dir/shallow" ]]; then
  git fetch --quiet --unshallow ||
    echo "cloud-bootstrap: warning: could not unshallow; base-ref diffs may fail" >&2
fi
# Explicit destination refspec: in a single-branch clone a bare `fetch origin
# main` only writes FETCH_HEAD and never creates refs/remotes/origin/main.
git fetch --quiet origin "+main:refs/remotes/origin/main" ||
  echo "cloud-bootstrap: warning: could not fetch origin/main" >&2

# --- Report --------------------------------------------------------------------
report_tool() {
  # report_tool <cmd-name> <version-args...>
  local name="$1"
  shift
  if command -v "$name" >/dev/null 2>&1; then
    echo "cloud-bootstrap: $name $("$name" "$@" 2>/dev/null | head -1)"
  else
    echo "cloud-bootstrap: $name ABSENT (its checks will SKIP)"
  fi
}
echo "cloud-bootstrap: bootstrap complete in $repo_root"
report_tool node --version
report_tool ruff --version
report_tool shellcheck --version
report_tool actionlint --version
report_tool typos --version
report_tool editorconfig-checker --version
report_tool gitleaks version
report_tool shfmt --version
report_tool markdownlint-cli2 --help
report_tool check-jsonschema --version
report_tool jq --version
exit 0
