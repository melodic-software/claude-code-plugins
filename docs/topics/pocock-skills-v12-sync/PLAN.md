# pocock-skills-v12-sync

## Brief

### TLDR

Sync the learnings from mattpocock/skills v1.2 (repo HEAD v1.2.3 @ `84fdeff`) into this marketplace: fix the drift the audit found, consolidate all Pocock provenance into one SSOT outside the skill bodies, land the verified 35-skill upstream↔ours map durably, then work four further lanes (owned-skill deltas, `/wait-what` port, `/wizard` port, infra adoptions) — one feature branch, one PR, a `/session-flow:handoff` at every lane boundary.

### Goal

Every v1.2 change that touches a skill we derived is either adopted, consciously rejected, or tracked; provenance for all Pocock-derived material lives in `docs/upstream/mattpocock-skills.md` (not in installed skill bodies); the map and research summary are committed under `docs/topics/pocock-skills-v12-sync/`; the two new upstream skills (`wait-what`, `wizard`) get an explicit port decision in their own lane sessions.

### Constraints

- ONE PR on `feat/pocock-skills-v12-sync`; squash merge; PR title Conventional Commits; PR body carries closing keyword + `## Related` per repo contract.
- Lane sessions are sequential on this branch; every lane boundary gets a `/session-flow:handoff`; each lane session opens with a lane-scoped `/planning:interview` (agenda = that lane's deferred questions) and `/discipline:use-your-skills`.
- Provenance/attribution never lands in SKILL.md bodies (agent noise); SSOT + plugin CHANGELOGs carry it. Content citations the agent uses (e.g. Fowler in code-reviewer) are not provenance and stay.
- Recheck triggers must name an observable event ("a mattpocock/skills release whose changeset names `<skill>`"); the SSOT stores the last-audited upstream ref, never dates/logs duplicating git history.
- Fresh-docs mandate applies to every contract-surface change in lanes 2–5 (frontmatter, plugin.json, hooks).
- Plugin edits bump semver + CHANGELOG per repo rules; `.work/**` stays uncommitted (gitignored).

### Acceptance criteria

- Lane 1: `docs/upstream/mattpocock-skills.md` exists with per-skill attribution table, recheck trigger, last-audited ref (v1.2.3 @ `84fdeff`), map pointer, and the issue-#693 harness note; `plugins/planning/skills/questionnaire/SKILL.md` and `wayfind/SKILL.md` carry zero Pocock provenance blocks; `docs/topics/ai-adoption-ladder/design/RESEARCH-sandcastle-pocock.md` no longer names `writing-great-skills` as live; map + research summary committed under `docs/topics/pocock-skills-v12-sync/`; planning plugin version bumped + CHANGELOG entry; repo lint/format checks pass.
- Lanes 2–5 (execution contract — per-lane loop): open with lane interview → implement that lane's items → verify (toolchain check + review pass) → commit → `/handoff`. A lane is CLOSED when its menu items are each adopted/rejected/tracked, its SSOT rows updated, and the branch is green.
- PR: all five lanes landed, CI green, PR body linkage contract satisfied.

### Captured assumptions

- Upstream MIT license permits derivation with attribution (his repo: MIT).
- `docs/upstream/` is a new directory; one file per upstream source is the going-forward registry pattern (firecrawl's per-plugin UPSTREAM.md sidecar stays as-is for that plugin's own update skill).
- Menu item ids M1–M20 refer to `.work/youtube-watch/new-skills-v1-2-brings-wait-what-writing-gaDdrDdczO4/recommendations/menu.md` (local slice); the committed map + SSOT carry everything lanes 2–5 need.

### Out-of-scope

- Codex `agents/openai.yaml` sidecars (no Codex target; v1.2.2 hidden-skill gotcha recorded in SSOT notes).
- Beta-channel bucket, docs-site build, `setup-matt-pocock-skills` analog, his personal/TS skills (shoehorn, scaffold-exercises, setup-pre-commit), writing-beats/fragments/shape, teach workspace, ask-matt router-as-skill.
- Changing `work-items` skill *behavior* (lane 1 records provenance only; any behavior sync is a separate effort).

### Deferred questions

- Q9 — RESOLVED (lane-3 interview, 2026-08-09): PORT as `discipline:wait-what`; upstream name kept with a PLUGIN-PHILOSOPHY naming-exception entry; read-pointer glossary seam (no curate-language invocation); ASD-STE100 inline in the body with a short gloss. Record: `### Lane 3` below + SSOT row.
- Q10 — RESOLVED (lane-4 interview, 2026-08-09): PORT, hardened, as a NEW single-capability plugin `wizard` with one skill `generate` (`/wizard:generate`, leaf named via a `/naming:name-it-better` tournament — grammar-clean imperative verb, noun namespace legal, no naming-exception entry); model-invoked with upstream's non-trigger fence kept; all security-review gating conditions shipped in the hardened template (human STAGES approval before `chmod +x`, https-only `open_url`, `/dev/tty` fail-closed prompts, hardened `.env`/gh writes, key-name validation, agent-never-executes doctrine). Record: `### Lane 4` below + SSOT row.
- Q11 — RESOLVED (lane-5 interview, 2026-08-09): per the user-delegated-vetting arbiter precedent (Q13/Q14/Q17 shape — fresh-context vetting agents plus an adversarial verifier, mandate delegated by the user in the lane interview): M10 SPLIT — ADOPT the shareable-HTML logic shell into `prototype:pressure-test` (audience-routed, TUI default, explore-directions' constraint set reused), REJECT the throwaway-branch "primary source" capture half; M13 REJECT bulk (parity or stronger) with two event-triggered TRACK strands (leading-words/negation — cross-linked to the interview-batch-rounds deferral — and the invocation-reach invariant); M14 REJECT (changesets/npm-pipeline tool; `check-changelog-parity.sh` stronger); M15 REJECT as already-adopted plus a required SSOT triage-row provenance correction (no `work-items` behavior change); M16 REJECT (docs-site decoration; reopen condition recorded in the rejection, not a TRACK row). Record: `### Lane 5` below + SSOT rows.

## Lanes

| # | Lane | Items | Status |
|---|---|---|---|
| 1 | Hygiene + record | M1 M2 M19 M20 + SSOT + map promotion + provenance strip | this session |
| 2 | Owned-skill deltas | M6 M7 M8 M9 M11 M12 | done |
| 3 | /wait-what port | M4 (Q9) | done |
| 4 | /wizard port | M5 (Q10) | done |
| 5 | Infra / P2 | M10 M13 M14 M15 M16 (Q11) | done |

## Plan

(Filled per-lane by the lane sessions; Lane 1 executes directly off this Brief.)

### Lane 2 — owned-skill deltas (closed)

Six fresh-context vetting agents (one per item) drove the decisions per the lane interview's
user-delegated mandate; outcomes recorded in `docs/upstream/mattpocock-skills.md`:

- **M6** — re-audited, no delta (graduation was a 100%-similarity rename; ours a superset).
- **M7** — emoji anchors adopted behind `userConfig` `use_emoji_question_markers` (default off);
  one-question-at-a-time opt-out rejected (consumer CLAUDE.md is the native seam). planning 0.29.0.
- **M8** — parallel research burn-down + no-fog bail-out adopted in `wayfind`; decision-ticket
  term (parity as "decision item") and `research/<name>` branch (two-lane violation) rejected.
- **M9** — YAGNI scoping filter adopted in `architecture:improve` deepening Phase 1;
  precomputed commits widened 10→20. architecture 0.4.3.
- **M11** — redaction guard adopted in `debugging:debug` (0.5.0) and `testing:diagnose` (0.4.0);
  tagged-log rider added to diagnose (debug already had it); loop doctrine tracked, not adopted.
- **M12** — phase-boundaries tree rejected at parity (ours stronger); one zone-gated
  primary-source continue criterion adopted in the continuation router. session-flow 0.18.1.
  ~150k smart-zone figure rejected as folklore; context-guard bands unchanged.

### Lane 3 — /wait-what port (closed)

Q9 resolved through the lane interview (rounds 4–6): a fresh-context vetting agent supplied the
gap/name/home/seam evidence, a 5-generator/3-judge `/naming:name-it-better` tournament ran the
name question (grammar-clean winner `re-pitch`; merits winner `lost-me`; `wait-what` the only
exception-eligible incumbent), and the user locked:

- **PORT as `discipline:wait-what`** — a declared non-corrector species beside `sweep-all`
  (siblings: `tighten-your-output`, `mind-your-maxims`). Home chosen on the blame axis: the
  drift being repaired is the model's output, not the user's comprehension (education rejected
  for that reason; session-flow a lifecycle misfit). discipline 0.10.1 → 0.11.0 + CHANGELOG.
- **Name kept** — sixth entry on the PLUGIN-PHILOSOPHY naming-exception list
  (utterance-is-mechanism + upstream muscle-memory parity).
- **Seam** — read pointer to the nearest domain glossary per the consumer's own convention;
  no `curate-language` invocation (reads are a one-line habit; that skill owns writes); silent
  degradation when no glossary exists; no prerequisites.
- **ASD-STE100 inline in the body** with a five-word gloss — his X thread (statuses
  2084753070437609606 → 2084941367659168064 → 2085681281795232026) shows the same instruction
  failing as passive global CLAUDE.md and as an output style; on-demand is the working shape.
- Migration gate: fresh docs fetched for the skills frontmatter surface
  (code.claude.com/docs/en/skills, this session); security review trivial-pass (no hooks, no
  code, no egress, no config secrets; plugin-form-safe — no reach-outs, same-plugin references
  only). Provenance in SSOT + CHANGELOG only; skill body carries none.

### Lane 4 — /wizard port (closed)

Q10 resolved through the lane interview; a completed security review of upstream `template.sh`
supplied the gating conditions, a `/naming:name-it-better` tournament ran the name question
(grammar-clean winner `generate` under a `wizard` noun namespace — legal per PLUGIN-PHILOSOPHY,
no naming-exception entry), and the user locked (decisions Q23–Q27):

- **Q23 — PORT, hardened**, as a NEW single-capability plugin `wizard` 0.1.0 (not a home in an
  existing plugin: the capability — agent-authored, human-run interactive setup scripts — is its
  own cohesive vertical slice).
- **Q24 — one skill `generate`** → `/wizard:generate` via the naming tournament; imperative verb
  leaf, noun namespace, grammar-clean.
- **Q25 — model-invoked** (no `disable-model-invocation`), keeping upstream's well-fenced
  triggers including the explicit non-trigger ("Don't invoke this for steps the agent can
  perform itself").
- **Q26 — security posture (gating outcome of the review, all shipped):** (a) mandatory human
  read-and-approve of the full STAGES block before `chmod +x` — stop-the-line in the skill's
  verify step; (b) https-only `open_url` with the URL printed before dispatch (also closes the
  Windows UNC/NTLM leak via explorer.exe); (c) all prompts read `/dev/tty` (fd 3), fail-closed
  abort without a TTY, fatal read failures in `pause`/`confirm` (retires the multi-line-paste
  confirm bypass and pause's EOF fail-open); (d) `chmod 600` `.env` after every write +
  `git check-ignore` assert + trap-cleaned same-filesystem mktemp; (e) gh writes resolve/echo/
  confirm the repo once, explicit `--repo` on every call, stderr into SKIPPED, empty values
  refused, `set_var` via `--body-file -`; (f) key-name validation in every helper; (g)
  single-quoted escaped `write_env` values; (h) `_existing` strips one matched quote pair.
  Ride-alongs: readline (`read -e`) on non-secret asks (upstream #741 fixed where safe), secrets
  via stdin, hidden entry, names-only output, gh-absence graceful degradation.
- **Q27 — scoping honesty fix:** step 1 reads `.env.example`/README/workflows fully but takes
  KEY NAMES ONLY from a live `.env`; the skill states the secrets-and-context property honestly
  (runtime capture never reaches the model; authoring reads are names-only by design; a value
  pasted into chat is in context).
- Files landed: `plugins/wizard/` (plugin.json 0.1.0, README, CHANGELOG with provenance +
  hardening deltas, `skills/generate/SKILL.md` + hardened `template.sh`), marketplace entry,
  regenerated CATALOG/cheat-sheet, SSOT row + open-evaluations update, map row 18, this record,
  MIGRATION-PLAYBOOK acceptance record (model-generated-executable rationale — deliberately
  breaks the statusline-shim "no templating" precedent, with the mitigations shipped).
- Migration gate: fresh docs fetched this session for skills frontmatter
  (code.claude.com/docs/en/skills), plugin manifest (code.claude.com/docs/en/plugins-reference),
  and marketplace schema (code.claude.com/docs/en/plugin-marketplaces). Gates run: `bash -n` +
  shellcheck (clean), skill-quality check-skill PASS, portability gate clean (gh coupling
  declared per-site `portability-ok` — GitHub Actions is the inherent CI-secret destination),
  markdownlint clean, JSON validity + catalog/cheat-sheet drift checks green. Fresh-context
  verifier subagent confirmed every hardening item line-by-line before commit. Provenance in
  SSOT + CHANGELOG only; skill body carries none.

### Lane 5 — infra / P2 (closed)

Q11 resolved through the lane interview under the user-delegated-vetting arbiter (fresh-context
vetting agents + adversarial verifier, the Q13/Q14/Q17 precedent); one verdict per menu item:

- **M10 SPLIT** — ADOPTED the shareable-HTML logic shell into `prototype:pressure-test` as an
  audience-routed substrate choice: TUI stays default; a self-contained HTML demo
  (domain-language labels, labelled state panel, free-play buttons, guided-walkthrough scenarios
  resetting to a known initial state) when the driver is a non-developer or no terminal fits.
  Explore-directions' HTML-substrate constraints reused verbatim-in-spirit (CSP meta tag,
  ephemeral `mktemp -d` / `%LOCALAPPDATA%\Temp` placement, synthetic data only, discard after
  the markdown capture). prototype 0.3.3 → 0.4.0 + CHANGELOG provenance (mattpocock/skills
  v1.2.3 @ `84fdeff`, `LOGIC.md`). REJECTED the throwaway-branch "primary source" capture half
  (two-lane posture violation; contradicts the plugin's delete-when-done discipline) — recorded
  in the SSOT, no behavior change.
- **M13 REJECT bulk** — `writing-for-agents` / `SKILL-MECHANICS.md` at parity or stronger
  (derivation-cache rubric, listing-budget check, hub-and-spoke). Two strands TRACKED with
  event triggers (never dates) in the SSOT's tracked section: (i) leading-words + negation
  doctrine, cross-linked to the prior deliberate deferral at
  `docs/topics/interview-batch-rounds/PLAN.md:43-44` rather than double-tracked; (ii) the
  invocation-reach invariant (`SKILL-MECHANICS.md:10`), unverified against current docs, zero
  live defect instances found.
- **M14 REJECT** — version-sync script serves upstream's changesets/npm pipeline; our CI-wired
  `scripts/check-changelog-parity.sh` is stronger; version one-home doctrine holds;
  `marketplace.json` carries no version keys.
- **M15 REJECT as already-adopted** — the work-items 0.6.0 rejected-concept ledger is a
  superset of upstream's `.out-of-scope/` KB. PLUS the required SSOT provenance correction:
  the triage row's "no structured port" claim was provably false (near-verbatim phrase match
  with upstream `OUT-OF-SCOPE.md:86`; one-file-per-concept, concept-not-keyword matching,
  never-ledger-built-features map one-to-one) — row amended to Derived (structured port). No
  `work-items` behavior change (this plan's out-of-scope bars it).
- **M16 REJECT** — "It's working if" sections decorate a per-skill docs site this marketplace
  doesn't build (docs-site build out of scope above); reopen condition (a docs-site build
  landing here) recorded in the SSOT rejection, not a TRACK row.
- Files: `plugins/prototype/skills/pressure-test/SKILL.md`,
  `plugins/prototype/.claude-plugin/plugin.json` (0.4.0), `plugins/prototype/CHANGELOG.md`,
  `docs/upstream/mattpocock-skills.md` (prototype row, triage-row correction, lane-5
  rejections, tracked section, open-evaluations closure), `docs/SKILL-CHEAT-SHEET.md`
  (regenerated — pressure-test summary changed), this record.
- Migration gate: fresh docs fetched this session for the skills frontmatter surface
  (code.claude.com/docs/en/skills — description semantics + 1,536-char listing cap). Gates run
  green: skill-quality check-skill on pressure-test, portability gate, markdownlint,
  changelog-parity (`--check` modes), catalog/cheat-sheet drift checks. Fresh-context verifier
  subagent confirmed each verdict landed before commit. Provenance in SSOT + CHANGELOG only;
  skill body carries none.
