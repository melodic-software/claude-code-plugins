# Recipe: security posture

Covers the credential, authentication, and app-trust bundle — five primary areas audited
together because they share a threat model and the same gate-heavy access profile:
`authentication-security` (2FA, SSO, session and credential policy), `advanced-security`
(security configurations, global settings, feature enablement), `github-apps` (installed apps,
permission creep, org app policy), `oauth-app-policy` (access restrictions, approved apps), and
`personal-access-tokens` (org PAT policy, active tokens, pending requests). What this recipe adds
over the generic [`../method-ladder.md`](../method-ladder.md) is the curated question set, the
posture heuristics, and the gate-diagnosis discipline specific to these surfaces — not the
mechanics. Every concrete "how" (which command, which endpoint, which credential a surface
demands, what a feature is called this quarter) resolves at runtime through the ladder against
freshly fetched official docs and live probes. This file names none of it on purpose: these
surfaces move fast, and vendored specifics would be stale before they were read.

## Credential-and-gate preflight

Run the ladder's rung 0 first, then layer these area-specific diagnoses on top. Security surfaces
gate more aggressively than any other area in this plugin, so establish what the session can
actually reach before making a single claim — an unreachable surface is not an absent one.

- **Role standing.** Most of this bundle requires org-owner (or, at enterprise scope,
  enterprise-owner) standing to read policy state, not merely repository admin. Diagnose the
  session's effective standing from live probe results, not from an assumed role table; a member
  session will see a truncated, misleading picture of every sub-area here.
- **Credential modality (the load-bearing one).** Per the ladder's rung 0 modality diagnosis, some
  org-governance surfaces in this bundle were observed to accept only an installed-App credential,
  not an interactive user-session token — the token governance and app-policy surfaces most of all.
  A user session can hit an authorization failure on these that looks identical to "feature off" or
  "nothing configured." Determine the credential kind the session holds and confirm, from the
  freshly fetched docs for the specific surface, which modality that surface demands before
  interpreting any empty or failed read.
- **Plan and feature gating.** Advanced-security capabilities, and several authentication-security
  controls (SSO, session policy, IP-based controls), are gated by plan and by whether a licensed
  feature is enabled for the account. The feature set and its packaging were mid-change at research
  time — resolve current availability from the fetched docs for the account's plan, then probe a
  surface known-available on that plan for contrast, rather than assuming a gate is drift.
- **SSO-authorized session.** Where SSO is enforced, an otherwise-valid credential can still be
  refused until its session is SSO-authorized for the org. Treat an SSO-authorization failure as a
  distinct, nameable gate — never as an absent setting or a finding.

Each requirement above is a diagnosis step, not a capability lookup. Resolve the actual current
requirement per surface from fetched docs plus live probes, exactly as the ladder prescribes.

## Audit-question checklist

One continuous list, grouped by sub-area. Aim to answer every applicable item; report any the
credential cannot reach as a gate (see the drift section), never as a silent pass.

**Authentication security (2FA, SSO, session/credential policy)**

1. Is two-factor authentication required org-wide, and does the requirement's coverage actually
   include every member, outside collaborator, and billing manager — or only a subset?
2. Are there standing 2FA exemptions or a grace-period population, and is each exemption recorded
   with a rationale rather than lingering unexplained?
3. Is single sign-on enabled and enforced, and are there members or bots operating on
   unauthorized (non-SSO) sessions that enforcement has not yet caught?
4. Do session, IP-based, and credential-lifetime controls match the declared posture, and is any
   authentication control set at a scope (org vs enterprise) different from where the convention
   expects it?

**Advanced security (configurations, global settings, feature enablement)**

1. Which security features (secret scanning, push protection, code scanning, dependency review and
   alerting) are enabled, and is that enablement expressed through a named security configuration
   or left to per-repository toggles?
2. Does a single global/default configuration apply consistently, or has per-repository drift
   accumulated so that repos of the same class carry different security postures?
3. Are new repositories brought under the intended security configuration automatically, or can a
   freshly created repo sit outside coverage until someone notices?
4. For any feature the account's plan gates, is the gap a deliberate, licensed decision or an
   unnoticed coverage hole — and is that distinction recorded?

**GitHub Apps (installed apps, permission creep, org app policy)**

1. What is the full inventory of installed GitHub Apps at the org, and does each still map to an
   active, understood need rather than a forgotten integration?
2. Has any installed app's permission footprint grown since installation (permission creep), and
    is the current footprint justified by what the app actually does today?
3. Are there apps installed or managed by members who have since departed, leaving ownerless trust
    relationships?
4. Is the org's policy for who may request, install, and manage apps set as intended, and are
    app-manager grants scoped to people who still need them?

**OAuth app policy (access restrictions, approved apps)**

1. Are third-party OAuth app access restrictions enabled for the org, or is the org running in the
    open-by-default posture where any member can authorize any app against org data?
2. Is the approved-apps list current — every entry still needed, still trusted, and none left
    approved long after its purpose ended?
3. Do any pending or previously denied app-authorization requests need review or a recorded
    decision?

**Personal access tokens (org PAT policy, active tokens, pending requests)**

1. What is the org's PAT policy: are classic tokens allowed at all, is an approval flow required,
    and does the live posture match the declared one (for example a stated "no classic PATs")?
2. What active tokens hold access to org resources, and are any stale by age, over-scoped for
    their use, or tied to a departed owner?
3. Are there pending token-access requests awaiting a decision, and is the fine-grained-vs-classic
    balance moving toward the intended end state or away from it?
4. Do the org's credential-lifetime and expiry expectations hold across the active token
    population, or are long-lived credentials accumulating past the intended horizon?

## Posture heuristics

Framing to apply when interpreting findings; the exact mechanism behind each resolves live.

- **Least privilege as the default reading.** For apps and tokens, treat any grant broader than the
  demonstrated need as a finding to raise, not a neutral observation. Permission creep on an
  installed app and an over-scoped token are the same anti-pattern in two surfaces.
- **Deny-by-default for third-party access.** An org where OAuth app access restrictions are off,
  or where app-request policy is open, is running a weaker posture than one that admits apps
  deliberately. Prefer the closed stance and flag the open one, even absent a specific declared
  convention — naming it as a fetched-docs recommendation when no convention exists.
- **Tighten over time.** Authentication and advanced-security controls are expected to ratchet
  toward stricter, not looser. A control that has loosened since a prior state deserves a why.
- **Secure-by-default configuration.** Prefer a single named security configuration applied
  org-wide with new repos auto-enrolled over scattered per-repo toggles; the latter is where
  coverage holes hide.
- **Review cadence.** Installed apps, approved OAuth apps, and active tokens all accrue risk with
  age. Recommend a recurring review — inventory, re-justify, revoke the unneeded — rather than a
  one-time cleanup, and treat a long gap since the last review as itself a finding.
- **Exceptions carry rationale.** A deviation from the secure default is acceptable when it is
  recorded with a reason; an undocumented deviation is the finding. This mirrors how the
  conventions file expects decided exceptions to be written down so an audit does not re-flag them.

## Drift comparison against declared conventions

Follow [`../conventions-file.md`](../conventions-file.md): read the layered conventions (user,
team, local overlay) in order and extract the security-relevant declarations before comparing
anything. Typical declarations in this bundle: "2FA required for all members," "SSO enforced," "no
classic PATs" / "fine-grained tokens only," an app allow-list or install-request policy, an
OAuth-restriction expectation, and a baseline set of enabled security features.

Then, for each sub-area:

1. **Disambiguate before you claim drift.** Because these surfaces are the most gate-heavy in the
   plugin, run the ladder's 403/404 disambiguation (see the table in
   [`../method-ladder.md`](../method-ladder.md)) on every non-answer *first*. An App-only-caller
   refusal, a plan/SKU gate, a missing scope, an SSO-authorization gap, and a genuinely unset
   control all look similar from a single failed read — and mislabeling any of them as "drift" is
   the predictable failure mode here. Never report a gate as drift.
2. **Compare live state to the declaration, per sub-area.** Authentication-security: enforced 2FA
   and SSO state and exemptions against the declared requirement. Advanced-security: enabled
   features and configuration coverage against the declared baseline. GitHub-apps: installed
   inventory and permission footprints against the allow-list and least-privilege expectation.
   OAuth-app-policy: restriction state and approved-apps list against the declared stance.
   Personal-access-tokens: PAT policy, active-token hygiene, and pending requests against the
   declared token posture.
3. **Cite the expectation basis for every finding.** Say whether the "should be" came from a
   declared convention (naming the layer, per the conventions file) or, when no convention covers
   the point, from a freshly fetched official-docs recommendation — and name that provenance so the
   reader can tell a consumer standard from a docs default.
4. **Report the gates.** Every declaration the current credential cannot verify — because of role,
   modality, plan, or SSO — is reported as a gate with its cause, not silently skipped and not
   counted as a pass. Degrade honestly to guidance-only for what stays out of reach.

When no conventions file exists at any layer, compare against the current official-docs
recommendations for each sub-area and label that provenance explicitly, rather than any
from-memory "best practice."

## Dated caveats (re-verify live)

Constraints observed at research time (2026-07). Each is a pointer to something that was moving,
not a fact to rely on — confirm current reality through the ladder before acting.

- Some org-governance and app-policy surfaces in this bundle were observed, at research time
  (2026-07), to accept only an installed-App credential rather than an interactive user session —
  meaning a plausible-looking user-session failure may reflect the required credential modality,
  not an absent setting. Observed against a non-Enterprise org. Re-verify live before relying on
  this.
- Advanced-security features were mid-rebrand and mid-repackaging at research time (2026-07): what
  the capabilities are named, how they are bundled, and which plan unlocks each were all in flux.
  Resolve current naming and packaging from the fetched docs for the account's plan. Re-verify live
  before relying on this.
- Personal-access-token policy and governance surfaces were evolving at research time (2026-07),
  including which actions were reachable programmatically versus settings-UI-only. Do not assume a
  prior reachability. Re-verify live before relying on this.
- OAuth-app access-restriction and approval surfaces were observed to be settings-UI-only at
  research time (2026-07), per the then-current docs. That may have changed. Re-verify live before
  relying on this.
- Certain authentication controls existed only at enterprise scope (not org scope) at research time
  (2026-07); where a control lives affects who can read it and whether its absence at org scope is
  even a finding. Re-verify live before relying on this.

None of the above should be treated as current mechanics — they are dated observations flagging
where volatility was highest, so the ladder's fresh fetch does the real work each run.

## Doc pointers

Stable entry hubs only. Resolve the exact current page live from each hub (or the site's own
search) and pass it through the ladder's fetch-integrity check before grounding on it — never
ground on a deep URL carried in from memory.

- Authentication and account security — <https://docs.github.com/en/authentication>
- Code and supply-chain security — <https://docs.github.com/en/code-security>
- GitHub Apps and app management — <https://docs.github.com/en/apps>
- Organization administration (app policy, OAuth restrictions, PAT policy) —
  <https://docs.github.com/en/organizations>
