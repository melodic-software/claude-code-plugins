---
bump: major
---

### Removed

- The audit-enforceability skill leaves the review plugin, with its probe. Use `/corrections:codify`, which takes a findings file and proposes the rung that catches each finding. The `ratchet_offer` setting stays for now, and no skill in this plugin reads it. To keep ratchet offers off, set `ratchet_offer` on the corrections plugin (its plugin option or `docs/conventions/corrections.yaml`): `/corrections:codify` does not read the review setting.
