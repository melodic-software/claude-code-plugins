# Hook precision — false-positive discipline for plugin hooks

Owner doc for the precision discipline every plugin hook follows so it fires on what it targets and stays
quiet on everything else. The [plugin philosophy](../../PLUGIN-PHILOSOPHY.md) owns the posture rule — an
advisory hook is a nudge, a guard must not block legitimate work; this doc owns the *precision shape* that
keeps both true: the recurring ways a hook over-fires, and the discipline that turns each production false
positive into a regression test instead of a re-filed issue.

Guardrails hooks repeatedly shipped false-positive over-fires — each found by a babysit worker on a real
pass, hand-filed, fixed in isolation, teaching the next hook nothing. The classes below are those over-fires
generalized; the discipline after them is what stops the pipeline from paying for the next one at production
time.

## The rules

Five rules for what a hook matches and how it reads its input; a sixth — the discipline — turns every next
over-fire into a committed regression test. A hook is precise when it matches the *structure* it targets,
reads its input safely, and scopes its check to what actually changed.

1. **Diff-scope `PostToolUse:Edit` checks to the changed hunk.** An Edit hook that scans the whole file
   warns on pre-existing lines the edit never touched. Check only the edited region (the tool payload's new
   content); scan the whole file only for a new-file Write, where every line is genuinely new.
2. **Match structural producers, not token co-occurrence — and ignore tokens inside quoted arguments.** A
   guard that greps for `echo` and `>` anywhere in a command string fires on any command whose quoted
   arguments merely mention them. Parse the command's structure and treat quoted spans as inert data, not
   executable tokens.
3. **Bound every stdin read; never parse the inherited fd0 directly.** A hook that runs `jq` against fd0
   unbounded stalls when a Win32 pipe delivers EOF late, hanging the tool call along with it. Buffer stdin
   once through the bounded reader, then parse every field from the buffer.
4. **Prefer either/or marker logic where "already-canonical → stay quiet" is the intent.** When any one
   marker proves the input is already canonical, requiring a *conjunction* of markers makes the hook fire on
   canonical input that happens to omit an optional second marker. Gate on the single marker that proves
   canonicality — and prefer the one that survives literal-stripping.
5. **Gate path detection on the discovered checkout, not the raw project dir.** A repo-path branch that
   matches the project dir as a literal substring flags every absolute path under it when the project dir is
   (or is under) the user's home. Resolve the enclosing git toplevel and compare *that* against home;
   suppress the branch when the checkout root is home or an ancestor of it.

## The discipline

The rules prevent the classes already seen; the discipline prevents the next one. It has two halves, and
both are non-negotiable:

- **Every filed production false positive becomes a MUST-stay-quiet case in that hook's existing
  `*.test.sh`.** The co-located contract test *is* the fixture corpus — true-positive MUST-fire cases and
  false-positive MUST-stay-quiet cases live side by side and run in CI on any `plugins/guardrails/hooks/**`
  change. An over-fire that is fixed but not pinned by a committed stay-quiet case is left half-fixed: the
  next author can reopen it and nothing catches them.
- **Every fix lands repro-first.** The new stay-quiet case must *fail* against the unmodified hook
  (reproducing the over-fire) and pass after the fix. A stay-quiet assertion that is already green before the
  fix guards nothing — it only looks tested.

## What this convention is not

- **Not a new harness.** There is no separate golden-fixture system to build or wire. The existing per-hook
  `*.test.sh` beside each hook is the corpus, and `guardrails-test-helpers.sh` is its shared assertion
  library. A standalone fixture harness was considered and rejected — it would duplicate the harness that
  already ships next to every hook.
- **Not true-positive tuning.** These rules narrow *false* positives without weakening detection; a change
  that also drops real catches is out of scope and must keep its MUST-fire cases green.
- **Not a substitute for the philosophy's hook posture.** Advisory-versus-blocking, fail-open-versus-closed,
  and prerequisite visibility are owned upstream in the plugin philosophy; this doc assumes them.

## Conformance

Fleet audits check that each `plugins/guardrails/hooks/**` change carries the discipline: a fix pins the
over-fire it closes as a repro-first stay-quiet case in the co-located test, and no rule above regresses. CI
runs every `*.test.sh` on any hooks change.

Existing adopters conform by carrying the rule their over-fire needed:

- `block-hook-bypass` strips quoted literal spans before its executable-token scan, so a command that only
  *mentions* `echo` / `>` inside an argument stays quiet (rule 2).
- `cli-flag-verify` buffers stdin through `hook::buffer_stdin` instead of reading `fd0` directly (rule 3).
- `flag-commit-pr-skill-bypass` gates on the canonical `-F -` marker alone, having dropped the `--trailer`
  conjunct it once required (rule 4).

The shared harness and a worked exemplar that co-locates both MUST-fire and MUST-stay-quiet cases:

- Assertion library: [`guardrails-test-helpers.sh`](../../../plugins/guardrails/hooks/guardrails-test-helpers.sh)
- Exemplar test: [`hardcoded-path-check.test.sh`](../../../plugins/guardrails/hooks/hardcoded-path-check.test.sh)
