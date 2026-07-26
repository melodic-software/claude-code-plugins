#!/usr/bin/env bash
# Resolve a single scalar value from a topic-docs concern file the way every
# consuming plugin must: quote-aware, comment-safe, whitespace-trimmed,
# trailing-slash-normalized — with a caller-supplied fallback for the case the
# key is absent.
#
# Why this exists: the topic-docs seam (`.claude/topic-docs.yaml` `memory_dir`
# and siblings) was parsed inline at each consumer with a naive
# `val="${val%%#*}"` FIRST — which truncates a legitimately-quoted value that
# contains `#` (`"a#b"` -> `"a`) and strips comments before quotes are resolved.
# Centralizing the parse fixes it once for every consumer instead of re-forking
# the same bug per site.
#
# SINGLE SOURCE OF TRUTH: lib/parse-concern-value.sh at the marketplace repo
# root. The copies materialized into consuming plugins exist because installed
# plugins are cache-isolated and must be self-contained — never edit a copy.
# Edit the source and run scripts/sync-parse-concern-value.sh; CI rejects
# drifted copies.
#
# Usage:
#   parse-concern-value.sh <concern-file> <key> [fallback]
#
#   <concern-file>  path to the concern file (e.g. .claude/topic-docs.yaml)
#   <key>           scalar key to read (e.g. memory_dir)
#   [fallback]      value to emit when the key is absent/empty — the caller's
#                   already-resolved rung-2 location (a save-point convention
#                   declared in CLAUDE.md / .claude/rules). Prose is an
#                   inference source, not a runtime authority, so the caller
#                   infers it and passes it in; this script never reads prose.
#
# Output: the resolved value on stdout, or empty when nothing resolves (the
# caller applies the documented default, e.g. `.work`). Always exits 0 for a
# well-formed invocation.
#
# Resolution order (mirrors the topic-docs contract's non-interactive degrade):
#   1. key present and non-empty in the concern file -> its parsed value
#   2. else the caller-supplied fallback (if non-empty)
#   3. else empty  (interactive/inferred-layout rungs are the caller's job)
set -uo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
parse-concern-value.sh — resolve a scalar value from a topic-docs concern file.

Usage:
  parse-concern-value.sh <concern-file> <key> [fallback]

Reads <key> from <concern-file>, quote-aware and comment-safe: a `#` inside a
quoted value is preserved; a trailing ` # comment` on an unquoted value is
stripped; surrounding quotes are peeled, surrounding whitespace trimmed, and a
trailing slash normalized. Emits [fallback] when the key is absent/empty, or
nothing when neither resolves. Always exits 0 for a well-formed invocation.
EOF
  exit 0
fi

concern_file="${1:-}"
key="${2:-}"
fallback="${3:-}"

if [[ -z "$concern_file" || -z "$key" ]]; then
  echo "parse-concern-value: usage: parse-concern-value.sh <concern-file> <key> [fallback]" >&2
  exit 2
fi

# Peel a matching surrounding quote pair, strip a comment (quote-aware), trim
# surrounding whitespace, normalize a trailing slash — in THAT order. Quote
# resolution comes first so a `#` inside quotes is never mistaken for a comment.
strip_value() {
  local raw="$1" val
  raw="${raw//$'\r'/}" # CRLF guard: Git Bash leaves a trailing \r on read lines
  # Trim leading whitespace (sed's [[:space:]]* already ate the post-colon run,
  # but a re-used helper must not assume its caller's extraction).
  raw="${raw#"${raw%%[![:space:]]*}"}"

  case "$raw" in
  '"'*)
    # Double-quoted: value is the span up to the closing quote; anything after
    # it (e.g. a trailing comment) is discarded. `#` inside is literal.
    val="${raw#\"}"
    val="${val%%\"*}"
    ;;
  "'"*)
    val="${raw#\'}"
    val="${val%%\'*}"
    ;;
  *)
    # Unquoted: strip a comment at a `#` that starts the value (a comment-only
    # value like `# use default` — YAML-null, must resolve to empty so the
    # fallback fires) or is preceded by whitespace (` #…`); a `#` adjacent to a
    # non-space char (`a#b`, `.work/#t`) is part of the scalar. Then trim
    # trailing whitespace.
    val="$raw"
    val="$(printf '%s' "$val" | sed -e 's/^#.*$//' -e 's/[[:space:]]#.*$//')"
    val="${val%"${val##*[![:space:]]}"}"
    ;;
  esac

  val="${val%/}" # normalize a single trailing slash
  printf '%s' "$val"
}

resolved=""
if [[ -f "$concern_file" ]]; then
  # sed anchors on the literal key; keys are `[a-z_]+` identifiers, no metachars.
  # YAML permits whitespace before the `:` (`memory_dir : .work`) and permits a
  # root block mapping to sit at a uniform indent, so neither shape may be read
  # as "key absent" — a consumer that silently took its fallback over a key the
  # file really declares would act on a value the repo never chose. An
  # unindented key is preferred, so a nested key of the same name cannot outrank
  # the top-level one.
  raw_line=$(sed -n "s/^${key}[[:space:]]*:[[:space:]]*//p" "$concern_file" | head -1)
  if [[ -z "$raw_line" ]]; then
    raw_line=$(sed -n "s/^[[:space:]]\{1,\}${key}[[:space:]]*:[[:space:]]*//p" "$concern_file" | head -1)
  fi
  if [[ -n "$raw_line" ]]; then
    resolved=$(strip_value "$raw_line")
  fi
fi

if [[ -z "$resolved" ]]; then
  resolved="$fallback"
fi

printf '%s\n' "$resolved"
