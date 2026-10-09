# First-run experience

Load when: designing or reviewing what an end user meets the first time they open the app: the
first-run flow, help for new users, first-use empty states, permission requests, or the moment of
first successful use.

This covers the app's end users. Developer onboarding (a codebase, an SDK, an API) belongs to
developer-experience tooling, not to this plugin. Basis: judgment.

Confidence labels on each `Basis:` follow the plugin's research: HIGH means three or more
independent authoritative sources agree; HIGH (single source) is what one publisher states about its
own guidance; MEDIUM is one or two sources, used only as labeled judgment.

## First successful use

Name the moment a new person first gets what they came for (a first message sent, a first report
seen), then design the first run as the shortest flow to it. Measure that flow with task measures
(`reference/measurement.md`): completion and time to first successful use. How product analytics
defines "activation" is its own choice: those definitions are vendor and practitioner constructs,
and no study found shows that reaching one causes retention. Basis: judgment; judgment over MEDIUM
evidence ([mixpanel-analytics]) for the construct.

## Help in context over up-front tutorials

For a simple or conventional product, teach in context, at the moment a feature is used, rather
than with a tutorial before the person starts; an up-front tutorial did not improve performance in
the studies read and helped only in a complex, unconventional product. Basis: judgment over MEDIUM
evidence ([andersen-chi-2012], [nng-mobile-tutorials]; one study of web-game players, one of 70
people on four iOS apps).

## First-use empty states

A screen that is empty because the person is new says why it is empty and gives a direct action or
starter content, which makes it part of the first run. Basis: [carbon-empty], [nng-empty],
[material-empty], HIGH (guidance only; none measures outcomes). This plugin decides which empty
states each first-run step has and what each must offer; how they look belongs to
`/user-interface:design`.

## Progressive disclosure

Show the most important options first and offer specialized ones on request; staged disclosure
splits a task into a linear sequence of steps. Basis: [nng-progressive], HIGH (single source;
the page asserts the benefits rather than measuring them). Use it to keep the first run short.
Basis: judgment.

## Permission requests

- Ask for a permission in context, when the person starts to use the feature that needs it. Both
  platforms say so; Apple adds avoiding requests at launch unless the app cannot work without the
  permission. Basis: [apple-privacy], [android-permissions], HIGH (single source each).
- Apple and Android give opposite rules for a custom screen shown before the system prompt, so
  follow each platform's current rule for that screen rather than one shared design. Basis:
  [apple-privacy], [android-permissions], HIGH (single source each).
  - **Pointer**: for Apple's rules on when to ask and on any screen shown before the system alert,
    read the Human Interface Guidelines, Privacy, at
    <https://developer.apple.com/design/human-interface-guidelines/privacy>.
  - **As of**: 2026-10-04
  - **Recheck trigger**: the page's change log shows an update, or Apple changes App Tracking
    Transparency review rules.
  - **Pointer**: for Android's rules on asking in context, the educational screen before the system
    dialog and repeated denial, read "Request runtime permissions" at
    <https://developer.android.com/training/permissions/requesting>.
  - **As of**: 2026-10-04
  - **Recheck trigger**: the page's last-updated date moves, or a new Android release changes the
    permission model.
- When local privacy law requires a consent screen, or the app cannot work without a permission,
  check Apple's current rules on where that screen or request may sit (around the system alert, or
  inside onboarding) before placing it in the first run. Basis: [apple-privacy], HIGH (single
  source) that Apple sets such rules; judgment for the placement check.
  - **Pointer**: for Apple's rules on a permission the app needs during onboarding, read the Human
    Interface Guidelines, Onboarding, at
    <https://developer.apple.com/design/human-interface-guidelines/onboarding>; for the consent
    screen and the tracking alert, the Privacy page in the record above.
  - **As of**: 2026-10-04
  - **Recheck trigger**: the Onboarding page's change log shows an update.

## First-run flow specification

Write the first run as a user flow (`reference/flows-ia.md`), starting at every entry point a new
person can arrive from, ending at first successful use, and listing for each step (Basis:
judgment):

| Step | What it teaches or asks | Permission or consent asked here | Empty state shown | Skip or exit path | Evidence |
|---|---|---|---|---|---|

Ask for an account only when the person needs what an account gives them, and let them leave or
skip any teaching step. Basis: judgment.

[mixpanel-analytics]: https://mixpanel.com/blog/what-is-product-management-analytics/
[andersen-chi-2012]: https://grail.cs.washington.edu/projects/game-abtesting/chi2012/chi2012.pdf
[nng-mobile-tutorials]: https://www.nngroup.com/articles/mobile-tutorials/
[carbon-empty]: https://carbondesignsystem.com/patterns/empty-states-pattern/
[nng-empty]: https://www.nngroup.com/articles/empty-state-interface-design/
[material-empty]: https://m2.material.io/design/communication/empty-states.html
[nng-progressive]: https://www.nngroup.com/articles/progressive-disclosure/
[apple-privacy]: https://developer.apple.com/design/human-interface-guidelines/privacy
[android-permissions]: https://developer.android.com/training/permissions/requesting
