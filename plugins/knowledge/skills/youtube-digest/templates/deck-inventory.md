# Deck inventory — {{VIDEO_SLUG}}

Per-session slide decks fetched during staged harvest. Template: promote triage uses this to skip static slides covered by deck files.

| Session | Source URL | Fetch status | Local path | Slide count | Notes |
| --- | --- | --- | --- | --- | --- |
| *example* | https://example.com | success \| failed \| pending | `source/decks/<session-slug>/` | — | titles/index if extractable |

**Pass A:** metadata/chapters from `harvested-links.json` (`kind: deck`).  
**Pass B:** on-screen URLs merged after early vision sheets.
