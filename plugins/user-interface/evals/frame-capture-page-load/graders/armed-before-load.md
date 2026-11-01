---
type: llm
arm: both
---
An entrance that plays on page load is over before a capture started after load can see it.
PASS only if the reply arms the capture in the page before its first script runs: it installs a
page clock (such as `page.clock.install`) before navigating, or registers an init script (such as
`page.addInitScript`) before navigation that holds or records the entrance. FAIL if it starts the
clock or the capture after the page has loaded, installs the clock after `goto`, relies on
reloading and pressing record quickly, offers only a screen recording or video to scrub, or names a
recording product's page-load mode without saying how the capture is armed.
