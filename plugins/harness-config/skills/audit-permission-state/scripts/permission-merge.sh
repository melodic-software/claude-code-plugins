#!/usr/bin/env bash
# permission-merge.sh — effective permission set with per-rule provenance, from
# permission-state.sh's scope records.
#
# Permission rules "merge across scopes rather than override", so every scope's
# rules, except `!` carve-outs, are live at once and there is no same-kind
# winner to elect. What a rule
# text CAN lose is its kind: "deny rules from any scope are evaluated before
# allow rules", in both directions — a user deny blocks a project allow and a
# project deny blocks a user allow. That is the only election this script makes,
# and every merged rule says which mechanic put it where it is.
#
# A deny or ask Read/Edit rule whose pattern starts with "!" is not merged: we
# treat it as a carve-out scoped to its own source, one settings file, with
# --disallowedTools a source of its own. Pointer: when the carve-out scope
# matters, fetch https://code.claude.com/docs/en/permissions#read-and-edit live.
# As of: 2026-10-10. Recheck trigger: that section changes what a carve-out
# reaches. A bare "!" pattern is a known gap: the changelog (v2.1.269) changed
# how it is handled and that section does not cover it, so the merge reports
# it, tagged bare, and models no effect.
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
#   carveout <kind> source=<scope>:<surface> [bare] <rule>        one per ! Read/Edit rule
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
"carveout <kind> source=<scope>:<surface> [bare] <rule text>", and "CAVEAT: <text>".

With --merge-only the reader's own NOTE records are dropped, including the one
stating where the server-managed settings cache lives. Read both sections when
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

# The site every merged-rule `inert` record is emitted from; an ignored `!`
# carve-out is printed in END, which increments the same count. Three call sites below
# report a beaten rule, and each one must also increment the summary count: a
# count that tracked only one of them printed beaten=0 beside an inert record on
# screen, leaving a reader unable to reconcile the summary with the records it
# summarizes. Keeping the emission and the count together makes that structural.
function emit_inert(ikind, itext, tag) {
  print "inert " ikind " scopes=" scopes[itext SUBSEP ikind] " " tag " " itext
  n_inert++
}

# conf records ALWAYS pass through, including under --merge-only. They are not
# presentation, they are input a downstream stage needs to be correct: the entry
# diff reads autoMode.classifyAllShell from them, and without it a narrow shell
# rule that auto mode actually suspends is reported as kept. Dropping them made
# a documented flag combination silently invert the answer, with no warning.
{ if (passthrough || $1 == "conf") print }

$1 == "rule" {
  kind = $4
  scope = $2
  text = text_of(5)
  # A deny or ask Read/Edit rule whose pattern starts with "!" is a carve-out,
  # not a rule: it narrows the earlier rules of its own settings file and no
  # other, so merging it across scopes would claim a reach it does not have.
  # It is held per source (scope plus surface) and reported on its own.
  if ((kind == "deny" || kind == "ask") && text ~ /^(Read|Edit)\(!/) {
    carve_src[++n_carve] = scope ":" $3
    carve_scope[n_carve] = scope
    carve_kind[n_carve] = kind
    carve_text[n_carve] = text
    next
  }
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
    # The guard is n_scopes, NOT `(k in scopes)`. mawk creates the element named
    # by an assignment target before it evaluates the right-hand side, so
    # `scopes[k] = (k in scopes) ? ... : scope` sees its own subscript already
    # present and takes the append branch on the FIRST contributor -- emitting
    # `scopes=,project` for a rule that exists in one scope. gawk defers the
    # creation and the same line reads correctly there, which is what let this
    # survive: the bug is invisible on a gawk box and wrong on every mawk one.
    # n_scopes is a plain counter, so reading it uninitialized is 0 under both.
    scopes[k] = (n_scopes[k] > 0) ? scopes[k] "," scope : scope
    n_scopes[k]++
  }
  next
}

# conf records are configuration inventory for downstream consumers (the entry
# diff), not rules and not surfaces — pass through, merge nothing, except the
# managed permission-rule lock, which changes which file rules are in effect.
$1 == "conf" {
  if ($2 == "managed" && $4 == "allowManagedPermissionRulesOnly" && $5 == "true")
    managed_rules_only = 1
  next
}
$1 == "NOTE:" { next }

function managed_scopes_only(list,   n, i, parts, out) {
  n = split(list, parts, ",")
  out = ""
  for (i = 1; i <= n; i++) {
    if (parts[i] == "managed") out = (out == "" ? parts[i] : out "," parts[i])
  }
  return out
}

NF >= 3 {
  n_surfaces++
  status = $3
  if (status == "skipped" || status == "unreadable" || status == "invalid-json") {
    unread[++n_unread] = $1 " " $2 " (" status ") " $4
    unread_status[n_unread] = status
    unread_scope[n_unread] = $1
    unread_surface[n_unread] = $2
  }
}

END {
  if (n_surfaces == 0) exit 2

  if (managed_rules_only)
    print "CAVEAT: the command-line scope under allowManagedPermissionRulesOnly: --allowedTools is ignored, and allow, ask, and deny rules in user, project, local, and --settings files are ignored. --disallowedTools and the session deny and ask rules still apply, including after a settings reload (v2.1.257+). This merge keeps managed-file rules only."
  else
    print "CAVEAT: the command-line scope (--settings, --allowedTools, --disallowedTools) ranks above local, project and user settings and has no file to read. This merge is the effective set the settings FILES define. When a managed file sets allowManagedPermissionRulesOnly, --allowedTools is ignored and --disallowedTools plus session deny and ask rules are kept across reloads (v2.1.257+); that lock is applied here only when a managed conf record carries it."
  print "CAVEAT: rules are compared by exact text. A broad deny blocks calls that also match a narrower allow, so a narrow allow shadowed only by a broader deny pattern is still reported effective here — the error direction is over-reporting allow."
  for (i = 1; i <= n_unread; i++) {
    extra = " The merged set below is incomplete by that surface."
    if (unread_status[i] == "invalid-json" && unread_scope[i] == "managed" && (unread_surface[i] == "file" || unread_surface[i] == "plist" || unread_surface[i] == "registry" || index(unread_surface[i], "dropin-file:") == 1))
      extra = " From Claude Code v2.1.259 a managed settings file, drop-in, MDM plist, or HKLM Settings value that cannot be parsed refuses startup (exit 1) and names the source. A malformed HKCU value does not refuse startup; it is a notice in /status. This is not silent non-enforcement." extra
    else if (unread_status[i] == "invalid-json")
      extra = " An interactive session shows a Settings Error for a user, project, or local file; after continue, /status names the file. A -p run skips the broken file. An unparsable user settings.json pauses the retention sweep and warns in /status unless managed settings supply cleanupPeriodDays." extra
    print "CAVEAT: " unread[i] " contributed no rules because it could not be read, not because it is empty." extra
  }

  if (managed_rules_only) {
    for (i = 1; i <= n_bare; i++) {
      split(bare_order[i], b, " ")
      bk = b[2] SUBSEP b[1]
      if (managed_scopes_only(scopes[bk]) == "") {
        if (b[1] == "deny") delete bare_deny[b[2]]
        else delete bare_ask[b[2]]
      }
    }
  }

  for (i = 1; i <= n_bare; i++) {
    split(bare_order[i], b, " ")
    if (b[1] == "deny" && !(b[2] in bare_deny)) continue
    if (b[1] == "ask" && !(b[2] in bare_ask)) continue
    if (b[1] == "deny")
      print "NOTE: deny " b[2] " names the whole tool, which removes " b[2] " from the model context entirely. Every other rule naming that tool is reported inert below — including denies, which are moot rather than weakened."
    else
      print "NOTE: ask " b[2] " names the whole tool, so every " b[2] " call prompts and no scoped allow for it can take effect."
  }

  split("deny ask allow", kinds, " ")

  for (t = 1; t <= n_texts; t++) {
    text = text_order[t]
    tk = tool[text]
    if (managed_rules_only) {
      kept_any = 0
      for (i = 1; i <= 3; i++) {
        ik = text SUBSEP kinds[i]
        if (!((ik) in kind_seen)) continue
        kept = managed_scopes_only(scopes[ik])
        if (kept == "") {
          emit_inert(kinds[i], text, "ignored_by=allowManagedPermissionRulesOnly")
          delete kind_seen[ik]
        } else {
          scopes[ik] = kept
          n_scopes[ik] = 1
          kept_any = 1
        }
      }
      if (!kept_any) continue
    }
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
        if ((text SUBSEP kinds[i]) in kind_seen) emit_inert(kinds[i], text, "removed_by=deny@" tk)
      }
      continue
    }
    if (scoped && win == "allow" && (tk in bare_ask)) {
      emit_inert("allow", text, "outranked_by=ask@" tk)
      continue
    }

    wk = text SUBSEP win
    basis = ""
    if (n_kinds > 1) basis = "evaluation-order"
    if (n_scopes[wk] > 1) basis = (basis == "") ? "merged-across-scopes" : basis "+merged-across-scopes"
    if (basis == "") basis = "uncontested"
    print "effective " win " scopes=" scopes[wk] " precedence_basis=" basis " " text
    n_effective[win]++
    for (i = 1; i <= 3; i++) {
      if (kinds[i] == win) continue
      if ((text SUBSEP kinds[i]) in kind_seen) emit_inert(kinds[i], text, "outranked_by=" win)
    }
  }

  # Carve-outs come after the merged rules because they qualify rules of their
  # own source only. A bare "!" pattern is reported like any other carve-out;
  # what Claude Code does with one is a known gap this merge does not model.
  if (n_carve > 0)
    print "CAVEAT: a carveout record narrows only the earlier rules of the same kind in its own source (one settings file; --disallowedTools is a source of its own, with no file to read). It never reopens a path that a rule from another source blocks, and this merge does not compute which paths it reopens. A carve-out whose pattern is a bare ! is a known gap: its effect is not modeled."
  for (i = 1; i <= n_carve; i++) {
    if (managed_rules_only && carve_scope[i] != "managed") {
      print "inert " carve_kind[i] " scopes=" carve_scope[i] " ignored_by=allowManagedPermissionRulesOnly " carve_text[i]
      n_inert++
      continue
    }
    print "carveout " carve_kind[i] " source=" carve_src[i] (carve_text[i] ~ /^(Read|Edit)\(!\)$/ ? " bare" : "") " " carve_text[i]
  }

  # Every other stage ends in a summary. Without one, a machine with no rules
  # emits two caveats and then nothing, and absence of output has to be read as a
  # result rather than stated as one.
  # "merge summary", not "effective summary": `effective ` is an established
  # record prefix that consumers count, and a summary sharing it would be read as
  # a rule with no precedence_basis. Every sibling stage uses `<stage> summary`.
  # The beaten-rule count is deliberately NOT named `inert=`: `inert` is a record
  # prefix consumers match on, and a summary field carrying that substring turns
  # "no rule was beaten" into a false positive for "an inert record exists".
  print "merge summary allow=" n_effective["allow"] + 0 " ask=" n_effective["ask"] + 0 " deny=" n_effective["deny"] + 0 " beaten=" n_inert + 0 " status=" (n_unread > 0 ? "incomplete" : "read")
}
')" || {
  echo "ERROR: no scope records on input — permission-merge.sh will not report an effective set it never read" >&2
  exit 2
}

printf '%s\n' "$merged"
