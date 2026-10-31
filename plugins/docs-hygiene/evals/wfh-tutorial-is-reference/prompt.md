---
description: "Routine guard, likely to score alike in both arms because the reader framing points at reference. Edge: the page is titled and voiced as a tutorial but its content is a list of every setting with defaults, and its readers already run the tool and come to look one value up. The contract picks the mode first (work plus understanding is reference) and keeps one mode per page; a no-skill rewrite tends to polish the tutorial voice or add steps. Written from the before SKILL.md contract"
tags: [write-for-humans, diataxis, doc-type, routine]
runs: 3
max_turns: 10
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply says the page is reference, not a tutorial; the fenced page is retitled after relayd configuration settings, keeps all five settings with their defaults, drops the lesson narration (welcome, we will, take your time, great job), and any tutorial is recommended in prose as a separate page"
---

This is our page `docs/getting-started.md`. Our analytics say most visitors already run relayd in production and arrive from search to check one setting's default or its allowed values, and they tell us they can't find what they came for. Rework the page for those readers. Reply with the reworked page in one ````markdown fenced block (four backticks), and if you think we need some other page as well, say so in prose after the block rather than writing it out.

````markdown
# Tutorial: Getting started with relayd

Welcome! In this tutorial we will learn all about configuring relayd. Let's dive in!

relayd reads its settings from `/etc/relayd/relayd.toml`. Here is an example:

```toml
listen_port = 8080
max_connections = 64
```

Now we'll go through every setting one by one. Take your time!

First, `listen_port` is the TCP port relayd listens on. It defaults to 8080 and must be between 1 and 65535.

Next up, `max_connections` caps concurrent client connections. The default is 64. Setting it to 0 means unlimited, which we don't recommend.

After that we have `idle_timeout`, the number of seconds an idle connection stays open before relayd closes it. The default is 300.

Then there's `tls_cert_path`, the path to a PEM certificate. It is empty by default, which turns TLS off.

Finally, `log_level` can be `error`, `warn`, `info`, or `debug`. The default is `info`.

Great job! You now know everything about configuring relayd.
````
