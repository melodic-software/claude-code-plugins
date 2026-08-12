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
| S13 | `advanced.md` Duration slider | Control exists, is named "Duration slider", lives in the Create form, scoped to Web + V5.5 | **Audited — first-party** (<https://suno.com/release-notes/duration-slider-on-web>, Jul 20 2026, fetched 2026-08-12) | 1.3.0 |
| S14 | `advanced.md` Duration slider | Range 10s-6min, 5-second increments, Auto/Custom default pair | **LOW-MEDIUM** — writer-observed 2026-08-12 and independently stated by one community post; `help.suno.com` has no slider article as of 2026-08-12, and the Jack Righteous duration-slider guide declines to state a range | 1.3.0 |
| S15 | `advanced.md` Duration slider | Whether a duration target rushes, pads, hard-cuts or fades a mismatched lyric | **Not yet audited** — shipped as an explicit open question; one community post reports hard-cut/rush, nothing first-party addresses it (2026-08-12) | 1.3.0 |
| S16 | `advanced.md` Creative Sliders — Audio Influence row + note | Audio Influence entry value is 25% in the cover-from-upload flow | **Writer-observed, off-ladder** — `writer-observed, single session (2026-08-12), n=1 — not externally corroborated`; no external corroboration attempted; the Extend and upload-as-seed entry values are unobserved | 1.3.0 |
| S17 | `troubleshoot.md` "My bridge is missing / another section sang its lyrics" | Tag-only repeat section adjacent to a lyric-bearing section can be absorbed — the adjacent section's lyrics sing in the empty slot and that section is dropped | **Observed failure, off-ladder** — `writer-observed, single session (2026-08-12), n=1 — not externally corroborated`; adjacency is a candidate cause, not a demonstrated mechanism; tag-only before `[Outro]`/`[End]` untested | 1.3.0 |
| S18 | `lyrics.md` "Line breaks cut both ways"; `tips.md` line-breaks entry | Short-line stacks over-separate (excess pauses, choppy delivery); prompt-layer join fixes it | **Split** — the line-break mechanism stays MEDIUM, unchanged; the failure edge and the join fix are `writer-observed, single session (2026-08-12), n=1 — not externally corroborated`, off-ladder | 1.3.0 |

When a row moves, update this table and the plugin CHANGELOG in the same
PR.
