#!/usr/bin/env bash
# Unit tests for sync-shared-copies.sh, driven through its CLI against a
# throwaway tree that carries its own scripts/shared-copies.txt.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

root=""
HEADER_JS='// GENERATED from lib/esc.mjs by scripts/sync-shared-copies.sh. Do not edit this copy:'

# fixture: canonical lib/esc.mjs carried by plugins/alpha and plugins/beta.
fixture() {
  fixture_tree::build root --sut sync-shared-copies.sh --label shared-copies || exit 2
  mkdir -p "$root/lib" "$root/plugins/alpha/.claude-plugin" "$root/plugins/beta/.claude-plugin"
  printf 'export const esc = (s) => String(s);\n' >"$root/lib/esc.mjs"
  printf '{"name":"alpha","version":"0.1.0"}\n' >"$root/plugins/alpha/.claude-plugin/plugin.json"
  printf '{"name":"beta","version":"0.1.0"}\n' >"$root/plugins/beta/.claude-plugin/plugin.json"
  printf '# comment line\nlib/esc.mjs plugins/alpha/lib/esc.mjs\nlib/esc.mjs plugins/beta/lib/esc.mjs  # trailing\n' \
    >"$root/scripts/shared-copies.txt"
}

run() { (cd "$root" && bash scripts/sync-shared-copies.sh "$@" 2>&1); }

expect() { # <name> <want-rc> <got-rc> <output>
  if [[ "$3" -eq "$2" ]]; then pass "$1"; else bad "$1" "want exit $2, got $3: $4"; fi
}

# --- regen writes the header, then the canonical, into every copy -----------
fixture
out="$(run)"
expect "regen exits 0" 0 $? "$out"
want="$HEADER_JS"$'\n''// edit the canonical source, then rerun the script.'$'\n''export const esc = (s) => String(s);'
for copy in plugins/alpha/lib/esc.mjs plugins/beta/lib/esc.mjs; do
  if [[ "$(cat "$root/$copy")" == "$want" ]]; then
    pass "regen generates $copy as header plus canonical"
  else
    bad "regen generates $copy as header plus canonical" "got: $(cat "$root/$copy")"
  fi
done

# --- running it twice produces no diff -------------------------------------
git_init_test_repo "$root" >/dev/null || exit 2
git -C "$root" add -A && git -C "$root" commit -qm base
out="$(run)"
if [[ -z "$(git -C "$root" status --porcelain)" && -z "$out" ]]; then
  pass "a second regen changes nothing"
else
  bad "a second regen changes nothing" "status: $(git -C "$root" status --porcelain) out: $out"
fi

# --- --check passes on generated copies --------------------------------------
out="$(run --check)"
expect "--check passes when every copy is generated" 0 $? "$out"

# --- --check fails on a hand-edited copy and never writes --------------------
printf '// hand edit\n' >>"$root/plugins/beta/lib/esc.mjs"
before="$(cat "$root/plugins/beta/lib/esc.mjs")"
out="$(run --check)"
expect "--check fails on a hand-edited copy" 1 $? "$out"
LAST_OUTPUT="$out"
assert_output_contains "--check names the drifted copy" "DRIFT: plugins/beta/lib/esc.mjs"
if [[ "$(cat "$root/plugins/beta/lib/esc.mjs")" == "$before" && "$out" != *alpha* ]]; then
  pass "--check leaves the drifted copy as it found it"
else
  bad "--check leaves the drifted copy as it found it" "copy rewritten or alpha reported"
fi
git -C "$root" checkout -q -- .

# --- --check fails when the canonical changed without a regen ----------------
printf 'export const esc = (s) => String(s ?? "");\n' >"$root/lib/esc.mjs"
out="$(run --check)"
expect "--check fails when the canonical changed without a regen" 1 $? "$out"

# --- --check-bump --------------------------------------------------------------
base="$(git -C "$root" rev-parse HEAD)"
run >/dev/null
out="$(run --check-bump "$base")"
expect "--check-bump fails when a carrier did not bump" 1 $? "$out"
LAST_OUTPUT="$out"
assert_output_contains "--check-bump names the stale manifest" "STALE VERSION: lib/esc.mjs or its copy plugins/alpha/lib/esc.mjs changed vs $base but plugins/alpha/.claude-plugin/plugin.json"
assert_output_contains "--check-bump gives the sync-only CHANGELOG entry" "Shared \`esc.mjs\` synced"
printf '{"name":"alpha","version":"0.1.1"}\n' >"$root/plugins/alpha/.claude-plugin/plugin.json"
out="$(run --check-bump "$base")"
expect "--check-bump still fails while one carrier is unbumped" 1 $? "$out"
printf '{"name":"beta","version":"0.1.1"}\n' >"$root/plugins/beta/.claude-plugin/plugin.json"
out="$(run --check-bump "$base")"
expect "--check-bump passes once every carrier bumped" 0 $? "$out"
git -C "$root" checkout -q -- .
out="$(run --check-bump "$base")"
expect "--check-bump passes when no canonical changed" 0 $? "$out"
out="$(run --check-bump no-such-ref)"
expect "--check-bump rejects a base that does not resolve" 2 $? "$out"

# A plugin absent at the base is new; its first release carries the change.
mkdir -p "$root/plugins/gamma/.claude-plugin"
printf '{"name":"gamma","version":"0.1.0"}\n' >"$root/plugins/gamma/.claude-plugin/plugin.json"
printf 'lib/esc.mjs plugins/gamma/lib/esc.mjs\n' >>"$root/scripts/shared-copies.txt"
printf 'export const esc = (s) => String(s ?? "");\n' >"$root/lib/esc.mjs"
printf '{"name":"alpha","version":"0.1.1"}\n' >"$root/plugins/alpha/.claude-plugin/plugin.json"
printf '{"name":"beta","version":"0.1.1"}\n' >"$root/plugins/beta/.claude-plugin/plugin.json"
run >/dev/null
out="$(run --check-bump "$base")"
expect "--check-bump exempts a plugin absent at the base" 0 $? "$out"
if [[ -f "$root/plugins/gamma/lib/esc.mjs" ]]; then
  pass "regen creates a newly registered copy"
else
  bad "regen creates a newly registered copy" "plugins/gamma/lib/esc.mjs missing"
fi

# A copy that changed while its canonical did not (a new header) still needs a bump.
fixture
run >/dev/null
git_init_test_repo "$root" >/dev/null || exit 2
git -C "$root" add -A && git -C "$root" commit -qm base
base="$(git -C "$root" rev-parse HEAD)"
printf '// new header line\n' >>"$root/plugins/alpha/lib/esc.mjs"
out="$(run --check-bump "$base")"
expect "--check-bump fails when only a copy changed" 1 $? "$out"
LAST_OUTPUT="$out"
assert_output_contains "--check-bump names the changed copy" "its copy plugins/alpha/lib/esc.mjs changed"

# A fragment carries a carrier's bump only when that carrier is in fragment mode.
mkdir -p "$root/.changes/alpha" "$root/.changes/beta"
for name in alpha beta; do
  printf -- '---\nbump: patch\n---\n\n### Fixed\n\n- Shared esc.mjs synced.\n' >"$root/.changes/$name/sync-esc-0123abcd.md"
done
git -C "$root" add -A
printf 'alpha\n' >"$root/scripts/fragment-plugins.txt"
printf 'export const esc = (s) => String(s ?? "");\n' >"$root/lib/esc.mjs"
run >/dev/null
out="$(run --check-bump "$base")"
expect "--check-bump still fails for a legacy carrier that has only a fragment" 1 $? "$out"
LAST_OUTPUT="$out"
assert_output_contains "--check-bump names the legacy carrier" "its copy plugins/beta/lib/esc.mjs changed"
if [[ "$out" != *"plugins/alpha/lib/esc.mjs changed"* ]]; then
  pass "--check-bump accepts a fragment-mode carrier's patch fragment as its bump"
else
  bad "--check-bump accepts a fragment-mode carrier's patch fragment as its bump" "$out"
fi
if [[ "$out" == *"Bump the version of every carrying plugin"* && "$out" != *"new-changelog-fragment.sh"* ]]; then
  pass "--check-bump tells only a legacy carrier to bump its version"
else
  bad "--check-bump tells only a legacy carrier to bump its version" "$out"
fi

# A fragment-mode carrier with no fragment is told to add one, not to bump.
git -C "$root" rm -q --cached .changes/alpha/sync-esc-0123abcd.md
rm "$root/.changes/alpha/sync-esc-0123abcd.md"
out="$(run --check-bump "$base")"
expect "--check-bump fails for a fragment-mode carrier with no fragment" 1 $? "$out"
LAST_OUTPUT="$out"
assert_output_contains "--check-bump names the fragment-mode carrier" "plugins/alpha/lib/esc.mjs changed vs $base but alpha, in fragment mode, has no fragment for it"
assert_output_contains "--check-bump gives one --carriers-of command when every fragment-mode carrier is stale" "scripts/new-changelog-fragment.sh --stdin --carriers-of lib/esc.mjs patch <<'EOF'"
assert_output_contains "--check-bump gives the fragment body" "- Shared \`esc.mjs\` synced (<link to the change>); no other change to this plugin."
assert_output_contains "--check-bump closes with the fragment instruction" "Add a patch fragment for every carrying plugin in fragment mode"
if [[ "$out" != *"plugins/alpha/.claude-plugin/plugin.json is still"* ]]; then
  pass "--check-bump does not tell a fragment-mode carrier to bump its manifest"
else
  bad "--check-bump does not tell a fragment-mode carrier to bump its manifest" "$out"
fi

# A fragment-mode carrier that already has its fragment is left out of the command.
printf 'alpha\nbeta\n' >"$root/scripts/fragment-plugins.txt"
out="$(run --check-bump "$base")"
expect "--check-bump fails while one fragment-mode carrier lacks a fragment" 1 $? "$out"
LAST_OUTPUT="$out"
assert_output_contains "--check-bump lists only the stale carrier" "scripts/new-changelog-fragment.sh --stdin alpha patch <<'EOF'"
if [[ "$out" != *"--carriers-of"* && "$out" != *"but beta, in fragment mode"* ]]; then
  pass "--check-bump does not ask the carrier with a fragment for another"
else
  bad "--check-bump does not ask the carrier with a fragment for another" "$out"
fi

# --- the executable bit follows the canonical, on regen and in --check ----------
fixture
printf '#!/usr/bin/env bash\necho hi\n' >"$root/lib/tool.sh"
printf 'lib/tool.sh plugins/alpha/scripts/tool.sh\n' >"$root/scripts/shared-copies.txt"
run >/dev/null
chmod +x "$root/lib/tool.sh"
out="$(run --check)"
expect "--check fails when a copy lacks the canonical's executable bit" 1 $? "$out"
LAST_OUTPUT="$out"
assert_output_contains "--check names the executable bit" "different executable bit"
run >/dev/null
if [[ -x "$root/plugins/alpha/scripts/tool.sh" ]]; then
  pass "regen gives an existing copy the canonical's executable bit"
else
  bad "regen gives an existing copy the canonical's executable bit" "not executable"
fi
chmod -x "$root/lib/tool.sh"
run >/dev/null
if [[ ! -x "$root/plugins/alpha/scripts/tool.sh" ]]; then
  pass "regen removes the executable bit the canonical dropped"
else
  bad "regen removes the executable bit the canonical dropped" "still executable"
fi

# --- a shebang stays on line one; the header follows it ------------------------
fixture
mkdir -p "$root/lib"
printf '#!/usr/bin/env bash\necho hi\n' >"$root/lib/tool.sh"
chmod +x "$root/lib/tool.sh"
printf 'lib/tool.sh plugins/alpha/scripts/tool.sh\n' >"$root/scripts/shared-copies.txt"
run >/dev/null
first="$(sed -n 1p "$root/plugins/alpha/scripts/tool.sh")"
second="$(sed -n 2p "$root/plugins/alpha/scripts/tool.sh")"
if [[ "$first" == '#!/usr/bin/env bash' && "$second" == '# GENERATED from lib/tool.sh by scripts/sync-shared-copies.sh. Do not edit this copy:' ]]; then
  pass "a shell copy keeps its shebang first and takes a # header"
else
  bad "a shell copy keeps its shebang first and takes a # header" "line1=$first line2=$second"
fi
if [[ -x "$root/plugins/alpha/scripts/tool.sh" ]]; then
  pass "a new copy takes the canonical's executable bit"
else
  bad "a new copy takes the canonical's executable bit" "not executable"
fi

# --- a Markdown copy takes an HTML-comment header, after any frontmatter --------
fixture
printf '# Title\n\nbody\n' >"$root/lib/plain.md"
printf -- '---\nkey: 1.0.0\n---\n\n# Title\n' >"$root/lib/front.md"
printf 'lib/plain.md plugins/alpha/ref/plain.md\nlib/front.md plugins/alpha/ref/front.md\n' >"$root/scripts/shared-copies.txt"
run >/dev/null
want=$'<!-- GENERATED from lib/plain.md by scripts/sync-shared-copies.sh. Do not edit this copy:\nedit the canonical source, then rerun the script. -->\n\n# Title\n\nbody'
if [[ "$(cat "$root/plugins/alpha/ref/plain.md")" == "$want" ]]; then
  pass "a Markdown copy without frontmatter opens with the header comment"
else
  bad "a Markdown copy without frontmatter opens with the header comment" "got: $(cat "$root/plugins/alpha/ref/plain.md")"
fi
want=$'---\nkey: 1.0.0\n---\n\n<!-- GENERATED from lib/front.md by scripts/sync-shared-copies.sh. Do not edit this copy:\nedit the canonical source, then rerun the script. -->\n\n# Title'
if [[ "$(cat "$root/plugins/alpha/ref/front.md")" == "$want" ]]; then
  pass "a Markdown copy keeps its frontmatter first and takes the header after it"
else
  bad "a Markdown copy keeps its frontmatter first and takes the header after it" "got: $(cat "$root/plugins/alpha/ref/front.md")"
fi
out="$(run --check)"
expect "--check passes on generated Markdown copies" 0 $? "$out"

# --- --print-manifest publishes one block per canonical ------------------------
fixture
printf 'lib/b.sh plugins/beta/hooks/b.sh\n' >>"$root/scripts/shared-copies.txt"
printf 'echo b\n' >"$root/lib/b.sh"
out="$(run --print-manifest)"
want=$'src\tlib/esc.mjs\ncopy\tplugins/alpha/lib/esc.mjs\ncopy\tplugins/beta/lib/esc.mjs\nsrc\tlib/b.sh\ncopy\tplugins/beta/hooks/b.sh'
if [[ "$out" == "$want" ]]; then
  pass "--print-manifest emits a src line then its copies, per canonical"
else
  bad "--print-manifest emits a src line then its copies, per canonical" "got: $out"
fi

# --- malformed registries and inputs exit 2 ------------------------------------
reject() { # <name> <needle> <registry line> [file to create]
  fixture
  if [[ -n "${4:-}" ]]; then
    mkdir -p "$root/${4%/*}" && printf 'x\n' >"$root/$4"
  fi
  printf '%s\n' "$3" >>"$root/scripts/shared-copies.txt"
  out="$(run --check)"
  expect "$1" 2 $? "$out"
  LAST_OUTPUT="$out"
  assert_output_contains "$1, with the reason" "$2"
}
reject "a line with one path is rejected" "want '<canonical> <copy>'" "lib/esc.mjs"
reject "a line with three paths is rejected" "want '<canonical> <copy>'" \
  "lib/esc.mjs plugins/alpha/a.mjs plugins/beta/b.mjs"
reject "a missing canonical is rejected" "canonical lib/nope.mjs does not exist" \
  "lib/nope.mjs plugins/alpha/lib/nope.mjs"
reject "a copy outside a plugin is rejected" "is not inside a plugin" "lib/esc.mjs scripts/esc.mjs"
reject "a copy registered twice is rejected" "registered twice" "lib/esc.mjs plugins/alpha/lib/esc.mjs"
reject "a canonical registered as a copy is rejected" "both a canonical and a copy" \
  "plugins/alpha/lib/esc.mjs plugins/gamma/lib/esc.mjs" plugins/alpha/lib/esc.mjs
reject "an extension with no known comment syntax is rejected" "no comment syntax known" \
  "lib/data.json plugins/alpha/data.json" lib/data.json

fixture
out="$(run --bogus)"
expect "an unknown flag exits 2" 2 $? "$out"

test_harness::report
