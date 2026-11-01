# shellcheck shell=bash
# Digest computations behind the digest pins of tests/interview-defenses.test.sh. Sourced, never
# executed: the test sources it to grade its pins, and scripts/repin-digests.sh sources it to
# compute a pin's new digest from the files alone, without running the test. Each digest function
# prints a sha256 hex digest, or NO-DIGEST-TOOL when no digest tool is available.

# sha256 of stdin. GNU coreutils ships sha256sum; a BSD userland (macOS) ships
# `shasum -a 256` instead. Probe both: a missing digest tool would otherwise silently
# vacate every section and case pin, which is the one failure mode the suite may never have.
sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    echo "NO-DIGEST-TOOL"
  fi
}

# sha256 of jq's stdout. A Windows jq writes through a text-mode stdout, so every record
# it prints ends CRLF where the same jq on Linux ends LF, which moves every case and
# roster digest on that host alone, for a file nobody touched. The only literal CR
# jq can emit is a line terminator (a CR inside a JSON string is escaped `\r`), so
# dropping it is the identity wherever stdout is already LF. Deliberately NOT folded into
# `sha256_stdin`: `file_digest` hashes a fixture's own bytes and must keep hashing them raw.
sha256_jq_stdin() {
  tr -d '\r' | sha256_stdin
}

# section_digest <file> <open heading line> <close heading line>
# sha256 of everything strictly BETWEEN the two heading lines, each matched as a WHOLE
# LINE. Whole-line matching is load-bearing, not tidiness: a prefix match let a crafted
# heading MOVE the region's own boundary. Appending
# `### Step 2 — Drive the frontier-rounds loop, and how to read Step 1.5 before it` plus an
# override paragraph as the last thing inside Step 1.5 closed the region early under a
# prefix match, so the override fell outside the hash and the suite stayed green. Under
# whole-line matching that crafted heading is just another line inside the region, and the
# digest changes. `pin_section` additionally requires each boundary to occur EXACTLY ONCE,
# so a duplicated heading cannot truncate the region either.
#
# `close` is a builtin in mawk (and `open` reads badly beside it), so the awk variables are
# named h_open / h_close: assigning to a builtin name is a run-time error, not a warning,
# and mawk is the default awk on Debian-family runners.
section_digest() {
  awk -v h_open="$2" -v h_close="$3" '
    $0 == h_open { inside = 1; next }
    $0 == h_close { inside = 0 }
    inside { print }
  ' "$1" | sha256_stdin
}

# frontmatter_digest <file>
# sha256 of the YAML frontmatter: everything between the opening `---` on line 1 and the
# closing `---`.
frontmatter_digest() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside { print }' "$1" | sha256_stdin
}

# case_digest <evals.json> <case name>
# sha256 of the named eval case's normalized JSON (keys sorted, one line).
case_digest() {
  jq -S -c --arg n "$2" '.evals[] | select(.name == $n)' "$1" | sha256_jq_stdin
}

# case_set_digest <evals.json>
# sha256 of the sorted `id:name` roster of every eval case.
case_set_digest() {
  jq -r '.evals[] | "\(.id):\(.name)"' "$1" | sort | sha256_jq_stdin
}

# file_digest <file>
# sha256 of the file's own bytes.
file_digest() {
  sha256_stdin <"$1"
}
