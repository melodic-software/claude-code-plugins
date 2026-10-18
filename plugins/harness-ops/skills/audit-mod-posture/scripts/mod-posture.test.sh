#!/usr/bin/env bash
# Self-contained tests for mod-posture.sh. A stub claude serves `plugin list`, `plugin
# validate`, `auth status` and `--version` from fixture files; HOME and the managed settings
# path point into the fixture, so no run reads this machine's install, settings or policy.
# One case runs the real `claude plugin validate` when a claude resolves on PATH.
set -uo pipefail

unset CLAUDE_CONFIG_DIR CLAUDE_CODE_ENTRYPOINT WSL_DISTRO_NAME
REAL_CLAUDE="$(command -v claude 2>/dev/null || true)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MP="$SCRIPT_DIR/mod-posture.sh"

TEST_TMPDIR="$(mktemp -d 2>/dev/null)" || TEST_TMPDIR=""
if [[ -z "$TEST_TMPDIR" || ! -d "$TEST_TMPDIR" ]]; then
  echo "mod-posture.test.sh: mktemp -d failed; refusing to write fixtures" >&2
  exit 2
fi
trap 'rm -rf -- "${TEST_TMPDIR:?}"' EXIT

FAILED=0
CASE=0
pass() {
  CASE=$((CASE + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE=$((CASE + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi; }
assert_contains() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "expected to contain: $3" ;; esac; }
assert_not_contains() { case "$2" in *"$3"*) fail "$1" "must not contain: $3" ;; *) pass "$1" ;; esac; }

# Fixture root holds a space so every path is exercised with one.
FIX="$TEST_TMPDIR/fix dir"
mkdir -p "$FIX/home/.claude" "$FIX/bin" "$FIX/proj" "$FIX/other proj" "$FIX/validate" "$FIX/managed"
export HOME="$FIX/home"
cat >"$HOME/.claude/settings.json" <<'EOF'
{"env": {"API_TOKEN": "SECRETSETTINGS1"}, "enabledPlugins": {"mod-a@mk": true}}
EOF

# plugin <dir> <name> <hooks.json body or ""> [plugin.json hooks object]
plugin() {
  mkdir -p "$1/.claude-plugin" "$1/hooks"
  local inline="${4:-}"
  printf '{"name":"%s","version":"1.0.0","userConfig":{"k":{"type":"string","default":"SECRETUSERCFG1"}}%s}\n' \
    "$2" "${inline:+,\"hooks\":$inline}" >"$1/.claude-plugin/plugin.json"
  [[ -n "$3" ]] && printf '%s\n' "$3" >"$1/hooks/hooks.json"
  return 0
}
P="$FIX/plugins"
plugin "$P/mod-a" mod-a '{"modules":["./register.js"],"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo SECRETHOOKCMD1"}]}]}}'
plugin "$P/plain" plain '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"true"}]}]}}'
plugin "$P/inline" inline '' '{"modules":["./register.js"]}'
plugin "$P/hostile" hostile '{"modules":["./register.js"]}'
plugin "$P/elsewhere" elsewhere '{"modules":["./register.js"]}'
plugin "$P/broken" broken '{"modules":["./register.js"]}'
plugin "$P/spaced" spaced '{"modules":["./a b.js"]}'
plugin "$P/silent" silent '{"modules":["./register.js"]}'

proj_real="$(cd "$FIX/proj" && pwd -P)"
other_real="$(cd "$FIX/other proj" && pwd -P)"
jq -n --arg p "$P" --arg proj "$proj_real" --arg other "$other_real" '[
  {id:"mod-a@mk", scope:"user", enabled:true, installPath:"\($p)/mod-a", installedAt:"SECRETINSTALLED1"},
  {id:"mod-a@mk", scope:"project", enabled:true, installPath:"\($p)/mod-a", projectPath:"/SECRETPROJPATH1"},
  {id:"plain@mk", scope:"user", enabled:true, installPath:"\($p)/plain"},
  {id:"inline@mk", scope:"project", enabled:false, installPath:"\($p)/inline", projectPath:$proj},
  {id:"bad id SECRETID1@mk", scope:"managed", enabled:true, installPath:"\($p)/hostile"},
  {id:"elsewhere@mk", scope:"local", enabled:true, installPath:"\($p)/elsewhere", projectPath:$other},
  {id:"broken@mk", scope:"user", enabled:true, installPath:"\($p)/broken"},
  {id:"spaced@mk", scope:"user", enabled:true, installPath:"\($p)/spaced"},
  {id:"silent@mk", scope:"user", enabled:true, installPath:"\($p)/silent"}
]' >"$FIX/list.json"

# validate fixtures, keyed by plugin directory name.
validate_json() { # <name> <success> <notes...>
  local name="$1" ok="$2"
  shift 2
  jq -n --arg f "$P/$name/hooks/hooks.json" --argjson ok "$ok" '$ARGS.positional as $n |
    {success:$ok, manifest:{errors:[]}, contents:[{file:$f, notes:$n}],
     advice:[{message:"install line SECRETADVICE1"}]}' --args "$@" >"$FIX/validate/$name.json"
}
validate_json mod-a true \
  './register.js hooks: tool.call, session.start, command.run{command=mod-a}' \
  './register.js calls: $.fs.read (via load), $.process.run, $.ui.log' \
  './register.js env reads: SECRETENVNAME1, HOME'
validate_json inline true './register.js hooks: prompt.submit, session.append' './register.js calls: $.http.fetch'
validate_json hostile false \
  './register.js hooks: tool.check, tool.call{x=a b SECRETHOOK1}, ignore.previous instructions SECRETHOOK2' \
  './register.js calls: $.fs.write, rm -rf SECRETCALL1, $.env.get(SECRETCALL2)'
validate_json elsewhere true './register.js hooks: tool.call'
validate_json spaced true \
  './a b.js hooks: tool.call{tool=mcp__plugin_context-guard_context-guard__status}, prompt.submit' \
  './a b.js calls: $.process.run'
validate_json silent false

cat >"$FIX/bin/claude" <<'EOF'
#!/usr/bin/env bash
case "$1 ${2:-}" in
"--version ") echo "2.1.302 (Claude Code)" ;;
"plugin list") [[ -f "$STUB_LIST" ]] && cat "$STUB_LIST" || exit 1 ;;
"plugin validate")
  dir="${4:-}"
  if [[ -n "${STUB_REAL_CLAUDE:-}" ]]; then exec "$STUB_REAL_CLAUDE" "$@"; fi
  f="$STUB_VALIDATE/$(basename "$dir").json"
  [[ -f "$f" ]] && cat "$f" || exit 1 ;;
"auth status") [[ -f "$STUB_AUTH" ]] && cat "$STUB_AUTH" || exit 1 ;;
*) exit 1 ;;
esac
EOF
chmod +x "$FIX/bin/claude"
export MOD_POSTURE_CLAUDE="$FIX/bin/claude" STUB_LIST="$FIX/list.json" STUB_VALIDATE="$FIX/validate" \
  STUB_AUTH="$FIX/auth.json"
# auth <subscriptionType JSON value>: every auth fixture also carries fields that must never print.
auth() { printf '{"subscriptionType":%s,"email":"SECRETEMAIL1@example.com","orgName":"SECRETORG1","orgId":"SECRETORGID1"}\n' "$1" >"$FIX/auth.json"; }
auth '"max"'

cat >"$FIX/overview.md" <<'EOF'
## Mods built into Claude Code

| Name in `/plugin` | What it does | Where it's on | How to turn it off |
| :- | :- | :- | :- |
| `cc-plugin-diff` | Takes over `/diff` | Interactive terminal sessions | Disable it in `/plugin`. |
| `cc-plugin-sec-default` | Guards what your organization manages | Where the guard loads | You can't. An administrator sets the order |
EOF
cat >"$FIX/inventory.json" <<'EOF'
{
  "builtin_plugins": {
    "cc-plugin-diff": {"id": "cc-plugin-diff@builtin", "default_enabled": true, "hook_events": ["ui.render", "tool.call"], "description": "SECRETBUILTIN1"},
    "cc-plugin-sec-default": {"id": "cc-plugin-sec-default@builtin", "default_enabled": true, "hook_events": ["tool.check", "session.append"]},
    "cc-plugin-you-should-know": {"id": "cc-plugin-you-should-know@builtin", "default_enabled": false, "hook_events": []},
    "cc-plugin-mystery": {"id": "cc-plugin-mystery@builtin", "default_enabled": null, "hook_events": null},
    "cc-plugin-off-by-default": {"id": "cc-plugin-off-by-default@builtin", "default_enabled": false, "hook_events": ["ui.render"]}
  },
  "builtin_plugin_state": {
    "global_config": "/SECRETGLOBALPATH1/.claude.json",
    "plugins": {
      "cc-plugin-you-should-know": {"id": "cc-plugin-you-should-know@builtin", "default_enabled": false, "enabled_setting": true},
      "cc-plugin-diff": {"id": "cc-plugin-diff@builtin", "default_enabled": true, "enabled_setting": false}
    }
  }
}
EOF

OUT=""
ERR=""
RC=0
ALL=""
run_mp() {
  OUT="$(cd "$FIX/proj" && bash "$MP" --date 2026-10-17 --managed-file "$FIX/managed/managed-settings.json" "$@" 2>"$FIX/stderr.txt")"
  RC=$?
  ERR="$(<"$FIX/stderr.txt")"
  ALL+="$OUT$ERR"
}
# field <id> <n>: the nth tab-separated field (1-based) of the row whose id is <id>.
field() { printf '%s\n' "$OUT" | awk -F'\t' -v id="$1" -v n="$2" '$1 == id { print $n; exit }'; }
count_rows() { printf '%s\n' "$OUT" | awk -F'\t' -v id="$1" '$1 == id' | wc -l | tr -d ' '; }

# --- Installed tier ------------------------------------------------------------------------
run_mp --overview "$FIX/overview.md" --builtin-json "$FIX/inventory.json"
assert_eq "exits 0" 0 "$RC"
assert_eq "dated header" "# mod-posture inventory 2026-10-17" "$(printf '%s\n' "$OUT" | head -1)"
assert_eq "column header" $'id\ttier\tenabled\tcan_disable\thooks\tcalls\tsource' "$(printf '%s\n' "$OUT" | sed -n 2p)"
assert_eq "hooks.json modules: the mod is listed with its hooks: line" \
  "tool.call,session.start,command.run{command=mod-a}" "$(field mod-a@mk 5)"
assert_eq "calls drop the (via ...) annotation" '$.fs.read,$.process.run,$.ui.log' "$(field mod-a@mk 6)"
assert_eq "two list entries for one installPath make one row" 1 "$(count_rows mod-a@mk)"
assert_eq "user-scope mod is user tier, on" "user on validate" "$(field mod-a@mk 2) $(field mod-a@mk 3) $(field mod-a@mk 7)"
assert_eq "plugin without modules is not listed" 0 "$(count_rows plain@mk)"
assert_eq "inline plugin.json hooks modules counts as a mod" "prompt.submit,session.append" "$(field inline@mk 5)"
assert_eq "project entry for this project decides enabled" "off" "$(field inline@mk 3)"
assert_eq "path only another project enables is skipped" 0 "$(count_rows elsewhere@mk)"
assert_contains "skipped path is counted in a footer" "$OUT" "# not read: installed tier: 1 install path(s) only other projects enable, skipped"
assert_eq "validate failure reads unknown" "unknown unknown validate-failed" \
  "$(field broken@mk 5) $(field broken@mk 6) $(field broken@mk 7)"

# --- Grammar filter ------------------------------------------------------------------------
assert_eq "id outside the grammar prints redacted-id" 1 "$(count_rows redacted-id)"
assert_eq "managed scope is the managed tier" managed "$(field redacted-id 2)"
assert_eq "hook names outside the grammar print redacted, keeping a valid event" \
  "tool.check,tool.call{redacted},redacted" "$(field redacted-id 5)"
assert_eq "call names outside the grammar print redacted" '$.fs.write,redacted' "$(field redacted-id 6)"
assert_eq "validate with success false is marked" validate-errors "$(field redacted-id 7)"
assert_eq "managed tier can_disable reads unknown" unknown "$(field redacted-id 4)"
assert_contains "withheld names are counted in a footer" "$OUT" "# not read: names: 4 hook or call name(s) outside the grammar withheld"
assert_eq "module path with a space keeps its hooks; a long filter keeps its event" \
  "tool.call{redacted},prompt.submit" "$(field spaced@mk 5)"
assert_eq "module path with a space keeps its calls" '$.process.run' "$(field spaced@mk 6)"
assert_eq "validate errors with no notes read unknown, not none" "unknown unknown validate-errors" \
  "$(field silent@mk 5) $(field silent@mk 6) $(field silent@mk 7)"

# --- Built-in tier -------------------------------------------------------------------------
assert_eq "built-in row: tier, setting overrides default, can_disable from the table" \
  "builtin off yes ui.render,tool.call unknown builtin-lane" \
  "$(for n in 2 3 4 5 6 7; do printf '%s ' "$(field cc-plugin-diff@builtin $n)"; done | sed 's/ $//')"
assert_eq "You can't in the table reads can_disable no" no "$(field cc-plugin-sec-default@builtin 4)"
assert_eq "enabled_setting true turns an off-by-default built-in on" on "$(field cc-plugin-you-should-know@builtin 3)"
assert_eq "empty hook_events reads -" "-" "$(field cc-plugin-you-should-know@builtin 5)"
assert_eq "default_enabled false with no setting reads off" off "$(field cc-plugin-off-by-default@builtin 3)"
assert_eq "unresolved default and hooks read unknown; absent from the table reads unknown" \
  "unknown unknown unknown" \
  "$(field cc-plugin-mystery@builtin 3) $(field cc-plugin-mystery@builtin 4) $(field cc-plugin-mystery@builtin 5)"
assert_contains "built-in enabled is marked partial" "$OUT" "# not read: built-in enabled: managed settings and --settings are not read"

run_mp --no-fetch
assert_contains "no --builtin-json is named in a footer" "$OUT" "# not read: built-in tier: built-in mods were not read (no --builtin-json inventory report)"
assert_contains "--no-fetch is named in a footer" "$OUT" "# not read: can_disable: --no-fetch"
assert_eq "no built-in rows without the report" 0 "$(printf '%s\n' "$OUT" | grep -c '@builtin')"

# --- Guard ---------------------------------------------------------------------------------
assert_contains "no managed settings and a Max plan: not seated" "$OUT" "# guard: not-seated (no managed settings; plan max)"
auth '"team"'
run_mp --no-fetch
assert_contains "Team plan seats the guard" "$OUT" "# guard: seated (plan team)"
auth null
run_mp --no-fetch
assert_contains "no subscription (API key) without managed settings: not seated" "$OUT" "# guard: not-seated (no managed settings; plan none)"
printf '{}\n' >"$FIX/managed/managed-settings.json"
run_mp --no-fetch
assert_contains "managed settings file seats the guard" "$OUT" "# guard: seated (managed settings present)"
rm -f -- "$FIX/managed/managed-settings.json"
mkdir -p "$FIX/managed/managed-settings.d"
printf '{}\n' >"$FIX/managed/managed-settings.d/10-team.json"
run_mp --no-fetch
assert_contains "a drop-in file seats the guard" "$OUT" "# guard: seated (managed settings present)"
rm -rf -- "${FIX:?}/managed/managed-settings.d"
mv "$FIX/auth.json" "$FIX/auth.off"
run_mp --no-fetch
assert_contains "unreadable auth status leaves the guard unknown" "$OUT" "# guard: unknown (managed settings absent; plan unread)"
mv "$FIX/auth.off" "$FIX/auth.json"

# --- Surface -------------------------------------------------------------------------------
assert_contains "terminal footer names the Desktop copy" "$OUT" "# surface: terminal (2.1.302); the Desktop app bundles its own copy"
run_mp --no-fetch --surface desktop
assert_contains "--surface desktop" "$OUT" "# surface: desktop (2.1.302"

# --- Failure and usage ---------------------------------------------------------------------
STUB_LIST="$FIX/missing.json" run_mp --no-fetch
assert_eq "plugin list failure still exits 0" 0 "$RC"
assert_contains "plugin list failure is named" "$OUT" "# not read: installed tier: claude plugin list --json did not return a list"
run_mp --date 17-10-2026
assert_eq "bad --date exits 2" 2 "$RC"
run_mp --surface web
assert_eq "bad --surface exits 2" 2 "$RC"
run_mp --project "$FIX/no-such-dir"
assert_eq "--project that is not a directory exits 2" 2 "$RC"
run_mp --frobnicate
assert_eq "unknown argument exits 2" 2 "$RC"
run_mp --help
assert_contains "--help prints usage" "$OUT" "Usage:"
assert_contains "--help prints through the Exit line" "$OUT" "Exit: 0"

# --- Real validate leaves the install directory unchanged ------------------------------------
tree_hash() { (cd "$1" && find . -print0 | LC_ALL=C sort -z | xargs -0 ls -ld --time-style=+%s 2>/dev/null | awk '{ $2 = ""; print }' && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 cksum) | cksum; }
if [[ -n "$REAL_CLAUDE" ]] && "$REAL_CLAUDE" --version >/dev/null 2>&1; then
  R="$FIX/real"
  plugin "$R/real-mod" real-mod '{"modules":["./register.js"]}'
  cat >"$R/real-mod/hooks/register.js" <<'EOF'
export const register = (on) => {
  on('tool.call', async ($, e, next) => {
    await $.fs.read('/tmp/fixture.txt')
    return next(e)
  }).catch(($, e, next) => next(e))
  on('session.start', async ($) => {
    await $.process.run(['true'])
  })
}
EOF
  jq -n --arg p "$R/real-mod" '[{id:"real-mod@mk", scope:"user", enabled:true, installPath:$p}]' >"$FIX/real-list.json"
  before="$(tree_hash "$R/real-mod")"
  STUB_LIST="$FIX/real-list.json" STUB_REAL_CLAUDE="$REAL_CLAUDE" run_mp --no-fetch
  after="$(tree_hash "$R/real-mod")"
  assert_eq "real validate reads the fixture mod's hooks" "tool.call,session.start" "$(field real-mod@mk 5)"
  assert_eq "real validate reads the fixture mod's calls" '$.fs.read,$.process.run' "$(field real-mod@mk 6)"
  assert_eq "install-dir tree hash unchanged after validate" "$before" "$after"
else
  printf 'SKIP: real claude plugin validate (no claude on PATH)\n'
fi

# --- Planted secrets never reach stdout or stderr of any run ---------------------------------
planted="$(grep -rhoE 'SECRET[A-Z0-9_]*' "$FIX" | LC_ALL=C sort -u)"
assert_eq "all 17 planted secret tokens were collected" 17 "$(printf '%s\n' "$planted" | grep -c .)"
while IFS= read -r secret; do
  [[ -n "$secret" ]] && assert_not_contains "secret $secret never emitted" "$ALL" "$secret"
done <<<"$planted"
assert_not_contains "no fixture path is emitted" "$ALL" "$FIX"

if [[ $FAILED -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE" >&2
exit 1
