---
type: regex
target: { source: file, path: docs/queue.md }
arm: both
pattern: '^# Choosing a queue\n\nExperts argue that a log-based queue is always the safer choice, and it is widely regarded\nas the modern default for event pipelines\.\n\nOur own load test settled it for this service\. In the March run, the log-based queue held\n40,000 messages a second before consumer lag passed one minute, while the broker we use today\nstalled at 12,000\. The Kafka documentation states that "a partition is the unit of\nparallelism", which is why we sized the topic at 24 partitions\.\n'
---
