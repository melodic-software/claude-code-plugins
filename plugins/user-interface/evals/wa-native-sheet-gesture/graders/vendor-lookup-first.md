---
type: llm
focus: trace
arm: both
---
Expectation: "The answer looks for an installed vendor skill or documentation for the
detected stack before writing gesture code".

PASS only if, before its gesture code, the run names the stack from the files (Expo, React Native,
react-native-gesture-handler, react-native-reanimated) and looks for an installed vendor skill for
it, then, finding none, goes down the lookup ladder (current docs, or the repository's patterns)
and names the rung it used. FAIL if gesture code comes first, or the run relies on recalled syntax
with no lookup and no word on the missing route.
