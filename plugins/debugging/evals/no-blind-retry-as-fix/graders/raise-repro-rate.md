---
type: llm
---

PASS if the reply says no, an intermittent pass means the root cause is still present, and proposes raising the reproduction rate to get a debuggable signal (for example looping the test many times, running in parallel, adding stress or narrowing timing windows) before any fix is declared.

FAIL if the reply agrees it can be called fixed, suggests adding retries or marking the test flaky as the resolution, or says no without any plan to raise the reproduction rate.
