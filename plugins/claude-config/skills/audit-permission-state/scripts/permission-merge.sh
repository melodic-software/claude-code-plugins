#!/usr/bin/env bash
# permission-merge.sh — effective permission set with per-rule provenance, from
# permission-state.sh's scope records.
#
# Permission rules "merge across scopes rather than override", so every scope's
# rules are live at once and there is no same-kind winner to elect. What a rule
# text CAN lose is its kind: "deny rules from any scope are evaluated before
# allow rules", in both directions — a user deny blocks a project allow and a
# project deny blocks a user allow. That is the only election this script makes,
# and every merged rule says which mechanic put it where it is.
#
# Input: permission-state.sh records, on stdin. With no piped input the sibling
# reader is run directly, and its exit status is propagated (a reader that could
# not run must not become an empty merge).
#
# Output (merge section; the input records pass through above it unless
# --merge-only):
#   CAVEAT: <text>                                                what bounds the claim
#   effective <kind> scopes=<a,b> precedence_basis=<token> <rule> one per live rule
#   inert <kind> scopes=<a,b> outranked_by=<kind> <rule>          one per beaten entry
#   inert <kind> scopes=<a,b> removed_by=deny@<tool> <rule>       whole-tool deny removal
#   inert <kind> scopes=<a,b> outranked_by=ask@<tool> <rule>      whole-tool ask removal
#
#   token  uncontested | merged-across-scopes | evaluation-order
#          | evaluation-order+merged-across-scopes
#
# `scopes=` lists contributors in the reader's emission order. That is NOT a
# precedence claim: the rules merge, so no contributor outranks another.
# reference/criteria.md maps every token to the sentence it follows from.
#
# Prerequisites: none beyond POSIX text tools. Invoked with no piped input it
# inherits the reader's jq requirement, and its exit 2.
#
# Usage:
#   permission-state.sh | permission-merge.sh
#   permission-merge.sh [--merge-only|--help]

set -uo pipefail

usage() {
  cat <<'EOF'
permission-merge.sh — compute the effective allow/ask/deny set with provenance.

Usage: permission-state.sh | permission-merge.sh [--merge-only]
       permission-merge.sh [--merge-only|--help]

  (no arg)      the input records, then the merge section
  --merge-only  the merge section alone
  --help        this message

Records: "effective <kind> scopes=<a,b> precedence_basis=<token> <rule text>",
"inert <kind> scopes=<a,b> outranked_by=<kind> <rule text>",
"inert <kind> scopes=<a,b> removed_by=deny@<tool> <rule text>",
"inert <kind> scopes=<a,b> outranked_by=ask@<tool> <rule text>", and "CAVEAT: <text>".

With --merge-only the reader's own NOTE records are dropped, including the one
stating that server-managed settings have no local path. Read both sections when
the question is what the machine's permission state actually is.

Reads only. Exits 2 when the input carries no scope records at all.
EOF
}

passthrough=1
case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
--merge-only) passthrough=0 ;;
"") ;;
*)
  echo "ERROR: unknown argument '$1'" >&2
  exit 2
  ;;
esac

if [[ -t 0 ]]; then
  STATE_SCRIPT="${BASH_SOURCE[0]%/*}/permission-state.sh"
  if [[ ! -r "$STATE_SCRIPT" ]]; then
    echo "ERROR: cannot read $STATE_SCRIPT — nothing to merge" >&2
    exit 2
  fi
  records="$(bash "$STATE_SCRIPT")" || exit $?
else
  records="$(cat)"
fi

# A reader that failed and a machine with no settings look identical downstream,
# and the second is a lie the first can tell. No scope records at all is an
# error, never an empty merge — and the output is held until that is known, so a
# failed run never emits a half-written merge section ahead of its own error.
merged="$(printf '%s\n' "$records" | awk -v passthrough="$passthrough" '
function text_of(start,   i, s) {
  s = $start
  for (i = start + 1; i <= NF; i++) s = s " " $i
  return s
}

# The tool token is everything before the first "(" — "Bash(rm *)" is a rule
# about Bash. A rule that IS its bare tool token is the whole-tool form, and
# whole-tool rules reach every call of that tool, which is decidable here with
# no pattern matcher.
function tool_of(t,   p) { p = index(t, "("); return p ? substr(t, 1, p - 1) : t }

{ if (passthrough) print }

$1 == "rule" {
  kind = $4
  scope = $2
  text = text_of(5)
  if (!(text in text_seen)) { text_seen[text] = 1; text_order[++n_texts] = text }
  tool[text] = tool_of(text)
  if (text == tool[text]) {
    # A bare tool name removes the tool from the model context entirely, so the
    # model never sees it. Every other rule naming that tool is then moot,
    # whatever its kind. EndConversation is the documented exception: a deny
    # rule cannot remove it while any other tool remains.
    if (kind == "deny" && text != "EndConversation" && !(text in bare_deny)) {
      bare_deny[text] = 1
      bare_order[++n_bare] = "deny " text
    }
    # A whole-tool ask prompts for every call of the tool, and a matching ask
    # rule prompts even when a more specific allow rule also matches the same
    # call — so scoped allows for that tool never take effect.
    if (kind == "ask" && !(text in bare_ask)) {
      bare_ask[text] = 1
      bare_order[++n_bare] = "ask " text
    }
  }
  k = text SUBSEP kind
  kind_seen[k] = 1
  ks = k SUBSEP scope
  if (!(ks in scope_seen)) {
    scope_seen[ks] = 1
    scopes[k] = (k in scopes) ? scopes[k] "," scope : scope
    n_scopes[k]++
  }
  next
}

$1 == "NOTE:" { next }

NF >= 3 {
  n_surfaces++
  status = $3
  if (status == "skipped" || status == "unreadable" || status == "invalid-json") {
    unread[++n_unread] = $1 " " $2 " (" status ") " $4
  }
}

END {
  if (n_surfaces == 0) exit 2

  print "CAVEAT: the command-line scope (--settings, --allowedTools, --disallowedTools) ranks above local, project and user settings and has no file to read. This merge is the effective set the settings FILES define."
  print "CAVEAT: rules are compared by exact text. A broad deny blocks calls that also match a narrower allow, so a narrow allow shadowed only by a broader deny pattern is still reported effective here — the error direction is over-reporting allow."
  for (i = 1; i <= n_unread; i++)
    print "CAVEAT: " unread[i] " contributed no rules because it could not be read, not because it is empty. The merged set below is incomplete by that surface."

  for (i = 1; i <= n_bare; i++) {
    split(bare_order[i], b, " ")
    if (b[1] == "deny")
      print "NOTE: deny " b[2] " names the whole tool, which removes " b[2] " from the model context entirely. Every other rule naming that tool is reported inert below — including denies, which are moot rather than weakened."
    else
      print "NOTE: ask " b[2] " names the whole tool, so every " b[2] " call prompts and no scoped allow for it can take effect."
  }

  split("deny ask allow", kinds, " ")

  for (t = 1; t <= n_texts; t++) {
    text = text_order[t]
    tk = tool[text]
    scoped = (text != tk)
    win = ""
    n_kinds = 0
    for (i = 1; i <= 3; i++) {
      if ((text SUBSEP kinds[i]) in kind_seen) {
        n_kinds++
        if (win == "") win = kinds[i]
      }
    }
    if (scoped && (tk in bare_deny)) {
      for (i = 1; i <= 3; i++) {
        k = text SUBSEP kinds[i]
        if (k in kind_seen) print "inert " kinds[i] " scopes=" scopes[k] " removed_by=deny@" tk " " text
      }
      continue
    }
    if (scoped && win == "allow" && (tk in bare_ask)) {
      print "inert allow scopes=" scopes[text SUBSEP "allow"] " outranked_by=ask@" tk " " text
      continue
    }

    wk = text SUBSEP win
    basis = ""
    if (n_kinds > 1) basis = "evaluation-order"
    if (n_scopes[wk] > 1) basis = (basis == "") ? "merged-across-scopes" : basis "+merged-across-scopes"
    if (basis == "") basis = "uncontested"
    print "effective " win " scopes=" scopes[wk] " precedence_basis=" basis " " text
    for (i = 1; i <= 3; i++) {
      if (kinds[i] == win) continue
      k = text SUBSEP kinds[i]
      if (k in kind_seen) print "inert " kinds[i] " scopes=" scopes[k] " outranked_by=" win " " text
    }
  }
}
')" || {
  echo "ERROR: no scope records on input — permission-merge.sh will not report an effective set it never read" >&2
  exit 2
}

printf '%s\n' "$merged"
