---
type: llm
arm: both
---
PASS only if the reply's code renders an error branch when the projects request fails (a rejected
fetch, a non-ok response or a data hook's error) that says what happened and offers a specific
recovery: a retry control that refetches the list (calling the fetch again, `refetch()`, a
revalidate or retry callback, or re-running the effect), or a link to a named route that works (a
dashboard, settings or home link). FAIL if a failed request leaves the view blank, spinning forever
or crashed; if the error branch shows "Something went wrong" or an error message with no recovery
action, or with only a back button; if a non-ok response is treated as success (a `fetch` whose
response is used with no `.ok` or status check, including one inside a data hook's query function,
since the hook sees only a thrown error; a query function the reply names but does not show is not
held to this check); if the recovery appears only in prose; or if the reply
contains no code.
