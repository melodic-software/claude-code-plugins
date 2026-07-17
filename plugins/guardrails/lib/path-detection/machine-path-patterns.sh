# shellcheck shell=bash
# The bodies are consumed by the sourcing drivers, never in this file itself —
# SC2034 "appears unused" is a false positive for a define-only library.
# shellcheck disable=SC2034
# Machine-specific path detection — shared per-OS regex BODIES, define-only.
#
# No functions, no env reads, no I/O, no exit calls. A scan driver sources
# this file and adds its own wrapping: boundary prefixes, exclusion pipe
# stages, exemptions, and exit-code mapping stay driver-owned.
#
# POSIX ERE only (grep -E) — NO grep -P: macOS BSD grep lacks it entirely,
# and bash =~ delegates to the platform regex library, so non-POSIX
# extensions would not behave identically on Linux CI and Git Bash.
#
# DEFINE single-quoted, EXPAND double-quoted ("$HPP_…"): a double-quoted
# definition would collapse the escaped-repo body's doubled backslashes and
# silently change what grep matches.
#
# The 3 Windows bodies match the separator as single-backslash, forward-slash,
# OR doubled-backslash (JSON-escaped) at EVERY position — (/|\\\\?) is fwd-slash
# OR one-or-two backslashes — and accept an 8.3 short-name segment that ends
# ~<digit> (e.g. ALICE~1) via the optional (~[0-9]+). These are the two shapes
# a script-written temp path evaded with. The negative class still excludes a
# bare ~ so a tilde-shorthand segment stays clean. macOS/Linux bodies are NOT
# widened: no 8.3 / escaped-JSON analogue exists there, so widening is pure
# false-positive risk.
#
# The Windows bodies are self-anchored by [A-Za-z]:. The slash-rooted
# macOS/Linux bodies need a driver-side boundary prefix so a substring like
# "doc/Users/guide" inside a longer word does not false-match.
HPP_WIN_USER_BODY='[A-Za-z]:(/|\\\\?)Users(/|\\\\?)[^/\\$<{~]+(~[0-9]+)?(/|\\\\?)'
HPP_MACOS_USER_BODY='/Users/[^/$<{~]+/'
HPP_LINUX_USER_BODY='/home/[^/$<{~]+/'
HPP_WIN_REPO_BODY='[A-Za-z]:(/|\\\\?)repos(/|\\\\?)[^/\\$<{~]+(~[0-9]+)?(/|\\\\?)'
# SC1003 false positive: the trailing \\\\ is a deliberate literal-backslash ERE
# body (a JSON-escaped path separator), not a botched single-quote escape.
# shellcheck disable=SC1003
HPP_ESCAPED_WIN_REPO_BODY='[A-Za-z]:\\\\repos\\\\[^\\$<{~]+(~[0-9]+)?\\\\'
