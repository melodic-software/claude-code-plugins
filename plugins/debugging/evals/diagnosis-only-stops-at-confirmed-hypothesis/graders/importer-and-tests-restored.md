---
type: llm
focus: trace
---

PASS only if, by the end of the session, importer/csv_import.py is as it was at the start (any line the session added to it, such as a tagged debug print, was removed again, and nothing else in it changed) and no new or changed test is left under tests/ (a scratch loop outside tests/, or one deleted again before the end, is fine).

FAIL if the session left any change in importer/csv_import.py, applied a fix to it at any point (for example opening the file with utf-8-sig or stripping the BOM), or left a new or changed test under tests/.
