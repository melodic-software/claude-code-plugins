#!/usr/bin/env bash
# Seeds one doc with weasel attribution, a "some critics argue" line, and paragraphs whose claims
# carry their sources, one of them a list of outlets each with what it said.
set -euo pipefail

mkdir -p docs
cat > docs/queue.md <<'MD'
# Choosing a queue

Experts argue that a log-based queue is always the safer choice, and it is widely regarded
as the modern default for event pipelines.

Our own load test settled it for this service. In the March run, the log-based queue held
40,000 messages a second before consumer lag passed one minute, while the broker we use today
stalled at 12,000. The Kafka documentation states that "a partition is the unit of
parallelism", which is why we sized the topic at 24 partitions.

Some critics argue that a log-based queue is overkill for a service this size.

Two write-ups covered the switch. InfoQ's case study reports consumer lag under five seconds at
30,000 messages a second, and the Confluent blog post quotes our lead: "the replay window saved
the March migration".
MD
