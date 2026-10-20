# Design Threads: report-export

## Thread 1: Export file naming. RESOLVED

Decision: name exported files `report-<date>.csv`.
Rationale: the name is built in one function and visible in the export handler; renaming
it later touches that function and a test. Including the report id in the name was
rejected as noisy for users.

## Thread 2: Config behind one defaults file. RESOLVED

Decision: keep export options in a single defaults file until the settings service lands.
Rationale: this is a temporary bridge; moving the options into the settings service later
is a mechanical edit of the loader. Reading options from environment variables was
rejected because the defaults file is simpler to review.

## Thread 3: Page size for large exports. RESOLVED

Decision: stream exports in pages of 500 rows.
Rationale: the constant lives in one place and can be tuned from measurements without any
data or contract change. Loading the whole result set into memory was rejected because of
peak memory on large reports.

## Thread 4: Principles. RESOLVED

Principles applied: YAGNI keeps options in one defaults file until the settings service lands.
Generalize now or wait: the Brief's `Intent: second variant = speculative` line settles it: wait
for the third occurrence.
Rationale: the Intent line is the user's answer.

## Thread 5: Lifecycle and reversibility. RESOLVED

Door: Threads 1, 2 and 3 two-way.
Rationale: each changes by editing code, with no data or contract change.
