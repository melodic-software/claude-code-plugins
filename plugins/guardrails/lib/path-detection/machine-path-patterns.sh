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
#
# Right boundary: the child-segment class itself. Each body requires at least
# one child segment past its root — a bare root (the home or checkout-parent
# directory with no child) never matches — but the child needs NO trailing
# separator: the class excludes whitespace and the double quote, so a match
# ends at the segment's natural value boundary (EOL, whitespace, quote, or
# the next separator). A mandatory trailing separator was the original design
# and inverted detection both ways: a real bare value at end of line
# ("root = <drive>:/Dev/GitHub") has no trailing separator and was MISSED,
# while prose satisfied the requirement anyway — the old space-permitting
# segment class greedily consumed words until a later slash appeared on the
# same line, flagging comments instead of values. Excluding whitespace from
# the class is what makes dropping the separator prose-safe: a phrase like
# "/Users/ for details" cannot match because at least one non-space child
# character must follow the root.
HPP_WIN_USER_BODY='[A-Za-z]:(/|\\\\?)Users(/|\\\\?)[^\\$%<{~"[:space:]/]+(~[0-9]+)?'
HPP_MACOS_USER_BODY='/Users/[^\\$%<{~"[:space:]/]+'
HPP_LINUX_USER_BODY='/home/[^\\$%<{~"[:space:]/]+'
# The checkout-parent segment is drive-letter-anchored, so broadening it beyond
# `repos` to the other common checkout-root names stays false-positive-safe —
# only a genuine `X:\<root>\<child>\` absolute path matches, never prose. Both
# lowercase and Capitalized spellings are listed (a regex character class such
# as `[Rr]` would leave a partial token the docs typos-gate flags). A consumer's
# OWN checkout root is already caught by the driver's project-root literal scan;
# this generic body catches references to OTHER machines' checkout paths in
# written content.
HPP_WIN_REPO_BODY='[A-Za-z]:(/|\\\\?)(repos|Repos|projects|Projects|dev|Dev)(/|\\\\?)[^\\$%<{~"[:space:]/]+(~[0-9]+)?'
HPP_ESCAPED_WIN_REPO_BODY='[A-Za-z]:\\\\(repos|Repos|projects|Projects|dev|Dev)\\\\[^\\$%<{~"[:space:]/]+(~[0-9]+)?'
