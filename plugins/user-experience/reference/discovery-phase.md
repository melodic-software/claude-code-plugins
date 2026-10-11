# App stage and the discovery phase

Load when: working out the app's stage, deciding what UX work comes first, framing the problem
before building, or starting on a legacy app.

Confidence labels on each `Basis:` follow the plugin's research: HIGH means three or more
independent authoritative sources agree; HIGH (single source) is what one publisher states about its
own guidance; MEDIUM is one or two sources, used only as labeled judgment.

## Stage checklist

State the stage before recommending anything, with the signals behind it, and invite the user to
correct it. A user's correction always wins. Basis: judgment. No source defines these four stages for apps in
general; the checklist is judgment, drawn from the lifecycle phases GOV.UK names (discovery phase,
alpha, beta, live, retirement). Basis: [gds-agile-delivery], HIGH (single source) for the phase
names; judgment for the mapping.

| Stage | Signals to look for | Not enough on its own | First UX work |
|---|---|---|---|
| idea | No manifest and no application code; the user describes what they want to build. | A notes or README file. | Understand the people and the problem; every claim about users is an assumption to test. |
| greenfield | Code or a manifest exists; no shipped-product signals: no analytics SDK, no research or persona files, no support data. | A manifest alone. | Test concepts and prototypes; plan research on the riskiest assumptions. |
| existing | Shipped-product signals: an analytics SDK, research or persona files, support exports, release history the user confirms. | Recent commits alone. | Review the evidence the product already produces, then test the live product. |
| legacy | An existing app with a long history, outdated dependencies or integrations others depend on, or a user who says it is being replaced or modernized. | Old code alone. | `## Legacy start: UX-debt inventory`. |

At the idea stage there is no code to read: work from what the user describes, and label the
deliverable `assumption-based` until research with real people supports it. Basis: judgment. Treat any input that
does not come from users as an assumption that research has to prove. Basis: [gds-needs],
[uswds-principles], HIGH (UK and US public-sector normative guidance).

## The same four activities at every stage

ISO 9241-210 names four linked human-centered design activities: understand and specify the context
of use, specify the user requirements, produce design solutions, and evaluate the designs. It
leaves the methods open. Every stage runs these four; the stage only changes where the work starts
and what evidence already exists. Basis: [iso-9241-210], HIGH (single source) for the activities;
judgment for the stage reading.

## Understand the problem before building

- Before committing to build, learn about the people, the constraints (law, contracts, legacy
  technology, existing processes) and the opportunities, and do not build yet. The phase ends with
  a decision whether to go on, and stopping is not a failure. Basis: [gds-discovery-phase], HIGH
  (single source; written for UK government services).
- When the team is handed a solution, question it and restate it as the problem it should solve,
  including what is not part of that problem. Basis: [gds-discovery-phase], HIGH (single source).
- The next phase tries out different solutions: build prototypes, test the riskiest assumptions,
  and expect to throw code and many ideas away. Basis: [gds-alpha-phase], HIGH (single source).
- A service is never finished: a live service must be able to make substantial improvements
  throughout its life, so this work applies to existing and legacy apps too. Basis: [gds-point-8],
  HIGH (single source; written for UK government services); applying it to legacy apps is judgment.
  - **Pointer**: for the current wording of point 8, read the GOV.UK Service Standard, "Iterate and
    improve frequently", at
    <https://www.gov.uk/service-manual/service-standard/point-8-iterate-and-improve-frequently>.
  - **As of**: 2026-10-04
  - **Recheck trigger**: GDS publishes a new version of the Service Standard, or renumbers point 8.
- **Pointer**: for the current phase guidance, including typical durations, read the GOV.UK Service
  Manual's discovery phase and alpha pages at
  <https://www.gov.uk/service-manual/agile-delivery/how-the-discovery-phase-works> and
  <https://www.gov.uk/service-manual/agile-delivery/how-the-alpha-phase-works>. Written for UK
  government services; other organizations adopt them by analogy.
- **As of**: 2026-10-04
- **Recheck trigger**: GDS revises either page, or restructures the agile delivery section.

## Assumptions and what to test first

- Make the team's assumptions explicit and plot them on importance against evidence; test the
  important assumptions with the least evidence first. Bland names desirability, feasibility,
  viability and adaptability; Torres adds usability and ethical as categories and adopts the same
  map. Strategyzer's current program page names Bland's fourth category survivability rather than
  adaptability (seen only in a search result). Basis: [bland-assumptions], [torres-assumptions], HIGH (single source each).
- An opportunity solution tree runs from one desired outcome, through the opportunity space (needs,
  pain points, desires) and candidate solutions, to the assumption tests; a product manager,
  designer and engineer build it together and revisit the opportunities every three or four
  interviews. Basis: [torres-ost], HIGH (single source).
- Cagan alone splits risk by role: the product manager answers for value and viability, the
  designer for usability, the engineer for feasibility. The split is about responsibility for a
  risk, not who does the work, which all the sources describe as shared. Basis: [cagan-risks],
  [torres-trio], [gds-roles], HIGH for shared work; Cagan's split is a single author's view.
- This plugin takes the user-side risks: usability (Cagan's design risk), plus desirability (a
  category in Bland's and Torres's maps) and the ethical risk to users (a Torres category).
  Feasibility goes to engineering; value and viability go to product management, whose requirements
  document is `/planning:prd`. Basis: judgment.
- Among the research-related responsibilities NN/g's survey examined, product managers and UX
  practitioners disagree most about who runs discovery phase work, so agree it explicitly at the
  start. Basis: [nng-pm-ux], HIGH (single source; a self-selected 2021 sample).

## The organization around an existing app

NN/g's UX maturity model rates a whole organization, not one team, on strategy, culture, process and
outcomes across six stages from Absent to User-Driven. Use it to judge how much research the
organization can take up, not to grade a single project. Basis: [nng-maturity], HIGH (single
source) for the model; judgment for its use here.

## Legacy start: UX-debt inventory

Start a legacy app by listing its UX debt before proposing a redesign. Basis: judgment.

- UX debt is the ongoing problems in the experience left by a fast, easy or careless solution that
  hurts users. Find it through frequent user feedback. Basis: [nng-ux-debt], HIGH (single source; a practitioner firm's framing, not a
  standard).
- Record each item with the fields NN/g suggests. Basis: [nng-ux-debt], HIGH (single source).

| Item, from the user's standpoint | Where in the experience | How often | Reported by | Effort to resolve | Evidence |
|---|---|---|---|---|---|
| People cannot find how to change their delivery address | Account, delivery settings | weekly support contacts | support team | small | support export 2026-09 |

- Take a baseline measure of the tasks the redesign will change before changing them, using
  `reference/measurement.md`, so the redesign can show what it improved. Basis: judgment.
- Where an old process or system blocks a good experience, change it rather than design around it.
  Basis: judgment over MEDIUM evidence ([gds-discovery-phase]; written for UK government
  services).

[gds-agile-delivery]: https://www.gov.uk/service-manual/agile-delivery
[gds-needs]: https://www.gov.uk/service-manual/user-research/start-by-learning-user-needs
[uswds-principles]: https://designsystem.digital.gov/design-principles/
[gds-discovery-phase]: https://www.gov.uk/service-manual/agile-delivery/how-the-discovery-phase-works
[gds-alpha-phase]: https://www.gov.uk/service-manual/agile-delivery/how-the-alpha-phase-works
[gds-point-8]: https://www.gov.uk/service-manual/service-standard/point-8-iterate-and-improve-frequently
[bland-assumptions]: https://www.strategyzer.com/library/how-assumptions-mapping-can-focus-your-teams-on-running-experiments-that-matter
[torres-assumptions]: https://www.producttalk.org/assumption-testing/
[torres-ost]: https://www.producttalk.org/opportunity-solution-trees/
[cagan-risks]: https://www.svpg.com/four-big-risks/
[torres-trio]: https://www.producttalk.org/product-trio/
[gds-roles]: https://www.gov.uk/service-manual/the-team/what-each-role-does-in-service-team
[nng-pm-ux]: https://www.nngroup.com/articles/pm-ux-different-views-of-responsibilities/
[nng-maturity]: https://www.nngroup.com/articles/ux-maturity-model/
[nng-ux-debt]: https://www.nngroup.com/articles/ux-debt/
[iso-9241-210]: https://www.iso.org/standard/77520.html
