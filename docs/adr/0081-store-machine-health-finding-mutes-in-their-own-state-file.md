# Store machine-health finding mutes in their own state file

- Status: accepted
- Date: 2026-10-21

## Context

The machine-health audit is gaining checks that list items (startup entries, extensions, listeners,
large folders). The owner needs to mark an item as expected so it stays listed but stops raising the
check's severity, and to make that pick on the interactive decision page that each run builds.

A mute has to outlive the run that created it, so it needs a stable name for an item across runs, a
stored place to live, and a way to tie a pick on a page back to the item that page showed.

The first design put mutes under `check_overrides` inside `approvals.json` at schema 1.0. A stress
test rejected that: an older plugin build reading an `approvals.json` with an unknown key either
FAILs `setup check` or strips the key on its next write, so a mute could break setup or vanish during
an update window.

## Decision

- **Mutes live in `<StateBase>/state/mutes.json`**, validated by a new
  `catalog/schemas/mutes.schema.json` at `schema_version` `"1.0"`. Its shape is
  `checks.<check-id>.muted_findings[]`, each entry `{ key, label, reason, added_at, run_id }`, with
  `key` and `added_at` required and no other properties allowed.
- **`approvals.json` and `approvals.schema.json` are unchanged**, byte for byte. Remediation
  approvals stay there; mutes never go there.
- **A finding item is named by a FindingKey**: `<kind>:<first 16 hex characters of
  SHA-256(lower(kind + "|" + identity fields joined by "|"))>`, matching
  `^[a-z-]{1,16}:[0-9a-f]{16}$`. The kinds are `startup`, `task`, `folder`, `app`, `ext`,
  `listener`, `exclusion`, `detection` and `firewall`, each with a fixed list of identity fields. A
  listener whose owner cannot be resolved gets no key and cannot be muted.
- **A pick resolves only against the map of the run that built the page.** Each run writes
  `<StateBase>/views/checkup-<runStamp>.ids.json`, mapping page row ids to an action and a
  FindingKey. The page's copied payload carries a builder-assigned `run: <runStamp>` line, and the
  resolver opens only the map that line names. A payload with no `run:` line, or one naming a map
  that is gone, is refused whole. The newest 12 runs' maps are kept.

## Consequences

- The FindingKey format and each kind's identity fields are one-way: changing either orphans every
  stored mute. A change ships with a migration or a new kind name.
- A downgraded plugin has no reader for `mutes.json`, so muted items raise severity again until the
  upgrade. Neither file FAILs and nothing is stripped. The CHANGELOG fragment for the release that
  adds `mutes.json` says so.
- Checks never read `mutes.json`. The orchestrator reads it and passes the muted keys to each check
  as an argument.
- A payload pasted after its run has been pruned (more than 12 runs later) cannot be resolved; the
  owner re-picks on a newer page.

## Amendment (2026-10-22): the shipped kinds and identity fields

The kinds that shipped are the nine listed under Decision plus `process`, emitted by
`top-processes` and named by the lowercased image file name, never the process id. Setup `check`
accepts a muted `process` key.

Two kinds carry more identity fields than the design listed, so each names an item more narrowly:

- `startup` is named by scope, run kind (the Run or RunOnce key, or the Startup folder) and name,
  so a Run entry and a RunOnce entry with the same name in the same scope get different keys.
- `detection` is named by threat id, resource and detection id, so each detection of the same
  threat at the same path gets its own key.

Unkeyed items are not limited to listeners: a per-version firewall rule whose protocol and local
port stay unread without elevation is also listed with no key and cannot be muted. No key is ever
computed from missing data.

The one-way consequence above applies to these shipped fields: changing any of them orphans the
stored mutes of that kind.
