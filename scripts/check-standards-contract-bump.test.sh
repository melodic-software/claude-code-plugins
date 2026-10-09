#!/usr/bin/env bash
# Unit tests for check-standards-contract-bump.sh. Builds a tiny synthetic repo
# tree per scenario in a temp dir, git-initialized for the base ref, with the
# generator and a registry that names two carrying plugins, and invokes the
# gate against it directly.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-standards-contract-bump.sh"
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
f=""

CANONICAL="docs/conventions/standards/README.md"
CHANGELOG="docs/conventions/standards/CHANGELOG.md"
SCHEMA="docs/conventions/standards/standards.schema.json"

canonical_v1() {
  printf -- '---\nstandards-contract: 1.0.0\n---\n\n# Standards Convention\n\ncontract body v1\n'
}
canonical_v1_edited() {
  printf -- '---\nstandards-contract: 1.0.0\n---\n\n# Standards Convention\n\ncontract body v1 EDITED without a version change\n'
}
canonical_v1_1() {
  printf -- '---\nstandards-contract: 1.1.0\n---\n\n# Standards Convention\n\ncontract body v1.1\n'
}
changelog_v1() {
  printf -- '# Changelog\n\n## 1.0.0 — 2026-07-17\n\n- initial\n'
}
changelog_v1_1() {
  printf -- '# Changelog\n\n## 1.1.0 — 2026-07-18\n\n- additive\n\n## 1.0.0 — 2026-07-17\n\n- initial\n'
}

# new_fixture <out-var> → fresh tree with the gate and the generator copied in.
new_fixture() {
  fixture_tree::build "$1" --sut "$SCRIPT" --sut sync-shared-copies.sh --plugins || return 1
  mkdir -p "${!1}/docs/conventions/standards"
}

# carrying_plugin <fixture> <plugin> <version> → manifest and registry entry.
carrying_plugin() {
  local fixture="$1" plugin="$2" version="$3"
  mkdir -p "$fixture/plugins/$plugin/reference" "$fixture/plugins/$plugin/.claude-plugin"
  printf '{"name":"%s","version":"%s"}\n' "$plugin" "$version" \
    >"$fixture/plugins/$plugin/.claude-plugin/plugin.json"
  printf '%s plugins/%s/reference/standards-contract.md\n' "$CANONICAL" "$plugin" \
    >>"$fixture/scripts/shared-copies.txt"
}

# base_fixture → the starting state most cases mutate from: the v1 canonical,
# its changelog, and two carrying plugins at 0.1.0 with generated copies.
base_fixture() { # <out-var>
  local dir
  new_fixture "$1" || return 1
  dir="${!1}"
  canonical_v1 >"$dir/$CANONICAL"
  changelog_v1 >"$dir/$CHANGELOG"
  : >"$dir/scripts/shared-copies.txt"
  carrying_plugin "$dir" planning 0.1.0
  carrying_plugin "$dir" review 0.1.0
  (cd "$dir" && bash scripts/sync-shared-copies.sh >/dev/null)
}

# git_fixture <fixture> → init repo + commit everything as the base ref; prints base sha
git_fixture() {
  local fixture="$1"
  # On refusal (e.g. TMPDIR inside the checkout) stop before add/commit can
  # resolve to the enclosing real repository.
  git_init_test_repo "$fixture" || return 1
  git -C "$fixture" add -A
  git -C "$fixture" commit -qm base
  git -C "$fixture" rev-parse HEAD
}

run_gate() (
  local fixture="$1"
  shift
  cd "$fixture" && bash scripts/check-standards-contract-bump.sh "$@"
)

# regen <fixture> → rewrite the generated copies after a canonical edit.
regen() { (cd "$1" && bash scripts/sync-shared-copies.sh >/dev/null); }

# bump <fixture> <plugin> <version>
bump() { printf '{"name":"%s","version":"%s"}\n' "$2" "$3" >"$1/plugins/$2/.claude-plugin/plugin.json"; }

# --- canonical unchanged vs base → pass ---------------------------------------
base_fixture f
base="$(git_fixture "$f")"
if out="$(run_gate "$f" "$base" 2>&1)"; then
  ok "the gate passes when the contract is unchanged"
else
  fail "the gate should pass when the contract is unchanged, got: $out"
fi
rm -rf "$f"

# --- a base ref that does not resolve is a usage error ------------------------
base_fixture f
git_fixture "$f" >/dev/null
out="$(run_gate "$f" no-such-ref 2>&1)"
rc=$?
if [[ "$rc" -eq 2 ]]; then
  ok "the gate exits 2 on a base ref that does not resolve"
else
  fail "the gate should exit 2 on a bad base ref, got rc=$rc: $out"
fi
rm -rf "$f"

# --- a missing base ref is a usage error ---------------------------------------
base_fixture f
git_fixture "$f" >/dev/null
out="$(run_gate "$f" 2>&1)"
rc=$?
if [[ "$rc" -eq 2 && "$out" == *usage:* ]]; then
  ok "the gate exits 2 with a usage line when no base ref is given"
else
  fail "the gate should exit 2 with usage when no base ref is given, got rc=$rc: $out"
fi
rm -rf "$f"

# --- change + frontmatter bump + changelog heading + manifest bumps → pass ----
base_fixture f
base="$(git_fixture "$f")"
canonical_v1_1 >"$f/$CANONICAL"
changelog_v1_1 >"$f/$CHANGELOG"
regen "$f"
bump "$f" planning 0.2.0
bump "$f" review 0.2.0
if out="$(run_gate "$f" "$base" 2>&1)"; then
  ok "the gate passes on a fully-bumped contract change"
else
  fail "the gate should pass when frontmatter, changelog, and manifests all moved, got: $out"
fi

# --- a fragment stands in for a carrier's bump only in fragment mode ----------
printf 'planning\n' >"$f/scripts/fragment-plugins.txt"
bump "$f" planning 0.1.0
bump "$f" review 0.1.0
for plugin in planning review; do
  mkdir -p "$f/.changes/$plugin"
  printf -- '---\nbump: patch\n---\n\n### Changed\n\n- Contract synced.\n' >"$f/.changes/$plugin/sync-0123abcd.md"
done
git -C "$f" add .changes
out="$(run_gate "$f" "$base" 2>&1)"
if [[ $? -eq 1 && "$out" == *"plugins/review/.claude-plugin/plugin.json is still 0.1.0"* && "$out" != *plugins/planning/* ]]; then
  ok "the gate accepts a fragment-mode carrier's fragment and still requires the legacy carrier's bump"
else
  fail "expected only review reported stale, got: $out"
fi
if [[ "$out" == *"and bump every carrying plugin."* && "$out" != *"new-changelog-fragment.sh"* ]]; then
  ok "a legacy carrier alone gets the unchanged bump message"
else
  fail "expected the legacy bump message and no fragment command, got: $out"
fi
# A fragment-mode carrier with no fragment is told to add one, not to bump.
git -C "$f" rm -q --cached .changes/planning/sync-0123abcd.md
rm "$f/.changes/planning/sync-0123abcd.md"
out="$(run_gate "$f" "$base" 2>&1)"
if [[ $? -eq 1 && "$out" == *"STALE VERSION: $CANONICAL changed vs $base but planning, in fragment mode, has no fragment for it"* &&
  "$out" == *"Run scripts/new-changelog-fragment.sh planning patch."* &&
  "$out" == *"bump every carrying plugin not in fragment mode."* &&
  "$out" == *"A carrying plugin in fragment mode takes a patch fragment instead"* &&
  "$out" != *"plugins/planning/.claude-plugin/plugin.json is still"* ]]; then
  ok "a fragment-mode carrier with no fragment is told to run new-changelog-fragment.sh"
else
  fail "expected the fragment command for planning, got: $out"
fi
rm -rf "$f"

# --- carrying plugin manifest not bumped → fail -------------------------------
base_fixture f
base="$(git_fixture "$f")"
canonical_v1_1 >"$f/$CANONICAL"
changelog_v1_1 >"$f/$CHANGELOG"
regen "$f"
bump "$f" planning 0.2.0 # review not bumped
if out="$(run_gate "$f" "$base" 2>&1)"; then
  fail "the gate should fail when a carrying plugin kept its version, got success: $out"
elif [[ "$out" == *"STALE VERSION: $CANONICAL changed vs $base but plugins/review/.claude-plugin/plugin.json"* ]]; then
  ok "the gate fails an unbumped carrying plugin with STALE VERSION"
  if [[ "$out" == *"no change to this plugin's reference."* ]]; then
    ok "the gate prescribes the sync-only CHANGELOG line"
  else
    fail "expected the sync-only CHANGELOG line, got: $out"
  fi
else
  fail "expected STALE VERSION naming the review manifest, got: $out"
fi
rm -rf "$f"

# --- content changed but frontmatter semver did not → fail --------------------
base_fixture f
base="$(git_fixture "$f")"
canonical_v1_edited >"$f/$CANONICAL"
changelog_v1_1 >"$f/$CHANGELOG"
regen "$f"
bump "$f" planning 0.2.0
bump "$f" review 0.2.0
if out="$(run_gate "$f" "$base" 2>&1)"; then
  fail "the gate should fail when the standards-contract semver did not change, got success: $out"
elif [[ "$out" == *"STALE CONTRACT VERSION"* ]]; then
  ok "the gate fails an unbumped standards-contract frontmatter with STALE CONTRACT VERSION"
else
  fail "expected STALE CONTRACT VERSION in output, got: $out"
fi
rm -rf "$f"

# --- content changed but the changelog gained no entry → fail -----------------
base_fixture f
base="$(git_fixture "$f")"
canonical_v1_1 >"$f/$CANONICAL"
regen "$f"
bump "$f" planning 0.2.0
bump "$f" review 0.2.0
if out="$(run_gate "$f" "$base" 2>&1)"; then
  fail "the gate should fail when the changelog gained no new heading, got success: $out"
elif [[ "$out" == *"STALE CHANGELOG"* ]]; then
  ok "the gate fails a heading-less changelog with STALE CHANGELOG"
else
  fail "expected STALE CHANGELOG in output, got: $out"
fi
rm -rf "$f"

# --- compound failure: all three stale conditions report ----------------------
base_fixture f
base="$(git_fixture "$f")"
canonical_v1_edited >"$f/$CANONICAL"       # content moved, frontmatter did not
printf -- '# Changelog\n' >"$f/$CHANGELOG" # entry for the head version removed
regen "$f"
if out="$(run_gate "$f" "$base" 2>&1)"; then
  fail "the gate should fail when every bump is missing, got success: $out"
elif [[ "$out" == *"STALE CONTRACT VERSION"* && "$out" == *"STALE CHANGELOG"* && "$out" == *"STALE VERSION"* ]]; then
  ok "the gate reports all three stale conditions before exiting"
else
  fail "expected all three STALE messages in one run, got: $out"
fi
rm -rf "$f"

# --- a schema-only change still requires the bumps ----------------------------
base_fixture f
printf '{"title":"standards concern file v1"}\n' >"$f/$SCHEMA"
base="$(git_fixture "$f")"
printf '{"title":"standards concern file v1","description":"schema-only change"}\n' >"$f/$SCHEMA"
if out="$(run_gate "$f" "$base" 2>&1)"; then
  fail "the gate should fail on an unbumped schema-only change, got success: $out"
elif [[ "$out" == *"STALE CONTRACT VERSION"* && "$out" == *"STALE VERSION"* ]]; then
  ok "the gate treats the schema as contract surface (a schema-only change needs the bumps)"
else
  fail "expected STALE CONTRACT VERSION and STALE VERSION on a schema-only change, got: $out"
fi
rm -rf "$f"

# --- a plugin absent at the base is new: skipped, not stale -------------------
new_fixture f
canonical_v1 >"$f/$CANONICAL"
changelog_v1 >"$f/$CHANGELOG"
: >"$f/scripts/shared-copies.txt"
carrying_plugin "$f" planning 0.1.0
regen "$f"
base="$(git_fixture "$f")"
canonical_v1_1 >"$f/$CANONICAL"
changelog_v1_1 >"$f/$CHANGELOG"
carrying_plugin "$f" review 0.1.0 # new plugin, absent at base
regen "$f"
bump "$f" planning 0.2.0
if out="$(run_gate "$f" "$base" 2>&1)"; then
  ok "the gate skips a plugin that did not exist at the base ref"
else
  fail "the gate should skip a base-absent plugin, got: $out"
fi
rm -rf "$f"

test_harness::report
