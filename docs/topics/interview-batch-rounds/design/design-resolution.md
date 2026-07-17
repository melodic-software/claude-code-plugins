# Design resolution — interview-batch-rounds

outcome: early-exit
tier: C

Reason: doc/config-only change — prose rewrite of the interview skill's questioning discipline across
five markdown surfaces plus one manifest key (`userConfig.use_ask_user_question`, boolean) and a
CHANGELOG entry. No new types, contracts, modules, or topology; the only schema surface is the
manifest key, whose shape is dictated verbatim by the plugins-reference userConfig schema (fetched
this session — no enum type exists, hence boolean). Design decisions of substance (rounds model,
surface default, config mechanism, facts-vs-decisions split, confirmation gate, budget guidance)
were resolved with the user in the /planning:interview session recorded in
`.work/interview-batch-rounds/interview-checklist.md`.
