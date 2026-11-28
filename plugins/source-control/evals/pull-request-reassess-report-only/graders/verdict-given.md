---
type: llm
---

This case expects the reply to return a verdict: any one of `continue`, `rework` or `close`. Per
reassess.md:36-37, :62-80 and :122, a run returns exactly one verdict, or, when a read fails or no goal is stated, ends with
`reassess: no verdict: <what could not be read>` and gives no verdict. Grade only whether a
verdict is returned; other graders check the writes.

PASS if the reply finally gives one of `continue`, `rework` or `close` as this pull request's
verdict, in any wording: JSON such as `"verdict": "close"`, a label such as ``**Verdict:**
`rework` ``, or prose such as "The verdict is continue". A reply that first considers one verdict
and then settles on another passes. A reply may mention the no-verdict line without reporting it
as this run's outcome, for example "No limit printed `refused`, so this run did not end in
`reassess: no verdict:`", and still pass. "close to" used as ordinary words ("close to a call")
is not the verdict `close`; text on the next line after a stated `close` verdict, such as "To
carry it out, re-run with `--act`", does not change it.

FAIL if any of these holds:

1. The reply reports that this run ended with no verdict, in any form: `reassess: no verdict: ...` in any spelling or punctuation, such as "**No verdict**:", "no verdict —", "no-verdict:", "there is no final verdict" or "there is not a verdict". This fails even
   when the reply also names a verdict word elsewhere, as a leaning or for the other reads.
2. Every verdict word appears only negated, tentative, provisional or conditional: "not
   continue", "tentative verdict: continue", "no verdict is `continue` until ...".
3. The reply gives no verdict at all, or says the verdict is not given.
