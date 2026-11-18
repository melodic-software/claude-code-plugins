---
bump: minor
---

### Changed

- The `work-unblock` sweep re-fires an issue run that stopped on a rate limit after its model ran as
  a fresh start, from the reset the run names to 20 minutes after it, repeating hourly. A run counts
  only when every failed job ended on a rate limit. With no reset named, it re-fires from an hour
  after the run ended.
- Each issue re-fires once per reset, at most the lane's slots per rolling hour, and takes the
  `failed-again` backoff after `limit-stops-per-issue` of these re-fires.
- A start-gate re-fire that names a reset uses the same 20-minute span. A re-fire whose span closes
  before the sweep writes it waits for the next window.
