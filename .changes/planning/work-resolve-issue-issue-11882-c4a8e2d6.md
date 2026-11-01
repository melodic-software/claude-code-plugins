---
bump: patch
---

### Changed

- `/planning:wayfind` reads its container label from `tracker.config.container_label` in `<home>/work-items.yaml`, the convention home's work-items file, through the new `skills/wayfind/scripts/container-label.sh`. The script uses the plugin's own copies of the convention-home resolver and the YAML subset parser, so wayfind no longer needs `jq`. An absent or empty key still gives `work-map`, and a non-string value still stops wayfind with an `ERROR:` line. A repository whose binding is still the legacy root JSON file gets `work-map` from wayfind until it moves the binding under `tracker:` in `<home>/work-items.yaml`.
