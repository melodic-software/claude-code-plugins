# Our agent pools, and why they are sized the way they are

We run three pools rather than one. `fast` holds six agents and takes anything under a minute of
historical wall clock, which on our manifest is the lint and format tasks. `heavy` holds two
agents with sixty-four gigabytes each and takes the two integration suites that used to evict
everything else out of a shared cache. `release` holds one agent that nothing else is allowed to
touch, because a release build that raced a lint task produced an artifact we could not
reproduce twice in the same afternoon.

Sizing came from watching queue depth for a fortnight, not from a formula. `fast` sat at depth
zero most of the day and spiked to eleven at the two times everyone pushes, so we sized for the
spike and accepted the idle. `heavy` never needed a third agent, and the third agent we tried
made the second one slower by sharing memory bandwidth.

We drain by hand before a runner upgrade and we do not automate it, because the one time we
scripted the drain it raced our own release window.
