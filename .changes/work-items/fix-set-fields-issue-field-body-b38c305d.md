---
bump: patch
---

### Fixed

- The GitHub adapter's `set-fields` now sends each field as one `{field_id, value}` object in a JSON body. The `gh api` array form it used split ids and values into separate entries, so every write failed with HTTP 422 and `set-dimensions.sh` could not set an issue's dimensions.
