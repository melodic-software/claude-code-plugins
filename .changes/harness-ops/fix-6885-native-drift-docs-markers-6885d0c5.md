---
bump: patch
---

### Fixed

- **changelog:** the native-drift pass no longer refiles a recheck item on every apply for a store row whose marker comes from the docs. A row lists such markers in the new optional `native.docs_markers`, and the pass leaves them out of the marker comparison; any other marker change still fires.
- **audit-native-overlap:** the store self-check rejects a `native.docs_markers` entry that the row's `native.markers` does not also record.
