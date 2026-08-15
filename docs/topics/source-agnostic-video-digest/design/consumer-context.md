# Consumer context

Setup facts supplied by the user on 2026-08-14. They constrain what "strong defaults" means for this
design, and one of them contradicts a capability the skill's own `SKILL.md` says it does not have.

## The corpus is a separate LFS-backed repo, not the working repo

`melodic-software/knowledge-corpus` is used as the **large-artifact corpus**, backed by **git LFS**,
holding video files, screenshots, and comparable binary material. It is a live `library_dir` target:
the machine sweep found 3 slices / 176 tracked files there.

Stated purpose, verbatim: *"so we can also repurpose that content against other synthesis targets."*

Design consequences:

- **The work root is genuinely, routinely non-default.** The `library_dir` seam is not a theoretical
  portability affordance here — it is the normal operating mode. Any default that only reads well
  when artifacts land at the consuming repo root is the wrong default for this consumer.
- **Slices are re-read long after the watch that produced them**, by a different synthesis target
  than the one they were framed against. That raises the value of source-agnostic slice layout and
  of the source being recorded *in* the slice (`watch.json`'s `sourceUrl`, `watch-state.js:40,83`)
  rather than in the path — independent corroboration of A1 move (i).
- **A mixed-source corpus is the expected end state**, not an edge case. Confirms that per-source
  partitioning would have been actively wrong for this consumer.

## What is actually in the corpus — measured, not taken on report

`.gitattributes` tracks `*.mp4 *.mov *.webm *.png *.jpg *.jpeg *.gif *.pdf *.epub *.mp3 *.wav` via
LFS. `git lfs ls-files` = **93 files**: 87 `png`, 4 `epub`, 1 `pdf`, 1 `mp4`.

They fall into **two distinct trees**, and the distinction is the whole point:

| Tree | Content | Relationship to the skill |
|---|---|---|
| `.work/youtube-watch/<slug>/key-frames/frames/*.png` (38 files) | Promoted key frames | **Conforming.** These are exactly what the Output contract already stages (`key-frames/frames/**` → staged: yes, DELIVERABLE). LFS is the consumer's storage choice for artifacts the skill already commits — no conflict at all |
| `sources/webinars/<slug>/` — `media/*.mp4` + `frames/scenes/scene-NNNN.png` | Committed **source video** and **bulk scene frames** | **Hand-built, in the skill's declared not-supported shape** |

### Correction to an earlier reading in this file

An earlier version of this section claimed the consumer was "doing by hand exactly what the skill
declares as a not-yet-built follow-up", inside the skill's own slices. **That was wrong.** The
skill-produced slices are fully conforming; LFS there is orthogonal storage policy. The hand-built
work lives in a **separate parallel tree**, which is a materially different situation and a weaker
conflict.

### But that parallel tree is evidence for BOTH deferred follow-ups at once

`sources/webinars/getting-started-with-loops/` is simultaneously:

- **The retention follow-up** (`SKILL.md:18`) — a committed source `.mp4` and committed bulk scene
  frames, which the skill keeps in OS temp and explicitly says it will not retain.
- **The sub-path-shape follow-up** (`SKILL.md:56`) — and `sources/<type>/<slug>/` is *verbatim the
  example that line gives* of a shape the skill does not provide: *"A consumer whose own convention
  lands source material at a differently-shaped path (for example `sources/<type>/<slug>/`) does not
  get that shape from this skill today."*

So both tracked follow-ups have a real, live user who has already built around them by hand. That is
the strongest evidence available that they are worth prioritizing — and it is independent evidence,
since it predates this design.

Note this is *adjacent to but distinct from* A1 move (ii): move (ii) was parameterizing the epic
**value**; `SKILL.md:56` is templating the sub-path **shape**. Both deferred, different follow-ups.
The webinar tree is evidence for the shape one specifically.

## Scope call

**Out of scope for this design; recorded, not folded in.** This is an *artifact-retention* concern,
not a *source-adapter* one, and X changes nothing about it — X videos produce the same frames,
contact sheets, and temp video as YouTube. Widening this refactor to cover LFS retention would be
scope creep of the same shape that A1 move (ii) was just rejected for.

**Trigger to take it up:** both follow-ups are already tracked in the skill's own text, and the
hand-built `sources/webinars/` tree is live evidence each has a real user. They warrant their own
topic slice. Specific mechanisms that would have to change: `snapshot-bootstrap.js`'s per-directory
`.gitignore` (`*.jpg`) write would have to become conditional, and `resolveWorkSliceDir`
(`derive-video-slug.js:45`) is where a templated sub-path shape would land — the same function A1
move (ii) identified as un-parameterized, so the two follow-ups share an implementation site and
should be scoped together rather than separately.

**One thing this design must not do:** add anything that makes the retention follow-up harder. A
source adapter that assumed temp-only media, or that hardcoded the never-in-git contact-sheet
handling more deeply, would foreclose it.
