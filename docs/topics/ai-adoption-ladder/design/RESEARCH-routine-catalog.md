# Research: Catalog of Recurring Engineering Work — Candidates for Scheduled Agent Routines

Compiled 2026-07-17. Method: six parallel research agents (broad sweep → primary-source funnel), synthesis by lead. Source tiers flagged: [DOCS] official product docs, [PRIMARY] canonical literature, [BLOG/PR] vendor marketing, UNVERIFIED where no primary was fetched.

## Summary

- Authoritative toil taxonomy exists: SRE Workbook Ch.6 names six toil sources (business processes, production interrupts, release shepherding, migrations, cost/capacity, troubleshooting opaque architectures). DORA publishes capabilities, NOT a task taxonomy — citing DORA for one is overreach.
- The domain splits cleanly: deterministic rule engines own date/threshold mechanics (stale bots, quarantine triggers, version bumps, coverage gates); agent judgment owns semantic work (dedup, classification, routing, readiness, root-cause, theming). Mature systems compose both — this validates keeping deterministic checks in plain cron.
- In AIOps, shipped AI agents are almost all EVENT-triggered (per-alert/per-incident), not scheduled; the genuinely recurring reviews (SLO/error-budget, alert-noise, on-call handoff) remain human-cadenced with standing dashboards — an open niche for scheduled advisory routines.
- The strongest direct-change precedents are where truth is mechanically checkable: Meta SCARF (daily auto-generated dead-code deletion CRs, 100M+ LOC), flaky-test auto-quarantine (Google/Trunk/BuildPulse/Datadog), Renovate/Dependabot automerge policies — each is a per-work-class guardrail precedent.
- Four independent vendors (Anthropic Routines, GitHub gh-aw/agentics, Devin Scheduled Sessions, OpenAI Codex Automations) showcase the SAME core recurring set: triage, status/digest, review, docs drift, dependency maintenance, deploy verification — convergent evidence for the class catalog.
- Access split is real: most classes are repo/CI/tracker-scoped; alert triage, deploy verification, analytics/experiment review, and VoC theming require production telemetry or product-feedback systems — isolation policy must distinguish these.
- Terminology: "goal" (completion-condition loop, separate grader model) is the strongest cross-vendor primitive (Claude Code + Codex CLI, both official); "scheduled task" and "background agent" are cross-vendor; "routine" (Claude) and "playbook" (Devin) are single-vendor names for the same saved-config-plus-trigger concept; "batch" means bulk inference, not recurring agents.
- 39 classes cataloged in the taxonomy table below, each with judgment level, output shape, access needs, and precedent.

## Q1 — Toil / recurring-work taxonomies (authoritative ops literature)

**Google SRE Book, "Eliminating Toil"** (https://sre.google/sre-book/eliminating-toil/) [PRIMARY]: toil = "manual, repetitive, automatable, tactical, devoid of enduring value, and that scales linearly as a service grows" (verbatim). Six characteristics; examples: running scripts by hand, pager alerts, non-urgent service emails, release/push processes. Explicitly NOT toil: overhead (meetings/HR), grungy-but-lasting-value work, novel problem-solving. The Book gives characteristics + examples, not a named category taxonomy.

**SRE Workbook Ch.6** (https://sre.google/workbook/eliminating-toil/) [PRIMARY] — the actual category list people cite:

1. Business processes (ticket-driven onboarding, config, capacity requests)
2. Production interrupts ("time-sensitive janitorial" — disk space, restarting leaky apps)
3. Release shepherding (release requests, rollbacks, emergency patches)
4. Migrations (tech-to-tech moves)
5. Cost engineering & capacity planning
6. Troubleshooting for opaque architectures

Elimination strategies named: engineer out at source; reject via SLOs; partial automation via "human-backed interfaces"; self-service; uniformity; decomposable automated response. The sources frame most toil as targets for DETERMINISTIC automation ("a machine could do it as well as a human"); the judgment-heavy categories (troubleshooting/triage, migrations) are where deterministic scripting historically fails — the natural AI-agent frontier (inference, not a source claim).

**DORA** (https://dora.dev/capabilities/) [PRIMARY]: unit of analysis is organizational CAPABILITIES (continuous delivery, CI, deployment automation, streamlining change approval, monitoring & observability, proactive failure notification, documentation quality, working in small batches, etc.), not task categories. **Falsification: DORA publishes no "tasks delegated to AI" taxonomy.** DORA 2025 AI report (https://dora.dev/dora-report-2025/) frames AI as amplifier; DORA AI Capabilities Model names 7 org conditions (https://services.google.com/fh/files/misc/2025_dora_ai_capabilities_model.pdf), none task-shaped. Classic four keys widely cited but not re-verified against a primary this session (UNVERIFIED).

**ITIL 4** (https://itsm.tools/34-itil-4-management-practices/; peoplecert.org): 34 practices in 3 groups. Recurring operational core: incident management, problem management, change enablement, service request management, monitoring & event management, service desk, service level management, capacity & performance, IT asset management, release management, plus 3 technical practices (deployment management, infrastructure & platform management, software development & management).

**SPACE** (https://queue.acm.org/detail.cfm?id=3454124): 5 productivity DIMENSIONS (satisfaction, performance, activity, communication, efficiency/flow) — a measurement lens, not a work-category taxonomy; use only as a framing axis.

## Q2 — Production monitoring + incident response (AIOps / agentic SRE)

**Key framing finding:** shipped AI agents in this space are almost all EVENT-triggered (per-alert/per-incident), not scheduled. Recurring reviews (weekly SLO/error-budget, alert-noise, on-call handoff) remain human-cadenced standing practices supported by (a) always-on anomaly detection, (b) standing insight dashboards feeding a human meeting, (c) auto-drafted documents. The one clear continuously-running background agent found: PagerDuty Shift Agent.

- **Datadog**: Bits AI SRE — autonomous per-alert investigation, hypotheses over telemetry, 7 triage actions (Slack/Teams, create incident, Case, Jira), learns from past alerts [DOCS https://docs.datadoghq.com/bits_ai/bits_ai_sre/]. Watchdog — continuous anomaly + faulty-deploy detection [DOCS https://docs.datadoghq.com/watchdog/].
- **PagerDuty**: SRE Agent — per-incident, ingests events/logs/runbooks, explicitly NOT a scheduler [DOCS https://support.pagerduty.com/main/docs/sre-agent]. Shift Agent — continuous background on-call conflict detection + replacement coordination, GA [DOCS https://support.pagerduty.com/main/docs/shift-agent]. Scribe (incident transcription/status updates), Insights Agent (proactive coaching; trigger model unconfirmed) [BLOG/PR https://www.pagerduty.com/platform/ai-agents/].
- **incident.io**: AI postmortem auto-draft on resolve (timeline, contributing factors, suggested follow-ups) + auto-export follow-ups to Jira/Linear [DOCS https://docs.incident.io/post-incident/postmortems-overview]. Alert Insights standing dashboard (noisiest alerts, decline/escalation rates) [DOCS https://help.incident.io/articles/2433910890-alert-insights]. The weekly alert-noise review and Monday on-call handoff meeting are RECOMMENDED HUMAN PRACTICES in their guidance, not automated [BLOG].
- **Rootly**: retrospective AI blocks (summary/impact/root-cause/timeline from incident data + Slack + call transcripts), recipient-tailored handoff/exec summaries, bridge-call transcription, automated follow-ups [DOCS https://docs.rootly.com/ai/ai].
- **Grafana**: ML forecasting + outlier detection powering dynamic alerting (continuous); Sift diagnostic checks during investigations [DOCS https://grafana.com/docs/grafana-cloud/machine-learning/].
- **New Relic**: SRE Agent per-incident (alert filter vs baselines, root-cause across traces/logs) [DOCS https://docs.newrelic.com/docs/agentic-ai/sre-agent/overview/]; Smart Alerts dynamic baselines (continuous) [BLOG/PR].
- **Google SRE** [PRIMARY]: SLO/error-budget review is a standing cadence — 4-week rolling window, weekly summaries, monthly/quarterly reports; policy triggers (incident >20% of 4-week budget ⇒ mandatory postmortem) (https://sre.google/workbook/error-budget-policy/, https://sre.google/workbook/implementing-slos/).

Not fetched (optional scope): Honeycomb BubbleUp, BigPanda, Resolve, Nobl9 — UNVERIFIED; Nobl9 is the strongest candidate for a shipped periodic-SLO-review product.

## Q3 — Bug/issue/work-item lifecycle

- **Mozilla bugbug** (https://github.com/mozilla/bugbug) — deepest precedent; decomposes triage into ~15 narrow ML classifiers: component assignment, assignee routing, defect-vs-enhancement-vs-task (~93%), bug type (crash/memory/perf/security), regression detection, regressor prediction, spam, steps-to-reproduce presence, test selection. Key insight: "triage" is N narrow classifiers, not one job.
- **google/triage-party** (https://github.com/google/triage-party) — deterministic YAML-configured multiplayer triage dashboard; the human-orchestration end of the spectrum. Kubernetes documented human triage taxonomy: https://www.kubernetes.dev/docs/guide/issue-triage/.
- **GitHub**: official "Triage an issue with AI" doc (https://docs.github.com/en/issues/tracking-your-work-with-issues/administering-issues/triaging-an-issue-with-ai); Copilot SDK triage tutorial (https://github.blog/ai-and-ml/github-copilot/building-ai-powered-github-issue-triage-with-the-copilot-sdk/); inline duplicate detection at issue-compose time, public preview June 2026, + MCP issue-fields support so agents can file "fully triaged" issues (https://github.blog/changelog/2026-06-18-duplicate-detection-and-issue-fields-mcp-support-for-github-issues/).
- **Stale grooming — fully deterministic**: actions/stale (https://github.com/actions/stale), gitlab-triage gem YAML policy engine (https://gitlab.com/gitlab-org/ruby/gems/gitlab-triage). LLM variant emerging: dosu "stale bot that reads the issue first" (https://dosu.dev/blog/an-ai-stale-bot-that-you-can-trust, UNVERIFIED depth).
- **Backlog refinement**: Atlassian Rovo agents GA 2025 — Issue Organizer (sprint moves, epic links, stale cleanup), Readiness Checker (missing fields/acceptance criteria) (https://www.atlassian.com/software/jira/ai). Linear Triage Intelligence (similar/duplicate surfacing, property suggestions; https://linear.app/docs/triage-intelligence) + Linear for Agents (agents as assignable workspace members; https://linear.app/agents).
- **Flaky tests — most mature closed-loop auto-remediation in the domain**: Google ~16% of 4M+ suites flaky, 84% of postsubmit pass→fail transitions are flakes; auto-quarantine into non-blocking suite (https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html). Trunk Flaky Tests auto-quarantine (https://trunk.io/flaky-tests), BuildPulse (https://docs.buildpulse.io/flaky-tests/guides/Test%20Quarantining), Datadog Flaky Management (https://docs.datadoghq.com/tests/flaky_management/).
- **Support→bug conversion — weakest/least-productized**: Intercom Fin / Zendesk AI auto-classify, summarize, escalate, but NO verified first-class "auto-file engineering bug from support ticket" loop found. UNVERIFIED as a productized pattern.

## Q4 — Security + compliance recurring work

- **Dependency updates — the archetype for scheduled + guardrailed direct change.** Dependabot splits SCHEDULED version updates (interval: daily/weekly/monthly/quarterly/semiannually/yearly or cron; default 3-day cooldown) from EVENT-driven security updates (no cooldown; never grouped with version updates) [DOCS https://docs.github.com/en/code-security/concepts/supply-chain-security/dependabot-version-updates, https://docs.github.com/en/code-security/concepts/supply-chain-security/about-dependabot-security-updates]. Renovate adds the richer guardrail matrix: `schedule` vs `automergeSchedule`, automerge gated on required tests passing, Dependency Dashboard with per-update manual approval (`:dependencyDashboardApproval`) [DOCS https://docs.renovatebot.com/key-concepts/automerge/, https://docs.renovatebot.com/key-concepts/dashboard/]. Clearest shipped precedent for a per-work-class automerge/guardrail policy.
- **CVE/advisory triage**: Snyk reachability analysis — static analysis + DeepCode AI rank whether vulnerable code elements are actually called; feeds Risk Score prioritization [DOCS https://docs.snyk.io/manage-risk/prioritize-issues-for-fixing/reachability-analysis]. Socket — 70+ alert categories (malware, typosquats, install scripts), org-level triage actions (block/warn/monitor/ignore) via API [DOCS https://docs.socket.dev/docs/alert-actions-and-triage-functionality]. GitHub Copilot Autofix — LLM fix suggestions for CodeQL alerts, GA Aug 2024 [DOCS https://docs.github.com/en/code-security/concepts/code-scanning/copilot-autofix-for-code-scanning]. Recurring prioritization inputs: EPSS refreshed daily (first.org/epss), CISA KEV updated continuously; the KEV/EPSS/CVSS composite triage queue is itself a recurring practice [via secondary summaries — first.org/cisa.gov primaries not fetched this session].
- **Secret-scan review**: GitGuardian — validity-checked alerts (non-intrusive API probes), rule-based severity scoring, incident triage/assignment workflows, Jira export, remediation playbooks [vendor https://www.gitguardian.com/monitor-internal-repositories-for-secrets; docs.gitguardian.com]. GitHub secret scanning + push protection shifts detection to event-time; the recurring residue is periodic review of open incidents (valid? rotated? false-positive?).
- **License/compliance + SBOM**: CISA 2025 SBOM Minimum Elements (updating NTIA 2021): a new build or release requires a new SBOM — SBOM refresh is per-build DETERMINISTIC pipeline work, not judgment work [PRIMARY https://www.cisa.gov/resources-tools/resources/2025-minimum-elements-software-bill-materials-sbom; https://www.ntia.gov/files/ntia/publications/sbom_minimum_elements_report.pdf]. License-audit tooling (FOSSA, ScanCode) not separately fetched — UNVERIFIED.
- **Access reviews**: quarterly user-access reviews are a standing SOC 2/ISO 27001 control; Vanta/Drata automate evidence collection and review workflows, and Vanta ships an AI Agent (policy drafting, evidence checks, questionnaire responses) — but third-party reviewers note the platforms do NOT make the access decision itself; ~40-60% of SOC 2 controls still require human process [third-party https://soc2auditors.org/insights/vanta-review/, https://truvocyber.com/blog/soc2-automation-compliance-as-code-guide — vendor primaries not fetched, UNVERIFIED]. Clean agent-prepares / human-decides example.
- **Base-image/patch refresh**: Chainguard rebuilds images DAILY with CVE SLAs; recommended consumption is digest-pinning + a bot that regularly bumps digests [DOCS https://edu.chainguard.dev/chainguard/chainguard-images/about/versions/]. `docker scout recommendations` surfaces base-image refresh suggestions [DOCS https://docs.docker.com/reference/cli/docker/scout/recommendations/]. Deterministic cadence + Renovate-style PR wave.
- **Agentic security scans**: gh-aw agentics pack ships Daily Malicious Code Scan and VEX Generator as scheduled agent workflows (see Q6).

## Q5 — Code quality + knowledge maintenance

- **Tech-debt sweeps**: Google Fixits (episodic company-wide reform sprints; https://mike-bland.com/2011/10/04/fixits.html) + Code Health program (https://testing.googleblog.com/2017/04/code-health-googles-internal-code.html). CodeScene — hotspot × code-health ROI prioritization, MCP context for agents (https://codescene.com/use-cases/technical-debt-management). SonarQube AI CodeFix — LLM fixes from deterministic findings (https://docs.sonarsource.com/sonarqube-server/2025.3/ai-capabilities/ai-codefix). Moderne/OpenRewrite — 10,000+ deterministic recipes run unattended, mass-commit migrations (https://docs.openrewrite.org/). Grit/GritQL — autonomous plan→transform→refine PR generation (https://docs.grit.io/).
- **Dead code — strongest direct-change precedent found anywhere**: Meta SCARF generates deletion change requests DAILY via CodemodService for human review; 100M+ LOC deleted over 5 yrs, 370,000+ CRs (https://engineering.fb.com/2023/10/24/data-infrastructure/automating-dead-code-cleanup/; paper https://dl.acm.org/doi/10.1145/3611643.3613871). Google Sensenmann continuously files deletion CLs (https://testing.googleblog.com/2023/04/sensenmann-code-deletion-at-scale.html; throughput numbers UNVERIFIED — page body would not render). Developer-run scanners: Knip, Vulture, ts-prune.
- **Doc freshness**: Google freshness dates + automated reminder emails when a doc untouched N months; docs change in same CL as code (https://google.github.io/styleguide/docguide/best_practices.html; https://abseil.io/resources/swe-book/html/ch10.html). Swimm auto-sync detects affected docs per change, verifies freshness on every PR (https://swimm.io/blog/how-does-swimm-s-auto-sync-feature-work).
- **Coverage/mutation watch**: Codecov/Coveralls PR threshold gates; Stryker/mutmut as nightly slow-tier jobs with ratcheted mutation-score targets (https://stryker-mutator.io).
- **Release notes**: GitHub auto-generated notes (https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes), Release Drafter (https://github.com/release-drafter/release-drafter), semantic-release (deterministic), Copilot Release Notes — AI, flags uncertain entries for human review (https://github.com/github/copilot-release-notes).
- **Metrics digests**: Swarmia daily/weekly Slack digests (https://www.swarmia.com/changelog/), LinearB WorkerB bot, DX/getDX (https://getdx.com/blog/dora-metrics/). Caveat: these analyze workflow metadata, not code.
- **Knowledge-base gardening**: best-attested as a PAIN with weak tooling — 78% of engineers cite outdated info as #1 reason to distrust internal docs; 84% prefer asking a colleague (https://stackoverflow.co/internal/resources/how-to-keep-your-knowledge-base-up-to-date/). Strongest mitigation is coupling docs to code (Swimm, Google freshness dates), not free-floating wiki review.

Pattern: the automatable high-value end is where truth is mechanically checkable (reachability graphs, coverage %, commit history) and output is a reviewable PR; the judgment-heavy end (is this debt worth paying, is this doc still true) stays report/work-item shaped.

## Q6 — Product/business-adjacent recurring work + vendor-showcased agent routines

- **Anthropic Claude Code Routines** (research preview; schedule + API + GitHub triggers; https://code.claude.com/docs/en/routines, https://code.claude.com/docs/en/scheduled-tasks): official examples — backlog maintenance (weeknight groom + Slack summary), alert triage (API-triggered, drafts fix PR), bespoke code review (pull_request.opened), deploy verification (API call after prod deploy → go/no-go), docs drift (weekly scan → docs PRs), library port (merged PR → parallel-SDK PR). Internal-use evidence: https://claude.com/blog/how-anthropic-teams-use-claude-code.
- **GitHub Agentic Workflows (gh-aw) + githubnext/agentics sample pack** — richest shipped catalog of recurring examples (https://github.com/githubnext/agentics; https://github.github.com/gh-aw/): Daily Repo/Team Status, Daily Plan, Weekly Research, CI Doctor, CI Coach, Cost Tracker, Issue Triage, PR reviewers, Daily Documentation Updater, Wiki Writer, Glossary Maintainer, Daily Test/Perf/Efficiency Improver, Code Simplifier, Duplicate Code Detector, Daily Accessibility Review, Daily Malicious Code Scan, VEX Generator.
- **Devin** — Playbooks (org-shareable repeated-task prompts) + Scheduled Sessions (cron; stateful notes across runs): weekly dependency updates (one package at a time, tests after each), daily reports, periodic maintenance (https://docs.devin.ai/product-guides/scheduled-sessions; https://cognition.ai/blog/devin-can-now-schedule-devins).
- **OpenAI Codex Automations** — scheduled agents, natural-language scheduling: issue triage, alert monitoring, prep-for-the-day, review-what-changed, check-for-updates, weekly report; caps ≤1 run/hr (https://developers.openai.com/codex/app/automations).
- **Cursor** — background agents are event/mention-driven (Slack @Cursor, launch API); NO first-class cron scheduler found in docs — the outlier (https://docs.cursor.com/slack).
- **Release management**: semantic-release (deterministic cut+notes; https://semantic-release.org/); Argo Rollouts AnalysisRuns auto-promote/rollback canaries (https://argoproj.github.io/rollouts/); Harness AI "expert SRE" deploy verification, auto-generated health profiles, AI-enabled rollback (https://www.harness.io/products/continuous-delivery/ai-assisted-deployment-verification).
- **User feedback**: Productboard AI/Spark (intent extraction, insight→feature linking), Canny Autopilot (clustering, top themes), Dovetail AI — pattern: continuous ingestion → weekly VoC theme digest (https://support.productboard.com/hc/en-us/articles/15113485128467-Productboard-AI).
- **Analytics/experiments**: Amplitude AI anomaly detection (Statsig folded into Amplitude May 2026); Statsig AI Experiment Summary — ship recommendation + key-metric highlights (https://www.statsig.com/updates/update/ai_experiment_summary); PostHog Max AI; Eppo automated analysis.
- **Competitive/ecosystem watch**: Klue StaKs Engine (agents extracting/scoring/routing competitive signals, auto-updating battlecards; https://klue.com/topics/automated-battlecards), Crayon continuous monitoring across 100+ signal types.

**Convergence finding:** Anthropic, GitHub, Devin, and OpenAI independently showcase the same core recurring set — triage, status/digest, review, docs drift, dependency maintenance, deploy verification — strong convergent evidence for the class catalog. Cursor is the one major coding-agent vendor without scheduled routines.

### Cross-vendor terminology inventory (recurring-work semantic primitives)

**The "goal" primitive — confirmed cross-vendor (headline).** Session-scoped completion condition: agent re-enters its own loop each turn until a separate evaluator model judges the condition met (or a budget/turn cap trips).

- Claude Code `/goal` (official, v2.1.139+): condition + transcript graded per turn by a small fast model (default Haiku); "no" feeds guidance into next turn; implemented as session-scoped Stop hook; one goal per session; survives `--resume` (https://code.claude.com/docs/en/goal).
- Codex CLI goal mode / `/goal` (official use-case page; feature-flagged, graduated ~v0.128-0.133): plan→act→test→review→iterate until stopping condition or token budget; separate small model grades (writer ≠ grader); community name "Ralph loop" (https://developers.openai.com/codex/use-cases/follow-goals).
- Gemini CLI `/goal`: UNVERIFIED — only a secondary blog asserts it; no official Google doc found. Gemini's documented primitives are Scheduled tasks / Background Agent instead.
- Amp: no goal equivalent; its model is threads + subagents + Oracle (second-opinion reasoning model) + skills (https://ampcode.com/manual) — the terminology outlier: composition-by-threads, not persistence-by-goal/schedule.

Distinction the contract should preserve: **goal** = next turn starts when previous finishes, stops when a model confirms the condition; **loop** = next turn starts on a time interval; **schedule/routine** = a fresh session starts on cron.

| Term | Vendor(s) | Meaning | Cross/single |
|------|-----------|---------|--------------|
| goal | Claude Code + Codex CLI (both official) | completion-condition loop, separate grader model | CROSS-VENDOR (strongest convergence) |
| scheduled task(s) | Codex/ChatGPT, Devin ("Scheduled Sessions"), Gemini | cron-fired agent run | CROSS-VENDOR |
| background agent | Cursor, Gemini (Codex adjacent) | async agent launched from editor/Slack/API | CROSS-VENDOR |
| skill(s) | Claude, Codex, Gemini, Amp | packaged reusable instructions | CROSS-VENDOR |
| workflow | GitHub (Agentic Workflows/gh-aw) + generic | markdown-defined agent run compiled to Actions, cron/event | GitHub formal name; generic concept |
| automation(s) | OpenAI Codex (formal feature name) + generic | scheduled agent = prompt + skills + triggers | Codex formal; generic elsewhere |
| routine | Claude Code | saved prompt + repos + connectors + triggers, cloud-run | SINGLE-VENDOR |
| playbook | Devin | "custom system prompt for a repeated task," org-shareable | SINGLE-VENDOR (functional twin of routine) |
| /loop | Claude Code | re-run prompt/skill on interval or self-paced | SINGLE-VENDOR command; "loop" concept cross-community |
| threads / Oracle | Amp | persistent shareable conversations / second-opinion model | SINGLE-VENDOR |
| batch | Anthropic/OpenAI Batch APIs | bulk async INFERENCE — not recurring-agent work; do not conflate | not a recurring primitive |
| dispatch | community/architecture term | parent agent launches child agents | not a vendor primitive |
| mission | none found | — | would be a coinage, not established vocabulary |

## Q7 — Synthesis axes

- **Judgment level**: deterministic (rules/thresholds suffice — keep in plain cron, zero agent) / agent-judgment (semantic classification, prioritization, drafting — routine territory) / human-required (the decision itself: ship/no-ship, access grant, debt priority — agent prepares, human decides).
- **Output shape**: advisory report / filed work item into governed queue / direct change (PR) — direct change is only precedented where truth is mechanically checkable AND a guardrail policy exists (SCARF review CRs, Renovate automerge rules, flaky auto-quarantine policies).
- **Access split**: repo/CI/tracker-scoped classes are the safe default surface; production-telemetry classes (alert triage, SLO review, deploy verification, log review) and product-data classes (VoC, analytics, experiments) need connector access and stricter isolation; competitive watch needs external web only.

## Proposed class taxonomy

Judgment: DET = deterministic (plain cron, no agent) · AGT = agent-judgment · AGT/HUM = agent prepares, human decides. Output: R = report · WI = filed work item · DC = direct change (gated). Access: repo (incl. CI/tracker) · prod (telemetry/alerts/logs) · product (analytics/feedback/support) · ext (external web) · org (HR/IdP/calendars).

| # | Class | Judgment | Output | Access | Precedent |
|---|-------|----------|--------|--------|-----------|
| **Ops / production** | | | | | |
| 1 | Alert triage & investigation | AGT | R + WI | prod | Datadog Bits AI SRE, PagerDuty SRE Agent, New Relic SRE Agent (all event-triggered today) |
| 2 | Anomaly / faulty-deploy detection | DET/ML | R (alert) | prod | Datadog Watchdog, Grafana ML, New Relic Smart Alerts (continuous, no agent) |
| 3 | SLO / error-budget review | AGT/HUM | R | prod | Google SRE Workbook cadence (human-run today; open niche for scheduled advisory routine) |
| 4 | Alert-noise review (tune noisy alerts) | AGT | R + WI | prod | incident.io Alert Insights dashboard (review itself human-cadenced today) |
| 5 | Log review sweep | AGT | R | prod | gh-aw Log Watcher |
| 6 | Incident retro / postmortem drafting | AGT | R (draft doc) | prod | incident.io, Rootly, PagerDuty (event-per-incident) |
| 7 | Postmortem action-item follow-up sweep | DET + AGT | R + WI nudges | repo | incident.io auto-export to Jira/Linear, Rootly follow-ups |
| 8 | On-call handoff summary | AGT | R | prod | Rootly tailored handoff summaries (on-demand today) |
| 9 | On-call schedule conflict resolution | AGT | DC (schedule) | org | PagerDuty Shift Agent (GA, continuous background agent) |
| **Issue lifecycle** | | | | | |
| 10 | Issue triage sweep (classify/route/set fields) | AGT | WI updates + R | repo | Mozilla bugbug, GitHub Copilot triage, Rovo Issue Organizer, Claude Routines backlog example |
| 11 | Duplicate-detection sweep | AGT | WI links + R | repo | GitHub inline dup detection (6/2026), Linear Triage Intelligence, bugbug |
| 12 | Stale-issue/PR grooming | DET | DC per policy | repo | actions/stale, gitlab-triage (AI-augmented: dosu) |
| 13 | Backlog refinement prep (readiness check) | AGT | WI annotations + R | repo | Rovo Readiness Checker, Linear property suggestions |
| 14 | Flaky-test triage & quarantine | DET detect + AGT root-cause | DC (quarantine) + WI | repo | Google auto-quarantine, Trunk, BuildPulse, Datadog — most mature closed loop |
| 15 | Support-ticket → bug conversion | AGT/HUM | WI (gated) | product | Intercom Fin / Zendesk AI classify+escalate (no verified closed loop — UNVERIFIED) |
| **Security / compliance** | | | | | |
| 16 | Dependency update wave | DET + AGT for breakage | DC (PR, automerge matrix) | repo | Renovate/Dependabot — THE guardrail-matrix archetype |
| 17 | Advisory / CVE triage & prioritization | AGT | R + WI | repo | Snyk reachability + Risk Score, Socket triage actions, Copilot Autofix, daily EPSS / continuous KEV |
| 18 | Secret-scan review | AGT/HUM | R + WI | repo | GitHub secret scanning + push protection, GitGuardian validity-checked triage workflows |
| 19 | License / compliance audit | DET + AGT edge cases | R | repo | FOSSA, ScanCode (UNVERIFIED — not fetched) |
| 20 | SBOM refresh | DET | DC (artifact) | repo | CISA 2025 Minimum Elements: new build ⇒ new SBOM (per-build pipeline) |
| 21 | Access review | AGT/HUM | R (evidence pack) | org | SOC 2 quarterly control; Vanta/Drata evidence automation + Vanta AI Agent (prep only) |
| 22 | Base-image / patch refresh | DET | DC (PR) | repo | Chainguard daily rebuilds + digest-bump bot, docker scout recommendations |
| 23 | Malicious-code / supply-chain scan | AGT | R | repo | gh-aw Daily Malicious Code Scan, VEX Generator |
| **Code quality / knowledge** | | | | | |
| 24 | Tech-debt sweep (prioritize + campaign) | AGT/HUM prioritize; DET recipes | WI; DC for recipe-driven | repo | CodeScene ROI hotspots, Moderne/OpenRewrite, Google Fixits |
| 25 | Dead-code sweep | DET detect | DC (review-gated PR) | repo | Meta SCARF (daily CRs, 100M+ LOC), Google Sensenmann |
| 26 | Doc-freshness sweep | AGT | R + DC (docs PR) | repo | Swimm auto-sync, Google freshness dates, gh-aw Daily Documentation Updater, Claude Routines docs-drift |
| 27 | Coverage / mutation regression watch | DET | R (digest/gate) | repo | Codecov gates, Stryker nightly ratchet |
| 28 | Changelog / release-notes generation | DET + AGT summarize | DC (draft) | repo | semantic-release, Release Drafter, Copilot Release Notes |
| 29 | Eng-metrics digest / status report | AGT narrative | R | repo | Swarmia digests, gh-aw Daily Repo Status, Codex weekly report |
| 30 | Knowledge-base / onboarding gardening | AGT/HUM | R + WI | repo | weakest precedent; gh-aw Wiki Writer/Glossary Maintainer; SO survey attests the pain |
| 31 | CI health review (doctor/coach/cost) | AGT | R + WI + DC (opt PR) | repo | gh-aw CI Doctor, CI Coach, Cost Tracker |
| 32 | Rotating quality improver (test/perf/a11y) | AGT | DC (targeted PRs) | repo | gh-aw Daily Test/Perf/Efficiency Improver |
| 33 | Cross-artifact sync (SDK port, glossary) | AGT | DC (mirrored PR) | repo (multi) | Claude Routines library port, Anthropic Python→Go SDK sync |
| **Product / business-adjacent** | | | | | |
| 34 | Release cut | DET | DC (version+tag) | repo | semantic-release, release trains |
| 35 | Deploy verification | AGT/HUM gate | R (go/no-go) + rollback | prod | Argo Rollouts AnalysisRuns, Harness AI Verify, Claude Routines deploy-verification |
| 36 | Voice-of-customer aggregation & theming | AGT | R (weekly themes) + WI links | product | Productboard AI/Spark, Canny Autopilot, Dovetail AI |
| 37 | Analytics anomaly review | AGT/HUM | R | product | Amplitude AI, PostHog Max |
| 38 | A/B experiment readout | AGT/HUM (ship decision human) | R + recommendation | product | Statsig AI Experiment Summary, Eppo |
| 39 | Competitive / ecosystem watch | AGT | R (intel digest) | ext | Klue StaKs, Crayon, gh-aw Weekly Research, Codex check-for-updates |

## Unverified / flagged

- DORA four-keys metric list: widely cited, not re-verified against a primary this session.
- Deterministic-vs-agent split per SRE toil category: synthesis/inference — SRE sources predate LLM agents; DORA makes no per-task claim.
- Nobl9 (periodic SLO review product), Honeycomb BubbleUp, BigPanda, Resolve: not fetched. PagerDuty Insights Agent trigger model: docs unconfirmed.
- Support→bug closed loop: no productized first-class precedent verified — treat class 15 as emerging.
- dosu AI stale bot: vendor blog only, depth unverified. GitLab Duo issue summarization specifics: not separately fetched.
- Google Sensenmann throughput numbers: page body would not render; existence verified, numbers not.
- Q4 caveat: the dedicated security researcher stalled; Q4 was covered by the lead via direct search — Dependabot/Renovate/Snyk/Socket/Copilot Autofix/CISA-SBOM/Chainguard/Docker Scout claims rest on official docs surfaced in search results, but page bodies were not all fetched in full. EPSS/KEV update-cadence detail and Vanta/Drata AI-agent capabilities come from secondary sources — verify against first.org, cisa.gov, vanta.com, drata.com before load-bearing use.
- Gemini CLI `/goal`: asserted only by a secondary blog; no official Google doc found — treat as unconfirmed.
- Claude Code `/goal` and Codex goal-mode version numbers (v2.1.139+, ~v0.128-0.133): reported by the researcher from vendor docs/changelogs; exact version boundaries not independently re-verified.
