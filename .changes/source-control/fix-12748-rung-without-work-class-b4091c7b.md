---
bump: minor
---

### Changed

- **The babysit loop admits a pull request at each rung by that rung's promotion, not by work class.** The rung partition no longer reads the close-linked item's `work-class:` label: once the effective rung's promotion cells are promoted (`C2-auto-merge` at `c2-mechanical`, every promotable cell at `c3-autonomous` and `full-autonomy`), an item with no class or any class but untrusted provenance is eligible. The untrusted-provenance hold, the fork and trust tests, and the other withholdings stay (#12748).
- **The unattended merge pin names its rung.** The pin comment the merge gate posts before it enqueues is now `<!-- babysit-merge-pin sha=<sha> rung=C2|C3 -->`, and the post-merge read-back accepts both that and the older shape. The pr-merge lane's native-arm pin names the lane room's rung the same way.
- **Promotion evidence is credited by rung.** `publish-promotion-evidence.mjs` credits each autonomous merge to the cells of the rung its lane pin names and reads no work-class label. A merge with no rung (no pin at its head, an older pin, a native auto-merge, another bot's merge) earns no credit, is listed in `noRungAutonomous` (formerly `unclassedAutonomous`), and its contrary events count against every cell. `C3-ai-review-blocking` counts every merge under rung C3 and every human merge, since it measures the AI review rather than merge authority.
