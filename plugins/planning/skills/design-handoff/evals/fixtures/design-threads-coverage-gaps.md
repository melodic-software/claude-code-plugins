# Design Threads: export-pipeline

## Thread 1: What we are building. The CSV export surface. RESOLVED

Decision: one `ExportRequest` command producing a single flat CSV per report type.
Rationale: every consumer asked for spreadsheets, and a flat file avoids the nested-shape
negotiation a JSON export would have forced on three separate consumers.

## Thread 2: Serialization mechanism. RESOLVED

Decision: stream rows through a buffered writer rather than materializing the whole result set.
Rationale: the largest report is 1.4M rows, which exceeded the memory ceiling in the spike; the
streaming writer held flat at 40MB.

## Thread 3: Export lifecycle and sequencing. RESOLVED

Decision: an export is generated on request rather than on a schedule, one generation at a time per
report type, and the generated file expires seven days after it is written.
Rationale: overlapping generations of the same report doubled the query cost in the spike, and the
seven-day window matches how long a finished export was observed to stay useful.

## Thread 4: Why CSV rather than the reporting vendor's own export. RESOLVED

Decision: build the export rather than adopting the reporting vendor's own.
Rationale: the vendor's export cannot join the two datasets that two of the three reports need, and
that join is the whole point of those reports; the recorded tradeoff is one more writer to maintain.

## Thread 5: Encoding and delimiter handling. TAGGED-DEFERRED

[RESEARCH: confirm which of the three consumers still require a BOM-prefixed UTF-8 file before
fixing the encoding].
