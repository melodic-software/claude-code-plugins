---
type: llm
arm: both
---

Judge the whole reply: the fenced page and the prose after it.

PASS only if all of these hold:

1. The reply identifies the page's content as reference material (it may say "reference", "lookup", or that readers are on the job looking a value up) and that the tutorial framing does not fit it.
2. The fenced page reads as reference: its title names relayd's configuration or settings rather than a lesson, its voice is neutral, and it holds no step-by-step lesson narration or encouragement.
3. All five settings (`listen_port`, `max_connections`, `idle_timeout`, `tls_cert_path`, `log_level`) keep their defaults and allowed values; a table or one heading per setting are both fine.

A recommendation in prose to write a separate tutorial or how-to page is fine and does not decide the verdict.

FAIL if the fenced page stays a tutorial (tutorial or getting-started title, "we" narration, numbered lesson steps), if a setting or its default is lost, or if the reply never says the page is reference.
