# Suno context drift audit ledger

Committed authority for what has and has not been audited in the `suno`
skill's context spokes.

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
| S11 | `tips.md` timing cue | `~70%` effectiveness figure | **Removed in 1.1.2** — no basis found in-repo (searched 2026-08-11, re-run 2026-08-12) or externally (2026-08-12: two `help.suno.com` articles read verbatim, two large community meta-tag references grepped; zero hits for the cue form or `70%`); technique retained, flagged LOW-MEDIUM; full search record kept in `tips.md` (#2266) | 1.1.2 |
| S12 | `[Section]` tag rows | (per #2233 item 4) | **Not yet audited** | — |
| S13 | `advanced.md` Duration slider | Control exists, is named "Duration slider", lives in the Create form, scoped to Web + V5.5 | **Audited — first-party** (<https://suno.com/release-notes/duration-slider-on-web>, Jul 20 2026, fetched 2026-08-12) | 1.3.0 |
| S14 | `advanced.md` Duration slider | Range 10s-6min, 5-second increments, Auto/Custom default pair | **LOW-MEDIUM** — writer-observed 2026-08-12 and independently stated by one community post; `help.suno.com` has no slider article as of 2026-08-12, and the Jack Righteous duration-slider guide declines to state a range | 1.3.0 |
| S15 | `advanced.md` Duration slider | Whether a duration target rushes, pads, hard-cuts or fades a mismatched lyric | **Not yet audited** — shipped as an explicit open question; one community post reports hard-cut/rush, nothing first-party addresses it (2026-08-12) | 1.3.0 |
| S16 | `advanced.md` Creative Sliders — Audio Influence row + note | Audio Influence entry value is 25% in the cover-from-upload flow | **Writer-observed, off-ladder** — `writer-observed, single session (2026-08-12), n=1 — not externally corroborated`; no external corroboration attempted; the Extend and upload-as-seed entry values are unobserved | 1.3.0 |
| S17 | `troubleshoot.md` "My bridge is missing / another section sang its lyrics" | Tag-only repeat section adjacent to a lyric-bearing section can be absorbed — the adjacent section's lyrics sing in the empty slot and that section is dropped | **Observed failure, off-ladder** — `writer-observed, single session (2026-08-12), n=1 — not externally corroborated`; adjacency is a candidate cause, not a demonstrated mechanism; tag-only before `[Outro]`/`[End]` untested | 1.3.0 |
| S18 | `lyrics.md` "Line breaks cut both ways"; `tips.md` line-breaks entry | Short-line stacks over-separate (excess pauses, choppy delivery); prompt-layer join fixes it | **Split** — the line-break mechanism stays MEDIUM, unchanged; the failure edge and the join fix are `writer-observed, single session (2026-08-12), n=1 — not externally corroborated`, off-ladder | 1.3.0 |
| S19 | `voices.md` two-stage bootstrap (non-singers) + "make this voice public" toggle-default warning | Reported route: clone from speech, then reclone from the Suno-generated singing; the visibility toggle defaults on for every voice created | **LOW-MEDIUM** — single r/SunoAI post (u/Physical-Dress8460, posted 2026-06-30) plus its comment thread, read 2026-08-11; not multi-source consensus; untested here | 1.3.0 |
| S20 | `SKILL.md` Character budgets — lyrics field; the mirrored row in `context/style.md` Character budgets | Hard cap 5,000 chars (v4.5/v5/v5.5); ~3,000 remains the practical quality budget | **Re-verified 2026-07-18, position flipped since the 2026-05-10 pass** — the earlier "3,000" consensus conflated the v4-era hard cap with the quality threshold; third-party tester consensus only (hookgenius, aimusicapi 2026-07-03), no official Suno page states field limits | 0.4.1 |

When a row moves, update this table and the plugin CHANGELOG in the same
PR.

## History

Prior issues (#2233, #2266) cited
`.work/songwriting-plugin-pilot/suno-drift/RESEARCH.md` as this ledger;
that memory-tier path was never created, so absence claims were
unfalsifiable until this file shipped (#2354).

**The Reddit corpus was never closed; the note saying so was never read.**
1.1.2 and 1.1.3 both recorded r/SunoAI as unreachable ("the search tool
refuses `reddit.com`") and rated claims down accordingly, even though
`context/workflow-recipes.md` has said since 1.1.0 that a browser session
reaches it where search and direct fetch both fail. Three releases in a
row missed the route already on record here; 1.2.0 ran the pass on the
first try. Before rating anything below MEDIUM for want of Reddit, use
the browser route rather than concluding the corpus is closed.
