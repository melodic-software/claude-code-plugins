#!/usr/bin/env bash
# Unit tests for check-cross-plugin-source-drift.sh. Builds a tiny synthetic
# plugins/ tree per scenario in a temp dir (not the real repo tree, which is
# large and would make these tests slow and coupled to live content) and
# invokes the script against it directly -- the script's own
# `cd "$(dirname "$0")/.."` makes this work unmodified: copy it to
# <fixture>/scripts/ and it operates on <fixture>/plugins and
# <fixture>/scripts/cross-plugin-source-registry.txt.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-cross-plugin-source-drift.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

# new_fixture → prints the path to a fresh <tmp>/scripts + <tmp>/plugins tree
# with the script copied in, ready for callers to populate.
new_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/scripts" "$dir/plugins"
  cp "$SCRIPT" "$dir/scripts/check-cross-plugin-source-drift.sh"
  chmod +x "$dir/scripts/check-cross-plugin-source-drift.sh"
  printf '%s' "$dir"
}

# plugin_file <fixture> <plugin> <relpath> <content>
plugin_file() {
  local fixture="$1" plugin="$2" rel="$3" content="$4"
  mkdir -p "$(dirname "$fixture/plugins/$plugin/$rel")"
  printf '%s' "$content" >"$fixture/plugins/$plugin/$rel"
}

registry() {
  local fixture="$1"
  shift
  printf '%s\n' "$@" >"$fixture/scripts/cross-plugin-source-registry.txt"
}

run_check() (
  cd "$1" && bash scripts/check-cross-plugin-source-drift.sh --check
)

run_discover() (
  cd "$1" && bash scripts/check-cross-plugin-source-drift.sh
)

# --- an identical cluster that's registered passes -------------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/shared.sh "same content"
plugin_file "$f" beta hooks/shared.sh "same content"
registry "$f" "hooks/shared.sh"
if out="$(run_check "$f" 2>&1)"; then
  ok "registered identical cluster passes --check"
else
  fail "registered identical cluster should pass --check, got: $out"
fi
rm -rf "$f"

# --- an identical cluster with NO registry entry fails ----------------------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/new-shared.sh "same content"
plugin_file "$f" beta hooks/new-shared.sh "same content"
if out="$(run_check "$f" 2>&1)"; then
  fail "unregistered identical cluster should fail --check, got success: $out"
else
  if echo "$out" | grep -q "UNREGISTERED"; then
    ok "unregistered identical cluster fails --check with UNREGISTERED"
  else
    fail "expected UNREGISTERED in output, got: $out"
  fi
fi
rm -rf "$f"

# --- a registered cluster that has drifted (copies no longer match) fails --
f="$(new_fixture)"
plugin_file "$f" alpha hooks/shared.sh "version one"
plugin_file "$f" beta hooks/shared.sh "version two -- drifted"
registry "$f" "hooks/shared.sh"
if out="$(run_check "$f" 2>&1)"; then
  fail "drifted registered cluster should fail --check, got success: $out"
else
  if echo "$out" | grep -q "DRIFTED"; then
    ok "drifted registered cluster fails --check with DRIFTED"
  else
    fail "expected DRIFTED in output, got: $out"
  fi
fi
rm -rf "$f"

# --- a registered cluster that dropped below 2 copies fails as stale -------
f="$(new_fixture)"
plugin_file "$f" alpha hooks/shared.sh "only one copy left"
registry "$f" "hooks/shared.sh"
if out="$(run_check "$f" 2>&1)"; then
  fail "registry entry with <2 copies should fail --check, got success: $out"
else
  if echo "$out" | grep -q "REGISTRY STALE"; then
    ok "registry entry with <2 copies fails --check with REGISTRY STALE"
  else
    fail "expected REGISTRY STALE in output, got: $out"
  fi
fi
rm -rf "$f"

# --- files that legitimately differ per plugin are never flagged -----------
f="$(new_fixture)"
plugin_file "$f" alpha SKILL.md "alpha's own content"
plugin_file "$f" beta SKILL.md "beta's own, totally different"
plugin_file "$f" alpha README.md "alpha readme"
plugin_file "$f" beta README.md "beta readme"
if out="$(run_check "$f" 2>&1)"; then
  ok "per-plugin-by-design files (SKILL.md, README.md) never flagged"
else
  fail "expected --check to pass with no shared-copy candidates, got: $out"
fi
rm -rf "$f"

# --- discover mode lists both IDENTICAL and DIFFERS clusters, with [registered] tag
f="$(new_fixture)"
plugin_file "$f" alpha hooks/shared.sh "same"
plugin_file "$f" beta hooks/shared.sh "same"
plugin_file "$f" alpha reference/per-plugin.md "alpha version"
plugin_file "$f" beta reference/per-plugin.md "beta version"
registry "$f" "hooks/shared.sh"
out="$(run_discover "$f" 2>&1)"
if echo "$out" | grep -q "IDENTICAL.*hooks/shared.sh.*\[registered\]"; then
  ok "discover tags a registered identical cluster"
else
  fail "expected discover to tag hooks/shared.sh as IDENTICAL + [registered], got: $out"
fi
if echo "$out" | grep -q "DIFFERS.*reference/per-plugin.md"; then
  ok "discover lists a differing cluster without failing"
else
  fail "expected discover to list reference/per-plugin.md as DIFFERS, got: $out"
fi
rm -rf "$f"

# --- a single plugin carrying a file is not a cluster (no 2+ occurrence) ---
f="$(new_fixture)"
plugin_file "$f" alpha hooks/only-here.sh "content"
if out="$(run_check "$f" 2>&1)"; then
  ok "a file carried by only one plugin is never treated as a cluster"
else
  fail "single-plugin file should not trigger --check failure, got: $out"
fi
rm -rf "$f"

# --- a cluster path containing a space iterates ONCE, not once per word ----
#
# Pre-#3376 discover mode iterated an UNQUOTED command substitution, so every
# cluster key was word-split on IFS whitespace and glob-expanded against the
# working directory; and the cluster accumulator was space-joined, so
# load_cluster split each entry's path apart again and handed sha256sum a
# truncated name, which is fatal under this script's `set -e`. A space-bearing
# path therefore iterated wrongly with no error signal, in the one mode whose
# job is showing a human the cluster inventory.
f="$(new_fixture)"
plugin_file "$f" alpha "hooks/shared file.sh" "same"
plugin_file "$f" beta "hooks/shared file.sh" "same"
registry "$f" "hooks/shared file.sh"
if out="$(run_discover "$f" 2>&1)"; then
  hits="$(grep -c 'shared file\.sh' <<<"$out" || true)"
  if [[ "$hits" == "1" ]] &&
    grep -q 'IDENTICAL.*hooks/shared file\.sh  (plugins: alpha beta) \[registered\]' <<<"$out"; then
    ok "discover lists a space-bearing cluster path exactly once, naming both plugins"
  else
    fail "expected ONE IDENTICAL line for 'hooks/shared file.sh' naming alpha and beta (saw $hits), got: $out"
  fi
else
  fail "discover should exit 0 on a space-bearing cluster path, got: $out"
fi
if out="$(run_check "$f" 2>&1)"; then
  ok "--check accepts a registered identical space-bearing cluster"
else
  fail "--check should pass for a registered identical space-bearing cluster, got: $out"
fi
rm -rf "$f"

# --- discover on a tree with NO clusters at all ----------------------------
#
# The empty-array edge the #3376 fix has to get right, and the one the obvious
# rewrite gets wrong: `printf '%s\n'` with no arguments still prints one blank
# line, so `mapfile -t < <(printf '%s\n' "${!cluster_status[@]}" | sort)` hands
# the loop a single EMPTY key, which dies on `${cluster_entries[]}` under
# `set -u`. The old unquoted `$(...)` was accidentally safe here, so a fix that
# only addressed word-splitting would trade one silent bug for a loud one.
f="$(new_fixture)"
plugin_file "$f" alpha hooks/only-here.sh "content"
if out="$(run_discover "$f" 2>&1)"; then
  if [[ -z "$out" ]]; then
    ok "discover on a cluster-free tree exits 0 and prints nothing"
  else
    fail "discover on a cluster-free tree should print nothing, got: $out"
  fi
else
  fail "discover on a cluster-free tree should exit 0, got: $out"
fi
rm -rf "$f"

# --- production registry: every cluster documents its enforcement path (#2404) -
REGISTRY="$SELF_DIR/cross-plugin-source-registry.txt"
if [[ ! -f "$REGISTRY" ]]; then
  fail "production registry missing at $REGISTRY"
else
  bad="$(awk '
    /^[[:space:]]*#/ { block = block $0 "\n"; next }
    /^[[:space:]]*$/ { next }
    {
      if (block !~ /Dedicated check:/ && block !~ /No dedicated check/) {
        print $0 " (missing Dedicated check / No dedicated check annotation)"
      } else if (block ~ /No dedicated check/ && block !~ /Canonical copy:/) {
        print $0 " (No dedicated check without Canonical copy)"
      }
      block = ""
    }
  ' "$REGISTRY")"
  if [[ -z "$bad" ]]; then
    ok "production registry documents enforcement for every cluster"
  else
    fail "registry policy gaps:${bad}"
  fi
fi

test_harness::report
