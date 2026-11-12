---
topic: test-stage-chart
section: origin
abstract: 'O1 (HIGH (single source)): "Cindy Sridharan published the three-phase test-stage chart in her Medium post Testing in Production, the safe way, dated Mar 25, 2018, after a two-column chart in her December 2017 post Testing Microservices, the sane way"'
claims:
  - claim: "Cindy Sridharan published the three-phase test-stage chart in her Medium post Testing in Production, the safe way, dated Mar 25, 2018, after a two-column chart in her December 2017 post Testing Microservices, the sane way"
    id: O1
    confidence: HIGH (single source)
    claim_kind: content
    source_owner: "Cindy Sridharan (copyconstruct)"
    single_source: "The claim is about the content and date of one author's own post; only that author publishes it. Later pages that credit the stage model to her are recorded as corroborators of attribution, not as second publishers."
    tiers: [1, 2]
    applies_to: "version-independent"
    sources:
      - url: "https://copyconstruct.medium.com/testing-in-production-the-safe-way-18ca102d0ef1"
        tier: 1
        pool: "Cindy Sridharan (copyconstruct)"
        measures: "the post itself, fetched this run (passages saved in RESEARCH-snapshot.md): byline, printed date Mar 25, 2018; a first image captioned From my post Testing Microservices, the sane way; the text saying testing in production encompasses techniques across three distinct phases; then the chart image 1*LFnVVlLrgrvXQ5ScrHVKjg with pre-production and deploy, release, post release columns"
        role: primary
        published: 2018-03-25
        dated_by: printed
        applies_to: "version-independent"
        standing: current
      - url: "https://sookocheff.com/post/architecture/testing-in-production/"
        tier: 2
        pool: "Kevin Sookocheff (sookocheff.com)"
        measures: "a 2018 article that divides testing into pre-production, deployment, release and post-release and credits the division to Testing in production, the safe way, Cindy Sridharan; read as a search excerpt only"
        role: corroborator
        published: 2018-09-25
        applies_to: "version-independent"
        standing: current
      - url: "https://testautomationu.applitools.com/test-automation-in-devops/chapter5.html"
        tier: 2
        pool: "Applitools Test Automation University"
        measures: "a course chapter that calls the stage model one from Cindy Sridharan and lists the post as a resource; search excerpt only; undated"
        role: corroborator
        published: undated
        applies_to: "version-independent"
        standing: historical
    inference: "The primary is the post itself: its byline, printed date, the caption on its first image and its three-phases sentence settle authorship, date and the predecessor; the corroborators only confirm that others attribute the model to her."
    qualifiers:
      - "The December 2017 two-column image (1*KtiYN4lEDHyp929tix6yzw) was not viewed; its description as two-column rests on the 2018 post's caption and three-phases sentence."
      - "The three-phase chart is the post's second image, not its first."
  - claim: "The 2018 chart lists 39 entries (18 pre-production, 5 deploy, 5 release, 11 post-release) and has no formal verification, performance tests or soak tests, the three entries the slide-31 redraw adds"
    id: O2
    confidence: HIGH (single source)
    claim_kind: content
    source_owner: "Cindy Sridharan (copyconstruct)"
    single_source: "The claim is about the entries drawn in one author's own image; only that author publishes it. The slide-31 side of the comparison is the talk digest's transcription of the slide, a local reading, not a second publisher of the 2018 image."
    tiers: [1]
    applies_to: "version-independent"
    sources:
      - url: "https://copyconstruct.medium.com/testing-in-production-the-safe-way-18ca102d0ef1"
        tier: 1
        pool: "Cindy Sridharan (copyconstruct)"
        measures: "the post that embeds the chart (printed date Mar 25, 2018); the embedded image, https://miro.medium.com/v2/resize:fit:1400/1*LFnVVlLrgrvXQ5ScrHVKjg.jpeg, was downloaded and viewed this run and every entry read column by column and counted; the image itself prints no date, so the date is the embedding post's printed date"
        role: primary
        published: 2018-03-25
        dated_by: printed
        applies_to: "version-independent"
        standing: current
    inference: "Counting the viewed image gives 39 entries; comparing them with the 42-entry slide-31 transcription leaves exactly formal verification, performance tests (pre-production) and soak tests (deploy) on the slide alone."
    qualifiers:
      - "Whether the 2026 tweet image or the talk redraw added the three entries was not established; the tweet image was not viewed."
      - "The slide-31 list comes from the talk digest transcription (key-frames/visual-frames.md row 31), not from a fresh view of the slide."
  - claim: "The 2018 post states its content applies only to testing services whose deployment is under the control of the engineers developing them, not to mobile applications, safety-critical systems or embedded software"
    id: O3
    confidence: HIGH (single source)
    claim_kind: content
    source_owner: "Cindy Sridharan (copyconstruct)"
    single_source: "The claim is what one author wrote about the scope of her own post; only that author publishes it."
    tiers: [1]
    applies_to: "version-independent"
    sources:
      - url: "https://copyconstruct.medium.com/testing-in-production-the-safe-way-18ca102d0ef1"
        tier: 1
        pool: "Cindy Sridharan (copyconstruct)"
        measures: "the scope paragraph of the post, read this run and saved in RESEARCH-snapshot.md: the content only ever applies to the testing of services whose deployment is under the control of engineers developing it, and is not suggested for mobile applications, safety critical systems or embedded software"
        role: primary
        published: 2018-03-25
        dated_by: printed
        applies_to: "version-independent"
        standing: current
    inference: "The sentence is in the post; the claim restates its scope limit."
    qualifiers:
      - "The scope limit is stated for the testing-in-production phases the post covers; the post does not restrict the pre-production column the same way."
produced_by: phase-1
---

# Origin

## Primary source

O1 (HIGH (single source)): "Cindy Sridharan published the three-phase test-stage chart in her Medium post Testing in Production, the safe way, dated Mar 25, 2018, after a two-column chart in her December 2017 post Testing Microservices, the sane way"

Link: [Testing in Production, the safe way](https://copyconstruct.medium.com/testing-in-production-the-safe-way-18ca102d0ef1).
Attribution corroborated by [sookocheff.com](https://sookocheff.com/post/architecture/testing-in-production/).
The quoted passages are saved in `RESEARCH-snapshot.md`, since the page refuses some automated
fetches.

## Original versus slide 31

O2 (HIGH (single source)): "The 2018 chart lists 39 entries (18 pre-production, 5 deploy, 5 release, 11 post-release) and has no formal verification, performance tests or soak tests, the three entries the slide-31 redraw adds"

## Scope the author set

O3 (HIGH (single source)): "The 2018 post states its content applies only to testing services whose deployment is under the control of the engineers developing them, not to mobile applications, safety-critical systems or embedded software"

The scope limit covers the three production phases. It is the basis for marking the deploy,
release and post-release rows ops-only where they need live traffic; it says nothing about the
pre-production column, where penetration tests are marked ops by judgment (coverage sidecar).
