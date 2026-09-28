# Gotchas

## A silent regex failure looks like a clean corpus

mawk panics at compile time on interval expressions (`{0,4}`), and the scan then returns nothing
while the script still exits 0. A whole rule stopped firing and the run looked healthy: no
error, no findings, a plausible-looking summary.

If a detector reports zero candidates where you expected many, run it against one file you know
trips it before believing the zero. Every regex in this plugin's scripts uses explicit
repetition for this reason; a contributed patch that reintroduces `{n,m}` will pass its own
tests on gawk and go quiet on mawk.

## A stamp keyword next to a date is not always a stamp

`context-management-2025-06-27` is an API beta identifier. It produced an expired-stamp finding
until the keyword window narrowed, because "read" appeared earlier in the sentence and an
ISO-shaped substring appeared later.

Before reporting a stamp finding on unusual-looking text, read the line. An ISO-shaped substring
inside an identifier is not a date anybody stamped, and a finding against it is a finding about
nothing.

## A high declined count is the honest answer, not a defect

A real share of this repository's stamp candidates decline, because the corpus genuinely writes
month-name and bare-year dates ("as of July 2026", "as of 2026"). That count is a fact about the
corpus.

Do not tune the parser to shrink it. A parser that guesses at those forms manufactures findings
against dates nobody wrote down precisely, which is worse than declining them and saying so.

## Zero expiry findings can be a real result

At the 180-day default this repository's oldest parsed stamp is not yet due, so the check
correctly fires on nothing. That is a statement about the corpus, not a broken detector.

Tell the two apart with `counts.parsed`: a run that parsed hundreds of stamps and expired none
is working; a run that parsed zero is not.

## Nomination passes union, and someone will try to intersect them

Two recall-biased passes look like they should agree, and intersecting them looks like free
precision. It is not: intersection converts two recall passes into a precision filter and throws
away exactly the recall the second pass was spawned to buy. Union them and deduplicate on
overlapping ranges.
