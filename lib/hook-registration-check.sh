# shellcheck shell=bash
# shellcheck disable=SC2154  # the calling plugin script sets every HR_* variable
hook_registration_check() {
  local hook hooks script_arg node_path out failed=0
  if [[ $# -gt 0 ]]; then
    echo "check-hook-registration: takes no arguments" >&2
    exit 2
  fi
  : "${HR_ROOT:?}" "${HR_HOOK:?}" "${HR_EVENT:?}" "${HR_MATCHER:?}" "${HR_ROW:?}" \
    "${HR_NODE_FAIL:?}" "${HR_TEXT_FAIL:?}" "${HR_SAMPLE:?}" "${HR_EXPECT:?}" \
    "${HR_SAMPLE_PASS:?}" "${HR_SAMPLE_FAIL:?}"
  hook="$HR_ROOT/hooks/$HR_HOOK"
  hooks="$HR_ROOT/hooks/hooks.json"
  _hook_registration_row() {
    printf '%s\t%s\t%s\n' "$1" "$2" "$3"
    [[ "$2" == PASS ]] || failed=1
  }

  node_path="$(command -v node 2>/dev/null || true)"
  if [[ -n "$node_path" ]]; then
    _hook_registration_row node PASS "$node_path $(node --version 2>&1)"
  else
    _hook_registration_row node FAIL "$HR_NODE_FAIL"
  fi

  # shellcheck disable=SC2016  # hooks.json spells the token literally
  script_arg='${CLAUDE_PLUGIN_ROOT}/hooks/'"$HR_HOOK"
  if [[ ! -f "$hooks" ]]; then
    _hook_registration_row registration FAIL "$hooks is missing"
  elif [[ ! -f "$hook" ]]; then
    _hook_registration_row registration FAIL "$hook is missing"
  elif [[ -n "$node_path" ]]; then
    if node -e '
      const [file, event, matcher, arg] = process.argv.slice(1)
      const groups = (JSON.parse(require("fs").readFileSync(file, "utf8")).hooks || {})[event] || []
      const ok = groups.some(g => g.matcher === matcher && (g.hooks || []).some(h =>
        h.type === "command" && h.command === "node" && Array.isArray(h.args) && h.args.includes(arg)))
      process.exit(ok ? 0 : 1)
    ' "$hooks" "$HR_EVENT" "$HR_MATCHER" "$script_arg" 2>/dev/null; then
      _hook_registration_row registration PASS "$HR_EVENT $HR_MATCHER -> node $HR_HOOK"
    else
      _hook_registration_row registration FAIL "no $HR_EVENT $HR_MATCHER hook entry runs node on $HR_HOOK"
    fi
  elif grep -qF "\"$HR_EVENT\"" "$hooks" && grep -q "\"matcher\": *\"$HR_MATCHER\"" "$hooks" &&
    grep -q '"command": *"node"' "$hooks" && grep -qF "$script_arg" "$hooks"; then
    _hook_registration_row registration PASS "text match only; one-entry structure is checked when node resolves"
  else
    _hook_registration_row registration FAIL "$HR_TEXT_FAIL"
  fi

  if [[ -z "$node_path" ]]; then
    _hook_registration_row "$HR_ROW" FAIL "not run: node is missing"
  elif [[ ! -f "$hook" ]]; then
    _hook_registration_row "$HR_ROW" FAIL "not run: $hook is missing"
  else
    out="$(printf '%s' "$HR_SAMPLE" | node "$hook" 2>&1)"
    if grep -q "$HR_EXPECT" <<<"$out"; then
      _hook_registration_row "$HR_ROW" PASS "$HR_SAMPLE_PASS"
    else
      _hook_registration_row "$HR_ROW" FAIL "$HR_SAMPLE_FAIL: ${out:-<no output>}"
    fi
  fi
  exit "$failed"
}
