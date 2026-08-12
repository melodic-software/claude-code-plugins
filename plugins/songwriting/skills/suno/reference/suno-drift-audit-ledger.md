# Suno context drift audit ledger

Committed authority for what has and has not been audited in the `suno`
skill's context spokes. Prior issues (#2233, #2266) cited
`.work/songwriting-plugin-pilot/suno-drift/RESEARCH.md` as this ledger;
that memory-tier path was never created, so absence claims were
unfalsifiable until this file shipped (#2354).

**How to use:** each row names a site, the claim class, audit status, and
the release or issue that last touched it. "Unsourced" means no source was
found in either direction at audit time — not a verdict that the claim is
false.

| ID | Site | Claim | Status | Last touched |
|---|---|---|---|---|
| S7 | `power-tips.md:7-13` | First tag carries highest weight; middle tags (4-7) soften/merge | **Unsourced** — retained as unverified rule of thumb; first-party category-order lead does not establish positional weight (#2353) | 1.1.4 |
| S8 | `lyrics.md:187` | (per #2233 item 4) | **Not yet audited** — cited by #2233 before any ledger existed | — |
| S9 | `advanced.md:99` | (per #2233 item 4) | **Not yet audited** | — |
| S10 | `power-tips.md:29` | Genre-fusion order encodes priority | **Audited** — demoted; anchor/accent hierarchy is attested, position-as-mechanism is not (#2351, 1.1.2) | 1.1.2 |
| S11 | `tips.md` timing cue | `~70%` effectiveness figure | **Unsourced** — basis recorded nowhere; flagged LOW-MEDIUM (#2266) | 1.1.1 |
| S12 | `[Section]` tag rows | (per #2233 item 4) | **Not yet audited** | — |

When a row moves, update this table and the plugin CHANGELOG in the same
PR.
