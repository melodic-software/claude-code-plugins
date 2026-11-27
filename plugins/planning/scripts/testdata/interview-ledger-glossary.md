# /planning:interview Checklist

Planning version: 4.2.0

## Steps

- [x] Step 1: Survey before you ask. Read existing context, the topic's memory slice, conversation history; identify what's already settled
- [x] Step 1.5: Auto-detect (default action only). Routed to Q&A loop: open layout decisions remain
- [x] Step 2: Drive the frontier-rounds loop
- [x] Step 2 exit: Assumption sweep
- [x] Step 3: Recognize the stop condition
- [x] Step 4: Persist the Brief (Finish line confirmed by the requester after the Brief was written, round 22)
- [x] Every round boundary: bigger-than-you-thought check (`context/routing.md`) (not recorded per round in this run; a gap Q25 fixes)
- [ ] Step 5: Hand off

## Constraint ledger

- C1 | confirmed | the digest renders in common mail clients, on desktop and phone widths; wide tables cost readers effort | user, round 1
- C2 | confirmed | layout rules follow published readability research, not team habit | user, round 1
- C3 | confirmed | the per-section item limit is configurable (account settings and team defaults), shipping a sensible default | user, round 2
- C4 | confirmed | delivery mechanics (queues, templates) are settled at planning, not in this interview | user, round 6
- C5 | confirmed | no item appears twice anywhere in the digest; every section is judged by how quickly a reader finds what changed | user, round 12

## Starting point

- The weekly digest works; the requester wants layout and reading-comfort changes, starting with the crowded summary block (sample email, round 1).

## Problems

- P1 | the weekly digest is hard to skim: long rows on wide screens, cryptic status codes, repeated items, a closing summary nobody reads | agreed

## Terminology matrix

## Glossary lookup

Glossary lookup (round 8): docs/terms.md holds none of: digest, highlight block, item limit, summary card, changelog. Clash: docs/terms.md "backlog" = tickets not yet scheduled; the digest uses it for items not yet shown.

## Open-question register

- Q1 | answered | round 1 | Which audience is this digest for? | team leads (user, round 5) kind:: discovery
- Q2 | answered | round 1 | Should the summary block become a labeled list, one fact per line? | yes: labeled list, one fact per line (user, round 2); labels narrowed by Q34 (summary labels): no Recent list; New, Coming up, Later problem:: P1
- Q3 | answered | round 1 | Keep rows short by layout rather than truncating at 60 characters? | yes: short by layout, no truncation (firm yes at the confirmation, user, round 21; earlier "likely fine", round 2) problem:: P1
- Q4 | answered | round 1 | Limit each section to 5 items? | a limit, configurable through account settings, with a shipped default; the default value is asked separately (user, round 2)
- Q5 | answered | round 2 | Highlight block: bold headline, then labeled bullets? | yes, as recommended: bold headline, then Owner/Due/Status/Link bullets (user, round 4) problem:: P1
- Q6 | answered | round 2 | Ship the limit with a default of 5? | yes, default 5 (user, round 4) depends:: Q4
- Q7 | answered | round 2 | Where is the limit set? | answered-from-evidence: an account setting with a team default. Basis: docs/settings.md:40-52 depends:: Q4
- Q8 | answered | round 3 | Empty section: say why it is empty, on two labeled lines? | yes: Nothing new: <reason>, then Next check: <when> (user, round 4) problem:: P1
- Q9 | answered | round 3 | Blank line before each summary label? | answered-from-evidence: yes. Basis: the round 2 sample shows labels run into the line above (user, round 3)
- Q10 | answered | round 6 (added in round 4) | Which text styles (bold, italic, monospace, quote, strikethrough, color) to use, and for what? | yes: bold the item title and the headline, nothing else; monospace for ids, quote for excerpts, no italic or strikethrough, warnings in words, color never alone (user, round 7) problem:: P1
- Q11 | answered | round 4 | How should the item details render? | yes: a short linked label at the end of each line, full links to the tracker; no References list; labels for meeting notes and other offline sources to be reworked (user, round 12) reopened:: round 10
- Q12 | answered | round 5 | Settle template and delivery changes at planning? | yes, at planning; this interview settles only how the digest reads (user, round 6)
- Q13 | answered | round 10 (added in round 7) | Separate sections by a blank line, section header and bold title, no divider? | yes: section name in the title line, a divider between sections, no extra headers (user, round 11) reopened:: round 10
- Q14 | answered | round 11 (added in round 7) | Number detail lines so readers can point at them (Q14.3, Q14b, Q14 [2])? | yes: Q14.3 a detail line, Q14b an option, sources by label, no source codes; must read naturally (user, round 12) reopened:: round 10
- Q15 | answered | round 7 | Closing summary grouped by team, one plain line per change? | yes: summary grouped by team, one plain line per change, changes in words (user, round 8) problem:: P1
- Q16 | answered | round 7 | Keep the glossary and decision-record timing; summary shows only what they admitted? | yes: keep glossary-first and record-per-round timing; the summary lists only records written and terms agreed (user, round 8); how to keep the steps from being skipped asked separately
- Q17 | answered | round 8 | Should a check stop the glossary and record steps from being skipped? | yes: the release check fails when either step left no entry in the ledger; wording unchanged (user, round 9)
- Q18 | answered | round 8 | Make the limit the only new setting for now? | answered through Q31: the limit and the link style are the two new settings; add another only when someone asks to change a default (user, round 16)
- Q19 | answered | round 9 (added in round 8) | Closing line says read more or unsubscribe, from the help page? | yes: one pointer line to the help page, no copy of its text (user, round 12)
- Q20 | answered | round 8 | Closing summary: status codes, change wording, assumptions | yes: important items first, grouped summary, checks in plain words, no internal codes; the summary is the last full overview, with no repetition (user, round 12) problem:: P1
- Q21 | answered | round 12 | Link each item to the ticket it came from? | yes: an item links to its exact ticket, in the link style the setting picks (Q31); deep links work without a sign-in prompt only for readers already signed in; a comment is quoted in a few words (user, round 14)
- Q22 | answered | round 12 | Header counts only shipped items; backlog line only when it applies? | yes: "N items shipped this week"; a backlog line only when its trigger applies (user, round 13)
- Q23 | answered | round 12 | Only reader-facing items take numbers; internal items keep their own prefix? | yes: only items readers act on take numbers; other kinds take their own clear prefixes (I internal, M maintenance), each defined where it first appears (user, round 13)
- Q24 | answered | round 12 | Backlog suggestion on the overflow signal only? | yes: drop the fixed count; the full trigger set is asked separately (user, round 13)
- Q25 | answered | round 13 | Backlog notice on three signals, weekly count recorded? | yes: first-week notice, the two-week signal, and a check at send time when items this digest cannot cover remain; each week's count recorded in the ledger (user, round 14)
- Q26 | answered | round 13 | Digest drops unused sections, plain-word headings? | yes: a section appears when its first item is written; a section only one audience uses is never sent to another; headings in plain words (user, round 16: sections cannot be dropped early, since use is known only as the week goes)
- Q27 | answered | round 13 | Inline previews as their own effort, filed as a ticket? | yes, deferred: its own effort with a design review and a trial, not limited to links (previews and summaries); filed as https://tracker.example.com/browse/DIG-412 (user, round 14)
- Q28 | answered | round 14 | Item spanning several tickets: first-ticket link, range named in the label? | yes: name the range (DIG-80 to DIG-100); with a link setting the link opens the first ticket; one per project (user, round 16)
- Q29 | answered | round 14 | Planning shows replaced answers before asking for sign-off? | yes: planning shows each changed answer in the sign-off request; sign-off covers what it showed (user, round 16)
- Q30 | withdrawn | round 14 | Links built per mail client (web link, or app link on phones)? | merged into Q31 (link style setting): the client-aware link becomes one value of that setting (round 15)
- Q31 | answered | round 15 | Link style a setting, plain ticket id by default, web links chosen in settings? | yes: plain DIG-48 text by default; web or app links chosen in account or team settings; this team sets web (user, round 16)
- Q32 | answered | round 16 | Fold the short digest into the default digest? | yes: absorb short into the default and remove every reference to it; the default lists everything, the ledger is the item list, archive stays (user, round 17)
- Q33 | answered | round 16 | Same layout for the mobile app, checked once by screenshot? | yes: one layout for mail and app, checked once with an app screenshot (user, round 17)
- Q34 | answered | round 17 | Summary labels: Recent, New, Coming up, Later, only when non-empty? | yes, narrowed by the user: the summary shows no list of earlier items at all (not even since last week); an earlier item appears only inside a section it informs, as local context; summaries keep New, Coming up and Later, each only when non-empty; what shows by default may vary by audience and team (detail for planning) (user, round 18)
- Q35 | answered | round 17 | Offline sources named in plain words, linked where stored? | yes: offline sources named in plain words, linked where stored, never an id or week number (user, round 18)
- Q36 | answered | round 17 | Limit applies in shared team digests, hard ceiling of 8? | yes: the configured limit applies in every digest with the research-backed default of 5; the shared digest's 8 stays the ceiling (user, round 18)
- Q37 | answered | round 17 | Say upcoming items to readers; no new glossary entries? | yes: say upcoming items to readers; no new glossary entries (user, round 18)
- Q38 | deferred | round 18 | Layout and template details the sweep found, for planning: setting names and values, ledger headings, quote form, link range rule, app card, important-item order, help pointer wording, internal-item naming | arbiter: /planning:design
- Q39 | answered | round 18 | Confirm the consequences that follow from your answers (links follow the link setting, the count setting is removed, overflow items go to next week, labels plain, icons stay, archive stays) | yes: all thirteen as stated, including the help text saying upcoming items instead of backlog (user, round 19)
- Q40 | answered | round 19 | Source labels without nested parentheses: name after a comma? | yes: one pair of parentheses, the name after a comma; origin: ours in options (user, round 20)

## Assumption sweep

- sweep 1 | register through Q33
- S1 | sweep 1 | hedged | decision | Q3 | deferred: closing summary (needs a firm yes)
- S2 | sweep 1 | hidden-default | decision | limit setting name and values | Q38
- S3 | sweep 1 | hidden-default | decision | link-style setting name and values | Q38
- S4 | sweep 1 | contradiction | decision | old item-count setting | Q39
- S5 | sweep 1 | contradiction | decision | shared-digest ceiling of 8 vs default 5 | Q36
- S6 | sweep 1 | undecided | decision | items over the limit | Q39
- S7 | sweep 1 | coined-term | decision | "Coming up (over the limit of 5)" | Q34
- S8 | sweep 1 | coined-term | decision | "Recent this week", "Worth a look" | Q34
- S9 | sweep 1 | contradiction | decision | Recent: list vs no repetition | Q34
- S10 | sweep 1 | undecided | decision | order of summary lines | Q34
- S11 | sweep 1 | undecided | decision | app summary card | Q38
- S12 | sweep 1 | contradiction | decision | Q11 tracker links vs Q31 | Q39
- S13 | sweep 1 | contradiction | decision | Q21 links vs Q31 | Q39
- S14 | sweep 1 | contradiction | fact | Q21 wording | Q39
- S15 | sweep 1 | undecided | decision | labels for offline, non-ticket sources | Q35
- S16 | sweep 1 | undecided | decision | excerpt quote and detail levels | Q38
- S17 | sweep 1 | undecided | decision | sub-item names for I and M items | Q38
- S18 | sweep 1 | undecided | decision | form of team in title line | Q39
- S19 | sweep 1 | undecided | decision | labels plain, status icons | Q39
- S20 | sweep 1 | contradiction | decision | ids in the closing summary | Q39
- S21 | sweep 1 | undecided | decision | which items are important | Q38
- S22 | sweep 1 | undecided | decision | what counts as the step's entry | Q38
- S23 | sweep 1 | contradiction | decision | Q17 vs C4 | Q39
- S24 | sweep 1 | unstated-value | decision | two-week signal measure | Q38
- S25 | sweep 1 | undecided | decision | send-time backlog check | Q38
- S26 | sweep 1 | undecided | decision | what the shipped count counts | Q38
- S27 | sweep 1 | coined-term | decision | M prefix; I, R, X prefixes | Q38
- S28 | sweep 1 | hidden-default | decision | ledger heading names | Q38
- S29 | sweep 1 | coined-term | decision | "archive" | Q39
- S30 | sweep 1 | undecided | decision | stop condition; send cap | Q39
- S31 | sweep 1 | undecided | tenant | who sets this team's link style | deferred: the team admin (account settings)
- S32 | sweep 1 | undecided | decision | links in the app; who checks | Q38
- S33 | sweep 1 | undecided | decision | format of planning's change list | Q38
- S34 | sweep 1 | undecided | decision | wording of the help pointer line | Q38
- S35 | sweep 1 | unstated-value | decision | quote length and form | Q38
- S36 | sweep 1 | undecided | decision | digest terms in docs/terms.md | Q37
- S37 | sweep 1 | contradiction | decision | "backlog" clash | Q37
- S38 | sweep 1 | undecided | decision | "one per project" | Q38

- sweep 2 | register through Q37
- S1 | sweep 2 | contradiction | decision | Q2 vs Q34 | Q39
- S2 | sweep 2 | undecided | decision | Q34 varies by audience | Q38
- S3 | sweep 2 | undecided | decision | New vs Coming up | Q39
- S4 | sweep 2 | contradiction | decision | shipped and backlog lines | Q39
- S5 | sweep 2 | undecided | decision | Coming up label number | Q39
- S6 | sweep 2 | hidden-default | decision | summary order | Q39
- S7 | sweep 2 | undecided | decision | form of earlier-item context | Q39
- S8 | sweep 2 | contradiction | decision | item handles in labels | Q39
- S9 | sweep 2 | undecided | decision | sources with no location | Q39
- S10 | sweep 2 | hidden-default | decision | limit above 8 in shared digest | Q39
- S11 | sweep 2 | hidden-default | decision | whose settings in shared digest | Q39
- S12 | sweep 2 | undecided | decision | backlog in help text | Q39
- S13 | sweep 2 | contradiction | decision | glossary none-admitted entry | Q38

## ADR outcomes

Checked with the decision-record admission test (round 17); records are written in the implementation change, in docs/decisions.

- Q6 (item limit default 5) | declined: a configurable default, easy to reverse; no trigger beyond the weighed alternative
- Q32 (one digest form) | record: removes the public short-digest option (an interface of the product)
- Q31 (link style setting) | record: adds a public setting and fixes the plain default for every team (interface)
- Q24/Q25 (backlog triggers) | record: removes the public item-count setting; a decision not to keep a count
- Q23 (numbers for reader-facing items only) | record: the ledger format other tools read (interface between tools)
- Q17 (checks enforce skipped steps) | record: not discoverable from the code; wording alone was tried and failed
- every other decision | declined: layout rules with no trigger beyond the weighed alternative

## Reopened answers

- Q13 | round 10 | was: yes: blank line, section header and bold title, no divider (user, round 8: samples judged separated) problem:: P1 | fact: design review (round 10): the section header and the item title are two bold lines separated by the same single blank line as every block inside a section, so a section boundary looks like any inner boundary; a visible divider keeps the boundary where whitespace alone does not, and the divider renders as a thin rule in every tested client (samples 19-21; readability notes, section 4).
- Q14 | round 10 | was: yes: numbered detail lines; Q14.3 a line, Q14b an option, Q14 [2] a source (user, round 8) problem:: P1 | fact: design review (round 10): numbered detail lines collide with [n] source markers (Q14.2 vs Q14 [2]); the style guide ties numbering to sequence or priority, not to reference in general (house style guide, lists).
- Q11 | round 10 | was: yes: [n] markers, sources listed once under References: (user, round 6) problem:: P1 | fact: design review (round 10): [n] source markers share the number set of numbered detail lines, and per-section References blocks put long links between the facts and the headline (samples 19-20).
- Q18 | round 15 | was: yes: no other layout rule configurable until someone asks (user, round 9) | fact: support note (round 15): app links assume the mobile app is installed and open without a prompt only on phones that have it; the digest goes to every team, so other readers get a store page or no working link; the team-neutral settings rule puts one team's preference in that team's settings, which needs a link-style setting.

## Self-answered facts

- F1 | answered-from-codebase | Where does the crowded summary block come from? | the template asks for the summary "in two or three sentences" | templates/digest/summary.html:170
- F2 | answered-from-codebase | Is there a per-section item limit today? | No: "no limit on items per section except the shared digest's" | docs/digest.md, "Sections"
- F3 | answered-from-research | Do the status icons meet the research's icon rule? | Yes: one leading icon per line, and the words still carry the meaning | readability notes rule 10 (accessibility guidance on color and icons)
- F4 | answered-from-research | Does the call to action sit last? | Yes: the help pointer is the last line of the digest | docs/digest.md "Footer"; readability notes rule 8

## Decision tree (`short` digest only)

Not the short digest.

## Skip criteria

See template.
