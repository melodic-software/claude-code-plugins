# Read the report

- In the chart, a state that breaks a rule has the class `breaks`. When only some model states
  behind it break the rule, it has the class `mayBreak`. The Legend names the rules of each mark.
  When two rules break, it names both on one mark, so say in the hand-off which state breaks which
  rule. In a regions chart, a state gets a mark when each combination of region states that
  includes it can break a rule. When a combination can break a rule and none of its states has a
  mark, each state in that combination gets a mark.
- TLC goes past a state that breaks a rule, so the chart shows the states after a bug.
- Because TLC goes past bugs, a model with no limit on its states can run without end. Keep the
  constants small, or add a CONSTRAINT.
- With a VIEW or a SYMMETRY, TLC counts states that it treats as the same as one state, and the
  chart draws that one state. An arrow can lead to it rather than to the state that the step
  reaches, and the report says so.
- TLC checks the rules in each state past a CONSTRAINT or an ACTION_CONSTRAINT, but it does not
  explore that state or check it for deadlock. When TLC's shortest path for a rule ends in such a
  state, the chart draws that state, and the report gives that path. The chart does not draw the
  other states past the bound. A deadlock in such a state does not show. TLC also checks the rules
  after each step that an ACTION_CONSTRAINT excludes, also when it reaches the next state another
  way. When TLC's shortest path for a rule ends with such a step, the chart draws that step.
- The command checks the rules with TLC on the config as written, with the TLC flags that
  `PINNED_FLAGS` in `scripts/run.ts` fixes, one worker among them. When a rule breaks, the command
  removes that rule and runs TLC again, until no rule breaks. After the first break, each run stops
  at the rerun bound (`--rerun-states`, default the `bounds.rerun_states` setting), so that a large
  model does not run without end. When a run reaches that bound or stops on an error, the report
  lists the rules that it did not check under "Rules not checked", and the chart does not mark
  them. A rule that is not checked can hold or break. To check it, remove the rules that break from
  the config, or make the model smaller. The bound adds a module that changes TLC's order of the
  variables, so for a property TLC can find a different counterexample than a run without the
  bound.
- `tlc.out` is what TLC printed on the config as written. When the chart does not show the bug path
  of a rule that breaks, `tlc-RULE.out` is what TLC printed for the run that found it. When TLC
  repeats its first warning, plain TLC prints it twice, but `tlc.out` shows it once, because TLC
  leaves the second copy out of the output that this command reads. That happens only when Java
  runs with `-XX:+UseParallelGC`, since otherwise TLC's first warning is its advice to pass that
  flag, which it prints once.
