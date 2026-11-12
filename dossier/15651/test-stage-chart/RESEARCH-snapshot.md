---
topic: test-stage-chart
section: snapshot
abstract: Verbatim passages of the 2018 post the origin claims quote, saved with the fetch command and date so a verifier can grade them when Medium refuses a fetch
claims: []
produced_by: phase-1
---

# Snapshot of the 2018 post

Fetched 2026-11-12 with the firecrawl scrape tool:
`firecrawl_scrape url=https://copyconstruct.medium.com/testing-in-production-the-safe-way-18ca102d0ef1 formats=[markdown] onlyMainContent=true`
(status 200). Passages below are extracted from the returned markdown with `jq` and copied
verbatim; the number is the line index in that markdown. Image lines are kept as returned.

```text
40: # Testing in Production, the safe way
52: Mar 25, 2018
---
### The Art of Testing in Production
...
108: ![](https://miro.medium.com/v2/resize:fit:546/1*KtiYN4lEDHyp929tix6yzw.png)

From my post “Testing Microservices, the sane way”

Since the publication of that post in late December 2017, I’ve had conversations with several people about the content of the post as well as on the broader topic of “testing in production” in general

Instead, I now believe that “testing in production” encompasses an entire gamut of techniques across _three distinct phases._

Press enter or click to view image in full size

120: ![](https://miro.medium.com/v2/resize:fit:700/1*LFnVVlLrgrvXQ5ScrHVKjg.jpeg)
---
However, before I proceed any further, I need to make it _explicitly_ clear that the content of this post only ever applies to the testing of **_services_** whose deployment is under the control of engineers developing it. By _absolutely no means whatsoever_ am I suggesting that this form of testing is applicable, let alone _advisable,_ for testing other types of software, such as mobile applications or safety critical systems or embedded software.
---
> Deployment is your team’s process for installing the new version of your service’s code on production infrastructure. [...] **Deployment need not expose customers to a new version of your service.**
> When we say a version of a service is **released**, we mean that it is responsible for serving production traffic. In verb form, **releasing** is the process of moving production traffic to the new version.
If the _release_ of the service went without a hitch and the newly released service is serving production traffic without any immediate issues, we can consider the _release_ to be successful. What follows a successful release is what I call the “post-release” phase.
As such, “testing” in the post-release phase resembles not so much traditional testing than _debugging_ or gathering analytics.
---
> [Testing Microservices, the sane way](https://copyconstruct.medium.com/testing-microservices-the-sane-way-9bb31d158c16) (published December 2017)
```

Chart image entries, read from
`https://miro.medium.com/v2/resize:fit:1400/1*LFnVVlLrgrvXQ5ScrHVKjg.jpeg` (downloaded with curl
and viewed 2026-11-12):

- PRE-PRODUCTION (18): unit tests, functional tests, component tests, fuzz tests, static analysis,
  property based tests, coverage tests, benchmark tests, regression tests, contract tests, lint
  tests, acceptance tests, mutation tests, smoke tests, UI/UX tests, usability tests, penetration
  tests, threat modeling.
- DEPLOY (5): integration tests, tap compare, load tests, shadowing, config tests.
- RELEASE (5): canarying, monitoring, traffic shaping, feature flagging, exception tracking.
- POST RELEASE (11): teeing, profiling, logs/events, chaos testing, monitoring, A/B tests, tracing,
  dynamic exploration, real user monitoring, auditing, oncall experience.
