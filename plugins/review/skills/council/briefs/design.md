# Design

Judge how the change fits the code around it: a second way of doing something the codebase
already does one way, duplicated logic or a value with no single source, a dependency pointing
the wrong way across a module boundary, a module that exposes its internals, configuration
hard-coded where the codebase externalizes it, and a name that says something other than what the
thing does.

Name the existing code or convention each finding departs from, by path. Leave defects in
behavior to other members unless the design causes them.

Report each finding on its own line as `SEVERITY | path:line | finding | action`, with SEVERITY
one of CRITICAL, IMPORTANT or SUGGESTION. With nothing to report, write `No findings.`
