# 0025. Adopt the rendered-views doctrine with a cascade-carried preference

Date: 2026-09-01. Status: accepted; superseded in part by
[ADR 0075](0075-resolve-plugin-settings-through-one-four-layer-cascade-and-a-bound-convention-home.md)
for the preference's location (`.claude/rendered-views.md` is retired; the settings are
`docs/conventions/rendered-views.yaml` and its personal override, per
[the rendered-views contract](../contracts/rendered-views/README.md#the-rendered-views-settings)),
and by [ADR 0019's 2026-10-02 amendment](0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md#amendment-2026-10-02-one-canonical-source-every-copy-generated)
for the in-plugin canonical chrome copy (the canonical is `lib/html-chrome.html`).

## Context

The "Unreasonable Effectiveness of HTML" corpus (article, blog republication, 31-demo
gallery and unknowns collection, official template repo) argues that person-facing
deliverables land better as rich, self-contained HTML pages, and this marketplace already
shipped 14 HTML-emitting surfaces under an implicit markdown-is-the-record rule. The
repo owner runs multiple claude.ai accounts, which breaks account-bound Artifacts
(publishes land on the wrong account; no cross-account sharing or editing exists, and no
roadmap for it is documented). The owner asked for an opinionated default that honors a
user's global preference while staying user-configurable and repo-agnostic.

## Decision

Codify the doctrine as `docs/contracts/rendered-views/` (the boundary rule, genre
rubric, reachability matrix, security skeleton, accessibility floor) rather than any
generic HTML-generating skill. Carry the cross-plugin format preference as a
config-cascade concern (`.claude/rendered-views.md`, per-key override, no policy-floor
class) with plugin `userConfig` reserved for plugin-specific dials under distinct keys.
Keep Artifact-first as the shipped ladder for existing surfaces, name the native Artifact
disable switches as the day-one personal flip, and grandfather the fleet until a priced
sweep. Ship the shared chrome/token reference as a canonical in-plugin copy that the
second adopter registers as a sync cluster. Stage escaping: instruction baseline now, a
deterministic helper required before any attacker-controlled lane.

## Why

Four precedence mechanisms were weighed; the cascade's ratified base law (team refines
user-global, local overlay as the personal trump, user preference governing wherever no
repo layer speaks) delivers the owner's intent without amending the contract or forking
two competing user-global surfaces for one concern. A single cited reference file cannot
reach installed consumers, and the drift checker mechanically rejects a one-plugin
registration, so the canonical-copy-then-register shape is the only conformant delivery.
Keeping the shipped ladder avoided a fleet-wide eval rewrite while the native switches
give any operator local-first today. The decisions survived a blindspot scan, a
devils-advocate stress-test, and a two-validator answer audit; the full record rides the
adopting pull request.
