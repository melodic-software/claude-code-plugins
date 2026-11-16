# Adding a team rule safely

A new check that fails on day one teaches the team to suppress it. Every proposal for a checking
rung, from any codify input, states each step below for its rule.

## Steps

1. **Survey the legitimate uses first.** Before writing the rule, find every place the code uses
   the thing the rule restricts, and sort them: uses the rule must allow, uses it exists to stop,
   and uses no one can call yet. The rule is written against that survey, not against the one
   occurrence that prompted it.
2. **Scope it to where it applies.** Apply the rule to the paths, layers or file types where the
   survey shows the mistake, not to the whole tree. A rule that only holds in production code does
   not run on tests, scripts or generated files.
3. **Warn before error.** The rule lands at warning severity, or as an advisory check, and becomes
   blocking only when the warnings show it fires on real mistakes and nothing else. Promoting it is
   a change of its own, and carries the record line's promotion form
   ([finding-classes.md](finding-classes.md#record-line)).
4. **Allow only justified exclusions.** Each exclusion, whether a config entry or an inline
   suppression, names its reason beside it. An exclusion with no reason is not allowed. The ladder's
   guardrail criterion item 8 covers expiry
   ([enforcement-ladder.md](enforcement-ladder.md#guardrail-criterion)).
5. **Audit suppressions afterwards.** Once the rule has run for a while, run
   `/code-metrics:audit-suppressions` on it: a suppression with no reason, or one the rule should
   not need, sends the rule back to step 2.

## A custom rule ships with its tests

A rule codify proposes to write (on `custom-analyzer` or `syntax-pattern-rule`, or a lint rule a
`shared-helper` needs) is not done until it has its own rule tests:

- **Invalid cases**: code the rule must report, at least the known cases it was written for.
- **Valid cases**: code the rule must leave alone, at least each legitimate use step 1 found.
- **The tool's own harness**: the cases run in the rule-test harness the analyzer or linter ships,
  where it has one; otherwise in the repository's own test runner.

The proposal also states what the rule does not catch, so no one reads it as complete. Name each
gap that applies to the rule's matching: an aliased or renamed import, a computed or dynamic member
access, a call reached through a wrapper or another indirect path, and code generated at build
time. A gap the rule must close becomes an invalid case; a gap it leaves open stays listed.
