# Journeys and service blueprints

Load when: mapping a user's journey across steps, channels and time, or the service behind it
(a journey map or a service blueprint).

Confidence labels on each `Basis:` follow the plugin's research: HIGH means three or more
independent authoritative sources agree; HIGH (single source) is what one publisher states about its
own guidance; MEDIUM is one or two sources, used only as labeled judgment.

## Journey or flow

NN/g defines a user journey as macro-level: it spans channels and a longer stretch of time and
records what the person thinks and feels. It defines a user flow as micro-level: the typical or ideal steps to complete one task
in the product, with the system's responses. Use this file for journeys and
`reference/flows-ia.md` for flows. Basis: [nng-journeys-flows], HIGH (single source).

## The two artifacts

Call the artifact a journey map (current-state or future-state) or a service blueprint; the plugin
uses no other map names. Basis: judgment.

- **Journey map.** A visualization of the process a person goes through to reach a goal. NN/g names
  five parts: the actor; the scenario and expectations; journey phases; actions, mindsets and
  emotions; and opportunities. Basis: [nng-journey-101], HIGH (single source).
- **Service blueprint.** NN/g calls it the second part of a journey map: it ties the people, props
  and processes inside the organization to the touchpoints of one journey, and suits services with
  many touchpoints across departments. Bitner, Ostrom and Morgan list five components (customer
  actions, onstage contact actions, backstage contact actions, support processes, physical
  evidence) separated by the line of interaction, the line of visibility and the line of internal
  interaction. Shostack's original blueprint also isolates fail points and sets a standard time for
  each step. Basis: [nng-blueprint], [bitner-2008], [shostack-1984], HIGH (single source each) for
  what each source says; that these are the field's consensus definitions is judgment over MEDIUM
  evidence.

Read together, they give one timeline of the person's steps with the organization's lanes beneath
it. Basis: judgment.

## Current state, then future state

- A current-state map documents today's experience and its pain points; a future-state map
  describes an improved or not-yet-existing one. Basis: [nng-journey-approaches],
  [gds-whole-problem], HIGH.
- Map the current state first, research it, then design the future state. Basis:
  judgment over MEDIUM evidence ([nng-journey-approaches], NN/g's recommendation).
- A map built from team assumptions or AI-generated data is a hypothesis map. Validate it with
  research with real users before it drives decisions; unvalidated maps tend not to gain traction.
  Basis: [nng-journey-approaches], [nng-synthetic], HIGH (single source; NN/g's position, while
  GOV.UK and ISO/TS 24082 ask for research to feed mapping without that framing).
- The evidence that maps pay off is practitioners' self-report (alignment and shared vision), not
  measured outcomes, so a map earns its cost only when it is validated and acted on. Basis:
  [nng-journey-practitioners], HIGH (single source; a small self-selected sample, n=48) for the
  survey; judgment for the conclusion.

## What the agent can draft and what it cannot

From the app itself (routes, flows, analytics, support tickets) an agent can draft the customer
actions, touchpoints, backstage steps and timing. It cannot know the person's mindsets, emotions,
offline steps or whether the map is right: those lanes come from research, or stay marked
"assumption" in the map's evidence column. Basis: judgment.

## Formats

Journeys are markdown tables, one row per step, so every cell can carry its evidence. Basis:
judgment.

Journey map:

| Phase | Step | Channel | What the person does | Thinking and feeling | Pain point | Opportunity | Evidence |
|---|---|---|---|---|---|---|---|
| Find out | Searches for how to renew | Web search | Compares two results | Unsure which site is official | Lookalike sites | Name the official route early | analytics report 2026-Q3; feelings: assumption |

Service blueprint. The line of interaction falls between the customer and onstage columns, the line
of visibility between onstage and backstage, and the line of internal interaction between backstage
and support:

| Step | Customer action | Onstage contact | Backstage contact | Support processes | What the person sees | Fail point | Evidence |
|---|---|---|---|---|---|---|---|

Opportunities in a future-state map name the need they serve, never a solution chosen in advance.
Basis: judgment.

## Omnichannel journey lanes

A journey rarely stays in one channel. Add a channel to every step and check each handoff. Basis:
judgment.

- Map the user's whole problem, including the parts outside this product and outside the
  organization, so the journey solves a whole problem and the person does not need to understand
  how the organization is arranged. Basis: [gds-point-2], HIGH (single source).
- Research and change offline channels as well as online ones, involve front-line staff (support,
  operations) in the research, and find the back-end barriers that stop a joined-up experience.
  Basis: [gds-point-3], HIGH (single source).
  - **Pointer**: for the current wording of the whole-problem and joined-up-channels points, read
    the GOV.UK Service Standard, points 2 and 3, at
    <https://www.gov.uk/service-manual/service-standard/point-2-solve-a-whole-problem> and
    <https://www.gov.uk/service-manual/service-standard/point-3-join-up-across-channels>. Written for
    UK government services; other organizations adopt them by analogy.
  - **As of**: 2026-10-04
  - **Recheck trigger**: GDS publishes a new version of the Service Standard, or renumbers either
    point.

For each handoff between channels (web, app, email, text message, phone, letter, in person,
support), record as judgment:

| Check | Question |
|---|---|
| Carry-over | What the person or their case brings across: their progress, their data, a reference. |
| Repetition | What they must say or enter again. Each repeat is a pain point. |
| Ownership | Which team or system owns the next step, and what happens when it fails. |
| Message moments | Which steps warrant an email, text message or notification, and how urgent each is. How it looks and is worded belongs to `/user-interface:design`. |
| Offline steps | Steps that happen on paper, by phone or in person, which the app's data cannot show. Mark them as coming from research or as assumptions. |

[nng-journeys-flows]: https://www.nngroup.com/articles/user-journeys-vs-user-flows/
[nng-journey-101]: https://www.nngroup.com/articles/journey-mapping-101/
[nng-blueprint]: https://www.nngroup.com/articles/service-blueprints-definition/
[bitner-2008]: https://mycourses.aalto.fi/pluginfile.php/2272345/mod_folder/content/0/Bitner%20et%20al.%202008.pdf?forcedownload=1
[shostack-1984]: https://hbr.org/1984/01/designing-services-that-deliver
[nng-journey-approaches]: https://www.nngroup.com/articles/journey-mapping-approaches/
[gds-whole-problem]: https://www.gov.uk/service-manual/design/map-a-users-whole-problem
[nng-synthetic]: https://www.nngroup.com/articles/synthetic-users/
[nng-journey-practitioners]: https://www.nngroup.com/articles/journey-mapping-ux-practitioners/
[gds-point-2]: https://www.gov.uk/service-manual/service-standard/point-2-solve-a-whole-problem
[gds-point-3]: https://www.gov.uk/service-manual/service-standard/point-3-join-up-across-channels
