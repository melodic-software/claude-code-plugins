#!/usr/bin/env bash
# managed-conformance.sh — which managed intents are actually enforced, and
# which a developer can loosen.
#
# An administrator deploys managed policy believing it is policy. Some of it is:
# "no other level, including command line arguments, can override a managed
# permission rule", and "if a tool is denied at any level, no other level can
# allow it". Some of it is not: a managed `autoMode` section is additive, so a
# developer can extend it with a personal `allow` entry that overrides an
# organization `soft_deny` -- "the combination is additive, not a hard policy
# boundary". Nothing surfaces which is which.
#
# This reports that split. It reports ONLY what the consumer's own policy does
# and does not achieve; it never prescribes what a policy should contain. That
# keeps it neutral by construction rather than by restraint -- every rule string
# it prints comes from a file it read.
#
# Input: permission-state.sh records on stdin (surface + rule + conf records).
# With no piped input the reader is run directly and its status propagated.
#
# Output:
#   MANAGED-NOTE: <text>
#   managed enforced <kind> <rule>            cannot be overridden from below
#   managed loosenable <what> <detail>        a lower scope can weaken this
#   managed conformance summary enforced=<n> loosenable=<n> status=<s>
#
# Prerequisites: POSIX text tools only.
#
# Usage:
#   permission-state.sh | managed-conformance.sh
#   managed-conformance.sh [--help]

set -uo pipefail

usage() {
  cat <<'EOF'
managed-conformance.sh — report which managed intents are enforced vs loosenable.

Usage: permission-state.sh | managed-conformance.sh
       managed-conformance.sh [--help]

Emits "managed enforced <kind> <rule>", "managed loosenable <what> <detail>",
and a summary. Every rule string printed comes from a file that was read -- this
report never prescribes rules a policy should contain.

Reads only. Managed policy is read-only by construction: those are admin-write
OS locations or a claude.ai Owner role, so a plugin could not author them.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
"") ;;
*)
  echo "ERROR: unknown argument '$1'" >&2
  exit 2
  ;;
esac

if [[ -t 0 ]]; then
  STATE_SCRIPT="${BASH_SOURCE[0]%/*}/permission-state.sh"
  if [[ ! -r "$STATE_SCRIPT" ]]; then
    echo "ERROR: cannot read $STATE_SCRIPT — nothing to report on" >&2
    exit 2
  fi
  records="$(bash "$STATE_SCRIPT")" || exit $?
else
  records="$(cat)"
fi

report="$(printf '%s\n' "$records" | awk '
function text_of(start,   i, s) {
  s = $start
  for (i = start + 1; i <= NF; i++) s = s " " $i
  return s
}

$1 == "rule" {
  if ($2 == "managed") {
    key = $4 SUBSEP text_of(5)
    if (!(key in managed_seen)) {
      managed_seen[key] = 1
      managed_order[++n_managed] = key
    }
  } else {
    lower[$4 SUBSEP text_of(5)] = ($4 SUBSEP text_of(5)) in lower ? lower[$4 SUBSEP text_of(5)] "," $2 : $2
  }
  next
}
$1 == "conf" {
  conf[$2 SUBSEP $4] = text_of(5)
  next
}
$1 == "NOTE:" { next }
NF >= 3 {
  n_surfaces++
  if ($1 == "managed") {
    n_managed_surfaces++
    status = $3
    if (status == "present") n_managed_present++
    # invalid-json belongs here, not with absent: a CORRUPT managed policy is a
    # policy that exists and could not be read, and reporting it as "no policy
    # deployed" is the single worst answer this report can give an
    # administrator. The merge already groups the three; this now matches it.
    else if (status == "skipped" || status == "unreadable" || status == "invalid-json") unread[++n_unread] = $2 " (" status ")"
  }
  next
}

END {
  if (n_surfaces == 0) exit 2

  # A managed report that cannot say whether it read the managed scope is worse
  # than no report: an administrator would read silence as "no policy deployed".
  for (i = 1; i <= n_unread; i++)
    print "MANAGED-NOTE: the managed surface " unread[i] " was NOT read, so this report is incomplete by that surface — it is not evidence that no policy is deployed there."

  print "MANAGED-NOTE: server-managed settings are delivered remotely at sign-in and have no local path, so no local reader can see them. \"Managed\" here means the LOCAL managed surfaces only; an intent enforced remotely will not appear below."

  # "No local policy" is claimed ONLY when every surface was actually looked at
  # and found empty. A surface that could not be read -- corrupt, skipped,
  # unreadable -- means a policy may well be deployed and this report could not
  # see it, so the honest status is `incomplete`. Reporting that as
  # `no-local-policy` told an administrator their corrupt policy file was an
  # absent one.
  if (n_managed_present == 0) {
    if (n_unread > 0) {
      print "MANAGED-NOTE: no managed surface could be read with content, and " n_unread " surface(s) above could not be read at all — this is NOT evidence that no policy is deployed, only that none could be read here."
      print "managed conformance summary enforced=0 loosenable=0 status=incomplete"
    } else {
      print "MANAGED-NOTE: no local managed policy surface was readable with content, so there is nothing to report conformance against."
      print "managed conformance summary enforced=0 loosenable=0 status=no-local-policy"
    }
    exit 0
  }

  # --- Enforced: what no lower scope can undo --------------------------------
  #
  # "no other level, including command line arguments, can override a managed
  # permission rule", and separately "if a tool is denied at any level, no other
  # level can allow it". A managed deny is therefore the strongest thing an
  # administrator can write, and it is the only category this report calls
  # enforced without qualification.
  for (i = 1; i <= n_managed; i++) {
    split(managed_order[i], f, SUBSEP)
    kind = f[1]; text = f[2]
    if (kind == "deny") {
      print "managed enforced deny " text
      n_enforced++
    } else {
      # ask and allow at managed scope still cannot be OVERRIDDEN, but they can
      # be OUTRANKED: deny is evaluated before ask and ask before allow, from any
      # scope. So a lower-scope deny changes the outcome without overriding the
      # managed rule at all -- a distinction an administrator reading "managed is
      # highest" would not expect.
      beaten = ""
      if (kind == "allow") {
        if ((("deny") SUBSEP text) in lower) beaten = "deny"
        else if ((("ask") SUBSEP text) in lower) beaten = "ask"
      } else if (kind == "ask") {
        if ((("deny") SUBSEP text) in lower) beaten = "deny"
      }
      if (beaten != "") {
        print "managed loosenable rule the managed " kind " rule " text " is outranked by a " beaten " rule in scope(s) " lower[beaten SUBSEP text] " — evaluation order (deny, then ask, then allow) applies from any scope, so a lower scope changes the outcome without overriding the managed rule"
        n_loosenable++
      } else {
        print "managed enforced " kind " " text
        n_enforced++
      }
    }
  }

  # --- Loosenable: the managed autoMode block --------------------------------
  #
  # permissions, hooks, MCP, sandbox-filesystem and sandbox-network each have an
  # exclusivity lock; auto mode has none. "A developer can extend environment,
  # allow, soft_deny, and hard_deny with personal entries but cannot remove
  # entries that managed settings provide… a developer-added allow entry can
  # override an organization soft_deny entry: the combination is additive, not a
  # hard policy boundary."
  if ((("managed") SUBSEP "autoModePresent") in conf) {
    print "managed loosenable autoMode a managed autoMode section is ADDITIVE, not a policy boundary: a developer cannot remove entries it provides, but a developer-added allow entry can override an organization soft_deny entry. For an action that must never run regardless of classifier configuration, use permissions.deny in managed settings, which cannot be overridden"
    n_loosenable++
  }

  # disableAutoMode is the one auto-mode-adjacent lever that IS a lock -- and
  # only when it carries the documented string.
  k = ("managed") SUBSEP "disableAutoMode"
  k2 = ("managed") SUBSEP "permissions.disableAutoMode"
  for (kk in conf) {
    split(kk, kf, SUBSEP)
    if (kf[1] != "managed") continue
    if (kf[2] != "disableAutoMode" && kf[2] != "permissions.disableAutoMode") continue
    if (conf[kk] == "\"disable\"")
      print "managed enforced lockout " kf[2] " is set to \"disable\" in managed settings, which prevents auto mode from being used at all"
    else
      print "managed loosenable lockout " kf[2] " is " conf[kk] " in managed settings, but the documented value is the STRING \"disable\" — any other value is accepted and silently does nothing, so auto mode is NOT disabled"
    if (conf[kk] == "\"disable\"") n_enforced++; else n_loosenable++
  }

  print "managed conformance summary enforced=" n_enforced + 0 " loosenable=" n_loosenable + 0 " status=read"
}
')" || {
  echo "ERROR: no scope records on input — managed-conformance.sh will not report on a managed policy it never read" >&2
  exit 2
}

printf '%s\n' "$report"
