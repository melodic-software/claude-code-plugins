#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'EOF'
conflict-scan.sh — mark cross-surface conflict candidate PAIRS in given files.

Usage: conflict-scan.sh [--count|--help] FILE...

  FILE...    print one candidate row (fileA:lineA|fileB:lineB|entity|flags); exit 0
  --count    print the integer candidate-pair count only; exit 0
  --help     this message

Advisory — always exits 0 (candidates never fail the run). Requires awk and
sort (exit 2 when either is absent). Seeds the mechanical tier of the
audit-instructions cross-surface conflict pass; the lane refines every candidate
against reference/conflict-criteria.md. A pair is a candidate, never a finding.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

for tool in awk sort; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: $tool required" >&2
    exit 2
  fi
done

mode="report"
if [[ "${1:-}" == "--count" ]]; then
  mode="count"
  shift
fi

BACKTICK=$(printf '\140')
ENTITY_ERE="[A-Z][a-z]+([A-Z][a-z]*)+|${BACKTICK}[A-Z][a-z]+${BACKTICK}"
PROHIBIT_ALT='never|do not|don[^a-z]?t|must ?not|mustn[^a-z]?t|should ?not|shouldn[^a-z]?t'
PROHIBIT_ERE="[^a-z](${PROHIBIT_ALT})[^a-z]"
MANDATE_ALT='must|always|mandator(y|ily)|require[ds]?|shall|use|present|ask'
MANDATE_ERE="[^a-z](${MANDATE_ALT})[^a-z]"
EXCEPTION_ERE='[^a-z](unless|except|only when|only if|other than)[^a-z]'
GATED_ERE='(user_config|user config|[^a-z]opt-?in[^a-z]|[^a-z]opted in[^a-z])'
CONDITIONAL_ERE='[^a-z](only when|only if|unless|requires?|gated|enabled|is on|when set)[^a-z]'
BOUNDARY_ERE='([.;!?] |[^a-z],? *(but|whereas|though|although|yet)[^a-z]|, while[^a-z])'
COORD_ERE="[^a-z],? *and +(${PROHIBIT_ALT}|${MANDATE_ALT})[^a-z]"
COORD_HEAD_ERE='[^a-z],? *and +'

WINDOW_CHARS="${CONFLICT_SCAN_WINDOW:-60}"

mapfile -t rows < <(
  for file in "$@"; do
    [[ -f "$file" ]] && printf '%s\n' "$file"
  done | awk -v w="$WINDOW_CHARS" -v entpat="$ENTITY_ERE" -v prohibit="$PROHIBIT_ERE" \
    -v mandate="$MANDATE_ERE" -v exception="$EXCEPTION_ERE" -v gated="$GATED_ERE" \
    -v conditional="$CONDITIONAL_ERE" -v bnd="$BOUNDARY_ERE" -v coord="$COORD_ERE" \
    -v coordhead="$COORD_HEAD_ERE" '
    # Leading half of a window: resume after the LAST boundary before the entity.
    # Contrastives and sentence marks are consumed whole; a coordinated directive
    # is consumed only up to its coordinator, leaving its polarity token in the
    # returned text because that token is what governs this entity.
    function cut_lead(t,   off, tail, cs, hl) {
      off = 0; tail = t
      while (match(tail, bnd)) {
        off += RSTART + RLENGTH - 1
        tail = substr(tail, RSTART + RLENGTH)
      }
      if (off > 0) t = substr(t, off + 1)
      off = 0; tail = t
      while (match(tail, coord)) {
        cs = RSTART
        match(substr(tail, cs), coordhead)
        hl = RLENGTH
        off += cs + hl - 1
        tail = substr(tail, cs + hl)
      }
      if (off > 0) t = substr(t, off + 1)
      return t
    }
    function classify(file, lineno, ent, prewindow, postwindow, window,   pol, exc, key) {
      # Every test here reads `window`, which the caller builds from the
      # sentence-bounded halves plus the mention itself. Nothing classifies an
      # entity from a neighboring sentence: a gate, a polarity token or an
      # exception clause governs the entity only if it shares a sentence with it.
      #
      # An opt-in gate arbitrates the pair away, but only when it reads as a
      # condition rather than as the subject being described.
      if (window ~ gated && window ~ conditional) return
      # A prohibition governing the entity sits either before it ("never use X")
      # or after it ("X must not be used"), inside the same sentence either way.
      # Beyond a sentence break a prohibition almost always governs a different
      # object ("… via `X` once. Do not gate per repo").
      if (prewindow ~ prohibit || postwindow ~ prohibit) pol = "prohibit"
      else if (window ~ mandate) pol = "mandate"
      else return
      exc = (window ~ exception) ? "yes" : "no"
      key = pol SUBSEP ent SUBSEP file SUBSEP lineno SUBSEP exc
      if (key in seen) return
      seen[key] = 1
      n = ++count[pol, ent]
      rec[pol, ent, n] = file SUBSEP lineno SUBSEP exc
      entities[ent] = 1
    }
    {
      # Filenames arrive on stdin so one awk process reads every file.
      file = $0
      while ((getline line < file) > 0) {
        lineno++
        gsub(/\t/, " ", line)
        pad = " " tolower(line) " "
        rest = line
        base = 0
        while (match(rest, entpat)) {
          # RSTART/RLENGTH are global and any later match() clobbers them, so the
          # loop advance is computed from copies taken before anything else runs.
          mstart = RSTART
          mlen = RLENGTH
          s = base + mstart
          e = s + mlen - 1
          ent = substr(rest, mstart, mlen)
          gsub(/`/, "", ent)
          ws = s - w
          if (ws < 1) ws = 1
          # Both windows stop at a boundary so only a polarity token in the SAME
          # clause as the entity classifies it: trailing text at its FIRST
          # boundary, leading text after its LAST.
          #
          # A boundary is either a sentence-ending mark followed by a space, or a
          # CONTRASTIVE conjunction with an optional preceding comma. The space
          # matters: a bare mark also occurs inside tokens this corpus is full of
          # (a dotted config path, a version number). The contrastive list matters
          # too, and is deliberately not "any comma": one sentence can carry two
          # entities at opposite polarity ("always use X but never use Y"), while
          # ordinary comma-separated prose keeps its polarity throughout, so
          # cutting on every comma would drop the token that governs the entity.
          #
          # A coordinated second directive bounds the window too, but
          # asymmetrically: a contrastive carries no polarity of its own and is
          # consumed whole, whereas the coord pattern matches THROUGH the second
          # polarity token, so a leading window resumes after the coordinator
          # alone and keeps that token. See cut_lead.
          post = substr(pad, e + 2, w)
          if (match(post, bnd)) post = substr(post, 1, RSTART - 1)
          if (match(post, coord)) post = substr(post, 1, RSTART - 1)
          pre = cut_lead(substr(pad, ws + 1, s - ws))
          # The full window is rebuilt from the bounded halves plus the mention,
          # so mandate, gate and exception tests see the same sentence the
          # polarity tests do rather than the raw span.
          classify(file, lineno, ent, \
            " " pre " ", \
            " " post " ", \
            " " pre " " tolower(ent) " " post " ")
          base = e
          rest = substr(rest, mstart + mlen)
        }
      }
      close(file)
      lineno = 0
    }
    END {
      for (ent in entities) {
        for (i = 1; i <= count["mandate", ent]; i++) {
          split(rec["mandate", ent, i], a, SUBSEP)
          for (j = 1; j <= count["prohibit", ent]; j++) {
            split(rec["prohibit", ent, j], b, SUBSEP)
            # Cross-surface by definition: a pair inside one file is not a
            # finding here.
            if (a[1] == b[1]) continue
            flags = ""
            if (a[3] == "yes") flags = "exception-A"
            if (b[3] == "yes") flags = (flags == "") ? "exception-B" : flags "+exception-B"
            if (flags == "") flags = "-"
            print a[1] ":" a[2] "|" b[1] ":" b[2] "|" ent "|" flags
          }
        }
      }
    }
  ' | sort -u
)

if [[ "$mode" == "count" ]]; then
  printf '%s\n' "${#rows[@]}"
  exit 0
fi

if [[ "${#rows[@]}" -eq 0 ]]; then
  echo "No conflict candidates found."
else
  printf '%s\n' "${rows[@]}"
fi
exit 0
