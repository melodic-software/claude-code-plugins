## Problem

The changelog fragment check rejects a fragment whose file name holds a digit, such as
`fix-oauth2-refresh.md`. The fragment naming rule allows digits, so the check is wrong.

## Done when

- [ ] The fragment check accepts a fragment file name that holds a digit.
- [ ] A test feeds the check a file name with a digit and expects it to pass.
