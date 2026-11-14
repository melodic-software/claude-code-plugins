---
type: llm
focus: 'last_message'
---

The branch adds src/hook_payload.py (parse_hook_payload reads JSON another process writes to stdin), src/billing_client.py (BillingClient calls the payments team's billing-service, whose CI verifies the contracts its consumers publish) and src/weather_client.py (WeatherClient calls a public third-party forecast API). PASS only if the plan does all three: it plans a fuzz target for parse_hook_payload (generated or mutated inputs, with what must not happen); it plans a consumer-driven contract test for BillingClient (the requests it sends and the response fields it relies on, verified by billing-service); and it plans no contract test for WeatherClient, planning canned responses instead whose expected values come from a source independent of the client code (the provider's documented response, a recorded real response, or hand-written literals); naming testing:test-value is not required. Saying WeatherClient gets no contract test because its provider runs no verification is fine. FAIL if any of the three is missing or contradicted.
