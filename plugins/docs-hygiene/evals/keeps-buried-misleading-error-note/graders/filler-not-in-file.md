---
type: regex
pattern: "```(?:markdown|md)\\n(?:(?!```)[\\s\\S])*(?:type (?:hints|annotations)|(?:small|short) (?:functions|routines)|(?:functions|routines) (?:small|short)|tidepool/routes|tidepool/models|conftest|`tidepool/`: application|`tests/`: pytest suite|`pyproject\\.toml`: project metadata)"
flags: i
match: not_contains
arm: both
---
