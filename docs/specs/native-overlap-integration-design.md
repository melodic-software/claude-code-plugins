---
outcome: early-exit
tier: B
reason: one new store field with a closed enum, one new convention grammar, and a per-lane integrity shape inside existing scripts; every contract decision was locked in the Brief, so a full design pass would re-derive settled threads
---

# Design resolution, audit-native-overlap

## Type sketch

### Store row (`docs/native-surfaces/records.json`, schema 1, additive)

```text
row.integration : "route" | "wrap" | "suggest"     required on every row
  invariants (enforced by overlap.py validate_row):
    native.class == "builtin-command"      -> integration in {route, suggest}
    native.class == "bundled-skill"        -> integration in {route, wrap}
    native.class == "bundled-skill" and "model-invocation-disabled" in native.markers
                                           -> integration == "suggest"   (the model never lists it, so a route phrase is dead text)
    native.class == "plugin-backed-builtin"-> integration in {route, wrap}
    native.class == "marketplace-plugin"   -> integration in {route, wrap}   (wrap grammar owned by seam-phrasing)
    native.class == "session-skill"        -> integration == "route"
    verdict == "defer"                     -> integration == "route"   (nothing is baked from a defer row)
    integration in {wrap, suggest}         -> an evidence line names the observed invocation mode
                                              (Skill-tool reach is per surface: /init and /security-review are
                                              reachable built-ins; /export and /skill-doctor are non-prompt
                                              command types; the class rules are a floor, not the determinant)
  marker source: the registration the row's evidence names, never the bare name
    (on 2.1.263 "design" is two bundled registrations: the canvas, model-invocable; the hub, model-disabled)
row.baked : {description_phrase, boundary_section, native_step, suggest_sentence}   two flags added
  native_step:      true only when integration == "wrap"    and the body carries "## Native step: <name> (<class>)"
  suggest_sentence: true only when integration == "suggest" and the body carries the suggest token
```

### Inventory integrity (`inventory.py`, schema 1, additive)

```text
integrity.status        : "ok" | "degraded" | "broken"        unchanged, now the worst lane
integrity.lanes         : { builtin_commands: LaneStatus, bundled_skills: LaneStatus, plugin_backed: LaneStatus }
LaneStatus              : { status: "ok" | "degraded" | "broken", problems: [str], advisories: [str] }
```

`overlap.py detect` reads `integrity.lanes` when present and falls back to the top-level status when absent, so an older inventory file still parses.

### Convention grammars (`docs/conventions/native-references`)

```text
route   : description phrase carrying the gate token "resolves in your session"   (existing)
wrap    : body section "## Native step: <name> (<class>)" carrying the gate token, the identity
          check by class, the mutation clause, the skip-and-report contract for five states
          (does not resolve, invocation refused with the reason named, identity mismatch,
          mutation detected after a scoped invocation, resolved but degraded with the surface's
          own disclosure relayed), and the enable path   (new)
suggest : body sentence "If /<command> is available in your session (<basis>), run it for <job>."
          carrying the token "available in your session", the basis pointing at a same-file
          four-part verification record                                              (new)
```

Class table: bundled-skill, plugin-backed-builtin, and marketplace-plugin may take route or wrap (the marketplace-plugin wrap grammar is seam-phrasing's, per the playgrounds precedent); a bundled-skill row marked model-invocation-disabled takes suggest; builtin-command may take route or suggest; session-skill may take route only. Amended 2026-09-11 after the round-4 validation pass.

## Threads resolved in the Brief

Wrap semantics, degradation contract, identity verification, suggestion placement, per-row field placement, description trimming, and filing shape are all locked in `../PLAN.md` `## Brief`. No thread is open.
