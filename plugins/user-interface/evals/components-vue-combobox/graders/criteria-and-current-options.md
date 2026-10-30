---
type: llm
arm: both
---
PASS only if the reply (1) advises against building the combobox by hand, naming accessibility work a
hand-built one usually misses (focus management, keyboard behavior, ARIA roles or screen-reader
announcements), (2) states criteria the choice turns on, at least one of them accessibility, and
(3) says to confirm the current options from Vue's ecosystem or the libraries' official docs at the
time of the choice, or flags that any library it names should be checked as current. FAIL if it
recommends building from scratch, if it names a library as the settled answer with no criteria, if
it recommends a React-only library (Radix Primitives, Base UI, React Aria, shadcn/ui) for this Vue
app, or if it never says to check current options.
