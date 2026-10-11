# Execute deterministic work with tools

When a task contains a substep that a mechanical procedure can decide, run the
narrowest existing tool, query, calculator, interpreter, or disposable script
that fits, then reason over its actual output. Do not hand-count, mentally sort,
or imitate execution in prose when the operation can run. Writing code-shaped
text without executing it produces no result.

The policy is grounded in a bounded body of evidence. PAL and Program of
Thoughts improved performance on the numerical, symbolic, and algorithmic
tasks they studied by delegating execution to an interpreter
([Gao et al.](https://proceedings.mlr.press/v202/gao23f),
[Chen et al.](https://openreview.net/forum?id=YfZ4ZPt8zd)). Toolformer found a
similar benefit from calling specialized tools, including a calculator, instead
of asking one language model to supply every result
([Schick et al.](https://proceedings.neurips.cc/paper_files/paper/2023/hash/d842425e4bf79ba039352da0f658a906-Abstract-Conference.html)).
Those studies do not prove that every generated program is correct. The policy
inference is narrower: once a substep has a complete mechanical specification,
its result should come from executing that specification rather than predicting
the result in text.

## Classify each substep before executing it

[`enforceability-tiers.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/enforceability-tiers.md) owns the tier definitions.
Apply them to the current substep, not to the task as a whole:

- For **deterministic** work, execute the operation and consume the returned
  result. Examples include an exact count or diff, arithmetic, sorting by a
  declared key, matching a declared pattern, a syntax-aware transformation, or
  a repository-wide inventory over an explicit path set.
- For **detect-then-judge** work, execute only the detection half. The result is
  a candidate set; a human or agent still rules on every candidate. A similarity
  score, heuristic match, or advisory scan cannot promote its own flag to a
  verdict.
- For **reasoning-only** work, do not encode the verdict in a script. A tool may
  gather deterministic evidence for the judgment, but meaning, intent, fit, and
  semantic equivalence remain with the human or agent.

Classification is itself reasoning-only. A task that mixes exact inventory with
architectural judgment therefore gets an executed inventory followed by a
reasoned decision, not one mechanism pretending to own both.

## Make the execution honest

A script is not deterministic merely because it is code. Before relying on its
output:

- state the operation, input scope, comparison rule, and ordering explicitly;
- prefer a mature existing tool over generating new logic when both implement
  the same operation;
- run the command or script and inspect its exit status and material output;
- check nontrivial generated logic against a known case, invariant, or second
  representation in proportion to the consequence of a wrong answer; and
- record the invocation, input scope, and material result when they support a
  change or verification claim, so another reader can repeat the computation.

Successful execution proves only that the encoded operation ran. It does not
prove that the inputs were complete, that the operation answered the intended
question, or that a later judgment is sound. The National Academies report
defines computational reproducibility around the same inputs, computational
steps, methods, code, and conditions of analysis
([*Reproducibility and Replicability in Science*](https://nap.nationalacademies.org/catalog/25303/reproducibility-and-replicability-in-science)).
The UK Government Analysis Function likewise recommends minimizing manual steps
while retaining quality assurance and an audit trail
([RAP strategy](https://analysisfunction.civilservice.gov.uk/policy-store/reproducible-analytical-pipelines-strategy/)).

## Keep session-time work in its lane

This convention governs one-off execution during the current task. It does not
require committing a throwaway script, adding a dependency, or building a
general utility. If the same deterministic finding recurs, route it through
[`enforceability-tiers.md#routing-a-recurring-finding`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/enforceability-tiers.md#routing-a-recurring-finding)
instead of accumulating session scripts.

When executable logic becomes committed behavior, the simplicity, ownership,
and test obligations in [`simpler-code.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/simpler-code.md),
[`code-organization.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/code-organization.md), and
[`../review/testing.md`](https://github.com/melodic-software/standards/blob/main/conventions/review/testing.md) apply. When the concern is a
reusable artifact's fixed shape rather than an in-task computation,
[`deterministic-artifact-scaffolding.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/deterministic-artifact-scaffolding.md)
owns it. Treat the output as proof only of the exact structural or computational
claim it checked; the verification-honesty criteria in
[`../review/testing.md#verification-honesty`](https://github.com/melodic-software/standards/blob/main/conventions/review/testing.md#verification-honesty)
own broader proof claims.

## Keep agent-run commands plain

When an agent runs commands through a harness that checks each command before
it runs, the command's shape decides how cheaply it is checked. Keep each one
plain:

- absolute paths, rather than a `cd` followed by relative paths;
- no inline environment assignments (`VAR=value command`), `export`, or output
  redirection;
- the harness's own file-read and search tools in place of shell reads such as
  `cat`, `sed -n`, or `grep`, where it has them;
- a POSIX shell rather than PowerShell unless the command needs PowerShell,
  because PowerShell starts noticeably slower on Windows; and
- a background job or the harness's wait mechanism for a long operation, never
  a foreground `sleep` or polling loop.

## Sources

- Gao et al., ["PAL: Program-aided Language Models"](https://proceedings.mlr.press/v202/gao23f) (ICML 2023).
- Chen et al., ["Program of Thoughts Prompting: Disentangling Computation from Reasoning for Numerical Reasoning Tasks"](https://openreview.net/forum?id=YfZ4ZPt8zd) (TMLR 2023).
- Schick et al., ["Toolformer: Language Models Can Teach Themselves to Use Tools"](https://proceedings.neurips.cc/paper_files/paper/2023/hash/d842425e4bf79ba039352da0f658a906-Abstract-Conference.html) (NeurIPS 2023).
- UK Government Analysis Function, ["Reproducible Analytical Pipelines (RAP) strategy"](https://analysisfunction.civilservice.gov.uk/policy-store/reproducible-analytical-pipelines-strategy/).
- National Academies of Sciences, Engineering, and Medicine, [*Reproducibility and Replicability in Science*](https://nap.nationalacademies.org/catalog/25303/reproducibility-and-replicability-in-science) (2019).
