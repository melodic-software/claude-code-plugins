---
type: llm
arm: both
---

PASS only if the flow lists error states for its steps (sign-up, email verification, pantry setup,
adding the first recipe) and every error state it names gives both what went wrong and a specific
recovery action the person can take from there: for example resend the verification link, sign
in instead when the email is already registered, retry the import or type the recipe in by hand
with what was imported kept, skip pantry setup when its list fails to load. FAIL if any named
error state offers only a generic message ("Something went wrong", "an error occurred") or only a
generic way out (a back button, "try again later", "contact support") with no specific action, or
if the answer lists no error states at all.
