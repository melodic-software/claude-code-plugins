# skill-frontmatter-alignment

## Brief

### TLDR

- Convert the 11 bare (class-c) frontmatter restatements to pointers at the official
  [frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference), keeping a
  fact inline only as a four-part stamped record where the surface stops functioning without it.
- Upgrade the date-only "(b)-minus" stamps and the 3 unstamped constant-encoding scripts
  (`check-skill.sh`, `check-listing-budget.sh`, `audit_skill_visibility.py`) to full four-part
  records, modeled on `plugins/context-budget/skills/audit/reference/levers.json`.
- Fleet frontmatter: add `user-invocable: true` to the 5 skills missing it (explicit-key posture,
  zero behavior change); no other field changes.
- Fold in the two pre-existing drift fixes (PLUGIN-PHILOSOPHY's pre-v2.1.216 `name` history now
  pinned by the changelog, not the skills page; skill-authoring's stale citation of the same), and
  record the fired no-CI-gate recheck trigger in the upstream-drift CHANGELOG (decision re-derived
  and upheld).
- One PR from `claude/frontmatter-reference-dlyhjm`; two follow-up issues drafted now and filed at
  PR-open (provenance redesign; description-quality measurement).

### Goal

Every living surface in this repo that states a skill-frontmatter fact either points at the
official reference so a reader always fetches the latest, or carries a conforming four-part
record (claim, basis, as-of date, observable recheck trigger) where restating is necessary to
function; and the skill fleet's frontmatter is uniformly explicit about invocation posture, with
the remaining quality questions (description-driven auto-invocation measurement, provenance
detection of restated facts) captured as filed follow-up issues rather than lost.

### Constraints

- Trigger-phrase preservation: `check-skill.sh` hard-fails a trigger phrase dropped from
  `description`/`when_to_use` versus the base ref. No description rewrites in this PR.
- Surface-kind split: plugin-shipped text cites only the official `code.claude.com` URL, never
  this repo's docs (native-references self-containment); repo-only surfaces may point at the
  owning convention doc instead (one owner per concern).
- House style: no em dashes or vendor formatting in owned instruction surfaces; quoted upstream
  text in stamps is verbatim, never paraphrased (upstream-drift fetch-route rules).
- Every touched plugin gets a CHANGELOG entry and a version bump; validation runs through
  `scripts/affected-tests.sh --run`.
- `name` fields are never added; `disable-model-invocation` stays explicit on every skill;
  `shell: bash` declarations stay.
- No mechanical CI gate for restatement conformance is added (recorded 2026-08-12 decision,
  re-derived this sweep and upheld).

### Acceptance criteria

- Zero class-c surfaces remain in the census scope: each of the 11 is a pointer, or a four-part
  record where function requires the fact inline; re-running the census grep
  (`1,536|1536|skillListingBudgetFraction|skillListingMaxDescChars` plus the field-name-token
  pass, minus the recorded exclusions) finds no unstamped, untriggered restatement.
- The 3 machine surfaces carry four-part records (basis URL, as-of date, observable recheck
  trigger) beside their constants; `levers.json` is unchanged.
- The 5 skills missing `user-invocable` declare `user-invocable: true`;
  `scripts/affected-tests.sh --run` passes; `check-skill.sh` passes for every touched skill.
- `docs/conventions/upstream-drift/CHANGELOG.md` records the fired trigger and the upheld
  decision.
- Per-surface close-out loop (execution contract): one surface at a time, apply the disposition,
  verify (script pass or re-read), record it closed; a surface is closed only when its restated
  facts are all pointed, stamped, or explicitly kept with a reason.
- Two follow-up issue drafts exist and are filed referencing the PR after it opens.

### Captured assumptions

- The claude-memory and claude-config criteria near-duplicates are fixed independently (each
  becomes official-URL pointer + minimal stamp); no shared SSOT doc is created. Revisit if a
  third in-plugin copy of the same paragraph appears.
- `paths` gets no fleet adoption; revisit inside the measurement follow-up issue.
- The two near-cap descriptions (1,526 and 1,518 of 1,536) stay untouched. Revisit if the cap or
  either description changes.
- `docs/specs/*` and `docs/knowledge-integration-design.md` stay excluded as history-adjacent.
  Revisit if either is edited as a living surface.

### Out-of-scope

- Aggregate listing budget overflow (130,470/8,000 chars as of 2026-08-31): owned by
  `claude-ops:audit-skill-visibility`; not this task.
- Spec-six field portability (claude.ai/Skills API upload): no upload ambition exists; the fleet
  stays Claude Code-expressive. Revisit only if an upload goal appears.
- `when_to_use` field migration: nothing to measure on the split itself (both fields render into
  one capped listing string); description content quality routes to the measurement issue.
- Provenance plugin redesign: separate follow-up issue, not this PR.

### Deferred questions

- Q5 (follow-up portion) — which description-quality levers are worth fleet application, measured
  how — defer until the measurement issue is worked; **arbiter: USER-RESERVED**
- Q9 (design portion) — the provenance redesign's concrete detection architecture — defer until
  that issue is worked; **arbiter: USER-RESERVED**

## Plan

<!-- populated by /planning:plan if invoked; for this task the Brief is the plan -->
