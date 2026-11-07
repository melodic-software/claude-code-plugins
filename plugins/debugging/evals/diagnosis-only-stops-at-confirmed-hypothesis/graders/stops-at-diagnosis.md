---
type: llm
---

PASS only if the reply reports one confirmed cause (the file is opened as plain utf-8, so the byte-order mark stays on the first header as '﻿sku' and the header check rejects it) at importer/csv_import.py with a line number, quotes the loop output that confirms it (for example the rejected header with '﻿sku'), says any instrumentation it added was removed (or that it added none), and says it made no fix and no regression test. Describing the fix the user could write is fine.

FAIL if the reply says it changed the importer or wrote a fix or a regression test, gives the cause without a file:line, gives no confirming loop output, or leaves the cause as an unconfirmed guess.
