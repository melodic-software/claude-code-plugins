---
topic: trust-measures
section: talk
abstract: 'T1 (MEDIUM): "The talk shows revert rate as the percent of commits reverted per month, and the speaker says the number of PRs that get reverted is steady at about half a percent"'
claims:
  - claim: "The talk shows revert rate as the percent of commits reverted per month, and the speaker says the number of PRs that get reverted is steady at about half a percent"
    id: T1
    confidence: MEDIUM
    claim_kind: content
    source_owner: "Lauren Tan (AI Engineer Code Summit talk)"
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "local: .work/youtube-watch/aie-code-google-deepmind-anthropic-spacex-ZZ19zhYnDKY/key-frames/visual-frames.md slide 37; source/transcript.txt line 36"
        tier: 0
        pool: "melodic-software (local digest of the talk)"
        measures: "slide 37 text as transcribed by an earlier session, and the transcript at 1:15:34"
        role: primary
        published: undated
        applies_to: "version-independent"
        standing: historical
    inference: "Read from a local digest of https://www.youtube.com/watch?v=ZZ19zhYnDKY, not from the video; the slide says commits and the speech says PRs"
    qualifiers: ["the speaker's own figures, not verified", "slide unit (commits) and spoken unit (PRs) differ"]
  - claim: "Slides 3 and 33 to 38 show PR volume, release counts, contributors per month, revert rate and app performance, and no share of PRs merged with no human touch"
    id: T2
    confidence: MEDIUM
    claim_kind: content
    source_owner: "Lauren Tan (AI Engineer Code Summit talk)"
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "local: .work/youtube-watch/aie-code-google-deepmind-anthropic-spacex-ZZ19zhYnDKY/key-frames/visual-frames.md slides 3, 33-38"
        tier: 0
        pool: "melodic-software (local digest of the talk)"
        measures: "every listed slide in the named range, as transcribed"
        role: primary
        published: undated
        applies_to: "version-independent"
        standing: historical
    inference: "Absence within the named slides only; the full talk's slide list was read and shows the trust loops (slides 6, 7, 41) as diagrams, not a measured share"
    qualifiers: ["absence in a transcription, not in the video"]
  - claim: "Outside the named range, slide 23 shows a rising step line headed whenever you correct your agent, footer lint against it or categorically eliminate the problem, with no axis label"
    id: T3
    confidence: MEDIUM
    claim_kind: content
    source_owner: "Lauren Tan (AI Engineer Code Summit talk)"
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "local: .work/youtube-watch/aie-code-google-deepmind-anthropic-spacex-ZZ19zhYnDKY/key-frames/visual-frames.md slide 23; source/transcript.txt line 38"
        tier: 0
        pool: "melodic-software (local digest of the talk)"
        measures: "slide 23 text and the 1:16:34 transcript line (start with a lint rule to prevent new occurrences)"
        role: primary
        published: undated
        applies_to: "version-independent"
        standing: historical
    inference: "The digest itself marks the axis meaning (count of lint rules) as inferred, not stated"
    qualifiers: ["axis unlabeled", "slide 23 is outside the slides the owner named"]
produced_by: owner-addition
---

# The talk, read as data

Source: [All Code Is Slop (Except Mine), Lauren Tan](https://www.youtube.com/watch?v=ZZ19zhYnDKY), read
through the local digest only. Her numbers are not targets.

| Measure | How the talk defines or shows it |
|---|---|
| Revert rate | T1 (MEDIUM): "The talk shows revert rate as the percent of commits reverted per month, and the speaker says the number of PRs that get reverted is steady at about half a percent" |
| No-human-touch merge share | T2 (MEDIUM): "Slides 3 and 33 to 38 show PR volume, release counts, contributors per month, revert rate and app performance, and no share of PRs merged with no human touch" |
| Corrections converted to checks | T3 (MEDIUM): "Outside the named range, slide 23 shows a rising step line headed whenever you correct your agent, footer lint against it or categorically eliminate the problem, with no axis label" |

All three are MEDIUM because they come from an earlier session's transcription, not a fetch of the video.
