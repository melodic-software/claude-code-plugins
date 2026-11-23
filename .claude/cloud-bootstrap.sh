#!/usr/bin/env bash
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

shellcheck_pin="v0.11.0"
shellcheck_sha="8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198"
actionlint_pin="1.17.0" # the kjanat/actionlint fork CI runs (ci-workflows actionlint/action.yml `version`); its numbers overlap upstream's, so the SHA-256 is the anchor
actionlint_sha="620abd485a12b6ab1125b844a876414e1d5bd2af8a3125b27f82b01d0d9d6e5a"
typos_pin="v1.42.1"
typos_sha="fe1492d6c1079c328ef66de2094b7a3a4569987ec972ab56002c5db4746a8d1b"
ec_pin="v3.4.0"
ec_sha="feae0baaf8d55e51fd9b6c9e04497f2fb288b40034110fb9ac83fb1bf0b6011e"
gitleaks_pin="8.28.0"
gitleaks_sha="a65b5253807a68ac0cafa4414031fd740aeb55f54fb7e55f386acb52e6a840eb"
shfmt_pin="v3.14.1"
shfmt_sha="76e77641faa025814b77f153b29796b8e6fa2fca03e0c76a691608b86c7ea7bf"
# markdownlint-cli2: root package-lock.json (npm ci) — never npm -g into the
# nvm prefix; hook processes do not inherit that PATH segment (#2739 / #2748).
check_jsonschema_pin="0.37.4"

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

if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
  # shellcheck disable=SC2016 # $PATH must stay literal for the session to expand
  path_line="$(printf 'export PATH="%s:%s/node_modules/.bin:%s:$PATH"' \
    "$node_bin" "$repo_root" "$bin_dir")"
  if ! grep -qxF "$path_line" "$CLAUDE_ENV_FILE" 2>/dev/null; then
    printf '%s\n' "$path_line" >>"$CLAUDE_ENV_FILE"
  fi
fi

if [[ ! -f node_modules/.package-lock.json || package-lock.json -nt node_modules/.package-lock.json ]]; then
  npm ci --no-audit --no-fund
fi

claude_bin="$repo_root/node_modules/.bin/claude"
marketplace_name="melodic-software"
fleet_list="${CLOUD_BOOTSTRAP_FLEET_LIST:-/opt/melodic-fleet-plugins.json}"
plugin_stage=0
if [[ ! -x "$claude_bin" ]] || ! command -v jq >/dev/null 2>&1; then
  echo "cloud-bootstrap: warning: claude CLI or jq unavailable; plugins will not load" >&2
elif [[ ! -f "$fleet_list" ]]; then
  echo 'cloud-bootstrap: no fleet plugin list in this snapshot; plugin install skipped' >&2
elif ! jq -e 'type == "object" and ((.enabledPlugins // {}) | type == "object")' \
  "$fleet_list" >/dev/null 2>&1; then
  echo "cloud-bootstrap: fleet plugin list $fleet_list is not a settings-shaped object; plugin install skipped" >&2
else
  plugin_stage=1
fi
if ((plugin_stage)); then
  if ! "$claude_bin" plugin marketplace list --json 2>/dev/null |
    jq -e --arg n "$marketplace_name" 'any(.[]; .name == $n)' >/dev/null; then
    "$claude_bin" plugin marketplace add "$repo_root" --scope user >/dev/null ||
      echo "cloud-bootstrap: warning: could not register the $marketplace_name marketplace" >&2
  fi

  source_repo="$repo_root"
  marketplace_entry="$("$claude_bin" plugin marketplace list --json 2>/dev/null |
    jq -c --arg n "$marketplace_name" 'first(.[]? | select(.name == $n)) // {}' 2>/dev/null || true)"
  [[ -n "$marketplace_entry" ]] || marketplace_entry='{}'
  marketplace_location="$(jq -r '.installLocation // ""' <<<"$marketplace_entry" 2>/dev/null | tr -d '\r')"
  if [[ -n "$marketplace_location" ]] &&
    git -C "$marketplace_location" rev-parse --verify HEAD >/dev/null 2>&1 &&
    [[ "$(cd -P -- "$marketplace_location" && pwd)" != "$(cd -P -- "$repo_root" && pwd)" ]]; then
    if ! "$claude_bin" plugin marketplace update "$marketplace_name" >/dev/null 2>&1; then
      echo "cloud-bootstrap: warning: could not bring the $marketplace_name marketplace clone current (\`plugin marketplace update\` failed); verifying against the clone as it stands" >&2
    fi
    source_repo="$marketplace_location"
    marketplace_source="$(jq -r 'if (.source | type) == "object" then (.source.repo // .source.source // "an unknown source") else (.source // "an unknown source") end' <<<"$marketplace_entry" 2>/dev/null | tr -d '\r')"
    echo "cloud-bootstrap: warning: marketplace $marketplace_name is registered from ${marketplace_source:-an unknown source} at $marketplace_location, not this checkout; plugins serve that clone at $(git -C "$source_repo" rev-parse --short HEAD 2>/dev/null), not $(git branch --show-current 2>/dev/null || echo detached) at $(git rev-parse --short HEAD 2>/dev/null)" >&2
  fi

  mapfile -t wanted < <(
    jq -r --arg n "$marketplace_name" --slurpfile f "$fleet_list" \
      '(($f[0].enabledPlugins // {}) + (.enabledPlugins // {})) | to_entries[]
       | select(.value == true and (.key | endswith("@" + $n))) | .key' \
      .claude/settings.json 2>/dev/null | tr -d '\r'
  )
  mapfile -t have < <("$claude_bin" plugin list --json 2>/dev/null | jq -r '.[].id' 2>/dev/null | tr -d '\r')

  mapfile -t default_disabled < <(
    jq -r '.plugins[]? | select(.defaultEnabled == false) | .name' \
      "$source_repo/.claude-plugin/marketplace.json" 2>/dev/null | tr -d '\r'
  )

  plugins_registry="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
  head_sha="$(git -C "$source_repo" rev-parse HEAD 2>/dev/null || true)"
  recorded_sha() {
    jq -r --arg id "$1" \
      '(.plugins[$id] // []) | map(select(.scope == "user")) | .[0].gitCommitSha // ""' \
      "$plugins_registry" 2>/dev/null | tr -d '\r'
  }
  needs_refresh() {
    local id="$1" name="${1%@*}" recorded
    [[ -n "$head_sha" && -f "$plugins_registry" ]] || return 1
    recorded="$(recorded_sha "$id")"
    [[ -n "$recorded" && "$recorded" != "$head_sha" ]] || return 1
    git -C "$source_repo" cat-file -e "${recorded}^{commit}" 2>/dev/null || return 0
    ! git -C "$source_repo" diff --quiet "$recorded" HEAD -- "plugins/$name" 2>/dev/null
  }

  snapshot_problem() {
    local id="$1" name="${1%@*}" recorded
    if [[ -z "$head_sha" ]]; then
      printf 'cannot verify snapshot: this checkout has no resolvable HEAD'
      return 0
    fi
    if [[ ! -f "$plugins_registry" ]]; then
      printf 'cannot verify snapshot: no plugin registry at %s' "$plugins_registry"
      return 0
    fi
    recorded="$(recorded_sha "$id")"
    if [[ -z "$recorded" || "$recorded" == "null" ]]; then
      printf 'cannot verify snapshot: no user-scope gitCommitSha recorded in %s' \
        "$plugins_registry"
      return 0
    fi
    [[ "$recorded" != "$head_sha" ]] || return 0
    if ! git -C "$source_repo" cat-file -e "${recorded}^{commit}" 2>/dev/null; then
      printf 'cannot verify snapshot: installed from commit %s, which this clone does not have' \
        "$recorded"
      return 0
    fi
    if ! git -C "$source_repo" diff --quiet "$recorded" HEAD -- "plugins/$name" 2>/dev/null; then
      printf 'plugins/%s changed between the installed commit %s and HEAD' "$name" "$recorded"
    fi
    return 0
  }

  installed=0
  refreshed=0
  declare -A action_of=()
  for id in "${wanted[@]}"; do
    [[ -n "$id" ]] || continue
    action_of["$id"]="no action"
    if [[ " ${have[*]} " == *" $id "* ]]; then
      # shellcheck disable=SC2310  # the return status IS the verdict
      needs_refresh "$id" || continue
      "$claude_bin" plugin uninstall "$id" --keep-data >/dev/null 2>&1 || true
      "$claude_bin" plugin install "$id" --scope user -y >/dev/null 2>&1 || true
      "$claude_bin" plugin enable "$id" --scope user >/dev/null 2>&1 || true
      action_of["$id"]="refresh"
      continue
    fi
    "$claude_bin" plugin install "$id" --scope user -y >/dev/null 2>&1 || true
    action_of["$id"]="install"
  done

  failed_ids=()
  end_state="$("$claude_bin" plugin list --json 2>/dev/null || true)"
  listed=1
  jq -e 'type == "array"' <<<"$end_state" >/dev/null 2>&1 || listed=0
  if [[ "$listed" -eq 0 ]]; then
    echo "cloud-bootstrap: warning: could not read \`claude plugin list --json\`; no plugin could be verified" >&2
  fi
  for id in "${wanted[@]}"; do
    [[ -n "$id" ]] || continue
    action="${action_of[$id]}"
    reason=""
    on_user="" enabled_true="" enabled_false=""
    if [[ "$listed" -eq 1 ]]; then
      IFS=$'\t' read -r on_user enabled_true enabled_false < <(
        jq -r --arg id "$id" \
          'def user(f): try any(.[]?; .id == $id and .scope == "user" and f) catch false;
           [user(true), user(.enabled == true), user(.enabled == false)] | @tsv' \
          <<<"$end_state" 2>/dev/null | tr -d '\r'
      ) || true
    fi
    if [[ "$listed" -eq 0 ]]; then
      reason="unverified"
    elif [[ "$on_user" != true ]]; then
      reason="not installed at user scope"
    elif [[ "$enabled_true" != true ]] &&
      ! [[ "$enabled_false" == true && " ${default_disabled[*]} " == *" ${id%@*} "* ]]; then
      reason="installed at user scope but not enabled"
    else
      reason="$(snapshot_problem "$id")"
    fi
    if [[ -n "$reason" ]]; then
      failed_ids+=("$id")
      [[ "$listed" -eq 0 ]] ||
        echo "cloud-bootstrap: warning: $id failed verification after $action: $reason" >&2
    elif [[ "$action" == "refresh" ]]; then
      refreshed=$((refreshed + 1))
    elif [[ "$action" == "install" ]]; then
      installed=$((installed + 1))
    fi
  done

  plugin_summary="cloud-bootstrap: plugins ${#wanted[@]} declared, $installed newly installed, $refreshed refreshed, ${#failed_ids[@]} failed"
  if [[ "$listed" -eq 0 ]]; then
    plugin_summary="$plugin_summary: none could be verified, see the warning above"
  elif ((${#failed_ids[@]} > 0)); then
    failed_list="$(printf '%s, ' "${failed_ids[@]}")"
    plugin_summary="$plugin_summary: ${failed_list%, }"
  fi
  echo "$plugin_summary"
fi

# --- Python CI deps (required) -------------------------------------------------
# pip rather than uv: uv's PyPI fetches time out against this VM's egress proxy.
python3 -m pip install --user --quiet --only-binary=:all: --require-hashes \
  --requirement .github/requirements-ci.txt

fetch_release_tool() {
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
    *) member="asset" ;;
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
if command -v actionlint >/dev/null 2>&1 &&
  [[ "$(actionlint -version 2>/dev/null | head -n 1)" != *kjanat* ]]; then
  rm -f "$bin_dir/actionlint"
fi
fetch_release_tool actionlint \
  "https://github.com/kjanat/actionlint/releases/download/v${actionlint_pin}/actionlint_${actionlint_pin}_linux_amd64.tar.gz" \
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
fetch_release_tool shfmt \
  "https://github.com/mvdan/sh/releases/download/${shfmt_pin}/shfmt_${shfmt_pin}_linux_amd64" \
  "$shfmt_sha" "-"

repo_mdlint="$repo_root/node_modules/.bin/markdownlint-cli2"
if [[ -x "$repo_mdlint" ]]; then
  ln -sfn "$repo_mdlint" "$bin_dir/markdownlint-cli2"
elif [[ ! -e "$bin_dir/markdownlint-cli2" ]]; then
  echo "cloud-bootstrap: warning: markdownlint-cli2 missing from node_modules/.bin after npm ci; markdown-format will skip until it is present" >&2
fi

if ! command -v check-jsonschema >/dev/null 2>&1; then
  if command -v uv >/dev/null 2>&1; then
    uv tool install --quiet "check-jsonschema==${check_jsonschema_pin}"
  else
    python3 -m pip install --user --quiet "check-jsonschema==${check_jsonschema_pin}"
  fi || echo "cloud-bootstrap: warning: check-jsonschema install failed" >&2
fi

git_dir="$(git rev-parse --git-dir)"
if [[ -f "$git_dir/shallow" ]]; then
  git fetch --quiet --unshallow ||
    echo "cloud-bootstrap: warning: could not unshallow; base-ref diffs may fail" >&2
fi
# Explicit destination refspec: in a single-branch clone a bare `fetch origin
# main` only writes FETCH_HEAD and never creates refs/remotes/origin/main.
git fetch --quiet origin "+main:refs/remotes/origin/main" ||
  echo "cloud-bootstrap: warning: could not fetch origin/main" >&2

# --- Git author (best effort) ---------------------------------------------------
gh_user="$(gh api user --jq 'select((.login // "") != "" and (.id // "" | tostring) != "")
  | [.login, (.id | tostring), (.name // "")] | @tsv' 2>/dev/null)" || gh_user=''
IFS=$'\t' read -r gh_login gh_id gh_name <<<"$gh_user" || true
if [[ -z "$gh_login" || -z "$gh_id" ]] ||
  ! git config --global author.name "${gh_name:-$gh_login}" ||
  ! git config --global author.email "$gh_id+$gh_login@users.noreply.github.com"; then
  git config --global --unset author.name 2>/dev/null || true
  git config --global --unset author.email 2>/dev/null || true
  echo "cloud-bootstrap: warning: could not derive the git author from the connected GitHub account; author.* cleared" >&2
fi

# --- Report --------------------------------------------------------------------
hook_safe_path="$PATH"
if [[ -n "${node_bin:-}" ]]; then
  hook_safe_path="$(
    PATH="$PATH" bash -c '
      IFS=:
      out=
      for p in $PATH; do
        [[ "$p" == "$0" ]] && continue
        out="${out:+$out:}$p"
      done
      printf "%s" "$out"
    ' "$node_bin"
  )"
fi

report_tool() {
  local name="$1" resolved ver
  shift
  resolved="$(PATH="$hook_safe_path" command -v "$name" 2>/dev/null || true)"
  if [[ -z "$resolved" && "$name" == "markdownlint-cli2" && -x "$repo_mdlint" ]]; then
    resolved="$repo_mdlint"
  fi
  if [[ -n "$resolved" ]]; then
    ver="$(PATH="$hook_safe_path" "$resolved" "$@" 2>/dev/null | head -1 || true)"
    echo "cloud-bootstrap: $name ($resolved)${ver:+ $ver}"
  else
    echo "cloud-bootstrap: $name ABSENT on hook-visible PATH (its checks will SKIP)"
  fi
}
echo "cloud-bootstrap: bootstrap complete in $repo_root (report_tool uses hook-safe PATH; nvm prefix excluded)"
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
