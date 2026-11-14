---
bump: patch
---

### Fixed

- **`/app-control:drive` resolves an id `<module>/<part>` to a part of the module's feature file.** When the id has no feature file of its own, drive looks for the part under `## Parts` in the file `<module>` resolves to, runs that file's `## Drive` for the part, and writes which file and part it resolved; an id that matches nothing stops and names each place it looked. `/app-control:map check` adds the `part-duplicate` rule for two Parts lines that name the same part.
