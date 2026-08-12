#!/usr/bin/env bash
# automode-block-lint.sh — findings over the `autoMode` block: what a customized
# section discards, what contradicts itself, and what can never fire.
#
# This lane is about the CLASSIFIER's rule lists, not the permission-rule plane.
# Its four sections (environment, allow, soft_deny, hard_deny) are natural-language
# entries an LLM reads, so the checks here are the mechanical ones only: what a
# section omits, what two entries say about the same subject, and what an earlier
# hard_deny already forecloses. `claude auto-mode critique` owns the semantic
# judgment and is surfaced by --critique rather than reimplemented.
#
# Reading the CLI is where this gets hard, and every defect below was MEASURED on
# 2.1.225 rather than guessed at:
#
#   1. `claude auto-mode config` emits raw control characters inside JSON string
#      values. jq and Python json.loads both reject it; exit status is still 0.
#      The offending byte is a raw line feed inside a string, so no line-oriented
#      POSIX filter can tell it from the pretty-printer's structural newlines --
#      that is why this lane needs a non-strict parser and why pure POSIX was
#      tested and rejected.
#   2. `defaults --label <x>` OMITS a non-matching key entirely rather than
#      returning an empty list. A reader that expects an empty array sees a
#      KeyError, not a clean "no entries".
#   3. Entry labels carry a bracketed annotation BEFORE the colon
#      (`Git Destructive [named+specifics ...]: ...`), so a label split at the
#      first `:` truncates. Split at the first `[` when one precedes the colon.
#   4. Exit status is never trustworthy: `critique` returned 0 on a run that
#      produced no output at all. A run that produced nothing usable says so and
#      never reports success.
#
# Prerequisites:
#   python3  REQUIRED FOR AN OPTIONAL FEATURE -- this lane only. Absent: warn
#            visibly, skip the lane, exit 0. Every other stage of the skill is
#            unaffected. Node is an equally capable host and is deliberately not
#            adopted: a second optional runtime doubles the declaration surface
#            for one feature.
#   claude   the same, for reading the live config.
#
# Test seams (no test may invoke the real CLI or read the operator's config):
#   AUTOMODE_CONFIG_FIXTURE    parse this file instead of `claude auto-mode config`
#   AUTOMODE_DEFAULTS_FIXTURE  parse this file instead of `claude auto-mode defaults`
#   AUTOMODE_CRITIQUE_FIXTURE  read this file instead of running `critique`
#
# Output:
#   finding <severity> [<check>] <section> <detail>
#   BLOCK-NOTE: <text>
#   automode summary findings=<n> sections=<n>
#
#   C4-defaults      a customized section that omits "$defaults"
#   C2b-contradiction  the same subject allowed and denied
#   C3-shadowed      an entry an earlier hard_deny already forecloses
#
# Usage:
#   automode-block-lint.sh [--critique] [--help]

set -uo pipefail

usage() {
  cat <<'EOF'
automode-block-lint.sh — lint the autoMode classifier block.

Usage: automode-block-lint.sh [--critique|--help]

  (no arg)    the mechanical checks: $defaults omissions, contradictions, shadowing
  --critique  additionally surface `claude auto-mode critique`, wrapped in
              truncation and empty-output detection
  --help      this message

Requires python3 and claude for this lane only; absent, it prints a visible skip
notice and exits 0 so the rest of the skill still runs. Reads only — it never
runs 'claude auto-mode reset' and never writes any settings file.
EOF
}

critique=0
case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
--critique) critique=1 ;;
"") ;;
*)
  echo "ERROR: unknown argument '$1'" >&2
  exit 2
  ;;
esac

note() { printf 'BLOCK-NOTE: %s\n' "$1"; }

# The lane is optional as a whole: a missing runtime degrades it visibly and
# leaves every other stage of the skill intact. That is the documented contract
# for an optional feature, and the alternative -- failing the run -- would make
# one lane's prerequisite everyone's problem.
PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then
    PY="$candidate"
    break
  fi
done
if [[ -z "$PY" ]]; then
  note "autoMode block lane SKIPPED: python3 is not on PATH. This lane needs a non-strict JSON parser because 'claude auto-mode config' emits raw control characters inside string values, which no line-oriented POSIX filter can repair. Every other stage of this skill is unaffected."
  echo "automode summary findings=0 sections=0 status=skipped"
  exit 0
fi

CONFIG_FIXTURE="${AUTOMODE_CONFIG_FIXTURE:-}"
DEFAULTS_FIXTURE="${AUTOMODE_DEFAULTS_FIXTURE:-}"

if [[ -z "$CONFIG_FIXTURE" || -z "$DEFAULTS_FIXTURE" ]] && ! command -v claude >/dev/null 2>&1; then
  note "autoMode block lane SKIPPED: 'claude' is not on PATH, so the classifier's own rule lists cannot be read. Every other stage of this skill is unaffected."
  echo "automode summary findings=0 sections=0 status=skipped"
  exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/automode-lint.XXXXXX")" || {
  echo "ERROR: cannot create a scratch directory" >&2
  exit 2
}
trap 'rm -rf "$tmp"' EXIT

# Exit status is never trusted (measured: critique returned 0 producing nothing),
# so each capture is judged by whether it yielded usable content.
capture() {
  # capture <outfile> <fixture-or-empty> <subcommand>
  local out="$1" fixture="$2" sub="$3"
  if [[ -n "$fixture" ]]; then
    [[ -r "$fixture" ]] || return 1
    cat "$fixture" >"$out" 2>/dev/null
  else
    claude auto-mode "$sub" >"$out" 2>/dev/null
  fi
  [[ -s "$out" ]]
}

if ! capture "$tmp/config.json" "$CONFIG_FIXTURE" config; then
  note "autoMode block lane produced no usable output: 'claude auto-mode config' returned nothing readable. This is NOT a clean bill -- the block was not read. Exit status from that command is known to be 0 even when it produces nothing, so it is deliberately not consulted here."
  echo "automode summary findings=0 sections=0 status=unavailable"
  exit 0
fi
if ! capture "$tmp/defaults.json" "$DEFAULTS_FIXTURE" defaults; then
  note "autoMode block lane produced no usable output: 'claude auto-mode defaults' returned nothing readable, so a \$defaults omission cannot be judged."
  echo "automode summary findings=0 sections=0 status=unavailable"
  exit 0
fi

"$PY" - "$tmp/config.json" "$tmp/defaults.json" <<'PYEOF'
import json
import re
import sys

# strict=False is the whole reason this lane needs a real parser: the measured
# defect is a raw line feed INSIDE a JSON string value, spliced in from
# user-authored entries without re-escaping. jq rejects it outright.
def load(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        raw = fh.read()
    try:
        return json.loads(raw, strict=False), None
    except json.JSONDecodeError as exc:
        return None, str(exc)


config, config_err = load(sys.argv[1])
defaults, defaults_err = load(sys.argv[2])

if config is None or defaults is None:
    print(
        "BLOCK-NOTE: autoMode block lane could not parse the classifier output even "
        "with a non-strict parser (%s). Reporting it as unread rather than as an "
        "empty block." % (config_err or defaults_err)
    )
    print("automode summary findings=0 sections=0 status=unparseable")
    raise SystemExit(0)

# Parsing is not enough: the payload must also be the SHAPE this lane expects.
# A valid JSON array or string parses cleanly and then explodes on the first
# .get() -- which exited 0 with a traceback and no summary line, so a caller
# grepping status= saw nothing and a success exit. In the one lane whose whole
# premise is that the CLI's output cannot be trusted, that is the failure the
# header contract exists to forbid.
for _payload, _name in ((config, "config"), (defaults, "defaults")):
    if not isinstance(_payload, dict):
        print(
            "BLOCK-NOTE: autoMode block lane read the %s payload but it is a %s, not "
            "an object with the four rule sections. Reporting it as unusable rather "
            "than as an empty block." % (_name, type(_payload).__name__)
        )
        print("automode summary findings=0 sections=0 status=unexpected-shape")
        raise SystemExit(0)

SECTIONS = ("environment", "allow", "soft_deny", "hard_deny")
findings = 0


def finding(severity, check, section, detail):
    global findings
    print("finding %s [%s] %s %s" % (severity, check, section, detail))
    findings += 1


def entries(block, name):
    # A non-matching key is OMITTED, not returned empty -- measured on
    # `defaults --label`. Treating a missing key as an error would report a
    # defect that is the documented shape of a section with no entries.
    value = block.get(name)
    return value if isinstance(value, list) else []


def label_of(entry):
    # Labels carry a bracketed annotation BEFORE the colon:
    #   "Git Destructive [named+specifics ...]: Force pushing ..."
    # Splitting at the first ':' truncates the label mid-annotation, so cut at
    # the first '[' when one precedes the colon.
    if not isinstance(entry, str):
        return ""
    colon = entry.find(":")
    bracket = entry.find("[")
    cut = colon if colon != -1 else len(entry)
    if bracket != -1 and (colon == -1 or bracket < colon):
        cut = bracket
    return entry[:cut].strip()


def subject_of(entry):
    return re.sub(r"[^a-z0-9]+", " ", label_of(entry).lower()).strip()


present = [s for s in SECTIONS if s in config]

# --- C4: a customized section that discards the built-in list ----------------
#
# "$defaults" is the token that keeps the shipped rule list in a section the
# operator has added to. Omitting it does not merge -- it REPLACES, so the
# built-in entries are gone. Naming how many are discarded is the finding: "you
# dropped 65 soft_deny rules" is actionable where "missing $defaults" is not.
for section in SECTIONS:
    custom = entries(config, section)
    if not custom:
        continue
    if any(isinstance(e, str) and e.strip() == "$defaults" for e in custom):
        continue
    built_in = entries(defaults, section)
    if not built_in:
        continue
    # A section that still carries every built-in entry verbatim was never
    # customized -- the CLI expands "$defaults" in its own output, so an
    # expanded section and an omitted one look identical from here except for
    # what is missing. Firing on the expanded case would report a discard that
    # did not happen, on a section the operator never touched.
    missing = [e for e in built_in if e not in custom]
    if not missing:
        continue
    finding(
        "error",
        "C4-defaults",
        section,
        '"$defaults" is absent and %d of the %d built-in %s entries are gone with it: '
        "a customized section REPLACES the built-in list rather than adding to it. "
        'Add "$defaults" to keep them. First missing: %s'
        % (len(missing), len(built_in), section, label_of(missing[0]) or "(unlabelled)"),
    )

# --- C2b: the same subject allowed and denied --------------------------------
#
# Compared by LABEL SUBJECT, not by body text: the bodies are prose an LLM
# reads, and no mechanical comparison of prose is defensible. A shared label
# across an allow and a deny section is a mechanical signal, and the finding
# says which two sections to reconcile rather than which one is right.
by_subject = {}
for section in ("allow", "soft_deny", "hard_deny"):
    for entry in entries(config, section):
        subject = subject_of(entry)
        if not subject:
            continue
        by_subject.setdefault(subject, set()).add(section)

for subject, sections in sorted(by_subject.items()):
    if "allow" in sections and (sections & {"soft_deny", "hard_deny"}):
        other = sorted(sections - {"allow"})
        finding(
            "warning",
            "C2b-contradiction",
            "allow",
            'the subject "%s" appears in both allow and %s -- the classifier reads '
            "both, so decide which one governs rather than leaving it to resolve them"
            % (subject, "/".join(other)),
        )

# --- C3: an entry an earlier hard_deny already forecloses --------------------
#
# hard_deny is the section that cannot be overridden, so an allow or soft_deny
# on the same subject can never fire. This is SEMANTIC shadowing inside the
# classifier block -- a different surface from the syntactic non-matching the
# permission-plane lint reports, with different inputs.
hard_subjects = {subject_of(e) for e in entries(config, "hard_deny") if subject_of(e)}
for section in ("allow", "soft_deny"):
    for entry in entries(config, section):
        subject = subject_of(entry)
        if subject and subject in hard_subjects:
            finding(
                "warning",
                "C3-shadowed",
                section,
                'the subject "%s" is already in hard_deny, which cannot be overridden, '
                "so this entry can never change an outcome" % subject,
            )

print("automode summary findings=%d sections=%d status=read" % (findings, len(present)))
PYEOF

[[ "$critique" == 1 ]] || exit 0

# --- critique: surfaced, wrapped, never replaced ------------------------------
#
# It owns the semantic judgment (clarity, completeness, conflicts, actionability)
# and this skill does not attempt it. What is added is honesty about the wrapper:
# measured across three consecutive runs on one unchanged config, the output was
# truncated mid-sentence twice and empty once, exiting 0 every time.
crit="$tmp/critique.txt"
# The entry-diff sibling prices its spawn before making it; this one did not,
# and an unpriced spawn is exactly the surprise the opt-in flag exists to avoid.
# Printed before the capture call so it is true whether or not a fixture short-
# circuits the run.
if [[ -z "${AUTOMODE_CRITIQUE_FIXTURE:-}" ]]; then
  cat >&2 <<'EOF'
CRITIQUE COST NOTICE — nothing has been spawned yet.
  --critique runs `claude auto-mode critique`, a real session on this machine.
  That costs API tokens and leaves the state any session leaves behind. It reads
  your autoMode block and writes no settings file.
EOF
fi
if ! capture "$crit" "${AUTOMODE_CRITIQUE_FIXTURE:-}" critique; then
  note "critique returned nothing; run it yourself. Measured on 2.1.225: three consecutive runs on one unchanged config produced 3032 bytes, 991 bytes, and no output at all, each exiting 0 -- so an empty result here means nothing about your rules."
  exit 0
fi

echo "--- claude auto-mode critique ---"
cat "$crit"
echo "--- end critique ---"

# Truncation cannot be detected from exit status, so it is detected from the
# text: a complete critique ends on sentence-final punctuation.
last_char="$(tr -d '[:space:]' <"$crit" | tail -c 1)"
case "$last_char" in
. | '!' | '?' | ')' | ']' | '`') ;;
*)
  note "The critique above appears TRUNCATED -- it does not end on sentence-final punctuation, and truncation is not detectable from exit status (measured: 0 on every run, including an empty one). Treat it as partial and run 'claude auto-mode critique' yourself for the full text."
  ;;
esac
