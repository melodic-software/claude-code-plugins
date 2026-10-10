# Downstream review mode

What does this change break **outside its own diff**? Every other mode in this skill judges the
changed lines; this one judges what the changed lines reach. It is the only mode whose findings are
expected to name files the diff never touches.

Listing the callers is not the job. A grep finds those in seconds. The job is the breakage a grep
does not show: the library whose source behaves unlike its docs, the wire format another service
parses, the column a report reads, the flag that changes which branch runs, the consumer three hops
out in another language.

Severity and confidence come from the shared vocabulary
([`context/severity.md`](../../../context/severity.md)) or the
project's own when it defines one. **This mode adds no grading scale of its own**: not a proof
level, not an evidence rung, not a confidence variant. The two existing axes carry every finding.

**Dispatch policy:** the producing main thread must not run the steps below inline. The thread that
wrote the change is the worst judge of what the change reaches, for the same reason `self` mode
refuses an inline checklist. Its model of "what this touches" is the one it already had while
writing, so an inline pass re-derives the author's own blast-radius assumption and confirms it.
Orchestrate a fresh-context read-only subagent; the main thread gathers inputs, dispatches, verifies
findings against the tree, and presents the verdict. Where the verdict is high-stakes and correlated
blind spots are the risk, prefer a cross-vendor advisor **when one is installed and set up**, for
example the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its
own docs, with the fresh-context same-vendor subagent as the stated fallback, never a route to a
command that may not resolve
(per [`docs/plugin-philosophy.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/plugin-philosophy.md)
"Fresh-eyes checkpoints").

## Orchestrator sequence (main thread)

1. **Gather inputs**: the resolved review diff base (SKILL.md "Shared inputs") and the changed
   symbol list from Step 1.
2. **Choose the worker**: this plugin's `brief-reviewer` agent (`review:brief-reviewer`), never a
   general-purpose subagent, so the worker cannot fan out. This mode has no checklist
   agent, unlike `architecture` and `security`: its checks are not a fixed per-ecosystem baseline
   but a search shaped by what the diff changed, so the brief below carries the specifics and
   `brief-reviewer` runs it as given.
3. **Dispatch** with the brief below.
4. **Verify every finding before presenting**: open the named file, confirm the caller or reader
   exists and behaves as claimed. Worker output is synthesis, not evidence, and this mode's findings
   point at files the diff never touched, so an unverified one sends a reviewer to the wrong place.
5. **Probe the safety fact** when Step 2 found one: resolve `downstream_probe` (below), then write
   the probe and run it or report it (Step 2, "The probe"). The orchestrator does this after
   verification, never the worker, whose brief stays read-only.
6. **Present** the `downstream_probe` line, the confirmed and cleared lists (Step 4) and the
   cheapest-test handback.

## Resolve `downstream_probe`

`run` or `report`, default `run`. It is a policy floor, not a later-layer key: `report` from any
valid layer wins. Layers:

1. The default, `run`.
2. The user's option, rendered in SKILL.md as `${user_config.downstream_probe}` (this file arrives
   unrendered, so take the value from SKILL.md's "Downstream probe setting"). A literal, unexpanded
   placeholder means unset. The option's default is `run`, so a user value of `run` cannot be told
   from an unset one and reads as the default.
3. `downstream_probe` in the repository's `docs/conventions/review.yaml`, read from the **default
   branch**, never from the working tree or the branch under review. Apply SKILL.md's root rule
   first: when the root (`CLAUDE_PROJECT_DIR`, else `git rev-parse --show-toplevel`) is not in a
   git working tree, or is `$HOME` or an ancestor of it, skip this layer and say so. Otherwise
   resolve `<default>` from `git ls-remote --symref origin HEAD` (the name after `refs/heads/` on
   its `ref:` line). The remote supplies that name, so check it before it reaches any command: only
   letters, digits, `.`, `_`, `/` and `-`, no leading `-` and no `..`, the same check the reader
   applies to `--ref`. Any other name skips this layer, and the report quotes the name as data.
   Then run `git fetch origin <default>`, then
   `node "<plugin-root>/skills/setup/scripts/setup-apply.mjs" --check --ref origin/<default> --root "<root>"`.
   Its first line names the commit it read; carry that commit into the report. A fetch that fails
   leaves the last fetched `origin/<default>`: read it and say the copy may be stale. The reader's
   result:
   - exit 0 with `INFO ... absent` or `PASS downstream_probe: (unset)`: this layer is unset.
   - exit 0 with `PASS downstream_probe: run` or `report`: this layer sets that value.
   - exit 1 with a `PASS downstream_probe:` line: a WARN sits on another key only. Name it, and
     read this layer's `downstream_probe` from the PASS line as above.
   - exit 1 with no `PASS downstream_probe:` line: `downstream_probe` or the whole committed file
     is invalid. Each `WARN` line names the file, the key and the value (`maybe`, a quoted string,
     an empty value, a list, a key set twice, an unknown key, a parse error, a symlink). Name them,
     drop this layer, and continue.
   - exit 2 (no `origin/<default>`, or a ref that does not resolve), or node is not installed: the
     layer cannot be read; skip it and say why.

A pull request that adds or changes `docs/conventions/review.yaml` on its head does not change the
value: the read is at `origin/<default>`, so a branch cannot switch its own probe on. A user value
other than `run` or `report` is named with the option, key and value and dropped the same way. The
run never stops on an invalid value. Resolve: `report` when any remaining layer says `report`;
otherwise `run`. Report one line before presenting, naming the value and every layer that set it,
for example `downstream_probe: report (docs/conventions/review.yaml at origin/main, commit <sha>)`,
`downstream_probe: report (userConfig)` or `downstream_probe: run (default)`.

## Worker brief

```text
You are a fresh-context reviewer. You did NOT author this change.

Inputs: git diff <review-diff-base>, plus the changed symbols named below.

Your job is what this change breaks OUTSIDE its own diff. Do not review the
changed lines. Another mode does that. Listing callers is not the job either.

Search for the breakage a grep does not show: a library whose source behaves
unlike its docs, a wire format another service parses, a column a report reads,
a flag that changes which branch runs, a consumer several hops out or in another
language. A search that finds nothing is still an answer. Report it as cleared,
with what you searched.

Do not edit files. Return two lists, confirmed and cleared, each finding with
its file:line and what you checked. Use only the severity and confidence
vocabulary given; introduce no other scale.
```

## Step 1: Read what actually changed

The diff, the symbols it adds, changes and removes, and what now behaves differently, including the
part the diff does not spell out. A renamed parameter is a signature change; a widened return type is
a contract change; a removed guard is a precondition moved onto every caller.

## Step 2: Ask the single-fact question once, then move on

Many changes that look alarming are safe because of one fact: "this only evicts entries already past
their TTL", or "the compiler rejects every caller that was not updated". Ask it first, because when such
a fact exists, verifying that one thing collapses most of the scary cases at once.

**Then enumerate the risks anyway.** The single fact is a probe, never the report's structure. A
change with three independent risks organized around its most legible one leaves the other two not
merely unmentioned but structurally invisible, since the report has no slot for them. Annotate which risks
collapsed into a shared fact; never let that annotation become the outline.

### The probe

When a safety fact exists and the worker's findings are verified, the orchestrator writes **one**
probe that checks that fact and nothing else: a short script that reads the tree and prints whether
the fact holds. Examples of a fact a probe can settle: every key in a fixture file already has the
new format; no row in a seed file has the value the new guard rejects; every caller of a changed
function passes the argument the new default replaces.

- **Where.** Create a directory with `mktemp -d`, outside the working tree, and write the probe
  there with the Write tool. The probe reads the repository through paths it is given; it writes
  nothing inside the tree and makes no network call.
- **Untrusted text stays data.** File names, symbol names and diff lines the probe needs go into a
  file in that directory, or into a literal inside the script's own language that the script reads
  as a value. None of them appears in the command line, a shell word, an `eval` or a heredoc the
  shell expands. The command that runs the probe names only the interpreter, the probe path and
  the repository root, for example `python3 "<tmpdir>/probe.py" "<root>"`.
- **Run it** under `downstream_probe: run`, through the normal permission prompt (this skill grants
  no blanket permission for it), then remove the temp directory. The probe's output is evidence:
  the fact verified clears the concerns it covers; the fact failed, or the probe erroring, keeps
  them confirmed (Step 4).
- **Report it instead of running it** under `downstream_probe: report`, or when Bash is denied or
  the run is refused: show the probe's text and the exact command, and say why it did not run
  (`downstream_probe: report` and the layer that set it, or the denial). The concerns it would
  have settled stay confirmed as "assessed, not verified because the probe was not run" (Step 5).

No safety fact, no probe: say so in one line and skip this section.

## Step 3: Look where grep stops

The reachable surfaces a symbol search misses, in rough order of how often they bite:

- **Library behavior**: read the dependency's own source for the call you changed, and check its
  pinned version and any local patch. Documented behavior and shipped behavior diverge.
- **Serialization boundaries**: JSON an API returns, a persisted column, a cache key shape, a wire
  format, a file another tool parses. A field rename is invisible to a compiler and fatal to a reader.
- **Timing and lifecycle**: teardown order, microtask versus macrotask, cancellation, retry, whether
  a handler can now run after unmount or after close.
- **Configuration reach**: feature flags, environment-dependent branches, defaults a consumer relies
  on precisely because it never overrides them.
- **Cross-language and cross-service readers**: anything consuming the same bytes without sharing
  the type definition.

A search that finds nothing is an answer worth reporting. Never invent a caller or an API to fill a
gap: cite `file:line` for what you found, and say plainly what you looked for and did not find.

## Step 4: Split confirmed from cleared

Both halves are deliverables. The cleared list is what makes the confirmed list trustworthy. A
report with no cleared concerns has not shown its work, only its conclusions.

- **Confirmed risks**: each names how it breaks, its `file:line`, how likely it is, what it costs
  when it happens, and how a reader can check it themselves.
- **Cleared concerns**: what was investigated and why it turned out fine.

**A safety fact you could not verify never clears a concern.** It belongs in the confirmed list,
carrying the reason it is unverified. This is the whole discipline of the mode: an unverified
assumption that has been sorted into the reassuring column is worse than one nobody looked at,
because it now reads as checked.

## Step 5: Say plainly what is unverified

This skill does not run builds or tests (see the parent skill's "What this skill does NOT do"). The
one exception is the safety-fact probe of Step 2, run only under `downstream_probe: run`. Any other
claim resting on an unrun check, and the probe itself when it was reported rather than run, is
stated as **"assessed, not verified because Y"**, naming Y.

That formula and the discipline behind it are owned by `/playbooks:fable-5 verification` when the
`playbooks` plugin is enabled. Invoke it **with the chapter name**, rather than reading into the
plugin's files, and rather than bare, which arms that playbook's entire doctrine as standing session
instructions for the rest of the run. When it is not enabled, the rule stands on its own as
written here. Do not invent a grading scale for it. The unverified claim is marked in words, and
its confidence is the shared `confidence` axis.

## Step 6: Hand back the cheapest test that would catch it

Name the smallest test or reproduction that fails if the most serious confirmed risk is real. The
safety-fact probe of Step 2 is the one thing this mode runs; the test named here is handed back,
not written or run.

- Authoring the test routes to `/testing:write` when the `testing` plugin is enabled.
- Proving the test actually catches the bug routes to `/mutation-testing:audit` when the
  `mutation-testing` plugin is enabled, which is stronger than asserting it will, because the
  mutant is re-run and the agent that wrote the test does not grade itself into a pass.
- Neither enabled: state the test in enough detail that a reader can write it, and say that its
  existence is unverified.

## Skip conditions: when this is the wrong mode

- **The change is not written yet.** Assessing a plan's reach before implementation is
  `/planning:plan`'s Step 3b scalar and `/planning:devils-advocate`'s adversarial rounds. This mode
  needs a diff.
- **The change is a rename sweep.** Counting and bucketing stale references after a rename is
  `/docs-hygiene:rename-references audit blast`, which is mechanical, token-scoped, and better at it.
- **The question is whether the diff does what was asked.** That is `spec` mode; this one does not
  care what was asked, only what else it reaches.
