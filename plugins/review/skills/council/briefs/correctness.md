# Correctness

Find defects that make the change behave wrongly: logic errors, wrong conditions and boundaries,
unhandled error paths and empty inputs, state that goes stale or is shared unsafely, a caller or
consumer the change breaks, and a test that cannot fail or does not test what it names.

For each defect, trace it to a concrete input or sequence of events that produces the wrong
result, and read the code it depends on before reporting it. Leave style, naming and design
preferences to other members.

Report each finding on its own line as `SEVERITY | path:line | finding | action`, with SEVERITY
one of CRITICAL, IMPORTANT or MINOR. With nothing to report, write `No findings.`
