# Scope `skill-quality` to the generic static checker and exclude the rest permanently

- Status: accepted
- Date: 2026-07-13

## Decision

The `skill-quality` plugin shipped only the generic static contract checker (`check-skill.sh`, seventeen
model-free checks) plus the `evals.schema.json` validation asset. Its held-back scope is resolved here as
**terminal exclusions** — decided out of the plugin for good, each with a permanent home, **not** deferrals
with a recheck trigger. (Contrast the "Deferred surfaces" record above, where the medley surface is held
*pending* a trigger; these are held *out*.)

- **A/B eval runner** (`tools/evals/run-skill-comparison.sh`): a headless `claude -p` skill-body A/B
  comparison driver — spins throwaway worktrees, runs fixture trials per arm, scrubs transcripts. **Not a
  plugin component; stays medley-owned in `tools/evals/`.** It is a *dynamic authoring experiment* harness,
  a distinct concern from this plugin's *static QA gate* (one cohesive capability per plugin — see the
  design charter), with a single consumer and ~29 KB of worktree / hub-safety / platform path-scrub
  surface that would be marketplace upkeep for that one consumer. **No recheck trigger:** a genuine
  second-consumer demand is a fresh publish issue, not standing debt.
- **Contract libs** (`tools/skill-contract/`: portability, encapsulation, script-contract, dispatcher):
  enforce medley-**invented** regimes — the skill public-surface / encapsulation contract, BEHAVIOR.md
  symmetry, unit-anatomy, the cleanliness-regime script contract, and a medley-specific identifier
  deny-list. **Permanent home is medley** (a de-couple-from-source-repo gate they cannot pass — every scan
  scope, exemption, and identifier is this repo's). The narrow genuinely-generic seams (machine-path /
  escape-path scanning, an encapsulation deep-cite regex, a "new script ships `--help` + a sibling test"
  assertion, a deny-list scan *mechanism* whose data is per-consumer) are net-new versus the shipped
  checks but have **no second consumer**; extracting them now is speculative generality / a pre-Rule-of-
  Three abstraction (`melodic-software/standards` `conventions/engineering/simpler-code.md`). The plugin
  can grow a machine-path check the day a real consumer needs one — as its own issue.
- **Checker hardening** (block-scalar description unfolding, an unquoted-`Use when:` warning, a
  `CHECK_SKILL_BASE_REF` post-commit audit ref for the git-backed checks, and a line-1 frontmatter-fence
  requirement): the one worker-executable slice — **landed** with this record.
