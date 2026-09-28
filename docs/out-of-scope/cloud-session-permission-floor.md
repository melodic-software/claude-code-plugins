# Cloud sessions: fleet permission floor never composed (#3172)

## Decision

**Parked — unpaid infra.** This repository does not add a composition step that writes the
fleet `claude-permissions` allow/deny floor into a Claude Code cloud session's
`~/.claude/settings.json`
([#3172](https://github.com/melodic-software/claude-code-plugins/issues/3172)).

**Claim:** Cloud sessions never receive the reviewed `standards` permission floor. User-level
`~/.claude` (where chezmoi composes it) does not carry over. This repo's tracked
`.claude/settings.json` carries only a secret-material `deny` subset, not the fleet allow
grants or the destructive-git `deny` floor. The compose step belongs in
`melodic-software/standards` `components/cloud-environment/setup.sh`. It is not implemented
here.

**Basis:** #3172 (filed 2026-08-23; re-verified 2026-09-06 in a cloud session: project,
user, remote, and launcher scopes had no fleet `deny` floor; `work-items:work` preflight
still reported the five GAP (b) verbs). `claude-permissions` README: distributed as data
and composed by each consumer; never merged by the sync engine. The one active composer is
the `dotfiles` chezmoi user-layer template, which never runs in a cloud session.
[cloud-sessions.md](../cloud-sessions.md) "What carries over from your setup": repo
`.claude/` reaches cloud sessions; user-level `~/.claude` never does. Plugin
`settings.json` `permissions` blocks are inert (permission-rule-hygiene; plugins reference
`settings.json` keys). Origin/main `.claude/settings.json` `permissions.deny` is
secret-material `Read()` patterns only.

**As of:** 2026-09-28.

**Recheck:** `standards` `components/cloud-environment/setup.sh` (or this repo's
`.claude/cloud-bootstrap.sh`) grows a `jq` union of `claude-permissions.json` into the
session settings, or a Claude Code cloud session's `~/.claude/settings.json` shows the
fleet `allow` grants and destructive-git `deny` rules.

## Recommended compose path (not built here)

When funded, implement in `standards`, not as a one-off in this checkout:

| Choice | Recommendation |
| --- | --- |
| Site | `components/cloud-environment/setup.sh` (fleet-wide, cache-baked), not every consumer's `cloud-bootstrap.sh` |
| Payload | Full floor (`allow` and `deny`). Unmatched `${CLAUDE_PLUGIN_ROOT}` allow rules are inert |
| Merge | `jq` union into `~/.claude/settings.json`; never overwrite the file |
| Posture | Best-effort (never fail the cache build), matching the rest of that script |
| Alternative | Cloud-specific subset, only if a maintainer rejects the full floor for the cloud posture |

Opening the `standards` issue stays a maintainer action. This settle does not file it.

## Rationale

- The entire fix locus is another repository's component. Cross-repo routing is what
  `needs-human` exists for.
- Composing from this repo would vendor or fetch `claude-permissions.json` and duplicate
  the consumer mechanism the component already describes.
- Unattended cloud lanes currently rest on the auto-mode classifier with no reviewed deny
  floor. That is a real guardrail reduction and is silent. Documenting it is the Option A
  close; composing it is unpaid infra.

## Revisit when

- A maintainer opens and funds the `standards` compose step above, or
- Claude Code starts composing user-level settings into cloud sessions (the chezmoi path
  would then reach them without a new mechanism).

## Prior requests

- #3172 (2026-09-28): drain shipper documents the gap and the recommended compose path;
  parks unpaid infra (no `setup.sh` or bootstrap compose step in this checkout).
